#!/bin/bash

# autopilot 初始化 / 子命令路由脚本
# 用法:
#   /autopilot <目标描述>                   启动新的 autopilot 闭环
#   /autopilot commit                       智能提交
#   /autopilot approve [反馈]               批准当前审批门
#   /autopilot revise <反馈>                要求修改当前阶段产出
#   /autopilot status                       查看当前状态
#   /autopilot cancel                       取消并清理
#   /autopilot doctor [--fix]                工程健康度诊断
#   /autopilot --help                       显示帮助

set -uo pipefail
# 注意：不用 set -e，因为此脚本通过 SKILL.md 的 !`command` 机制调用，
# 非零退出码会阻止整个 skill 加载。所有错误通过 stdout 输出让 AI 处理。

source "$(dirname "$0")/lib.sh"
init_paths "" "$PPID"

# 启动时清理过期的 active 文件（PID 不存在的）
cleanup_stale_actives

# ── 早期迁移：.claude/autopilot.local.md → .autopilot/ 旧格式检测 ──
# 旧版状态文件在 .autopilot/autopilot.local.md（无 active 指针），需要检测处理
if [[ -f "$PROJECT_ROOT/.autopilot/autopilot.local.md" ]] && [[ ! -f "$PROJECT_ROOT/.autopilot/active" ]]; then
    OLD_PHASE=$(get_field "phase" 2>/dev/null || true)
    if [[ "$OLD_PHASE" == "done" || -z "$OLD_PHASE" ]]; then
        rm -f "$PROJECT_ROOT/.autopilot/autopilot.local.md"
        echo "🧹 清理了旧格式的 autopilot 状态文件。"
    else
        echo "⚠️ 检测到旧格式活跃状态文件 .autopilot/autopilot.local.md（阶段: ${OLD_PHASE}）"
        echo "   请先手动处理（删除或完成），再启动新的 autopilot。"
        exit 0
    fi
fi
# 从 .claude/ 迁移的旧逻辑保留兼容
if [[ -f "$PROJECT_ROOT/.claude/autopilot.local.md" ]] && [[ ! -f "$PROJECT_ROOT/.autopilot/active" ]]; then
    mkdir -p "$PROJECT_ROOT/.autopilot"
    rm -f "$PROJECT_ROOT/.claude/autopilot.local.md"
    echo "🧹 清理了 .claude/ 下的旧状态文件。"
fi

# ── 早期迁移：.claude/worktree-links → .autopilot/worktree-links ──
if [[ -f "$PROJECT_ROOT/.claude/worktree-links" ]] && [[ ! -f "$PROJECT_ROOT/.autopilot/worktree-links" ]]; then
    mkdir -p "$PROJECT_ROOT/.autopilot"
    if mv "$PROJECT_ROOT/.claude/worktree-links" "$PROJECT_ROOT/.autopilot/worktree-links"; then
        echo "📦 worktree-links 迁移: .claude/worktree-links → .autopilot/worktree-links"
    fi
fi

# ── 参数安全处理 ──────────────────────────────────────────────
# SKILL.md 用 '$ARGUMENTS' 单引号传参（防止 zsh glob/brace 展开），
# 导致所有参数合并为单个字符串。这里重新按空格拆分恢复原始行为。
if [[ $# -eq 1 && "$1" == *" "* ]]; then
    read -ra _SPLIT_ARGS <<< "$1"
    set -- "${_SPLIT_ARGS[@]}"
fi

# ── 子命令路由 ──────────────────────────────────────────────

FIRST_ARG="${1:-}"

case "$FIRST_ARG" in
    -h|--help)
        cat << 'HELP_EOF'
autopilot — AI 自动驾驶工程套件

用法:
  /autopilot <目标描述> [选项]           启动全流程闭环（红蓝对抗）
  /autopilot <任务ID>                    匹配项目任务文件，brief 模式执行
  /autopilot commit                      智能提交（React 优化 + 代码测验）
  /autopilot doctor [--fix]              工程健康度诊断（评估 autopilot 兼容性）
  /autopilot approve [反馈]              批准当前审批门
  /autopilot revise <反馈>               要求修改
  /autopilot status                      查看状态（有项目时显示 DAG）
  /autopilot next                        查找就绪任务
  /autopilot cancel                      取消并清理

选项:
  --deep                    深度设计模式（交互式 Q&A + 方案对比 + 规格审查）
  --project                 强制项目模式（跳过复杂度检测）
  --single                  强制单任务模式（跳过复杂度检测）
  --max-iterations <n>      最大迭代次数 (默认: 30)
  --max-retries <n>         单阶段最大重试次数 (默认: 3)

示例:
  /autopilot 实现用户头像上传功能，支持裁剪和压缩
  /autopilot --deep 设计新的推荐算法架构
  /autopilot --project 复刻 Happy 到 Raven 生态
  /autopilot 001-wire-schema
  /autopilot next
  /autopilot commit
  /autopilot doctor
  /autopilot doctor --fix
  /autopilot approve
  /autopilot revise 需要支持 WebP 格式
HELP_EOF
        exit 0
        ;;

    commit)
        # 智能提交子命令 — 触发 autopilot-commit skill
        echo "📦 启动智能提交工作流..."
        echo ""
        echo "请按照 autopilot-commit skill 的指引执行智能提交工作流。"
        exit 0
        ;;

    doctor)
        # 工程健康度诊断子命令 — 触发 autopilot-doctor skill
        DOCTOR_ARGS="${2:-}"
        echo "🏥 启动工程健康度诊断..."
        echo ""
        if [[ "$DOCTOR_ARGS" == "--fix" ]]; then
            echo "修复模式已启用，将在诊断后自动修复可改进项。"
            echo ""
        fi
        echo "请按照 autopilot-doctor skill 的指引执行诊断工作流。"
        exit 0
        ;;

    approve)
        if [[ ! -f "$STATE_FILE" ]]; then
            echo "❌ 没有活跃的 autopilot。使用 /autopilot <目标> 启动新循环。"
            exit 0
        fi
        GATE=$(get_field "gate")
        if [[ -z "$GATE" ]]; then
            echo "❌ 当前不在审批门，无需 approve。"
            echo "   当前阶段: $(get_field 'phase')"
            exit 0
        fi
        FEEDBACK="${2:-}"
        set_field "gate" '""'
        # 推进阶段（design 审批由 Plan Mode 处理，这里只处理 review-accept）
        case "$GATE" in
            review-accept)
                set_field "phase" '"merge"'
                append_changelog "用户批准验收，进入合并阶段${FEEDBACK:+。反馈: $FEEDBACK}"
                echo "✅ 验收已通过，将进入代码合并阶段。"
                ;;
            *)
                echo "⚠️  未知的审批门: $GATE"
                exit 0
                ;;
        esac
        echo ""
        echo "循环将在下次自动继续。"
        exit 0
        ;;

    revise)
        if [[ ! -f "$STATE_FILE" ]]; then
            echo "❌ 没有活跃的 autopilot。"
            exit 0
        fi
        GATE=$(get_field "gate")
        if [[ -z "$GATE" ]]; then
            echo "❌ 当前不在审批门，无法 revise。"
            exit 0
        fi
        shift  # 移除 "revise"
        FEEDBACK="$*"
        if [[ -z "$FEEDBACK" ]]; then
            echo "❌ 请提供修改反馈。用法: /autopilot revise <反馈>"
            exit 0
        fi
        set_field "gate" '""'
        set_field "retry_count" "0"
        # design 审批由 Plan Mode 处理，这里只处理 review-accept
        case "$GATE" in
            review-accept)
                set_field "phase" '"implement"'
                append_changelog "用户要求修改实现: $FEEDBACK"
                echo "🔄 收到修改反馈，将重新进入实现阶段。"
                ;;
        esac
        # 将反馈写入状态文件的用户反馈区
        TEMP_REV="${STATE_FILE}.tmp.$$"
        awk -v fb="**用户反馈 ($(date -u +%Y-%m-%dT%H:%M:%SZ))**: $FEEDBACK" '
            /^## 变更日志/ { print "## 用户反馈\n" fb "\n"; print; next }
            { print }
        ' "$STATE_FILE" > "$TEMP_REV"
        mv "$TEMP_REV" "$STATE_FILE"
        echo ""
        echo "循环将在下次自动继续。"
        exit 0
        ;;

    status)
        if [[ -f "$STATE_FILE" ]]; then
            PHASE=$(get_field "phase")
            GATE=$(get_field "gate")
            ITERATION=$(get_field "iteration")
            MAX_ITER=$(get_field "max_iterations")
            RETRY=$(get_field "retry_count")
            MAX_RETRY=$(get_field "max_retries")
            STARTED=$(get_field "started_at")
            MODE=$(get_field "mode" || true)

            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "  autopilot 状态"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "阶段:     $PHASE"
            echo "审批门:   ${GATE:-无}"
            echo "迭代:     $ITERATION / $MAX_ITER"
            echo "重试:     $RETRY / $MAX_RETRY"
            echo "开始时间: $STARTED"
            [[ -n "$MODE" ]] && echo "模式:     $MODE"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        fi
        # 项目 DAG 状态（无论是否有活跃 autopilot 都尝试显示）
        DAG_FILE="$PROJECT_ROOT/.autopilot/project/dag.yaml"
        if [[ -f "$DAG_FILE" ]]; then
            [[ -f "$STATE_FILE" ]] && echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "  项目 DAG"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            # 用 awk 解析 dag.yaml（兼容 bash 3.2）
            awk '
            /^[[:space:]]*-[[:space:]]*id:/ {
                gsub(/.*id:[[:space:]]*"?/, ""); gsub(/".*/, ""); id=$0
                title=""; status=""
            }
            /^[[:space:]]*(title|name):/ {
                gsub(/.*:[[:space:]]*"?/, ""); gsub(/".*/, ""); title=$0
            }
            /^[[:space:]]*status:/ {
                gsub(/.*status:[[:space:]]*"?/, ""); gsub(/".*/, ""); status=$0
                if (id != "" && title != "") {
                    total++
                    if (status == "done") { icon="✅"; done_count++ }
                    else if (status == "in_progress") icon="🔄"
                    else if (status == "failed") icon="❌"
                    else if (status == "skipped") icon="⏭️"
                    else icon="⏳"
                    printf "  %s %s: %s\n", icon, id, title
                    id=""; title=""; status=""
                }
            }
            END {
                printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
                printf "  进度: %d / %d 完成\n", done_count, total
                printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            }
            ' "$DAG_FILE"
        elif [[ ! -f "$STATE_FILE" ]]; then
            echo "📋 没有活跃的 autopilot，也没有项目 DAG。"
        fi
        exit 0
        ;;

    next)
        DAG_FILE="$PROJECT_ROOT/.autopilot/project/dag.yaml"
        if [[ ! -f "$DAG_FILE" ]]; then
            echo "❌ 没有项目 DAG。使用 /autopilot --project <目标> 创建项目。"
            exit 0
        fi
        # 自动选择第一个就绪任务并启动
        NEXT_TASK=$(get_first_ready_task "$DAG_FILE")
        if [[ "$NEXT_TASK" == "ALL_DONE" ]]; then
            echo "🎉 所有任务已完成！"
            echo ""
            echo "💡 提示: 全项目 QA 会在最后一个任务的 auto-chain 中自动触发。"
            echo "   如需手动重跑: /autopilot --single 全项目集成QA验证"
            exit 0
        elif [[ -n "$NEXT_TASK" ]]; then
            echo "🚀 自动选择就绪任务: $NEXT_TASK"
            echo ""
            # 重新调用自身走 brief 模式初始化流程
            exec bash "$0" "$NEXT_TASK"
        else
            echo "⏳ 没有就绪任务。以下任务正在阻塞："
            awk '
            /^[[:space:]]*-[[:space:]]*id:/ {
                gsub(/.*id:[[:space:]]*"?/, ""); gsub(/".*/, ""); id=$0
                title=""; status=""
            }
            /^[[:space:]]*(title|name):/ {
                gsub(/.*:[[:space:]]*"?/, ""); gsub(/".*/, ""); title=$0
            }
            /^[[:space:]]*status:/ {
                gsub(/.*status:[[:space:]]*"?/, ""); gsub(/".*/, ""); status=$0
                if (id != "" && title != "" && status == "pending") {
                    printf "   ⏳ %s: %s\n", id, title
                }
                id=""; title=""; status=""
            }
            ' "$DAG_FILE"
            exit 0
        fi
        ;;

    cancel)
        if [[ ! -f "$STATE_FILE" ]]; then
            echo "📋 没有活跃的 autopilot。"
            exit 0
        fi
        # 仅移除 active 指针，requirements 文件夹保留作为历史归档
        cleanup_active "$PPID"
        echo "🛑 autopilot 已取消，active 指针已清理。"
        [[ -n "$TASK_DIR" ]] && echo "   需求文件夹保留在: $TASK_DIR"
        echo "   代码改动仍保留在工作目录中，可通过 git 查看。"
        exit 0
        ;;
esac

# ── 初始化新的 autopilot ────────────────────────────────────

# 检查冲突（仅检查当前 PID 是否已有活跃 autopilot）
if [[ -f "$STATE_FILE" ]]; then
    EXISTING_PHASE=$(get_field "phase" || true)
    if [[ "$EXISTING_PHASE" == "done" ]]; then
        cleanup_active "$PPID"
        echo "🧹 清理了上一次已完成的 autopilot active 指针。"
    else
        echo "❌ 当前会话已有活跃的 autopilot 在运行（阶段: ${EXISTING_PHASE:-unknown}）。"
        echo "   使用 /autopilot status 查看状态"
        echo "   使用 /autopilot cancel 取消后重新开始"
        exit 0
    fi
fi

if [[ -f ".claude/ralph-loop.local.md" ]]; then
    echo "❌ 检测到 ralph-loop 正在运行，两者共用 Stop hook 机制，不能同时运行。"
    echo "   请先取消 ralph-loop 后再启动 autopilot。"
    exit 0
fi

# 解析参数
PROMPT_PARTS=()
MAX_ITERATIONS=30
MAX_RETRIES=3
MODE_OVERRIDE=""
PLAN_MODE_OVERRIDE=""
BRIEF_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --max-iterations)
            if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo "❌ --max-iterations 需要一个正整数参数"
                exit 0
            fi
            MAX_ITERATIONS="$2"
            shift 2
            ;;
        --max-retries)
            if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo "❌ --max-retries 需要一个正整数参数"
                exit 0
            fi
            MAX_RETRIES="$2"
            shift 2
            ;;
        --project)
            MODE_OVERRIDE="project"
            shift
            ;;
        --single)
            MODE_OVERRIDE="single"
            shift
            ;;
        --deep)
            PLAN_MODE_OVERRIDE="deep"
            shift
            ;;
        *)
            PROMPT_PARTS+=("$1")
            shift
            ;;
    esac
done

GOAL="${PROMPT_PARTS[*]:-}"

if [[ -z "$GOAL" ]]; then
    echo "❌ 请提供目标描述。"
    echo "   用法: /autopilot <目标描述>"
    echo "   示例: /autopilot 实现用户头像上传功能"
    exit 0
fi

# 任务文件自然语言匹配（项目模式下）
TASKS_DIR="$PROJECT_ROOT/.autopilot/project/tasks"
if [[ -d "$TASKS_DIR" ]] && [[ -f "$PROJECT_ROOT/.autopilot/project/dag.yaml" ]]; then
    # 先精确前缀匹配，再模糊包含匹配
    MATCH=$(find "$TASKS_DIR" -maxdepth 1 -name "${GOAL}*.md" ! -name "*.handoff.md" 2>/dev/null | head -1)
    [[ -z "$MATCH" ]] && MATCH=$(find "$TASKS_DIR" -maxdepth 1 -name "*${GOAL}*.md" ! -name "*.handoff.md" 2>/dev/null | head -1)
    if [[ -n "$MATCH" ]]; then
        BRIEF_FILE="$(realpath "$MATCH")"
        echo "📎 匹配到项目任务: $(basename "$MATCH")"
    fi
fi

# 创建需求管理文件夹
mkdir -p "$PROJECT_ROOT/.autopilot"

# session_id：与 ralph 一致，直接使用环境变量（可能为空）。
# 空值时由 stop-hook 首次触发时认领真实 session_id，建立隔离。
SESSION_ID="${CLAUDE_CODE_SESSION_ID:-}"

# 迁移检测：旧路径 .claude/knowledge/ → 新路径 .autopilot/
# 注意：检查 .autopilot/index.md 而非 .autopilot/ 目录，因为上面 mkdir -p 已创建该目录
if [[ -d "$PROJECT_ROOT/.claude/knowledge" ]] && [[ ! -f "$PROJECT_ROOT/.autopilot/index.md" ]]; then
    echo "📦 检测到旧知识库 .claude/knowledge/，自动迁移到 .autopilot/ ..."
    bash "$(dirname "$0")/migrate-knowledge.sh"
    echo ""
fi

# 检查知识库是否存在
KNOWLEDGE_HINT=""
if [[ -d "$PROJECT_ROOT/.autopilot" ]]; then
    KNOWLEDGE_HINT="
> 📚 项目知识库已存在: .autopilot/。design 阶段请先加载相关知识上下文。"
elif [[ -d "$PROJECT_ROOT/.claude/knowledge" ]]; then
    KNOWLEDGE_HINT="
> ⚠️ 知识库仍在旧路径 .claude/knowledge/，建议手动运行迁移脚本:
> bash $(dirname "$0")/migrate-knowledge.sh"
fi

# 生成 task slug 并创建 requirements 文件夹
TASK_SLUG=$(generate_task_slug "$GOAL")
setup_requirement_dir "$TASK_SLUG" "$PPID"

# Brief 模式：从任务简报文件启动
if [[ -n "$BRIEF_FILE" ]]; then
    create_brief_state_file "$BRIEF_FILE" "$SESSION_ID" "$MAX_ITERATIONS" "$MAX_RETRIES" "false"

else
    # 正常模式状态文件
    cat > "$STATE_FILE" <<EOF
---
active: true
phase: "design"
gate: ""
iteration: 1
max_iterations: $MAX_ITERATIONS
max_retries: $MAX_RETRIES
retry_count: 0
mode: "${MODE_OVERRIDE}"
plan_mode: "${PLAN_MODE_OVERRIDE}"
brief_file: ""
next_task: ""
auto_approve: false
knowledge_extracted: ""
task_dir: "$TASK_DIR"
session_id: $SESSION_ID
started_at: "$(now_iso)"
---

## 目标
$GOAL
$KNOWLEDGE_HINT

## 设计文档
(待 design 阶段填充)

## 实现计划
(待 design 阶段填充)

## 红队验收测试
(待 implement 阶段填充)

## QA 报告
(待 qa 阶段填充)

## 变更日志
- [$(now_iso)] autopilot 初始化，目标: $GOAL
EOF
fi

# 输出信息
IS_WORKTREE=""
if [[ -f "$PROJECT_ROOT/.git" ]]; then
    IS_WORKTREE="(worktree: $(basename "$PROJECT_ROOT"))"
fi

# 根据模式调整输出
if [[ -n "$BRIEF_FILE" ]]; then
    DISPLAY_GOAL="任务: $(basename "$BRIEF_FILE" .md)"
    PHASE_FLOW="design → implement → qa → merge (brief 模式)"
elif [[ "$MODE_OVERRIDE" == "project" ]]; then
    DISPLAY_GOAL="$GOAL"
    PHASE_FLOW="design → 复杂度检测 → 架构设计 → DAG 创建 → done"
elif [[ "$PLAN_MODE_OVERRIDE" == "deep" ]]; then
    DISPLAY_GOAL="$GOAL"
    PHASE_FLOW="deep design（Q&A → 方案对比 → 规格审查）→ 审批 → implement → qa → 审批 → merge"
else
    DISPLAY_GOAL="$GOAL"
    PHASE_FLOW="design → 审批 → implement → qa → 审批 → merge"
fi

cat <<EOF
🔄 autopilot 已启动！

目标: $DISPLAY_GOAL
最大迭代: $MAX_ITERATIONS
最大重试: $MAX_RETRIES
状态文件: $STATE_FILE ${IS_WORKTREE}
需求文件夹: $TASK_DIR

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  阶段流程: $PHASE_FLOW
  当前阶段: design（AI 正在分析目标并设计方案）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

命令:
  /autopilot approve    批准当前审批门
  /autopilot revise     要求修改
  /autopilot status     查看状态
  /autopilot next       查找就绪任务（项目模式）
  /autopilot cancel     取消循环
  /autopilot commit     智能提交（独立使用）

提示: 建议在 worktree 中运行以隔离代码改动
      claude -w autopilot-xxx 然后 /autopilot <目标>
EOF

echo ""
echo "开始设计阶段。请按照 autopilot skill 的指引，读取 $STATE_FILE 状态文件并执行 design 阶段。"
