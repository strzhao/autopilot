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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

# compress_qa_report — 压缩状态文件 ## QA 报告 区域的历史轮次
#
# 行为：保留最新一轮（### 轮次 N）完整内容，将之前所有轮次压缩为单行摘要：
#   ### 轮次 N (时间) — ✅/❌ 简要
# 状态符号从该块首行（紧跟标题之后第一个非空行）的 ✅/❌ emoji 推断，
# 摘要文本截取该首行剩余内容前 60 个字符。
#
# 不影响 ## QA 报告 之外的 section（## 设计文档 / ## 变更日志 等保持不变）。
# 失败不阻断 stop-hook（调用方使用 || true 兜底）。
# 函数幂等：对已经只剩单轮 + N 行摘要的文件再次调用结果不变。
compress_qa_report() {
    local state_file="$1"
    [ -f "$state_file" ] || return 0

    local tmp="${state_file}.compressed.$$"

    awk '
        BEGIN {
            in_qa = 0          # 当前是否在 ## QA 报告 section
            round_count = 0    # 已遇到的 ### 轮次 N 总数
            buffered = 0       # 当前 round 缓冲区是否已积累内容
        }

        # 刷新缓冲：如果是最后一轮（last_round=1）保留完整；否则压缩为一行摘要
        function flush_buffer(last_round,    i, status, summary, line, header) {
            if (!buffered) return
            if (last_round) {
                print round_header
                for (i = 1; i <= buf_n; i++) print buf_lines[i]
            } else {
                status = "✅"
                summary = ""
                for (i = 1; i <= buf_n; i++) {
                    line = buf_lines[i]
                    # 跳过空行寻找首个有内容的行
                    if (line ~ /^[[:space:]]*$/) continue
                    if (index(line, "❌") > 0) status = "❌"
                    else if (index(line, "✅") > 0) status = "✅"
                    summary = line
                    break
                }
                # 摘要截断到 60 字符（按字节，足够中文 ~20 字）
                if (length(summary) > 60) summary = substr(summary, 1, 60)
                # 若 round_header 已包含 — 状态 简要 形式（之前压缩过），保留原样
                if (round_header ~ /— [✅❌]/) {
                    print round_header
                } else {
                    if (summary == "") {
                        print round_header " — " status " 简要"
                    } else {
                        # 清理 summary 中的 markdown 标记前缀（- / ### / **）
                        gsub(/^[[:space:]]*[-*#]+[[:space:]]*/, "", summary)
                        gsub(/\*\*/, "", summary)
                        # 去掉 summary 中重复的状态 emoji（避免 — ❌ ❌ ... 形式）
                        gsub(/[✅❌][[:space:]]*/, "", summary)
                        gsub(/^[[:space:]]+/, "", summary)
                        print round_header " — " status " " summary
                    }
                }
            }
            buffered = 0
            buf_n = 0
        }

        {
            line = $0

            # 检测 ## QA 报告 section 起始
            if (line ~ /^## QA 报告[[:space:]]*$/) {
                in_qa = 1
                print line
                next
            }

            # 不在 QA 报告区：照常输出
            if (!in_qa) {
                print line
                next
            }

            # 在 QA 报告区遇到下一个 ## section（不是 ###）→ 结束 QA 区
            if (line ~ /^## / && line !~ /^## QA 报告/) {
                # 刷出最后一轮（保留完整）
                flush_buffer(1)
                in_qa = 0
                print line
                next
            }

            # 在 QA 报告区遇到 ### 轮次 N
            if (line ~ /^### 轮次/) {
                # 先把上一轮按"非最后一轮"处理（压缩）
                if (buffered) flush_buffer(0)
                round_header = line
                round_count++
                buffered = 1
                buf_n = 0
                next
            }

            # 在 QA 报告区累积当前轮次内容
            if (buffered) {
                buf_n++
                buf_lines[buf_n] = line
            } else {
                # ## QA 报告 标题与首个 ### 轮次 之间的内容（说明文字等）原样输出
                print line
            }
        }

        END {
            # 文件结束时如还在 QA 区且有缓冲，flush 为最后一轮（保留完整）
            if (in_qa && buffered) flush_buffer(1)
        }
    ' "$state_file" > "$tmp" 2>/dev/null && mv "$tmp" "$state_file" || rm -f "$tmp"
}

# detect_smoke_eligible — 检测当前 diff 是否满足 smoke QA 条件，满足则设置 qa_scope=smoke
#
# 触发路径：
#   路径 A — fast_mode=true 且 diff ≤ 100 行 / ≤ 8 文件且无依赖变更 → smoke
#   路径 B — fast_mode=true 但 diff 太大或含依赖 → 降级 fast_mode=false
#   路径 C — 标准模式 diff ≤ 30 行 AND ≤ 3 文件且无依赖变更 → smoke
#
# $1（可选）：mock diff 文件路径（红队测试用）。生产留空时跑 `git diff --stat HEAD`。
# 副作用：通过 set_field / append_changelog 修改全局 STATE_FILE 状态文件
# 失败不阻断 stop-hook（调用方使用 || true 兜底）
detect_smoke_eligible() {
    local diff_input="${1:-}"

    # qa_scope 已有值（如 "selective"）时不重复评估
    [[ -n "$(get_field qa_scope)" ]] && return 0

    local diff_lines=0 diff_files=0 has_deps=0

    if [[ -n "$diff_input" ]] && [[ -f "$diff_input" ]]; then
        # 测试模式：从传入文件解析 mock raw diff
        diff_lines=$(grep -cE '^[+-][^+-]' "$diff_input" 2>/dev/null || echo 0)
        diff_files=$(grep -cE '^diff --git' "$diff_input" 2>/dev/null || echo 0)
        if grep -qE '(package\.json|pnpm-lock|yarn\.lock|requirements\.txt|Cargo\.lock)' "$diff_input" 2>/dev/null; then
            has_deps=1
        fi
    else
        # 生产模式：git diff --stat
        local stat_output
        stat_output=$(git diff --stat HEAD 2>/dev/null) || return 0
        [[ -z "$stat_output" ]] && return 0
        diff_lines=$(echo "$stat_output" | tail -1 | grep -oE '[0-9]+ insertion|[0-9]+ deletion' | grep -oE '[0-9]+' | awk '{s+=$1} END{print s+0}')
        diff_files=$(echo "$stat_output" | grep -cE '^\s+\S+\s+\|\s+[0-9]+')
        if echo "$stat_output" | grep -qE '(package\.json|pnpm-lock|yarn\.lock|requirements\.txt|Cargo\.lock)'; then
            has_deps=1
        fi
    fi

    local fast_mode
    fast_mode=$(get_field fast_mode || true)

    # 路径 A — fast_mode=true 且全部阈值内（≤100行/≤8文件/无依赖）→ smoke + 保持 fast_mode
    if [[ "$fast_mode" == "true" ]] && [[ "$has_deps" -eq 0 ]] && [[ "${diff_lines:-999}" -le 100 ]] && [[ "${diff_files:-999}" -le 8 ]]; then
        set_field "qa_scope" '"smoke"'
        append_changelog "stop-hook: fast_mode=true 且 diff 在阈值内（${diff_lines}行/${diff_files}文件），启用 smoke QA"
        return 0
    fi

    # 路径 B — fast_mode=true 但任一阈值超出（行/文件/依赖）→ 降级 fast_mode
    if [[ "$fast_mode" == "true" ]] && { [[ "${diff_lines:-0}" -gt 100 ]] || [[ "${diff_files:-0}" -gt 8 ]] || [[ "$has_deps" -eq 1 ]]; }; then
        set_field "fast_mode" "false"
        append_changelog "stop-hook: fast_mode 降级（${diff_lines}行/${diff_files}文件/含依赖=${has_deps}），QA 走全量"
        return 0
    fi

    # 路径 C — 标准模式：严格阈值，diff ≤ 30 行 AND ≤ 3 文件 AND 无依赖
    if [[ "$has_deps" -eq 0 ]] && [[ "${diff_lines:-999}" -le 30 ]] && [[ "${diff_files:-999}" -le 3 ]]; then
        set_field "qa_scope" '"smoke"'
        append_changelog "stop-hook: 自动检测 diff 体积小（${diff_lines}行/${diff_files}文件），启用 smoke QA"
    fi
}

# 支持 source 加载模式：被 source 时只导出函数定义（compress_qa_report 等），
# 不执行 main 逻辑。这让外部测试可以单独验证函数行为。
# 直接执行（bash stop-hook.sh）时 BASH_SOURCE[0] == $0，正常往下走。
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    return 0 2>/dev/null || exit 0
fi

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
        rm -f "$(get_active_file)"
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
                rm -f "$(get_active_file)"
                exit 0
            fi
        else
            bash "$SCRIPT_DIR/notify.sh" project-design-complete 2>/dev/null || true
            rm -f "$(get_active_file)"
            exit 0
        fi

    # Case 1: AI 信号了下一个任务 → 自动链接
    elif [[ -n "$NEXT_TASK" ]] && [[ -f "$DAG_FILE" ]]; then
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
            rm -f "$(get_active_file)"
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
            rm -f "$(get_active_file)"
            exit 0
        fi
    # Case 3: 单任务模式 → 正常清理（保留 requirements 文件夹，移除 active 指针）
    else
        bash "$SCRIPT_DIR/notify.sh" complete 2>/dev/null || true
        rm -f "$(get_active_file)"
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
    rm -f "$(get_active_file)"
    exit 0
fi

# ── 8. 递增 iteration（自动链接创建的新状态文件跳过递增） ──

if [[ "$SKIP_INCREMENT" -eq 0 ]]; then
    NEXT_ITERATION=$((ITERATION + 1))
    set_field "iteration" "$NEXT_ITERATION"
else
    NEXT_ITERATION="$ITERATION"
fi

# ── 8.5 在 phase 转入 qa/auto-fix 时压缩 QA 报告历史轮次 ──
# 失败不阻断 stop-hook，使用 || true 兜底
NEW_PHASE=$(get_field "phase" || true)
if [[ "$NEW_PHASE" == "qa" ]] || [[ "$NEW_PHASE" == "auto-fix" ]]; then
    compress_qa_report "$STATE_FILE" || true
fi
# 单独的 qa 触发点（不在 auto-fix 触发，避免重复评估）
if [[ "$NEW_PHASE" == "qa" ]]; then
    detect_smoke_eligible || true
fi

# ── 9. 构造 block JSON ──
# 注意：macOS bash 3.2 有 multibyte bug，$VAR 后紧跟全角标点会吞掉变量值。
# 所有变量必须用 ${VAR} 花括号界定。

# design 阶段使用 Plan Mode（auto_approve 时跳过 Plan Mode）
AUTO_APPROVE=$(get_field "auto_approve" || true)
PLAN_MODE=$(get_field "plan_mode" || true)
FAST_MODE=$(get_field "fast_mode" || true)
if [[ "$PHASE" == "design" ]]; then
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        PROMPT="读取 ${STATE_FILE} 状态文件获取目标描述. auto_approve=true: 跳过 Plan Mode, 直接写设计文档到状态文件. ⚠️ 必须使用 Agent 工具启动 plan-reviewer sub-agent (model: sonnet) 审查设计方案, 参见 references/plan-reviewer-prompt.md. 审查通过则推进到 implement; 失败则回退到正常 Plan Mode (设置 auto_approve: false). 按照 autopilot skill 的 Phase: design 指引执行."
    elif [[ "$PLAN_MODE" == "deep" ]]; then
        PROMPT="读取 ${STATE_FILE} 状态文件获取目标描述. plan_mode=deep: 先执行 Deep Design 交互探索流程（参见 references/deep-design-guide.md），包括项目上下文探索、视觉伴侣征求、逐个澄清问题(AskUserQuestion)、提出 2-3 种方案. 交互探索完成后再调用 EnterPlanMode 写正式设计文档. ⚠️ 在 ExitPlanMode 之前, 必须使用 Agent 工具启动 plan-reviewer sub-agent (model: sonnet) 审查设计方案, 参见 references/plan-reviewer-prompt.md. 审查通过再 ExitPlanMode. 产出物写入 task_dir: $(get_field 'task_dir'). 按照 autopilot skill 的 Phase: design 指引执行."
    elif [[ "$FAST_MODE" == "true" ]]; then
        PROMPT="读取 ${STATE_FILE} 状态文件获取目标描述, fast_mode=true: 立即调用 EnterPlanMode 工具进入 Plan Mode. 设计阶段只用 1 个 Explore agent, 不启动 scenario-generator Agent, 不启动 plan-reviewer Agent — 编排器对 plan file 按 references/plan-reviewer-prompt.md 中的 6 维度自审（需求完整性/技术可行性/任务分解/验证方案/风险/范围控制）, 自审通过后直接 ExitPlanMode. 详见 SKILL.md Fast Mode 快速路径章节. 按照 autopilot skill 的 Phase: design 指引执行."
    else
        PROMPT="读取 ${STATE_FILE} 状态文件获取目标描述, 然后立即调用 EnterPlanMode 工具进入 Plan Mode. 不要在调用 EnterPlanMode 之前做任何代码探索. 所有探索和设计工作必须在 Plan Mode 内完成. ⚠️ 在 ExitPlanMode 之前, 必须使用 Agent 工具启动 plan-reviewer sub-agent (model: sonnet) 审查设计方案, 参见 references/plan-reviewer-prompt.md. 审查通过再 ExitPlanMode. 按照 autopilot skill 的 Phase: design 指引执行."
    fi
elif [[ "$PHASE" == "implement" ]]; then
    PROMPT="读取 ${STATE_FILE} 状态文件, 当前阶段: implement, 迭代: ${NEXT_ITERATION}. ⚠️ 红蓝对抗铁律: (1) 从状态文件读取设计文档, 检查是否有领域 Skill 委托; (2) 无委托时必须使用 Agent 工具在同一轮响应中同时启动蓝队和红队两个并行 sub-agent (model: sonnet), prompt 模板参见 references/blue-team-prompt.md 和 references/red-team-prompt.md; (3) 红队绝对不能读取蓝队新写的实现代码——红队只看设计文档; (4) 两个 Agent 都完成后合流: 收集产出、写入红队测试文件、更新状态文件. 详细工作流参见 references/implement-phase.md. 按照 autopilot skill 的 Phase: implement 指引执行."
elif [[ "$PHASE" == "qa" ]]; then
    QA_SCOPE=$(get_field "qa_scope" || true)
    if [[ "$QA_SCOPE" == "smoke" ]]; then
        PROMPT="读取 ${STATE_FILE} 状态文件, 当前阶段: qa (smoke), 迭代: ${NEXT_ITERATION}. ⚠️ smoke QA: 只执行 Wave 1 (Tier 0/1 红队验收测试 + 类型/Lint/单元/构建) + Wave 1.5 真实测试场景, 不启动 qa-reviewer Agent — 编排器自行 Read git diff 后内联做 3 项自审 (设计符合性 / OWASP 关键 / 代码质量明显问题). Tier 1.5 铁律不变: 必须执行设计文档每一个真实测试场景, 场景计数匹配 E≥N. 按照 autopilot skill 的指引执行."
    else
        PROMPT="读取 ${STATE_FILE} 状态文件, 当前阶段: qa, 迭代: ${NEXT_ITERATION}. ⚠️ Tier 1.5 铁律: (1) 必须执行设计文档中的每一个真实测试场景, 不允许跳过任何场景; (2) 结果判定前先做场景计数匹配——统计报告中执行:标记数量 E 与设计文档场景总数 N, E<N 则有场景被跳过, 必须补做. 按照 autopilot skill 的指引执行当前阶段的工作流."
    fi
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
