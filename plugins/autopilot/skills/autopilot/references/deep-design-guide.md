# Deep Design 工作流指南

Deep Design 模式通过交互式需求探索（改编自 brainstorming skill），在进入 Plan Mode 前充分理解用户意图。

**触发条件**：frontmatter `plan_mode: "deep"` 或步骤 1.5 用户选择深度设计。

---

## 阶段 A — Pre-Plan-Mode 交互探索

在 Plan Mode 外执行，允许使用 Write/Bash 等工具。

### A1. 探索项目上下文

- 使用 1-2 个 Explore agent 分析代码库
- 检查文件、文档、近期 commit
- 如目标涉及多个独立子系统，立即标记（可能需要项目模式拆分）

### A2. 视觉伴侣征求（可选）

评估后续问题是否涉及视觉内容（UI mockup、架构图、布局对比），如果是：

使用 AskUserQuestion 征求同意：
> "后续讨论可能涉及视觉内容（mockup、布局对比等），可以在浏览器中展示。需要启用视觉伴侣吗？"

同意后：
1. 从 frontmatter 读取 `task_dir`
2. 启动服务器：`bash ${CLAUDE_PLUGIN_ROOT}/scripts/visual-companion/start-server.sh --project-dir $TASK_DIR`
3. 保存 `screen_dir` 和 `state_dir`

详细使用说明参见 `references/visual-companion-guide.md`。

**判断标准**：
- **用浏览器**：UI mockup、架构图、布局对比、设计风格对比
- **用终端**：需求问题、概念选择、权衡列表、技术决策

### A3. 逐个澄清问题

核心原则：
- **一次一个问题**，不要一次问多个
- **偏好多选题**（AskUserQuestion 的 options），开放式也可以
- **聚焦**：目的、约束、成功标准
- 如有视觉伴侣，视觉问题用浏览器展示

问题策略：
1. 先问目的和范围（"这个功能要解决什么问题？"）
2. 再问约束（"有没有性能/兼容性/时间要求？"）
3. 最后问成功标准（"怎样算做好了？"）

每轮 Q&A 结果追加到 `$TASK_DIR/brainstorm.md`。

### A4. 提出 2-3 种方案

- 准备 2-3 种方案，每种包含权衡分析
- **先展示推荐方案**，解释推荐理由
- 使用 AskUserQuestion 让用户选择
- 记录选择和理由到 `$TASK_DIR/brainstorm.md`

### A5. 过渡到 Plan Mode

交互探索完成后：
1. 将收集到的需求、约束、方案选择整理为上下文摘要
2. 调用 `EnterPlanMode` 进入正式设计阶段

---

## 阶段 B — Plan Mode 正式设计

### B1. 写设计文档

基于阶段 A 收集的完整上下文，在 plan file 中写入设计文档。模板同标准模式，但增加：

```markdown
## 需求探索摘要
(从 brainstorm.md 提炼的关键决策和约束)

## 方案选择
- 选定方案：X
- 选择理由：...
- 被排除方案及原因：...
```

### B2. 规格自审

写完设计文档后，用"新鲜眼光"检查：

1. **占位符扫描**：是否有 "TBD"、"TODO"、不完整的部分？修复。
2. **内部一致性**：各节是否相互矛盾？架构是否与功能描述匹配？
3. **范围检查**：是否聚焦到足以支撑单个实现计划？
4. **歧义检查**：是否有需求可被两种方式理解？明确选一种。

发现问题直接内联修复，无需重新审查。

### B3. Plan Reviewer + Spec Reviewer

1. 启动 Plan Reviewer agent（同标准模式，参见 `references/plan-reviewer-prompt.md`）
2. 启动 Spec Reviewer agent（参见 `references/spec-reviewer-prompt.md`），验证规格完整性
3. 两个 reviewer 可并行启动

### B4. ExitPlanMode

调用 ExitPlanMode，用户审阅设计方案。

---

## 关键原则

- **YAGNI**：无情移除不必要的功能
- **递进验证**：展示设计、获得认可后再继续
- **灵活回溯**：发现理解不对时返回澄清
- **设计隔离性**：每个单元有清晰的职责、接口和依赖
- **现有代码优先**：先探索现有结构，遵循已有模式
