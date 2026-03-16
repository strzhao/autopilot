#!/bin/bash

# dev-loop Stop Hook — 阶段状态机循环引擎
# 基于 ralph-loop 的 Stop hook 模式，增加阶段状态机和审批门逻辑
#
# 行为:
#   1. 状态文件不存在 → 放行
#   2. session_id 不匹配 → 放行
#   3. gate 非空（审批门） → 发通知 + 放行（等待用户审批）
#   4. phase=done → 清理 + 放行
#   5. 超过 max_iterations → 清理 + 放行
#   6. 其他 → block + 注入阶段 prompt，继续循环

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 读取 hook 输入
HOOK_INPUT=$(cat)

STATE_FILE=".claude/dev-loop.local.md"

# ── 1. 状态文件检查 ──

if [[ ! -f "$STATE_FILE" ]]; then
    exit 0
fi

# ── 2. 解析 frontmatter ──

FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")

get_field() {
    echo "$FRONTMATTER" | grep "^${1}:" | sed "s/${1}: *//" | sed 's/^"\(.*\)"$/\1/'
}

PHASE=$(get_field "phase")
GATE=$(get_field "gate")
ITERATION=$(get_field "iteration")
MAX_ITERATIONS=$(get_field "max_iterations")
STATE_SESSION=$(get_field "session_id")

# ── 3. Session 隔离 ──

HOOK_SESSION=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""')
if [[ -n "$STATE_SESSION" ]] && [[ "$STATE_SESSION" != "$HOOK_SESSION" ]]; then
    exit 0
fi

# ── 4. 数值校验 ──

if [[ ! "$ITERATION" =~ ^[0-9]+$ ]]; then
    echo "⚠️  dev-loop: 状态文件损坏 (iteration: '$ITERATION')" >&2
    rm "$STATE_FILE"
    exit 0
fi

if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
    echo "⚠️  dev-loop: 状态文件损坏 (max_iterations: '$MAX_ITERATIONS')" >&2
    rm "$STATE_FILE"
    exit 0
fi

# ── 5. phase=done → 完成清理 ──

if [[ "$PHASE" == "done" ]]; then
    bash "$SCRIPT_DIR/notify.sh" complete 2>/dev/null || true
    rm "$STATE_FILE"
    exit 0
fi

# ── 6. 审批门检查 ──

if [[ -n "$GATE" ]]; then
    bash "$SCRIPT_DIR/notify.sh" "$GATE" 2>/dev/null || true
    # 放行退出，等待用户回来审批
    exit 0
fi

# ── 7. max_iterations 检查 ──

if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
    echo "🛑 dev-loop: 达到最大迭代次数 ($MAX_ITERATIONS)。" >&2
    bash "$SCRIPT_DIR/notify.sh" error 2>/dev/null || true
    rm "$STATE_FILE"
    exit 0
fi

# ── 8. 递增 iteration ──

NEXT_ITERATION=$((ITERATION + 1))
TEMP_FILE="${STATE_FILE}.tmp.$$"
sed "s/^iteration: .*/iteration: $NEXT_ITERATION/" "$STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$STATE_FILE"

# ── 9. 构造 block JSON ──

# design 阶段使用 Plan Mode
if [[ "$PHASE" == "design" ]]; then
    PROMPT="读取 .claude/dev-loop.local.md 状态文件获取目标描述，然后立即调用 EnterPlanMode 工具进入 Plan Mode。不要在调用 EnterPlanMode 之前做任何代码探索。所有探索和设计工作必须在 Plan Mode 内完成。按照 dev-loop skill 的 Phase: design 指引执行。"
else
    PROMPT="读取 .claude/dev-loop.local.md 状态文件，当前阶段: $PHASE，迭代: $NEXT_ITERATION。按照 dev-loop skill 的指引执行当前阶段的工作流。"
fi
SYSTEM_MSG="🔄 dev-loop 迭代 $NEXT_ITERATION | 阶段: $PHASE"

jq -n \
    --arg prompt "$PROMPT" \
    --arg msg "$SYSTEM_MSG" \
    '{
        "decision": "block",
        "reason": $prompt,
        "systemMessage": $msg
    }'

exit 0
