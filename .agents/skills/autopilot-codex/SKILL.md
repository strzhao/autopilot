---
name: autopilot-codex
description: 在 Codex 中使用本仓库的 autopilot 工作流时使用。适用于用户提到 /autopilot、自动驾驶、红蓝对抗、设计审批、五层 QA、或希望在 Codex 中继续使用 autopilot 的场景。不要在 Claude Code 插件运行时文件上直接操作。
---

# Autopilot for Codex

这是本仓库 `autopilot` 的 Codex 兼容入口。你要复用 autopilot 的工程方法论，但不能依赖 Claude Code 专有能力。

## Codex 兼容边界

- **运行时状态文件**：使用 `.codex/autopilot.local.md`
- **不要写入** `.claude/autopilot.local.md`
- **不要依赖** Claude 的 `EnterPlanMode`、`ExitPlanMode`、`Stop hook`、`WorktreeCreate`、`WorktreeRemove`
- `.claude/knowledge/` 可作为**只读知识库**
- 需要参考历史工作流时，读取以下只读基线文件：
  - `plugins/autopilot/skills/autopilot/SKILL.md`
  - `plugins/autopilot/skills/autopilot/references/`

基线文件里的 Claude 专有机制只作为方法论参考，不直接照搬。

## 用户意图映射

把当前用户请求视为以下两类之一：

1. **启动新流程**
   - 用户描述一个要完成的目标
2. **控制已有流程**
   - `approve` / `/autopilot approve`
   - `revise <反馈>` / `/autopilot revise <反馈>`
   - `status` / `/autopilot status`
   - `cancel` / `/autopilot cancel`

如果用户请求更像提交或诊断：

- `autopilot commit` -> 引导并使用 `$autopilot-commit-codex`
- `autopilot doctor` -> 引导并使用 `$autopilot-doctor-codex`

## 状态文件

创建或更新 `.codex/autopilot.local.md`。初始化时使用 `assets/autopilot-state-template.md` 作为骨架，并填充真实值。

必须维护这些 frontmatter 字段：

- `runtime: "codex"`
- `phase: "design" | "implement" | "qa" | "merge" | "done" | "cancelled"`
- `gate: "" | "design-approval" | "review-accept"`
- `iteration`
- `retry_count`
- `max_retries`
- `started_at`
- `updated_at`
- `goal`

## 工作流

### 1. 启动或恢复流程

- 如果用户是控制命令，先读取 `.codex/autopilot.local.md`
- 如果状态文件不存在：
  - `approve` / `revise` / `status` / `cancel` 都直接告诉用户当前没有活跃的 Codex autopilot
- 如果是新目标：
  - 用模板创建状态文件
  - 写入目标、时间戳和初始 frontmatter
  - `phase=design`
  - `gate=""`
  - `retry_count=0`

### 2. Design

先做设计，不直接写代码。

- 读取 `.claude/knowledge/index.md`；没有索引时退回读 `.claude/knowledge/decisions.md` 和 `.claude/knowledge/patterns.md`
- 探索代码库，识别技术栈、现有模式、测试框架、可复用模块
- 参考 `plugins/autopilot/skills/autopilot/references/` 中的计划与审查模板
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

完成后：

- 设置 `gate: "design-approval"`
- 更新 `updated_at`
- 向用户展示设计摘要并明确等待 `approve` 或 `revise`
- 在审批前停止，不进入实现

### 3. Approve / Revise

当状态文件存在且有 gate 时：

- `approve`
  - 如果 `gate=design-approval`：进入 `phase=implement`，清空 `gate`
  - 如果 `gate=review-accept`：进入 `phase=merge`，清空 `gate`
- `revise <反馈>`
  - 把反馈追加到 `## 用户反馈`
  - 如果当前 gate 是 `design-approval`：保持 `phase=design`
  - 如果当前 gate 是 `review-accept`：回到 `phase=implement`
  - 清空 `gate`
  - `retry_count` 保持不变，除非你明确开始新的 QA 修复轮次

### 4. Implement

Codex 版不依赖 Stop hook 自循环，要在当前会话内明确推进。

- 先基于设计产出红队验收标准，再进入编码
- 如果运行时支持子代理，优先使用并行红蓝分工
- 如果不支持子代理：
  - 先写 `## 红队验收测试` 或验收检查清单
  - 再按计划实现蓝队部分
- 绝不为了让实现通过而篡改红队验收标准

实现阶段要把产出写回状态文件：

- 标记已完成任务
- 记录实现摘要
- 更新 `updated_at`

实现完成后进入 `phase=qa`

### 5. QA

执行顺序固定：

1. 红队验收测试或验收清单
2. 类型检查 / lint / 单元测试 / 构建
3. 设计文档中的真实场景验证
4. 设计符合性与代码质量审查

规则：

- 成功需要证据
- 假设需要证据
- 不允许修改红队测试来“修复”实现
- 实际用户场景验证不能跳过

如果 QA 失败：

- 进入修复循环
- `retry_count += 1`
- 最多 3 轮
- 每一轮都先解释根因，再修复，再重跑受影响验证

如果 QA 通过：

- 设置 `phase=merge`
- 设置 `gate=review-accept`
- 更新 `updated_at`
- 向用户展示验收摘要并等待 `approve` 或 `revise`

### 6. Merge

如果用户明确要提交：

- 调用 `$autopilot-commit-codex`

如果用户暂时不提交：

- 输出完成摘要
- 保留状态文件，直到用户确认后再进入 `done`

### 7. Cancel / Done

- `cancel`：把 `phase` 设为 `cancelled`，保留最后状态和取消原因，不删除文件
- 流程正式完成后：把 `phase` 设为 `done`

## 输出要求

- 面向用户的汇报保持简洁
- 设计审批和验收审批都必须显式停下等待用户
- 任何时候都不要把 Codex 的运行时产物写到 `.claude/` 的运行时文件里
