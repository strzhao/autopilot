# Autopilot — Claude Code 自动驾驶工程套件

<div align="center">

**从目标描述到代码合并，全程自动化**

[![Plugins](https://img.shields.io/badge/plugins-7-blue.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Compatible-green.svg)](https://claude.ai/code)
[![License](https://img.shields.io/badge/license-MIT-orange.svg)](LICENSE)

</div>

---

## 这是什么

Autopilot 是一套 Claude Code 插件集合，核心是 **autopilot 自动驾驶工程套件**——你只需要描述目标，它就能自动完成设计、编码、测试、修复、提交的全流程闭环。

一句话：**把 AI 从"辅助编程"升级到"自动驾驶"。**

---

## 核心能力

### `/autopilot <目标描述>` — 全流程闭环

```
目标描述 → 设计方案 → [你审批] → 红蓝对抗编码 → 五层 QA → 自动修复 → [你验收] → 合并
```

- **红蓝对抗**：蓝队按方案编码，红队仅看设计文档写验收测试——信息隔离确保测试独立于实现
- **五层 QA**：红队验收测试 → 类型/Lint/单元测试/构建 → 真实场景冒烟 → 设计符合性审查 → 代码质量审查
- **自动修复**：QA 失败项自动定位根因、修复、重跑，最多 3 轮
- **知识工程**：自动积累项目决策和调试教训，越用越聪明
- **你只需介入 2 次**：设计审批 + 验收审批

### `/autopilot commit` — 智能提交

不只是 `git commit`。它会自动做代码优化、生成高质量中文提交信息、更新 CLAUDE.md、版本升级、ai-todo 同步。

### `/autopilot doctor` — 工程健康度诊断

10 维度评分（测试/类型/lint/构建/CI/结构/文档/Git/依赖/AI就绪度），S-F 六级评分，告诉你项目哪里需要改进。`--fix` 模式自动修复。

---

## 生态插件

除了核心的 autopilot，还提供以下实用插件：

| 插件 | 功能 | 一句话描述 |
|------|------|-----------|
| **worktree-setup** | Git Worktree 自动初始化 | `claude -w <name>` 后自动链接配置、安装依赖、分配端口，开箱即用 |
| **writer-skill** | 写作技能包 | 博客向 / 通用向 / 技术文档向三种风格 |
| **npm-toolkit** | npm 发布 + GitHub Actions | OIDC 自动发布（无需 token）+ CI/CD 工作流配置 |
| **summarizer** | 多模态内容摘要 | 文章/视频/音频自动提取 + 结构化摘要 + flomo 保存 |
| **task-notifier** | 任务完成提示音 | 任务执行完自动播放系统提示音，跨平台支持 |
| **plugin-sync** | 跨模型插件同步 | 解决 `cc switch` 切换模型后插件丢失问题 |

---

## 快速开始

### 方案一：插件市场安装（推荐）

在 Claude Code 中执行：

```bash
/plugin marketplace add https://github.com/strzhao/autopilot.git
```

然后按需安装你想用的插件。

### 方案二：单插件安装

```bash
git clone https://github.com/strzhao/autopilot.git
cd autopilot
# 安装 autopilot 核心
/install plugins/autopilot
# 安装其他插件（按需）
/install plugins/worktree-setup
/install plugins/writer-skill
```

重启 Claude Code 后生效。

---

## 许可证

MIT

---

## 联系方式

- **维护者**：String Zhao
- **邮箱**：zhaoguixiong@corp.netease.com
- **仓库**：https://github.com/strzhao/autopilot
