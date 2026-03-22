# Task Notifier 插件

任务完成提示音插件。在 Claude Code 任务执行完成后播放提示音提醒用户。

## 功能特性

- 🔔 **任务完成通知**：在执行任务相关工具后触发系统通知
- 🌐 **跨平台支持**：支持 macOS、Linux、Windows 系统
- ⚡ **超时保护**：10秒超时机制，防止通知阻塞主进程
- 🔧 **可配置性**：支持自定义匹配规则

## 支持的触发工具

插件默认监听以下工具的使用：
- `Task` - 创建新任务
- `TodoWrite` - 写入待办事项
- `TaskComplete` - 完成任务
- `TaskUpdate` - 更新任务状态

## 安装方法

### 方法一：通过插件市场安装（推荐）
1. 确保已安装 Claude Code 插件市场
2. 运行 `/plugins` 查看可用插件
3. 选择安装 `task-notifier` 插件

### 方法二：本地安装
1. 复制插件目录到 Claude Code 插件目录：
   ```bash
   cp -r plugins/task-notifier ~/.claude/plugins/
   ```
2. 重启 Claude Code
3. 运行 `/hooks` 确认插件已加载

## 使用方法

安装后无需额外配置，插件会自动工作。当您执行以下操作时，将听到提示音：

1. 创建新任务：`Task` 工具
2. 写入待办事项：`TodoWrite` 工具
3. 完成任务：`TaskComplete` 工具
4. 更新任务：`TaskUpdate` 工具

## 通知方式

插件直接使用系统默认通知，无需配置音频文件：

- **macOS**：显示桌面通知并播放系统提示音
- **Linux**：发送桌面通知（如可用）并触发终端响铃
- **Windows**：触发终端响铃

### 优势
- ✅ **零配置**：无需准备音频文件
- ✅ **跨平台**：使用各操作系统原生通知机制
- ✅ **稳定可靠**：避免音频播放器兼容性问题
- ✅ **轻量快速**：无需加载外部音频文件

## 配置说明

### hooks 配置
配置文件位于 `hooks/hooks.json`，支持以下配置项：

```json
{
    "description": "任务完成提示音配置",
    "hooks": {
        "PostToolUse": [
            {
                "matcher": "Task|TodoWrite|TaskComplete|TaskUpdate",
                "hooks": [
                    {
                        "type": "command",
                        "command": "${CLAUDE_PLUGIN_ROOT}/assets/scripts/play-sound.sh task-complete",
                        "timeout": 10
                    }
                ]
            }
        ]
    }
}
```

### 自定义匹配规则
如需监听其他工具，修改 `matcher` 字段的正则表达式：
```json
"matcher": "Task|TodoWrite|TaskComplete|TaskUpdate|YourCustomTool"
```

## 跨平台兼容性

### macOS
- 显示桌面通知并播放系统提示音（Glass 音效）
- 使用 `osascript` 命令触发系统通知

### Linux
- 发送桌面通知（使用 `notify-send`，如可用）
- 触发终端响铃（`echo -e "\a"`）

### Windows
- 触发终端响铃（`echo -e "\a"`）

## 故障排除

### 没有收到通知
1. **检查插件是否加载**：运行 `/hooks` 查看 hooks 配置是否生效
2. **检查系统通知设置**：确保操作系统允许显示通知
3. **查看日志**：检查 Claude Code 的日志输出
4. **检查超时设置**：在 hooks 配置中调整 `timeout` 值（默认 10 秒）

### 通知不工作
1. **macOS**：确保通知中心功能正常
2. **Linux**：安装 `notify-send` 以获得桌面通知（可选）
3. **Windows**：终端响铃功能应该始终可用

## 开发指南

### 项目结构
```
task-notifier/
├── .claude-plugin/
│   └── plugin.json                    # 插件元数据
├── hooks/
│   └── hooks.json                     # hooks 配置
├── assets/
│   └── scripts/
│       └── play-sound.sh              # 跨平台系统通知脚本
└── README.md                          # 本文档
```

### 系统通知脚本
`play-sound.sh` 脚本提供跨平台系统通知功能，包含：
- 操作系统自动检测
- 原生系统通知机制
- 终端响铃备用方案
- 10秒超时保护

## 贡献指南

欢迎提交 Issue 和 Pull Request 来改进插件：

1. **报告问题**：在 GitHub Issues 中描述问题
2. **功能建议**：提出改进建议或新功能想法
3. **代码贡献**：Fork 仓库并提交 Pull Request
4. **文档改进**：帮助改进文档或翻译

## 许可证

本项目采用 MIT 许可证。详见 [LICENSE](LICENSE) 文件。

## 联系方式

- 作者：stringzhao
- 邮箱：zhaoguixiong@corp.netease.com
- 项目地址：https://github.com/strzhao/autopilot

## 更新日志

### v1.0.0 (2026-02-07)
- 初始版本发布
- 支持任务完成提示音功能
- 跨平台兼容性支持
- 优雅降级机制
- 完整的文档和配置说明

### v2.0.0 (简化版本)
- 移除自定义音频播放功能
- 直接使用系统默认通知
- 简化配置，无需音频文件
- 更新文档和脚本