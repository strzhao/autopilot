# Migration From plugin-sync

本仓库历史上曾经有过一版 `plugin-sync`，目的是在 `cc switch` 或多模型目录下共享 Claude 插件状态。

对应历史提交：

- 引入：`55f7ab2 feat(plugins): add plugin-sync for cross-model plugin synchronization`
- 移除：`d124641 chore: 移除 plugin-sync 插件`

## 旧方案做了什么

旧方案的核心思路是：

- 用软链接共享 `~/.claude/plugins`
- 在会话开始或插件安装后，用自定义 hooks 做同步
- 维护一份额外的共享启用配置

## 为什么不恢复旧实现

旧实现的问题不在“目标”，而在“机制”：

- 强依赖私有运行时目录结构
- 软链接方案侵入性强，容易影响所有模型实例
- hooks 需要模拟大量运行时事件，稳定性差
- 对 Codex 来说，这类 bridge/watch 方案长期维护成本高，且经常出问题

## 现在的替代方案

当前 Codex 支持改为官方仓库级入口：

- `.codex/AGENTS.md`
- `.agents.md`（通过 `project_doc_fallback_filenames`）
- `.agents/skills`
- `.codex/hooks.json`

对应思路是：

- **共享工作流语义**，不共享运行时目录
- **共享只读参考资料**，不共享 Claude 的状态文件
- **把 Codex 状态写到 `.codex/`**，避免污染 `.claude/`

## 当前边界

这次恢复的是**Codex 兼容层**，不是旧 `plugin-sync` 的回归：

- 没有软链接共享目录
- 没有插件安装后自动同步
- 没有 bridge、watcher、日志轮询
- 没有模拟 Claude 的 WorktreeCreate/Remove 事件

## 为什么不用根目录 AGENTS.md

这个仓库里根目录 `AGENTS.md` 是既有软链接，指向 `CLAUDE.md`。

如果直接把 Codex 指令写进根目录 `AGENTS.md`，实际会改动现有 `CLAUDE.md`，违背“只新增文件、不影响 Claude 插件”的约束。

因此当前替代方案是：

- 保留根目录 `AGENTS.md -> CLAUDE.md`
- 新增 `.agents.md` 作为 Codex 项目说明
- 用 `.codex/config.toml` 把 `.agents.md` 注册成项目说明 fallback
- 用 `codex/bin/codex-local` 提供 repo-local `CODEX_HOME`

## 后续如果要继续扩展

推荐方向：

- 继续增强 `.agents/skills` 下的 Codex 工作流
- 必要时把稳定的 Codex 技能再打包成正式 Codex plugin

不推荐方向：

- 恢复 `plugin-sync`
- 重新引入私有 bridge
- 继续把 Codex 适配建立在 Claude 运行时目录和 hooks 之上
