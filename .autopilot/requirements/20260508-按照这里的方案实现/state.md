---
active: true
phase: "done"
gate: ""
iteration: 1
max_iterations: 30
max_retries: 3
retry_count: 0
mode: ""
plan_mode: ""
brief_file: ""
next_task: ""
auto_approve: false
knowledge_extracted: "skipped"
task_dir: "/Users/stringzhao/workspace/agi/live/string-claude-code-plugin/.autopilot/requirements/20260508-按照这里的方案实现"
session_id: d73eaf6c-a974-49cd-9c77-5ff07b294bdb
started_at: "2026-05-08T10:49:42Z"
---

## 目标
按照这里的方案实现

> 📚 项目知识库已存在: .autopilot/。design 阶段请先加载相关知识上下文。

## 设计文档

### Context
红队在编写验收测试时容易忽略 e2e 测试，即使 plan review 已明确指出需要。根本原因是 plan review 的发现没有转化为红队的硬约束，QA 也缺乏回溯验证。本次改动建立三层闭环：设计必须声明 → 红队必须兑现 → qa-reviewer 兜底提醒。

### 改动 1：红队 prompt 增加测试层级强制规则
**文件**: `plugins/autopilot/skills/autopilot/references/red-team-prompt.md`
在规则 6 之后追加规则 7 和 8（整数连续编号）。

### 改动 2：Plan Reviewer 维度 4 增加 E2E 强制条件
**文件**: `plugins/autopilot/skills/autopilot/references/plan-reviewer-prompt.md`
维度 4 独立子条目追加 E2E 强制条件。

### 改动 3：QA Reviewer Section A 增加验证层级兑现检查
**文件**: `plugins/autopilot/skills/autopilot/references/qa-reviewer-prompt.md`
Section A 检查清单追加第 5 条。

### 验证方案
#### 真实测试场景
1. [独立] grep 验证 red-team-prompt.md 包含"测试层级强制"和"输入验证边界"
2. [独立] grep 验证 plan-reviewer-prompt.md 包含"E2E 强制条件"
3. [独立] grep 验证 qa-reviewer-prompt.md 包含"验证层级兑现"

## 实现计划
- [x] 1. 修改 `red-team-prompt.md`：在规则 6 之后追加规则 7 + 8
- [x] 2. 修改 `plan-reviewer-prompt.md`：维度 4 独立子条目追加 E2E 强制条件
- [x] 3. 修改 `qa-reviewer-prompt.md`：Section A 追加检查项 5

## 红队验收测试
(待 implement 阶段填充)

## QA 报告

### 轮次 1 (2026-05-08T10:51:30Z)

**变更分析**: 3 个 markdown 文件，+7 行纯文本追加，无代码逻辑

**Tier 0**: N/A — 无可执行测试（prompt 模板文本变更）
**Tier 1**: N/A — 纯 markdown，无 tsc/lint/build 适用
**Tier 1.5**: ✅ grep 验证 4/4 关键内容均存在（red-team:37,41 | plan-reviewer:29 | qa-reviewer:41）
**Tier 2**: ✅ git diff 与设计文档完全一致，编号连续、格式正确
**Tier 3/3.5/4**: N/A — 无前端/API/跨文件变更

**结论**: ✅ 全部通过

## 变更日志
- [2026-05-08T10:49:42Z] autopilot 初始化，目标: 按照这里的方案实现
- [2026-05-08T10:50:30Z] 设计方案通过审批（Plan Reviewer 6/6 ✅），采纳编号连续性和维度 4 格式改进建议
- [2026-05-08T10:51:00Z] 实现完成：3 个 prompt 模板文件已修改，grep 验证全部通过
- [2026-05-08T10:52:00Z] QA 全部通过，提交: 4a77776 feat(autopilot): 建立三层 E2E 测试覆盖强制机制
- [2026-05-08T10:52:10Z] 知识提取：本次无新增（改动模式已被现有 patterns.md "外部审查后的修改必须重新验证" 覆盖）
