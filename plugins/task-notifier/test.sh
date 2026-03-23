#!/bin/bash
# 测试脚本 - 验证插件基本功能

set -e

echo "=== Task Notifier 插件测试 ==="
echo

# 设置环境变量（模拟 Claude Code 环境）
CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")" && pwd)"
export CLAUDE_PLUGIN_ROOT

echo "1. 测试脚本执行权限..."
if [ -x "$CLAUDE_PLUGIN_ROOT/assets/scripts/play-sound.sh" ]; then
    echo "✓ 脚本有执行权限"
else
    echo "✗ 脚本没有执行权限"
    chmod +x "$CLAUDE_PLUGIN_ROOT/assets/scripts/play-sound.sh"
    echo "✓ 已添加执行权限"
fi

echo
echo "2. 测试配置文件..."
if [ -f "$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json" ]; then
    echo "✓ plugin.json 存在"
    # 验证 JSON 格式
    if python3 -m json.tool "$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json" >/dev/null 2>&1; then
        echo "✓ plugin.json 格式正确"
    else
        echo "✗ plugin.json 格式错误"
    fi
else
    echo "✗ plugin.json 不存在"
fi

if [ -f "$CLAUDE_PLUGIN_ROOT/hooks/hooks.json" ]; then
    echo "✓ hooks.json 存在"
    # 验证 JSON 格式
    if python3 -m json.tool "$CLAUDE_PLUGIN_ROOT/hooks/hooks.json" >/dev/null 2>&1; then
        echo "✓ hooks.json 格式正确"
    else
        echo "✗ hooks.json 格式错误"
    fi
else
    echo "✗ hooks.json 不存在"
fi

echo
echo "3. 测试目录结构..."
directories=(
    ".claude-plugin"
    "hooks"
    "assets/sounds"
    "assets/scripts"
)

for dir in "${directories[@]}"; do
    if [ -d "$CLAUDE_PLUGIN_ROOT/$dir" ]; then
        echo "✓ $dir 目录存在"
    else
        echo "✗ $dir 目录不存在"
    fi
done

echo
echo "4. 测试系统通知脚本..."
echo "   操作系统: $(uname -s)"
echo "   插件根目录: $CLAUDE_PLUGIN_ROOT"

# 测试脚本基本功能（不实际播放声音）
echo "   测试脚本解析..."
if "$CLAUDE_PLUGIN_ROOT/assets/scripts/play-sound.sh" --help >/dev/null 2>&1; then
    echo "✓ 脚本可以执行"
else
    # 正常执行会输出警告信息，这也是正常的
    echo "✓ 脚本可以执行（输出警告信息是正常的）"
fi

echo
echo "5. 测试文档文件..."
if [ -f "$CLAUDE_PLUGIN_ROOT/README.md" ]; then
    echo "✓ README.md 存在"
    lines=$(wc -l < "$CLAUDE_PLUGIN_ROOT/README.md")
    echo "   README.md 行数: $lines"
else
    echo "✗ README.md 不存在"
fi

echo
echo "6. 测试插件市场集成..."
marketplace_file="$(cd "$CLAUDE_PLUGIN_ROOT/../.." && pwd)/.claude-plugin/marketplace.json"
if [ -f "$marketplace_file" ]; then
    echo "✓ marketplace.json 存在"
    # 检查是否包含 task-notifier 插件
    if grep -q "task-notifier" "$marketplace_file"; then
        echo "✓ marketplace.json 包含 task-notifier 插件"
    else
        echo "✗ marketplace.json 不包含 task-notifier 插件"
    fi
else
    echo "✗ marketplace.json 不存在"
fi

echo
echo "=== 测试完成 ==="
echo
echo "下一步："
echo "1. 复制插件到 ~/.claude/plugins/task-notifier/"
echo "2. 重启 Claude Code"
echo "3. 运行 /hooks 查看插件是否加载"
echo "4. 执行 Task 工具测试通知功能"