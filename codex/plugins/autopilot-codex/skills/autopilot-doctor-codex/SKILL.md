---
name: autopilot-doctor-codex
description: 在 Codex 中执行 autopilot doctor 时使用。适用于用户提到 doctor、工程健康诊断、为什么 autopilot 效果不好、Codex readiness、工程成熟度评估等场景。
---

# Autopilot Doctor for Codex

这是 Claude 版 `autopilot-doctor` 的 Codex 兼容入口。

## 基线文件

把以下文件当作详细评分与检查基线：

- `baselines/claude-autopilot-doctor.md`

读取基线后，按本技能的 Codex 覆盖规则执行。

## Codex 覆盖规则

- 诊断报告写入 `.codex/doctor-report.md`
- 不写入 `.claude/doctor-report.md`
- 额外检查当前项目的 Codex readiness：
  - 是否还能在没有 repo-local launcher、bridge、watcher、plugin-sync 的情况下工作
  - `.codex/` 目录是否存在或可安全创建
  - 当前项目说明是否清晰可发现，例如 `.agents.md`、`AGENTS.md`、`CLAUDE.md` 中至少有一个能作为协作入口
  - `.autopilot/` 如果存在，结构是否足够清晰供 Codex 只读消费
  - `.codex/hooks.json` 是否包含可工作的 `Stop` runtime，而不只是轻量提示 hook
  - 是否仍在依赖旧的 bridge、watcher、plugin-sync、软链接共享目录方案
- 当用户传入 `--fix`：
  - 只修复用户明确同意的项
  - 优先修复 `.codex/` 下的问题或补充当前项目的 Codex-facing 文档
  - 不要为了 Codex 适配去改现有 Claude 插件文件，除非用户明确要求

## 输出要求

- 评分维度、加权总分、Top 问题、Top 建议沿用基线格式
- 明确区分：
  - 通用工程 readiness
  - Codex autopilot readiness
- 最终把完整报告写到 `.codex/doctor-report.md`
- 对用户的聊天摘要要短，重点给：
  - 总分
  - 最影响 autopilot 的 3 个问题
  - 最先做的 3 个改进项
