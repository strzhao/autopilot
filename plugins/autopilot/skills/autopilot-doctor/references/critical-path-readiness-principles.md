# 命脉链路 readiness 覆盖 — 核心原则与代表性盲区

> Dim 14 修复 prompt：当本维度判 warn/fail（命脉无 prod 同构覆盖）时，doctor 报告引用本文件对应片段驱动 AI 自主识别本项目命脉与盲区并给修复方向。
> 风格：非 scaffold（不给具体文件名/具体命令模板/具体框架），给「本质 + 业界对照 + 自主调研方向」。
> **代表性非穷举**：CP-01/02/03 是常见盲区样例，**不是必检清单**。不同项目命脉不同、盲区各异，AI 应以此为参照，自主发现本项目的独有命脉与回归路径。
> 调用方：doctor Wave 2 输出报告时，对 warn/fail 维度粘贴对应 `CP-XX` 段。

## 核心原则

**readiness ≠ liveness**。liveness 回答「进程活着吗」（health 探首页、/ping 返 200），readiness 回答「命脉通吗」（缺了即产品报废的核心链路是否端到端可用）。doctor 13 维全是 liveness 类（工程健康度），命脉穿透审计补 readiness 维度：验证体系是否真正覆盖「缺了即报废」的链路。

**命脉识别方向（给判据不给穷举）**：命脉 = 用户感知的核心价值路径，**不是基础设施**。判据三问：① 这个链路挂了，用户会立刻感知产品报废吗？② 它依赖运行时外部条件（CDN/对象存储/数据库/第三方 API/特定 env）吗？③ 它的「存在」与「可用」是否同构（build 通过 ≠ 运行时通）？三条都中 = 命脉。

**审计动作**：识别命脉 → 假设它以最可能方式回归（见 CP-01/02/03 代表性回归路径，但不限于此）→ 追问现有每一层验证（单测/API/E2E/部署健康/build 断言）能否在造成线上影响前抓到 → 只有至少一层在**与生产同构的环境**里真正覆盖该命脉，才算 readiness 达标。

---

### [CP-01] dev↔prod 异构（Dev-Prod Parity Gap）

**核心原则：验证在 dev 跑通 ≠ 生产能跑通，环境同构是 readiness 的前提。**

dev 侧的 E2E / 集成测试通常用 dev server + mock 依赖 + 本地路径，与生产镜像 / CDN / 对象存储 / 生产 env 完全异构。一条链路在 dev 全绿，可能在 prod 因镜像少装系统依赖、CDN 配置错、对象存储 bucket 权限、env 未注入而 404/500。liveness 类验证（dev E2E、health 探首页）抓不到这类回归——它们只证明「dev 能跑」，不证明「prod 能跑」。

**业界对照**：十二要素应用「Dev/Prod parity」原则、Docker multi-stage build + prod 镜像 E2E、Backstage software templates 的 prod-like environment、Next.js `next build && next start`（而非 `next dev`）作 E2E webServer。

**自主调研方向**：本项目 E2E 跑的是 dev server 还是 prod 构建？dev 与 prod 的依赖、路径、env 有哪些差异点？哪些差异点恰好落在命脉链路上？思考是否至少有一层验证在 prod 同构镜像/环境里跑过命脉路径。

---

### [CP-02] liveness≠readiness（Liveness-Readiness Confusion）

**核心原则：health 端点探首页或进程活 ≠ 命脉通，readiness 探活必须覆盖命脉链路本身。**

部署健康检查常探首页（返回 200）或 `/ping`（进程活），但首页/进程活不等于命脉可用——首页可能是静态 HTML 不依赖命脉链路（如媒体 CDN、搜索、支付），进程活着但命脉 404/500。Kubernetes liveness probe 保活、readiness probe 保流量，二者混淆（用 liveness 探活冒充 readiness 探命脉）是常见假绿根源。

**业界对照**：Kubernetes liveness/readiness probe 双分离规范（readiness 探依赖+命脉，liveness 只探进程）、Spring Boot Actuator `/actuator/health/readiness` 与 `/actuator/health/liveness` 分离、Google SRE 「Prodrocket」深度健康检查原则。

**自主调研方向**：本项目部署后/CI 的健康检查探的是什么？是首页 200 还是命脉链路（如媒体播放、搜索请求、支付回调）？思考 readiness 端点应探哪些命脉子检查（依赖连通 + 关键路径返回预期数据），而非仅进程活或首页静态。

---

### [CP-03] build 期固化（Build-Time Pinning）

**核心原则：配置在 build 时求值固化，运行时 env 注入对已固化配置无效，readiness 必须 build 产物层面断言。**

静态站点/SSR 框架常在 build 时求值配置（如 `publicPath` / `assetPrefix` / CDN 域名 / 路由表），固化进 build 产物。运行时注入 env 想覆盖这些配置无效——产物里的路径已经定型。回归场景：build 时 env 缺失或占位 → 产物路径错 → 部署后命脉链路（媒体/资源/路由）404，而 build 本身成功（liveness 类「build pass」抓不到）。

**业界对照**：Next.js `routes-manifest` / `export.json` build 期固化、Vite `BASE_URL` build 期注入、Webpack `publicPath` build/runtime 分离模式、静态站点生成（SSG）的路径固化本质。

**自主调研方向**：本项目哪些配置是 build 期求值的？命脉链路依赖的路径/域名/路由是否在 build 时固化？思考 build 产物断言（如校验 manifest 含预期路径、产物体积、关键资源可解析）能否在 build 阶段 fail-fast 抓到固化错误，而非等部署后用户撞到。

---

## 修复方向（非 scaffold，给方向不给模板）

针对命脉 readiness warn/fail，修复优先级（投资回报率降序）：

1. **build 期 fail-fast 断言**（对应 CP-03）：build 产物层面校验命脉所需资源/路径/manifest 完整，固化错误在 build 阶段暴露而非部署后。方向：build 后加一步产物校验（解析关键 manifest / 断言路径存在 / 体积阈值），失败即 fail build。
2. **readiness gate 升级**（对应 CP-02）：把部署健康从「首页 200」升级为「命脉子检查」，每个命脉一条 readiness 断言（依赖连通 + 预期响应）。方向：readiness 端点接入命脉子检查，CI/部署后探 readiness 而非首页。
3. **prod 同构 E2E**（对应 CP-01）：至少一条命脉链路在 prod 镜像/prod-like 环境跑端到端，覆盖 dev↔prod 异构点。方向：E2E webServer 切到 prod 构建 + 真实/高保真 mock 依赖，覆盖命脉路径。
4. **命脉契约测试**：命脉链路的请求/响应 schema 作为契约固化在测试里，dev↔prod 配置漂移导致契约破缺即 CI 拦截。

**业界对照**：契约测试（Pact）、prod-like integration test（Testcontainers）、deployment gate（Argo Rollouts analysis）、build-time validation（Terraform validate 思路迁移到应用产物校验）。

**自主调研方向**：本项目命脉链路的「最小可验证子集」是什么？哪一层验证升级成本最低、抓回归覆盖最高？先做那一层。
