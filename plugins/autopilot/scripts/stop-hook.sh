#!/bin/bash

# autopilot Stop Hook — 阶段状态机循环引擎
# 基于 ralph-loop 的 Stop hook 模式，增加阶段状态机和审批门逻辑
#
# 行为:
#   1. 状态文件不存在 → 放行
#   2. session_id 不匹配 → 放行
#   3. gate 非空（审批门） → 发通知 + 放行（等待用户审批）
#   4. phase=done → 清理 + 放行
#   5. 超过 max_iterations → 清理 + 放行
#   6. 其他 → block + 注入阶段 prompt，继续循环

# 安全策略：Stop hook 中任何未预期的错误都应放行（exit 0），
# 只有明确需要 block 时才输出 JSON。避免 set -e 导致意外非零退出。
trap 'exit 0' ERR

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# ── 0. 快速退出：状态文件不存在时直接放行，避免读 stdin 阻塞 ──

if [[ ! -f "$STATE_FILE" ]]; then
    exit 0
fi

# 读取 hook 输入（带超时保护，防止 stdin 未关闭导致挂起）
HOOK_INPUT=$(timeout 5 cat 2>/dev/null || true)

# ── 2. 解析 frontmatter ──

PHASE=$(get_field "phase" || true)
GATE=$(get_field "gate" || true)
ITERATION=$(get_field "iteration" || true)
MAX_ITERATIONS=$(get_field "max_iterations" || true)
STATE_SESSION=$(get_field "session_id" || true)

# ── 3. Session 隔离 ──

HOOK_SESSION=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)
if [[ -n "$STATE_SESSION" ]] && [[ "$STATE_SESSION" != "$HOOK_SESSION" ]]; then
    exit 0
fi

# ── 4. 数值校验 ──

if [[ ! "$ITERATION" =~ ^[0-9]+$ ]]; then
    echo "⚠️  autopilot: 状态文件损坏 (iteration: '$ITERATION')" >&2
    rm "$STATE_FILE"
    exit 0
fi

if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
    echo "⚠️  autopilot: 状态文件损坏 (max_iterations: '$MAX_ITERATIONS')" >&2
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
    echo "🛑 autopilot: 达到最大迭代次数 ($MAX_ITERATIONS)。" >&2
    bash "$SCRIPT_DIR/notify.sh" error 2>/dev/null || true
    rm "$STATE_FILE"
    exit 0
fi

# ── 8. 递增 iteration ──

NEXT_ITERATION=$((ITERATION + 1))
set_field "iteration" "$NEXT_ITERATION"

# ── 9. 构造 block JSON ──

# design 阶段使用 Plan Mode
if [[ "$PHASE" == "design" ]]; then
    PROMPT="读取 $STATE_FILE 状态文件获取目标描述，然后立即调用 EnterPlanMode 工具进入 Plan Mode。不要在调用 EnterPlanMode 之前做任何代码探索。所有探索和设计工作必须在 Plan Mode 内完成。按照 autopilot skill 的 Phase: design 指引执行。"
else
    PROMPT="读取 $STATE_FILE 状态文件，当前阶段: $PHASE，迭代: $NEXT_ITERATION。按照 autopilot skill 的指引执行当前阶段的工作流。"
fi
SYSTEM_MSG="🔄 autopilot 迭代 $NEXT_ITERATION | 阶段: $PHASE"

jq -n \
    --arg prompt "$PROMPT" \
    --arg msg "$SYSTEM_MSG" \
    '{
        "decision": "block",
        "reason": $prompt,
        "systemMessage": $msg
    }'

exit 0
