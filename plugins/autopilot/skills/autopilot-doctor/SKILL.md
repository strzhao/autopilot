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
3. Wave 1：并行命令检测（Dim 1-4, 8-9）
4. Wave 2：串行 AI 判断（Dim 5-7, 10）
5. 计算加权总分 → 生成报告
6. 保存到 `.claude/doctor-report.md`
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

**在同一轮响应中发出 6 个 Bash 调用**（每个维度一个），所有命令独立运行、互不依赖。每个命令的目标是收集事实数据，不做判断。所有命令都必须用 `|| true` 或 `2>/dev/null` 保护，避免非零退出码中断检测。

### Dim 1: 测试基础设施（权重 20%）

根据技术栈运行对应命令（示例为 Node.js，其他栈自行适配）：

```bash
# 检查测试框架和配置
cat package.json | grep -E '"(jest|vitest|mocha|ava|tap)"' 2>/dev/null; \
cat package.json | grep -E '"test"' 2>/dev/null; \
ls jest.config* vitest.config* .mocharc* 2>/dev/null; \
find src -name "*.test.*" -o -name "*.spec.*" -o -name "__tests__" 2>/dev/null | head -20; \
find src -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" 2>/dev/null | grep -v node_modules | grep -v ".test." | grep -v ".spec." | wc -l; \
find src -name "*.test.*" -o -name "*.spec.*" 2>/dev/null | wc -l; \
cat package.json | grep -E '"(coverage|c8|istanbul|nyc)"' 2>/dev/null
```

**评分标准**（0-10）：

| 分数 | 条件 |
|------|------|
| 9-10 | 框架 + 配置 + 实际测试 + 覆盖率工具 + 测试/源文件比 > 0.3 |
| 7-8 | 框架 + 配置 + 实际测试文件 ≥ 5 |
| 5-6 | 框架 + 配置 + 少量测试（1-4 个文件） |
| 3-4 | 框架已安装但无测试文件或 test script 不可用 |
| 1-2 | 有 test script 但框架不明或配置错误 |
| 0 | 完全没有测试基础设施 |

### Dim 2: 类型安全（权重 15%）

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

### Dim 3: 代码质量工具链（权重 10%）

```bash
# Lint + Format
ls .eslintrc* eslint.config* biome.json .prettierrc* 2>/dev/null; \
cat package.json | grep -E '"(eslint|biome|prettier)"' 2>/dev/null; \
cat package.json | grep -E '"(lint|lint:fix|format)"' 2>/dev/null
```

**评分标准**（0-10）：

| 分数 | 条件 |
|------|------|
| 9-10 | Lint + Format + 自动修复 script + 无自定义规则冲突 |
| 7-8 | Lint + Format 配置完整 |
| 5-6 | 仅有 Lint 或仅有 Format |
| 3-4 | 工具已安装但配置过期或有大量 disable 注释 |
| 0 | 无代码质量工具 |

### Dim 4: 构建系统（权重 10%）

```bash
cat package.json | grep -E '"(build|dev|start)"' 2>/dev/null; \
ls next.config* vite.config* webpack.config* tsup.config* rollup.config* 2>/dev/null; \
ls dist/ build/ .next/ out/ 2>/dev/null
```

**评分标准**（0-10）：

| 分数 | 条件 |
|------|------|
| 9-10 | build + dev 命令 + 构建工具配置 + 输出目录存在 |
| 7-8 | build + dev 命令可用 |
| 5-6 | 有 build 命令但 dev server 缺失（或反之） |
| 3-4 | 构建配置存在但命令不工作 |
| 0 | 无构建系统（纯脚本项目可跳过此维度） |

### Dim 8: Git 工作流（权重 5%）

```bash
ls .husky/ .lefthook.yml .pre-commit-config.yaml 2>/dev/null; \
cat package.json | grep -E '"(husky|lefthook|lint-staged|commitlint)"' 2>/dev/null; \
ls .commitlintrc* commitlint.config* 2>/dev/null; \
echo "--- worktree ---"; \
cat .claude/worktree-links 2>/dev/null; \
ls .env* 2>/dev/null; \
grep -rn 'PORT=' .env* 2>/dev/null | head -5; \
cat package.json 2>/dev/null | grep -E '"(dev|start)"' 2>/dev/null; \
git worktree list 2>/dev/null
```

**评分标准**（0-10）：

| 分数 | 条件 |
|------|------|
| 9-10 | pre-commit hooks + commitlint + lint-staged + worktree-links 配置 + 端口无硬编码 |
| 7-8 | pre-commit hooks + lint-staged + (.env 可链接或 worktree-links 存在) |
| 5-6 | 仅 pre-commit hooks 或仅 commitlint + 无 worktree 适配 |
| 3-4 | 工具已安装但 hooks 未激活 |
| 0 | 无 Git 工作流工具 |

### Dim 9: 依赖健康（权重 5%）

```bash
# Lock 文件检查
ls package-lock.json yarn.lock pnpm-lock.yaml 2>/dev/null; \
# 漏洞检查（快速，不阻塞）
npm audit --json 2>/dev/null | head -5 || echo "npm audit not available"; \
# 过时依赖（仅计数）
npm outdated 2>/dev/null | wc -l || echo "0"
```

**评分标准**（0-10）：

| 分数 | 条件 |
|------|------|
| 9-10 | Lock 文件 + 0 漏洞 + outdated < 5 |
| 7-8 | Lock 文件 + 低风险漏洞 ≤ 3 |
| 5-6 | Lock 文件存在 + 部分漏洞 |
| 3-4 | Lock 文件缺失或严重不同步 |
| 0 | 无依赖管理 |

---

## Step 2: Wave 2 — 串行 AI 判断

这些维度需要阅读文件内容并做综合判断，不能简单用命令输出打分。

### Dim 5: CI/CD Pipeline（权重 10%）

**检查**：读取 `.github/workflows/`、`.gitlab-ci.yml`、`Jenkinsfile` 等 CI 配置文件。

**评分标准**（0-10）：

| 分数 | 条件 |
|------|------|
| 9-10 | CI 配置 + 包含 test/lint/type-check/build 四项质量门 + PR 检查 |
| 7-8 | CI 配置 + 至少 2 项质量门 |
| 5-6 | CI 配置存在但仅做 build 或 deploy |
| 3-4 | CI 配置过期或不完整 |
| 0 | 无 CI/CD 配置 |

### Dim 6: 项目结构（权重 10%）

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

### Dim 7: 文档质量（权重 10%）

**检查**：读取 `CLAUDE.md`、`README.md`、查看是否有 JSDoc/docstring。

**评分标准**（0-10）：

| 分数 | 条件 |
|------|------|
| 9-10 | CLAUDE.md（内容丰富）+ README + API 文档 |
| 7-8 | CLAUDE.md 存在 + README 完整 |
| 5-6 | 仅 README 或仅 CLAUDE.md |
| 3-4 | README 存在但过于简略（< 10 行） |
| 0 | 无文档 |

### Dim 10: AI 就绪度（权重 5%）

这是 autopilot doctor 与传统工具的核心差异化维度。

**检查项**：
- **CLAUDE.md 深度**：是否包含架构说明、开发规范、常用命令？（读取 CLAUDE.md 评估）
- **测试模板可复制性**：现有测试文件是否有清晰的模式可供 AI 参考？（读取 1-2 个测试文件评估）
- **红队测试可行性**：项目是否有足够的接口定义让红队仅凭设计文档就能写测试？
- **AI 友好的 script**：package.json 中的 scripts 是否语义清晰、可独立运行？

**评分标准**（0-10）：

| 分数 | 条件 |
|------|------|
| 9-10 | CLAUDE.md 丰富 + 测试模板清晰 + scripts 语义化 + 接口定义完整 |
| 7-8 | CLAUDE.md 存在 + 有参考测试 + 基本 scripts |
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
| Dim 1: 测试基础设施 | 0.20 |
| Dim 2: 类型安全 | 0.15 |
| Dim 3: 代码质量工具链 | 0.10 |
| Dim 4: 构建系统 | 0.10 |
| Dim 5: CI/CD Pipeline | 0.10 |
| Dim 6: 项目结构 | 0.10 |
| Dim 7: 文档质量 | 0.10 |
| Dim 8: Git 工作流 | 0.08 |
| Dim 9: 依赖健康 | 0.02 |
| Dim 10: AI 就绪度 | 0.05 |

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
| 1 | 测试基础设施 | X/10 | ✅/⚠️/❌ | 一句话概括 |
| 2 | 类型安全 | X/10 | ✅/⚠️/❌ | 一句话概括 |
| 3 | 代码质量工具链 | X/10 | ✅/⚠️/❌ | 一句话概括 |
| 4 | 构建系统 | X/10 | ✅/⚠️/❌ | 一句话概括 |
| 5 | CI/CD Pipeline | X/10 | ✅/⚠️/❌ | 一句话概括 |
| 6 | 项目结构 | X/10 | ✅/⚠️/❌ | 一句话概括 |
| 7 | 文档质量 | X/10 | ✅/⚠️/❌ | 一句话概括 |
| 8 | Git 工作流 | X/10 | ✅/⚠️/❌ | 一句话概括 |
| 9 | 依赖健康 | X/10 | ✅/⚠️/❌ | 一句话概括 |
| 10 | AI 就绪度 | X/10 | ✅/⚠️/❌ | 一句话概括 |

> 状态图标：✅ ≥ 7 | ⚠️ 4-6 | ❌ ≤ 3

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
| Worktree 并行开发 | ✅/⚠️/❌ | Dim 8 | 需要 worktree-links 或 .env 可链接 + 端口无硬编码 |

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

将上述完整报告写入 `.claude/doctor-report.md`（使用 Write 工具）。

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
| 测试基础设施 | 安装测试框架 + 生成配置 + 创建示例测试 |
| 类型安全 | 生成 tsconfig.json（strict 模式）/ 安装 mypy |
| 代码质量 | 生成 ESLint/Biome 配置 + 添加 lint script |
| 构建系统 | 添加缺失的 build/dev scripts |
| CI/CD | 生成 GitHub Actions 基础 workflow |
| 文档 | 生成 CLAUDE.md 模板 + README 骨架 |
| Git 工作流 | 初始化 husky + lint-staged + 生成 `.claude/worktree-links`（扫描 .env* 自动填充）+ 检测硬编码端口 + 调用 worktree repair |
| 依赖健康 | 运行 `npm audit fix` |
| AI 就绪度 | 丰富 CLAUDE.md 内容 + 创建测试模板 |

### 修复安全规则

- **文件已存在** → 展示 diff 让用户确认，绝不覆盖
- **涉及依赖安装** → 明确列出将安装的包和版本
- **配置文件冲突** → 提示用户手动合并
