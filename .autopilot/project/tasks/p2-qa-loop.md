---
id: p2-qa-loop
depends_on: [p0-qa-dedup]
status: pending
---

# p2-qa-loop · QA 回炉治理 → v3.64.0

## 目标
压缩 qa→qa 回炉成本（调研：12 次回炉共 113h，P50 116min/轮）：① auto-fix 从「逐项修→逐项跑检查」改为「全部失败项完成观察/假设/验证 → 统一修复 → 一轮检查验证全部」② 蓝队自检证据复用——QA Tier 1 不再无条件重跑蓝队已跑绿且代码未变的同命令检查。

## 架构上下文
- 完整设计见 `.autopilot/project/design.md`（T2 节 + 契约规约 C3）
- **先读上游 handoff** `tasks/p0-qa-dedup.handoff.md`：SKILL.md 行号已变（步骤 2.5 已删），锚点以 grep 为准；T1 的 context.md 机制可在蓝队 prompt 复用
- 现状：SKILL.md auto-fix 段「3. 逐项修复」d 步「立即运行对应检查命令」；references/auto-fix-phase.md:56 同义表述；SKILL.md:240 selective 重跑逻辑
- 基线行数：SKILL.md = T1 结束后新基线（handoff 给）/ auto-fix-phase.md 94 / blue-team-prompt.md = T1 后新基线

## 输出契约
- C3 state.md `## 蓝队自检` 区域（内容区域，非 frontmatter 新字段）：每条 `- <命令> ｜ exit=<码> ｜ <一句话范围>`；蓝队 prompt 要求交付摘要附此清单，编排器写 state.md；QA 沿用判定在 QA 报告标注「沿用蓝队自检」
- 代码未再变的确定性判定下沉 lib.sh（HEAD sha / diff 比对），命令等价性语义判断留编排器（AI First）
- C5 版本号 v3.64.0，四处同步

## 跨任务约束
- SKILL.md 行数只减不增（≤ T1 后基线）
- 防滥用：蓝队自检复用必须有「同命令 + 代码未变 + exit=0」三条件，缺一重跑；不得成为跳过验证的合理化通道（anti-rationalization 对齐）
- 质量闸门不动；selective/smoke 既有 qa_scope 语义不变

## 受影响既有 acceptance 测试
- blue-team-boundary（蓝队 prompt 改动）
- skill-md-net-shrinkage / skill-shrinkage-invariants
- 以 T1 后 `grep -rn 'auto-fix\|蓝队' tests/acceptance/` 清扫结果为准

## 验收标准
- 红队新验收测试锁 C3 三条件 + 批量修复流程表述；受影响既有测试全绿
- auto-fix 四阶段方法论（观察/假设/验证/修复）保留，仅改「逐项跑检查」为「统一一轮验证」
