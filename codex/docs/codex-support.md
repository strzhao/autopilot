# Codex Support

本仓库现在提供一套**仓库内、Codex 原生、与 Claude 插件隔离**的兼容层。

## 目标

让 Codex CLI 能直接使用本仓库的 autopilot 工作流和仓库约定，同时不影响现有 Claude Code 插件源码、插件市场配置和运行时目录。

## 入口

推荐通过仓库内启动脚本进入：

- `codex/bin/codex-local`

等价手动方式：

- `CODEX_HOME="$(git rev-parse --show-toplevel)/.codex" codex`

这样 Codex 会读取：

- `.codex/AGENTS.md`
- `.agents.md`（通过 `.codex/config.toml` 中的 `project_doc_fallback_filenames`）
- `.codex/hooks.json`
- `.agents/skills/*`

可直接使用的技能：

- `$autopilot-codex`
- `$autopilot-commit-codex`
- `$autopilot-doctor-codex`

## 与 Claude 侧的隔离方式

- Claude 插件源码仍然在 `plugins/`
- Claude 插件市场配置仍然是 `.claude-plugin/marketplace.json`
- 根目录 `AGENTS.md` 继续保留给 Claude 侧既有软链接，不作为本次 Codex 兼容层写入目标
- Codex 运行时状态和报告统一写入 `.codex/`
- `.autopilot/` 只作为共享知识库读取，不作为 Codex 运行时状态目录

## 路径约定

### Codex 运行时

- autopilot 状态：`.codex/autopilot.local.md`
- doctor 报告：`.codex/doctor-report.md`
- hooks：`.codex/hooks.json`
- repo-local `CODEX_HOME` 引导：`.codex/AGENTS.md`
- repo-local 配置：`.codex/config.toml`

### Codex 技能

- `.agents/skills/autopilot-codex`
- `.agents/skills/autopilot-commit-codex`
- `.agents/skills/autopilot-doctor-codex`

### Codex 项目说明

- `.agents.md`

## 设计原则

- 官方能力优先：项目说明 fallback、`.agents/skills`、`.codex/hooks.json`
- 不恢复历史 `plugin-sync`
- 不依赖私有 bridge、watcher、session 日志轮询
- 不把 Codex 的临时状态写回 Claude 的运行时文件

当前 repo-local `.codex/hooks.json` 还承载 autopilot 的 phase-state runtime，不再只是轻量提示层；它会推进 `design -> implement -> qa -> auto-fix -> merge` 并在审批门停下。

## 使用建议

如果你习惯 Claude Code 的说法，可以这样映射：

- `/autopilot ...` -> `$autopilot-codex`
- `/autopilot commit` -> `$autopilot-commit-codex`
- `/autopilot doctor` -> `$autopilot-doctor-codex`

如果 Codex 会话里用户直接写了 Claude 风格命令，`UserPromptSubmit` hook 会补充提示并引导继续 `$autopilot-codex`，但不会恢复旧式 bridge 转换。

逐阶段差异和对等实现见：

- `codex/docs/claude-vs-codex-autopilot.md`
