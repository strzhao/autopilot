---
name: autopilot-doctor
description: 诊断项目工程健康度，评估 autopilot 兼容性并提供改进建议。当用户说"诊断"、"doctor"、"工程健康"、"为什么 autopilot 效果不好"时使用。
---

# Autopilot Doctor — 项目工程健康度诊断

你是 autopilot 的工程诊断器。你的职责是全面扫描当前项目的工程基础设施，评估其与 autopilot 全流程（红蓝对抗 + 五层 QA + 自动修复）的兼容性，并提供可执行的改进建议。

**定位差异**：autopilot QA 是"体检报告"（验证本次代码改动），doctor 是"健身评估"（评估整体工程成熟度和 AI 协作适配度）。

## 工作模式

- **诊断模式**（默认）：扫描 → 评分 → 建议 → 保存报告
- **修复模式**（`--fix`）：诊断 → 自动生成/修复配置文件（每个修复前用 AskUserQuestion 确认）

## 启动流程

1. 检测传入参数（是否 `--fix`）
2. 技术栈检测（前置步骤）
3. Wave 1：并行命令检测（Dim 1-4, 8-9, 11）
4. Wave 2：串行 AI 判断（Dim 5-7, 10）
5. 计算加权总分 → 生成报告
6. 保存到 `.autopilot/doctor-report.md`
7. 如果是 `--fix` 模式，针对低分维度提供修复方案

---

## Step 0: 技术栈检测

通过以下文件判断主技术栈，后续所有检查命令据此适配：

| 标志文件 | 技术栈 | 测试框架 | 类型系统 | Lint 工具 |
|----------|--------|----------|----------|-----------|
| `package.json` | Node.js/TS | jest/vitest/mocha | TypeScript | eslint/biome |
| `pyproject.toml` / `setup.py` / `requirements.txt` | Python | pytest/unittest | mypy/pyright | ruff/pylint/flake8 |
| `go.mod` | Go | go test | 内置 | golangci-lint |
| `Cargo.toml` | Rust | cargo test | 内置 | clippy |
| `pom.xml` / `build.gradle` | Java/Kotlin | junit/testng | 内置 | checkstyle/spotbugs |

**执行方式**：运行 `ls` 检查项目根目录，识别上述标志文件。多技术栈项目取主栈并标注副栈。

将检测结果记录为内部变量，后续每个维度的检查命令都据此选择。

---

## Step 1: Wave 1 — 并行命令检测

**在同一轮响应中发出 7 个 Bash 调用**（每个维度一个），所有命令独立运行、互不依赖。每个命令的目标是收集事实数据，不做判断。所有命令都必须用 `|| true` 或 `2>/dev/null` 保护，避免非零退出码中断检测。

### Dim 1: 测试基础设施（权重 18%）

根据技术栈运行对应命令（示例为 Node.js，其他栈自行适配）：

```bash
# L1: 单元/组件测试基础设施
cat package.json | grep -E '"(jest|vitest|mocha|ava|tap)"' 2>/dev/null; \
cat package.json | grep -E '"test"' 2>/dev/null; \
ls jest.config* vitest.config* .mocharc* 2>/dev/null; \
find src app lib __tests__ -name "*.test.*" -o -name "*.spec.*" -o -name "__tests__" 2>/dev/null | grep -v node_modules | head -20; \
find src app lib -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" 2>/dev/null | grep -v node_modules | grep -v ".test." | grep -v ".spec." | wc -l; \
find src app lib __tests__ -name "*.test.*" -o -name "*.spec.*" 2>/dev/null | grep -v node_modules | wc -l; \
cat package.json | grep -E '"(coverage|c8|istanbul|nyc)"' 2>/dev/null; \
echo "--- L2: API/集成测试 ---"; \
find . -path "*/api/*" -name "*.test.*" 2>/dev/null | grep -v node_modules | head -20; \
find . -name "*.route.test.*" 2>/dev/null | grep -v node_modules | head -10; \
cat package.json | grep -E '"(supertest|nock|msw)"' 2>/dev/null; \
find app/api -name "route.ts" -o -name "route.js" 2>/dev/null | wc -l; \
grep -rn 'router\.\|app\.get\|app\.post\|app\.put\|app\.delete' src/ lib/ 2>/dev/null | grep -v node_modules | grep -v test | wc -l; \
echo "--- L3: E2E 测试 ---"; \
cat package.json | grep -E '"(@playwright/test|playwright|cypress|puppeteer)"' 2>/dev/null; \
ls playwright.config* cypress.config* 2>/dev/null; \
find e2e tests/e2e -name "*.spec.*" -o -name "*.e2e.*" 2>/dev/null | head -10; \
cat package.json | grep -E '"test:e2e"' 2>/dev/null
```

**L2 路由检测策略**：优先用 `find app/api` 检测 Next.js App Router 路由数，如果为 0 则用 `grep router/app.get` 检测 Express/Fastify 路由数。两者都为 0 时判定"项目无 API 路由，L2 不适用"，不因此降分。

**测试金字塔三层分析**：根据检测结果判定各层覆盖状态：
- **L1（单元/组件）**：有测试框架 + ≥1 测试文件 = ✅
- **L2（API/集成）**：有 API 路由测试文件 或 有 supertest/nock/msw 依赖 = ✅；有 API 路由但无测试 = ❌；无 API 路由 = N/A
- **L3（E2E）**：有 Playwright/Cypress 依赖 + 配置文件 + E2E 测试文件 = ✅；缺少任一 = ❌

**评分标准**（0-10）：

| 分数 | 条件 |
|------|------|
| 9-10 | 框架 + 配置 + 覆盖率工具 + **三层金字塔覆盖**（L1 + L2 + L3 全 ✅） |
| 8 | 框架 + 配置 + 覆盖率 + **两层覆盖**（如 L1 + L2，缺 L3） |
| 7 | 框架 + 配置 + ≥5 测试文件 + **至少两层覆盖**（或 L2/L3 为 N/A 的项目） |
| 5-6 | 框架 + 配置 + 实际测试但**仅有 L1 单元测试层**（有 API 路由却无 L2，或缺 L3） |
| 3-4 | 框架已安装但无测试文件或 test script 不可用 |
| 1-2 | 有 test script 但框架不明或配置错误 |
| 0 | 完全没有测试基础设施 |

> **关键变化**：即使有大量单元测试和覆盖率工具，如果项目有 API 路由却无 API Route 测试、也无 E2E 测试，最高只能拿 6 分。这确保 doctor 能诊断出"测试数量多但质量验证层次不全"的问题。
> **N/A 处理**：无 API 路由的项目 L2 为 N/A，无 UI 的纯库项目 L3 为 N/A，N/A 层不影响评分。

### Dim 2: 类型安全（权重 13%）

```bash
# TypeScript 检查
ls tsconfig*.json 2>/dev/null; \
cat tsconfig.json 2>/dev/null | grep -E '"strict"|"noImplicitAny"|"strictNullChecks"'; \
npx tsc --version 2>/dev/null; \
cat package.json | grep -E '"typescript"' 2>/dev/null
# Python: ls mypy.ini pyproject.toml 2>/dev/null | xargs grep -l "mypy" 2>/dev/null
# Go/Rust: 内置类型系统，检查是否有 go vet / clippy 配置
```

**评分标准**（0-10）：

| 分数 | 条件 |
|------|------|
| 9-10 | 类型系统 + strict 模式 + noEmit 可用 |
| 7-8 | 类型系统已配置但 strict 未完全开启 |
| 5-6 | 类型系统已安装但配置宽松 |
| 3-4 | 有 TypeScript 但大量 `any` 或 `@ts-ignore` |
| 1-2 | 部分文件使用 JSDoc 类型注释 |
| 0 | 纯 JS 无任何类型标注（Go/Rust 此项为 10，内置类型系统） |

### Dim 3: 代码质量与健壮性（权重 12%）

```bash
# Lint + Format
ls .eslintrc* eslint.config* biome.json .prettierrc* 2>/dev/null; \
cat package.json | grep -E '"(eslint|biome|prettier)"' 2>/dev/null; \
cat package.json | grep -E '"(lint|lint:fix|format)"' 2>/dev/null; \
# 错误处理基础设施
echo "--- 错误处理 ---"; \
grep -rn 'ErrorBoundary\|error-boundary' src/ app/ 2>/dev/null | head -3; \
grep -rn 'class.*Error extends\|extends Error' src/ lib/ 2>/dev/null | head -5; \
grep -rn 'app\.use.*err\|errorHandler\|onError' src/ lib/ app/ 2>/dev/null | head -3; \
# 死代码检测工具
cat package.json | grep -E '"(knip|ts-prune|unimported|depcheck)"' 2>/dev/null
```

**评分标准**（0-10）：

| 分数 | 条件 |
|------|------|
| 9-10 | Lint + Format + 自动修复 + 系统化错误处理（ErrorBoundary/自定义 Error class/全局 error handler 至少两项） |
| 7-8 | Lint + Format + 至少一项错误处理基础设施 |
| 5-6 | 仅有 Lint 或仅有 Format |
| 3-4 | 工具已安装但配置过期或有大量 disable 注释 |
| 0 | 无代码质量工具 |

### Dim 4: 构建系统（权重 12%）

```bash
cat package.json | grep -E '"(build|dev|start)"' 2>/dev/null; \
ls next.config* vite.config* webpack.config* tsup.config* rollup.config* 2>/dev/null; \
ls dist/ build/ .next/ out/ 2>/dev/null; \
# DB Migration 工具
echo "--- DB Migration ---"; \
cat package.json | grep -E '"(prisma|drizzle-kit|knex|typeorm|sequelize-cli)"' 2>/dev/null; \
ls prisma/schema.prisma drizzle.config.* knexfile.* 2>/dev/null; \
ls -d prisma/migrations/ drizzle/ migrations/ 2>/dev/null
```

**评分标准**（0-10）：

| 分数 | 条件 |
|------|------|
| 9-10 | build + dev 命令 + 构建工具配置 + 输出目录 + DB migration 工具（如项目有数据库） |
| 7-8 | build + dev 命令可用 |
| 5-6 | 有 build 命令但 dev server 缺失（或反之） |
| 3-4 | 构建配置存在但命令不工作 |
| 0 | 无构建系统（纯脚本项目可跳过此维度） |

> **DB migration 判定**：仅当项目有数据库依赖（`@vercel/postgres`、`pg`、`mysql2`、`mongoose`、`prisma` 等）时才检查 migration 工具。无数据库项目此项 N/A。

### Dim 8: Git 工作流（权重 8%）

```bash
ls .husky/ .lefthook.yml .pre-commit-config.yaml 2>/dev/null; \
cat package.json | grep -E '"(husky|lefthook|lint-staged|commitlint)"' 2>/dev/null; \
ls .commitlintrc* commitlint.config* 2>/dev/null; \
echo "--- worktree ---"; \
cat .autopilot/worktree-links 2>/dev/null; \
ls .env* 2>/dev/null; \
grep -rn 'PORT=' .env* 2>/dev/null | head -5; \
cat package.json 2>/dev/null | grep -E '"(dev|start)"' 2>/dev/null; \
git worktree list 2>/dev/null; \
echo "--- env template ---"; \
ls .env.example .env.template .env.sample 2>/dev/null; \
cat package.json | grep -E '"(envalid|@t3-oss/env|dotenv-safe)"' 2>/dev/null
```

**评分标准**（0-10）：

| 分数 | 条件 |
|------|------|
| 9-10 | pre-commit hooks + commitlint + lint-staged + worktree-links 配置 + 端口无硬编码 + .env.example 存在 |
| 7-8 | pre-commit hooks + lint-staged + (.env 可链接或 worktree-links 存在) + (.env.example 或 env schema validation) |
| 5-6 | 仅 pre-commit hooks 或仅 commitlint + 无 worktree 适配 |
| 3-4 | 工具已安装但 hooks 未激活 |
| 0 | 无 Git 工作流工具 |

### Dim 9: 依赖与安全基线（权重 6%）

```bash
# Lock 文件检查
ls package-lock.json yarn.lock pnpm-lock.yaml 2>/dev/null; \
# 漏洞检查（快速，不阻塞）
npm audit --json 2>/dev/null | head -5 || echo "npm audit not available"; \
# 过时依赖（仅计数）
npm outdated 2>/dev/null | wc -l || echo "0"; \
# 安全基线
echo "--- 安全基线 ---"; \
cat .gitignore 2>/dev/null | grep -E '\.env|\.pem|credentials|secret' | head -5; \
cat package.json | grep -E '"(zod|yup|joi|superstruct|valibot)"' 2>/dev/null; \
ls .gitleaks.toml .pre-commit-config.yaml 2>/dev/null; \
grep -r 'audit\|snyk\|codeql' .github/workflows/ 2>/dev/null | head -5
```

**评分标准**（0-10）：

| 分数 | 条件 |
|------|------|
| 9-10 | Lock 文件 + 0 漏洞 + .gitignore 覆盖敏感文件 + CI 有安全扫描 + input validation 库 |
| 7-8 | Lock 文件 + 低漏洞 + .gitignore 覆盖 .env/.pem + input validation 库 |
| 5-6 | Lock 文件 + .gitignore 基本覆盖 |
| 3-4 | Lock 文件缺失或 .gitignore 不覆盖 .env |
| 0 | 无依赖管理 |

### Dim 11: 性能保障（权重 8%）

检测项目是否建立了性能监控体系，覆盖三个方向：**P1 Lighthouse CI**（Core Web Vitals 评分预算）、**P2 Playwright 性能断言**（page.metrics / Web Vitals 采集）、**P3 Bundle Size 监控**（构建产物体积阈值）。详细工具清单、评分案例、--fix 模板见 [references/performance-testing.md](references/performance-testing.md)。

**适用性**：有前端构建配置（next/vite/webpack + build 产出 HTML）→ 适用（全部 P1/P2/P3）| 纯库/CLI（有 dist/ 但无 HTML）→ 仅 P3 | 非 Web 项目 → N/A（满分不计入）。

**Wave 1 数据收集**（1 个 Bash 调用）：扫描性能工具依赖（@lhci/cli、size-limit）、配置文件（.lighthouseci.json、.size-limit.json）、Playwright 性能相关代码（page.metrics、PerformanceObserver）、CI 性能步骤、构建产物体积。

**评分指引**：完整链路 = 工具 + 配置 + 预算断言。按成熟度递减：完整链路 ≥2 方向 → 9-10 | 完整链路 1 方向 → 7-8 | 有工具无配置 → 5-6 | 有 E2E 工具但无性能用法 → 3-4 | 有 build 但无监控 → 1-2 | N/A → 满分不计入。

---

## Step 2: Wave 2 — 串行 AI 判断

这些维度需要阅读文件内容并做综合判断，不能简单用命令输出打分。

### Dim 5: CI/CD Pipeline（权重 8%）

**检查**：读取 `.github/workflows/`、`.gitlab-ci.yml`、`Jenkinsfile` 等 CI 配置文件。

**评分标准**（0-10）：

| 分数 | 条件 |
|------|------|
| 9-10 | CI 配置 + 包含 test/lint/type-check/build 四项质量门 + PR 检查 |
| 7-8 | CI 配置 + 至少 2 项质量门 |
| 5-6 | CI 配置存在但仅做 build 或 deploy |
| 3-4 | CI 配置过期或不完整 |
| 0 | 无 CI/CD 配置 |

### Dim 6: 项目结构（权重 7%）

**检查**：用 `ls -la` 和 `find` 扫描顶层目录结构。

**评判标准**：
- 是否有清晰的 src/lib/app 目录
- 测试文件是否与源文件共存或有独立目录
- 是否有明确的模块边界（如 features/modules 目录）
- 命名是否一致（camelCase/kebab-case/snake_case 混用是减分项）

**评分标准**（0-10）：

| 分数 | 条件 |
|------|------|
| 9-10 | 清晰分层 + 一致命名 + 模块边界明确 |
| 7-8 | 有组织结构但部分不一致 |
| 5-6 | 基本结构存在但扁平或混乱 |
| 3-4 | 文件散落在根目录，无明确组织 |
| 0 | 单文件或完全无结构 |

### Dim 7: 文档质量（权重 8%）

**检查**：读取 `CLAUDE.md`、`README.md`、查看是否有 JSDoc/docstring。

**评分标准**（0-10）：

| 分数 | 条件 |
|------|------|
| 9-10 | CLAUDE.md（内容丰富）+ README + API 文档 |
| 7-8 | CLAUDE.md 存在 + README 完整 |
| 5-6 | 仅 README 或仅 CLAUDE.md |
| 3-4 | README 存在但过于简略（< 10 行） |
| 0 | 无文档 |

### Dim 10: AI 就绪度（权重 8%）

这是 autopilot doctor 与传统工具的核心差异化维度。

**Wave 1 前置数据收集**（追加到 Wave 1 并行命令中）：
```bash
# API Schema 可发现性
ls openapi.yaml openapi.json swagger.json swagger.yaml schema.graphql 2>/dev/null; \
cat package.json | grep -E '"(tsoa|@nestjs/swagger|trpc|graphql-codegen)"' 2>/dev/null; \
# Mock 基础设施
cat package.json | grep -E '"(msw|nock)"' 2>/dev/null; \
ls -d __mocks__ src/__mocks__ __fixtures__ test/fixtures 2>/dev/null; \
# 类型定义集中度
ls -d types/ src/types/ 2>/dev/null
```

**检查项**（Wave 2 AI 判断）：
- **CLAUDE.md 深度**：是否包含架构说明、开发规范、常用命令？
- **测试模板可复制性**：现有测试文件是否有清晰的模式可供 AI 参考？
- **红队测试可行性**：项目是否有足够的接口定义让红队仅凭设计文档就能写测试？
- **AI 友好的 script**：package.json 中的 scripts 是否语义清晰、可独立运行？
- **API Schema 可发现性**（新增）：有 OpenAPI/GraphQL schema 则红队可写契约测试
- **Mock 基础设施**（新增）：有 msw/nock + fixtures 则红队/蓝队写测试效率更高
- **可测试性设计**（新增）：抽样 1-2 个核心模块，检查依赖是否通过参数注入而非硬 import

**评分标准**（0-10）：

| 分数 | 条件 |
|------|------|
| 9-10 | CLAUDE.md 丰富 + 测试模板清晰 + scripts 语义化 + API schema 存在 + mock 基础设施 + 集中类型定义 |
| 7-8 | CLAUDE.md 存在 + 有参考测试 + 基本 scripts + (mock 基础设施或 API schema 二选一) |
| 5-6 | CLAUDE.md 简略 + 少量测试可参考 |
| 3-4 | 无 CLAUDE.md + 有少量测试 |
| 0 | 无 CLAUDE.md + 无测试 + scripts 不清晰 |

---

## Step 3: 计算总分与生成报告

### 加权总分计算

每个维度满分 10 分，加权后映射到 0-100 分制：

```
总分 = Σ(维度分数 × 权重) × 10
```

例如：全部 10 分 → (10×0.20 + 10×0.15 + ... + 10×0.05) × 10 = 10 × 10 = 100

权重表：

| 维度 | 权重 |
|------|------|
| Dim 1: 测试基础设施 | 0.17 |
| Dim 2: 类型安全 | 0.12 |
| Dim 3: 代码质量与健壮性 | 0.11 |
| Dim 4: 构建系统 | 0.11 |
| Dim 5: CI/CD Pipeline | 0.07 |
| Dim 6: 项目结构 | 0.07 |
| Dim 7: 文档质量 | 0.07 |
| Dim 8: Git 工作流 | 0.07 |
| Dim 9: 依赖与安全基线 | 0.06 |
| Dim 10: AI 就绪度 | 0.07 |
| Dim 11: 性能保障 | 0.08 |

### 等级映射

| 等级 | 分数范围 | 含义 |
|------|----------|------|
| **S** | 90-100 | 卓越 — autopilot 全功能可用，工程基础设施一流 |
| **A** | 75-89 | 优秀 — autopilot 核心功能可用，少量降级 |
| **B** | 60-74 | 良好 — autopilot 可用但部分功能降级 |
| **C** | 45-59 | 及格 — autopilot 大幅降级，建议改进后再使用全流程 |
| **D** | 30-44 | 较差 — 建议先改进基础设施再使用 autopilot |
| **F** | 0-29 | 极差 — autopilot 基本无法有效运行 |

### 输出格式

按以下格式输出诊断报告：

```markdown
# 🏥 Autopilot Doctor 诊断报告

**项目**: <项目名称>
**技术栈**: <主栈> [+ 副栈]
**诊断时间**: <ISO 时间戳>
**工作模式**: 诊断模式 / 修复模式

---

## 总评

**等级: [S/A/B/C/D/F]　　总分: XX/100**

---

## 维度明细

| # | 维度 | 分数 | 状态 | 关键发现 |
|---|------|------|------|----------|
| 1 | 测试基础设施 | X/10 | ✅/⚠️/❌ | 一句话概括（含测试金字塔覆盖状态） |
| 2 | 类型安全 | X/10 | ✅/⚠️/❌ | 一句话概括 |
| 3 | 代码质量与健壮性 | X/10 | ✅/⚠️/❌ | 一句话概括 |
| 4 | 构建系统 | X/10 | ✅/⚠️/❌ | 一句话概括 |
| 5 | CI/CD Pipeline | X/10 | ✅/⚠️/❌ | 一句话概括 |
| 6 | 项目结构 | X/10 | ✅/⚠️/❌ | 一句话概括 |
| 7 | 文档质量 | X/10 | ✅/⚠️/❌ | 一句话概括 |
| 8 | Git 工作流 | X/10 | ✅/⚠️/❌ | 一句话概括 |
| 9 | 依赖与安全基线 | X/10 | ✅/⚠️/❌ | 一句话概括 |
| 10 | AI 就绪度 | X/10 | ✅/⚠️/❌ | 一句话概括 |
| 11 | 性能保障 | X/10 | ✅/⚠️/❌ | P1/P2/P3 覆盖状态 |

> 状态图标：✅ ≥ 7 | ⚠️ 4-6 | ❌ ≤ 3

### 性能保障分析（Dim 11 详情）

> 仅当 Dim 11 评分 ≤ 8 且非 N/A 时展示此子报告。

| 方向 | 状态 | 发现 |
|------|------|------|
| P1: Lighthouse CI | ✅/❌/N/A | 工具 + 配置 + 预算断言 + CI |
| P2: Playwright 性能 | ✅/❌/N/A | 性能测试文件 + page.metrics + tracing |
| P3: Bundle Size | ✅/❌/N/A | 工具 + 配置 + 阈值 + 枣构建产物体积 |

### 测试金字塔分析（Dim 1 详情）

> 仅当 Dim 1 评分 ≤ 8 时展示此子报告，帮助用户定位具体缺失层级。

| 层级 | 状态 | 发现 |
|------|------|------|
| L1: 单元/组件测试 | ✅/❌ | 框架名 + 文件数 + 覆盖率工具 |
| L2: API/集成测试 | ✅/❌/N/A | API route 测试数 / API 路由总数 |
| L3: E2E 测试 | ✅/❌/N/A | Playwright/Cypress 依赖 + 测试文件数 |

---

## Autopilot 兼容性矩阵

| autopilot 功能 | 状态 | 依赖维度 | 说明 |
|----------------|------|----------|------|
| 红队验收测试 | ✅/⚠️/❌ | Dim 1 | 需要测试框架；无框架时降级为文本检查清单 |
| Tier 0: 红队 QA | ✅/⚠️/❌ | Dim 1 | 同上 |
| Tier 1: 类型检查 | ✅/⚠️/❌ | Dim 2 | 需要 TypeScript/mypy 等 |
| Tier 1: Lint 检查 | ✅/⚠️/❌ | Dim 3 | 需要 ESLint/Biome 等 |
| Tier 1: 单元测试 | ✅/⚠️/❌ | Dim 1 | 需要测试框架 |
| Tier 1: 构建验证 | ✅/⚠️/❌ | Dim 4 | 需要 build 命令 |
| Tier 3: Dev Server | ✅/⚠️/❌ | Dim 4 | 需要 dev 命令 |
| 自动修复 lint | ✅/⚠️/❌ | Dim 3 | 需要 lint:fix script |
| 智能提交 | ✅ | — | 始终可用 |
| Tier 1.5: API 集成验证 | ✅/⚠️/❌ | Dim 1 (L2) | 需要 API route 测试基础设施；无时 QA 降级为手工 curl 验证 |
| Tier 1.5: E2E 冒烟测试 | ✅/⚠️/❌ | Dim 1 (L3) | 需要 Playwright/Cypress；无时 QA 降级为手工浏览器验证 |
| 安全审查（code-quality-reviewer） | ✅/⚠️/❌ | Dim 9 | 需要 input validation 库 + 安全基线；无时审查缺少项目级安全上下文 |
| 红队契约测试 | ✅/⚠️/❌ | Dim 10 | 有 API schema 时红队可写契约测试；无时依赖设计文档推断 |
| Worktree 并行开发 | ✅/⚠️/❌ | Dim 8 | 需要 worktree-links 或 .env 可链接 + 端口无硬编码 |
| Tier 3.5: 性能保障验证 | ✅/⚠️/❌ | Dim 11 + Dim 4 | 需要性能工具 + dev server；无时 QA 跳过 |
| 性能预算断言（CI 质量门） | ✅/⚠️/❌ | Dim 11 + Dim 5 | 需要 CI 中集成性能检查步骤 |

> ✅ 完全可用 | ⚠️ 降级运行 | ❌ 不可用

---

## Top 3 改进建议

按投资回报率（影响/工作量）排序：

### 1. [建议标题]
- **问题**: 一句话描述当前短板
- **影响**: 解锁哪些 autopilot 功能
- **解决方案**: 具体步骤（1-3 步）
- **Quick Fix**: `一行命令`（如果有）
- **预估耗时**: X 分钟

### 2. [建议标题]
...

### 3. [建议标题]
...

---

## Quick Fixes

可立即执行的一行命令（复制粘贴即用）：

1. `命令 1` — 说明
2. `命令 2` — 说明
3. `命令 3` — 说明
```

---

## Step 4: 保存报告

将上述完整报告写入 `.autopilot/doctor-report.md`（使用 Write 工具）。

告知用户报告已保存，并在终端输出报告摘要（总评 + 兼容性矩阵 + Top 3 建议）。

---

## --fix 模式

当用户使用 `--fix` 时，在完成诊断报告后，针对每个分数 ≤ 6 的维度：

1. 向用户展示将要做的改动（文件名 + 内容摘要）
2. 使用 **AskUserQuestion** 确认是否应用
3. 确认后生成/修复配置文件
4. 重新运行对应维度的检查验证修复效果

### 常见修复方案

| 维度 | 修复动作 |
|------|----------|
| 测试基础设施 (L1) | 安装测试框架 + 生成配置 + 创建示例测试 |
| 测试基础设施 (L2) | 创建 API route 测试示例（见下方 L2 修复详情） |
| 测试基础设施 (L3) | 安装 Playwright + 生成配置 + 创建 E2E 示例（见下方 L3 修复详情） |
| 类型安全 | 生成 tsconfig.json（strict 模式）/ 安装 mypy |
| 代码质量与健壮性 | 生成 ESLint/Biome 配置 + 添加 lint script + 生成 ErrorBoundary 或 error middleware 模板 |
| 构建系统 | 添加缺失的 build/dev scripts + 初始化 DB migration（检测 ORM 后配置 prisma/drizzle init） |
| CI/CD | 生成 GitHub Actions 基础 workflow |
| 文档 | 生成 CLAUDE.md 模板 + README 骨架 |
| Git 工作流 | 初始化 husky + lint-staged + 生成 `.autopilot/worktree-links` + 检测硬编码端口 + 从 .env.local 生成 .env.example（值替换为占位符） |
| 依赖与安全基线 | 运行 `npm audit fix` + 补全 .gitignore 敏感文件规则 + 推荐安装 zod 做 input validation |
| AI 就绪度 | 丰富 CLAUDE.md 内容 + 创建测试模板 + 建议生成 OpenAPI spec（如有 API 路由） |
| 性能保障 (P1) | 安装 @lhci/cli + 生成 .lighthouseci.json（含 Core Web Vitals 预算断言）+ 添加 npm script |
| 性能保障 (P2) | 生成 Playwright 性能测试示例（e2e/performance.spec.ts），详见 [references/performance-testing.md](references/performance-testing.md) |
| 性能保障 (P3) | 安装 size-limit + 生成 .size-limit.json（当前体积 + 20% buffer）+ 添加 npm script |

#### L2 修复详情：API Route 测试

当 Dim 1 因 L2 缺失降分时（有 API 路由但无 API route 测试），执行以下步骤：

1. **检测 API 框架**：
   - Next.js App Router：`app/api/` 目录存在 → 直接 import handler 方式
   - Express/Fastify：`router.get/app.get` 模式 → 推荐安装 supertest

2. **扫描现有测试模板**：
   - 搜索 `*.acceptance.test.*` 或 `*.integration.test.*` 文件
   - 取第一个文件的 import 结构和 mock 模式作为模板参考
   - 无现有模板则使用通用骨架

3. **生成文件**：
   - 创建 `__tests__/api/` 目录
   - 生成 1 个示例 API route test（基于项目中最简单的 API 路由）
   - 示例需包含：auth mock、db mock、成功/失败两个测试用例

4. **AskUserQuestion 确认**后执行

#### L3 修复详情：E2E 测试

当 Dim 1 因 L3 缺失降分时，执行以下步骤：

1. **安装依赖**：`npm install -D @playwright/test && npx playwright install chromium`
2. **生成 `playwright.config.ts`**：
   - 自动检测 dev server 命令（从 package.json `scripts.dev` 读取）
   - 自动检测端口（从 dev 命令参数中提取，如 `--port 4000`）
   - 配置 `webServer` 自动启动 dev server
   - 只配置 chromium 项目
3. **生成 `e2e/` 目录 + 示例 spec**：
   - 1 个冒烟测试：访问首页 → 验证页面标题 → 截图
4. **更新已有配置**：
   - `vitest.config.ts`：添加 `exclude: ['e2e/**']`（如文件存在）
   - `package.json`：添加 `"test:e2e": "playwright test"` script
   - `.gitignore`：添加 `test-results/`、`playwright-report/`、`blob-report/`
5. **AskUserQuestion 确认**后执行

### 修复安全规则

- **文件已存在** → 展示 diff 让用户确认，绝不覆盖
- **涉及依赖安装** → 明确列出将安装的包和版本
- **配置文件冲突** → 提示用户手动合并
