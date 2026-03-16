# Claude Code 插件集合

<div align="center">

**String Claude Code 插件集合**

[![Plugins](https://img.shields.io/badge/plugins-3-blue.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Compatible-green.svg)](https://claude.ai/code)
[![License](https://img.shields.io/badge/license-MIT-orange.svg)](LICENSE)

</div>

---

## 📖 项目简介

本仓库是一个 **Claude Code 插件市场**，收集了一系列高质量的 Claude Code 插件，旨在通过 AI 辅助提升开发效率和代码质量。

### 🎯 设计理念

- **专业化**：每个插件专注于特定领域，提供深度优化的解决方案
- **易用性**：简化配置流程，降低团队推广成本
- **实时性**：通过 MCP 动态获取数据，确保信息准确性
- **可扩展**：清晰的架构设计，便于二次开发和定制

---

## 📦 插件列表

### 🎯 summarizer (v1.0.0)
**多模态内容摘要工具**

- **功能**：自动识别文章、视频、音频链接，提取内容并生成多层次结构化摘要，最后通过 flomo MCP 保存
- **核心特性**：
  - 使用 Playwright 无头浏览器提取网页内容，Video-to-Text MCP处理视频/音频转文字
  - 结构化摘要生成（核心思想、核心论点、关键信息、结论等）
  - 支持 flomo 笔记保存，自动添加标签和来源
  - 严格遵循原文内容，无个人解读
- **技术栈**：Playwright MCP、Video-to-Text MCP、flomo MCP
- **作者**：String Zhao

### 🔔 task-notifier (v1.0.0)
**任务完成提示音插件**

- **功能**：在 Claude Code 任务执行完成后播放系统提示音提醒用户
- **核心特性**：
  - 任务完成自动通知（支持 Task、TodoWrite、TaskComplete、TaskUpdate 等工具）
  - 跨平台支持（macOS、Linux、Windows）
  - 使用系统原生通知，零配置
  - 10秒超时保护，防止阻塞
- **技术栈**：Hooks、系统通知、Shell 脚本
- **作者**：String Zhao

### 🚀 autopilot (v2.0.0)
**AI 自动驾驶工程套件**

- **功能**：全流程闭环（红蓝对抗 + 五层 QA + 自动修复）+ 智能提交
- **核心特性**：
  - 从目标描述到代码合并全程自动化，仅需两次人工审批
  - 红蓝对抗：蓝队编码 + 红队仅看设计文档写验收测试（信息隔离）
  - 五层 QA + 系统化调试方法论 + 自动修复循环
  - 智能提交：React 优化、代码测验、版本升级、任务同步
  - 防合理化表格 + 成功需要证据原则
- **技术栈**：Skill + Hook（Stop hook 驱动状态机）
- **作者**：String Zhao

---

## 🚀 快速开始

### 方案一：插件市场安装（推荐）

本仓库本身就是一个 Claude Code 插件市场。在 Claude Code 中执行以下命令添加为插件市场来源：

```bash
/plugin marketplace add https://g.hz.netease.com/cloudmusic-agi/plugins/vip-claude-code-plugin.git
```

安装完成后重启 Claude Code。

### 方案二：本地安装流程

#### 1️⃣ 克隆仓库

```bash
git clone <repository-url>
cd string-claude-code-plugin
```

#### 2️⃣ 安装插件

```bash
# 复制插件到 Claude Code 插件目录
cp -r plugins/summarizer ~/.claude/plugins/
```

#### 3️⃣ 重启 Claude Code

重启后插件会自动加载生效。

---

## 📂 项目结构

```
string-claude-code-plugin/
├── README.md                           # 本文档
├── .claude-plugin/                     # 插件市场配置
│   └── marketplace.json               # 插件市场元数据
├── document/                           # 文档资料
│   └── skill_best_practices.md        # Skill 开发最佳实践
└── plugins/                            # 插件目录
    └── summarizer/                     # 多模态内容摘要工具
        ├── .claude-plugin/             # 插件配置目录
        │   └── plugin.json            # 插件元数据
        ├── .mcp.json                  # MCP 服务器配置
        └── skills/                     # Skill 技能
            └── summarizer/
                ├── SKILL.md           # AI 行为指南
                ├── assets/            # 模板资源
                │   └── summary_template.md  # 摘要模板
                ├── references/        # 参考指南
                │   └── content_extraction_guidelines.md  # 内容提取指南
                └── scripts/           # 辅助工具
                    └── content_extractor.py  # 内容提取器
```

---

## 🔧 插件开发指南

### 插件结构规范

每个插件应遵循以下结构：

```
plugin-name/
├── .claude-plugin/
│   └── plugin.json                    # 插件元数据
├── .mcp.json                          # MCP 服务器配置（可选）
├── skills/
│   └── skill-name/
│       ├── SKILL.md                   # AI 行为指南
│       ├── assets/                    # 模板资源
│       ├── references/                # 参考指南
│       └── scripts/                   # 辅助工具
└── README.md                          # 插件文档
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
    "license": "MIT",
    "keywords": ["关键词1", "关键词2"]
}
```

---

## 🤝 贡献指南

欢迎贡献新插件或改进现有插件！

### 贡献流程

1. **Fork 仓库**
2. **创建特性分支**：
   ```bash
   git checkout -b plugin/your-plugin-name
   ```
3. **开发插件**：
   - 遵循项目结构规范
   - 编写完整的 README.md
   - 提供安装和配置指南
4. **测试验证**：
   - 在本地 Claude Code 中测试
   - 确保文档准确性
5. **提交 PR**：
   - 详细描述插件功能
   - 附上使用截图或演示

### 插件提交清单

- [ ] 完整的 `.claude-plugin/plugin.json`
- [ ] 详细的 `README.md`（包含使用示例）
- [ ] 清晰的 `SKILL.md`（定义明确的角色和工作流程）
- [ ] 必要的 `install.sh`（MCP 插件必需）
- [ ] 在本地 Claude Code 中测试通过
- [ ] 文档准确无误
- [ ] 遵循项目的目录结构规范

---

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件。

---

## 📞 联系方式

- **项目维护者**：String Zhao
- **邮箱**：zhaoguixiong@corp.netease.com
- **仓库地址**：https://g.hz.netease.com/cloudmusic-agi/plugins/vip-claude-code-plugin.git

---

## 🙏 致谢

感谢所有贡献者和用户的支持！特别感谢 Claude Code 团队提供的优秀平台。

