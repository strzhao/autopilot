# 性能保障检测参考（Dim 11）

AI 按需加载的参考文件。包含工具检测清单、评分案例、--fix 模板。

## 工具检测清单

### P1: Lighthouse CI

| 检测项 | 命令/文件 |
|--------|-----------|
| 依赖 | `package.json` 中 `@lhci/cli` 或 `lighthouse` |
| 配置文件 | `.lighthouseci.json`、`.lighthouserc.{json,js,cjs}` |
| CI 集成 | workflow 文件中 `lhci` / `lighthouse` 关键字 |
| 预算断言 | 配置中有 `assert.assertions` 含性能阈值（minScore / maxNumericValue） |
| npm script | `perf:lighthouse` 或含 `lhci` 的 script |

**完整链路标志**：依赖 + 配置 + 预算断言 +（CI 或 npm script）

### P2: Playwright 性能断言

| 检测项 | 命令/文件 |
|--------|-----------|
| 前提 | 已有 `@playwright/test`（Dim 1 L3 已检测） |
| 性能 API 使用 | 代码中有 `page.metrics()`、`performance.mark/measure`、`PerformanceObserver`、Web Vitals（LCP/CLS/FID/INP） |
| 性能测试文件 | `*.perf.*`、`*.performance.*`、`*.bench.*` |
| tracing 配置 | `playwright.config.*` 中有 `trace` 设置 |

**完整链路标志**：有独立性能测试文件 + tracing 配置 + 至少 2 个性能断言

### P3: Bundle Size 监控

| 检测项 | 命令/文件 |
|--------|-----------|
| 依赖 | `size-limit`、`@size-limit/*`、`bundlesize` |
| 配置文件 | `.size-limit.json`、`.size-limit.js`、`.bundlesizerc*` |
| 分析工具 | `webpack-bundle-analyzer`、`rollup-plugin-visualizer`、`source-map-explorer` |
| CI 集成 | workflow 文件中 `size-limit` / `bundlesize` 关键字 |
| 构建产物体积 | `du -sh dist/ build/ .next/static/` |

**完整链路标志**：依赖 + 配置 + 阈值断言 +（CI 或 npm script）

---

## 适用性判断

| 项目类型 | 适用性 | 说明 |
|----------|--------|------|
| 有前端构建配置（next/vite/webpack）+ build 产出 HTML | **适用** | 全部 P1/P2/P3 |
| 纯库/CLI（有 dist/ 但无 HTML 产出） | **部分适用** | 仅 P3（Bundle Size） |
| 纯后端 API（Express/Fastify） | **N/A** | 无前端产物 |
| 非 Web 项目（Go/Rust/Python 非 Web） | **N/A** | 跳过，满分不计入 |

---

## 评分案例

AI 根据收集的事实数据自行判断，以下为参考（非僵化规则）：

| 场景 | 预期分数 | 理由 |
|------|---------|------|
| Lighthouse CI 完整链路 + size-limit 完整链路 + Playwright 性能断言 | 9-10 | ≥2 方向完整链路 |
| Lighthouse CI 完整链路（含预算），其他方向仅有工具 | 7-8 | 1 方向完整链路 |
| 安装了 size-limit 但无配置文件，或安装了 @lhci/cli 但无断言 | 5-6 | 有工具无配置/断言 |
| 有 Playwright 但无任何 page.metrics / 性能测试文件 | 3-4 | E2E 工具在但未用于性能 |
| 有 dist/ / build/ 但无任何性能监控工具 | 1-2 | 只有构建产物 |
| 纯后端 API、CLI 工具库 | N/A | 不适用，满分 |

---

## --fix 模板

### P1: Lighthouse CI 修复

当 Dim 11 因 P1 缺失降分时（前提：项目有前端构建）：

1. **安装**：`npm install -D @lhci/cli`
2. **生成 `.lighthouseci.json`**：
   - `collect.startServerCommand`：从 `package.json` 的 `dev` script 提取
   - 端口：从 dev script 参数中提取（如 `--port 4000`），默认 3000
   - 断言：performance ≥ 0.9、LCP < 2500ms、CLS < 0.1、TBT < 300ms
3. **添加 npm script**：`"perf:lighthouse": "lhci autorun"`
4. **AskUserQuestion 确认**后执行

### P2: Playwright 性能测试修复

当 Dim 11 因 P2 缺失降分时（前提：项目已有 Playwright）：

1. **生成 `e2e/performance.spec.ts`**：
   - 首页加载时间 < 3s
   - JSHeap < 50MB
   - CLS < 0.1
2. **更新 `playwright.config.ts`**：启用 `trace: 'on-first-retry'`（如未启用）
3. **AskUserQuestion 确认**后执行

### P3: Bundle Size 修复

当 Dim 11 因 P3 缺失降分时（前提：项目有 build 命令）：

1. **安装**：`npm install -D size-limit @size-limit/file`
2. **检测当前构建产物体积**：运行 `npm run build` → `du -sh dist/`
3. **生成 `.size-limit.json`**：阈值 = 当前体积 × 1.2（buffer 避免首次就失败）
4. **添加 npm script**：`"perf:size": "size-limit"`
5. **AskUserQuestion 确认**后执行
