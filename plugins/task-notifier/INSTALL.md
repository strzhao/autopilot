# 安装指南

## 快速安装

### 方法一：通过插件市场安装（推荐）
1. 确保已安装 Claude Code 插件市场
2. 运行 `/plugins` 查看可用插件
3. 选择安装 `task-notifier` 插件

### 方法二：手动安装
```bash
# 复制插件到 Claude Code 插件目录
cp -r plugins/task-notifier ~/.claude/plugins/

# 重启 Claude Code
```

## 详细安装步骤

### 前提条件
- 已安装 Claude Code
- 已安装插件市场（可选，但推荐）

### 步骤 1：获取插件
```bash
# 克隆插件仓库（如果从 GitHub 获取）
git clone https://github.com/strzhao/autopilot.git
cd autopilot/plugins/task-notifier
```

### 步骤 2：插件说明
插件直接使用系统默认通知，无需准备音频文件。简化方案具有以下优势：

- ✅ **零配置**：无需准备音频文件
- ✅ **跨平台**：使用各操作系统原生通知机制
- ✅ **稳定可靠**：避免音频播放器兼容性问题
- ✅ **轻量快速**：无需加载外部音频文件

### 步骤 3：安装插件
```bash
# 创建 Claude Code 插件目录（如果不存在）
mkdir -p ~/.claude/plugins

# 复制插件
cp -r /path/to/task-notifier ~/.claude/plugins/
```

### 步骤 4：验证安装
1. 重启 Claude Code
2. 运行 `/hooks` 命令
3. 应该看到类似以下的输出：
   ```
   Hook: PostToolUse
   Matcher: Task|TodoWrite|TaskComplete|TaskUpdate
   Command: /Users/username/.claude/plugins/task-notifier/assets/scripts/play-sound.sh task-complete
   ```

### 步骤 5：测试功能
1. 在 Claude Code 中执行任何任务相关工具：
   ```bash
   # 示例：创建一个任务
   Task "测试任务完成提示音"
   ```
2. 应该收到系统通知（桌面通知或终端响铃）

## 故障排除

### 问题 1：没有收到通知
**可能原因**：
1. 插件未正确加载
2. 系统通知被禁用
3. 终端响铃功能不可用

**解决方案**：
1. 检查插件是否加载：
   ```bash
   /hooks
   ```
2. 检查系统通知设置：
   - **macOS**：确保通知中心允许 Claude Code 显示通知
   - **Linux**：确保 `notify-send` 已安装（可选，不影响基本功能）
   - **Windows**：终端响铃功能通常可用
3. 检查脚本执行权限：
   ```bash
   chmod +x ~/.claude/plugins/task-notifier/assets/scripts/play-sound.sh
   ```
4. 查看 Claude Code 日志：
   ```bash
   tail -f ~/.claude/logs/claude-code.log
   ```

### 问题 2：插件未出现在 /plugins 列表中
**可能原因**：
1. 插件市场配置未更新
2. 插件目录结构不正确

**解决方案**：
1. 检查插件市场配置：
   ```bash
   cat ~/.claude/plugins/task-notifier/.claude-plugin/plugin.json
   ```
2. 验证目录结构：
   ```bash
   tree ~/.claude/plugins/task-notifier -L 3
   ```

### 问题 3：脚本执行错误
**可能原因**：
1. 脚本没有执行权限
2. 环境变量未设置

**解决方案**：
1. 添加执行权限：
   ```bash
   chmod +x ~/.claude/plugins/task-notifier/assets/scripts/play-sound.sh
   ```
2. 手动测试脚本：
   ```bash
   cd ~/.claude/plugins/task-notifier
   CLAUDE_PLUGIN_ROOT=$(pwd) ./assets/scripts/play-sound.sh
   ```

## 高级配置


### 扩展匹配规则
要监听更多工具，修改 `hooks/hooks.json` 中的 `matcher` 字段：
```json
"matcher": "Task|TodoWrite|TaskComplete|TaskUpdate|YourCustomTool"
```

### 调整超时时间
默认超时为 10 秒，可以调整：
```json
"timeout": 5  # 设置为 5 秒
```

## 卸载插件

### 方法一：通过插件市场卸载
```bash
/plugins uninstall task-notifier
```

### 方法二：手动卸载
```bash
rm -rf ~/.claude/plugins/task-notifier
```

## 更新插件

### 方法一：通过插件市场更新
```bash
/plugins update task-notifier
```

### 方法二：手动更新
```bash
# 备份配置（如果有自定义配置）
cp -r ~/.claude/plugins/task-notifier ~/.claude/plugins/task-notifier.backup

# 删除旧版本
rm -rf ~/.claude/plugins/task-notifier

# 安装新版本
cp -r /path/to/new/task-notifier ~/.claude/plugins/

# 恢复自定义配置（如果有）
cp ~/.claude/plugins/task-notifier.backup/hooks/hooks.json ~/.claude/plugins/task-notifier/hooks/
```

## 支持的操作系统

- ✅ **macOS** 10.15+
- ✅ **Linux** (Ubuntu 20.04+, CentOS 8+, Fedora 32+)
- ✅ **Windows** 10+ (通过 WSL2、Git Bash、PowerShell)

## 获取帮助

如果遇到问题：
1. 查看 [README.md](README.md) 中的故障排除部分
2. 检查 Claude Code 日志：
   ```bash
   # macOS/Linux
   tail -f ~/.claude/logs/claude-code.log

   # Windows
   Get-Content -Path "$env:USERPROFILE\.claude\logs\claude-code.log" -Wait
   ```
3. 在 GitHub 上提交 Issue：
   https://github.com/strzhao/autopilot/issues

## 许可证

本项目采用 MIT 许可证。详见 [LICENSE](../LICENSE) 文件。