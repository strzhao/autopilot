# Phase 检查清单

每个阶段开始时立即使用 `todo-write` 工具创建任务列表，按以下清单复制条目。

## Phase: design
- [ ] 步骤 0: 知识上下文加载（.autopilot/ 存在时）
- [ ] 步骤 1: 调用 EnterPlanMode 进入 Plan Mode
- [ ] 步骤 1.5: 模式检测与分流（单任务/项目模式）
- [ ] 步骤 2: 代码探索 + 写设计文档（并行：Explore agent + 验收场景生成器 agent）
- [ ] 步骤 3: Plan 审查（启动 plan-reviewer agent）
- [ ] 步骤 5: ExitPlanMode 请求用户审批
- [ ] 步骤 6: 审批通过后写入状态文件，设 phase: implement，结束响应

## Phase: implement
- [ ] 读取设计文档，检查是否有领域 Skill 委托
- [ ] 并行启动蓝队 agent + 红队 agent（同一轮响应发出两个 Agent 调用）
- [ ] 合流：收集蓝队产出 + 红队测试文件
- [ ] 更新状态文件（实现计划标 [x]、写入红队验收测试、变更日志）
- [ ] 设 phase: qa，结束响应

## Phase: qa
- [ ] 前置：变更分析（git diff 分类 + 影响半径判断）
- [ ] Wave 1: 并行执行 Tier 0/1/3/3.5/4（多个 Bash 调用）
- [ ] Wave 1.5: 逐个执行真实测试场景（每个记录 执行: + 输出:）
- [ ] Wave 2: 并行启动 design-reviewer agent + code-quality-reviewer agent
- [ ] 结果判定（场景计数匹配 + 格式检查）→ 设 gate 或 phase

## Phase: auto-fix
- [ ] 读取 QA 报告中所有 ❌ 项
- [ ] 按优先级逐项修复（Tier 0 > Tier 1.5 > Tier 1 > Tier 2-4）
- [ ] retry_count++ → 设 phase: qa（selective）或 gate: review-accept

## Phase: merge
- [ ] 启动 commit-agent（预收集 git diff + 设计目标）
- [ ] Handoff（brief 模式时写 .handoff.md + 更新 dag.yaml）
- [ ] 知识提取与沉淀
- [ ] 设 phase: done，结束响应
