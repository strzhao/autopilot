#!/bin/bash
# 演示脚本 - 展示插件功能

set -e

echo "🎵 Task Notifier 插件演示"
echo "=========================="
echo

# 设置环境变量
CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")" && pwd)"
export CLAUDE_PLUGIN_ROOT

echo "1. 显示插件信息"
echo "   名称: task-notifier"
echo "   版本: 1.0.0"
echo "   作者: stringzhao"
echo "   描述: 任务完成提示音插件"
echo

echo "2. 显示 hooks 配置"
echo "   事件: PostToolUse"
echo "   匹配工具: Task|TodoWrite|TaskComplete|TaskUpdate"
echo "   命令: \${CLAUDE_PLUGIN_ROOT}/assets/scripts/play-sound.sh task-complete"
echo "   超时: 10秒"
echo

echo "3. 测试音频播放脚本"
echo "   当前目录: $CLAUDE_PLUGIN_ROOT"
echo "   操作系统: $(uname -s)"
echo

# 测试脚本功能（不实际播放声音）
echo "4. 运行测试（模拟环境）"
echo "   步骤 1: 检测操作系统..."
os=$(uname -s)
case "$os" in
    Darwin*) echo "      检测到: macOS (将使用 afplay)" ;;
    Linux*) echo "      检测到: Linux (将尝试 mpv/mplayer/paplay/aplay)" ;;
    CYGWIN*|MINGW*|MSYS*) echo "      检测到: Windows (将使用 PowerShell)" ;;
    *) echo "      检测到: 未知系统" ;;
esac

echo
echo "   步骤 2: 检查音频文件..."
sound_file="$CLAUDE_PLUGIN_ROOT/assets/sounds/task-complete.mp3"
if [ -f "$sound_file" ]; then
    echo "      ✓ 找到音频文件: $(basename "$sound_file")"
    file_size=$(stat -f%z "$sound_file" 2>/dev/null || stat -c%s "$sound_file" 2>/dev/null || echo "未知")
    echo "        文件大小: ${file_size} 字节"
else
    echo "      ⚠ 未找到音频文件: task-complete.mp3"
    echo "        插件将使用系统默认通知"
fi

echo
echo "   步骤 3: 检查播放器..."
case "$os" in
    Darwin*)
        if command -v afplay >/dev/null 2>&1; then
            echo "      ✓ 找到 afplay: $(which afplay)"
        else
            echo "      ⚠ 未找到 afplay，将使用系统通知"
        fi
        ;;
    Linux*)
        found=false
        for player in mpv mplayer paplay aplay; do
            if command -v "$player" >/dev/null 2>&1; then
                echo "      ✓ 找到 $player: $(which "$player")"
                found=true
                break
            fi
        done
        if [ "$found" = false ]; then
            echo "      ⚠ 未找到任何音频播放器，将使用系统通知"
        fi
        ;;
    CYGWIN*|MINGW*|MSYS*)
        if command -v powershell >/dev/null 2>&1; then
            echo "      ✓ 找到 PowerShell: $(which powershell)"
        else
            echo "      ⚠ 未找到 PowerShell，将使用终端响铃"
        fi
        ;;
esac

echo
echo "5. 模拟 hooks 触发"
echo "   当您执行以下操作时，插件会自动触发："
echo "   - 创建任务: Task \"任务描述\""
echo "   - 写入待办: TodoWrite \"待办事项\""
echo "   - 完成任务: TaskComplete"
echo "   - 更新任务: TaskUpdate"
echo

echo "6. 优雅降级演示"
echo "   如果音频播放失败，插件将："
echo "   - macOS: 显示系统通知 + 播放 Glass 音效"
echo "   - Linux: 发送桌面通知 + 终端响铃"
echo "   - Windows: 终端响铃"
echo

echo "7. 安装说明"
echo "   快速安装:"
echo "   cp -r plugins/task-notifier ~/.claude/plugins/"
echo "   然后重启 Claude Code"
echo

echo "8. 验证安装"
echo "   安装后，运行以下命令验证："
echo "   /hooks  # 查看已注册的 hooks"
echo "   Task \"测试任务\"  # 测试提示音功能"
echo

echo "🎉 演示完成！"
echo
echo "下一步操作："
echo "1. 将音频文件放入 assets/sounds/ 目录"
echo "2. 按照 INSTALL.md 中的说明安装插件"
echo "3. 重启 Claude Code 并测试功能"
echo
echo "更多信息请查看："
echo "- README.md - 完整文档"
echo "- INSTALL.md - 安装指南"
echo "- test.sh - 测试脚本"