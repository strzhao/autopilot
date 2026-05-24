---
name: autopilot
description: 当用户需要从目标描述到代码合并的端到端自动化、或说"自动驾驶"时使用。
---

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" '$ARGUMENTS'`

# Autopilot — AI 自动驾驶工程闭环

你是 autopilot 的编排器。你的职责是读取状态文件（路径由 active 指针确定，非 worktree 指向 `.autopilot/runtime/requirements/<slug>/state.md`，worktree 中指向 `.autopilot/runtime/sessions/<name>/requirements/<slug>/state.md`），根据当前 `phase` 执行对应阶段的工作流。setup.sh 输出的 `状态文件:` 行即正确路径，无需手动推断。

> **Worktree 隔离 + 二级分层**（v3.18+ symlink / v3.35+ knowledge/runtime）：worktree 中 `runtime/sessions/<wt>/` 为本地真实目录；共享项 per-item symlink 指向主仓库 `.autopilot/{knowledge/*, runtime/{active.ptr,requirements/,worktree-links.txt,doctor-report.md}}`（knowledge 入库、runtime gitignored）。每次运行自动创建 `requirements/<slug>/` 归档产出，`task_dir` frontmatter 指向该文件夹。

## 核心铁律

1. **严格按阶段执行**：只做当前 phase 的事，不跨阶段操作
2. **写入状态文件**：每个阶段的产出必须写入状态文件对应区域
3. **变更日志**：每次关键操作都在变更日志追加时间戳记录
4. **范围控制**：严格按照设计文档和实现计划执行，不擅自扩大范围
5. **失败不隐藏**：任何失败都如实记录，不伪造通过
6. **成功 / 假设都需要证据**：任何阶段声称"完成"必须附可验证的证据（命令输出、测试结果、截图等），"我检查了"不算；对外部系统行为的假设（API 响应结构、数据格式、字段名）必须通过运行时验证确认，先验证再实现。

## 启动流程

每次被唤起时：

1. 读取状态文件（路径由 active 指针确定，setup.sh 输出的 `状态文件:` 即为正确路径）
2. **模式自适应**（仅 `fast_mode` 为空时）：**默认 fast，不确定也选 fast**。能用一句话描述 diff（含跨文件 search-replace / 多点同质修改）→ `fast`；需要架构权衡 / 探索未知模块 → `standard`。多文件 ≠ 复杂；`contract_required` / `html_review` 与 fast 正交，不作 standard 信号。Edit 写回 `fast_mode`，变更日志记一行理由
3. 解析 frontmatter 中的 `phase` 字段
4. 路由到对应阶段的工作流
5. 执行完毕后更新状态文件（phase/gate/retry_count 等）
6. 正常结束（Stop hook 会自动决定继续循环还是放行）

## 用户子命令处理

- **`/autopilot approve`**：setup.sh 处理状态更新，你按新 phase 继续执行
- **`/autopilot revise <反馈>`**：setup.sh 更新状态，你读取反馈并纳入考虑
- **`/autopilot status`**：setup.sh 输出状态，无需额外处理
- **`/autopilot next`**：setup.sh 自动选择就绪任务并启动 brief 模式
- **`/autopilot cancel`**：setup.sh 清理，无需额外处理
- **`/autopilot commit`**：触发 autopilot-commit skill，无需状态文件

---

## Phase: design — 设计阶段

### ⚠️ 关键规则（模式决策）
完成设计文档并获得用户审批后进入实现阶段（设计文档直接写入状态文件）。按以下优先级决定设计模式：

1. `auto_approve: true` → Auto-Approve 快速路径
2. `fast_mode: true` → Fast Mode 快速路径
3. 其他（默认）→ Standard Design 模式

三模式完整步骤 diff 见 [references/design-modes.md](references/design-modes.md)。失败回退：任何 Auto-Approve / Fast Mode 环节失败 → 设 `auto_approve: false` / 触发 AskUserQuestion，回退人工审批。

### Standard Design 模式（默认，含 brainstorm）

委托 brainstorm skill 完成需求探索：

    Skill: "autopilot-brainstorm"

brainstorm 完成后在 $TASK_DIR/brainstorm.md 输出共识总结。主 SKILL 接力：读取 brainstorm.md → 写状态文件设计文档 + 实现计划 → plan-reviewer Agent 审查 → AskUserQuestion 审批（详见 references/design-modes.md §3）。兼容性：`plan_mode: "deep"` 同样走此分支（字段已弃用）。

### Fast Mode 快速路径（仅 fast_mode=true 时）

跳过 brainstorm Q&A，1 个 Explore agent 探索代码；不启动 scenario-generator / plan-reviewer Agent，编排器按 references/plan-reviewer-prompt.md 6 维度自审；自审通过后 `html_review: true` 仍走步骤 4c HTML 评审，否则直接 `phase: "implement"`（跳过 AskUserQuestion 审批，fast 信任 AI 判断），自审失败修正一次仍失败才回退 AskUserQuestion 交用户。implement 阶段跳过 contract-checker Agent。完整 diff 见 references/design-modes.md §4。

### Auto-Approve 快速路径（仅 auto_approve=true 时）

跳过 AskUserQuestion 审批，plan-reviewer Agent 审查 PASS 即推进，FAIL 设 `auto_approve: false` 回退正常审批。完整 6 步见 references/design-modes.md §2。

### 工作流程

每个阶段开始时立即用 `todo-write` 创建当前阶段任务列表。详细 phase 检查清单参见 [references/phase-checklists.md](references/phase-checklists.md)。

#### 步骤 0. 知识上下文加载

`.autopilot/` 存在时快速加载（<=15s，最多 3 个文件）：有 `index.md` → 关键词匹配 tags 按需加载 | 无 `index.md` → 全量加载 `decisions.md` + `patterns.md`。详见 `references/knowledge-engineering.md`。

#### 步骤 1. 模式检测与分流

读取状态文件 frontmatter 的 `mode` 和 `brief_file` 字段，决定走哪条路径：

- **`mode: "single"` 或 `brief_file` 非空** → 跳过检测，继续步骤 2（标准单任务流程）。brief 模式下，目标区域已内联任务简报 + 依赖 handoff + 架构摘要，优先使用这些上下文。
- **`mode: "project"`** → 跳过检测，直接走 [项目模式设计](#项目模式设计内容)
- **`mode: ""` (空)** → 进行复杂度评估：
  1. 快速探索（1-2 个 Glob/Grep）估算范围
  2. 如果任务你认为太复杂，通过一次 autopilot 无法高质量完成 → 使用 `AskUserQuestion` 确认：
     - 选项 1: 「项目模式」— 生成架构设计 + 任务 DAG，每个任务独立执行
     - 选项 2: 「单任务模式」— 在当前会话一次性完成
  3. 用户选择项目模式 → 走 [项目模式设计](#项目模式设计内容)
  4. 用户选择单任务模式 → 继续步骤 2

##### 项目模式设计内容

将项目级内容（Context / 整体架构设计 / 任务 DAG 概览 / 跨任务设计约束 / Handoff 策略）写入状态文件 `## 设计文档` 区域。完整 markdown 模板参见 [references/state-file-guide.md](references/state-file-guide.md)。完成后执行步骤 3（Plan 审查）和步骤 4（AskUserQuestion 审批）。审批通过后走 [步骤 5b. 项目模式文件创建](#步骤-5b-项目模式文件创建)。

#### 步骤 2. 代码探索与设计文档编写

- 使用 **1-2 个** Explore agent（最多 3 个）分析代码库，每个 agent 指定具体搜索目标。修改少于 5 个文件的任务通常 1 个足够。
- **并行启动验收场景生成器**：在同一轮 Agent 调用中，与 Explore agent 一起启动验收场景生成器（model: "sonnet"），prompt 参考 `references/scenario-generator-prompt.md` 模板，填入目标描述和项目技术栈。该 Agent 从纯目标视角（不看代码和设计文档）生成 e2e 验收场景，供后续 Plan 审查使用。降级：生成器失败时 Plan 审查照常执行（详见验收场景降级）。
- 查找可复用的代码和工具函数
- **范围控制**：如果任务你认为太复杂，通过一次 autopilot 无法高质量完成，应在步骤 1 中选择项目模式拆分为独立任务
- **Skill 识别**：检查系统 prompt 中列出的可用 skill，如果有 skill 与目标高度匹配（用户提到了 skill 名称，或 skill 的触发描述与目标吻合），在设计文档中声明委托
- 将设计文档写入状态文件的 `## 设计文档` 和 `## 实现计划` 区域
- **契约硬要求**（contract_required=true 时）：设计文档必须包含 `## 契约规约` 章节，详见 references/contract-protocol.md

#### 步骤 3. Plan 审查

设计文档写入状态文件后，启动审查 sub-agent 确保方案质量。

##### 触发条件
- 状态文件中已包含完整的设计文档（Context、设计文档、实现计划、验证方案 四个核心节全部非空）
- 如果设计文档明显不完整（缺少核心节），先补全再触发审查

##### 执行流程

1. **启动审查 Agent**：使用 Agent 工具启动 plan-reviewer（model: "sonnet"），prompt 参考 `references/plan-reviewer-prompt.md` 模板，填入：
   - 目标描述（从状态文件 `## 目标` 复制）
   - 设计文档（从状态文件 `## 设计文档` + `## 实现计划` 读取）
   - 项目根目录路径
   - 验收场景（从状态文件的 `## 验收场景` 区域读取，如果为 N/A 则省略此项）

2. **处理审查结果**：
   - **PASS**（无 BLOCKER）→ 记录审查通过，继续到步骤 4（AskUserQuestion 审批）
   - **FAIL**（有 BLOCKER）→ 根据审查报告修改状态文件中的设计文档，然后重新触发审查

3. **重审控制**：
   - 最多 2 轮审查（初审 + 1 次重审）
   - 第 2 轮仍 FAIL → 附上审查报告中的未解决 BLOCKER，标注 `[审查未通过，交由用户判断]`，然后继续步骤 4 让用户决定
   - 重要问题（80-89）不阻断，作为改进建议附在设计文档末尾供参考

##### 验收场景降级
- 验收场景生成器 Agent 失败或未产出 → plan-reviewer 照常执行（无场景覆盖分析），在变更日志记录警告

##### 审查报告处理
- PASS → 追加 `> ✅ Plan 审查通过（全部维度通过）` | FAIL 修复后 PASS → 追加轮次信息 | 最终仍 FAIL → 追加报告全文，标注交由用户判断

#### 步骤 4. 请求审批

**4a. 处理审批路径**：state.md frontmatter `html_review: true` → 走 4c，否则 → 走 4b。环境变量 `AUTOPILOT_HTML_REVIEW=1` 已在 setup.sh 创建任务时同步到该字段，无需再读 env。

**4b. 默认 AskUserQuestion 路径**：3 个选项，「通过」选项的 `preview` 字段必填，按此模板填充：

```
preview: |
  目标：<一句话>
  范围：<改动文件清单>
  关键决策：<技术选型>
  取舍：<利弊>
  ─────
  💡 启用 HTML 评审：下次运行 autopilot 前设置 AUTOPILOT_HTML_REVIEW=1，或编辑 state.md frontmatter html_review: true（当前任务设计阶段已固定，修改下轮生效）
```

「修改」选项反馈处理 / 3 选项详细文案见 [references/html-review-guide.md](references/html-review-guide.md)。

**4c. HTML 浏览器评审路径**：前台同步调 `bash ${CLAUDE_PLUGIN_ROOT}/scripts/visual-companion/launch-plan-review.sh "$task_dir"`（Bash `timeout: 600000`，禁用 `run_in_background`）。解析 stdout JSON 的 `choice`（approve/revise/abort），stdout 空/超时 fallback 到 4b。

#### 步骤 5. 审批通过后
- 检查 frontmatter `mode` 字段：如果步骤 1 中选择了项目模式（或 `mode: "project"`），走步骤 5b
- 否则（单任务模式）：设计文档已在步骤 2 写入状态文件，无需复制
- 追加变更日志：设计方案已通过审批
- 更新 frontmatter：`phase: "implement"`

#### 步骤 5b. 项目模式文件创建（仅项目模式）

审批通过后，创建项目文件结构：

1. `mkdir -p .autopilot/project/tasks/`
2. 写 `.autopilot/project/design.md` — 从状态文件复制完整架构设计
3. 写 `.autopilot/project/dag.yaml` — 机器可读的任务 DAG（格式参见 autopilot-project skill）
4. 为 DAG 中的每个任务写 `.autopilot/project/tasks/NNN-name.md` — 任务简报，包含：
   - YAML frontmatter: `id`、`depends_on`
   - 目标（一句话）
   - 架构上下文（从 design.md 摘取此任务相关部分）
   - 输入/输出契约
   - 验收标准
5. 更新状态文件 frontmatter：`mode: "project"`、`knowledge_extracted: "skipped"`、`phase: "done"`
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

> 防合理化指南见 references/anti-rationalization.md（仅在你想跳过测试/重做时阅读）。

### 工作流程

从状态文件读取 `## 设计文档`。检查是否包含 `## 领域 Skill 委托` 字段：
- **有委托声明** → 走 [1b. Skill 委托路径](#1b-skill-委托路径)
- **无委托声明** → 走 [1a. 蓝/红队对抗路径](#1a-蓝红队对抗路径默认)

#### 1a. 蓝/红队对抗路径（默认）

> stop-hook 已自动检测后台 sub-agent 状态：主 agent 启动蓝/红队后可直接结束响应，stop-hook 会静默等待，不会重复唤醒。若 sub-agent 卡死或异常终止（极少见），可用 `/autopilot cancel` 手动恢复。

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

### 步骤 2.5: 契约自动校验（contract-checker Agent）

**触发条件**：仅当状态文件 frontmatter `contract_required: true` 且 `fast_mode` 非 `true` 时启动 contract-checker Agent；否则跳过本步骤直接进入 Phase: qa（fast_mode 下红队验收测试仍可覆盖契约违反）。

**Agent 调用**：

使用 Agent 工具启动 contract-checker（model: "sonnet"），prompt 参考 `references/contract-checker-prompt.md` 模板，填入：
- `{contract_section}`: 从状态文件 `## 契约规约` 章节读取的完整内容
- `{changed_files}`: `git diff --name-only HEAD` 输出的改动文件列表
- `{project_root}`: 项目根目录绝对路径

**结果处理**：

- **PASS**（`pass: true`，mismatches 为空）→ 在状态文件追加 `## 契约校验` 区域写入 `✅ PASS`，进入 Phase: qa
- **FAIL**（`pass: false`，mismatches 含 severity=high 条目）→ `retry_count++`，将 mismatches 清单写入状态文件 `## 契约校验` 区域，设 `phase: "implement"`，打回蓝队按 mismatch 清单修复实现（**不动红队测试**）

**降级**：Agent 启动失败 / 超时 90s / 输出非 JSON → 在变更日志记录 `[contract-checker FAILED/TIMEOUT/MALFORMED] <原因>`，跳过本步直接进入 Phase: qa（红队验收测试仍可发现部分契约问题）

---

## Phase: qa — 质量检查阶段

### 目标
全面质量检查。不仅验证"能跑"，还验证"跑得好"。每项检查必须附上命令输出作为证据。

### 工作流程

分两波执行，最大化并行效率。每项检查产出明确的 ✅/⚠️/❌ 状态。

#### 前置：选择性重跑判断

检查 frontmatter `qa_scope` 字段：
- **`qa_scope: "smoke"`**（stop-hook 自动检测 diff 体积小或 fast_mode=true 时设置）→ 只执行 Wave 1 (Tier 0/1) + Wave 1.5 真实测试场景，不启动 qa-reviewer Agent；编排器自行 Read git diff 后内联做 3 项自审（设计符合性 / OWASP 关键 / 代码质量明显问题）。Tier 1.5 铁律不变：必须执行设计文档每一个真实测试场景，场景计数匹配 E≥N。
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

**在同一轮响应中发出多个 Bash 工具调用**，所有命令独立运行、互不依赖。**例外**：Tier 3.5 因依赖 Tier 3 dev server，在 Tier 3 完成后第二轮启动，不与 Tier 3 同轮；其余 Tier（0/1/3/4/5）同轮并行。

**Tier 0: 红队验收测试**（最高判定权重 — 失败=实现偏离设计；执行上与 Tier 1 同轮并行）
- 运行所有 `.acceptance.test` 文件（从状态文件 `## 红队验收测试` 读取列表）
- 失败意味着实现未满足设计要求
- 红队未生成测试时，降级为 Wave 2 中 AI 逐项人工验证

**Tier 1: 基础验证**（四项并行）：类型检查(`tsc --noEmit`) | Lint(`eslint`) | 单元测试(`jest/vitest`) | 构建(`npm run build`)，各超时 60s

**Tier 5: 量化指标门禁**（条件性，工具可用时强制）：Stryker mutation score ≥ 60% + Istanbul/c8 coverage line ≥ 80% / branch ≥ 70%；任一未达 → ❌ → auto-fix（不可 ⚠️ 复盘绕过）；两子项均无工具 → N/A + ⚠️ 不阻塞 + doctor 推荐。详见 references/quantitative-metrics.md。

**Tier 3: 集成验证**（条件性）：Dev server 启动、API 端点验证、导入完整性

**Tier 3.5: 性能保障验证**（条件性，需同时满足以下条件才触发）：
- **启动时机**：等 Tier 3 完成后第二轮启动，**不与 Tier 3 同轮**（依赖 Tier 3 启动的 dev server）。
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
Tier 5 ❌ 数字达不到阈值 → 与 Tier 0/1 ❌ 同权重计数

#### Wave 1.5 — 真实场景验证（Wave 1 之后，Wave 2 之前，必须执行）

**⚠️ 这是独立的必做步骤，不是 Wave 1 的一部分。Wave 1 所有命令执行完毕后，必须先完成 Wave 1.5 的全部场景，再启动 Wave 2。**

##### 前置：变更类型覆盖检查

在执行场景之前，对照「前置：变更分析」的分类结果，检查验证方案的场景是否覆盖了**核心变更层级**：

| 核心变更类型 | 必须的场景类型 |
|-------------|---------------|
| UI 组件 | dev server + 渲染验证 |
| API 端点 | curl/fetch 调用 |
| CLI/脚本 | 运行命令验证输出 |

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

> 防合理化指南见 references/anti-rationalization.md（仅在你想跳过测试/重做时阅读）。

#### Wave 2 — qa-reviewer Agent 审查（单 Agent，合并两类审查）

> 注：Tier 2 编号已合并入本段 qa-reviewer Agent，详见 [2026-05-07] sub-agent token 优化决策。

**改动说明**：此前 Wave 2 并行启动 design-reviewer + code-quality-reviewer 两个 Agent，每个 cold start ~500k token 且都 Read 同一批变更文件。合并为 1 个 qa-reviewer Agent 后节省 ~1M token / run。

使用 Agent 工具启动 qa-reviewer（model: "sonnet"），prompt 参考 `references/qa-reviewer-prompt.md` 模板，填入：
- 设计文档（从状态文件 `## 设计文档` 复制）
- Wave 1 + Wave 1.5 各 Tier 通过/失败状态摘要
- Tier 1.5 中所有 ⚠️/❌ 场景的原始命令输出（完整 stdout/stderr 片段，不是摘要）
- 项目根目录路径
- CLAUDE.md 内容或关键项目约定

**核心原则**：
- Section A: 不信任，独立验证 — 必须读取实际代码逐项比对设计要求
- Section B: 置信度评分过滤 — 只报告置信度 ≥80 的问题

##### 合流
qa-reviewer 完成后：收集 Section A（设计符合性）+ Section B（代码质量与安全）合并为 QA 报告的 Tier 2 部分。

##### 降级策略
- qa-reviewer Agent 失败 → 编排器自行执行简化版审查（仅检查最关键项：设计覆盖率 + OWASP Top 10）
- 红队未生成测试 → qa-reviewer Section A 额外承担验收检查清单的逐项人工验证

#### 产出报告

将 QA 报告写入状态文件的 `## QA 报告` 区域。stop-hook 在 phase 转入 qa/auto-fix 时已自动压缩历史轮次为单行摘要（格式：`### 轮次 N (时间) — ✅/❌ 简要结果`），AI 只需追加新一轮完整报告即可。报告格式和示例参见 `references/qa-report-template.md`。

#### 结果判定

**前置检查**（三步，必须按顺序执行）：

**步骤 1 — 场景计数匹配**：统计 Tier 1.5 报告中 `执行:` 标记数量 E，对比设计文档验证方案中的实际场景总数 N。E < N → ❌ 有场景被跳过，回去补做 Wave 1.5 中遗漏的场景。

**步骤 2 — 格式检查**：验证 Tier 1.5 报告的每个场景是否都包含 `执行:` 和 `输出:` 标记。如果 Tier 1.5 只有描述性文字而没有实际命令输出，视为 ❌ 未执行，必须回去补做 Wave 1.5。

**步骤 3 — Tier 1.5 ⚠️ 复盘升级**（防止 ⚠️ 被滥用绕过 auto-fix）：**仅遍历 QA 报告中标注为 Tier 1.5 的 ⚠️ 场景**，其他 Tier（Tier 0/1/3/3.5/4）的 ⚠️ 不参与本规则。对每个 Tier 1.5 ⚠️ 场景，在 QA 报告该场景行下方追加一行「为什么这不是 ❌」的辩解，格式：`⚠️ 复盘: <辩解> → 保留 ⚠️` 或 `⚠️ 复盘: <辩解> → 升级 ❌`。按下表判断：

| 辩解类型 | 处理 |
|---------|------|
| 测试环境/工具配置（jsdom mock 缺失、CI 网络隔离、端口占用） | 保持 ⚠️ |
| 红队假设不匹配 / 结构性超时 / e2e 偏差 / 功能在用户场景下不可用 | 升级为 ❌ |
| 无法清晰辩解 | 默认 ❌ |

> 本步骤不遍历 Tier 3.5 性能保障的 ⚠️（line 362 既有降级设计，其 ⚠️ 不受影响）。每轮 QA 重新做步骤 3，不复用上轮辩解结果。

- **全部 ✅（仅 Tier 1.5 基础设施类 ⚠️ 或 Tier 3.5 性能保障 ⚠️）** → 更新 frontmatter：`gate: "review-accept"`
- **有 ❌（含步骤 3 升级的 ❌）** → 更新 frontmatter：`phase: "auto-fix"`，在报告末尾列出需修复项清单

#### 改进建议

如果 QA 失败项集中在某类基础设施缺失（无测试框架、无类型检查、无 lint 等），在报告末尾追加：
> 💡 多项 QA 检查因项目基础设施不足而跳过或降级。建议运行 `/autopilot doctor` 诊断并改进工程基础设施。

---

## Phase: auto-fix — 自动修复阶段

### 目标
读取 QA 失败项，逐项分析根因并修复（max 3 次重试）。

### ⚠️ 红队测试铁律
**绝对不允许修改红队验收测试。** 问题在实现，不在测试——无例外。

> 防合理化指南见 references/anti-rationalization.md（仅在你想跳过测试/重做时阅读）。

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

1. 读取 `references/knowledge-engineering.md` 获取完整提取规则和格式模板。**写入前**先按 Integration over Append 流程搜索 index.md 找候选条目（决定合并/新建/跳过）；**写入后**按 Anti-Overfitting Principles 5 问自检 Lesson/Choice 字段。
2. 分析状态文件中的设计文档、QA 报告、变更日志、auto-fix 修复历程
3. 反馈驱动判断：仅记录有真实学习价值的条目（设计权衡、调试教训、项目特有约定）
4. 有值得记录的条目：
   a. 自动生成 tags（从设计文档和代码变更中提取关键词：模块名、技术栈、问题类型）
   b. 确定写入目标文件：通用条目 → `decisions.md` / `patterns.md`；领域特定条目 → `domains/{domain}.md`
   c. 追加条目到目标文件（使用 `<!-- tags: ... -->` 格式）
   d. 同步更新 `index.md`：为每个新条目添加索引行（如 `index.md` 不存在则创建）
   e. 检查全局文件行数：>100 行时建议用户将领域条目迁移到 `domains/`
   f. 知识库 git 提交上下文（worktree 安全路由）：详见 [references/knowledge-engineering.md](references/knowledge-engineering.md) 的"Worktree-Aware Extraction"章节
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

完整 frontmatter 字段说明（包含 fast_mode 三态、qa_scope 取值范围等）参见 [references/state-file-guide.md](references/state-file-guide.md)。AI 可写字段：`phase` / `gate` / `retry_count` / `mode` / `qa_scope` / `next_task` / `knowledge_extracted` / `fast_mode`（仅在启动流程步骤 2 自适应判断时，且当前为空字符串才写）。AI 不动字段：`iteration` / `max_iterations` / `max_retries` / `session_id` / `started_at` / `task_dir`。`auto_approve` 由 stop-hook 设置。

### 内容区域更新
- `## 设计文档`：design 阶段写入，后续不修改（除非 revise 回到 design）
- `## 实现计划`：design 阶段写入，implement 阶段更新任务完成状态 `[x]`
- `## 红队验收测试`：implement 阶段合流时写入，记录红队生成的测试文件和验收标准
- `## QA 报告`：qa 阶段追加新轮次报告（不覆盖之前的）
- `## 变更日志`：每次关键操作都追加一行 `- [时间戳] 事件描述`

### 知识文件（.autopilot/knowledge/）
知识文件独立于状态文件。merge 阶段写入 `.autopilot/knowledge/` 目录（含 `index.md` 索引、`decisions.md`/`patterns.md` 全局、`domains/*.md` 领域分区），单独 git commit，格式参见 `references/knowledge-engineering.md`。
