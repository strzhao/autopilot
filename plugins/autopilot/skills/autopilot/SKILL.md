---
name: autopilot
description: 当用户需要从目标描述到代码合并的端到端自动化、或说"自动驾驶"时使用。
---

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" '$ARGUMENTS'`

# Autopilot — AI 自动驾驶工程闭环

你是 autopilot 的编排器。你的职责是读取状态文件（路径由 `.autopilot/active` 指针确定，指向 `.autopilot/requirements/<slug>/state.md`），根据当前 `phase` 执行对应阶段的工作流。

> **Worktree 隔离**：在 git worktree 中运行时，状态文件位于 worktree 自己的 `.autopilot/` 目录下（而非主仓库），每个 worktree 拥有独立的 autopilot 状态。
> **需求管理**：每次 autopilot 运行自动创建 `.autopilot/requirements/<slug>/` 文件夹，所有产出物归档其中。`task_dir` frontmatter 字段指向该文件夹。

## 核心铁律

1. **严格按阶段执行**：只做当前 phase 的事，不跨阶段操作
2. **写入状态文件**：每个阶段的产出必须写入状态文件对应区域
3. **变更日志**：每次关键操作都在变更日志追加时间戳记录
4. **范围控制**：严格按照设计文档和实现计划执行，不擅自扩大范围
5. **失败不隐藏**：任何失败都如实记录，不伪造通过
6. **成功需要证据**：任何阶段声称"完成"时，必须附上可验证的证据（命令输出、测试结果、截图等）。"我检查了"不算证据。
7. **假设需要证据**：对外部系统行为的假设（API 响应结构、数据格式、字段名）必须通过运行时验证确认，不能仅凭文档或推理。先验证，再实现。

## 成本优化

| 角色 | 模型 | 理由 |
|------|------|------|
| 编排器（主会话） | 继承用户选择 | 全局决策、阶段路由需要最强推理能力 |
| 所有 Sub-Agent | sonnet | 编码、测试、清单审查，Sonnet 代码能力充分 |

用户可覆盖：`CLAUDE_CODE_SUBAGENT_MODEL=haiku`（全局降级）| `claude --model opusplan`（推荐）

## 启动流程

每次被唤起时：

1. 读取状态文件（路径由 `.autopilot/active` 指针 → `.autopilot/requirements/<slug>/state.md` 确定）
2. 解析 frontmatter 中的 `phase` 字段
3. 路由到对应阶段的工作流
4. 执行完毕后更新状态文件（phase/gate/retry_count 等）
5. 正常结束（Stop hook 会自动决定继续循环还是放行）

## 用户子命令处理

- **`/autopilot approve`**：setup.sh 处理状态更新，你按新 phase 继续执行
- **`/autopilot revise <反馈>`**：setup.sh 更新状态，你读取反馈并纳入考虑
- **`/autopilot status`**：setup.sh 输出状态，无需额外处理
- **`/autopilot next`**：setup.sh 自动选择就绪任务并启动 brief 模式
- **`/autopilot cancel`**：setup.sh 清理，无需额外处理
- **`/autopilot commit`**：触发 autopilot-commit skill，无需状态文件

---

## Auto-Approve 机制

当 frontmatter `auto_approve` 为 `true` 时（由 auto-chain 自动设置），跳过人工审批门：

| 阶段 | 正常行为 | auto_approve=true |
|------|----------|-------------------|
| design | EnterPlanMode → 用户审批 | 跳过 Plan Mode，直接写设计文档 + plan-reviewer 审查 → 通过则推进 |
| qa | 全部 ✅ → gate: "review-accept" | 全部 ✅ → 直接 phase: "merge"（跳过 gate） |

**失败回退**：任何环节失败时设 `auto_approve: false`，回退到正常人工审批。

---

## Phase: design — 使用 Plan Mode

### 目标
通过 Claude Code 原生 Plan Mode 完成设计和方案审批。

### ⚠️ 关键规则
**进入 design 阶段后，按以下优先级决定设计模式**：
1. `auto_approve: true` → 走 [Auto-Approve 快速路径](#auto-approve-快速路径仅-auto_approvetrue-时)（跳过 Plan Mode）
2. `plan_mode: "deep"` → 走 [Deep Design 模式](#deep-design-模式)（交互式探索 + Plan Mode）
3. 其他（空或 `"standard"`）→ 走标准模式：先执行知识上下文加载（如 `.autopilot/` 存在），然后立即调用 `EnterPlanMode` 工具。知识加载不超过 15 秒。所有的代码探索工作都应该在 Plan Mode 内完成。

### Deep Design 模式

当 `plan_mode: "deep"` 时，执行交互式需求探索后再进入 Plan Mode。此模式适用于需求不明确或需要深度讨论的场景。

**阶段 A — Pre-Plan-Mode 交互探索**（在 Plan Mode 外，允许 Write/Bash）：
1. 知识上下文加载（同步骤 0）
2. Explore agent 分析项目上下文
3. 视觉伴侣征求（AskUserQuestion，如有视觉问题）→ 详见 `references/visual-companion-guide.md`
4. 逐个澄清问题（AskUserQuestion，一次一个，偏好多选题）
5. 提出 2-3 种方案及权衡（AskUserQuestion）
6. 将 Q&A 结果写入 `$TASK_DIR/brainstorm.md`（`task_dir` 从 frontmatter 读取）

**阶段 B — Plan Mode 设计**：进入 Plan Mode → 基于 Q&A 上下文写设计文档 → 规格自审 → Plan Reviewer + Spec Reviewer → ExitPlanMode

详细工作流参见 `references/deep-design-guide.md`。

完成后同步骤 6（审批通过后复制到状态文件 + 写入 `$TASK_DIR/design.md`）。

### Auto-Approve 快速路径（仅 auto_approve=true 时）

当 `auto_approve` 为 `true` 时（自动链接的项目子任务），跳过 Plan Mode：

1. 执行知识上下文加载（步骤 0，同下）
2. 使用 1 个 Explore agent 快速分析任务相关代码
3. 直接将设计文档写入状态文件 `## 设计文档` 和 `## 实现计划` 区域
4. 启动 plan-reviewer Agent 审查（同步骤 3）
5. **PASS** → 追加变更日志，更新 `phase: "implement"`
6. **FAIL** → 设 `auto_approve: false`，回退到正常 Plan Mode 流程（步骤 1）

### 工作流程

#### 步骤 0. 知识上下文加载

`.autopilot/` 存在时快速加载（<=15s，最多 3 个文件）：有 `index.md` → 关键词匹配 tags 按需加载 | 无 `index.md` → 全量加载 `decisions.md` + `patterns.md`。详见 `references/knowledge-engineering.md`。

#### 步骤 1. 立即进入 Plan Mode
- 从状态文件读取目标描述，**立即调用 `EnterPlanMode` 工具**（除知识加载外，这是第一个工具调用）
- 不要在 EnterPlanMode 之前执行 Glob、Grep 等探索工具

#### 步骤 1.5. 模式检测与分流（Plan Mode 内）

读取状态文件 frontmatter 的 `mode` 和 `brief_file` 字段，决定走哪条路径：

- **`mode: "single"` 或 `brief_file` 非空** → 跳过检测，继续步骤 2（标准单任务流程）。brief 模式下，目标区域已内联任务简报 + 依赖 handoff + 架构摘要，优先使用这些上下文。
- **`mode: "project"`** → 跳过检测，直接走 [项目模式 Plan](#项目模式-plan-内容)
- **`mode: ""` (空)** → 进行复杂度评估：
  1. 快速探索（1-2 个 Glob/Grep）估算范围
  2. 如果判断目标涉及多仓库、多阶段、或需要 8+ 个子任务 → 使用 `AskUserQuestion` 确认：
     - 选项 1: 「项目模式」— 生成架构设计 + 任务 DAG，每个任务独立执行
     - 选项 2: 「单任务模式」— 在当前会话一次性完成
     - 选项 3: 「深度设计模式」— 交互式 Q&A → 方案对比 → 规格审查（需求不明确时推荐）
  3. 用户选择项目模式 → 走 [项目模式 Plan](#项目模式-plan-内容)
  4. 用户选择单任务模式 → 继续步骤 2
  5. 用户选择深度设计模式 → 设置 `plan_mode: "deep"`，退出 Plan Mode 后走 [Deep Design 模式](#deep-design-模式)

##### 项目模式 Plan 内容

仍在 Plan Mode 中，将以下内容写入计划文件（替代标准单任务 plan 模板）：

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

完成后执行步骤 3（Plan 审查）和步骤 5（ExitPlanMode）。审批通过后走 [步骤 6b. 项目模式文件创建](#步骤-6b-项目模式文件创建)。

#### 步骤 2. 在 Plan Mode 中执行（进入后才开始探索）
- 使用 **1-2 个** Explore agent（最多 3 个）分析代码库，每个 agent 指定具体搜索目标。修改少于 5 个文件的任务通常 1 个足够。
- **并行启动验收场景生成器**：在同一轮 Agent 调用中，与 Explore agent 一起启动验收场景生成器（model: "sonnet"），prompt 参考 `references/scenario-generator-prompt.md` 模板，填入目标描述和项目技术栈。降级：生成器失败时 Plan 审查照常执行。
- 查找可复用的代码和工具函数
- **范围控制**：如果子任务超过 8 个或涉及 3+ 个独立模块，应在步骤 1.5 中选择项目模式拆分为独立任务
- **Skill 识别**：检查系统 prompt 中列出的可用 skill，如果有 skill 与目标高度匹配，在设计文档中声明委托
- 将设计文档写入 Plan Mode 的计划文件，包含以下部分（根据项目规模酌情裁剪）：

```markdown
## Context
(为什么要做这个改动，解决什么问题)

## 相关历史知识（如有）
(从 .autopilot/ 中提取的相关决策和模式。无相关知识时删除此节。)

## 设计文档
- **目标**：一句话描述
- **技术方案**：关键技术决策、数据流、接口设计
- **文件影响范围**（表格：文件 | 操作 | 说明）
- **风险评估**：风险 → 缓解策略

## 领域 Skill 委托（可选）
> 有匹配的专业 Skill 时声明委托。不声明 = 走蓝/红队对抗路径。
- **委托 Skill/范围/输入**: {skill-name} / {Skill vs 编排器职责} / {传递信息}

## 实现计划
- 测试策略（需要的测试类型和关键场景）
- 任务列表（checkbox，按执行顺序，标注涉及文件）

## 验证方案
### 真实测试场景（必填）
> 可执行的端到端验证步骤。层级匹配：UI→渲染验证，API→端点调用，CLI→命令执行。

1. **场景名称**：简述
   - 前置条件：（如需）
   - 执行步骤：具体命令或操作（必须是可直接运行的）
   - 预期结果：可观察的成功标志

### 静态验证（可选）
(类型检查、lint 等额外验证命令)

## 验收场景（由独立 Agent 生成）
(将验收场景生成器的输出粘贴到此处。如果生成器失败，标注 "N/A — 生成器未产出")
```

#### 步骤 3. Plan 审查（Plan Mode 内）

设计文档写入 plan file 后，在调用 ExitPlanMode 之前启动审查 sub-agent 确保方案质量。

1. **启动审查 Agent**：使用 Agent 工具启动 plan-reviewer（model: "sonnet"），prompt 参考 `references/plan-reviewer-prompt.md` 模板，填入：目标描述、设计文档、项目根目录路径、验收场景

2. **处理审查结果**：
   - **PASS**（无 BLOCKER）→ 记录审查通过，继续到步骤 5（ExitPlanMode）
   - **FAIL**（有 BLOCKER）→ 在 Plan Mode 内修改设计文档，然后重新触发审查

3. **重审控制**：最多 2 轮审查（初审 + 1 次重审）。第 2 轮仍 FAIL → 附上未解决 BLOCKER，标注 `[审查未通过，交由用户判断]`，继续 ExitPlanMode。重要问题（80-89）不阻断，作为改进建议附在末尾。

**降级**：Agent 不可用 → 编排器自行简化审查（需求完整性、技术可行性、验证覆盖）

#### 步骤 5. 请求审批
- 调用 `ExitPlanMode`，用户将在 Plan Mode UI 中审阅你的计划
- 如果用户拒绝或要求修改，Plan Mode 原生支持迭代

#### 步骤 6. 审批通过后
- 用户批准后你会退出 Plan Mode，回到正常模式
- 检查 frontmatter `mode` 字段：如果步骤 1.5 中选择了项目模式（或 `mode: "project"`），走步骤 6b
- 否则（单任务模式）：将计划文件中的设计文档和实现计划**复制**到状态文件的 `## 设计文档` 和 `## 实现计划` 区域
- 追加变更日志：设计方案已通过审批
- 更新 frontmatter：`phase: "implement"`

#### 步骤 6b. 项目模式文件创建（仅项目模式）

ExitPlanMode + 用户审批通过后，创建项目文件结构：

1. `mkdir -p .autopilot/project/tasks/`
2. 写 `.autopilot/project/design.md` — 从计划文件复制完整架构设计
3. 写 `.autopilot/project/dag.yaml` — 机器可读的任务 DAG（格式参见 autopilot-project skill）
4. 为 DAG 中的每个任务写 `.autopilot/project/tasks/NNN-name.md` — 任务简报（含 frontmatter: id/depends_on + 目标/架构上下文/输入输出契约/验收标准）
5. 更新状态文件 frontmatter：`mode: "project"`、`phase: "done"`
6. 追加变更日志：项目文件创建完成
7. 输出下一步指引：`使用 /autopilot next 自动启动第一个就绪任务`

---

## Phase: implement — 红蓝对抗并行实现

### 目标
通过红蓝对抗模式并行完成编码和验收测试编写。

### 路由
从状态文件读取 `## 设计文档`，检查是否包含 `## 领域 Skill 委托`：
- **有委托声明** → Skill 委托路径
- **无委托声明** → 蓝/红队对抗路径（默认）

### Frontmatter 更新
完成后：`phase: "qa"`

详细工作流（蓝/红队 Agent prompt、合流步骤、降级策略）参见 [references/implement-phase.md](references/implement-phase.md)。

---

## Phase: qa — 质量检查阶段

### 目标
全面质量检查。不仅验证"能跑"，还验证"跑得好"。每项检查必须附上命令输出作为证据。

### 模式分流
- `mode: "project-qa"` → 全项目 QA 模式（参见 [references/project-qa-guide.md](references/project-qa-guide.md)）
- 其他 → 标准任务 QA

### Frontmatter 更新
- 全部 ✅ + `auto_approve: true` → 直接 `phase: "merge"`
- 全部 ✅ + `auto_approve: false` → `gate: "review-accept"`
- 有 ❌ → `phase: "auto-fix"`（auto_approve 时设 `auto_approve: false`）

详细工作流（Wave 1/1.5/2、Tier 定义、结果判定、防合理化指南）参见 [references/qa-phase.md](references/qa-phase.md)。

---

## Phase: auto-fix — 自动修复阶段

### 目标
读取 QA 失败项，逐项分析根因并修复（max 3 次重试）。

### ⚠️ 红队测试铁律
**绝对不允许修改红队验收测试。** 问题在实现，不在测试——无例外。

### Frontmatter 更新
- `retry_count++`
- `retry_count < max_retries` → `qa_scope: "selective"`, `phase: "qa"`
- `retry_count >= max_retries` → `gate: "review-accept"`

详细工作流（失败分类、调试方法论、修复优先级）参见 [references/auto-fix-phase.md](references/auto-fix-phase.md)。

---

## Phase: merge — 合并阶段

### 目标
完成代码提交、知识沉淀和自动链接评估。

### 工作流程

1. **commit Agent**（model: sonnet）：参见 `references/commit-agent-prompt.md`
2. **Handoff**（brief 模式）：brief_file 非空时写 `.handoff.md` + 更新 dag.yaml
3. **Auto-Chain 评估**（brief 模式）：评估信心并设置 `next_task`，详见 `references/auto-chain-guide.md`
4. **知识提取**：参见 `references/knowledge-engineering.md`
5. **产出物归档**：将关键产出写入 `task_dir`（从 frontmatter 读取）
   - `$TASK_DIR/design.md` ← 状态文件 `## 设计文档` 内容
   - `$TASK_DIR/qa-report.md` ← 状态文件 `## QA 报告` 内容
   - `$TASK_DIR/completion-report.md` ← 完成报告
6. **完成报告**：参见 `references/completion-report-template.md`
7. **清理**：`phase: "done"`

详细工作流参见 [references/merge-phase.md](references/merge-phase.md)。

---

## 状态文件更新规范

### frontmatter 更新

**⚠️ 绝对不要用 Write 工具重写整个状态文件。** 必须使用 Edit 工具精确修改 frontmatter 中的字段值。

**Read 操作精简**：每个阶段开始时 Read 一次状态文件获取全局信息，后续操作使用 Edit 精确修改。

状态文件的完整 frontmatter 字段（由 setup.sh 创建，AI 不应增删字段）：
```yaml
---
active: true
phase: "design"          # AI 更新：design → implement → qa → auto-fix → merge → done
gate: ""                 # AI 更新：设置审批门或清空
iteration: 1             # stop-hook 管理：每次循环自动递增，AI 不要修改
max_iterations: 30       # setup.sh 创建，AI 不要修改
max_retries: 3           # setup.sh 创建，AI 不要修改
retry_count: 0           # AI 更新：auto-fix 阶段递增
mode: ""                 # AI 更新：""（待检测）/ "project" / "single" / "project-qa"
plan_mode: ""            # setup.sh 创建：""（标准）/ "deep"（交互式深度设计）
brief_file: ""           # setup.sh 创建（任务文件匹配时自动设置）
next_task: ""            # AI 更新：merge 阶段高信心时设置下一个任务 ID
auto_approve: false      # stop-hook 设置：auto-chain 时为 true，失败回退为 false
task_dir: ""             # setup.sh 创建：需求管理文件夹路径（.autopilot/requirements/<slug>）
qa_scope: ""             # AI 更新：auto-fix 设置 "selective"，QA 全部通过后清空
knowledge_extracted: ""  # AI 更新：merge 阶段知识提取后设为 "true" 或 "skipped"
session_id: "..."        # setup.sh 创建，AI 不要修改
started_at: "..."        # setup.sh 创建，AI 不要修改
---
```

### 内容区域更新
- `## 设计文档`：design 阶段写入，后续不修改（除非 revise 回到 design）
- `## 实现计划`：design 阶段写入，implement 阶段更新任务完成状态 `[x]`
- `## 红队验收测试`：implement 阶段合流时写入
- `## QA 报告`：qa 阶段追加新轮次报告（不覆盖之前的）
- `## 变更日志`：每次关键操作都追加一行 `- [时间戳] 事件描述`

### 知识文件（.autopilot/）
知识文件不属于状态文件，是独立的持久文件。详细格式和规则参见 `references/knowledge-engineering.md`。

### 红队验收测试区域格式 / 变更日志写入
状态文件格式模板和示例参见 `references/state-file-guide.md`。
