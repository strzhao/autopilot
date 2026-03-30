---
name: autopilot-codex
description: 在 Codex 中使用 autopilot 的全闭环 runtime 时使用。适用于用户提到 /autopilot、自动驾驶、设计审批、红蓝对抗、五层 QA，或希望在 Codex 中继续沿用 autopilot 方法论的场景。
---

# Autopilot for Codex

这是面向 Codex CLI 的 autopilot 全闭环入口。目标不是只复用方法论，而是在 Codex 中恢复与 Claude autopilot 等价的 phase-state runtime、审批门、红蓝攻防和 QA 闭环。

## 方法论基线

以下文件是插件内置的只读基线：

- `baselines/claude-autopilot.md`
- `references/`

把它们当作设计、红蓝攻防和 QA 模板来源。Claude 专有 runtime 机制不要直接照搬，但行为要尽量对齐。

## Codex 运行边界

- 运行时状态文件统一使用 `.codex/autopilot.local.md`
- 不要写入 `.claude/autopilot.local.md`
- `.claude/knowledge/` 只作为当前项目的只读知识库
- 可以依赖 Codex 官方 hook 能力和本插件自带的 `Stop` runtime
- 不恢复旧的 bridge、watcher、plugin-sync、私有 launcher

## Runtime Helpers

优先通过状态脚本管理状态文件，而不是手写 frontmatter。先解析脚本路径：

```bash
AUTOPILOT_STATE_SCRIPT="$(git rev-parse --show-toplevel 2>/dev/null)/codex/plugins/autopilot-codex/assets/scripts/autopilot_state.py"
if [ ! -f "$AUTOPILOT_STATE_SCRIPT" ]; then
  AUTOPILOT_STATE_SCRIPT="${CODEX_HOME:-$HOME/.codex}/plugins/cache/string-codex-plugins/autopilot-codex/local/assets/scripts/autopilot_state.py"
fi
```

控制命令统一用它：

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
   - 用户描述一个要完成的目标
2. 控制已有流程
   - `approve`
   - `revise <反馈>`
   - `status`
   - `cancel`

如果用户请求更像提交或诊断：

- `autopilot commit` -> 引导并使用 `$autopilot-commit-codex`
- `autopilot doctor` -> 引导并使用 `$autopilot-doctor-codex`

## 状态文件契约

状态文件至少维护这些 frontmatter：

- `runtime: "codex"`
- `phase: "design" | "implement" | "qa" | "auto-fix" | "merge" | "done" | "cancelled"`
- `gate: "" | "design-approval" | "review-accept"`
- `iteration`
- `max_iterations`
- `retry_count`
- `max_retries`
- `session_id`
- `qa_scope`
- `started_at`
- `updated_at`
- `goal`

## 状态写回规则

- 每次修改 `phase`、`gate`、`retry_count`、`qa_scope`、`updated_at` 时，先把 `.codex/autopilot.local.md` 写对，再结束当前回复
- 设计阶段至少写完 `## 目标`、`## 设计文档`、`## 实现计划`、`## 验证方案`
- 实现阶段必须把红队产物写回 `## 红队验收测试`，并在 `## 变更日志` 留下并行执行或 forced downgrade 记录
- QA 和 auto-fix 不能覆盖旧证据；在 `## QA 报告` 里追加新的轮次结果、失败项、修复证据和重跑结果
- merge 阶段结束前，把最终摘要与必要的知识沉淀结果写回状态文件，然后再设 `phase=done`

## 工作流

### 1. 启动或恢复流程

- 新目标：
  - 先运行 `python3 "$AUTOPILOT_STATE_SCRIPT" start --goal "<GOAL>"`
  - 然后读取 `.codex/autopilot.local.md` 并立刻进入当前 phase 工作流
- 控制命令：
  - `approve` -> 运行 `approve`
  - `revise <反馈>` -> 运行 `revise`
  - `status` -> 运行 `status`
  - `cancel` -> 运行 `cancel`
- 如果控制命令执行后 phase 仍是活跃阶段（如 `implement`、`auto-fix` 或 `merge`），在同一轮继续推进；不要只改状态不推进

### 2. Design

先做设计，不直接写代码。

- 如果当前项目有 `.claude/knowledge/index.md`，先读索引并按需加载最多 3 个相关知识文件
- 如果没有索引但存在 `.claude/knowledge/`，退回读取 `decisions.md` 和 `patterns.md`
- 探索代码库，识别技术栈、现有模式、测试框架、可复用模块
- 在状态文件中写入：
  - `## 目标`
  - `## 设计文档`
  - `## 实现计划`
  - `## 验证方案`

设计产物至少包含：

- 目标
- 技术方案
- 文件影响范围
- 风险评估
- 测试策略
- 1-3 个真实场景验证步骤

设计完成后必须启动 plan reviewer 子代理：

- 使用 `references/plan-reviewer-prompt.md`
- 最多 2 轮审查
- 第 2 轮仍有 blocker 时，把 blocker 写回状态文件并交给用户判断

完成后：

- 设置 `gate: "design-approval"`
- 更新 `updated_at`
- 向用户展示设计摘要并等待 `approve` 或 `revise`

### 3. Implement

实现阶段必须先产出红队验收标准，再进入编码。

- 必须并行启动两个子代理：
  - 蓝队：按设计文档 + 实现计划编码
  - 红队：只看目标 + 设计文档，不能看实现计划和蓝队新代码
- 红队产物必须写回 `## 红队验收测试`
- 绝不为了让实现通过而篡改红队验收标准

如果子代理工具不可用或调用失败：

- 先把失败原因写入 `## 变更日志`
- 标记这是 `FORCED DOWNGRADE`
- 红队降级为本地验收检查清单后，蓝队才能继续实现

实现阶段要写回状态文件：

- 已完成任务
- 实现摘要
- forced downgrade 记录（如果有）
- 红队验收测试或验收清单
- `updated_at`

实现完成后进入 `phase=qa`

### 4. QA

执行顺序固定：

1. Tier 0：红队验收测试或验收清单
2. Tier 1：类型检查 / lint / 单元测试 / 构建
3. Tier 1.5：设计文档中的真实场景验证
4. Tier 2：设计符合性 reviewer + 代码质量 reviewer，并行启动
5. Tier 3 / Tier 4：集成验证与回归检查（按影响范围执行）

规则：

- 成功需要证据
- 假设需要证据
- 不允许修改红队测试来“修复”实现
- 实际用户场景验证不能跳过

如果 QA 失败：

- 在 `## QA 报告` 追加失败证据
- 设置 `phase=auto-fix`
- `retry_count += 1`
- 最多 3 轮
- 每一轮都先解释根因，再修复，再重跑受影响验证

如果 QA 通过：

- 设置 `qa_scope=""`
- 设置 `phase=merge`
- 设置 `gate=review-accept`
- 更新 `updated_at`
- 向用户展示验收摘要并等待 `approve` 或 `revise`

### 5. Auto-fix

- 先读取最近一轮 `## QA 报告`，逐项列出失败原因、根因假设、修复动作和重跑证据
- 绝不修改红队验收标准；只能修实现、配置、测试夹具或验证路径
- 如果 `retry_count < max_retries`：
  - 设置 `qa_scope="selective"`
  - 设置 `phase=qa`
  - 更新 `updated_at`
  - 回到 QA，只重跑受影响层级
- 如果 `retry_count >= max_retries`：
  - 在 `## QA 报告` 记录仍未解决项
  - 设置 `gate=review-accept`
  - 更新 `updated_at`
  - 显式停下等待用户决定继续 revise 还是接受当前风险

### 6. Merge

- 如果用户明确要提交：
  - 调用 `$autopilot-commit-codex`
- 如果用户暂时不提交：
  - 输出完成摘要
  - 保留状态文件，直到用户确认或流程自行进入 `done`
- 完成后把最终摘要和必要的知识沉淀写回状态文件，再设置 `phase=done`

### 7. Cancel / Done

- `cancel`：先把 `phase` 设为 `cancelled`，记录取消原因；Stop hook 会在本轮结束后清理状态文件
- 正式完成后：把 `phase` 设为 `done`；Stop hook 会自动清理状态文件

## 完成提示音

- 当你因为 `design-approval`、`review-accept`、`done` 或 `cancelled` 准备把控制权还给用户时，尽力播放一次完成提示音
- Stop hook 也会兜底触发提示音，因此不要把播放失败当成任务失败

## 输出要求

- 面向用户的汇报保持简洁
- 设计审批和验收审批都必须显式停下等待用户
- 任何时候都不要把 Codex 的运行时产物写到 `.claude/` 的运行时文件里
- 如果当前项目仍依赖 bridge、watcher、plugin-sync，明确指出这是兼容风险，而不是复活旧方案
