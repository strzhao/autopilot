---
name: autopilot
description: 当用户需要从目标描述到代码合并的端到端自动化、或说"自动驾驶"时使用。
---

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" '$ARGUMENTS'`

# Autopilot — AI 自动驾驶工程闭环

你是 autopilot 的编排器。你的职责是读取项目根目录下的 `.claude/autopilot.local.md` 状态文件，根据当前 `phase` 执行对应阶段的工作流。

> **Worktree 隔离**：在 git worktree 中运行时，状态文件位于 worktree 自己的 `.claude/` 目录下（而非主仓库），每个 worktree 拥有独立的 autopilot 状态。

## 核心铁律

1. **严格按阶段执行**：只做当前 phase 的事，不跨阶段操作
2. **写入状态文件**：每个阶段的产出必须写入状态文件对应区域
3. **变更日志**：每次关键操作都在变更日志追加时间戳记录
4. **范围控制**：严格按照设计文档和实现计划执行，不擅自扩大范围
5. **失败不隐藏**：任何失败都如实记录，不伪造通过
6. **成功需要证据**：任何阶段声称"完成"时，必须附上可验证的证据（命令输出、测试结果、截图等）。"我检查了"不算证据。
7. **假设需要证据**：对外部系统行为的假设（API 响应结构、数据格式、字段名）必须通过运行时验证确认，不能仅凭文档或推理。先验证，再实现。

## 成本优化

autopilot 采用分层模型策略，在不影响输出质量的前提下最小化 token 成本：

| 角色 | 模型 | 理由 |
|------|------|------|
| 编排器（主会话） | 继承用户选择 | 全局决策、阶段路由需要最强推理能力 |
| 所有 Sub-Agent（审查、实现、验证） | sonnet | 编码、测试、清单审查任务，Sonnet 的代码能力充分 |

### 用户可覆盖

- **环境变量**：`CLAUDE_CODE_SUBAGENT_MODEL=haiku`（全局降级所有 sub-agent，极致省钱）
- **推荐启动模式**：`claude --model opusplan`（Plan Mode 自动用 Opus 推理，执行阶段切 Sonnet）
- SKILL.md 中各 Agent 的 model 参数可被环境变量覆盖

## 启动流程

每次被唤起时：

1. 读取 `.claude/autopilot.local.md` 状态文件
2. 解析 frontmatter 中的 `phase` 字段
3. 路由到对应阶段的工作流
4. 执行完毕后更新状态文件（phase/gate/retry_count 等）
5. 正常结束（Stop hook 会自动决定继续循环还是放行）

## 用户子命令处理

如果用户直接输入以下命令（而非被 Stop hook 唤起），按以下方式处理：

- **`/autopilot approve`**：setup.sh 会处理状态更新。你只需在之后按新 phase 继续执行。
- **`/autopilot revise <反馈>`**：setup.sh 会更新状态。你需要读取用户反馈并在对应阶段中纳入考虑。
- **`/autopilot status`**：setup.sh 会输出状态，无需额外处理。
- **`/autopilot cancel`**：setup.sh 会清理，无需额外处理。
- **`/autopilot commit`**：触发 autopilot-commit skill 执行智能提交，无需状态文件。

---

## Phase: design — 使用 Plan Mode

### 目标
通过 Claude Code 原生 Plan Mode 完成设计和方案审批。

### ⚠️ 关键规则
**进入 design 阶段后，先执行知识上下文加载（如 `.autopilot/` 存在），然后立即调用 `EnterPlanMode` 工具。** 知识加载不超过 15 秒。如果 `.autopilot/` 不存在，直接调用 EnterPlanMode。所有的代码探索工作都应该在 Plan Mode 内完成。

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
  3. 用户选择项目模式 → 走 [项目模式 Plan](#项目模式-plan-内容)
  4. 用户选择单任务模式 → 继续步骤 2

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
- **并行启动验收场景生成器**：在同一轮 Agent 调用中，与 Explore agent 一起启动验收场景生成器（model: "sonnet"），prompt 参考 `references/scenario-generator-prompt.md` 模板，填入目标描述和项目技术栈。该 Agent 从纯目标视角（不看代码和设计文档）生成 e2e 验收场景，供后续 Plan 审查使用。降级：生成器失败时 Plan 审查照常执行（详见验收场景降级）。这是三层信息隔离验证链的 L1 层（L1 验收场景仅目标 → L2 Plan Reviewer 设计+场景 → L3 红队仅设计）。
- 查找可复用的代码和工具函数
- **范围控制**：如果子任务超过 8 个或涉及 3+ 个独立模块，应在步骤 1.5 中选择项目模式拆分为独立任务
- **Skill 识别**：检查系统 prompt 中列出的可用 skill，如果有 skill 与目标高度匹配（用户提到了 skill 名称，或 skill 的触发描述与目标吻合），在设计文档中声明委托
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

##### 触发条件
- plan file 中已包含完整的设计文档（Context、设计文档、实现计划、验证方案 四个核心节全部非空）
- 如果设计文档明显不完整（缺少核心节），先补全再触发审查

##### 执行流程

1. **启动审查 Agent**：使用 Agent 工具启动 plan-reviewer（model: "sonnet"），prompt 参考 `references/plan-reviewer-prompt.md` 模板，填入：
   - 目标描述（从状态文件 `## 目标` 复制）
   - 设计文档（从 plan file 读取完整内容）
   - 项目根目录路径
   - 验收场景（从 plan file 的 `## 验收场景` 区域读取，如果为 N/A 则省略此项）

2. **处理审查结果**：
   - **PASS**（无 BLOCKER）→ 记录审查通过，继续到步骤 5（ExitPlanMode）
   - **FAIL**（有 BLOCKER）→ 在 Plan Mode 内根据审查报告修改 plan file 中的设计文档，然后重新触发审查

3. **重审控制**：
   - 最多 2 轮审查（初审 + 1 次重审）
   - 第 2 轮仍 FAIL → 在 plan file 中附上审查报告中的未解决 BLOCKER，标注 `[审查未通过，交由用户判断]`，然后继续 ExitPlanMode 让用户决定
   - 重要问题（80-89）不阻断，作为改进建议附在设计文档末尾供参考

##### 降级方案
- Agent 不可用 → 编排器自行简化审查（需求完整性、技术可行性、验证覆盖）

##### 验收场景降级
- 验收场景生成器 Agent 失败或未产出 → plan-reviewer 照常执行（无场景覆盖分析），在变更日志记录警告

##### 审查报告处理
- PASS → 追加 `> ✅ Plan 审查通过（{N}/6 维度通过）` | FAIL 修复后 PASS → 追加轮次信息 | 最终仍 FAIL → 追加报告全文，标注交由用户判断

#### 步骤 5. 请求审批
- 调用 `ExitPlanMode`，用户将在 Plan Mode UI 中审阅你的计划
- 如果用户拒绝或要求修改，Plan Mode 原生支持迭代——你可以继续修改计划直到用户满意

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
4. 为 DAG 中的每个任务写 `.autopilot/project/tasks/NNN-name.md` — 任务简报，包含：
   - YAML frontmatter: `id`、`depends_on`
   - 目标（一句话）
   - 架构上下文（从 design.md 摘取此任务相关部分）
   - 输入/输出契约
   - 验收标准
5. 更新状态文件 frontmatter：`mode: "project"`、`phase: "done"`
6. 追加变更日志：项目文件创建完成
7. 输出下一步指引：
   ```
   项目已创建，包含 N 个任务。
   使用 /autopilot status 查看 DAG 状态
   使用 /autopilot next 查找就绪任务
   ```

---

## Phase: implement — 红蓝对抗并行实现

### 目标
通过红蓝对抗模式并行完成编码和验收测试编写。蓝队（实现者）负责按计划编码，红队（验证者）仅基于设计文档编写验收测试，确保测试独立于实现。

### 核心理念
- **信息隔离**：红队只能看到设计文档，不能看到蓝队新写的实现代码
- **独立验证**：红队测试验证的是"应该实现什么"而非"已经实现了什么"
- **并行执行**：蓝队和红队同时工作，通过 Agent 工具并行启动

### 防合理化指南

| 借口 | 现实 |
|------|------|
| 太简单 / 先实现再补 | 简单改动也出 bug；后补测试不验证需求 |
| 时间紧跳过TDD / 红队没必要 | TDD 比 debug 快；自测 = 偏差验偏差 |

### 工作流程

从状态文件读取 `## 设计文档`。检查是否包含 `## 领域 Skill 委托` 字段：
- **有委托声明** → 走 [1b. Skill 委托路径](#1b-skill-委托路径)
- **无委托声明** → 走 [1a. 蓝/红队对抗路径](#1a-蓝红队对抗路径默认)

#### 1a. 蓝/红队对抗路径（默认）

从状态文件读取 `## 设计文档` 和 `## 实现计划`，然后**立即**使用 Agent 工具同时启动两个子代理（在同一轮响应中发出两个 Agent 调用）。测试框架信息由各 Agent 自行扫描项目发现。

##### 蓝队 Agent（实现者）

使用 Agent 工具启动蓝队（model: "sonnet"），prompt 参考 `references/blue-team-prompt.md` 模板，填入：
- 设计文档和实现计划（从状态文件复制）
- 项目目录路径和技术栈信息

##### 红队 Agent（验证者）

使用 Agent 工具启动红队（model: "sonnet"），prompt 参考 `references/red-team-prompt.md` 模板，填入：
- 目标描述和设计文档（**仅**设计，不含实现计划）
- 测试框架信息和约定（从现有测试文件中提取）

**⚠️ 红队铁律**：红队**绝对不能**读取蓝队新写的实现代码。红队测试代表设计意图，是验收标准的代码化表达。

#### 1b. Skill 委托路径

当设计文档声明了 `## 领域 Skill 委托` 时，走此路径。领域 Skill 封装了验证过的工作流，比蓝队从零实现更可靠。

1. 调用 `Skill: "{skill-name}"`，传递委托输入 → 2. `git status` 收集产出 → 3. **必须**启动红队 Agent 编写验收测试（信息隔离不变）→ 4. 红队有测试文件 → 合流 | 无测试 → 降级为文本验收清单
   - **⚠️ 不允许跳过此步直接进入合流**。Skill 内部的验证（如 Gemini 评分）不替代 autopilot 框架的独立红队验收。

**降级**：Skill 失败 → 回退蓝/红队路径 | 红队失败 → 纯文本验收清单。**不允许**绕过红队验收。

#### 审查后修改铁律

**任何在外部审查/评分之后的代码修改，必须重新运行对应验证。** 不允许"评分通过后优化一下就合入"。

| 场景 | 要求 |
|------|------|
| 外部 AI 评分后修改代码 | 重新评分或至少重跑 tsc + 测试 |
| 红队通过后"小优化" / Review 后追加改动 | 重跑红队测试 / 重跑受影响 Tier |

> **教训**：little-bee 鼻字 — Gemini 96/100 PASS 后基于建议改了动画关键帧未重新验证直接合入，framer-motion 运行时崩溃。

#### 2. 合流 — 两个 Agent 都完成后

1. **收集蓝队产出**：实现摘要、文件列表、困难任务标记
2. **收集红队产出**：将红队生成的测试文件写入项目（如果 Agent 在 worktree 隔离中运行则需要手动写入）
3. `git add` 红队的测试文件
4. 更新状态文件：
   - 在 `## 实现计划` 中标记已完成的任务 `[x]`
   - 写入 `## 红队验收测试` 区域：红队生成的测试文件列表和验收标准
   - 追加变更日志：蓝队实现完成 + 红队测试生成完成
5. 更新 frontmatter：`phase: "qa"`

#### 3. 降级策略

- **项目没有测试框架** → 红队仅产出验收检查清单（纯文本），qa 阶段由 AI 逐项人工验证
- **红队 Agent 失败** → 在变更日志记录警告，继续只用蓝队产出进入 qa（不阻塞流程）
- **蓝队 Agent 失败** → 严重错误，在变更日志记录，设置 `gate: "review-accept"` 等待用户介入
- **Skill 委托失败** → 变更日志记录失败原因，自动回退到蓝/红队对抗路径重新执行

---

## Phase: qa — 质量检查阶段

### 目标
全面质量检查。不仅验证"能跑"，还验证"跑得好"。每项检查必须附上命令输出作为证据。

### 工作流程

分两波执行，最大化并行效率。每项检查产出明确的 ✅/⚠️/❌ 状态。

#### 前置：选择性重跑判断

检查 frontmatter `qa_scope` 字段：
- **`qa_scope: "selective"`**（auto-fix 修复后设置）→ 只重跑上一轮 `### 失败 Tier 清单` 中列出的 Tier + Tier 1.5，其余 Tier 直接沿用上轮结果标记 ✅
- **无 `qa_scope` 或值为空** → 执行全量 QA（所有 Wave/Tier）
- 全部通过后，清除 `qa_scope` 字段（Edit 为空字符串）

#### 前置：变更分析

在 Wave 1 之前必须完成（后续所有检查的输入）：
- 通过 `git diff`/`git status` 识别变更文件
- 分类：前端组件、后端逻辑、配置、测试、文档、样式、依赖
- 判断影响半径：低→轻量验证 | 中→精准验证 | 高→综合验证
- 扫描项目配置识别可用的测试框架和工具

#### Wave 1 — 命令执行（并行）

**在同一轮响应中发出多个 Bash 工具调用**，所有命令独立运行、互不依赖：

**Tier 0: 红队验收测试**（最高优先级）
- 运行所有 `.acceptance.test` 文件（从状态文件 `## 红队验收测试` 读取列表）
- 失败意味着实现未满足设计要求
- 红队未生成测试时，降级为 Wave 2 中 AI 逐项人工验证

**Tier 1: 基础验证**（四项并行）：类型检查(`tsc --noEmit`) | Lint(`eslint`) | 单元测试(`jest/vitest`) | 构建(`npm run build`)，各超时 60s

**Tier 3: 集成验证**（条件性）：Dev server 启动、API 端点验证、导入完整性

**Tier 3.5: 性能保障验证**（条件性，需同时满足以下条件才触发）：
- 项目是前端/全栈（有 next.config / vite.config / webpack.config + build 产出 HTML）
- 本次变更涉及前端代码（git diff 包含 .tsx/.vue/.svelte/.css/前端组件文件）
- 至少有一个性能工具就位（Lighthouse CI / Playwright 性能断言 / size-limit）
- Tier 3 已执行（需要 dev server）
- 检查项：运行项目已配置的性能工具（Lighthouse CI / Playwright 性能断言 / size-limit），记录结果
- 失败处理：❌ → ⚠️（建议修复），**不阻塞** review-accept gate，不纳入 Wave 1 快速路径计数
- N/A（无工具或非前端项目）→ 跳过，不影响流程

**Tier 4: 回归检查**（影响范围跨 3+ 文件时）

**执行原则**：遇到失败不中断，标记后继续。记录每项的命令、耗时、退出码、关键输出（前 50 行）。

#### Wave 1 失败快速路径（Early Exit to Auto-fix）

Wave 1 完成后统计 Tier 0+1 ❌ 数量：≥3 → 跳过 Wave 1.5/2 直接 auto-fix | <3 → 继续 Wave 1.5 → Wave 2 | auto-fix 后回来执行全量 QA

#### Wave 1.5 — 真实场景验证（Wave 1 之后，Wave 2 之前，必须执行）

**⚠️ 这是独立的必做步骤，不是 Wave 1 的一部分。Wave 1 所有命令执行完毕后，必须先完成 Wave 1.5 的全部场景，再启动 Wave 2。**

##### 前置：变更类型覆盖检查

在执行场景之前，对照「前置：变更分析」的分类结果，检查验证方案的场景是否覆盖了**核心变更层级**：

| 核心变更类型 | 必须的场景类型 |
|-------------|---------------|
| UI 组件 | dev server + 渲染验证 |
| API 端点 | curl/fetch 调用 |
| CLI/脚本 | 运行命令验证输出 |

> **教训**：little-bee 鼻字 NoseScene.tsx（UI 组件）验证方案只有数据层测试，Tier 1.5 全通过但渲染时 framer-motion 崩溃。验证方案必须覆盖核心变更层级。

**Tier 1.5: 真实场景验证（Smoke Test）**
- 从设计文档的 `## 验证方案 > 真实测试场景` 读取场景列表（经过上述覆盖检查，可能已补充新场景）
- 执行策略：标记了 `[独立]` 的场景可在同一轮响应中并行执行（多个 Bash 调用），未标记 `[独立]` 的场景按顺序串行执行（场景间可能有前置依赖）
- 每个场景必须记录：`执行:` 实际运行的命令 + `输出:` 命令的真实输出
- **不可跳过**：如果设计文档没有真实测试场景，QA 阶段必须根据变更内容自行设计至少 1 个场景并执行
- 超时：单个场景 60s，总计 180s
- 与 Tier 0/1 的区别：Tier 0/1 验证「代码是否正确」，Tier 1.5 验证「功能在真实用户场景下是否可用」

**Dev server 启动规范**：先 `lsof -ti:3000 -ti:4000` 检查已有进程 → 有则直接用 → 无则 `npm run dev &` 后台启动 + `sleep 8` 等待 → 不要将多条命令拼接为一行（避免参数解析错误）。

| 场景类型 | 示例 |
|----------|------|
| CLI/Hook/配置 | 运行命令验证输出和退出码，模拟 stdin 验证 stdout |
| API/UI/库函数 | curl 调用端点验证响应，启动 dev server 验证渲染，临时脚本验证返回值 |

##### 防合理化指南（Tier 1.5 专用）

| 借口 | 现实 |
|------|------|
| dev server 太重 / 已通过 tsc+jest | `npm run dev &` 等 5 秒即可；单测验证代码结构，真实测试验证用户场景 |
| 设计文档没写 / 后续手动验证 | 没有就自行设计 1 个；QA 阶段就是验证阶段，"后面再验"= 跳过验证 |
| 蓝队已冒烟 / 场景 1 已验核心 | QA 必须独立执行；little-bee-cli 48 测全过但 4 bug 靠手动发现，只跑了 --help |

> **教训**：little-bee 性能优化 — 45 单测全过但 Tier 1.5 被跳过，集成 bug（缺少 profileId 多一次 fallback 请求）靠手动发现。

> **教训**：little-bee-cli — 48 测全过但 4 bug 靠手动发现，设计了 3 个真实场景只执行了 --help，跳过了需要 server 的场景。

#### Wave 2 — AI 审查（并行 Agent，基于 Wave 1 + Wave 1.5 结果）

**在同一轮响应中使用 Agent 工具启动两个并行审查 Agent。** 两个 Agent 独立运行、互不依赖，完成后合流。

##### Tier 2a: design-reviewer Agent（设计符合性）

使用 Agent 工具启动 design-reviewer（model: "sonnet"），prompt 参考 `references/design-reviewer-prompt.md` 模板，填入：
- 设计文档（从状态文件 `## 设计文档` 复制）
- Wave 1 + Wave 1.5 各 Tier 通过/失败状态摘要
- 项目根目录路径

**核心原则**：不信任，独立验证 — Agent 必须读取实际代码逐项比对设计要求。
如果 Wave 1 有大量 ❌，仍然启动审查——可能揭示根本原因。

##### Tier 2b: code-quality-reviewer Agent（代码质量）

使用 Agent 工具启动 code-quality-reviewer（model: "sonnet"），prompt 参考 `references/code-quality-reviewer-prompt.md` 模板，填入：
- 项目根目录路径
- CLAUDE.md 内容或关键项目约定（如果存在）
- Wave 1 + Wave 1.5 各 Tier 通过/失败状态摘要

**核心原则**：置信度评分过滤 — Agent 按 `references/code-quality-reviewer-prompt.md` 中的审查清单审查，只报告置信度 ≥80 的问题。

##### 合流

两个 Agent 都完成后：
1. 收集 design-reviewer 产出：设计符合状态 + 问题列表
2. 收集 code-quality-reviewer 产出：Issues（Critical/Important/Minor）+ Assessment
3. 合并为 QA 报告的 Tier 2a/2b 部分

##### 降级策略

- **单个 Agent 失败** → 在变更日志记录警告，使用另一个 Agent 的结果继续（不阻塞流程）
- **两个 Agent 都失败** → 编排器自行执行简化版审查（仅检查最关键项：设计覆盖率 + OWASP Top 10）
- **红队未生成测试** → 设计审查 Agent 额外承担验收检查清单的逐项人工验证

#### 产出报告

将 QA 报告写入状态文件的 `## QA 报告` 区域。**写入前先将所有历史轮次报告压缩为一行摘要**（格式：`### 轮次 N (时间) — ✅/❌ 简要结果`），只保留最新一轮完整报告。报告格式和示例参见 `references/qa-report-template.md`。

#### 结果判定

**前置检查**（两步，必须按顺序执行）：

**步骤 1 — 场景计数匹配**：统计 Tier 1.5 报告中 `执行:` 标记数量 E，对比设计文档验证方案中的实际场景总数 N。E < N → ❌ 有场景被跳过，回去补做 Wave 1.5 中遗漏的场景。

**步骤 2 — 格式检查**：验证 Tier 1.5 报告的每个场景是否都包含 `执行:` 和 `输出:` 标记。如果 Tier 1.5 只有描述性文字而没有实际命令输出，视为 ❌ 未执行，必须回去补做 Wave 1.5。

- **全部 ✅（可有 ⚠️）** → 更新 frontmatter：`gate: "review-accept"`
- **有 ❌** → 更新 frontmatter：`phase: "auto-fix"`，在报告末尾列出需修复项清单

#### 改进建议

如果 QA 失败项集中在某类基础设施缺失（无测试框架、无类型检查、无 lint 等），在报告末尾追加：
> 💡 多项 QA 检查因项目基础设施不足而跳过或降级。建议运行 `/autopilot doctor` 诊断并改进工程基础设施。

---

## Phase: auto-fix — 自动修复阶段

### 目标
读取 QA 失败项，逐项分析根因并修复（max 3 次重试）。

### ⚠️ 红队测试铁律
**绝对不允许修改红队验收测试。** 问题在实现，不在测试——无例外。

| 借口 | 现实 |
|------|------|
| 改断言值就过了 / 我知道问题直接修 | 这就是修改红队测试，铁律无例外；70% shotgun fix 引入新 bug，先验证假设再修 |

### 工作流程

#### 1. 读取失败项
从最近一轮 QA 报告中提取所有 ❌ 标记的项目。

#### 2. 区分失败来源并确定修复策略

**并行判断**：如果多个失败项涉及**不同文件且互不依赖**，可以并行修复（多个 Edit 调用）。涉及**同一文件或有依赖关系**时必须串行。

##### 红队验收测试失败（Tier 0）— 最高优先级
- **含义**：实现不符合设计要求
- **修复目标**：修改实现代码使其满足设计文档的要求
- **绝对禁止**：修改红队测试文件（`.acceptance.test.*`）
- **修复方式**：
  1. 阅读失败的验收测试，理解它期望的行为
  2. 对照设计文档确认期望是正确的
  3. 定位实现代码中的偏差
  4. 修改实现代码以满足期望

##### 蓝队单元测试失败（Tier 1 测试部分）
- **含义**：实现内部有 bug
- **修复方式**：修复实现代码中的 bug
- **特殊情况**：如果蓝队测试与红队测试矛盾（测试同一行为但期望不同），以红队测试（设计意图）为准，修改蓝队测试

##### 类型/Lint/构建失败（Tier 1 其他部分）
- 类型错误 → 修正类型声明或实现
- Lint 错误 → `eslint --fix` 或手动修复
- 构建失败 → 检查导入、依赖、配置

##### 代码质量/安全问题（Tier 2-4）
- 最小化重构，保持行为不变

##### 真实场景验证失败（Tier 1.5）
- **含义**：功能在真实用户场景下不可用（可能单元测试全通过但真实运行失败）
- **修复方式**：
  1. 分析场景执行的实际输出（错误信息、日志、退出码）
  2. 与预期结果对比，定位偏差点
  3. 这类问题通常是集成问题（路径、环境、权限、配置），而非逻辑错误
  4. 修复后必须重新执行该场景验证，附上成功输出作为证据

#### 3. 逐项修复 — 系统化调试方法论

对每个失败项，严格按四阶段执行：

**a. 观察**
- 完整阅读错误信息和上下文，不跳过任何细节
- 记录错误的完整堆栈和相关文件位置

**b. 假设**
- 形成明确的因果假设："X 导致 Y，因为 Z"
- 写下假设再行动，避免盲目修改

**c. 验证**
- 用最小实验验证假设（添加日志、运行单个测试、检查变量值）
- 假设被推翻 → 回到观察阶段，不要在错误假设上继续修

**d. 修复**
- 假设被验证后才做修复
- 应用最小化修复，`git add` 暂存
- 立即运行对应检查命令确认修复，**附上命令输出作为证据**

#### 4. 重试控制
- 读取 frontmatter 的 `retry_count`
- `retry_count++`，更新状态文件
- **retry_count < max_retries** → 设置 `qa_scope: "selective"`，更新 `phase: "qa"` 回去选择性重跑失败 Tier（参见 QA 阶段「前置：选择性重跑判断」）
  - 例外：如果本次 auto-fix 是从 Wave 1 快速路径进入的（QA 报告标注了 `[快速路径]`），不设置 `qa_scope`，执行全量 QA
- **retry_count >= max_retries** → 停止自动修复：
  - 在 QA 报告中标注哪些已修复、哪些仍未解决
  - 更新 `gate: "review-accept"`（让用户决定）
  - 追加变更日志：自动修复达到上限

#### 5. 修复优先级
1. **红队验收测试失败**（Tier 0）→ 实现不符合设计，必须修复实现
2. **真实场景验证失败**（Tier 1.5）→ 功能在用户场景下不可用，根据场景输出定位根因
3. **lint/类型错误** → 通常可自动修复
4. **蓝队单元测试失败** → 分析是实现 bug 还是测试本身问题
5. **构建失败** → 检查导入、依赖、配置
6. **安全问题** → 添加输入验证、转义、权限检查
7. **代码质量问题** → 重构，保持最小改动

---

## Phase: merge — 合并阶段

### 目标
完成代码提交和最终收尾。

### 工作流程

#### 1. 调用 commit Agent（上下文隔离提交）

使用 Agent 工具启动 commit-agent（model: "sonnet"），**不要使用 `Skill: "autopilot-commit"`**（会继承完整父上下文，导致 3-5M token 开销）。

**预收集 Agent 输入**（编排器在启动 Agent 前通过 Bash 获取）：
- `git diff --stat` 输出（变更概况）
- `git diff` 完整 diff（供分析具体改动）
- 设计文档的目标一句话（从状态文件 `## 设计文档` 提取）
- commit type 判断依据（根据变更性质判断 feat/fix/refactor 等）
- 项目根目录路径

**启动 Agent**：prompt 参考 `references/commit-agent-prompt.md` 模板，填入上述输入。Agent 执行：分析变更 → 生成 commit message（中文） → git add → git commit → 版本号升级 → CLAUDE.md 更新。

编排器收到 Agent 结果后，验证 `git log --oneline -1` 确认提交成功。

#### 1.5. 写入 Handoff（brief 模式）

如果 frontmatter `brief_file` 非空（任务来自项目 DAG）：

1. 从 `brief_file` 路径推导 handoff 路径：将 `.md` 替换为 `.handoff.md`（如 `tasks/001-wire-schema.md` → `tasks/001-wire-schema.handoff.md`）
2. 写入 handoff 文件（≤500 字），包含：实现摘要、文件变更列表、下游须知、偏差说明
3. 更新 `.autopilot/project/dag.yaml` 中对应任务的 `status` 从 `pending`/`in_progress` 改为 `done`
4. 追加变更日志：handoff 已写入

#### 2. 知识提取与沉淀

commit Agent 完成后，回顾本次全流程产出，提取值得持久化的知识。

1. 读取 `references/knowledge-engineering.md` 获取完整提取规则和格式模板
2. 分析状态文件中的设计文档、QA 报告、变更日志、auto-fix 修复历程
3. 反馈驱动判断：仅记录有真实学习价值的条目（设计权衡、调试教训、项目特有约定）
4. 有值得记录的条目：
   a. 自动生成 tags（从设计文档和代码变更中提取关键词：模块名、技术栈、问题类型）
   b. 确定写入目标文件：通用条目 → `decisions.md` / `patterns.md`；领域特定条目 → `domains/{domain}.md`
   c. 追加条目到目标文件（使用 `<!-- tags: ... -->` 格式）
   d. 同步更新 `index.md`：为每个新条目添加索引行（如 `index.md` 不存在则创建）
   e. 检查全局文件行数：>100 行时建议用户将领域条目迁移到 `domains/`
   f. 确定知识库 git 提交上下文（worktree 安全路由）：
      - **步骤 1**：检查 `.autopilot` 是否为符号链接
        - 是 → 解析真实路径：`MAIN_REPO=$(cd "$(realpath .autopilot)" && git rev-parse --show-toplevel)`，使用 `git -C "$MAIN_REPO"` 提交 → 完成
      - **步骤 2**（非符号链接）：检查当前是否在 worktree 中（`.git` 是文件而非目录）
        - 是 worktree → 详细的 worktree 安全路由脚本参见 references/knowledge-engineering.md 的"Worktree-Aware Extraction"章节。
      - **步骤 3**（非 worktree）：正常执行 `git add .autopilot/ && git commit -m "docs(knowledge): ..."`
5. 无值得记录的内容 → 在变更日志追加"知识提取：本次无新增"后跳过

时间限制 2 分钟。宁可少写高质量条目，不要穷举。

#### 3. 最终总结

输出结构化完成报告（6 个区块）。报告模板和格式要求参见 `references/completion-report-template.md`。

#### 4. 清理
- 更新 frontmatter：`phase: "done"`
- Stop hook 检测到 done 后会自动清理状态文件并发送完成通知

---

## 状态文件更新规范

### frontmatter 更新

**⚠️ 绝对不要用 Write 工具重写整个状态文件。** 必须使用 Edit 工具精确修改 frontmatter 中的字段值。重写会丢失 stop-hook 必需的字段（`iteration`、`max_iterations`、`session_id`），导致 stop-hook 误判文件损坏并删除。

**Read 操作精简**：每个阶段开始时 Read 一次状态文件获取全局信息，后续操作使用 Edit 精确修改。不需要在每次 Edit 前重复 Read 整个文件。

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
mode: ""                 # AI 更新：""（待检测）/ "project" / "single"
brief_file: ""           # setup.sh 创建（任务文件匹配时自动设置）
qa_scope: ""             # AI 更新：auto-fix 设置 "selective"，QA 全部通过后清空
session_id: "..."        # setup.sh 创建，AI 不要修改
started_at: "..."        # setup.sh 创建，AI 不要修改
---
```

示例：将 phase 从 design 改为 implement：
```
old: phase: "design"
new: phase: "implement"
```

### 内容区域更新
- `## 设计文档`：design 阶段写入，后续不修改（除非 revise 回到 design）
- `## 实现计划`：design 阶段写入，implement 阶段更新任务完成状态 `[x]`
- `## 红队验收测试`：implement 阶段合流时写入，记录红队生成的测试文件和验收标准
- `## QA 报告`：qa 阶段追加新轮次报告（不覆盖之前的）
- `## 变更日志`：每次关键操作都追加一行 `- [时间戳] 事件描述`

### 知识文件（.autopilot/）
知识文件不属于状态文件，是独立的持久文件。知识提取在 merge 阶段直接写入 `.autopilot/` 目录，用单独的 git commit 提交，不写入状态文件。知识目录包含索引层（`index.md`）、全局文件（`decisions.md`、`patterns.md`）和领域分区（`domains/*.md`）。详细格式和规则参见 `references/knowledge-engineering.md`。

### 红队验收测试区域格式

状态文件格式模板和示例参见 references/state-file-guide.md。

### 变更日志写入

状态文件格式模板和示例参见 references/state-file-guide.md。
