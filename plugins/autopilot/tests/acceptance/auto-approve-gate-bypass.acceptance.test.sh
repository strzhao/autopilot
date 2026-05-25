#!/usr/bin/env bash
# R12: 验证 stop-hook 在 auto_approve=true + phase=qa + gate=review-accept 时
# 自动推进 merge（auto-chain 子任务），其他场景不动。
# 红队测试 — 仅基于设计文档编写。
#
# 设计文档要求（state.md 20260526-开始修复这个问题）：
#   - 正向：phase=qa + gate=review-accept + auto_approve=true → 自动推进 merge
#     (gate 清空、phase=merge、stdout 含 block JSON 注入 merge prompt)
#   - 反向 A：同上但 auto_approve=false → 静默 exit 0（普通单任务等用户审批）
#   - 反向 B：同上但 phase=auto-fix → 静默 exit 0（不误处理 max_retries 兜底）
#
# 回归历史：v3.36.1 修了 auto-chain 失效双链「第 3 环」（AI 不写 next_task），
# v3.36.2 修「第 2 环」（stop-hook 不在 auto_approve=true 时跳过 review-accept gate）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
STOP_HOOK="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"

fail() {
    echo "[FAIL] R12: $1" >&2
    exit 1
}

pass() {
    echo "[PASS] R12: $1"
}

# 前置
[[ -f "$STOP_HOOK" ]] || fail "stop-hook.sh 不存在: $STOP_HOOK"

# ── fixture helper ──
# 参数: phase gate auto_approve
# 输出: fixture 目录绝对路径
build_fixture() {
    local phase="$1" gate="$2" auto_approve="$3"
    local dir
    dir="$(mktemp -d -t autopilot-r12-XXXXXX)"
    mkdir -p "$dir/.autopilot/runtime/requirements/test-task"
    echo "test-task" > "$dir/.autopilot/runtime/active.ptr"
    cat > "$dir/.autopilot/runtime/requirements/test-task/state.md" <<EOF
---
active: true
phase: "$phase"
gate: "$gate"
iteration: 3
max_iterations: 30
max_retries: 3
retry_count: 0
mode: "single"
plan_mode: ""
fast_mode: true
brief_file: "$dir/.autopilot/project/tasks/001-x.md"
next_task: ""
auto_approve: $auto_approve
knowledge_extracted: ""
task_dir: "$dir/.autopilot/runtime/requirements/test-task"
session_id: r12sess
started_at: "2026-05-26T00:00:00Z"
contract_required: false
html_review: false
---

## 目标
test fixture
EOF
    echo "$dir"
}

# 在 fixture 目录中运行 stop-hook，捕获 stdout + exit code
run_hook() {
    local dir="$1"
    local hook_input='{"session_id":"r12sess","transcript_path":"/tmp/none"}'
    (cd "$dir" && echo "$hook_input" | bash "$STOP_HOOK" 2>/dev/null; echo "__EXIT__$?")
}

# 提取 fixture 中 state.md 的字段值
get_state_field() {
    local dir="$1" field="$2"
    grep -E "^${field}:" "$dir/.autopilot/runtime/requirements/test-task/state.md" \
        | head -1 | sed -E "s/^${field}:[[:space:]]*\"?([^\"]*)\"?$/\1/"
}

# ─────────────────────────────────────────────────────────────────────
# 断言 1：正向 — auto_approve=true + phase=qa + gate=review-accept → 自动推进
# ─────────────────────────────────────────────────────────────────────
dir_pos="$(build_fixture qa review-accept true)"
out_pos="$(run_hook "$dir_pos")"
body_pos=$(echo "$out_pos" | grep -v '__EXIT__')

if ! echo "$body_pos" | grep -q '"decision":[[:space:]]*"block"'; then
    fail "正向场景未输出 block JSON（应该 auto-approve 推进 merge）。stdout: $body_pos"
fi
phase_after_pos=$(get_state_field "$dir_pos" phase)
gate_after_pos=$(get_state_field "$dir_pos" gate)
if [[ "$phase_after_pos" != "merge" ]]; then
    fail "正向场景 state.md phase 未推进到 merge，实际: $phase_after_pos"
fi
if [[ -n "$gate_after_pos" ]]; then
    fail "正向场景 state.md gate 未清空，实际: '$gate_after_pos'"
fi
pass "正向：phase=qa + gate=review-accept + auto_approve=true → block JSON + state.phase=merge + state.gate=''"
rm -rf "$dir_pos"

# ─────────────────────────────────────────────────────────────────────
# 断言 2：反向 A — auto_approve=false（普通单任务）→ 静默 exit、不推进
# ─────────────────────────────────────────────────────────────────────
dir_neg_a="$(build_fixture qa review-accept false)"
out_neg_a="$(run_hook "$dir_neg_a")"
body_neg_a=$(echo "$out_neg_a" | grep -v '__EXIT__')

if echo "$body_neg_a" | grep -q '"decision":[[:space:]]*"block"'; then
    fail "反向 A（auto_approve=false）不应输出 block JSON（应等用户审批）。stdout: $body_neg_a"
fi
phase_after_neg_a=$(get_state_field "$dir_neg_a" phase)
gate_after_neg_a=$(get_state_field "$dir_neg_a" gate)
if [[ "$phase_after_neg_a" != "qa" ]]; then
    fail "反向 A state.md phase 不应被修改（auto_approve=false），实际: $phase_after_neg_a"
fi
if [[ "$gate_after_neg_a" != "review-accept" ]]; then
    fail "反向 A state.md gate 不应被清空（auto_approve=false），实际: '$gate_after_neg_a'"
fi
pass "反向 A：phase=qa + gate=review-accept + auto_approve=false → 不推进，等用户审批"
rm -rf "$dir_neg_a"

# ─────────────────────────────────────────────────────────────────────
# 断言 3：反向 B — phase=auto-fix（max_retries 兜底）→ 静默 exit、不推进
# ─────────────────────────────────────────────────────────────────────
dir_neg_b="$(build_fixture auto-fix review-accept true)"
out_neg_b="$(run_hook "$dir_neg_b")"
body_neg_b=$(echo "$out_neg_b" | grep -v '__EXIT__')

if echo "$body_neg_b" | grep -q '"decision":[[:space:]]*"block"'; then
    fail "反向 B（phase=auto-fix）不应输出 block JSON（max_retries 兜底场景应等用户决定）。stdout: $body_neg_b"
fi
phase_after_neg_b=$(get_state_field "$dir_neg_b" phase)
if [[ "$phase_after_neg_b" != "auto-fix" ]]; then
    fail "反向 B state.md phase 不应被修改（phase!=qa 不进短路），实际: $phase_after_neg_b"
fi
pass "反向 B：phase=auto-fix + gate=review-accept + auto_approve=true → 不推进，max_retries 兜底不自动通过"
rm -rf "$dir_neg_b"

# ─────────────────────────────────────────────────────────────────────────────
# 断言 4：版本同步守护 — 这 4 个测试文件不再硬编码 '3.x.0' 版本字面
# v3.36.2 把硬编码 TARGET_VERSION 改为动态读 plugin.json，根治 [2026-05-09]
# 「acceptance test 中 TARGET_VERSION 是版本同步规则的隐藏盲区」教训
# ─────────────────────────────────────────────────────────────────────────────
ACCEPTANCE_DIR="$REPO_ROOT/plugins/autopilot/tests/acceptance"
DYNAMIC_TESTS=(
    "brainstorm-default.acceptance.test.sh"
    "plan-review-html.acceptance.test.sh"
    "brainstorm-skill-extract.acceptance.test.sh"
)
# tier5-quantitative.sh 注释/banner 里描述性 v3.36.0 历史标记保留，
# 但断言中的版本号必须动态读，故单独宽松规则：只检查 assert_grep_ge 调用的字面参数

for t in "${DYNAMIC_TESTS[@]}"; do
    file="$ACCEPTANCE_DIR/$t"
    [[ -f "$file" ]] || fail "测试文件不存在: $t"
    # 不应有 TARGET_VERSION="数字.数字.数字" 字面赋值（必须用变量赋值）
    if grep -qE 'TARGET_VERSION="[0-9]+\.[0-9]+\.[0-9]+"' "$file"; then
        fail "$t 仍硬编码 TARGET_VERSION 字面（应改为从 plugin.json 动态读）"
    fi
    # 必须从 plugin.json 动态读
    if ! grep -q 'plugin.json' "$file" || ! grep -q 'TARGET_VERSION=' "$file"; then
        fail "$t 缺少从 plugin.json 动态读 TARGET_VERSION 的逻辑"
    fi
done
pass "版本同步守护：3 个 acceptance test 已动态化 TARGET_VERSION（根治硬编码盲区）"

# tier5-quantitative 单独检查：T5e 段的 assert_grep_ge 不应再有 "3.36.0" 字面参数
TIER5_FILE="$ACCEPTANCE_DIR/tier5-quantitative.acceptance.test.sh"
T5E_SECTION=$(awk '/^# T5e:/{f=1;print;next} f&&/^# T5[fghij]:/{f=0} f' "$TIER5_FILE")
if echo "$T5E_SECTION" | grep -qE 'assert_grep[E]?_ge[[:space:]]+"T5e[^"]*"[[:space:]]+[^P]*"3\.36\.0"'; then
    fail "tier5-quantitative.sh T5e 段的 assert 仍硬编码 '3.36.0' 字面（应使用 \$PLUGIN_VERSION 变量）"
fi
pass "tier5-quantitative T5e 段断言已动态化（PLUGIN_VERSION 变量替代硬编码字面）"

echo "[OK ] R12 auto-approve-gate-bypass — 5 条断言全部通过"
exit 0
