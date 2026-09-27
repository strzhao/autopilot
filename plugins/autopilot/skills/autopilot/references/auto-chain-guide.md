# Auto-Chain 信心评估指南

## 触发条件

仅在以下条件全部满足时评估：
- `brief_file` 非空（当前任务来自项目 DAG）
- merge 阶段的 commit 和 handoff 均已完成

## 信心评估标准

逐项检查，**全部满足**才设置 `next_task`：

| # | 检查项 | 判断方式 |
|---|--------|----------|
| 1 | QA 全部通过 | QA 报告中无 ❌ 标记（⚠️ 可接受） |
| 2 | 无设计偏差 | handoff 文件的"偏差说明"为空或为"无" |

> 走过 auto-fix 但最终收敛全绿不扣信心——拦截基于证据不基于计数：「没修好」已由上游两点拦截（auto-fix 用尽 `max_retries` → `gate: "review-accept"` 停等发生在 merge 前；带遗留合入会被条件 1 的 ❌ 拦住）。

## 查找下一个就绪任务

1. 读取 `.autopilot/project/dag.yaml`
2. 遍历所有 `status: pending` 的任务
3. 检查每个任务的 `depends_on` 是否全部 `status: done`
4. 返回第一个满足条件的任务 ID

## 设置 next_task

```
高信心 + 有就绪任务:
  Edit frontmatter: next_task: "<first-ready-task-id>"

低信心:
  保持 next_task: ""

无就绪任务（但有 pending 任务被阻塞）:
  保持 next_task: ""

所有任务已完成:
  保持 next_task: ""
  (stop-hook 会自动检测 ALL_DONE 并触发全项目 QA)
```

## Auto-Approve 传递

当 stop-hook 基于 `next_task` 创建新状态文件时，会设置 `auto_approve: true`，使下一个任务也可以在高信心时跳过人工审批门。注：standard 单任务 design 步骤 4 AI 自治默认（例外征询时不设）也可设 `auto_approve: true`（详见 autopilot SKILL.md 步骤 4），同样跳过 design 审批 + QA gate。

## 降级

- DAG 文件不存在 → 跳过评估
- DAG 解析失败 → 跳过评估，在对话中说明原因
