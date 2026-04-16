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
# shellcheck source=./lib.sh
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

# ── 5. phase=done → 完成清理 / 自动链接 ──

SKIP_INCREMENT=0

if [[ "$PHASE" == "done" ]]; then
    # 知识提取守卫：AI 跳过知识提取直接设 done → 回滚到 merge
    KNOWLEDGE_EXTRACTED=$(get_field "knowledge_extracted" || true)
    if [[ "$KNOWLEDGE_EXTRACTED" != "true" ]] && [[ "$KNOWLEDGE_EXTRACTED" != "skipped" ]]; then
        # 豁免：无代码变更的阶段不需要知识提取
        MODE_CHECK=$(get_field "mode" || true)
        BRIEF_CHECK=$(get_field "brief_file" || true)
        if { [[ "$MODE_CHECK" == "project" ]] && [[ -z "$BRIEF_CHECK" ]]; } || [[ "$MODE_CHECK" == "project-qa" ]]; then
            set_field "knowledge_extracted" '"skipped"'
        else
            set_field "phase" '"merge"'
            NEXT_ITERATION=$((ITERATION + 1))
            set_field "iteration" "$NEXT_ITERATION"
            PROMPT="你跳过了知识提取步骤。读取 ${STATE_FILE}，按照 autopilot skill Phase: merge 的知识提取与沉淀步骤执行。完成后用 Edit 设置 knowledge_extracted 为 true（有新增）或 skipped（无新增），然后再设 phase: done。"
            jq -n --arg prompt "$PROMPT" --arg msg "autopilot iteration ${NEXT_ITERATION} | phase: merge | 知识提取回滚" \
                '{"decision":"block","reason":$prompt,"systemMessage":$msg}'
            exit 0
        fi
    fi

    MODE=$(get_field "mode" || true)

    # Case 0: project-qa 完成 → 项目完成通知 + 清理 active 指针
    if [[ "$MODE" == "project-qa" ]]; then
        bash "$SCRIPT_DIR/notify.sh" project-complete 2>/dev/null || true
        rm -f "$PROJECT_ROOT/.autopilot/active"
        exit 0
    fi

    NEXT_TASK=$(get_field "next_task" || true)
    BRIEF_FILE=$(get_field "brief_file" || true)
    DAG_FILE="$PROJECT_ROOT/.autopilot/project/dag.yaml"

    # Case 0.5: 项目模式设计完成（非子任务）→ 自动启动首个就绪任务
    if [[ "$MODE" == "project" ]] && [[ -z "$BRIEF_FILE" ]] && [[ -f "$DAG_FILE" ]]; then
        FIRST_READY=$(get_first_ready_task "$DAG_FILE")
        if [[ -n "$FIRST_READY" ]] && [[ "$FIRST_READY" != "ALL_DONE" ]]; then
            TASK_FILE="$PROJECT_ROOT/.autopilot/project/tasks/${FIRST_READY}.md"
            if [[ -f "$TASK_FILE" ]]; then
                new_slug=$(generate_task_slug "$FIRST_READY")
                setup_requirement_dir "$new_slug"
                TASK_FILE_ABS=$(cd "$(dirname "$TASK_FILE")" && pwd)/$(basename "$TASK_FILE")
                create_brief_state_file "$TASK_FILE_ABS" "$HOOK_SESSION" "30" "3" "true"
                bash "$SCRIPT_DIR/notify.sh" auto-chain 2>/dev/null || true
                echo "🔗 project-design → ${FIRST_READY}" >&2
                PHASE=$(get_field "phase" || true)
                ITERATION=$(get_field "iteration" || true)
                MAX_ITERATIONS=$(get_field "max_iterations" || true)
                SKIP_INCREMENT=1
                # 落入下方 block JSON 构造
            else
                bash "$SCRIPT_DIR/notify.sh" project-design-complete 2>/dev/null || true
                rm -f "$PROJECT_ROOT/.autopilot/active"
                exit 0
            fi
        else
            bash "$SCRIPT_DIR/notify.sh" project-design-complete 2>/dev/null || true
            rm -f "$PROJECT_ROOT/.autopilot/active"
            exit 0
        fi
    fi

    # Case 1: AI 信号了下一个任务 → 自动链接
    if [[ -n "$NEXT_TASK" ]] && [[ -f "$DAG_FILE" ]]; then
        TASK_FILE="$PROJECT_ROOT/.autopilot/project/tasks/${NEXT_TASK}.md"
        if [[ -f "$TASK_FILE" ]]; then
            # 为新任务创建新的 requirements 文件夹
            new_slug=$(generate_task_slug "$NEXT_TASK")
            setup_requirement_dir "$new_slug"
            TASK_FILE_ABS=$(cd "$(dirname "$TASK_FILE")" && pwd)/$(basename "$TASK_FILE")
            create_brief_state_file "$TASK_FILE_ABS" "$HOOK_SESSION" "30" "3" "true"
            bash "$SCRIPT_DIR/notify.sh" auto-chain 2>/dev/null || true
            echo "🔗 auto-chain: ${NEXT_TASK}" >&2
            # 重新读取新状态文件的字段
            PHASE=$(get_field "phase" || true)
            ITERATION=$(get_field "iteration" || true)
            MAX_ITERATIONS=$(get_field "max_iterations" || true)
            SKIP_INCREMENT=1
            # 落入下方 block JSON 构造
        else
            echo "⚠️  autopilot: next_task file not found: ${TASK_FILE}" >&2
            bash "$SCRIPT_DIR/notify.sh" complete 2>/dev/null || true
            rm -f "$PROJECT_ROOT/.autopilot/active"
            exit 0
        fi
    # Case 2: 项目子任务完成 + 无 next_task → 检查是否全部完成
    elif [[ -n "$BRIEF_FILE" ]] && [[ -f "$DAG_FILE" ]]; then
        RESULT=$(get_first_ready_task "$DAG_FILE")
        if [[ "$RESULT" == "ALL_DONE" ]]; then
            # 全部完成 → 启动全项目 QA，创建新的 requirements 文件夹
            qa_slug=$(generate_task_slug "全项目集成QA验证")
            setup_requirement_dir "$qa_slug"
            create_project_qa_state_file "$HOOK_SESSION"
            bash "$SCRIPT_DIR/notify.sh" project-qa 2>/dev/null || true
            echo "🏁 所有任务已完成，启动全项目 QA" >&2
            PHASE=$(get_field "phase" || true)
            ITERATION=$(get_field "iteration" || true)
            MAX_ITERATIONS=$(get_field "max_iterations" || true)
            SKIP_INCREMENT=1
            # 落入下方 block JSON 构造
        else
            # 还有任务但 AI 未信号高信心 → 释放，等用户操作
            bash "$SCRIPT_DIR/notify.sh" complete 2>/dev/null || true
            rm -f "$PROJECT_ROOT/.autopilot/active"
            exit 0
        fi
    # Case 3: 单任务模式 → 正常清理（保留 requirements 文件夹，移除 active 指针）
    else
        bash "$SCRIPT_DIR/notify.sh" complete 2>/dev/null || true
        rm -f "$PROJECT_ROOT/.autopilot/active"
        exit 0
    fi
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
    rm -f "$PROJECT_ROOT/.autopilot/active"
    exit 0
fi

# ── 8. 递增 iteration（自动链接创建的新状态文件跳过递增） ──

if [[ "$SKIP_INCREMENT" -eq 0 ]]; then
    NEXT_ITERATION=$((ITERATION + 1))
    set_field "iteration" "$NEXT_ITERATION"
else
    NEXT_ITERATION="$ITERATION"
fi

# ── 9. 构造 block JSON ──
# 注意：macOS bash 3.2 有 multibyte bug，$VAR 后紧跟全角标点会吞掉变量值。
# 所有变量必须用 ${VAR} 花括号界定。

# design 阶段使用 Plan Mode（auto_approve 时跳过 Plan Mode）
AUTO_APPROVE=$(get_field "auto_approve" || true)
PLAN_MODE=$(get_field "plan_mode" || true)
if [[ "$PHASE" == "design" ]]; then
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        PROMPT="读取 ${STATE_FILE} 状态文件获取目标描述. auto_approve=true: 跳过 Plan Mode, 直接写设计文档到状态文件. 运行 plan-reviewer agent 审查, 通过则直接推进到 implement; 失败则回退到正常 Plan Mode (设置 auto_approve: false). 按照 autopilot skill 的 Phase: design 指引执行."
    elif [[ "$PLAN_MODE" == "deep" ]]; then
        PROMPT="读取 ${STATE_FILE} 状态文件获取目标描述. plan_mode=deep: 先执行 Deep Design 交互探索流程（参见 references/deep-design-guide.md），包括项目上下文探索、视觉伴侣征求、逐个澄清问题(AskUserQuestion)、提出 2-3 种方案. 交互探索完成后再调用 EnterPlanMode 写正式设计文档. 产出物写入 task_dir: $(get_field 'task_dir'). 按照 autopilot skill 的 Phase: design 指引执行."
    else
        PROMPT="读取 ${STATE_FILE} 状态文件获取目标描述, 然后立即调用 EnterPlanMode 工具进入 Plan Mode. 不要在调用 EnterPlanMode 之前做任何代码探索. 所有探索和设计工作必须在 Plan Mode 内完成. 按照 autopilot skill 的 Phase: design 指引执行."
    fi
elif [[ "$PHASE" == "qa" ]]; then
    PROMPT="读取 ${STATE_FILE} 状态文件, 当前阶段: qa, 迭代: ${NEXT_ITERATION}. ⚠️ Tier 1.5 铁律: (1) 必须执行设计文档中的每一个真实测试场景, 不允许跳过任何场景; (2) 结果判定前先做场景计数匹配——统计报告中执行:标记数量 E 与设计文档场景总数 N, E<N 则有场景被跳过, 必须补做. 按照 autopilot skill 的指引执行当前阶段的工作流."
elif [[ "$PHASE" == "merge" ]]; then
    PROMPT="读取 ${STATE_FILE} 状态文件, 当前阶段: merge, 迭代: ${NEXT_ITERATION}. ⚠️ merge 阶段必须使用 Agent 工具启动 commit-agent (model: sonnet), 参见 references/commit-agent-prompt.md 模板. 不要使用 Skill: autopilot-commit. 完成知识提取后, 用 Edit 设置 knowledge_extracted 为 true 或 skipped, 再设 phase: done. 按照 autopilot skill 的 Phase: merge 指引执行."
else
    PROMPT="读取 ${STATE_FILE} 状态文件, 当前阶段: ${PHASE}, 迭代: ${NEXT_ITERATION}. 按照 autopilot skill 的指引执行当前阶段的工作流."
fi
MODE=$(get_field "mode" || true)
SYSTEM_MSG="autopilot iteration ${NEXT_ITERATION} | phase: ${PHASE}${MODE:+ | mode: $MODE}"

jq -n \
    --arg prompt "$PROMPT" \
    --arg msg "$SYSTEM_MSG" \
    '{
        "decision": "block",
        "reason": $prompt,
        "systemMessage": $msg
    }'

exit 0
