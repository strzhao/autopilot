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
init_paths

# ── 参数安全处理 ──────────────────────────────────────────────
# SKILL.md 用 "$ARGUMENTS" 引号传参（防止 shell 解析括号等特殊字符），
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
  /autopilot commit                      智能提交（React 优化 + 代码测验）
  /autopilot doctor [--fix]              工程健康度诊断（评估 autopilot 兼容性）
  /autopilot approve [反馈]              批准当前审批门
  /autopilot revise <反馈>               要求修改
  /autopilot status                      查看状态
  /autopilot cancel                      取消并清理

选项:
  --max-iterations <n>    最大迭代次数 (默认: 30)
  --max-retries <n>       单阶段最大重试次数 (默认: 3)

示例:
  /autopilot 实现用户头像上传功能，支持裁剪和压缩
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
        if [[ ! -f "$STATE_FILE" ]]; then
            echo "📋 没有活跃的 autopilot。"
            exit 0
        fi
        PHASE=$(get_field "phase")
        GATE=$(get_field "gate")
        ITERATION=$(get_field "iteration")
        MAX_ITER=$(get_field "max_iterations")
        RETRY=$(get_field "retry_count")
        MAX_RETRY=$(get_field "max_retries")
        STARTED=$(get_field "started_at")

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  autopilot 状态"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "阶段:     $PHASE"
        echo "审批门:   ${GATE:-无}"
        echo "迭代:     $ITERATION / $MAX_ITER"
        echo "重试:     $RETRY / $MAX_RETRY"
        echo "开始时间: $STARTED"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        exit 0
        ;;

    cancel)
        if [[ ! -f "$STATE_FILE" ]]; then
            echo "📋 没有活跃的 autopilot。"
            exit 0
        fi
        rm "$STATE_FILE"
        echo "🛑 autopilot 已取消，状态文件已清理。"
        echo "   代码改动仍保留在工作目录中，可通过 git 查看。"
        exit 0
        ;;
esac

# ── 初始化新的 autopilot ────────────────────────────────────

# 检查冲突
if [[ -f "$STATE_FILE" ]]; then
    EXISTING_PHASE=$(get_field "phase" || true)
    if [[ "$EXISTING_PHASE" == "done" ]]; then
        # phase=done 的状态文件是残留（stop hook 未及时清理），直接清理
        rm "$STATE_FILE"
        echo "🧹 清理了上一次已完成的 autopilot 状态文件。"
    else
        echo "❌ 已有活跃的 autopilot 在运行（阶段: ${EXISTING_PHASE:-unknown}）。"
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

# 创建状态文件
mkdir -p "$PROJECT_ROOT/.claude"

# session_id：与 ralph 一致，直接使用环境变量（可能为空）。
# 空值时由 stop-hook 首次触发时认领真实 session_id，建立隔离。
SESSION_ID="${CLAUDE_CODE_SESSION_ID:-}"

# 检查知识库是否存在
KNOWLEDGE_HINT=""
if [[ -d "$PROJECT_ROOT/.claude/knowledge" ]]; then
    KNOWLEDGE_HINT="
> 📚 项目知识库已存在: .claude/knowledge/。design 阶段请先加载相关知识上下文。"
fi

cat > "$STATE_FILE" <<EOF
---
active: true
phase: "design"
gate: ""
iteration: 1
max_iterations: $MAX_ITERATIONS
max_retries: $MAX_RETRIES
retry_count: 0
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

# 输出信息
IS_WORKTREE=""
if [[ -f "$PROJECT_ROOT/.git" ]]; then
    IS_WORKTREE="(worktree: $(basename "$PROJECT_ROOT"))"
fi

cat <<EOF
🔄 autopilot 已启动！

目标: $GOAL
最大迭代: $MAX_ITERATIONS
最大重试: $MAX_RETRIES
状态文件: $STATE_FILE ${IS_WORKTREE}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  阶段流程: design → 审批 → implement → qa → 审批 → merge
  当前阶段: design（AI 正在分析目标并设计方案）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

命令:
  /autopilot approve    批准当前审批门
  /autopilot revise     要求修改
  /autopilot status     查看状态
  /autopilot cancel     取消循环
  /autopilot commit     智能提交（独立使用）

提示: 建议在 worktree 中运行以隔离代码改动
      claude -w autopilot-xxx 然后 /autopilot <目标>
EOF

echo ""
echo "开始设计阶段。请按照 autopilot skill 的指引，读取 $STATE_FILE 状态文件并执行 design 阶段。"
