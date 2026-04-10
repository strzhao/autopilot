# 状态文件格式指南

## 状态文件字段说明

状态文件 `.autopilot/autopilot.local.md` 的 frontmatter 包含以下字段：
- `phase`: 当前阶段（design → implement → qa → auto-fix → merge → done），AI 更新
- `gate`: 审批门标记，AI 更新
- `iteration`: 当前迭代次数，stop-hook 自动递增，AI 不修改
- `max_iterations`: 最大迭代次数，AI 不修改
- `retry_count`: auto-fix 重试计数，AI 更新
- `qa_scope`: 选择性重跑标记，AI 更新
- `session_id`: 会话 ID，AI 不修改

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
