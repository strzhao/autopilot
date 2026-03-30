# Codex Home Guide

本目录设计为本仓库的 repo-local `CODEX_HOME`。

如果你是通过 `codex/bin/codex-local` 或手动设置：

- `CODEX_HOME="$(git rev-parse --show-toplevel)/.codex" codex`

启动 Codex，那么本目录提供以下能力：

- `config.toml`：启用 `codex_hooks`，并把项目说明 fallback 指向根目录 `.agents.md`
- `hooks.json`：在会话开始和用户提交 prompt 时补充轻量提示
- `.codex/`：存放 Codex 的运行时状态和报告

## 运行约束

- 不要把 Codex 的运行时状态写到 `.claude/`。
- `.claude/knowledge/` 只作为共享知识库读取。
- 如果需要仓库工作流，请优先使用：
  - `$autopilot-codex`
  - `$autopilot-commit-codex`
  - `$autopilot-doctor-codex`

## 仓库说明来源

项目级说明来自根目录 `.agents.md`，不是根目录 `AGENTS.md`。

原因是这个仓库里根目录 `AGENTS.md` 是既有 Claude 软链接，不能作为 Codex 兼容层的写入目标。
