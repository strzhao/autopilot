# Phase: design — 使用 Plan Mode

> 📋 读取状态文件后，本阶段只需关注 frontmatter + `## 目标` 区域。

## 目标
通过 Claude Code 原生 Plan Mode 完成设计和方案审批。

## 关键规则
**进入 design 阶段后，先执行知识上下文加载（如 `.claude/knowledge/` 存在），然后立即调用 `EnterPlanMode` 工具。** 知识加载不超过 15 秒。不存在则直接调用 EnterPlanMode。所有代码探索在 Plan Mode 内完成。

## 工作流程

### 步骤 0. 知识上下文加载（两阶段检索）

1. 检查 `.claude/knowledge/` 目录是否存在，不存在则跳过
2. **Phase 1 — 索引扫描（<=5s）**：
   - `index.md` 存在：读取索引，用当前目标关键词匹配 tags，确定需加载文件（最多 3 个）
   - `index.md` 不存在：直接读取 `decisions.md` 和 `patterns.md` 全量加载
3. **Phase 2 — 按需加载（<=10s）**：读取匹配文件，判断相关条目
4. 将相关条目作为内部上下文带入 Plan Mode

详细消费规则参见 `references/knowledge-engineering.md` 的 `## Consumption Rules` 节。

### 步骤 1. 立即进入 Plan Mode
- 从状态文件读取目标描述
- **立即调用 `EnterPlanMode` 工具** —— 除知识加载外，这是 design 阶段的第一个工具调用
- 不要在调用前执行 Glob、Grep 等探索工具
- 必须在同一轮响应中调用，不要只描述意图

### 步骤 2. 在 Plan Mode 中执行
- 使用 Explore agent 深度分析代码库
- 查找可复用的代码和工具函数
- **范围控制**：子任务超过 8 个或涉及 3+ 独立模块，建议拆分
- **Skill 识别**：检查可用 skill，匹配时在设计文档中声明委托
- 将设计文档写入 Plan Mode 计划文件，包含：

```markdown
## Context
(为什么要做这个改动，解决什么问题)

## 相关历史知识（如有）
(从 .claude/knowledge/ 中提取的相关决策和模式。无则删除此节。)

## 设计文档
- **目标**：一句话描述
- **技术方案**：关键技术决策、数据流、接口设计
- **文件影响范围**（表格：文件 | 操作 | 说明）
- **风险评估**：风险 → 缓解策略

## 领域 Skill 委托（可选）
- **委托 Skill**: {skill-name}
- **委托范围**: {Skill 负责什么，编排器负责什么}
- **委托输入**: {传递给 Skill 的关键信息}

## 实现计划
- 测试策略
- 任务列表（checkbox，按执行顺序）

## 验证方案
### 真实测试场景（必填）
> 场景必须是可执行的命令或操作序列。**层级匹配原则**：UI → 渲染验证；API → 端点验证；CLI → 命令验证。

1. **[独立] 场景名称**：简述
   - 前置条件：（如需）
   - 执行步骤：具体命令
   - 预期结果：可观察的成功标志

### 静态验证（可选）
```

### 步骤 3. Plan 审查（Plan Mode 内）

设计文档写入 plan file 后，在 ExitPlanMode 之前启动审查 sub-agent。

**触发条件**：plan file 包含完整设计文档（Context、设计文档、实现计划、验证方案四节非空）。

**执行流程**：
1. **启动审查 Agent**：prompt 参考 `references/plan-reviewer-prompt.md`，填入目标描述 + 设计文档 + 项目根目录路径
2. **PASS** → 记录通过，继续 ExitPlanMode；**FAIL** → 修改后重新审查
3. **重审控制**：最多 2 轮。第 2 轮仍 FAIL → 附上未解决 BLOCKER，标注 `[审查未通过，交由用户判断]`

**降级**：Agent 不可用时编排器自行简化审查（需求完整性 + 技术可行性 + 验证覆盖）。

**审查报告处理**：PASS → `> ✅ Plan 审查通过`；FAIL 修复后 PASS → `> ✅ 第 N 轮通过`；最终 FAIL → 附全文。

### 步骤 5. 请求审批
- 调用 `ExitPlanMode`，用户审阅计划
- 拒绝/修改时 Plan Mode 支持迭代

### 步骤 6. 审批通过后
- 将设计文档和实现计划**复制**到状态文件 `## 设计文档` 和 `## 实现计划`
- 追加变更日志
- 更新 frontmatter：`phase: "implement"`
