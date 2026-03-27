# Phase: qa — 质量检查阶段

> 📋 读取状态文件后，本阶段重点关注 `## 设计文档` 的验证方案和 `## 红队验收测试` 区域。

## 目标
全面质量检查。不仅验证"能跑"，还验证"跑得好"。每项检查必须附上命令输出作为证据。

> ⚠️ 防合理化：See [references/anti-rationalization.md](references/anti-rationalization.md)

## 工作流程

分两波执行，最大化并行效率。每项检查产出 ✅/⚠️/❌ 状态。

### 前置：选择性重跑判断

检查 frontmatter `qa_scope` 字段：
- `"selective"` → 只重跑上轮失败 Tier + Tier 1.5，其余沿用
- 空/无 → 全量 QA
- 全部通过后清除 `qa_scope`

### 前置：变更分析

- `git diff`/`git status` 识别变更文件
- 分类：前端/后端/配置/测试/文档/样式/依赖
- 判断影响半径
- 扫描项目配置识别测试框架和工具

### Wave 1 — 命令执行（并行）

**在同一轮响应中发出多个 Bash 调用**：

**Tier 0: 红队验收测试**（最高优先级）
- 运行所有 `.acceptance.test` 文件
- 红队未生成测试时降级为 Wave 2 人工验证

**Tier 1: 基础验证**（四项并行）

| 验证项 | 条件 | 命令示例 | 超时 |
|--------|------|----------|------|
| 类型检查 | TS/Flow | `npx tsc --noEmit` | 60s |
| Lint | eslint/biome | `npx eslint src/` | 60s |
| 单元测试 | 有测试框架 | `npx jest --passWithNoTests` | 60s |
| 构建验证 | 影响构建 | `npm run build` | 60s |

**Tier 3: 集成验证**（条件性并行）
**Tier 4: 回归检查**（条件性，跨 3+ 文件时）

**执行原则**：失败不中断，标记后继续。记录命令、耗时、退出码、关键输出（前 50 行）。

### Wave 1 失败快速路径

Tier 0 + Tier 1 合计 ≥3 项 ❌ → 跳过 Wave 1.5/2，直接 QA 报告 + auto-fix。

### Wave 1.5 — 真实场景验证（必须执行）

**⚠️ 独立必做步骤。Wave 1 完毕后先完成 Wave 1.5，再启 Wave 2。**

#### 变更类型覆盖检查

| 核心变更类型 | 必须包含的场景类型 | 缺失处理 |
|-------------|-------------------|---------|
| UI 组件 | dev server + 渲染验证 | QA 补充 |
| API 端点 | `curl` 调用真实端点 | QA 补充 |
| CLI 工具/脚本 | 运行命令验证输出 | QA 补充 |
| 数据库变更 | 查询验证数据状态 | QA 补充 |

**Tier 1.5: 真实场景验证（Smoke Test）**
- 从设计文档 `## 验证方案 > 真实测试场景` 读取场景列表
- `[独立]` 标记的场景可并行，未标记的串行
- 每个场景必须记录 `执行:` + `输出:`
- **不可跳过**：无场景时 QA 自行设计至少 1 个
- 超时：单场景 60s，总计 180s

| 场景类型 | 真实测试示例 |
|----------|-------------|
| CLI 工具 | 运行命令，验证输出和退出码 |
| Hook 脚本 | 模拟 stdin 运行脚本 |
| API 端点 | `curl` 调用 |
| UI 组件 | dev server + 页面访问 |
| 库函数 | 临时脚本调用 |
| 配置变更 | 变更后配置启动服务 |

> **教训**：little-bee-cli 48 个测试全通过但 4 个 bug 靠手动发现。根因：设计了 3 个场景但只执行了 --help。

### Wave 2 — AI 审查（并行 Agent）

**在同一轮响应中启动两个并行审查 Agent**：

#### Tier 2a: design-reviewer Agent
prompt 参考 `references/design-reviewer-prompt.md`，填入设计文档 + Wave 结果摘要 + 项目路径。
**核心**：不信任，独立验证。

#### Tier 2b: code-quality-reviewer Agent
prompt 参考 `references/code-quality-reviewer-prompt.md`，填入项目路径 + 项目约定 + Wave 结果摘要。
**核心**：置信度 ≥80 才报告。按 `references/review-checklist.md` 审查。

#### 合流
收集两 Agent 产出，合并为 QA 报告 Tier 2a/2b 部分。

**降级**：单 Agent 失败不阻塞；双失败编排器自行简化审查。

### 产出报告
追加到状态文件 `## QA 报告`。格式参见 `references/qa-report-template.md`。

### 结果判定

**前置检查**：
1. **场景计数匹配**：Tier 1.5 `执行:` 数量 E vs 设计文档场景总数 N。E < N → 补做。
2. **格式检查**：每场景有 `执行:` + `输出:`。纯描述 → 补做。

- 全 ✅（可有 ⚠️）→ `gate: "review-accept"`
- 有 ❌ → `phase: "auto-fix"`，列出需修复项

### 改进建议
QA 失败集中在基础设施缺失时：
> 💡 建议运行 `/autopilot doctor` 改进工程基础设施。
