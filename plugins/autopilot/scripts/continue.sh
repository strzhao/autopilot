#!/bin/bash

# autopilot-continue 初始化脚本
# 扫描未完成需求，用户选择后写入 active.$PPID 指针

set -uo pipefail

source "$(dirname "$0")/lib.sh"
init_paths "" "$PPID"

REQ_DIR="$PROJECT_ROOT/.autopilot/requirements"

if [[ ! -d "$REQ_DIR" ]]; then
    echo "📋 没有未完成的需求。使用 /autopilot <目标> 启动新需求。"
    exit 0
fi

# 如果传入了序号参数，直接绑定
CHOICE="${1:-}"

# 收集未完成需求
SLUGS=()
PHASES=()
GOALS=()

while IFS= read -r dir; do
    [[ -d "$dir" ]] || continue
    sf="$dir/state.md"
    [[ -f "$sf" ]] || continue
    # 临时用该状态文件解析 phase
    STATE_FILE="$sf"
    phase=$(get_field "phase" || true)
    [[ "$phase" == "done" ]] && continue
    slug=$(basename "$dir")
    goal=$(sed -n '/^## 目标/,/^## /{/^## 目标/d;/^## /d;/^$/d;p;}' "$sf" | head -1 | sed 's/^[[:space:]]*//')
    SLUGS+=("$slug")
    PHASES+=("$phase")
    GOALS+=("${goal:-(无描述)}")
done < <(find "$REQ_DIR" -mindepth 1 -maxdepth 1 -type d | sort -r)

if [[ ${#SLUGS[@]} -eq 0 ]]; then
    echo "📋 没有未完成的需求。使用 /autopilot <目标> 启动新需求。"
    exit 0
fi

# 如果有选择参数，直接绑定
if [[ -n "$CHOICE" ]] && [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
    IDX=$((CHOICE - 1))
    if [[ $IDX -ge 0 ]] && [[ $IDX -lt ${#SLUGS[@]} ]]; then
        selected_slug="${SLUGS[$IDX]}"
        TASK_DIR="$REQ_DIR/$selected_slug"
        STATE_FILE="$TASK_DIR/state.md"
        echo "$selected_slug" > "$PROJECT_ROOT/.autopilot/active.$PPID"
        echo "$selected_slug" > "$PROJECT_ROOT/.autopilot/active"
        echo "✅ 已绑定需求: $selected_slug"
        echo "   阶段: ${PHASES[$IDX]}"
        echo "   状态文件: $STATE_FILE"
        echo ""
        echo "请按照 autopilot skill 的指引，读取 $STATE_FILE 状态文件并执行当前阶段。"
        exit 0
    fi
fi

# 列出需求供选择
echo "📋 未完成的需求："
echo ""
for i in "${!SLUGS[@]}"; do
    idx=$((i + 1))
    echo "  $idx) [${PHASES[$i]}] ${SLUGS[$i]}"
    echo "     ${GOALS[$i]}"
    echo ""
done
echo "请选择要继续的需求序号（使用 AskUserQuestion），然后运行："
echo "  /autopilot-continue <序号>"
exit 0
