---
id: p0-qa-dedup
status: done
---

# p0-qa-dedup.handoff — QA 重复执行合并（v3.63.0）

## 实现摘要
三项合并去重全部落地：① Tier 1∪Tier 5 coverage 合并（SKILL.md:239/243 + quantitative-metrics.md:60，freshness_check FRESH 复用、无工具降级逐字节不变）② contract-checker 并入 qa-reviewer Section D（删步骤 2.5 整节 + 11 处引用清扫 + 删 contract-checker-prompt.md；Section D 含 severity 枚举 + high→Critical 联动，smoke 路径 SKILL.md:228 保留 Section D）③ context.md 探针产物化（SKILL.md:79 步骤 1 写入 + 三模板改 Read）。SKILL.md 501→491 净减 10。QA 全绿：红队 19/19、npm 80/80、run-all 40/40、谓词 18/18、qa-reviewer 0 Critical（Section D 首次 dogfood C1-C4 全 ✅）。

## 文件变更
修改 15 + 删除 2（contract-checker-prompt.md、tests/contract-protocol/functional-meta.acceptance.sh）+ 新增 1（tests/acceptance/p0-qa-dedup.acceptance.test.sh）。详见本任务 commit。

## 下游须知（T2/T3 必读）
- **新行号基线**：SKILL.md 491 / qa-reviewer-prompt.md 198 / quantitative-metrics.md 183 / red-team-prompt.md 71 / blue-team-prompt.md 41；design-modes.md 69 不变。锚点一律 grep，不用旧行号
- **步骤 2.5 已不存在**：T2 改 auto-fix 段时，implement 阶段现在从「合流」直接进 Phase: qa
- **context.md 机制可复用**：T2 蓝队 prompt 加自检清单要求时，直接在 blue-team-prompt.md 现有规则 1（已是 context.md 版）附近追加
- **smoke 行已含 Section D**：T2 改 qa_scope 相关表述时注意 SKILL.md:228 现状
- **qa-reviewer ≤200 行约束**：198 已接近上限，T2 若动 qa-reviewer-prompt.md 只有 2 行余量

## 偏差说明
无（实现与设计一致）。QA 阶段过程事件（均已在 QA 报告披露）：4 条既存时序耦合断言经用户批准语义化适配（predicate-coverage 删 SC1.P1/SC3.P4、brainstorm-reuse SC4.P2 转内容断言 + 删 SC4.P3、merge-knowledge 删 P5）；structural C11 顺手修复（硬编码 3.24.0 + `$var（` 全角括号 set -u 崩溃，qa-reviewer Section B 发现的 pre-existing 崩溃，修复后 11/11 绿）；brainstorm-default 一次 flaky（复跑全绿）。
