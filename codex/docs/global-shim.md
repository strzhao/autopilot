# Global Codex Shim

如果你希望继续保持原始使用习惯：

```bash
cd <你的工作目录>
codex
```

那么推荐安装本仓库提供的全局薄 shim，而不是记新的启动命令。

## 安装

```bash
/Users/stringzhao/workspace_sync/personal_projects/string-claude-code-plugin/codex/install-global.sh
exec zsh
```

安装后行为如下：

- 你继续直接执行 `codex`
- 当当前目录位于某个 git 仓库中，且该仓库包含 `.codex/hooks.json` 时，自动启用 `features.codex_hooks=true`
- 当该仓库包含 `.agents.md` 时，自动把它作为 `model_instructions_file`
- 没有这些文件的仓库，不受影响，直接走原始 `codex`

## 卸载

```bash
/Users/stringzhao/workspace_sync/personal_projects/string-claude-code-plugin/codex/uninstall-global.sh
exec zsh
```

## 临时绕过

如果某次你想跳过 shim，直接运行底层 `codex`：

```bash
CODEX_SHIM_DISABLE=1 codex
```

## 为什么这是更好的方案

- 不改变日常习惯
- 安装一次，全局生效
- 卸载只需一个命令
- 真正的仓库逻辑仍然留在 repo 内：
  - `.agents.md`
  - `.codex/hooks.json`
  - `.agents/skills/`
