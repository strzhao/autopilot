# Claude Code 插件 - 快速开始指南

## 概述

本仓库是 **Autopilot 插件市场**，提供多个实用的 Claude Code 插件，帮助提升开发效率。

## 可用插件

| 插件名 | 版本 | 描述 |
|--------|------|------|
| `summarizer` | v1.0.0 | 多模态内容摘要工具，自动提取文章/视频/音频内容并生成结构化摘要 |
| `task-notifier` | v1.0.0 | 任务完成提示音插件，在任务完成后播放系统通知 |
| `autopilot` | v2.0.0 | AI 自动驾驶工程套件，全流程闭环 + 智能提交 |

## 快速安装

### 方法一：通过插件市场安装（推荐）

添加本仓库为插件市场来源：

```bash
/plugin marketplace add https://github.com/strzhao/autopilot.git
```

然后运行 `/plugins` 查看并安装可用插件。

### 方法二：手动安装

```bash
# 克隆仓库
git clone https://github.com/strzhao/autopilot.git
cd autopilot

# 安装指定插件（以 summarizer 为例）
cp -r plugins/summarizer ~/.claude/plugins/

# 重启 Claude Code
```

## 插件详情

### 📄 summarizer - 内容摘要工具

自动识别链接内容，生成结构化摘要并保存到 flomo。

**使用方法：**
```bash
# 在 Claude Code 中输入文章、视频或音频链接
https://example.com/article

# AI 会自动提取内容并生成多层次摘要
# 摘要将通过 flomo MCP 保存到笔记
```

**配置要求：**
- Playwright MCP（网页内容提取）
- Video-to-Text MCP（视频/音频转文字）
- flomo MCP（笔记保存）

---

### 🔔 task-notifier - 任务提示音

在任务执行完成后自动播放系统提示音。

**使用方法：**
```bash
# 创建任务
Task "我的任务"

# 完成任务时会自动触发提示音
TaskComplete
```

**验证安装：**
```bash
/hooks
```
应该看到 `task-notifier` 相关的 hook 配置。

---

### 🚀 autopilot - AI 自动驾驶工程套件

全流程闭环（红蓝对抗 + 五层 QA）+ 智能提交。

**使用方法：**
```bash
# 启动全流程闭环
/autopilot 实现用户头像上传功能

# 智能提交（独立使用）
/autopilot commit
```

**工作流程：**
1. 全流程：目标 → 设计 → 红蓝对抗编码 → 五层 QA → 自动修复 → 合并
2. 智能提交：分析改动 → React 优化 → 代码测验 → 生成提交信息

**验证安装：**
```bash
/skills
```
应该看到 `autopilot` 和 `autopilot-commit` skill。

## 项目结构

```
autopilot/
├── README.md                    # 主文档
├── QUICK_START.md              # 快速开始指南（本文档）
├── .claude-plugin/
│   └── marketplace.json        # 插件市场配置
├── document/
│   ├── hooks.md                # Hooks 开发文档
│   └── skill_best_practices.md # Skill 开发最佳实践
└── plugins/
    ├── summarizer/             # 内容摘要插件
    ├── task-notifier/          # 任务提示音插件
    └── autopilot/              # AI 自动驾驶工程套件
```

## 插件开发

### 基本结构

```
plugin-name/
├── .claude-plugin/
│   └── plugin.json             # 插件元数据
├── .mcp.json                   # MCP 配置（可选）
├── skills/                     # Skill 目录（可选）
├── hooks/                      # Hooks 目录（可选）
└── README.md                   # 插件文档
```

### plugin.json 示例

```json
{
    "name": "plugin-name",
    "version": "1.0.0",
    "description": "插件功能描述",
    "author": {
        "name": "作者名",
        "email": "作者邮箱"
    },
    "license": "MIT"
}
```

## 故障排除

### 插件未加载
1. 检查插件目录结构是否正确
2. 运行 `/plugins` 查看已安装插件
3. 重启 Claude Code

### MCP 工具无法使用
1. 检查 `.mcp.json` 配置是否正确
2. 确保 MCP 服务器已安装
3. 查看 Claude Code 日志获取详细错误

### Hooks 不生效
1. 运行 `/hooks` 查看 hooks 是否注册
2. 检查 `hooks.json` 语法是否正确
3. 确保脚本有执行权限

## 贡献指南

欢迎贡献新插件或改进现有插件！

1. **Fork 仓库**
2. **创建特性分支**：`git checkout -b feature/your-feature`
3. **开发插件**：遵循项目结构规范
4. **测试验证**：在本地 Claude Code 中测试
5. **提交 PR**：详细描述更改内容

## 相关文档

- [主文档](README.md) - 完整的项目介绍
- [Hooks 开发文档](document/hooks.md) - 学习如何开发 Hooks
- [Skill 最佳实践](document/skill_best_practices.md) - Skill 开发指南

## 支持

- **项目维护者**：String Zhao
- **邮箱**：zhaoguixiong@corp.netease.com
- **仓库地址**：https://github.com/strzhao/autopilot

## 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件。