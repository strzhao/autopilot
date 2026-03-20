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

# ── 0. 先读 stdin，提取 cwd 后再初始化路径 ──
# Stop hook 的 stdin JSON 包含 cwd 字段，是 Claude Code 的实际工作目录。
# 在 worktree 场景下 hook 脚本的 shell CWD 可能不是项目目录，
# 必须用 stdin 中的 cwd 来正确定位状态文件。

HOOK_INPUT=$(timeout 5 cat 2>/dev/null || true)
HOOK_CWD=$(echo "$HOOK_INPUT" | jq -r '.cwd // ""' 2>/dev/null || true)

# 用 stdin 的 cwd 初始化路径（为空时 fallback 到当前 CWD）
init_paths "$HOOK_CWD"

# 状态文件不存在时直接放行
if [[ ! -f "$STATE_FILE" ]]; then
    exit 0
fi

# ── 2. 解析 frontmatter ──

PHASE=$(get_field "phase" || true)
GATE=$(get_field "gate" || true)
ITERATION=$(get_field "iteration" || true)
MAX_ITERATIONS=$(get_field "max_iterations" || true)
STATE_SESSION=$(get_field "session_id" || true)

# ── 3. Session 隔离（Ralph 兼容 + 首次认领） ──

HOOK_SESSION=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)

# Guard 1: 空 STATE_SESSION → 首次认领
# setup.sh 在 CLAUDE_CODE_SESSION_ID 不可用时写入空值（与 ralph 一致）。
# 首次 Stop hook 触发时，用真实 session_id 认领状态文件，建立隔离。
if [[ -z "$STATE_SESSION" ]]; then
    if [[ -n "$HOOK_SESSION" ]]; then
        set_field "session_id" "$HOOK_SESSION"
        STATE_SESSION="$HOOK_SESSION"
        # 继续执行，不 exit — session 已认领
    fi
    # HOOK_SESSION 也为空时继续执行（与 ralph 的空值跳过隔离一致）
fi

# Guard 2: 非空且不匹配 → 不同会话，放行
if [[ -n "$STATE_SESSION" ]] && [[ "$STATE_SESSION" != "$HOOK_SESSION" ]]; then
    exit 0
fi

# ── 4. 数值校验（缺失时自动修复，不删除文件） ──

if [[ ! "$ITERATION" =~ ^[0-9]+$ ]]; then
    echo "⚠️  autopilot: iteration 字段缺失或无效 ('$ITERATION')，自动修复为 1" >&2
    ITERATION=1
    # 尝试修复状态文件：如果字段存在但值非法则修正，如果字段不存在则注入
    if grep -q "^iteration:" "$STATE_FILE" 2>/dev/null; then
        set_field "iteration" "1"
    else
        sed -i.bak '/^phase:/a\
iteration: 1' "$STATE_FILE" && rm -f "${STATE_FILE}.bak"
    fi
fi

if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
    echo "⚠️  autopilot: max_iterations 字段缺失或无效 ('$MAX_ITERATIONS')，自动修复为 30" >&2
    MAX_ITERATIONS=30
    if grep -q "^max_iterations:" "$STATE_FILE" 2>/dev/null; then
        set_field "max_iterations" "30"
    else
        sed -i.bak '/^iteration:/a\
max_iterations: 30' "$STATE_FILE" && rm -f "${STATE_FILE}.bak"
    fi
fi

# ── 5. phase=done → 知识提取守卫 + 完成清理 ──

if [[ "$PHASE" == "done" ]]; then
    KE=$(get_field "knowledge_extracted" || true)
    if [[ "$KE" != "true" ]] && [[ "$KE" != "skipped" ]]; then
        # 知识提取未完成，回滚到 merge 阶段
        set_field "phase" "merge"
        NEXT_ITERATION=$((ITERATION + 1))
        set_field "iteration" "$NEXT_ITERATION"
        KE_PROMPT="你跳过了知识提取步骤. 读取 ${STATE_FILE} 状态文件, 按照 autopilot skill Phase: merge 的 Step 2 执行知识提取与沉淀. 完成后用 Edit 设置 knowledge_extracted 为 true 或 skipped, 然后再设 phase: done."
        KE_MSG="autopilot iteration ${NEXT_ITERATION} | phase: merge (知识提取回滚)"
        jq -n \
            --arg prompt "$KE_PROMPT" \
            --arg msg "$KE_MSG" \
            '{
                "decision": "block",
                "reason": $prompt,
                "systemMessage": $msg
            }'
        exit 0
    fi
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
# 注意：macOS bash 3.2 有 multibyte bug，$VAR 后紧跟全角标点会吞掉变量值。
# 所有变量必须用 ${VAR} 花括号界定。

# design 阶段使用 Plan Mode
if [[ "$PHASE" == "design" ]]; then
    PROMPT="读取 ${STATE_FILE} 状态文件获取目标描述. 如果项目中存在 .claude/knowledge/ 目录, 先 Read decisions.md 和 patterns.md 加载相关知识上下文. 然后立即调用 EnterPlanMode 工具进入 Plan Mode. 不要在调用 EnterPlanMode 之前做任何代码探索. 所有探索和设计工作必须在 Plan Mode 内完成. 按照 autopilot skill 的 Phase: design 指引执行."
else
    PROMPT="读取 ${STATE_FILE} 状态文件, 当前阶段: ${PHASE}, 迭代: ${NEXT_ITERATION}. 按照 autopilot skill 的指引执行当前阶段的工作流."
fi
SYSTEM_MSG="autopilot iteration ${NEXT_ITERATION} | phase: ${PHASE}"

jq -n \
    --arg prompt "$PROMPT" \
    --arg msg "$SYSTEM_MSG" \
    '{
        "decision": "block",
        "reason": $prompt,
        "systemMessage": $msg
    }'

exit 0
