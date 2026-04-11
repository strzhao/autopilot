# Phase: qa — 详细工作流

## 项目 QA 模式（mode: "project-qa"）

当 `mode` 为 `project-qa` 时，执行跨任务整体验证：

1. **加载上下文**：读取 `.autopilot/project/design.md` 作为设计参考，读取状态文件 `## 任务完成摘要`
2. **变更范围**：使用 `git diff` 从项目创建以来的所有变更（而非单任务 diff）
3. **Tier 调整**：
   - Tier 0：跳过（无项目级红队测试）
   - Tier 1：全项目构建、测试、lint、类型检查 — 验证跨任务集成
   - Tier 1.5：聚焦跨任务集成场景（从 design.md 的"跨任务设计约束"提取）
   - Tier 2a：整体架构符合性检查（对照 design.md）
   - Tier 2b：全变更范围代码质量审查
   - Tier 3+：按需
4. **结果判定**：
   - 全部 ✅ → `phase: "done"`（stop-hook 发送 project-complete 通知）
   - 有 ❌ → `gate: "review-accept"`（让用户决定）
   - 不进入 auto-fix（项目 QA 失败需人工判断修复范围）

---

## 目标

全面质量检查。不仅验证"能跑"，还验证"跑得好"。每项检查必须附上命令输出作为证据。

## 工作流程

分两波执行，最大化并行效率。每项检查产出明确的 ✅/⚠️/❌ 状态。

### 前置：选择性重跑判断

检查 frontmatter `qa_scope` 字段：
- **`qa_scope: "selective"`**（auto-fix 修复后设置）→ 只重跑上一轮 `### 失败 Tier 清单` 中列出的 Tier + Tier 1.5，其余 Tier 直接沿用上轮结果标记 ✅
- **无 `qa_scope` 或值为空** → 执行全量 QA（所有 Wave/Tier）
- 全部通过后，清除 `qa_scope` 字段（Edit 为空字符串）

### 前置：变更分析

在 Wave 1 之前必须完成（后续所有检查的输入）：
- 通过 `git diff`/`git status` 识别变更文件
- 分类：前端组件、后端逻辑、配置、测试、文档、样式、依赖
- 判断影响半径：低→轻量验证 | 中→精准验证 | 高→综合验证
- 扫描项目配置识别可用的测试框架和工具

### Wave 1 — 命令执行（并行）

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

### Wave 1 失败快速路径（Early Exit to Auto-fix）

Wave 1 完成后统计 Tier 0+1 ❌ 数量：≥3 → 跳过 Wave 1.5/2 直接 auto-fix | <3 → 继续 Wave 1.5 → Wave 2 | auto-fix 后回来执行全量 QA

### Wave 1.5 — 真实场景验证（Wave 1 之后，Wave 2 之前，必须执行）

**⚠️ 这是独立的必做步骤，不是 Wave 1 的一部分。Wave 1 所有命令执行完毕后，必须先完成 Wave 1.5 的全部场景，再启动 Wave 2。**

#### 前置：变更类型覆盖检查

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

#### 防合理化指南（Tier 1.5 专用）

| 借口 | 现实 |
|------|------|
| dev server 太重 / 已通过 tsc+jest | `npm run dev &` 等 5 秒即可；单测验证代码结构，真实测试验证用户场景 |
| 设计文档没写 / 后续手动验证 | 没有就自行设计 1 个；QA 阶段就是验证阶段，"后面再验"= 跳过验证 |
| 蓝队已冒烟 / 场景 1 已验核心 | QA 必须独立执行；little-bee-cli 48 测全过但 4 bug 靠手动发现，只跑了 --help |

> **教训**：little-bee 性能优化 — 45 单测全过但 Tier 1.5 被跳过，集成 bug（缺少 profileId 多一次 fallback 请求）靠手动发现。

> **教训**：little-bee-cli — 48 测全过但 4 bug 靠手动发现，设计了 3 个真实场景只执行了 --help，跳过了需要 server 的场景。

### Wave 2 — AI 审查（并行 Agent，基于 Wave 1 + Wave 1.5 结果）

**在同一轮响应中使用 Agent 工具启动两个并行审查 Agent。** 两个 Agent 独立运行、互不依赖，完成后合流。

#### Tier 2a: design-reviewer Agent（设计符合性）

使用 Agent 工具启动 design-reviewer（model: "sonnet"），prompt 参考 `references/design-reviewer-prompt.md` 模板，填入：
- 设计文档（从状态文件 `## 设计文档` 复制）
- Wave 1 + Wave 1.5 各 Tier 通过/失败状态摘要
- 项目根目录路径

**核心原则**：不信任，独立验证 — Agent 必须读取实际代码逐项比对设计要求。
如果 Wave 1 有大量 ❌，仍然启动审查——可能揭示根本原因。

#### Tier 2b: code-quality-reviewer Agent（代码质量）

使用 Agent 工具启动 code-quality-reviewer（model: "sonnet"），prompt 参考 `references/code-quality-reviewer-prompt.md` 模板，填入：
- 项目根目录路径
- CLAUDE.md 内容或关键项目约定（如果存在）
- Wave 1 + Wave 1.5 各 Tier 通过/失败状态摘要

**核心原则**：置信度评分过滤 — Agent 按 `references/code-quality-reviewer-prompt.md` 中的审查清单审查，只报告置信度 ≥80 的问题。

#### 合流

两个 Agent 都完成后：
1. 收集 design-reviewer 产出：设计符合状态 + 问题列表
2. 收集 code-quality-reviewer 产出：Issues（Critical/Important/Minor）+ Assessment
3. 合并为 QA 报告的 Tier 2a/2b 部分

#### 降级策略

- **单个 Agent 失败** → 在变更日志记录警告，使用另一个 Agent 的结果继续（不阻塞流程）
- **两个 Agent 都失败** → 编排器自行执行简化版审查（仅检查最关键项：设计覆盖率 + OWASP Top 10）
- **红队未生成测试** → 设计审查 Agent 额外承担验收检查清单的逐项人工验证

### 产出报告

将 QA 报告写入状态文件的 `## QA 报告` 区域。**写入前先将所有历史轮次报告压缩为一行摘要**（格式：`### 轮次 N (时间) — ✅/❌ 简要结果`），只保留最新一轮完整报告。报告格式和示例参见 `references/qa-report-template.md`。

### 结果判定

**前置检查**（两步，必须按顺序执行）：

**步骤 1 — 场景计数匹配**：统计 Tier 1.5 报告中 `执行:` 标记数量 E，对比设计文档验证方案中的实际场景总数 N。E < N → ❌ 有场景被跳过，回去补做 Wave 1.5 中遗漏的场景。

**步骤 2 — 格式检查**：验证 Tier 1.5 报告的每个场景是否都包含 `执行:` 和 `输出:` 标记。如果 Tier 1.5 只有描述性文字而没有实际命令输出，视为 ❌ 未执行，必须回去补做 Wave 1.5。

- **全部 ✅（可有 ⚠️）** → 更新 frontmatter：`gate: "review-accept"`
- **有 ❌** → 更新 frontmatter：`phase: "auto-fix"`，在报告末尾列出需修复项清单

#### Auto-Approve 处理

如果 frontmatter `auto_approve` 为 `true` 且全部 ✅：
- 跳过 `gate: "review-accept"`，直接更新 `phase: "merge"`
- 追加变更日志：QA 全部通过（auto-approve）

如果有 ❌：
- 设置 `auto_approve: false`（回退到人工审批）
- 正常设置 `gate: "review-accept"` 或 `phase: "auto-fix"`

### 改进建议

如果 QA 失败项集中在某类基础设施缺失（无测试框架、无类型检查、无 lint 等），在报告末尾追加：
> 多项 QA 检查因项目基础设施不足而跳过或降级。建议运行 `/autopilot doctor` 诊断并改进工程基础设施。
