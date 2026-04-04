---
name: autopilot-codex
description: 在 Codex 中使用本仓库的 autopilot 全闭环 runtime 时使用。适用于用户提到 /autopilot、自动驾驶、红蓝对抗、设计审批、五层 QA、或希望在 Codex 中继续使用 autopilot 的场景。不要在 Claude Code 插件运行时文件上直接操作。
---

# Autopilot for Codex

这是本仓库 `autopilot` 的 Codex 兼容入口。目标是在 Codex 中恢复与 Claude autopilot 等价的 phase-state runtime，而不是停留在“方法论兼容”。

## 基线文件

把以下文件当作只读基线：

- `plugins/autopilot/skills/autopilot/SKILL.md`
- `plugins/autopilot/skills/autopilot/references/`

Claude 专有机制只作为行为 oracle，不直接把运行时写回 `.claude/`。

## Codex 兼容边界

- 运行时状态文件：`.codex/autopilot.local.md`
- 不要写入 `.claude/autopilot.local.md`
- 可以依赖 repo-local `.codex/hooks.json` 的 `Stop` runtime
- `.autopilot/` 可作为只读知识库
- 不恢复历史 plugin-sync、bridge、watcher

## Runtime Helpers

先解析状态脚本路径：

```bash
AUTOPILOT_STATE_SCRIPT="$(git rev-parse --show-toplevel 2>/dev/null)/codex/plugins/autopilot-codex/assets/scripts/autopilot_state.py"
if [ ! -f "$AUTOPILOT_STATE_SCRIPT" ]; then
  AUTOPILOT_STATE_SCRIPT="${CODEX_HOME:-$HOME/.codex}/plugins/cache/string-codex-plugins/autopilot-codex/local/assets/scripts/autopilot_state.py"
fi
```

统一使用它管理状态：

```bash
python3 "$AUTOPILOT_STATE_SCRIPT" start --goal "<GOAL>"
python3 "$AUTOPILOT_STATE_SCRIPT" approve [--feedback "<TEXT>"]
python3 "$AUTOPILOT_STATE_SCRIPT" revise --feedback "<TEXT>"
python3 "$AUTOPILOT_STATE_SCRIPT" status [--json]
python3 "$AUTOPILOT_STATE_SCRIPT" cancel [--reason "<TEXT>"]
```

## 用户意图映射

把当前用户请求视为以下两类之一：

1. 启动新流程
2. 控制已有流程：`approve` / `revise <反馈>` / `status` / `cancel`

如果请求更像提交或诊断：

- `autopilot commit` -> `$autopilot-commit-codex`
- `autopilot doctor` -> `$autopilot-doctor-codex`

## 状态写回规则

- 每次改 `phase`、`gate`、`retry_count`、`qa_scope`、`updated_at`，先写回 `.codex/autopilot.local.md`
- design 必须写完 `## 目标`、`## 设计文档`、`## 实现计划`、`## 验证方案`
- implement 必须把红队产物写回 `## 红队验收测试`
- qa / auto-fix 必须把每轮证据追加到 `## QA 报告`，不要覆盖旧轮次
- merge 结束前把最终摘要写回状态文件，再设 `phase=done`

## 工作流

### 1. 启动或恢复

- 新目标：运行 `start`，然后继续当前 phase
- 控制命令：运行对应子命令；如果 phase 被推进到活跃阶段（含 `auto-fix`、`merge`），在同一轮继续推进
- 如果没有状态文件，`approve/revise/status/cancel` 直接说明没有活跃 autopilot

### 2. Design

- 读取 `.autopilot/index.md`；没有索引时退回读 `decisions.md` 和 `patterns.md`
- 探索代码库，识别技术栈、现有模式、测试框架、可复用模块
- 在状态文件中写入：
  - `## 目标`
  - `## 设计文档`
  - `## 实现计划`
  - `## 验证方案`
- 设计产物至少包含：
  - 目标
  - 技术方案
  - 文件影响范围
  - 风险评估
  - 测试策略
  - 1-3 个真实场景验证步骤
- 必须启动 plan reviewer 子代理，最多 2 轮
- 完成后设置 `gate: "design-approval"` 并停下等待用户审批

### 3. Implement

- 先基于设计产出红队验收标准，再进入编码
- 必须并行启动蓝队和红队子代理
- 红队只能看到目标 + 设计文档，不能看到实现计划和蓝队新代码
- 红队产物必须写回 `## 红队验收测试`
- 如果子代理不可用：
  - 记录 `FORCED DOWNGRADE`
  - 红队降级为验收清单后才能继续
- 实现完成后进入 `phase=qa`

### 4. QA

固定顺序：

1. Tier 0 红队验收
2. Tier 1 类型/lint/测试/构建
3. Tier 1.5 真实场景验证
4. Tier 2 设计 reviewer + 代码质量 reviewer，并行
5. Tier 3 / Tier 4 集成与回归

如果 QA 失败：

- 先把失败证据写入 `## QA 报告`
- 设置 `phase=auto-fix`
- `retry_count += 1`
- 最多 3 轮

如果 QA 通过：

- 设置 `qa_scope=""`
- 设置 `phase=merge`
- 设置 `gate=review-accept`
- 向用户展示验收摘要并等待 `approve` 或 `revise`

### 5. Auto-fix

- 逐项记录失败原因、根因假设、修复动作、重跑结果
- 绝不修改红队验收标准
- `retry_count < max_retries`：设置 `qa_scope="selective"`，再回到 `phase=qa`
- `retry_count >= max_retries`：记录未解决项，设置 `gate=review-accept`，停下让用户决策

### 6. Merge

- 需要提交时调用 `$autopilot-commit-codex`
- 不需要立即提交时保留状态文件，直到进入 `done`
- 结束前把最终摘要写回状态文件，再设 `phase=done`

### 7. Cancel / Done

- `cancel`：设为 `cancelled` 并记录原因，由 Stop hook 清理
- `done`：由 Stop hook 清理

## 输出要求

- 汇报保持简洁
- 审批门必须显式停下等待用户
- 不把 Codex runtime 写回 `.claude/`
