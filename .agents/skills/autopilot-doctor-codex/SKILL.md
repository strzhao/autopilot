---
name: autopilot-doctor-codex
description: 在 Codex 中执行 autopilot doctor 时使用。适用于用户提到 doctor、工程健康诊断、为什么 autopilot 效果不好、Codex readiness、工程成熟度评估等场景。
---

# Autopilot Doctor for Codex

这是 Claude 版 `autopilot-doctor` 的 Codex 兼容入口。

## 基线文件

把以下文件当作详细评分与检查基线：

- `plugins/autopilot/skills/autopilot-doctor/SKILL.md`

读取基线后，按本技能的 Codex 覆盖规则执行。

## Codex 覆盖规则

- 诊断报告写入 `.codex/doctor-report.md`
- 不写入 `.claude/doctor-report.md`
- 额外检查本仓库的 Codex readiness：
  - `.codex/AGENTS.md` 是否存在
  - `.agents.md` 是否存在
  - `.codex/config.toml` 是否存在，且已启用 `codex_hooks` 与 `project_doc_fallback_filenames`
  - `.agents/skills/` 是否存在并包含 Codex 技能
  - `.codex/hooks.json` 是否存在且 JSON 合法
  - 是否仍在依赖旧的 bridge、watcher、plugin-sync、软链接共享目录方案
- 当用户传入 `--fix`：
  - 只修复用户明确同意的项
  - 优先修复 Codex 自身目录下的问题
  - 不要为了 Codex 适配去改现有 Claude 插件文件，除非用户明确要求

## 输出要求

- 评分维度、加权总分、Top 问题、Top 建议沿用基线格式
- 明确区分：
  - Claude readiness
  - Codex readiness
- 最终把完整报告写到 `.codex/doctor-report.md`
- 对用户的聊天摘要要短，重点给：
  - 总分
  - 最影响 autopilot 的 3 个问题
  - 最先做的 3 个改进项
