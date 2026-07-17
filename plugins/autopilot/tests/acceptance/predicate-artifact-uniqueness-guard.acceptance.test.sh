#!/usr/bin/env bash
# R_PRED_DUP: artifact 内容去重守卫验收测试（守卫③）
# 红队测试 — 仅基于设计文档（黑盒契约）编写，铁律：
#   ❌ 绝不读取蓝队本次改动的实现文件（lib.sh 新函数 validate_predicate_artifact_uniqueness /
#      compute_file_hash / stop-hook §5.7 接线 / scenario-generator-prompt.md / SKILL.md），
#      不读 state.md 的 ## 实现计划 区域。
#   ✅ 信号串（PRED-ARTIFACT-DUP）/ 函数名（validate_predicate_artifact_uniqueness）/
#      退出码（0/1/2）/ 守卫③边界 —— 全部从 ## 契约规约 C2/C6 读字面量。
#
# 守卫机制（设计契约 C2/C6，黑盒）：
#   lib.sh::validate_predicate_artifact_uniqueness <state_file>
#     - 口径（C6）：artifact 路径不同但内容（MD5）相同 → 违规；
#       路径相同（显式共用命令输出）→ 允许
#     - 跨平台哈希：lib.sh::compute_file_hash（md5sum / md5 -q 双探测，一处真相）
#     - 自门控：无谓词/全无 artifact → rc1；全唯一或显式共用 → rc0；
#       路径不同 ∧ MD5 相同 → rc2 + stdout 含 PRED-ARTIFACT-DUP: <id1> <id2> <md5>
#   stop-hook.sh §5.7：gate=review-accept ∧ phase=qa 时调此函数，
#     rc==2 → 清 gate + block JSON（reason 含 "不耗 max_retries"）+ exit 0
#
# 覆盖验收场景（SSOT，逐条覆盖，三变体）：
#   场景3.A dup-guard.diff-path-same-md5-blocked   2 谓词不同路径同 MD5 → rc2 + PRED-ARTIFACT-DUP（iina 7 图复制实证）
#   场景3.B dup-guard.same-path-allowed            2 谓词同路径（显式共用）→ rc0
#   场景3.C dup-guard.diff-path-diff-md5-allowed   2 谓词不同路径不同内容 → rc0（kill「漏算 MD5 直接判路径」no-op mutation）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# REPO_ROOT 稳健探测：从 SCRIPT_DIR 往上找 .claude-plugin/marketplace.json
_find_repo_root() {
    local d="$SCRIPT_DIR"
    while [[ -n "$d" && "$d" != "/" ]]; do
        if [[ -f "$d/.claude-plugin/marketplace.json" ]]; then
            echo "$d"; return 0
        fi
        d=$(dirname "$d")
    done
    return 1
}
REPO_ROOT="$(_find_repo_root)" || {
    echo "[FAIL] R_PRED_DUP: 无法定位 REPO_ROOT（缺 .claude-plugin/marketplace.json）" >&2
    exit 1
}

LIB_SH="${REPO_ROOT}/plugins/autopilot/scripts/lib.sh"
STOP_HOOK="${REPO_ROOT}/plugins/autopilot/scripts/stop-hook.sh"

# ── 计数器 ───────────────────────────────────────────────────────────────────
PASSED=0
FAILED=0
FAILURES=()

_log_pass() {
    local id="$1"; shift
    echo "✓ $id $*"
    PASSED=$((PASSED + 1))
}

_log_fail() {
    local id="$1"; shift
    echo "✗ $id $*" >&2
    FAILED=$((FAILED + 1))
    FAILURES+=("$id $*")
}

# ── 前置：关键文件存在 ───────────────────────────────────────────────────────
[[ -f "$LIB_SH" ]] || { echo "[FAIL] R_PRED_DUP: lib.sh 不存在: $LIB_SH" >&2; exit 1; }
[[ -f "$STOP_HOOK" ]] || { echo "[FAIL] R_PRED_DUP: stop-hook.sh 不存在: $STOP_HOOK" >&2; exit 1; }
[[ -d "$REPO_ROOT/.git" ]] || {
    echo "[FAIL] R_PRED_DUP: REPO_ROOT 非 git 仓库: $REPO_ROOT" >&2
    exit 1
}

echo "=========================================="
echo " R_PRED_DUP artifact 内容去重守卫验收（设计契约黑盒）"
echo "=========================================="

# ─────────────────────────────────────────────────────────────────────────────
# 前置断言：函数定义 + §5.7 接线 + compute_file_hash helper（TDD 红灯——蓝队未实现必 fail，绝不 skip）
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- 前置：函数定义 + §5.7 接线 + compute_file_hash helper ---"

if grep -qE '^validate_predicate_artifact_uniqueness\(\)|^function validate_predicate_artifact_uniqueness' "$LIB_SH"; then
    _log_pass "PRE.uniqueness" "validate_predicate_artifact_uniqueness() 函数定义存在于 lib.sh"
else
    _log_fail "PRE.uniqueness" "validate_predicate_artifact_uniqueness() 函数未定义于 lib.sh（设计契约 C2 要求新增此函数）"
fi

if grep -qE 'validate_predicate_artifact_uniqueness' "$STOP_HOOK"; then
    _log_pass "PRE.wire.uniqueness" "stop-hook.sh 引用 validate_predicate_artifact_uniqueness（§5.7 接线）"
else
    _log_fail "PRE.wire.uniqueness" "stop-hook.sh 未引用 validate_predicate_artifact_uniqueness（§5.7 接线缺失——防只写函数不接守卫）"
fi

if grep -q 'PRED-ARTIFACT-DUP' "$LIB_SH"; then
    _log_pass "PRE.signal" "lib.sh 含 'PRED-ARTIFACT-DUP' 字面量（违规信号串，契约 C2）"
else
    _log_fail "PRE.signal" "lib.sh 未含 'PRED-ARTIFACT-DUP' 字面量（违规信号串缺失，契约 C2）"
fi

# compute_file_hash helper（C6 契约：跨平台哈希一处真相）
if grep -qE '^compute_file_hash\(\)|^function compute_file_hash' "$LIB_SH"; then
    _log_pass "PRE.hash" "compute_file_hash() 函数定义存在于 lib.sh（跨平台哈希封装，契约 C6）"
else
    _log_fail "PRE.hash" "compute_file_hash() 函数未定义于 lib.sh（设计契约 C6 要求新增跨平台哈希 helper）"
fi

# ── helper：subshell 中 source lib.sh 后调用 validate 函数 ────────────────────
# 范式照搬 predicate-driver-guard.acceptance.test.sh:invoke_validate_driver
invoke_validate_uniqueness() {
    local state_file="${1}"
    bash -c "
        set -uo pipefail
        export AUTOPILOT_TEST_MODE=1
        export AUTOPILOT_DISABLE_MAIN=1
        source '${LIB_SH}' 2>/dev/null || true
        validate_predicate_artifact_uniqueness '${state_file}'
    "
}

# 写 mock state.md（含 ## 验收场景 区域，fullwidth ｜ 分隔谓词）
# 范式照搬 predicate-driver-guard:write_mock_state
write_mock_state() {
    local out="$1" scenarios="$2"
    cat > "$out" <<EOF_MD
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
task_dir: ""
session_id: ""
started_at: "2026-07-17T00:00:00Z"
contract_required: false
html_review: false
---

## 目标
mock artifact uniqueness guard test

## 验收场景

${scenarios}
EOF_MD
}

# ── 临时目录 + cleanup ───────────────────────────────────────────────────────
TMP_DIR="$(mktemp -d)"
CLEANUP_DIRS=("$TMP_DIR")
trap 'for d in "${CLEANUP_DIRS[@]}"; do rm -rf "$d"; done' EXIT

# ═════════════════════════════════════════════════════════════════════════════
# 场景3.A dup-guard.diff-path-same-md5-blocked [det-machine]:
#   assert: validate_predicate_artifact_uniqueness rc2 ∧ stdout 含 PRED-ARTIFACT-DUP
#   构造：2 谓词 artifact 指向不同路径但内容相同（cp 同一文件到两路径）
#   反 tautological：违规断言同时断 rc==2 和信号串；下游 3.B/3.C 配 rc0 反例
#   治 iina dogfood 实证：7 个不同路径 .png MD5 全同 dce6b4d0... 冒充独立 artifact
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- 场景3.A dup-guard.diff-path-same-md5-blocked: 不同路径同 MD5 → rc2 + PRED-ARTIFACT-DUP ---"

# 构造：同一源文件 cp 到两个不同路径（保证 MD5 相同）
ART_SRC_A="${TMP_DIR}/source-a.png"
printf 'identical-fake-screenshot-content-iina\n' > "$ART_SRC_A"
ART_DUP_PATH1="${TMP_DIR}/shot-1.png"
ART_DUP_PATH2="${TMP_DIR}/shot-2.png"
cp "$ART_SRC_A" "$ART_DUP_PATH1"
cp "$ART_SRC_A" "$ART_DUP_PATH2"

# 确认 MD5 相同（测试自检，非被测函数——用系统工具直接算，不依赖 lib.sh 实现）
HASH_CHECK=$(command -v md5sum >/dev/null && md5sum "$ART_DUP_PATH1" "$ART_DUP_PATH2" | awk '{print $1}' | sort -u | wc -l \
    || md5 -q "$ART_DUP_PATH1" "$ART_DUP_PATH2" 2>/dev/null | awk '{print $NF}' | sort -u | wc -l)
# macOS md5 -q 只收一个文件，逐个算
if [[ "$HASH_CHECK" -ne 1 ]]; then
    H1=$(command -v md5sum >/dev/null && md5sum "$ART_DUP_PATH1" | awk '{print $1}' || md5 -q "$ART_DUP_PATH1")
    H2=$(command -v md5sum >/dev/null && md5sum "$ART_DUP_PATH2" | awk '{print $1}' || md5 -q "$ART_DUP_PATH2")
    if [[ "$H1" != "$H2" ]]; then
        echo "[WARN] R_PRED_DUP: 测试脚手架自检 MD5 不一致（h1=$H1 h2=$H2），但 cp 同源文件理论必相同，继续"
    fi
fi

SC_DUP_DIFF="- **dup-guard.p1 [det-machine]** 场景一 ｜ observe: 截图 ｜ assert: rc==0 ｜ driver: bash:diff ｜ artifact: ${ART_DUP_PATH1}
- **dup-guard.p2 [det-machine]** 场景二 ｜ observe: 截图 ｜ assert: rc==0 ｜ driver: bash:diff ｜ artifact: ${ART_DUP_PATH2}"
STATE_DUP_DIFF="${TMP_DIR}/state-dup-diff.md"
write_mock_state "$STATE_DUP_DIFF" "$SC_DUP_DIFF"

out_dup=$(invoke_validate_uniqueness "$STATE_DUP_DIFF"); rc_dup=$?

if [[ $rc_dup -eq 2 ]]; then
    _log_pass "dup-guard.diff-path-same-md5-blocked.rc" "validate_predicate_artifact_uniqueness rc2（不同路径同 MD5 违规）"
else
    _log_fail "dup-guard.diff-path-same-md5-blocked.rc" "validate_predicate_artifact_uniqueness 期望 rc2，实际 rc=${rc_dup}，stdout='${out_dup}'"
fi

if echo "$out_dup" | grep -q 'PRED-ARTIFACT-DUP'; then
    _log_pass "dup-guard.diff-path-same-md5-blocked.signal" "stdout 含 PRED-ARTIFACT-DUP（双信号之一）"
else
    _log_fail "dup-guard.diff-path-same-md5-blocked.signal" "stdout 应含 PRED-ARTIFACT-DUP，实际='${out_dup}'"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 场景3.B dup-guard.same-path-allowed [det-machine]:
#   assert: validate_predicate_artifact_uniqueness rc0（同路径显式共用放行）
#   构造：2 谓词 artifact 指向同一 .out 路径（多谓词显式共用同一 xcodebuild 输出）
#   反 tautological：此为场景3.A 违规的反例（rc0），守卫恒输出信号串时反例能 kill no-op mutation
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- 场景3.B dup-guard.same-path-allowed: 同路径（显式共用）→ rc0 放行 ---"

ART_SHARED="${TMP_DIR}/xcodebuild-shared.out"
printf 'shared xcodebuild test output\n' > "$ART_SHARED"

SC_SAME="- **dup-guard.shared1 [det-machine]** 测试一 ｜ observe: xcodebuild ｜ assert: PASS ｜ driver: bash:xcodebuild ｜ artifact: ${ART_SHARED}
- **dup-guard.shared2 [det-machine]** 测试二 ｜ observe: xcodebuild ｜ assert: PASS ｜ driver: bash:xcodebuild ｜ artifact: ${ART_SHARED}"
STATE_SAME="${TMP_DIR}/state-same.md"
write_mock_state "$STATE_SAME" "$SC_SAME"

out_same=$(invoke_validate_uniqueness "$STATE_SAME"); rc_same=$?

if [[ $rc_same -eq 0 ]]; then
    _log_pass "dup-guard.same-path-allowed.rc" "validate_predicate_artifact_uniqueness rc0（同路径显式共用放行）"
else
    _log_fail "dup-guard.same-path-allowed.rc" "validate_predicate_artifact_uniqueness 同路径期望 rc0，实际 rc=${rc_same}，stdout='${out_same}'"
fi

if echo "$out_same" | grep -q 'PRED-ARTIFACT-DUP'; then
    _log_fail "dup-guard.same-path-allowed.no-signal" "同路径不应输出 PRED-ARTIFACT-DUP（反例 kill 恒输出信号串 mutation），实际='${out_same}'"
else
    _log_pass "dup-guard.same-path-allowed.no-signal" "同路径 stdout 不含 PRED-ARTIFACT-DUP（反例守恒）"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 场景3.C dup-guard.diff-path-diff-md5-allowed [det-machine]:
#   assert: validate_predicate_artifact_uniqueness rc0（不同路径不同内容独立产物放行）
#   构造：2 谓词 artifact 指向不同路径且内容不同
#   关键 mutation kill：若蓝队实现「漏算 MD5 直接判路径不同=独立」的 no-op mutation，
#     此变体能 kill——场景3.A 已证路径不同+内容相同应 rc2，此变体证路径不同+内容不同应 rc0，
#     两变体联合锁定「必须比较内容（MD5）」的契约 C6
#   反 tautological：此为场景3.A 违规的第二反例（rc0），与 3.B 共同构成「内容比较」三角验证
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- 场景3.C dup-guard.diff-path-diff-md5-allowed: 不同路径不同内容 → rc0 放行（kill 漏算 MD5 mutation） ---"

ART_DIFF1="${TMP_DIR}/independent-1.out"
ART_DIFF2="${TMP_DIR}/independent-2.out"
printf 'first independent artifact content\n' > "$ART_DIFF1"
printf 'second independent artifact content - different from first\n' > "$ART_DIFF2"

SC_DIFF="- **dup-guard.indep1 [det-machine]** 场景一 ｜ observe: 独立命令 ｜ assert: rc==0 ｜ driver: bash:cmd1 ｜ artifact: ${ART_DIFF1}
- **dup-guard.indep2 [det-machine]** 场景二 ｜ observe: 独立命令 ｜ assert: rc==0 ｜ driver: bash:cmd2 ｜ artifact: ${ART_DIFF2}"
STATE_DIFF="${TMP_DIR}/state-diff.md"
write_mock_state "$STATE_DIFF" "$SC_DIFF"

out_diff=$(invoke_validate_uniqueness "$STATE_DIFF"); rc_diff=$?

if [[ $rc_diff -eq 0 ]]; then
    _log_pass "dup-guard.diff-path-diff-md5-allowed.rc" "validate_predicate_artifact_uniqueness rc0（不同路径不同内容独立产物放行）"
else
    _log_fail "dup-guard.diff-path-diff-md5-allowed.rc" "validate_predicate_artifact_uniqueness 不同路径不同内容期望 rc0，实际 rc=${rc_diff}，stdout='${out_diff}'"
fi

if echo "$out_diff" | grep -q 'PRED-ARTIFACT-DUP'; then
    _log_fail "dup-guard.diff-path-diff-md5-allowed.no-signal" "独立产物不应输出 PRED-ARTIFACT-DUP（反例 kill 恒输出信号串 mutation），实际='${out_diff}'"
else
    _log_pass "dup-guard.diff-path-diff-md5-allowed.no-signal" "独立产物 stdout 不含 PRED-ARTIFACT-DUP（反例守恒）"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 三变体联合 mutation kill 断言（场景3.A + 3.B + 3.C 语义闭环）：
#   - 3.A rc2 ∧ 3.B rc0 ∧ 3.C rc0 同时成立 → 锁定「路径不同 ∧ 内容相同」为唯一违规条件
#   - kill 两种 no-op mutation：
#     ① 「漏算 MD5 直接判路径不同=违规」→ 3.C 路径不同但 rc0 kill 此 mutation
#     ② 「路径相同=违规」→ 3.B 路径相同但 rc0 kill 此 mutation
#   此断言是三元组语义闭环的元断言，仅在三个子断言全 PASS 时才 PASS
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- 场景3 mutation kill 元断言（三变体联合锁定「路径不同 ∧ 内容相同」唯一违规条件） ---"

if [[ $rc_dup -eq 2 && $rc_same -eq 0 && $rc_diff -eq 0 ]]; then
    _log_pass "dup-guard.triple-mutation-kill" "三变体联合语义闭环（3.A rc2 ∧ 3.B rc0 ∧ 3.C rc0）→ kill 漏算 MD5 + 路径相同=违规两种 no-op mutation"
else
    _log_fail "dup-guard.triple-mutation-kill" "三变体未联合闭环（3.A rc=${rc_dup} / 3.B rc=${rc_same} / 3.C rc=${rc_diff}）→ mutation 未被 kill"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 汇总
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo " R_PRED_DUP 汇总: PASSED=$PASSED  FAILED=$FAILED"
echo "=========================================="
echo ""
echo "覆盖的验收场景/谓词：场景3 dup-guard.diff-path-same-md5-blocked / dup-guard.same-path-allowed / dup-guard.diff-path-diff-md5-allowed"

if [[ $FAILED -gt 0 ]]; then
    echo ""
    echo "失败明细："
    for f in "${FAILURES[@]}"; do
        echo "   - $f"
    done
    echo ""
    echo "FAIL"
    exit 1
fi

echo "PASS"
exit 0
