# 状态文件格式指南

## 状态文件字段说明

状态文件（`.autopilot/active` 指针指向的 `.autopilot/requirements/<slug>/state.md`，worktree 中位于 `.autopilot/sessions/<name>/requirements/<slug>/state.md`）的 frontmatter 包含以下字段：

**AI 可写字段**：
- `phase`: 当前阶段（design → implement → qa → auto-fix → merge → done），AI 更新
- `gate`: 审批门标记，AI 更新
- `retry_count`: auto-fix 重试计数，AI 在 auto-fix 阶段递增
- `mode`: 任务模式（""/"single"/"project"），AI 在 design 阶段 1.5 步骤检测后写入
- `qa_scope`: 选择性重跑标记，AI 更新；可选值：`"smoke"`（diff 小或 fast_mode 触发，跳过 Wave 2 qa-reviewer）/ `"selective"`（auto-fix 后只重跑失败 Tier）/ `""`（默认全量 QA）
- `next_task`: 下一个就绪任务 ID（项目模式 merge 阶段写入，触发 auto-chain）
- `knowledge_extracted`: 知识提取完成标记，AI 在 merge 阶段设为 `"true"`（有新增）或 `"skipped"`（无新增）。stop-hook 的 phase=done 守卫检查此字段，缺失或空值会回滚到 merge

**stop-hook 管理（AI 只读）**：
- `iteration`: 当前迭代次数，stop-hook 自动递增
- `auto_approve`: auto-chain 时为 true，失败回退为 false
- `fast_mode`: 默认 false；`/autopilot --fast` 时 setup.sh 设 true；stop-hook `detect_smoke_eligible` 在 diff 超阈值时降级为 false。AI 只读，不应直接修改

**setup.sh 创建（AI 不修改）**：
- `max_iterations`: 最大迭代次数（默认 30）
- `max_retries`: auto-fix 最大重试次数（默认 3）
- `plan_mode`: 设计模式（""/"deep"），由 `--deep` flag 设置
- `brief_file`: 项目子任务简报文件路径（项目模式自动设置）
- `task_dir`: 需求管理文件夹路径
- `session_id`: 会话 ID
- `started_at`: 启动时间戳（ISO 8601）

## 项目模式 Plan 模板

项目模式（`--project` flag 或 step 1.5 检测）时，Plan Mode 中将以下内容写入计划文件，替代标准单任务 plan 模板：

```markdown
## Context
(为什么需要这个项目，解决什么问题)

## 整体架构设计
- 系统概览（组件、数据流、集成点）
- 关键技术决策和权衡

## 任务 DAG 概览
| ID | 任务 | 依赖 | 复杂度 |
|----|------|------|--------|
| 001-xxx | ... | - | S/M/L |
| 002-xxx | ... | 001-xxx | S/M/L |

## 跨任务设计约束
(命名规范、共享接口、错误处理模式等)

## Handoff 策略
(任务间信息传递的关键内容)
```

## 更新原则

使用 Edit 工具精确修改字段值，不要用 Write 重写整个文件。

## 红队验收测试区域格式

```markdown
## 红队验收测试

### 测试文件
- `src/__tests__/user-avatar.acceptance.test.ts` — 头像上传完整流程

### 验收标准
1. 用户可以上传 JPG/PNG 格式的头像图片
2. 上传后自动裁剪为 200x200 尺寸
```

## 变更日志写入

在 `## 变更日志` 标题下方追加新记录行。格式：
```
- [2026-03-16T10:05:00Z] design 阶段完成，等待用户审批
```
