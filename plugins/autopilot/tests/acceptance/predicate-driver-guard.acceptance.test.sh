#!/usr/bin/env bash
# R_PRED_GUARD: 谓词驱动证据守卫验收测试
# 红队测试 — 仅基于设计文档（守卫机制 + 谓词格式 + 验收谓词 SSOT）编写，
#            铁律：绝不读取蓝队本次改动的实现文件（lib.sh 新函数 / stop-hook §5.7 /
#            scenario-generator-prompt.md / state-file-guide.md / SKILL.md），
#            不读 state.md 的 ## 实现计划 区域。
#            grep 命中数 == 契约字面要求（函数名 / 接线 / reason 字面量），非"读内容凑断言"。
#
# 守卫机制（设计契约，黑盒）：
#   lib.sh::validate_predicate_driver <state_file>
#     - 解析 ## 验收场景 区域（bullet-list + fullwidth ｜ 分隔）
#     - 反向判定：driver type=node-script ∧ (description 或 observe 含
#       curl/fetch/playwright/overmind/pylon/mysql) → 违规
#     - rc0=合规 / rc2=违规（stdout PRED-DRIVER-VIOLATION: <id> <reason>）/ rc1=无谓词或全无 driver（no-op）
#   lib.sh::validate_predicate_artifacts <state_file>
#     - 对有 artifact 字段的谓词校验 -f 且 wc -c > 0
#     - rc0/rc2(PRED-ARTIFACT-MISSING: <id> <path>)/rc1
#   stop-hook.sh §5.7：gate=review-accept ∧ phase=qa 时调两函数，
#     任一 rc2 → 清 gate + block JSON（reason 含 "不耗 max_retries"）+ exit 0
#   driver type ∈ {curl, playwright, node-script, fs-grep, freshness}
#   谓词格式：- **<id> [channel]** <描述> ｜ observe: <观测> ｜ assert: <DbC> ｜ driver: <type>:<target> ｜ artifact: <path>
#              （fullwidth ｜ 分隔，禁 halfwidth | 表格）
#
# 覆盖验收谓词（SSOT，逐条覆盖）：
#   ACC-GUARD-01  driver=curl + artifact 存在非空 → 放行 rc0
#   ACC-GUARD-10  observe 含 curl 但 driver=node-script → block PRED-DRIVER-VIOLATION
#   ACC-GUARD-12  block 不耗 retry_count（非 auto-fix 路径）
#   ACC-GUARD-13  block 后 gate="" phase=qa
#   ACC-GUARD-20  artifact 字段存在但文件不存在/空 → block PRED-ARTIFACT-MISSING
#   ACC-GUARD-30  旧 task 谓词无 driver 字段 → no-op 放行 rc1
#   ACC-GUARD-40  skill-md-net-shrinkage.acceptance.test.sh PASS（四文件净 deleted >= added）
#   ACC-GUARD-51  不引入新 skill 调用（verify/run）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# REPO_ROOT 稳健探测：从 SCRIPT_DIR 往上找 .claude-plugin/marketplace.json
# （兼容暂存区 .autopilot/runtime/requirements/<slug>/acceptance-staging/ 与
#   合流后 plugins/autopilot/tests/acceptance/ 两种部署位置）
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
    echo "[FAIL] R_PRED_GUARD: 无法定位 REPO_ROOT（缺 .claude-plugin/marketplace.json）" >&2
    exit 1
}

LIB_SH="${REPO_ROOT}/plugins/autopilot/scripts/lib.sh"
STOP_HOOK="${REPO_ROOT}/plugins/autopilot/scripts/stop-hook.sh"
SKILL_FILE="${REPO_ROOT}/plugins/autopilot/skills/autopilot/SKILL.md"
SHRINKAGE_TEST="${SCRIPT_DIR}/skill-md-net-shrinkage.acceptance.test.sh"

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
[[ -f "$LIB_SH" ]] || { echo "[FAIL] R_PRED_GUARD: lib.sh 不存在: $LIB_SH" >&2; exit 1; }
[[ -f "$STOP_HOOK" ]] || { echo "[FAIL] R_PRED_GUARD: stop-hook.sh 不存在: $STOP_HOOK" >&2; exit 1; }
[[ -f "$SKILL_FILE" ]] || { echo "[FAIL] R_PRED_GUARD: SKILL.md 不存在: $SKILL_FILE" >&2; exit 1; }
[[ -f "$SHRINKAGE_TEST" ]] || { echo "[FAIL] R_PRED_GUARD: shrinkage 测试不存在: $SHRINKAGE_TEST" >&2; exit 1; }

# 仓库根可识别为 git 仓库（ACC-GUARD-40 子测试依赖 git diff）
[[ -d "$REPO_ROOT/.git" ]] || {
    echo "[FAIL] R_PRED_GUARD: REPO_ROOT 非 git 仓库: $REPO_ROOT" >&2
    exit 1
}

echo "=========================================="
echo " R_PRED_GUARD 谓词驱动证据守卫验收（设计契约黑盒）"
echo "=========================================="

# ─────────────────────────────────────────────────────────────────────────────
# 前置断言：函数定义 + §5.7 接线存在性（TDD 红灯——蓝队未实现必 fail，绝不 skip）
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- 前置：函数定义 + §5.7 接线存在性 ---"

if grep -qE '^validate_predicate_driver\(\)|^function validate_predicate_driver' "$LIB_SH"; then
    _log_pass "PRE.driver" "validate_predicate_driver() 函数定义存在于 lib.sh"
else
    _log_fail "PRE.driver" "validate_predicate_driver() 函数未定义于 lib.sh（设计契约要求新增此函数）"
fi

if grep -qE '^validate_predicate_artifacts\(\)|^function validate_predicate_artifacts' "$LIB_SH"; then
    _log_pass "PRE.artifacts" "validate_predicate_artifacts() 函数定义存在于 lib.sh"
else
    _log_fail "PRE.artifacts" "validate_predicate_artifacts() 函数未定义于 lib.sh（设计契约要求新增此函数）"
fi

# §5.7 接线：stop-hook 引用两函数 + reason 字面量
if grep -qE 'validate_predicate_driver' "$STOP_HOOK"; then
    _log_pass "PRE.wire.driver" "stop-hook.sh 引用 validate_predicate_driver（§5.7 接线）"
else
    _log_fail "PRE.wire.driver" "stop-hook.sh 未引用 validate_predicate_driver（§5.7 接线缺失——防只写函数不接守卫）"
fi

if grep -qE 'validate_predicate_artifacts' "$STOP_HOOK"; then
    _log_pass "PRE.wire.artifacts" "stop-hook.sh 引用 validate_predicate_artifacts（§5.7 接线）"
else
    _log_fail "PRE.wire.artifacts" "stop-hook.sh 未引用 validate_predicate_artifacts（§5.7 接线缺失）"
fi

if grep -q '不耗 max_retries' "$STOP_HOOK"; then
    _log_pass "PRE.wire.reason" "stop-hook.sh 含 '不耗 max_retries' 字面量（§5.7 block reason 契约）"
else
    _log_fail "PRE.wire.reason" "stop-hook.sh 未含 '不耗 max_retries' 字面量（§5.7 block reason 契约缺失）"
fi

# ── helper：subshell 中 source lib.sh 后调用 validate 函数 ────────────────────
# 沿用 acceptance-tamper-guard / oracle-snapshot-taint-guard 的 invoke 范式：
# AUTOPILOT_TEST_MODE + AUTOPILOT_DISABLE_MAIN 抑制 main 副作用，subshell 隔离。
invoke_validate_driver() {
    local state_file="${1}"
    bash -c "
        set -uo pipefail
        export AUTOPILOT_TEST_MODE=1
        export AUTOPILOT_DISABLE_MAIN=1
        source '${LIB_SH}' 2>/dev/null || true
        validate_predicate_driver '${state_file}'
    "
}

invoke_validate_artifacts() {
    local state_file="${1}"
    bash -c "
        set -uo pipefail
        export AUTOPILOT_TEST_MODE=1
        export AUTOPILOT_DISABLE_MAIN=1
        source '${LIB_SH}' 2>/dev/null || true
        validate_predicate_artifacts '${state_file}'
    "
}

# 从 state.md frontmatter 提取字段值（去引号去首尾空格）
# 用于 ACC-GUARD-12/13 端到端测试检查 retry_count / gate / phase
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
# $1 = 输出文件路径，$2 = 验收场景区域 bullet list 内容
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
started_at: "2026-07-08T00:00:00Z"
contract_required: false
html_review: false
---

## 目标
mock predicate guard test

## 验收场景

${scenarios}
EOF_MD
}

# ── 临时目录 + cleanup ───────────────────────────────────────────────────────
TMP_DIR="$(mktemp -d)"
CLEANUP_DIRS=("$TMP_DIR")
trap 'for d in "${CLEANUP_DIRS[@]}"; do rm -rf "$d"; done' EXIT

# ═════════════════════════════════════════════════════════════════════════════
# ACC-GUARD-01 [det-machine]: driver=curl + artifact 文件存在且非空 → 守卫放行（rc0）
#   assert: validate_predicate_driver rc0 ∧ validate_predicate_artifacts rc0
#   构造：谓词 driver=curl:http://x + artifact 指向临时非空文件
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- ACC-GUARD-01: driver=curl + artifact 存在非空 → 放行 rc0 ---"

ART01="${TMP_DIR}/ACC-GUARD-01.out"
printf 'real curl output non-empty\n' > "$ART01"

SC01='- **ACC-GUARD-01 [det-machine]** 验证 API 返回 ｜ observe: curl http://x/api ｜ assert: rc==0 ｜ driver: curl:http://x/api ｜ artifact: '"$ART01"
STATE01="${TMP_DIR}/state-01.md"
write_mock_state "$STATE01" "$SC01"

out_drv01=$(invoke_validate_driver "$STATE01"); rc_drv01=$?
out_art01=$(invoke_validate_artifacts "$STATE01"); rc_art01=$?

if [[ $rc_drv01 -eq 0 ]]; then
    _log_pass "ACC-GUARD-01.driver" "validate_predicate_driver rc0（driver=curl 合规，observe 含 curl 但 driver 非 node-script 不违规）"
else
    _log_fail "ACC-GUARD-01.driver" "validate_predicate_driver 期望 rc0，实际 rc=${rc_drv01}，stdout='${out_drv01}'"
fi

if [[ $rc_art01 -eq 0 ]]; then
    _log_pass "ACC-GUARD-01.artifacts" "validate_predicate_artifacts rc0（artifact 文件存在且 wc -c > 0）"
else
    _log_fail "ACC-GUARD-01.artifacts" "validate_predicate_artifacts 期望 rc0，实际 rc=${rc_art01}，stdout='${out_art01}'"
fi

# ═════════════════════════════════════════════════════════════════════════════
# ACC-GUARD-10 [det-machine]: observe 含 curl 但 driver=node-script → block
#   assert: validate_predicate_driver rc2 ∧ stdout 含 PRED-DRIVER-VIOLATION
#   构造：谓词 observe 含 curl + driver=node-script:tests/mock.js
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- ACC-GUARD-10: observe 含 curl 但 driver=node-script → block PRED-DRIVER-VIOLATION ---"

SC10='- **ACC-GUARD-10 [det-machine]** 验证 API 返回 ｜ observe: curl http://x/api ｜ assert: rc==0 ｜ driver: node-script:tests/mock.js'
STATE10="${TMP_DIR}/state-10.md"
write_mock_state "$STATE10" "$SC10"

out10=$(invoke_validate_driver "$STATE10"); rc10=$?

if [[ $rc10 -eq 2 ]]; then
    _log_pass "ACC-GUARD-10.rc" "validate_predicate_driver rc2（observe 含 curl + driver=node-script 反向判定违规）"
else
    _log_fail "ACC-GUARD-10.rc" "validate_predicate_driver 期望 rc2，实际 rc=${rc10}，stdout='${out10}'"
fi

if echo "$out10" | grep -q 'PRED-DRIVER-VIOLATION'; then
    _log_pass "ACC-GUARD-10.signal" "stdout 含 PRED-DRIVER-VIOLATION（双信号之一）"
else
    _log_fail "ACC-GUARD-10.signal" "stdout 应含 PRED-DRIVER-VIOLATION，实际='${out10}'"
fi

# ═════════════════════════════════════════════════════════════════════════════
# ACC-GUARD-20 [det-machine]: 有 artifact 字段但文件不存在/空 → block
#   assert: validate_predicate_artifacts rc2 ∧ stdout 含 PRED-ARTIFACT-MISSING
#   构造：谓词 artifact 指向不存在的文件 + 空文件子断言
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- ACC-GUARD-20: artifact 字段存在但文件不存在/空 → block PRED-ARTIFACT-MISSING ---"

# 子断言 a：文件不存在
MISSING_PATH="${TMP_DIR}/nonexistent-20.out"
rm -f "$MISSING_PATH"
SC20='- **ACC-GUARD-20 [det-machine]** 验证 API ｜ observe: curl http://x ｜ assert: rc==0 ｜ driver: curl:http://x ｜ artifact: '"$MISSING_PATH"
STATE20="${TMP_DIR}/state-20.md"
write_mock_state "$STATE20" "$SC20"

out20=$(invoke_validate_artifacts "$STATE20"); rc20=$?

if [[ $rc20 -eq 2 ]]; then
    _log_pass "ACC-GUARD-20.rc" "validate_predicate_artifacts rc2（artifact 文件不存在）"
else
    _log_fail "ACC-GUARD-20.rc" "validate_predicate_artifacts 期望 rc2（文件不存在），实际 rc=${rc20}，stdout='${out20}'"
fi

if echo "$out20" | grep -q 'PRED-ARTIFACT-MISSING'; then
    _log_pass "ACC-GUARD-20.signal" "stdout 含 PRED-ARTIFACT-MISSING（双信号之一）"
else
    _log_fail "ACC-GUARD-20.signal" "stdout 应含 PRED-ARTIFACT-MISSING，实际='${out20}'"
fi

# 子断言 b：文件存在但空（wc -c == 0）
EMPTY_PATH="${TMP_DIR}/empty-20.out"
: > "$EMPTY_PATH"
SC20b='- **ACC-GUARD-20b [det-machine]** 验证 API ｜ observe: curl http://x ｜ assert: rc==0 ｜ driver: curl:http://x ｜ artifact: '"$EMPTY_PATH"
STATE20b="${TMP_DIR}/state-20b.md"
write_mock_state "$STATE20b" "$SC20b"

out20b=$(invoke_validate_artifacts "$STATE20b"); rc20b=$?
if [[ $rc20b -eq 2 ]]; then
    _log_pass "ACC-GUARD-20b.empty" "validate_predicate_artifacts rc2（artifact 空文件 wc -c == 0 同样违规）"
else
    _log_fail "ACC-GUARD-20b.empty" "validate_predicate_artifacts 空文件期望 rc2，实际 rc=${rc20b}，stdout='${out20b}'"
fi

# ═════════════════════════════════════════════════════════════════════════════
# ACC-GUARD-30 [det-machine]: 旧 task 谓词无 driver 字段 → no-op 放行（rc1）
#   assert: validate_predicate_driver rc1（或 rc0 放行）∧ stdout 不含 PRED-DRIVER-VIOLATION
#   构造：谓词只有描述/observe/assert，无 driver 字段（旧 task 兼容）
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- ACC-GUARD-30: 旧 task 谓词无 driver 字段 → no-op 放行 rc1 ---"

SC30='- **ACC-GUARD-30 [det-machine]** 验证 API 返回 ｜ observe: curl http://x ｜ assert: rc==0'
STATE30="${TMP_DIR}/state-30.md"
write_mock_state "$STATE30" "$SC30"

out30=$(invoke_validate_driver "$STATE30"); rc30=$?

# rc1=无 driver no-op，或 rc0=合规放行；设计文档 SSOT 允许 rc1 或 rc0 放行
if [[ $rc30 -eq 1 ]] || [[ $rc30 -eq 0 ]]; then
    _log_pass "ACC-GUARD-30.rc" "validate_predicate_driver rc=${rc30}（无 driver 字段 → no-op/放行，旧 task 兼容）"
else
    _log_fail "ACC-GUARD-30.rc" "validate_predicate_driver 无 driver 期望 rc1 或 rc0，实际 rc=${rc30}，stdout='${out30}'"
fi

if echo "$out30" | grep -q 'PRED-DRIVER-VIOLATION'; then
    _log_fail "ACC-GUARD-30.signal" "stdout 不应含 PRED-DRIVER-VIOLATION（旧谓词放行），实际='${out30}'"
else
    _log_pass "ACC-GUARD-30.signal" "stdout 不含 PRED-DRIVER-VIOLATION（旧谓词 no-op 放行，不误报）"
fi

# ═════════════════════════════════════════════════════════════════════════════
# ACC-GUARD-12 / ACC-GUARD-13 [det-machine]: stop-hook §5.7 端到端 block 行为
#   ACC-GUARD-12 assert: stop-hook block 后 retry_count 不变（非 auto-fix 路径）
#   ACC-GUARD-13 assert: stop-hook block 后 gate="" phase=qa
#   构造：临时 git 仓库 + state.md(phase=qa, gate=review-accept, retry_count=2) +
#         违规谓词（observe 含 curl + driver=node-script）
#   跑 stop-hook（stdin JSON），检查 decision:block + reason 含"不耗 max_retries" +
#         state.md retry_count 不变 + gate 清空 + phase 仍 qa
# （端到端范式参照 oracle-snapshot-taint-guard.acceptance.test.sh §8.5.2 行为测试）
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- ACC-GUARD-12/13: stop-hook §5.7 block 行为（不耗 retry + 清 gate） ---"

# 构造临时 git 仓库（符合真实场景；stop-hook 可能依赖 git 上下文）
E2E_REPO="$(mktemp -d)"
CLEANUP_DIRS+=("$E2E_REPO")
git -C "$E2E_REPO" init -q
git -C "$E2E_REPO" config user.email "test@test.com"
git -C "$E2E_REPO" config user.name "Test"

E2E_SLUG="20260708-pred-guard-behavior"
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
session_id: "pred-guard-session"
started_at: "2026-07-08T00:00:00Z"
contract_required: false
html_review: false
---

## 目标
pred guard behavior

## 验收场景

- **E2E-PRED [det-machine]** 验证 API 返回 ｜ observe: curl http://x/api ｜ assert: rc==0 ｜ driver: node-script:tests/mock.js
EOF_E2E

# 跑 stop-hook（stdin JSON：cwd + session_id 匹配 state；范式同 oracle 测试）
stop_out=$(printf '{"cwd":"%s","session_id":"pred-guard-session","transcript_path":""}' "$E2E_REPO" \
    | bash "$STOP_HOOK" 2>&1)

# block 发生（decision:block）
if echo "$stop_out" | grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    _log_pass "ACC-GUARD-12.block" "stop-hook 输出 decision:block（§5.7 predicate driver 违规触发 block）"
else
    _log_fail "ACC-GUARD-12.block" "stop-hook 应输出 decision:block（gate=review-accept ∧ phase=qa ∧ driver 违规），实际='${stop_out}'"
fi

# §5.7 特有 reason 字面量（区分其他守卫 block，证明走的是 §5.7 路径）
if echo "$stop_out" | grep -q '不耗 max_retries'; then
    _log_pass "ACC-GUARD-12.reason" "block reason 含 '不耗 max_retries'（§5.7 契约：非 auto-fix 路径）"
else
    _log_fail "ACC-GUARD-12.reason" "block reason 应含 '不耗 max_retries'（§5.7 契约），实际='${stop_out}'"
fi

# ACC-GUARD-12: block 不耗 retry_count
RETRY_AFTER=$(get_field "${E2E_TASK_DIR}/state.md" "retry_count")
if [[ "$RETRY_AFTER" == "$RETRY_BEFORE" ]]; then
    _log_pass "ACC-GUARD-12.retry" "block 不耗 retry_count（before=${RETRY_BEFORE} after=${RETRY_AFTER}，非 auto-fix 路径）"
else
    _log_fail "ACC-GUARD-12.retry" "block 不应耗 retry_count，before=${RETRY_BEFORE} after=${RETRY_AFTER}"
fi

# ACC-GUARD-13: block 后 gate="" phase=qa
GATE_AFTER=$(get_field "${E2E_TASK_DIR}/state.md" "gate")
PHASE_AFTER=$(get_field "${E2E_TASK_DIR}/state.md" "phase")
if [[ -z "$GATE_AFTER" ]]; then
    _log_pass "ACC-GUARD-13.gate" "block 后 gate 清空（gate=''）"
else
    _log_fail "ACC-GUARD-13.gate" "block 后 gate 应清空，实际 gate='${GATE_AFTER}'"
fi
if [[ "$PHASE_AFTER" == "qa" ]]; then
    _log_pass "ACC-GUARD-13.phase" "block 后 phase 仍为 qa（不回退阶段）"
else
    _log_fail "ACC-GUARD-13.phase" "block 后 phase 应为 qa，实际 phase='${PHASE_AFTER}'"
fi

# ═════════════════════════════════════════════════════════════════════════════
# ACC-GUARD-40 [det-machine]: skill-md-net-shrinkage.acceptance.test.sh PASS
#   assert: bash skill-md-net-shrinkage.acceptance.test.sh exit 0
#   （四文件 red-team-prompt.md/blue-team-prompt.md/implement-phase.md/SKILL.md 净 deleted >= added）
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- ACC-GUARD-40: skill-md-net-shrinkage.acceptance.test.sh PASS ---"

bash "$SHRINKAGE_TEST" >/dev/null 2>&1
rc_shrink=$?
if [[ $rc_shrink -eq 0 ]]; then
    _log_pass "ACC-GUARD-40" "skill-md-net-shrinkage.acceptance.test.sh exit 0（四文件净 deleted >= added）"
else
    _log_fail "ACC-GUARD-40" "skill-md-net-shrinkage.acceptance.test.sh 期望 exit 0，实际 exit ${rc_shrink}（四文件净增行违规）"
fi

# ═════════════════════════════════════════════════════════════════════════════
# ACC-GUARD-51 [det-machine]: 不引入新 skill 调用（verify/run）
#   assert: grep stop-hook.sh/lib.sh/SKILL.md 无 `Skill: "verify"` / `Skill: "run"`
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo "--- ACC-GUARD-51: 不引入新 skill 调用（verify/run） ---"

SKILL_CALL_VIOL=0
SKILL_CALL_FILES=()
for f in "$STOP_HOOK" "$LIB_SH" "$SKILL_FILE"; do
    if grep -qE 'Skill: "(verify|run)"' "$f" 2>/dev/null; then
        SKILL_CALL_VIOL=1
        SKILL_CALL_FILES+=("$(basename "$f")")
    fi
done

if [[ $SKILL_CALL_VIOL -eq 0 ]]; then
    _log_pass "ACC-GUARD-51" "stop-hook.sh/lib.sh/SKILL.md 均无 'Skill: \"verify\"' / 'Skill: \"run\"' 调用"
else
    _log_fail "ACC-GUARD-51" "检测到新 skill 调用（verify/run）于: ${SKILL_CALL_FILES[*]}（设计要求不引入新 skill 调用）"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 汇总
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo " R_PRED_GUARD 汇总: PASSED=$PASSED  FAILED=$FAILED"
echo "=========================================="
echo ""
echo "覆盖的验收谓词：ACC-GUARD-01/10/12/13/20/30/40/51（全 8 条 det-machine）"

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
