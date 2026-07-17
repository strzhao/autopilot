#!/usr/bin/env bash
# R_PRED_COV_GUARD: visual-residue 谓词须有 artifact 守卫验收测试（守卫②）
# 红队测试 — 仅基于设计文档（黑盒契约）编写，铁律：
#   ❌ 绝不读取蓝队本次改动的实现文件（lib.sh 新函数 validate_predicate_coverage /
#      compute_file_hash / stop-hook §5.7 接线 / scenario-generator-prompt.md / SKILL.md），
#      不读 state.md 的 ## 实现计划 区域。
#   ✅ 信号串（PRED-COVERAGE-GAP）/ 函数名（validate_predicate_coverage）/
#      退出码（0/1/2）/ 守卫②口径 —— 全部从 ## 契约规约 C2/C5 读字面量。
#
# 文件名说明：避开既有 predicate-coverage.acceptance.test.sh（v3.51.0 dogfood，
#   plan-reviewer/qa-reviewer 谓词充分性）碰撞，本测试是 v3.57.0 §5.7 谓词守卫②。
#
# 守卫机制（设计契约 C2/C5，黑盒）：
#   lib.sh::validate_predicate_coverage <state_file>
#     - 口径（C5）：有 [visual-residue] channel 的谓词必须有 artifact: 字段
#       （弃 N vs M 散文解析 + 弃泛化所有 channel——只强制留人通道，
#        det-machine/real-process 由 driver 守卫兜底兼容 ACC-GUARD-30）
#     - 自门控：无谓词 → rc1；visual-residue 谓词全有 artifact → rc0；
#       任一 visual-residue 无 artifact → rc2 + stdout 含 PRED-COVERAGE-GAP: <id> 无 artifact
#   stop-hook.sh §5.7：gate=review-accept ∧ phase=qa 时调此函数，
#     rc==2 → 清 gate + block JSON（reason 含 "不耗 max_retries"）+ exit 0
#
# 覆盖验收场景（SSOT，逐条覆盖）：
#   场景2 cov-guard.visual-residue-without-artifact-blocked  [visual-residue] 无 artifact → rc2 + PRED-COVERAGE-GAP
#   场景2 cov-guard.det-machine-without-artifact-allowed     [det-machine] 无 artifact → rc0/rc1（兼容 ACC-GUARD-30）

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
    echo "[FAIL] R_PRED_COV_GUARD: 无法定位 REPO_ROOT（缺 .claude-plugin/marketplace.json）" >&2
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
[[ -f "$LIB_SH" ]] || { echo "[FAIL] R_PRED_COV_GUARD: lib.sh 不存在: $LIB_SH" >&2; exit 1; }
[[ -f "$STOP_HOOK" ]] || { echo "[FAIL] R_PRED_COV_GUARD: stop-hook.sh 不存在: $STOP_HOOK" >&2; exit 1; }
[[ -d "$REPO_ROOT/.git" ]] || {
    echo "[FAIL] R_PRED_COV_GUARD: REPO_ROOT 非 git 仓库: $REPO_ROOT" >&2
    exit 1
}

echo "=========================================="
echo " R_PRED_COV_GUARD visual-residue 谓词须有 artifact 守卫验收（设计契约黑盒）"
echo "=========================================="

# ─────────────────────────────────────────────────────────────────────────────
# 前置断言：函数定义 + §5.7 接线存在性（TDD 红灯——蓝队未实现必 fail，绝不 skip）
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- 前置：函数定义 + §5.7 接线存在性 ---"

if grep -qE '^validate_predicate_coverage\(\)|^function validate_predicate_coverage' "$LIB_SH"; then
    _log_pass "PRE.coverage" "validate_predicate_coverage() 函数定义存在于 lib.sh"
else
    _log_fail "PRE.coverage" "validate_predicate_coverage() 函数未定义于 lib.sh（设计契约 C2 要求新增此函数）"
fi

if grep -qE 'validate_predicate_coverage' "$STOP_HOOK"; then
    _log_pass "PRE.wire.coverage" "stop-hook.sh 引用 validate_predicate_coverage（§5.7 接线）"
else
    _log_fail "PRE.wire.coverage" "stop-hook.sh 未引用 validate_predicate_coverage（§5.7 接线缺失——防只写函数不接守卫）"
fi

if grep -q 'PRED-COVERAGE-GAP' "$LIB_SH"; then
    _log_pass "PRE.signal" "lib.sh 含 'PRED-COVERAGE-GAP' 字面量（违规信号串，契约 C2）"
else
    _log_fail "PRE.signal" "lib.sh 未含 'PRED-COVERAGE-GAP' 字面量（违规信号串缺失，契约 C2）"
fi

# ── helper：subshell 中 source lib.sh 后调用 validate 函数 ────────────────────
# 范式照搬 predicate-driver-guard.acceptance.test.sh:invoke_validate_driver
invoke_validate_coverage() {
    local state_file="${1}"
    bash -c "
        set -uo pipefail
        export AUTOPILOT_TEST_MODE=1
        export AUTOPILOT_DISABLE_MAIN=1
        source '${LIB_SH}' 2>/dev/null || true
        validate_predicate_coverage '${state_file}'
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
mock coverage guard test

## 验收场景

${scenarios}
EOF_MD
}

# ── 临时目录 + cleanup ───────────────────────────────────────────────────────
TMP_DIR="$(mktemp -d)"
CLEANUP_DIRS=("$TMP_DIR")
trap 'for d in "${CLEANUP_DIRS[@]}"; do rm -rf "$d"; done' EXIT

# ═════════════════════════════════════════════════════════════════════════════
# 场景2.A cov-guard.visual-residue-without-artifact-blocked [det-machine]:
#   assert: validate_predicate_coverage rc2 ∧ stdout 含 PRED-COVERAGE-GAP
#   构造：[visual-residue] 谓词无 artifact: 字段（iina dogfood 变种——改标合法 channel 继续逃避）
#   反 tautological：违规断言同时断 rc==2 和信号串；下游 det-machine-without-artifact-allowed 配反例
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- 场景2 cov-guard.visual-residue-without-artifact-blocked: [visual-residue] 无 artifact → rc2 + PRED-COVERAGE-GAP ---"

SC_VR_NO_ART='- **cov-guard.visual-residue-without-artifact-blocked [visual-residue]** 动效流畅 ｜ observe: 截图人眼 ｜ assert: 主观 OK ｜ driver: bash:manual'
STATE_VR_NO_ART="${TMP_DIR}/state-vr-no-art.md"
write_mock_state "$STATE_VR_NO_ART" "$SC_VR_NO_ART"

out_vr=$(invoke_validate_coverage "$STATE_VR_NO_ART"); rc_vr=$?

if [[ $rc_vr -eq 2 ]]; then
    _log_pass "cov-guard.visual-residue-without-artifact-blocked.rc" "validate_predicate_coverage rc2（[visual-residue] 谓词无 artifact 违规）"
else
    _log_fail "cov-guard.visual-residue-without-artifact-blocked.rc" "validate_predicate_coverage 期望 rc2，实际 rc=${rc_vr}，stdout='${out_vr}'"
fi

if echo "$out_vr" | grep -q 'PRED-COVERAGE-GAP'; then
    _log_pass "cov-guard.visual-residue-without-artifact-blocked.signal" "stdout 含 PRED-COVERAGE-GAP（双信号之一）"
else
    _log_fail "cov-guard.visual-residue-without-artifact-blocked.signal" "stdout 应含 PRED-COVERAGE-GAP，实际='${out_vr}'"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 场景2.B cov-guard.det-machine-without-artifact-allowed [det-machine]:
#   assert: validate_predicate_coverage rc0 ∨ rc1（[det-machine] 无 artifact 放行，兼容 ACC-GUARD-30）
#   构造：[det-machine] 谓词无 artifact 字段（旧 task 兼容；driver 守卫兜底）
#   反 tautological：此为场景2.A 违规的反例（rc0/rc1），守卫恒输出信号串时反例能 kill no-op mutation
#   兼容契约：对齐 predicate-driver-guard.acceptance.test.sh ACC-GUARD-30（det-machine 无 driver 也放行）
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- 场景2 cov-guard.det-machine-without-artifact-allowed: [det-machine] 无 artifact → rc0/rc1 放行 ---"

SC_DET_NO_ART='- **cov-guard.det-machine-without-artifact-allowed [det-machine]** AX 断言 ｜ observe: xcodebuild test ｜ assert: isHidden==false ｜ driver: bash:xcodebuild'
STATE_DET_NO_ART="${TMP_DIR}/state-det-no-art.md"
write_mock_state "$STATE_DET_NO_ART" "$SC_DET_NO_ART"

out_det=$(invoke_validate_coverage "$STATE_DET_NO_ART"); rc_det=$?

# 设计 SSOT（C5）：det-machine 由 driver 守卫兜底，coverage 守卫放行 rc0 或 rc1（兼容 ACC-GUARD-30）
if [[ $rc_det -eq 0 ]] || [[ $rc_det -eq 1 ]]; then
    _log_pass "cov-guard.det-machine-without-artifact-allowed.rc" "validate_predicate_coverage rc=${rc_det}（[det-machine] 无 artifact 放行，兼容 ACC-GUARD-30）"
else
    _log_fail "cov-guard.det-machine-without-artifact-allowed.rc" "validate_predicate_coverage [det-machine] 无 artifact 期望 rc0 或 rc1，实际 rc=${rc_det}，stdout='${out_det}'"
fi

if echo "$out_det" | grep -q 'PRED-COVERAGE-GAP'; then
    _log_fail "cov-guard.det-machine-without-artifact-allowed.no-signal" "det-machine 谓词不应输出 PRED-COVERAGE-GAP（反例 kill 恒输出信号串 mutation），实际='${out_det}'"
else
    _log_pass "cov-guard.det-machine-without-artifact-allowed.no-signal" "det-machine 谓词 stdout 不含 PRED-COVERAGE-GAP（反例守恒）"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 汇总
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo " R_PRED_COV_GUARD 汇总: PASSED=$PASSED  FAILED=$FAILED"
echo "=========================================="
echo ""
echo "覆盖的验收场景/谓词：场景2 cov-guard.visual-residue-without-artifact-blocked / cov-guard.det-machine-without-artifact-allowed"

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
