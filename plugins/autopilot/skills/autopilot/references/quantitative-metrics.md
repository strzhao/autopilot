# Tier 5 量化指标门禁参考手册

> **业界对齐命名**：本文件使用业界标准术语 `mutation score / kill rate / survived mutant / coverage / threshold`，不自创术语。
>
> **引用基准**：
> - **Meta FSE 2025**：mutation-targeted 测试改进 LLM kill rate 32% vs coverage-targeted 5.3%；约 50% LLM 生成测试无法 kill 任何 mutation。
> - **Stryker** (JavaScript/TypeScript)：业界主流 mutation 测试框架，默认 `high: 80 / low: 60 / break: 50`。
> - **Istanbul / c8 / nyc**：业界主流 coverage 工具链，前端项目 mid-tier 基准 line ≥ 80% / branch ≥ 70%。

---

## 1. 阈值常量声明

> **修改阈值时单点改动**。OC-2 契约 grep 正则锚定如下三行字面。

mutation_threshold: 60
coverage_line_threshold: 80
coverage_branch_threshold: 70

---

## 2. 工具检测函数 `detect_quantitative_tools()`

**目的**：在 QA Wave 1 前判定 Tier 5 是否触发（按子项独立触发，缺一仍跑另一项）。

**检测项**（package.json 依赖 + config 文件存在）：

| 工具 | 依赖名 | Config 文件 |
|------|--------|-------------|
| stryker | `@stryker-mutator/core` | `stryker.conf.{js,json,cjs,mjs}` |
| c8 | `c8` | `.c8rc*` / package.json `c8` 字段 |
| nyc | `nyc` | `.nycrc*` / package.json `nyc` 字段 |
| jest_coverage | `jest` | `jest --coverage` script 或 jest.config 含 `collectCoverage` |

**返回**：JSON `{stryker: bool, c8: bool, nyc: bool, jest_coverage: bool}`

---

## 3. Tier 5 触发条件 / 执行命令 / 超时

**触发条件**（任一子项独立触发）：
- mutation 子项：`stryker.conf.*` 存在 或 `@stryker-mutator/core` 在依赖中
- coverage 子项：`c8` / `nyc` / `istanbul` 在依赖中，或 jest 配置含 coverage

**执行命令**（按检测到的工具自适应）：

| 工具 | 命令 | 输出解析 |
|------|------|---------|
| Stryker | `npx stryker run --reporters json` | `reports/mutation/mutation.json` → `metrics.killed / metrics.totalValid` |
| c8 | `npx c8 --reporter=json npm test` | `coverage/coverage-summary.json` |
| jest --coverage | `npx jest --coverage --coverageReporters=json-summary` | `coverage/coverage-summary.json` |

**超时**：
- mutation: 600s (10 min)
- coverage: 120s

---

## 4. tier5-report.json Schema（OC-4 契约）

```json
{
  "tier5_status": "pass" | "fail" | "na" | "skipped",
  "mutation": {
    "tool": "stryker" | "pit" | "mutmut" | null,
    "kill_rate": number | null,
    "killed": number,
    "total_valid": number,
    "threshold": 60,
    "survived_mutants": [
      {"file": "...", "line": 0, "mutator": "...", "original": "...", "mutated": "..."}
    ],
    "passed": "bool"
  },
  "coverage": {
    "tool": "c8" | "nyc" | "istanbul" | "jest" | null,
    "line": number | null,
    "branch": number | null,
    "function": number | null,
    "thresholds": {"line": 80, "branch": 70},
    "uncovered_critical": [
      {"file": "...", "line": 0, "branch": 0}
    ],
    "passed": "bool"
  },
  "blocker": "bool",
  "warning": "bool"
}
```

### 双向语义对偶（防"设计文档单方向语义"反模式）

| 端 | 行为 |
|----|------|
| **生成端** | Tier 5 跑工具 → 产出 `tier5-report.json` |
| **消费端** | auto-fix 从 `survived_mutants[]` 与 `uncovered_critical[]` 取改进目标；qa-reviewer Section A 与本数字对照，禁止主观 tautological 估算 |

### 反向约束（不变量）

- `tier5_status != "pass"` ⟹ `survived_mutants[]` 非空 OR `uncovered_critical[]` 非空（否则属格式错误）
- **双子项 null 不变量**：`(mutation.tool == null && coverage.tool == null) ⟹ tier5_status == "na"`

---

## 5. 降级矩阵（4 状态）

| 状态 | mutation.tool | coverage.tool | tier5_status | blocker | warning |
|------|---------------|---------------|--------------|---------|---------|
| both | 非 null | 非 null | pass/fail（按 passed 综合） | fail 时 true | false |
| mutation-only | 非 null | null | 按 mutation.passed 定 | fail 时 true | true（缺 coverage） |
| coverage-only | null | 非 null | 按 coverage.passed 定 | fail 时 true | true（缺 mutation） |
| na | null | null | "na" | false | true |

**Wave 1 失败快速路径计数**：Tier 5 ❌ 与 Tier 0/1 ❌ 同权重计数（Tier 0+1+5 ≥3 → 跳过 Wave 1.5/2 直接 auto-fix）。

**Tier 5 ❌ 不可 ⚠️ 复盘绕过**（与 Tier 3.5 ⚠️ 不阻塞模式不同）：数字达不到阈值 → ❌ → auto-fix。

---

## 6. smoke 模式跳过路径（OC-5 / IMP-2 补丁）

`qa_scope: "smoke"`（fast_mode 自动检测或显式声明）→ 主动跳过 Tier 5：

```json
{
  "tier5_status": "skipped",
  "warning": false,
  "blocker": false
}
```

**与 N/A 区分**：`skipped` = 主动不跑（fast/smoke 模式选择），`na` = 项目无工具（被动无法跑）。

---

## 7. 工具不可用时降级清单

两子项均检测不到 → `tier5_status: "na"` + `warning: true` + `blocker: false`。

**na 必须可见不得静默放行**（见 [2026-05-31] 静默放行反模式）：
QA 报告必须显式渲染"⚠️ 测试有效性维度未验证（无 mutation/coverage 工具）"，该标注不得含"PASS"/"绿灯"/"通过"字样。na 不等于 PASS，是"无法求值"。

**doctor-report.md 必须输出字面安装命令**：

```bash
npm install --save-dev @stryker-mutator/core @stryker-mutator/jest-runner c8
```

工具完全缺位时，回退到 prompt 层降级清单（`references/test-mutation-survival.md`）：
- 5 类 mutator 名称：No-op / Conditional Flip / Boundary / Return-Value / State-Update Skip
- Tautological Test 反模式识别（Coulman 2016）
- Mutation-Survival 自检铁律（兜底，不可删）

> **重要**：降级清单是兜底，Tier 5 工具量化门禁是主路径。AI 主观自检比客观工具数字弱一个数量级。

---

## 8. coverage 反向否决语义

**覆盖率达标不作通过/绿灯信号**（Inozemtseva ICSE 2014：高覆盖不预示高检错率）。

coverage 的唯一判定用途：`uncovered_critical[]` 非空时**反向否决**（改动行有未覆盖路径 → ❌ 阻塞）。
覆盖率达标（line ≥ 80%、branch ≥ 70%）仅表示"未进入反向否决条件"，不可据此输出 PASS 或绿灯标记。

---

## 业界证据脚注

| 来源 | 结论 |
|------|------|
| **Meta FSE 2025** | mutation-targeted 32% vs coverage-targeted 5.3%；约 50% LLM 测试无法 kill 任何 mutation |
| **Stryker 官方默认** | high: 80 / low: 60 / break: 50；break 之下 CI fail |
| **Istanbul / c8** | 业界主流前端 coverage 工具；JSON summary schema 稳定 |
| **arXiv 2506.02954 MutGen** | mutation 反馈写入 LLM prompt 显著提升 kill rate；74% LLM 测试失败根因是 oracle 质量 |
