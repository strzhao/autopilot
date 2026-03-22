# worktree-setup

Claude Code plugin that auto-initializes git worktrees when using `claude -w <name>`.

## 功能

- **自动创建符号链接**：`.env.local`、`.mcp.json` 等 gitignored 配置文件
- **自动安装依赖**：识别 npm/yarn/pnpm，自动运行 install（含 `prisma generate`）
- **确定性端口分配**：基于分支名 hash，每个 worktree 固定端口（4001-4999），避免冲突
- **知识目录共享**：自动将 `.claude/knowledge/` 符号链接到主仓库，所有 worktree 共享同一份知识库
- **手动修复命令**：`/worktree-setup:repair` 修复已有 worktree

## 安装

```bash
/plugin install --user-scope ./plugins/worktree-setup
```

安装后所有项目的 `claude -w <name>` 自动触发初始化，无需额外配置。

## 项目定制（可选）

在项目 `.claude/worktree-links` 文件中声明需要符号链接的文件：

```
# 相对于仓库根目录，每行一个，# 开头为注释
.env.local
.env.vercel.development
.mcp.json
```

未配置时自动链接所有 `.env*` 文件。

## 使用

```bash
# 创建 worktree（自动完成所有初始化）
claude -w feature-name

# 修复已有 worktree（在 worktree 内运行）
/worktree-setup:repair
```

## 技术说明

- `WorktreeCreate` hook **替代** git 默认行为，脚本内部调用 `git worktree add`
- stdout 只输出 worktree 路径，其他日志走 stderr（防止 Claude 静默卡住）
- `worktree-repair.sh` 被 create hook 和 repair skill 共用，逻辑不重复
