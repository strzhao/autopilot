#!/usr/bin/env bash
# R_ORACLE: 验证 lib.sh snapshot_oracle_regened 函数 + stop-hook §8.5.2 守卫契约
# 红队测试 — 仅基于设计契约编写，不读取蓝队新写实现（不读 snapshot_oracle_regened
#            函数体、不读 stop-hook §8.5.2 实现段）。
#
# 覆盖契约点（设计文档逐条断言）：
#   函数 snapshot_oracle_regened（三态退出码 + 双信号 stdout）：
#     路径1 tainted-deletion: 快照文件被删（rm/git rm）→ rc!=0（期望2）+ stdout 含 ORACLE + 列文件
#     路径2 tainted-modify:   快照文件被改 → rc!=0（期望2）+ stdout 含 ORACLE
#     路径3 clean:            仅源码改、无快照改动 → rc==0 + stdout 不含 ORACLE / PASS
#     路径4 n/a 自门控:       仓库无快照类文件 → rc==1 + stdout 不含 ORACLE（不误报）
#   双信号判定（与 tamper 一致）：
#     tainted = (rc==2) OR (stdout 含 "ORACLE")
#   §8.5.2 守卫：
#     tainted → block + 注入确定性 prompt（含重录文件清单 + "依赖快照的 T1.5 谓词不得 PASS"）
#     n/a（rc==1）→ 不触发
#
# 信号定义（设计契约）：
#   快照/baseline 文件类（git diff HEAD vs worktree 命中即 tainted）：
#     __Snapshots__/*                       （jest/snapshot）
#     __snapshots__/*/*.snap                （jest ESM 嵌套）
#     playwright 快照目录 *.png|txt|yaml    （playwright 定位器/视觉快照）
#   退出码：
#     0 = clean（无快照重录）
#     2 = tainted（检测到快照重录）
#     1 = n/a（项目无快照类文件，自门控 no-op）
#   stdout 文风（参照 TAMPER(modified): <path>）：预期形如 ORACLE-REGHEN(...): <path>
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 优先 git 顶层（对暂存区位置和 target 位置都健壮）；回退到 target 推算路径。
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
    REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
fi
LIB_SH="${REPO_ROOT}/plugins/autopilot/scripts/lib.sh"
STOP_HOOK="${REPO_ROOT}/plugins/autopilot/scripts/stop-hook.sh"

fail() {
    echo "[FAIL] R_ORACLE: ${1}" >&2
    exit 1
}

pass() {
    echo "[PASS] R_ORACLE: ${1}"
}

# 前置
[[ -f "${LIB_SH}" ]] || fail "lib.sh 不存在: ${LIB_SH}"
[[ -f "${STOP_HOOK}" ]] || fail "stop-hook.sh 不存在: ${STOP_HOOK}"

# ── 断言0：函数定义存在性（蓝队 TDD 红灯——此刻未实现必 fail，绝不 skip） ───────
if ! grep -qE '^snapshot_oracle_regened\(\)|^function snapshot_oracle_regened' "${LIB_SH}"; then
    fail "snapshot_oracle_regened() 函数未定义于 lib.sh（设计契约要求新增此函数）"
fi
pass "snapshot_oracle_regened() 函数定义存在"

# ── helper：subshell 中 source lib.sh 后调用函数 ────────────────────────────────
# snapshot_oracle_regened 设计为无参（依赖 git 上下文），在调用方 cwd（临时仓库）执行。
invoke_oracle() {
    local cwd="${1}"
    bash -c "
        set -uo pipefail
        export AUTOPILOT_TEST_MODE=1
        export AUTOPILOT_DISABLE_MAIN=1
        cd '${cwd}'
        source '${LIB_SH}' 2>/dev/null || true
        snapshot_oracle_regened
    "
}

# ── helper：构造临时 git 仓库（符合真实场景；函数实现可能依赖 git 上下文） ─────
mk_repo() {
    local d
    d="$(mktemp -d)"
    git -C "${d}" init -q
    git -C "${d}" config user.email "test@test.com"
    git -C "${d}" config user.name "Test"
    printf '%s' "${d}"
}

CLEANUP_DIRS=()
cleanup() {
    local d
    for d in "${CLEANUP_DIRS[@]}"; do
        rm -rf "${d}"
    done
}
trap cleanup EXIT

# ── 路径1 tainted-deletion：快照文件被删 → rc!=0（期望2）+ stdout 含 ORACLE ─────

R1="$(mk_repo)"; CLEANUP_DIRS+=("${R1}")
# jest 风格快照（__Snapshots__ 大写 S，常见于 .net/jest-snapshot-tools）
mkdir -p "${R1}/__Snapshots__"
SNAP1="${R1}/__Snapshots__/Foo.test.snap.png"
printf 'PNG_BLOB_v1\n' > "${SNAP1}"
git -C "${R1}" add -A
git -C "${R1}" commit -q -m "baseline snapshot"

# 删除式重录（rm 后无 commit → worktree 与 HEAD diff）
rm -f "${SNAP1}"

out1=$(invoke_oracle "${R1}") ; rc1=$?

# 路径1.P1：双信号之一成立（rc==2 或 stdout 含 ORACLE）
if [[ ${rc1} -eq 0 ]] && ! echo "${out1}" | grep -q "ORACLE"; then
    fail "路径1 tainted-deletion: 快照删除后 rc=${rc1} 且 stdout 未含 'ORACLE'，实际='${out1}'"
fi
# 路径1.P1：强断言 rc!=0（契约: tainted=2）
if [[ ${rc1} -eq 0 ]]; then
    fail "路径1 tainted-deletion: rc 应 !=0（期望 2），实际 rc=${rc1}"
fi
# 路径1.P1：stdout 须含 ORACLE（双信号之一）
if ! echo "${out1}" | grep -q "ORACLE"; then
    fail "路径1 tainted-deletion: stdout 应含 'ORACLE'，实际='${out1}'"
fi
# 路径1.P1：stdout 须列出被重录文件名（设计契约：列出被重录文件清单）
if ! echo "${out1}" | grep -q "Foo.test.snap.png"; then
    fail "路径1 tainted-deletion: stdout 应列出被重录文件名 'Foo.test.snap.png'，实际='${out1}'"
fi
# 路径1.P2：tainted 时 stdout 不含 PASS / 通过证据（文风对齐 tamper 场景4.P2）
if echo "${out1}" | grep -qi "PASS"; then
    fail "路径1 tainted-deletion: tainted 输出不应含 'PASS'，实际='${out1}'"
fi
pass "路径1 tainted-deletion: 快照删除 → rc!=0 + stdout 含 ORACLE + 列出文件 + 不含 PASS"

# ── 路径2 tainted-modify：快照文件被改 → rc!=0（期望2）+ stdout 含 ORACLE ────────

R2="$(mk_repo)"; CLEANUP_DIRS+=("${R2}")
# jest ESM 嵌套快照目录（__snapshots__ 小写 s，带 .snap 后缀）
mkdir -p "${R2}/src/__snapshots__"
SNAP2="${R2}/src/__snapshots__/bar.test.js.snap"
printf 'exports[`bar`] = `v1`;\n' > "${SNAP2}"
git -C "${R2}" add -A
git -C "${R2}" commit -q -m "baseline jest snapshot"

# 修改式重录（内容变化，未 commit）
printf 'exports[`bar`] = `v2_REGEN`;\n' > "${SNAP2}"

out2=$(invoke_oracle "${R2}") ; rc2=$?

# 路径2.P1：rc!=0（期望2）
if [[ ${rc2} -eq 0 ]]; then
    fail "路径2 tainted-modify: 快照被改后 rc 应 !=0（期望 2），实际 rc=${rc2}"
fi
# 路径2.P1：stdout 须含 ORACLE（双信号之一）
if ! echo "${out2}" | grep -q "ORACLE"; then
    fail "路径2 tainted-modify: stdout 应含 'ORACLE'，实际='${out2}'"
fi
# 路径2.P1：rc==2 时也判 tainted（双信号）
if [[ ${rc2} -eq 2 ]]; then
    :
else
    # 非 0 非 2 仍可接受，只要 stdout 含 ORACLE（双信号）——但 rc==0 是 clean，已在上面拦截
    if ! echo "${out2}" | grep -q "ORACLE"; then
        fail "路径2 tainted-modify: rc=${rc2} 非 2 且 stdout 无 ORACLE，双信号均不成立，实际='${out2}'"
    fi
fi
pass "路径2 tainted-modify: 快照内容改 → rc!=0 + stdout 含 ORACLE"

# ── 路径3 clean：仅源码改、无快照改动 → rc==0 + stdout 不含 ORACLE ──────────────

R3="$(mk_repo)"; CLEANUP_DIRS+=("${R3}")
# 项目里「有」快照目录（排除 n/a 分支），但本轮未改它们
mkdir -p "${R3}/__Snapshots__"
printf 'exports[`unchanged`] = `v1`;\n' > "${R3}/__Snapshots__/X.test.js.snap"
SRC3="${R3}/src/lib.ts"
mkdir -p "${R3}/src"
printf 'export const v = 1;\n' > "${SRC3}"
git -C "${R3}" add -A
git -C "${R3}" commit -q -m "baseline with snapshot dir"

# 仅改源码（不动快照）
printf 'export const v = 2;\n' > "${SRC3}"

out3=$(invoke_oracle "${R3}") ; rc3=$?

# 路径3.P1：rc==0（clean）
if [[ ${rc3} -ne 0 ]]; then
    fail "路径3 clean: 仅源码改、快照未动时 rc 应 ==0（clean），实际 rc=${rc3}，stdout='${out3}'"
fi
# 路径3.P1：stdout 不含 ORACLE（不误报）
if echo "${out3}" | grep -q "ORACLE"; then
    fail "路径3 clean: stdout 不应含 'ORACLE'，实际='${out3}'"
fi
# 路径3.P2：clean 时也不应冒出 PASS（设计契约：clean/n/a 时不含 ORACLE 也不含 PASS）
if echo "${out3}" | grep -qi "PASS"; then
    fail "路径3 clean: stdout 不应含 'PASS'，实际='${out3}'"
fi
pass "路径3 clean: 仅源码改、快照未动 → rc==0 + stdout 不含 ORACLE/PASS"

# ── 路径4 n/a 自门控：仓库无快照类文件 → rc==1 + stdout 不含 ORACLE（不误报） ───

R4="$(mk_repo)"; CLEANUP_DIRS+=("${R4}")
# 纯源码项目：无 __Snapshots__ / __snapshots__ / playwright 快照目录
mkdir -p "${R4}/src"
SRC4="${R4}/src/app.swift"
printf 'func f() {}\n' > "${SRC4}"
git -C "${R4}" add -A
git -C "${R4}" commit -q -m "pure source project"

# 改源码（触发 git diff，但无快照类文件可命中）
printf 'func f() { /* changed */ }\n' > "${SRC4}"

out4=$(invoke_oracle "${R4}") ; rc4=$?

# 路径4.P1：rc==1（n/a 自门控）
if [[ ${rc4} -ne 1 ]]; then
    fail "路径4 n/a 自门控: 仓库无快照类文件时 rc 应 ==1（n/a），实际 rc=${rc4}，stdout='${out4}'"
fi
# 路径4.P1：stdout 不含 ORACLE（不误报）
if echo "${out4}" | grep -q "ORACLE"; then
    fail "路径4 n/a 自门控: stdout 不应含 'ORACLE'（不误报），实际='${out4}'"
fi
# 路径4.P1：stdout 不含 PASS（设计契约：clean/n/a 时不含 PASS）
if echo "${out4}" | grep -qi "PASS"; then
    fail "路径4 n/a 自门控: stdout 不应含 'PASS'，实际='${out4}'"
fi
pass "路径4 n/a 自门控: 无快照类文件 → rc==1 + 不误报 ORACLE/PASS"

# ── 路径5 tainted playwright 快照目录（覆盖第三类快照信号） ─────────────────────
# 设计契约信号：playwright 快照目录 *.png|txt|yaml（视觉/定位器快照）

R5="$(mk_repo)"; CLEANUP_DIRS+=("${R5}")
# playwright 视觉快照目录（典型: tests/visual/*.png + 定位器 *.yaml）
mkdir -p "${R5}/tests/visual"
SNAP5_PNG="${R5}/tests/visual/home.png"
printf 'PNG_PIXELS_v1\n' > "${SNAP5_PNG}"
git -C "${R5}" add -A
git -C "${R5}" commit -q -m "playwright baseline"

# 视觉快照重录
printf 'PNG_PIXELS_v2_REGEN\n' > "${SNAP5_PNG}"

out5=$(invoke_oracle "${R5}") ; rc5=$?

# 路径5.P1：rc!=0
if [[ ${rc5} -eq 0 ]]; then
    fail "路径5 playwright 视觉快照: 快照被改后 rc 应 !=0（期望 2），实际 rc=${rc5}"
fi
# 路径5.P1：stdout 含 ORACLE（双信号）
if ! echo "${out5}" | grep -q "ORACLE"; then
    fail "路径5 playwright 视觉快照: stdout 应含 'ORACLE'，实际='${out5}'"
fi
# 路径5.P1：列出被重录文件
if ! echo "${out5}" | grep -q "home.png"; then
    fail "路径5 playwright 视觉快照: stdout 应列出 'home.png'，实际='${out5}'"
fi
pass "路径5 playwright 视觉快照: 重录 → rc!=0 + stdout 含 ORACLE + 列出文件"

# ── §8.5.2 集成：stop-hook 守卫在 phase→qa 时检测到 oracle 重录 → block ─────────
# INTEGRATION: 留 QA 真机判定
#
# 说明：§8.5.2 守卫在 stop-hook.sh 中作为 bash 分支块内联执行（参照 §8.5.1
#       的结构：if rc==2 || stdout 含 ORACLE → jq 注入 decision:block + exit 0），
#       与 stop-hook 的 PHASE/TASK_DIR 上下文/状态文件读取强耦合，单元级不易隔离调用
#       （需构造完整 stop-hook 输入 JSON + state.md + .acceptance-lock + phase=qa）。
#       本集成点交由 QA Tier 1.5 真机判定覆盖：
#         (a) phase 转 qa、存在快照重录 fixture 时，stop-hook 输出 JSON
#             decision=="block"
#         (b) block reason 含被重录文件清单（stdout 中的路径）
#         (c) block reason 含确定性字面量"依赖快照的 T1.5 谓词不得 PASS，须独立 oracle"
#         (d) n/a 场景（rc==1）stop-hook 不触发 block（自门控透传）
#       不 soft-skip：上面路径1-5 已对 snapshot_oracle_regened 函数做完整断言，
#       §8.5.2 的 block 注入逻辑文风与 §8.5.1 同构（设计契约明确），QA 真机复跑即可。
#
#       但此处保留一条「成文存在性」强断言——证明蓝队确实把 §8.5.2 落到了 stop-hook
#       里（防止蓝队只写函数不接守卫，这是设计契约的两半必须同时落地）：

if ! grep -qE 'snapshot_oracle_regened' "${STOP_HOOK}"; then
    fail "§8.5.2 集成: stop-hook.sh 未引用 snapshot_oracle_regened（设计契约要求 §8.5.2 守卫调用此函数）"
fi
# §8.5.2 的 block reason 应含确定性字面量（设计契约原文：须独立 oracle）
if ! grep -qE '独立 oracle|独立oracle' "${STOP_HOOK}"; then
    fail "§8.5.2 集成: stop-hook.sh 未含 '须独立 oracle' 确定性字面量（设计契约要求 block prompt 含此字面量）"
fi
pass "§8.5.2 集成: stop-hook 引用 snapshot_oracle_regened + 含 '须独立 oracle' 字面量"

echo "[OK ] R_ORACLE oracle-snapshot-taint-guard — 全部断言通过（路径1-5 函数契约 + §8.5.2 成文接线断言）"
exit 0
