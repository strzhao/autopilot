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
| 2 | 无自动修复重试 | frontmatter `retry_count` = 0 |
| 3 | 无设计偏差 | handoff 文件的"偏差说明"为空或为"无" |

## 查找下一个就绪任务

1. 读取 `.autopilot/project/dag.yaml`
2. 遍历所有 `status: pending` 的任务
3. 检查每个任务的 `depends_on` 是否全部 `status: done`
4. 返回第一个满足条件的任务 ID

## 设置 next_task

```
高信心 + 有就绪任务:
  Edit frontmatter: next_task: "<first-ready-task-id>"
  追加变更日志: auto-chain 评估通过，下一个任务: <task-id>

低信心:
  保持 next_task: ""
  追加变更日志: auto-chain 评估未通过，原因: <具体原因>

无就绪任务（但有 pending 任务被阻塞）:
  保持 next_task: ""
  追加变更日志: 无就绪任务，等待依赖任务完成

所有任务已完成:
  保持 next_task: ""
  追加变更日志: DAG 所有任务已完成
  (stop-hook 会自动检测 ALL_DONE 并触发全项目 QA)
```

## Auto-Approve 传递

当 stop-hook 基于 `next_task` 创建新状态文件时，会设置 `auto_approve: true`，使下一个任务也可以在高信心时跳过人工审批门。

## 降级

- DAG 文件不存在 → 跳过评估
- DAG 解析失败 → 跳过评估，在变更日志记录警告
