# Official Codex Plugin Flow

本仓库现在同时提供两条路：

- **官方主路径**：Codex 官方 plugin 机制
- **辅助管理路径**：仓库内 `string-codex-plugin` CLI，底层仍调用 Codex 官方 `plugin/install` / `plugin/uninstall`

推荐以后都以官方 plugin 为主，不再依赖 repo-local launcher、`CODEX_HOME=...`、bridge、watcher、plugin-sync。

## 跨仓库生效的关键点

Codex 官方 app-server 在非当前仓库目录里，只会自动发现：

- 官方 curated marketplace
- home-scoped personal marketplace：`~/.agents/plugins/marketplace.json`

所以如果只在当前仓库里有 `.agents/plugins/marketplace.json`，插件会表现成“当前目录能看到，别的仓库看不到”。

本仓库现在的做法是：

- 仓库内继续保留 repo marketplace：`.agents/plugins/marketplace.json`
- 同时把同一插件源同步到 home-scoped marketplace：`~/.agents/plugins/marketplace.json`
- home marketplace 通过 `~/.agents/plugins/string-codex-plugins/autopilot-codex` 这个本地链接指回仓库内插件源

这样安装完成后，在 `../ai-todo` 之类没有 repo-local Codex 标记的仓库里，`Autopilot for Codex` 也仍然可发现、可启用。

## 这次新增了什么

- Repo marketplace：`.agents/plugins/marketplace.json`
- 官方 Codex plugin 包：`codex/plugins/autopilot-codex/`
- 全局安装/卸载辅助命令：`codex/bin/string-codex-plugin`
- 官方 Stop hook runtime：`codex/plugins/autopilot-codex/assets/scripts/autopilot_stop.py`

这些都只新增或修改 Codex 侧文件，没有改动现有 Claude plugin、Claude marketplace、README、CLAUDE.md 或已有插件源码。

## 官方安装方式

第一次安装时，进入本仓库后用 Codex 自带的 `/plugins`：

1. `cd /Users/stringzhao/workspace_sync/personal_projects/string-claude-code-plugin`
2. 先执行一次 `/Users/stringzhao/workspace_sync/personal_projects/string-claude-code-plugin/codex/install-global.sh`
3. `codex`
4. 输入 `/plugins`
5. 在 `String Codex Plugins` marketplace 里安装 `Autopilot for Codex`

安装完成后，插件会由 Codex 自己放到全局插件缓存中；`install-global.sh` 也会同步 personal marketplace。后续你在任意工作目录下直接执行 `codex` 即可，不需要再改启动方式。

可用技能：

- `$autopilot-codex`
- `$autopilot-commit-codex`
- `$autopilot-doctor-codex`

## 辅助 CLI

如果你不想每次走 `/plugins` 菜单，可以用仓库内辅助 CLI：

```bash
/Users/stringzhao/workspace_sync/personal_projects/string-claude-code-plugin/codex/bin/string-codex-plugin install
/Users/stringzhao/workspace_sync/personal_projects/string-claude-code-plugin/codex/bin/string-codex-plugin list
/Users/stringzhao/workspace_sync/personal_projects/string-claude-code-plugin/codex/bin/string-codex-plugin doctor
/Users/stringzhao/workspace_sync/personal_projects/string-claude-code-plugin/codex/bin/string-codex-plugin sync-home-marketplace
/Users/stringzhao/workspace_sync/personal_projects/string-claude-code-plugin/codex/bin/string-codex-plugin uninstall
```

这个 CLI 不是运行时 shim。它除了封装官方插件安装 RPC，还会维护 home-scoped marketplace，确保插件在其他仓库目录下也能被 Codex 发现。

## API Key 模式说明

`string-codex-plugin install --force-remote-sync` 只有在 ChatGPT 登录态下才能成功。

如果当前机器是 API key 鉴权，Codex 会返回类似：

```text
chatgpt authentication required for remote plugin mutation; api key auth is not supported
```

因此本仓库不再把 remote sync 当作跨仓库可见性的前提，而是显式维护 `~/.agents/plugins/marketplace.json` 这条官方 home-scoped 路径。

## 卸载方式

两种都可以：

- 官方：`codex` -> `/plugins` -> uninstall `Autopilot for Codex`
- 辅助 CLI：`codex/bin/string-codex-plugin uninstall`

## 设计约束

- Codex runtime 继续写 `.codex/`
- 不把 Codex runtime 写入 `.claude/`
- 不修改现有 Claude plugin 文件
- 不恢复旧 `codex-sync`、bridge、watcher、软链接同步方案
- 运行时阶段与 Claude 版尽量对齐：`design -> implement -> qa -> auto-fix -> merge`

对等实现对照表见：

- `codex/docs/claude-vs-codex-autopilot.md`
