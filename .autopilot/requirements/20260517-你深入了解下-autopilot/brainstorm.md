# Brainstorm 共识总结

> 本文档由 autopilot design 阶段 brainstorm 流程产出。用于沉淀 Q&A 探索过程与方案选择理由，供后续 plan-reviewer 审查与用户审批参考。

## 探索的目的与约束

### 目的
理解 autopilot brainstorm 环节"被阉割"的根因，评估"抽离成独立 skill 在主 skill 内调用"是否能解决：
1. 主 SKILL.md 644 行过大（超 best practice 500 行）
2. brainstorm 实际执行与 superpowers brainstorming skill 不对齐（被阉割）

### 关键约束
- 必须了解 skill best practices（`document/skill_best_practices.md`）
- 必须了解 superpowers brainstorming 实现（`/Users/stringzhao/workspace/superpowers/skills/brainstorming/`）
- 不能破坏现有契约（已有 12 个 acceptance test 锁定大量行为）
- 改动应遵循 `decisions.md` 2026-05-09「最小集 + 纯追加 + 可独立回滚」

## 候选方案与权衡

### 方案 A：抽离独立 skill + 强语言（✅ 选定）
- 新建 `plugins/autopilot/skills/autopilot-brainstorm/`，主 SKILL 通过 `Skill: "autopilot-brainstorm"` 显式调用
- 借鉴 superpowers 的 `<HARD-GATE>` / Anti-Pattern / 强制 Checklist 风格
- 主 SKILL 644 → ~580 行
- **优点**：description 触发让 AI 全神贯注，跳出"后置章节被跳过"陷阱；与 implement 阶段 Skill 委托路径有先例对齐；改动半径最小
- **缺点**：skill 数量 +1；与 state.md 协议有耦合（但通过"只做 Q&A + brainstorm.md 输出"边界控制在最小）

### 方案 B：不抽离，主 SKILL 内前置 brainstorm
- 把 brainstorm-guide.md 内容反向折叠回主 SKILL Standard Design 段落顶部
- 加 HARD-GATE 强语言解决"后置被跳过"
- **优点**：不增加 skill 数量；前置位置避免被跳过
- **缺点**：主 SKILL 反而涨到 ~720 行，与"主 skill 太大"诉求矛盾 ❌

### 方案 C：抽 brainstorm + 同步把所有 phase 拆 references
- 不仅抽 brainstorm，还把 design/implement/qa/merge 全部走 references/*-phase.md（已存在但未深度使用）
- **优点**：一次性把主 SKILL 削到 ~200 行核心路由
- **缺点**：改动面大，违背"最小集 + 可独立回滚"原则；这些 phase 文件已被 2026-03-27 Phase 分片决策抽过又涨回，根因不是它们，是主 SKILL 持续增长 ❌

## 选择与理由

**选定方案 A**。三个核心理由：

1. **唯一同时解决两个痛点的最小改动** —— 抽离让主 SKILL 减 ~64 行（部分解决"太大"），描述符触发让 brainstorm 不再被阉割（完全解决"对齐"）
2. **职责边界清晰** —— 新 skill 只做 Q&A + 方案共识（输出 brainstorm.md），plan-reviewer / 审批门 / state.md 写入留在主 SKILL，避免 SSOT 违反（fast / auto_approve 路径仍能复用主 SKILL 的审查逻辑）
3. **借鉴成熟参考** —— superpowers brainstorming（165 行）是社区验证的设计，HARD-GATE / Anti-Pattern / Checklist 三个强语言元素直接解决"AI 跳过指令"问题

### 被排除方案 B 的原因
反向折叠会让主 SKILL 涨到 720 行，与"主 SKILL 太大"用户诉求直接冲突。

### 被排除方案 C 的原因
- 改动面 5x（涉及 5 个 phase 文件 + 主 SKILL + 测试）
- 违背知识库 2026-05-09 sealed pattern「修改脆弱 skill 时遵循最小集 + 纯追加 + 可独立回滚」
- 不解决根本问题：主 SKILL 持续增长的根因是新功能不断加（fast/auto_approve/contract-checker），不是 phase 文件没拆

### 关于 plan-reviewer 是否也抽 skill（用户疑问）

**结论：不抽**。理由对比表：

| 维度 | brainstorm | plan-reviewer |
|------|-----------|---------------|
| 需要用户交互 | 是（AskUserQuestion 逐个问） | 否（纯输出 JSON 报告） |
| 当前实现形态 | references 文件被主 SKILL 引用 | 已用 Agent 工具调用（fresh context） |
| 当前是否有问题 | 被阉割 | 工作良好 |
| 抽 skill 收益 | description 触发→指令优先级提升 | 倒退到主线程继承父上下文（参考 2026-04-03 决策：merge 从 Skill 改 Agent 节省 3-5M token） |

plan-reviewer 抽 skill 是**反优化**，本次不动。

## 待主 SKILL 接力的设计决策

> brainstorm skill 职责到此为止。以下决策由主 SKILL 在 design 阶段步骤 3+ 接力执行：

1. **新 skill 文件骨架**（~120 行）—— frontmatter + HARD-GATE + Anti-Pattern + Checklist + The Process + Key Principles + brainstorm.md 模板 + 交接协议
2. **主 SKILL Standard Design 段落改写** —— line 67-77 从 ~10 行压到 ~6 行委托调用
3. **stop-hook prompt 同步** —— line 560 design phase prompt 移除 brainstorm-guide.md 引用
4. **acceptance test 同步** —— brainstorm-default.acceptance.test.sh 契约 7/8/9 + project-mode.acceptance.test.mjs:643-644
5. **版本升级** —— v3.32.0 → v3.33.0（plugin.json / marketplace.json / CLAUDE.md / README.md 顶部）

完整契约规约（C1-C10 字面契约 + 行为契约）见 `state.md` 的「## 契约规约」章节。

## 关键参考来源

- **superpowers brainstorming SKILL.md**：`/Users/stringzhao/workspace/superpowers/skills/brainstorming/SKILL.md`
- **skill best practices**：`document/skill_best_practices.md`（主体 ≤500 行 / progressive disclosure / 强 description）
- **autopilot 知识库 5 条相关决策**：
  - `decisions.md` 2026-05-08「Design 阶段默认含 brainstorm Q&A」
  - `decisions.md` 2026-03-27「SKILL.md Phase 分片优于状态文件索引」
  - `decisions.md` 2026-04-03「merge 阶段 Agent 化优于 Skill 调用」
  - `patterns.md` 2026-04-17「SKILL.md 决策树中后置章节会被 AI 跳过」（根因诊断）
  - `patterns.md` 2026-03-22「通用编排器不应替代领域专业 Skill」（Skill 委托先例）
