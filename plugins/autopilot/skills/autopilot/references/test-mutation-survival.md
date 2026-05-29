# Mutation-Survival 自检参考手册（降级清单）

> **v3.36 起本文件已精简为降级清单。Tier 5 工具量化门禁是主路径（references/quantitative-metrics.md）。**
>
> AI 主观自检比客观工具数字弱一个数量级。Stryker（mutation score）+ Istanbul/c8（coverage）可用时强制走 Tier 5；两子项均无工具时再退回本文清单作为兜底。

---

## Mutation-Survival 自检铁律

**触发条件**：测试中存在至少 1 个用户交互（`click()` / `fill()` / `submit()` / `drag()` / `dispatch()`）。

**最低要求**：每个用户交互后的断言必须能 kill **至少 No-op Mutation**（把 handler 改为空函数 `() => {}`，测试仍通过即视为反模式）。

---

## 5 类核心 mutator（业界对齐，基于 PIT / Stryker 最高 ROI）

| # | Mutation 类型 | 自问 | 适用层级 |
|---|--------------|------|---------|
| 1 | **No-op Mutation** | 把 handler 改为 `() => {}`，测试还会通过吗？ | UI / CLI / API |
| 2 | **Conditional Flip** | 把 `if (X)` 改为 `if (!X)` 或 `if (true)`，测试会失败吗？ | 所有 |
| 3 | **Boundary Mutation** | 把 `===` 改为 `>=`、`<` 改为 `<=`，测试会失败吗？ | 数值 / 计数 |
| 4 | **Return-Value Mutation** | 把返回值改为 `true` / `[]` / `null`，测试会失败吗？ | API / 函数 |
| 5 | **State-Update Skip** | 跳过 `setState` / `dispatch`，测试会失败吗？ | UI 状态 |

---

## 反模式速查（典型 Tautological Test）

- **Stable Element Assertion**：断言一个页面初始即存在的元素仍然可见（与交互无关）。
- **Click Chain Without Mid-Asserts**：连续多次交互后只在最终检查一次状态，中间无断言。
- **Timer-Only Wait**：`waitForTimeout(N)` 后只断言页面初始即满足的条件。

---

## 正模式速查（Mutation-Resistant）

- **Observable State Transition**：断言**仅由该交互产生**的状态变化（计数 / aria-state / 文本）。
- **State-Driven Wait**：`expect(...).toBeVisible({ timeout })` 等待交互产生的元素，不用 `waitForTimeout`。
- **Negative Path Verification**：对"应该无副作用"的操作显式断言状态未变。

---

## 也用于 design 阶段审谓词

预注册验收谓词（scenario-generator 的 `assert:`）同样套本手册：`height >= 44`（数字，可 kill Boundary mutation）合格；`element visible`（页面初始即满足）是 Stable Element Assertion 反模式，design 阶段当场打回。每条谓词的 assert 必须能 kill 至少 No-op mutation。

---

## 适用边界（不触发）

1. 纯渲染测试（无交互，渲染即行为）
2. 纯 API 契约测试（无用户交互，断言即规范）
3. 纯函数单元测试（函数式断言天然 mutation-resistant）
4. Negative testing（断言"无变化"本身即 kill No-op mutation）

---

## 业界证据脚注

| 来源 | 结论 |
|------|------|
| **Coulman 2016** | 定义 Tautological Test：断言镜像实现而非独立行为，测试永远通过但无保护价值 |
| **Meta FSE 2025 / InfoQ 2026** | mutation testing 用于 LLM 生成测试合规门禁；约 50% LLM 测试无法 kill 任何 mutation |
| **arXiv 2506.02954 MutGen** | 74% LLM 测试失败根因是 oracle 质量问题 |
