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

# ── 路径6 playwright 默认目录 <spec>-snapshots/（N1 修复覆盖盲区）─────────────────
# v3.48.0 初版 snapshot_re 漏检 Playwright 默认目录 tests/<spec>.spec.ts-snapshots/，
# 独立 claude -p 验证发现 N1：自门控把漏检静默化为 n/a（无信号）。v3.48.1 snapshot_re
# 加 [^/]*-snapshots/ 条目覆盖。本路径用 Playwright 真实默认目录验证（防 fixture 掩盖）。
R6_REPO="$(mk_repo)"; CLEANUP_DIRS+=("${R6_REPO}")
mkdir -p "${R6_REPO}/tests/foo.spec.ts-snapshots"
SNAP6="${R6_REPO}/tests/foo.spec.ts-snapshots/home-chromium.png"
printf 'PW_DEFAULT_v1\n' > "${SNAP6}"
git -C "${R6_REPO}" add -A
git -C "${R6_REPO}" commit -q -m "playwright default dir baseline"
printf 'PW_DEFAULT_v2_REGEN\n' > "${SNAP6}"   # 重录
out6=$(invoke_oracle "${R6_REPO}") ; rc6=$?
if [[ ${rc6} -eq 0 ]]; then
    fail "路径6 playwright 默认目录: <spec>-snapshots/ 快照被改后 rc 应 !=0，实际 rc=${rc6}（N1 盲区回归）"
fi
if ! echo "${out6}" | grep -q "ORACLE"; then
    fail "路径6 playwright 默认目录: stdout 应含 'ORACLE'，实际='${out6}'（N1 盲区回归）"
fi
pass "路径6 playwright 默认目录 <spec>-snapshots/: N1 修复后检出（rc!=0 + ORACLE）"

# ── §8.5.2 集成：接线 grep + 端到端行为（N2 加固，闭合 INTEGRATION）──────────────
# 接线存在性（防"只写函数不接守卫"）：
if ! grep -qE 'snapshot_oracle_regened' "${STOP_HOOK}"; then
    fail "§8.5.2 接线: stop-hook.sh 未引用 snapshot_oracle_regened（设计契约要求 §8.5.2 守卫调用此函数）"
fi
if ! grep -qE '独立 oracle|独立oracle' "${STOP_HOOK}"; then
    fail "§8.5.2 接线: stop-hook.sh 未含 '须独立 oracle' 确定性字面量（block prompt 契约）"
fi
pass "§8.5.2 接线: stop-hook 引用 snapshot_oracle_regened + 含 '须独立 oracle' 字面量"

# 端到端行为（N2 加固：v3.48.0 初版只有 grep 接线断言，独立 claude -p 指出 grep 可命中
# 注释、无法证明真在 implement→qa 触发 block。v3.48.1 构造 tainted worktree + state.md
# (phase=qa) 直接跑 stop-hook，断言 decision=="block"）。
PW_REPO="$(mk_repo)"; CLEANUP_DIRS+=("${PW_REPO}")
PW_SLUG="20260702-oracle-behavior"
PW_TASK_DIR="${PW_REPO}/.autopilot/runtime/requirements/${PW_SLUG}"
mkdir -p "${PW_TASK_DIR}"
printf '%s\n' "${PW_SLUG}" > "${PW_REPO}/.autopilot/runtime/active.ptr"
cat > "${PW_TASK_DIR}/state.md" <<EOF_STATE_PW
---
active: true
phase: "qa"
gate: ""
iteration: 1
max_iterations: 30
max_retries: 3
retry_count: 0
mode: ""
plan_mode: ""
fast_mode:
brief_file: ""
next_task: ""
auto_approve: false
knowledge_extracted: ""
task_dir: "${PW_TASK_DIR}"
session_id: "pw-behavior-session"
started_at: "2026-07-02T00:00:00Z"
contract_required: false
html_review: false
---

## 目标
pw behavior
EOF_STATE_PW
# tainted：commit 快照 + 删（删除式重录）
mkdir -p "${PW_REPO}/__Snapshots__"
printf 'PW_v1\n' > "${PW_REPO}/__Snapshots__/behavior.png"
git -C "${PW_REPO}" add -A && git -C "${PW_REPO}" commit -q -m "baseline"
rm -f "${PW_REPO}/__Snapshots__/behavior.png"
# 跑 stop-hook（stdin JSON：cwd + session_id 匹配 state）
stop_out=$(printf '{"cwd":"%s","session_id":"pw-behavior-session","transcript_path":""}' "${PW_REPO}" \
    | bash "${STOP_HOOK}" 2>&1)
if ! echo "${stop_out}" | grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    fail "§8.5.2 行为: tainted worktree + phase=qa 跑 stop-hook 应输出 decision:block，实际='${stop_out}'"
fi
if ! echo "${stop_out}" | grep -q '独立 oracle'; then
    fail "§8.5.2 行为: block reason 应含 '独立 oracle'，实际='${stop_out}'"
fi
pass "§8.5.2 行为: tainted worktree + phase=qa → stop-hook 输出 decision:block + 须独立 oracle（N2 端到端闭合）"

echo "[OK ] R_ORACLE oracle-snapshot-taint-guard — 全部断言通过（路径1-6 函数契约 + §8.5.2 接线 + 端到端行为）"
exit 0
