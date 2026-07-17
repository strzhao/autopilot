#!/usr/bin/env bash
# R_PRED_CHAN: 谓词 channel 合法性守卫验收测试（守卫①）
# 红队测试 — 仅基于设计文档（黑盒契约）编写，铁律：
#   ❌ 绝不读取蓝队本次改动的实现文件（lib.sh 新函数 validate_predicate_channels /
#      compute_file_hash / stop-hook §5.7 接线 / scenario-generator-prompt.md / SKILL.md），
#      不读 state.md 的 ## 实现计划 区域。
#   ✅ 信号串（PRED-CHANNEL-ILLEGAL）/ 函数名（validate_predicate_channels）/
#      退出码（0/1/2）/ channel 合法枚举 —— 全部从 ## 契约规约 C2/C4 读字面量，
#      不从实现里 grep 凑断言。
#
# 守卫机制（设计契约 C2/C4，黑盒）：
#   lib.sh::validate_predicate_channels <state_file>
#     - 解析 ## 验收场景 区域每条谓词的 [channel] 标签
#     - 合法集 = {det-machine, real-process, visual-residue}（SSOT: scenario-generator-prompt.md:42）
#     - 自门控：无谓词 → rc1；全合法 → rc0；任一非法（如 human-obs）→ rc2 +
#       stdout 含 PRED-CHANNEL-ILLEGAL: <id> <tag>
#   stop-hook.sh §5.7：gate=review-accept ∧ phase=qa 时调此函数，
#     rc==2 → 清 gate + block JSON（reason 含 "不耗 max_retries"）+ exit 0
#
# 覆盖验收场景（SSOT，逐条覆盖）：
#   场景1 chan-guard.illegal-channel-blocked   [human-obs] 非法 channel → rc2 + PRED-CHANNEL-ILLEGAL
#   场景1 chan-guard.legal-channel-pass        三合法 channel → rc0 放行
#   场景4 e2e.block-no-retry-cost             gate=review-accept ∧ phase=qa ∧ 违规 → stop-hook block

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
    echo "[FAIL] R_PRED_CHAN: 无法定位 REPO_ROOT（缺 .claude-plugin/marketplace.json）" >&2
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
[[ -f "$LIB_SH" ]] || { echo "[FAIL] R_PRED_CHAN: lib.sh 不存在: $LIB_SH" >&2; exit 1; }
[[ -f "$STOP_HOOK" ]] || { echo "[FAIL] R_PRED_CHAN: stop-hook.sh 不存在: $STOP_HOOK" >&2; exit 1; }
[[ -d "$REPO_ROOT/.git" ]] || {
    echo "[FAIL] R_PRED_CHAN: REPO_ROOT 非 git 仓库: $REPO_ROOT" >&2
    exit 1
}

echo "=========================================="
echo " R_PRED_CHAN 谓词 channel 合法性守卫验收（设计契约黑盒）"
echo "=========================================="

# ─────────────────────────────────────────────────────────────────────────────
# 前置断言：函数定义 + §5.7 接线存在性（TDD 红灯——蓝队未实现必 fail，绝不 skip）
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- 前置：函数定义 + §5.7 接线存在性 ---"

if grep -qE '^validate_predicate_channels\(\)|^function validate_predicate_channels' "$LIB_SH"; then
    _log_pass "PRE.channels" "validate_predicate_channels() 函数定义存在于 lib.sh"
else
    _log_fail "PRE.channels" "validate_predicate_channels() 函数未定义于 lib.sh（设计契约 C2 要求新增此函数）"
fi

if grep -qE 'validate_predicate_channels' "$STOP_HOOK"; then
    _log_pass "PRE.wire.channels" "stop-hook.sh 引用 validate_predicate_channels（§5.7 接线）"
else
    _log_fail "PRE.wire.channels" "stop-hook.sh 未引用 validate_predicate_channels（§5.7 接线缺失——防只写函数不接守卫）"
fi

if grep -q 'PRED-CHANNEL-ILLEGAL' "$LIB_SH"; then
    _log_pass "PRE.signal" "lib.sh 含 'PRED-CHANNEL-ILLEGAL' 字面量（违规信号串，契约 C2）"
else
    _log_fail "PRE.signal" "lib.sh 未含 'PRED-CHANNEL-ILLEGAL' 字面量（违规信号串缺失，契约 C2）"
fi

# ── helper：subshell 中 source lib.sh 后调用 validate 函数 ────────────────────
# 范式照搬 predicate-driver-guard.acceptance.test.sh:invoke_validate_driver：
# AUTOPILOT_TEST_MODE + AUTOPILOT_DISABLE_MAIN 抑制 main 副作用，subshell 隔离。
invoke_validate_channels() {
    local state_file="${1}"
    bash -c "
        set -uo pipefail
        export AUTOPILOT_TEST_MODE=1
        export AUTOPILOT_DISABLE_MAIN=1
        source '${LIB_SH}' 2>/dev/null || true
        validate_predicate_channels '${state_file}'
    "
}

# 从 state.md frontmatter 提取字段值（去引号去首尾空格）
# 范式照搬 predicate-driver-guard:get_field
get_field() {
    local state_file="$1" field="$2"
    awk -v f="$field" '
        /^---$/ { in_fm = !in_fm; next }
        in_fm && $0 ~ "^" f ":" {
            value = $0
            sub("^" f ":[[:space:]]*", "", value)
            gsub(/"/, "", value)
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            print value
            exit
        }
    ' "$state_file"
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
mock channel guard test

## 验收场景

${scenarios}
EOF_MD
}

# ── 临时目录 + cleanup ───────────────────────────────────────────────────────
TMP_DIR="$(mktemp -d)"
CLEANUP_DIRS=("$TMP_DIR")
trap 'for d in "${CLEANUP_DIRS[@]}"; do rm -rf "$d"; done' EXIT

# ═════════════════════════════════════════════════════════════════════════════
# 场景1.A chan-guard.illegal-channel-blocked [det-machine]:
#   assert: validate_predicate_channels rc2 ∧ stdout 含 PRED-CHANNEL-ILLEGAL
#   构造：谓词 [human-obs] 非法 channel（iina dogfood 实证场景）
#   反 tautological：违规断言同时断 rc==2 和信号串；下游 chan-guard.legal-channel-pass 配 rc0 反例
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- 场景1 chan-guard.illegal-channel-blocked: [human-obs] 非法 → rc2 + PRED-CHANNEL-ILLEGAL ---"

SC_ILLEGAL='- **chan-guard.illegal-channel-blocked [human-obs]** 操作后 spinner 消失 ｜ observe: 人眼看 ｜ assert: 用户报告 OK ｜ driver: bash:manual'
STATE_ILLEGAL="${TMP_DIR}/state-illegal.md"
write_mock_state "$STATE_ILLEGAL" "$SC_ILLEGAL"

out_illegal=$(invoke_validate_channels "$STATE_ILLEGAL"); rc_illegal=$?

if [[ $rc_illegal -eq 2 ]]; then
    _log_pass "chan-guard.illegal-channel-blocked.rc" "validate_predicate_channels rc2（[human-obs] 非法 channel 违规）"
else
    _log_fail "chan-guard.illegal-channel-blocked.rc" "validate_predicate_channels 期望 rc2，实际 rc=${rc_illegal}，stdout='${out_illegal}'"
fi

if echo "$out_illegal" | grep -q 'PRED-CHANNEL-ILLEGAL'; then
    _log_pass "chan-guard.illegal-channel-blocked.signal" "stdout 含 PRED-CHANNEL-ILLEGAL（双信号之一）"
else
    _log_fail "chan-guard.illegal-channel-blocked.signal" "stdout 应含 PRED-CHANNEL-ILLEGAL，实际='${out_illegal}'"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 场景1.B chan-guard.legal-channel-pass [det-machine]:
#   assert: validate_predicate_channels rc0（全合法 channel 放行）
#   构造：三条谓词 channel 分别 ∈ {det-machine, real-process, visual-residue}（契约 C4 全枚举）
#   反 tautological：此为场景1.A 违规的反例（rc0），守卫恒输出信号串时反例能 kill no-op mutation
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- 场景1 chan-guard.legal-channel-pass: 三合法 channel → rc0 放行 ---"

SC_LEGAL='- **chan-guard.legal-det [det-machine]** AX 断言 ｜ observe: xcodebuild test ｜ assert: isHidden==false ｜ driver: bash:xcodebuild
- **chan-guard.legal-real [real-process]** 进程存活 ｜ observe: pgrep ｜ assert: PID>0 ｜ driver: bash:pgrep
- **chan-guard.legal-visual [visual-residue]** 二值清单 ｜ observe: 截图 diff ｜ assert: 全勾 ｜ driver: bash:diff'
STATE_LEGAL="${TMP_DIR}/state-legal.md"
write_mock_state "$STATE_LEGAL" "$SC_LEGAL"

out_legal=$(invoke_validate_channels "$STATE_LEGAL"); rc_legal=$?

if [[ $rc_legal -eq 0 ]]; then
    _log_pass "chan-guard.legal-channel-pass.rc" "validate_predicate_channels rc0（三合法 channel {det-machine, real-process, visual-residue} 全放行）"
else
    _log_fail "chan-guard.legal-channel-pass.rc" "validate_predicate_channels 三合法 channel 期望 rc0，实际 rc=${rc_legal}，stdout='${out_legal}'"
fi

if echo "$out_legal" | grep -q 'PRED-CHANNEL-ILLEGAL'; then
    _log_fail "chan-guard.legal-channel-pass.no-signal" "合法谓词不应输出 PRED-CHANNEL-ILLEGAL（反例 kill 恒输出信号串 mutation），实际='${out_legal}'"
else
    _log_pass "chan-guard.legal-channel-pass.no-signal" "合法谓词 stdout 不含 PRED-CHANNEL-ILLEGAL（反例守恒）"
fi

# ═════════════════════════════════════════════════════════════════════════════
# 场景4 e2e.block-no-retry-cost [det-machine]: stop-hook §5.7 端到端 block 行为
#   assert: grep decision:block ∧ retry before==after ∧ gate==""
#   构造：临时 git 仓库 + state.md(phase=qa, gate=review-accept, retry_count=2) + [human-obs] 违规
#   跑 stop-hook（stdin JSON），检查 decision:block + reason 含"不耗 max_retries" +
#         state.md retry_count 不变 + gate 清空 + phase 仍 qa
#   范式照搬 predicate-driver-guard.acceptance.test.sh ACC-GUARD-12/13
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- 场景4 e2e.block-no-retry-cost: stop-hook §5.7 block（不耗 retry + 清 gate） ---"

# 构造临时 git 仓库（符合真实场景；stop-hook 可能依赖 git 上下文）
E2E_REPO="$(mktemp -d)"
CLEANUP_DIRS+=("$E2E_REPO")
git -C "$E2E_REPO" init -q
git -C "$E2E_REPO" config user.email "test@test.com"
git -C "$E2E_REPO" config user.name "Test"

E2E_SLUG="20260717-chan-guard-behavior"
E2E_TASK_DIR="${E2E_REPO}/.autopilot/runtime/requirements/${E2E_SLUG}"
mkdir -p "$E2E_TASK_DIR"
printf '%s\n' "$E2E_SLUG" > "${E2E_REPO}/.autopilot/runtime/active.ptr"

RETRY_BEFORE=2
cat > "${E2E_TASK_DIR}/state.md" <<EOF_E2E
---
active: true
phase: "qa"
gate: "review-accept"
iteration: 1
max_iterations: 30
max_retries: 3
retry_count: ${RETRY_BEFORE}
mode: ""
plan_mode: ""
fast_mode:
brief_file: ""
next_task: ""
auto_approve: false
knowledge_extracted: ""
task_dir: "${E2E_TASK_DIR}"
session_id: "chan-guard-session"
started_at: "2026-07-17T00:00:00Z"
contract_required: false
html_review: false
---

## 目标
chan guard behavior

## 验收场景

- **E2E-CHAN [human-obs]** 操作后 spinner 消失 ｜ observe: 人眼看 ｜ assert: 用户报告 OK ｜ driver: bash:manual
EOF_E2E

# 跑 stop-hook（stdin JSON：cwd + session_id 匹配 state；范式同 predicate-driver-guard e2e）
stop_out=$(printf '{"cwd":"%s","session_id":"chan-guard-session","transcript_path":""}' "$E2E_REPO" \
    | bash "$STOP_HOOK" 2>&1)

# block 发生（decision:block）
if echo "$stop_out" | grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    _log_pass "e2e.block-no-retry-cost.block" "stop-hook 输出 decision:block（§5.7 channel 守卫违规触发 block）"
else
    _log_fail "e2e.block-no-retry-cost.block" "stop-hook 应输出 decision:block（gate=review-accept ∧ phase=qa ∧ [human-obs] 非法），实际='${stop_out}'"
fi

# §5.7 特有 reason 字面量（区分其他守卫 block，证明走的是 §5.7 路径）
if echo "$stop_out" | grep -q '不耗 max_retries'; then
    _log_pass "e2e.block-no-retry-cost.reason" "block reason 含 '不耗 max_retries'（§5.7 契约：非 auto-fix 路径）"
else
    _log_fail "e2e.block-no-retry-cost.reason" "block reason 应含 '不耗 max_retries'（§5.7 契约），实际='${stop_out}'"
fi

# e2e.block-no-retry-cost: block 不耗 retry_count
RETRY_AFTER=$(get_field "${E2E_TASK_DIR}/state.md" "retry_count")
if [[ "$RETRY_AFTER" == "$RETRY_BEFORE" ]]; then
    _log_pass "e2e.block-no-retry-cost.retry" "block 不耗 retry_count（before=${RETRY_BEFORE} after=${RETRY_AFTER}，非 auto-fix 路径）"
else
    _log_fail "e2e.block-no-retry-cost.retry" "block 不应耗 retry_count，before=${RETRY_BEFORE} after=${RETRY_AFTER}"
fi

# e2e.block-no-retry-cost: block 后 gate="" phase=qa（gate 清空子断言）
GATE_AFTER=$(get_field "${E2E_TASK_DIR}/state.md" "gate")
PHASE_AFTER=$(get_field "${E2E_TASK_DIR}/state.md" "phase")
if [[ -z "$GATE_AFTER" ]]; then
    _log_pass "e2e.block-no-retry-cost.gate" "block 后 gate 清空（gate=''）"
else
    _log_fail "e2e.block-no-retry-cost.gate" "block 后 gate 应清空，实际 gate='${GATE_AFTER}'"
fi
if [[ "$PHASE_AFTER" == "qa" ]]; then
    _log_pass "e2e.block-no-retry-cost.phase" "block 后 phase 仍为 qa（不回退阶段）"
else
    _log_fail "e2e.block-no-retry-cost.phase" "block 后 phase 应为 qa，实际 phase='${PHASE_AFTER}'"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 汇总
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo " R_PRED_CHAN 汇总: PASSED=$PASSED  FAILED=$FAILED"
echo "=========================================="
echo ""
echo "覆盖的验收场景/谓词：场景1 chan-guard.illegal-channel-blocked / chan-guard.legal-channel-pass / 场景4 e2e.block-no-retry-cost"

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
