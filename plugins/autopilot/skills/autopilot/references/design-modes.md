# Design 阶段三模式详解

主 SKILL.md `Phase: design` 章节是路由器——只列出决策树和每个模式的入口，详细执行步骤都在本文件。

模式由 frontmatter 两个字段决定，优先级从高到低：`auto_approve > fast_mode > 默认 (Standard)`。

## §1. 三模式速查表

| 模式 | 触发条件 | 跳过的节点 | 失败回退 |
|------|----------|-----------|----------|
| Auto-Approve | `auto_approve: true`（auto-chain 设置） | AskUserQuestion 审批；qa 通过后跳过 `gate: "review-accept"` 直接 merge | 设 `auto_approve: false`，回到 Standard 人工审批 |
| Fast Mode | `fast_mode: true`（启动 `--fast` 或自适应判断） | brainstorm Q&A、scenario-generator、plan-reviewer Agent、contract-checker、qa-reviewer Agent；Tier 1.5 必做 | 自审失败修正 1 次仍 FAIL → AskUserQuestion 交用户 |
| Standard | 其他（默认） | 无（全节点保留） | — |

注意：红蓝对抗 / 红队验收测试 / qa Wave 1+1.5 是核心，三模式都保留不动。

## §2. Auto-Approve 完整工作流

`auto_approve: true` 通常由 stop-hook 的 auto-chain 机制在项目子任务推进时自动设置。design 阶段流程：

1. 执行知识上下文加载（主 SKILL.md 步骤 0）
2. 1 个 Explore agent 快速分析任务相关代码
3. 直接将设计文档写入状态文件 `## 设计文档` 和 `## 实现计划` 区域
4. **Plan 审查（必须执行）**：启动 plan-reviewer Agent（model: "sonnet"，参见 `plan-reviewer-prompt.md`）
5. **PASS** → 更新 `phase: "implement"`
6. **FAIL** → 设 `auto_approve: false`，回退到 Standard 正常审批流程（重新走主 SKILL.md 步骤 1）

qa 阶段差异：

| 阶段 | 正常行为 | auto_approve=true |
|------|----------|-------------------|
| design | AskUserQuestion 审批 | 跳过审批，写设计文档 + plan-reviewer 审查 → 通过推进 |
| qa | 全部 ✅ → `gate: "review-accept"` | 全部 ✅ → 直接 `phase: "merge"`（跳过 gate） |

**失败回退总则**：任何环节失败 → 设 `auto_approve: false`，回退到正常人工审批。

## §3. Standard Design 模式详细步骤

委托 `Skill: "autopilot-brainstorm"` 完成需求探索（默认触发，`--fast` 跳过）。

完成后续步骤：

1. 读取 `$TASK_DIR/brainstorm.md`（brainstorm skill 的共识总结产出）
2. 主 SKILL 接力：按主 SKILL.md「步骤 2. 代码探索与设计文档编写」执行（按需 1 个或多个 Explore agent + 并行启动 scenario-generator）
3. 设计文档写入状态文件 `## 设计文档` 和 `## 实现计划` 区域
4. 主 SKILL.md「步骤 3. Plan 审查」：plan-reviewer Agent 审查（最多 2 轮）
5. 主 SKILL.md「步骤 4. 请求审批」：AskUserQuestion + 3 选项（通过 / 修改 / 放弃）
6. 审批通过 → 主 SKILL.md「步骤 5. 审批通过后」

**兼容性**：历史 state.md 中的 `plan_mode: "deep"` 同样走此分支；`plan_mode` 字段已弃用，新代码不读。

## §4. Fast Mode 详细 diff

`fast_mode: true` 时砍掉所有 plan-review 类节点（红蓝对抗 / qa Wave 1+1.5 是核心，保留不动）：

| 阶段 | Fast Mode 行为 |
|------|---------------|
| design | 知识加载 → **1 个**（按需，复杂时自行增加）Explore agent → 设计文档写入状态文件 → 按 `plan-reviewer-prompt.md` 6 维度**自审**（编排器 inline，不启动 scenario-generator / plan-reviewer Agent，不做 brainstorm Q&A）→ 自审通过 → `html_review: true` 仍走步骤 4c HTML 评审，否则**直接 `phase: "implement"`**（跳过 AskUserQuestion 审批，fast 信任 AI 判断） |
| implement | blue-team / red-team 双 Agent 保留不变，**跳过 contract-checker Agent**（步骤 2.5 在 fast_mode=true 时直接进入 qa） |
| qa | `qa_scope=smoke`（详见主 SKILL.md 「Phase: qa 前置：选择性重跑判断」），不启动 qa-reviewer Agent，编排器自行 Read git diff 后 inline 做 3 项自审（设计符合性 / OWASP 关键 / 代码质量明显问题）。Tier 1.5 必做铁律不变 |
| merge | commit-agent 保留不变 |

**自审 6 维度**：需求完整性 / 技术可行性 / 任务分解 / 验证方案 / 风险 / 范围控制（完整定义见 `plan-reviewer-prompt.md`）。

## §5. 自审失败回退到 AskUserQuestion 的判定

Fast Mode 自审若失败：

1. 第 1 次 FAIL → 修正设计文档（按自审报告的 BLOCKER 项），再做 1 次自审
2. 第 2 次仍 FAIL → 回退到 Standard 审批流程，触发主 SKILL.md 步骤 4 AskUserQuestion，附上未解决的 BLOCKER 清单，由用户决定
3. 不修改 frontmatter 的 `fast_mode` 字段（保持 fast 标记，仅审批通路降级；后续 implement / qa 阶段仍走 fast 的轻量分支）

Auto-Approve 失败回退（见 §2 步骤 6）：直接设 `auto_approve: false`，下一轮按 Standard 走，包括 AskUserQuestion 审批。

——
跨引用：`plan-reviewer-prompt.md`（自审 6 维度模板）、`scenario-generator-prompt.md`（标准模式并行启动的验收场景生成器）、`html-review-guide.md`（步骤 4 HTML 评审路径）。
