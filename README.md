# Autopilot

Autopilot 是一套 Claude Code 插件，核心是一个完整的自动驾驶工程工作流——从你描述目标到代码合并，全程自动化。

## How it works

当你输入 `/autopilot 实现用户头像上传功能`，它**不会**直接开始写代码。

它先进入 Plan Mode，深入分析你的代码库——架构、技术栈、已有模式、可复用的工具函数——然后产出一份设计文档：技术方案、文件影响范围、风险评估、真实测试场景。这份文档会交给你审批。你可以反复修改直到满意。

审批通过后，autopilot 同时启动两个独立的 Agent：

- **蓝队**拿到设计文档和实现计划，按方案编码。
- **红队**只拿到设计文档——看不到蓝队写的任何代码——独立编写验收测试。

这种信息隔离不是偏执，而是工程纪律。红队测试代表的是设计意图，不是对已有实现的追认。如果蓝队的实现偏离了设计，红队的测试会抓住它。

编码完成后进入五层 QA。不是跑一遍测试就完事：

1. 红队验收测试 + 类型检查 + Lint + 单元测试 + 构建验证——全部并行执行
2. 真实场景冒烟测试——用 curl 调 API、启动 dev server 点页面、跑 CLI 命令——验证功能在真实用户场景下可用，不只是测试通过
3. 两个独立 AI Agent 并行做设计符合性审查和代码质量审查

QA 有失败项？autopilot 不会乱修。它按系统化调试方法论走四个阶段：观察完整错误 → 形成因果假设 → 用最小实验验证假设 → 假设被证实后才做修复。红队测试失败了？改实现，不改测试——没有例外。最多自动修复 3 轮，修不好交还给你。

全部通过后，你做最终验收，autopilot 执行智能提交并合并。整个过程中，它会自动把设计决策和调试教训沉淀到项目知识库，下次遇到类似问题时自动加载参考。

全程你只需要介入两次：设计审批和最终验收。

## What's Inside

### `/autopilot <目标>` — 全流程闭环

6 阶段状态机驱动（design → implement → qa → auto-fix → merge → done），状态持久化到文件，支持 Git Worktree 隔离。

- **红蓝对抗编码**：并行 Agent，严格信息隔离。支持领域 Skill 委托——如果项目有已验证的专业 Skill，自动路由过去而非从零实现，失败则回退到红蓝对抗
- **五层 QA**：三波执行（Wave 1 命令并行 → Wave 1.5 真实场景冒烟 → Wave 2 并行 AI 审查）。内置防合理化机制，覆盖"dev server 太重"、"jest 已验证"等 5 种常见跳过借口。修复后选择性重跑失败项，节省 30-50% 重试时间
- **系统化调试**：观察 → 假设 → 验证 → 修复，拒绝 shotgun fix。红队测试铁律：问题在实现不在测试
- **知识工程**：三层 Progressive Disclosure（索引层 → 全局层 → 领域分区），两阶段检索（≤5s 索引扫描 → ≤10s 按需加载）。merge 阶段自动提取决策和教训，同步索引

贯穿全流程的两条核心原则：**成功需要证据**（命令输出、测试结果，"我检查了"不算）和**假设需要证据**（对外部系统的假设必须运行时验证，不能仅凭文档）。

### `/autopilot commit` — 智能提交

三阶段并行执行模型。分析改动 → 代码优化（React 最佳实践 + 简化）→ Bugfix 双模式验证 + 代码理解测验 + 元数据更新——并行执行 → 提交 + 任务同步。

上下文感知：检测到代码已通过五层 QA 时，自动跳过优化和测验——再优化可能破坏已验证状态。

代码理解测验考的是设计权衡和失败模式（"如果上游返回的数据结构和预期不同会怎样？"），不是语法细节。Vibe Coding 时代，开发者的核心价值是有效监督 AI 产出。

### `/autopilot doctor` — 工程健康度诊断

10 维度加权评分（测试 20% / 类型 15% / Lint 10% / 构建 10% / CI 10% / 结构 10% / 文档 10% / Git 8% / 依赖 2% / AI 就绪度 5%），S-F 六级评分。

输出 autopilot 兼容性矩阵：将 9 项核心功能映射到依赖维度，告诉你具体哪项功能会因为基础设施不足而降级。`--fix` 模式对低分维度自动生成修复方案，逐项确认后应用。

### Worktree 自动初始化

`claude -w <name>` 创建 worktree 后自动完成初始化：按 `.claude/worktree-links` 创建符号链接（.env、.mcp.json 等）、确定性端口分配（避免多 worktree 冲突）、自动识别包管理器安装依赖。退出时自动清理。`/worktree-repair` 可手动修复配置缺失。

---

## 生态插件

除了核心的 autopilot，还提供以下实用插件：

| 插件 | 一句话描述 |
|------|-----------|
| **writer-skill** | 博客向 / 通用向 / 技术文档向三种写作风格 |
| **npm-toolkit** | OIDC 自动发布（无需 token）+ GitHub Actions CI/CD 配置 |
| **summarizer** | 文章/视频/音频自动提取 + 结构化摘要 + flomo 保存 |
| **task-notifier** | 任务执行完自动播放系统提示音 |

---

## 快速开始

### Claude Code 安装

以下方式是给 **Claude Code** 用的。

#### 插件市场安装（推荐）

```bash
/plugin marketplace add https://github.com/strzhao/autopilot.git
```

然后按需安装你想用的插件。

#### 手动安装

```bash
git clone https://github.com/strzhao/autopilot.git
cd autopilot
/install plugins/autopilot
```

重启 Claude Code 后生效。

### Codex CLI 安装

以下方式是给 **Codex CLI** 用的，目前提供的是 `Autopilot for Codex` 插件包，对应技能：

- `$autopilot-codex`
- `$autopilot-commit-codex`
- `$autopilot-doctor-codex`

#### 官方安装方式（推荐）

```bash
git clone https://github.com/strzhao/autopilot.git
cd autopilot
codex
```

进入 Codex 后输入：

```text
/plugins
```

然后在 `String Codex Plugins` marketplace 里安装 `Autopilot for Codex`。

安装完成后，后续你可以在任意工作目录直接执行 `codex` 使用，不需要继续从本仓库启动。

#### 命令行安装方式

```bash
git clone https://github.com/strzhao/autopilot.git
cd autopilot
codex/bin/string-codex-plugin install
```

可选检查：

```bash
codex/bin/string-codex-plugin list
codex/bin/string-codex-plugin doctor
```

#### Codex 卸载

官方方式：

- `codex` -> `/plugins` -> uninstall `Autopilot for Codex`

命令行方式：

```bash
cd autopilot
codex/bin/string-codex-plugin uninstall
```

---

## 许可证

MIT

## 联系方式

- **维护者**：String Zhao
- **邮箱**：zhaoguixiong@corp.netease.com
- **仓库**：https://github.com/strzhao/autopilot
