#!/bin/bash

# autopilot 审批通知脚本
# 在审批门触发时发送系统通知 + 声音提醒

set -euo pipefail

SCENE="${1:-review}"

case "$SCENE" in
    review-accept)
        TITLE="autopilot: 验收审批"
        MSG="代码实现和测试已完成，等待您的验收。运行 /autopilot approve 批准合并。"
        ;;
    complete)
        TITLE="autopilot: 任务完成"
        MSG="代码已成功合并，autopilot 闭环完成。"
        ;;
    error)
        TITLE="autopilot: 需要人工介入"
        MSG="自动修复达到上限，部分问题需要人工处理。"
        ;;
    *)
        TITLE="autopilot"
        MSG="需要您的关注。"
        ;;
esac

# macOS 通知
if command -v osascript &>/dev/null; then
    osascript -e "display notification \"$MSG\" with title \"$TITLE\" sound name \"Glass\"" 2>/dev/null || true
# Linux 通知
elif command -v notify-send &>/dev/null; then
    notify-send "$TITLE" "$MSG" 2>/dev/null || true
fi

# 终端响铃作为后备
printf '\a' 2>/dev/null || true
