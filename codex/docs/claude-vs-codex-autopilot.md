# 原始 Claude autopilot vs 当前 Codex autopilot

这份文档记录原始 Claude autopilot 与当前 Codex autopilot 的逐阶段差异，以及本仓库已经补齐的对等实现。

| 阶段/能力 | 原始 Claude autopilot | 当前 Codex autopilot |
| --- | --- | --- |
| 启动与控制命令 | `setup.sh` 处理 `/autopilot <goal>`、`approve`、`revise`、`status`、`cancel` | `autopilot_state.py` 处理 `start`、`approve`、`revise`、`status`、`cancel` |
| 状态文件 | `.claude/autopilot.local.md` | `.codex/autopilot.local.md` |
| Session 认领 | 首次 Stop hook 用真实 `session_id` 认领状态文件 | 首次 Stop hook 用 `session_id` 认领状态文件，避免跨会话串线 |
| 自动续跑 | `Stop` hook 在非 gate 阶段 block/resume | `Stop` hook 在非 gate 阶段 block/resume |
| Design | 先设计，再写 plan，再跑 plan-reviewer | 先设计，再写状态文件，再跑 plan reviewer |
| Design 审批门 | `gate=design-approval`，显式停下等用户 | `gate=design-approval`，显式停下等用户 |
| Implement | 蓝队/红队 Agent 并行，红队只看目标和设计文档 | 蓝队/红队子代理并行，红队只看目标和设计文档 |
| Forced downgrade | Agent 工具不可用时允许降级，但必须留痕 | 子代理不可用时允许 forced downgrade，但必须写回状态文件 |
| QA | Tier 0/1/1.5/2/3/4 固定顺序，必须保留证据 | Tier 0/1/1.5/2/3/4 固定顺序，必须保留证据 |
| Auto-fix | 独立 `phase=auto-fix`，修复后回到 `qa` | 独立 `phase=auto-fix`，修复后回到 `qa` |
| 验收审批门 | QA 通过后进入 `gate=review-accept` | QA 通过或 auto-fix 达到上限后进入 `gate=review-accept` |
| Merge | 调用 commit 流程、知识沉淀、完成总结 | 调用 `$autopilot-commit-codex`、知识沉淀、完成总结 |
| 完成清理 | `phase=done` 后 Stop hook 清理 | `phase=done/cancelled` 后 Stop hook 清理 |

## 当前 Codex runtime 组成

- repo-local hooks：`.codex/hooks.json`
- 官方插件 hooks：`codex/plugins/autopilot-codex/hooks.json`
- 状态脚本：`codex/plugins/autopilot-codex/assets/scripts/autopilot_state.py`
- Stop runtime：`codex/plugins/autopilot-codex/assets/scripts/autopilot_stop.py`
- 仓库 skill：`.agents/skills/autopilot-codex/SKILL.md`
- 官方插件 skill：`codex/plugins/autopilot-codex/skills/autopilot-codex/SKILL.md`

## 已补齐的关键行为

- phase-state runtime 由 Codex Stop hook 持续推进，不再只是“设计优先提示词”
- `design-approval` 和 `review-accept` 两个审批门与 Claude 版对齐
- 红蓝子代理在 implement 阶段按并行语义执行，失败时必须记录 forced downgrade
- QA 失败后进入独立 `auto-fix` phase，而不是静默留在 QA 里
- `done` / `cancelled` 由 Stop hook 做最终清理，避免残留状态文件

## 不做的事情

- 不恢复 plugin-sync
- 不恢复私有 bridge、watcher、日志轮询
- 不把 Codex runtime 写回 `.claude/`
