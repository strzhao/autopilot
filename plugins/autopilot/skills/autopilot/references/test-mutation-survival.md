# Mutation-Survival 自检参考手册（反 no-op）

> **单一真相源**。所有关于测试 Mutation-Survival 抗性的规则均定义于此。  
> 其他 prompt 文件仅持有触发铁律，细节完全在本文件。

---

## 1. 概念定义

### Tautological Test（Coulman 2016）

**定义**：测试断言镜像实现逻辑或仅验证永远成立的条件，而非独立验证行为规范。无论被测功能是否正确运行，测试均通过。

**典型症状**：click 一个按钮后，断言该按钮依然可见（该按钮在点击前后均存在）。

### Mutation Testing 上下文

Mutation Testing（突变测试）通过对源码施加微小变更（mutation），验证测试能否检测出变更（kill the mutant）。若测试无法 kill mutation，该测试不具备回归防护价值。

**case.txt 实证（little-ant Garden v4.0）**：

```typescript
// 红队生成的 e2e helper——典型反模式
async function completeCountLevel(page) {
  for (let i = 0; i < 3; i++) {
    await page.locator('[data-testid="flower-target"]').nth(i).click();
    await page.waitForTimeout(150);
  }
  await page.locator('[data-testid="watering-can"]').click();
  await page.waitForTimeout(3500);
  // ❌ flower-target 元素在页面初始即存在，无论点击是否生效均为 true
  await expect(page.locator('[data-testid="flower-target"]').first()).toBeVisible();
}
```

实际 bug：SSR hydration mismatch 导致**所有 click 都是 no-op**。测试仍通过，因断言的元素在页面加载时即存在（stable element）。

---

## 2. 触发范围

### 必须触发

测试中存在**至少 1 个**用户交互操作时：

- `click()` / `tap()` / `dblclick()`
- `fill()` / `type()` / `selectOption()`（输入类）
- `submit()`（表单提交）
- `drag()` / `dragTo()`（拖拽）
- `dispatch()` / `dispatchEvent()`（事件分发）

### 明确不触发（避免误报）

| 场景 | 原因 |
|------|------|
| 纯渲染断言（"页面加载后显示用户名"）| 无交互，渲染结果本身是 OST |
| 纯数据契约断言（API 响应字段验证）| 函数输入→输出，无状态变化 |
| 纯函数单元测试（`fn(a) === b`）| 无副作用，断言即行为本身 |
| Negative testing（断言"无变化"）| 断言无变化本身即 mutation-resistant，避免双重要求 |

---

## 3. Mental Mutation 5 问

对**每个用户交互断言**，自问以下 5 个 mutation 是否会被测试捕获（基于 PIT/Stryker 最高 ROI 的 mutator）：

| # | Mutation 类型 | 自问内容 | 适用层级 |
|---|--------------|---------|---------|
| 1 | **No-op Mutation** | 把 handler 改为空函数 `() => {}`，测试还会通过吗？ | UI / CLI / API |
| 2 | **Conditional Flip** | 把 `if (X)` 改为 `if (!X)` 或 `if (true)`，测试会失败吗？ | 所有 |
| 3 | **Boundary Mutation** | 把 `===` 改为 `>=`、`<` 改为 `<=`，测试会失败吗？ | 数值 / 计数 |
| 4 | **Return-Value Mutation** | 把返回值改为 happy-path 默认值（`true` / `[]` / `null`），测试会失败吗？ | API / 函数 |
| 5 | **State-Update Skip** | 跳过 `setState` / `dispatch`，测试会失败吗？ | UI 状态 |

**最低要求**：每个用户交互后的断言必须能 kill **至少 No-op Mutation（#1）**。

---

## 4. 反模式清单（对应 case.txt 实证）

### Stable Element Assertion

**描述**：断言一个在页面初始加载时即存在的元素仍然可见，与交互是否生效无关。

```typescript
// ❌ 反模式
await page.locator('[data-testid="flower-target"]').click();
await expect(page.locator('[data-testid="flower-target"]').first()).toBeVisible();
// flower-target 在点击前已存在，No-op Mutation 无法被 kill
```

### Click Chain Without Mid-Asserts

**描述**：连续多次用户交互后只在最终检查一次状态，中间无任何断言验证每步交互是否生效。

```typescript
// ❌ 反模式
await page.locator('[data-testid="btn"]').click();
await page.waitForTimeout(150);
await page.locator('[data-testid="btn"]').click();
await page.waitForTimeout(150);
await page.locator('[data-testid="btn"]').click();
await page.waitForTimeout(3500);
await expect(page.locator('[data-testid="result"]')).toBeVisible();
// 3 次点击中任何一次成为 no-op，测试无法区分
```

### Timer-Only Wait

**描述**：用固定时长 `waitForTimeout(N)` 等待后，仅断言页面初始状态即满足的条件。

```typescript
// ❌ 反模式
await page.locator('[data-testid="submit"]').click();
await page.waitForTimeout(3500);
await expect(page.locator('[data-testid="form"]')).toBeVisible();
// form 在提交前已存在，等待 3.5s 后的断言仍是 stable element
```

---

## 5. 正模式清单

### Observable State Transition

**描述**：每次用户交互后，断言**仅由该交互产生**的可观察状态变化（aria-state / 计数 / 类名 / 文本内容）。

```typescript
// ✅ 正模式
const countBefore = await page.locator('[data-testid="flower-count"]').textContent();
await page.locator('[data-testid="flower-target"]').nth(0).click();
// 断言计数增加——No-op Mutation 必然 kill（未点击则计数不变）
await expect(page.locator('[data-testid="flower-count"]')).toHaveText(
  String(Number(countBefore) + 1)
);
// 或断言 aria 状态变化
await expect(page.locator('[data-testid="flower-target"]').nth(0))
  .toHaveAttribute('aria-pressed', 'true');
```

### State-Driven Wait

**描述**：用 `expect(...).toBeVisible({ timeout })` 等待状态出现，而非 `waitForTimeout` 后做弱断言。状态本身是因交互才产生的元素或文本。

```typescript
// ✅ 正模式
await page.locator('[data-testid="watering-can"]').click();
// 等待"浇水完成"提示——仅在点击且操作成功时出现
await expect(page.locator('[data-testid="watering-complete-toast"]'))
  .toBeVisible({ timeout: 5000 });
// 等待计数从 2 变为 3（状态驱动，非时间驱动）
await expect(page.locator('[data-testid="progress"]')).toHaveText('3/3');
```

### Negative Path Verification

**描述**：对"应该无副作用"的操作显式断言状态未发生变化，防止误操作被忽略。

```typescript
// ✅ 正模式（点击填充物 filler 不应触发进度）
await page.locator('[data-testid="filler-item"]').click();
await expect(page.locator('[data-testid="flower-count"]')).toHaveText('0');
// 显式断言计数未变——Conditional Flip / State-Update Skip 均可 kill
```

---

## 6. 审查侧检查清单

### plan-reviewer（维度 #8 触发时）

- [ ] 方案中每个"用户交互"步骤是否声明了 Observable State Transitions（可被外部观察的状态变化）？
- [ ] 验证方案是否仅有"通关"终态断言而无中间状态断言？（→ BLOCKER ≥91）
- [ ] E2E 场景的测试数据是否支持验证计数/状态变化？（初始值已知才能断言增量）

### qa-reviewer（Section C #4 触发时）

- [ ] 每次 `click()` / `fill()` / `submit()` 后是否至少有 1 个断言验证**仅由该交互产生**的状态变化？
- [ ] 最终断言的元素/属性是否**仅在功能正确时**才出现/匹配？
- [ ] `waitForTimeout(N)` 后的断言是否仅检查页面初始状态即满足的条件？

---

## 7. 适用边界（明确"不触发"场景）

1. **纯渲染测试**：`expect(page.locator('h1')).toHaveText('欢迎')` 无需 Mutation-Survival 自检，页面加载本身是行为。
2. **纯 API 契约测试**：`expect(response.status).toBe(200)` + `expect(body.userId).toBe(123)` — 无用户交互，断言即规范。
3. **纯函数单元测试**：`expect(add(1, 2)).toBe(3)` — 函数式断言天然 mutation-resistant。
4. **Negative testing（断言无变化）**：断言"点击无效按钮后计数仍为 0"本身已 kill No-op mutation，无需额外自检。

---

## 业界证据脚注

| 来源 | 结论 |
|------|------|
| **Coulman 2016** | 定义 Tautological Test：断言镜像实现而非独立行为，测试永远通过但没有保护价值 |
| **arXiv 2506.02954 MutGen (2026)** | 把 mutation 反馈写进 LLM prompt 显著提升 kill rate；74% LLM 测试失败根因是 oracle 质量问题 |
| **arXiv 2410.10628 (2024)** | LLM 生成测试中 Assertion Roulette 占 54.54%，Magic Number 占 99%；Tautological 断言是最常见 smell |
| **Meta 工程博客 (InfoQ 2026/01)** | Meta 将 mutation testing 用于 LLM 生成测试的合规门禁；约一半 LLM 测试无法 kill 任何 mutation |
| **Playwright 官方文档** | 推荐 web-first assertions（`toHaveText` / `toHaveAttribute`）优于 `toBeVisible()` on stable element；后者不验证状态变化 |
