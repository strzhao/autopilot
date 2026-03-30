---
name: autopilot-commit-codex
description: 在 Codex 中执行 autopilot 风格的智能提交时使用。适用于用户提到 autopilot commit、git commit、智能提交、提交代码、生成中文提交信息等场景。
---

# Autopilot Commit for Codex

这是 Claude 版 `autopilot-commit` 的 Codex 兼容入口。

## 基线文件

把以下文件当作详细工作流基线：

- `plugins/autopilot/skills/autopilot-commit/SKILL.md`

先读取基线，再按下面的 Codex 覆盖规则执行。

## Codex 覆盖规则

- Codex 版主链路状态文件使用 `.codex/autopilot.local.md`，不要读取 `.claude/autopilot.local.md`
- Codex 中没有 Claude 的 `AskUserQuestion`，需要用户输入时直接在对话中提问
- 如果要更新项目文档：
  - **Codex-facing 规则** 优先更新 `.agents.md`，必要时同步更新 `.codex/AGENTS.md`
  - 本仓库不要直接更新根目录 `AGENTS.md`，因为它是指向 `CLAUDE.md` 的既有软链接
  - **Claude-facing 规则** 仅当改动确实影响 Claude 插件说明时才更新 `CLAUDE.md`
- 不依赖 Claude 专有插件 hooks 或 Session 变量

## 执行要求

- 先看 git 状态与改动内容
- 按基线工作流决定 commit type
- 需要 bugfix 证据时，优先运行真实验证
- 生成中文提交信息，格式仍保持：
  - `type(scope): 业务描述 (技术说明)`
- 如果 `ai-todo` 可用，按基线逻辑同步任务

## 上下文感知

如果 `.codex/autopilot.local.md` 存在且当前 `phase=merge`：

- 视为主链路模式
- 跳过会破坏已验证状态的重复优化
- 保留必要的提交前检查和最终总结

否则按独立模式完整执行。
