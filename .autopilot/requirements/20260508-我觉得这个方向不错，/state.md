---
active: true
phase: "done"
gate: ""
iteration: 2
max_iterations: 30
max_retries: 3
retry_count: 0
mode: ""
plan_mode: ""
fast_mode: false
brief_file: ""
next_task: ""
auto_approve: false
knowledge_extracted: "true"
task_dir: "/Users/stringzhao/workspace/agi/live/string-claude-code-plugin/.autopilot/requirements/20260508-我觉得这个方向不错，"
session_id: aa080700-a311-4897-b18e-f378a0f462ab
started_at: "2026-05-08T12:16:14Z"
---

## 目标
我觉得这个方向不错，按照这个思路优化，这样做完似乎 skill 大小还能少一点？ 当前 skill 刚好也太大了

> 📚 项目知识库已存在: .autopilot/。design 阶段请先加载相关知识上下文。

## 设计文档

### Context
autopilot design 阶段依赖 Claude Code Plan Mode（EnterPlanMode/ExitPlanMode），存在 deep 模式两步走（brainstorm + plan）和 SKILL.md 过大的问题。用户判断 AI 指令遵循已足够好，Plan Mode 的写入禁止不再必要，可用 AskUserQuestion 作为审批门替代。

### 设计方案
移除 Plan Mode，所有设计模式统一为：知识加载 → 模式分流 → 代码探索 → [deep: Q&A] → 写设计文档到状态文件 → 审查 → AskUserQuestion 审批。

### 改动文件
1. SKILL.md — 重写 Phase: design（删除 EnterPlanMode/ExitPlanMode/plan file copy 步骤）
2. deep-design-guide.md — 删除 Phase A/B 双阶段，改为单流程
3. stop-hook.sh — 更新 design 阶段 4 个分支的 prompt 注入
4. phase-checklists.md — 更新步骤编号和内容
5. skill-fast-mode-doc.acceptance.test.sh — 断言 6/7 改为 AskUserQuestion
6. state-file-guide.md — plan_mode 字段描述更新
7. MEMORY.md — 删除 Plan Mode Gate 规则

## 实现计划
- [x] 步骤 1: SKILL.md 重写 design 阶段（594→582 行）
- [x] 步骤 2: deep-design-guide.md 精简（112→89 行）
- [x] 步骤 3: stop-hook.sh 更新 prompt 注入
- [x] 步骤 4: phase-checklists.md 更新
- [x] 步骤 5: 验收测试更新
- [x] 步骤 6: state-file-guide.md 更新
- [x] 步骤 7: MEMORY.md 清理

## 红队验收测试
(待 implement 阶段填充)

## QA 报告
(待 qa 阶段填充)

## 变更日志
- [2026-05-08T12:16:14Z] autopilot 初始化，目标: 我觉得这个方向不错，按照这个思路优化，这样做完似乎 skill 大小还能少一点？ 当前 skill 刚好也太大了
- [2026-05-08T12:20:00Z] 设计方案已通过审批
- [2026-05-08T12:25:00Z] 实现完成：移除 Plan Mode，7 个文件已更新，验收测试 7/8 通过（1 个是已有版本号问题）
