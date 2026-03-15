---
name: repair
description: Repair an existing Claude Code worktree — re-create missing symlinks and reinstall dependencies. Use when a worktree is missing .env files or node_modules.
disable-model-invocation: true
allowed-tools: Bash
---

修复当前 worktree 的配置：补全缺失的符号链接和依赖安装。

## 操作步骤

1. 确认当前目录是一个 worktree（`.git` 是文件而非目录）
2. 运行修复脚本：

```bash
bash "${CLAUDE_SKILL_DIR}/../../scripts/worktree-repair.sh" "$(pwd)"
```

3. 报告结果：哪些文件被链接、哪些已存在、依赖是否重装

## 适用场景

- Worktree 创建后 `.env.local` 等配置文件缺失
- `node_modules` 不存在或已损坏
- 通过 `git worktree add` 手动创建的 worktree 需要初始化
- hook 执行中断导致初始化不完整
