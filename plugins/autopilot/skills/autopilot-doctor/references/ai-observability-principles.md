# AI 可观测性 / 调试友好度 — 9 维核心原则

> Dim 13 修复 prompt：当某维度非 PASS 时，doctor 报告引用本文件对应片段驱动 AI 自主修复。
> 风格：非 scaffold（不给具体文件名/具体命令模板），给「本质 + 业界对照 + 自主调研方向」。
> 调用方：doctor Wave 2 输出报告时，对每个 ⚠️/❌ 维度粘贴对应 id 段。

## 维度分层

- 维 1-6：客观信号（`detect_ai_observability()` lib.sh 探测）
- 维 7-9：语义判断（doctor Wave 2 AI 判断）

---

### [DIM-13-01] 结构化日志（Struct Log）

**核心原则：日志的本质是「机器可解析的事件流」，不是写给人读的散文。**

每条日志应是结构化记录（JSON / logfmt），含 `timestamp` / `level` / `msg` / 上下文字段（如 `requestId` / `userId` / `error.code`）。让 AI 能按字段 `jq` 过滤、聚合、定位根因——而不是从自由文本里 regex 抽信息。

**业界对照**：Node pino/winston JSON mode、Python structlog/loguru、Go zap/slog、Swift Logger + 自定义 JSON formatter、Google Cloud structured logging 规范。

**自主调研方向**：调研本栈最轻量的结构化方案，确保：① 输出机器可解析 ② 级别由 env 控制 ③ 落盘可查询。思考生产 vs 测试环境日志级别差异如何配置。

---

### [DIM-13-02] 日志轮转（Log Rotation）

**核心原则：日志不能无限增长，必须有显式的「容量边界」。**

两条边界至少各一：① 单文件大小上限（如 5 MiB 触发切分）② 历史文件数量/总大小上限（如保留最近 30 个归档、总量 50 MiB）。无边界 = 磁盘耗尽风险 = 生产事故隐患。

**业界对照**：logrotate（Linux 系统级）、pino-roll / winston-daily-rotate-file（Node）、Swift `rotateSizeBytes` + `retainMaxArchives`（buddy 模式）、Python `RotatingFileHandler` / `TimedRotatingFileHandler`。

**自主调研方向**：本栈是否有内建轮转机制？无则需自定义或依赖 logrotate。思考大小阈值与数量阈值应分别取多少（参考业界默认 5-10 MiB / 7-30 个）。

---

### [DIM-13-03] CLI 诊断命令（CLI Diagnostic）

**核心原则：应用必须暴露「健康自查入口」，让人和 AI 一条命令拿到当前状态。**

至少提供 `health` / `status` / `info` 之一（输出 JSON 最佳），用于：① CI 预检 ② 部署后冒烟 ③ 故障排查第一手信息 ④ AI 调试时不重启应用拿到配置/依赖/连接状态。

**业界对照**：`kubectl health` / `buddy health` / Django `manage.py check` / Rails `rails db:migrate:status` / Next.js 自定义 `/api/health` route + npm script 包装。

**自主调研方向**：本栈/本框架的 CLI 入口是什么？应该新增子命令还是 npm script？思考命令应输出哪些字段（version / uptime / dependencies / connections / errors）。

---

### [DIM-13-04] health JSON（Health Endpoint）

**核心原则：health 端点的输出必须是「机器可解析的契约」，不是「人类可读的散文」。**

`status: "ok"` / `status: "degraded"` / `status: "down"` 三态枚举 + 各依赖子检查（db / cache / external api）的独立状态。让监控系统、AI 排查、CI 预检都能 `jq` 解析后做布尔决策。

**业界对照**：Spring Boot Actuator `/actuator/health`（JSON + 细分 db/disk/mq）、Kubernetes liveness/readiness probe 标准、RFC 草案 draft-inadarei-api-health-check。

**自主调研方向**：health 命令 / `/health` route / `/api/health` 任一即可，输出需 `jq .status` 可解析。思考依赖项应暴露哪些（db / cache / external api / disk space / memory）。

---

### [DIM-13-05] 缓存清理（Cache Clean）

**核心原则：可重置状态是「可调试」的前提，应用必须有「干净重启」的能力。**

至少有一个 `clean` / `purge` / `prune` 入口（npm script / Makefile target / CLI 子命令），用于：① 清除损坏的缓存 ② 复现"干净环境"行为 ③ CI 跑前归零 ④ AI 修复后验证回归。

**业界对照**：`npm cache clean` / `cargo clean` / `make clean` / Swift `swift package clean` / `go clean -cache` / Next.js `rm -rf .next`（但应封装成 script，不让 AI 记路径）。

**自主调研方向**：本项目的产物目录是什么？封装一个 `clean` script 即可。思考是否需要分级（`clean:build` vs `clean:cache` vs `clean:all`）。

---

### [DIM-13-06] debug 开关（Debug Switch）

**核心原则：详细日志必须是「可按需开启的」，不能写死在代码里。**

通过 env 变量（`LOG_LEVEL` / `DEBUG` / `<NS>_LOG_LEVEL`）或编译 flag（Swift `#if DEBUG` / Rust `cfg(debug_assertions)`）控制，让生产环境默认安静、调试时一行 env 切到 verbose。写死 debug 日志 = 生产噪音 + 信息泄漏。

**业界对照**：十二要素应用「Logs」原则（级别由 env 控制）、`debug` npm 包（namespace 启用）、Python `logging.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))`、Swift `#if DEBUG`。

**自主调研方向**：本栈推荐的日志级别控制方式是什么？至少一个 env 切 debug 级别。思考是否需要分级 trace/debug/info/warn/error/off 全集。

---

### [DIM-13-07] error code 语义（Error Code）— Wave 2 AI 判断

**核心原则：错误响应必须是「可程序化处理的契约」，不是「人类可读的报错文案」。**

每个对外错误应含：① 稳定的 `code` 字段（如 `USER_NOT_FOUND` / `RATE_LIMIT_EXCEEDED`）② 上下文字段（`requestId` / `resource` / `limit`）③ 可选修复建议链接或 hint。让客户端能 `switch(code)` 而非 `if(message.includes(...))`，让 AI 能据 code 直查根因。

**业界对照**：gRPC status code + details、JSON-API errors spec（`errors[]` with `code`/`status`/`detail`）、gRPC `google.rpc.Status`、Stripe API error structure（`error.code` + `error.decline_code`）。

**自主调研方向**：本项目错误响应 schema 是什么？是否仅返回 message 字符串？思考 error code 应如何命名（稳定枚举 vs 动态字符串）、如何与 HTTP status 协同、是否对外暴露 fix hint。判断标准：API 错误响应能否让 AI 仅据 code（不看 message）定位到处理分支。

---

### [DIM-13-08] 命名空间一致（Namespace Consistency）— Wave 2 AI 判断

**核心原则：跨目录/产物/配置的命名前缀统一，是「可发现性」的基础。**

目录名、日志路径、socket 名、bundle id、env 变量前缀、npm scope 都应共享同一命名空间（如 `buddy` / `little-bee`）。混用前缀（`tools/` vs `svc-little-bee/` vs `little-bee/`）→ AI 难以 grep 全部相关代码、难以推断归属。

**业界对照**：Spring `@ComponentScan` base package、Django app config `name`、npm scope `@org/pkg`、Swift Bundle module name、env 变量 `<APP>_*` 前缀约定（`BUDDY_LOG_DIR` / `STRIPE_API_KEY`）。

**自主调研方向**：本项目跨目录/产物/配置的前缀是否统一？混用是减分项。思考应保留哪个前缀作主、其他逐步迁移；判断标准：`grep -r '<前缀>'` 能否一次命中所有相关代码、配置、产物路径。

---

### [DIM-13-09] debug/prod 隔离（Debug-Production Isolation）— Wave 2 AI 判断

**核心原则：调试信息与生产路径必须「严格隔离」，详细输出绝不能泄漏到生产。**

两层隔离至少其一：① 编译时隔离（Swift `#if DEBUG` / Rust `cfg(debug_assertions)` / webpack `mode: development`）② 运行时 env 隔离（`NODE_ENV=production` 关闭 verbose、`LOG_LEVEL` 默认 info）。隔离不充分 = 性能损耗 + 信息泄漏 + 生产事故（如 verbose 日志记下 PII）。

**业界对照**：React DevTools 生产禁用、webpack `DefinePlugin` + `if (process.env.NODE_ENV !== 'production')`、Swift `#if DEBUG`、Rust `cfg!(debug_assertions)`、Node `NODE_ENV` 约定。

**自主调研方向**：本项目 debug 代码路径是否会泄漏到生产？检查 `process.env.NODE_ENV` / `#if DEBUG` / `isProduction()` 的使用密度。思考是否需要双保险（编译时 + 运行时）、是否有 PII / secret 在 debug 路径里裸打印；判断标准：生产构建是否物理删除 debug 代码路径（dead code elimination），而非仅运行时跳过。
