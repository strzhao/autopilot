<!-- domain: QA 判定 / red-team / mutation / contract / 量化门禁 / tautological -->
# QA & Testing

### [2026-05-16] 改 QA ⚠️/❌ 判定规则时必须枚举所有合法标记来源 + 强制复盘机制
<!-- tags: autopilot, qa, judgement, warning, false-acquit, plan-reviewer, blocker, defensive-design, anti-rationalization, tier-1.5, tier-3.5 -->
**Background**: case.txt 复盘揭示 little-ant garden 项目 3 个真实 bug（?level=N URL 跳关 / DecorationPiece onClick 断裂 / jsdom useSearchParams null）在 QA 阶段都被 Tier 1.5 e2e 超时暴露，却被编排器自我合理化为 ⚠️「结构性超时」绕过 auto-fix。autopilot SKILL.md 三个缺陷共享同一根因：⚠️ 标记没有独立校验。设计方案最初是「判定行改为 全部 ✅（仅基础设施类 ⚠️）」，plan-reviewer 抓到 BLOCKER：会把 Tier 3.5 性能保障的合法 ⚠️（line 362 既有降级设计）误升级为 ❌，违反现有设计。
**Choice**: (1) 在 `#### 结果判定` 前置检查新增「步骤 3 — Tier 1.5 ⚠️ 复盘」强制对每个 ⚠️ 写辩解 + 对照表三分类（环境/功能/无法辩解）；(2) 步骤 3 显式声明遍历范围严格限定为 Tier 1.5，明列其他 Tier (0/1/3/3.5/4) 都不参与；(3) 判定行括号文字明示双合法 ⚠️ 来源（Tier 1.5 基础设施类 ⚠️ 或 Tier 3.5 性能保障 ⚠️），不能用"基础设施类"一个标签兜底；(4) qa-reviewer prompt 加第 6 项做独立复核（Standard 模式双层防线）；(5) Fast Mode 单层防线（仅改动 1 生效）作为可接受取舍写入风险表。
**Alternatives rejected**: (1) 判定行用单一"基础设施类 ⚠️"兜底（plan-reviewer BLOCKER-1 — Tier 3.5 不属于"基础设施类"语义，会被对照表"无法清晰辩解"分支吞噬升级为 ❌）；(2) 只改 SKILL.md 不改 qa-reviewer prompt（缺第二道独立复核，编排器自我合理化无人监督）；(3) 在 Fast Mode 内联自审里也加 Tier 1.5 ⚠️ 复盘（第 4 处改动，超出"最小化"承诺；case.txt 复盘场景本身是 standard 模式）。
**Trade-offs**: 改动从 1 处扩到 3 处（约 15 行新增），但换得 ⚠️ 滥用必须显式辩解 + 双层独立校验。Fast Mode 失去 qa-reviewer 校验作为单层防线代价，可被未来「step 3 也加到 fast smoke 自审清单」迭代弥补。
**Evidence**: case.txt 末尾用户 3 缺陷列表 + plan-reviewer 初审 BLOCKER-1（置信度 95：「对照表是闭集但不完备，Tier 3.5 性能 ⚠️ 落入'无法清晰辩解 → 默认 ❌'」）+ SKILL.md line 362 既有降级原文 + 复审 PASS + QA 五场景 trace（场景 5 专测 Tier 3.5 ⚠️ 豁免回归 ✅）。
**Lesson**: 改 QA 判定行 / 标记规则前，**必须先枚举所有合法 ⚠️ 来源**（用 grep `⚠️\|降级\|N/A` 扫全 SKILL.md），任何「✅ 允许 ⚠️」的兜底措辞都要白名单化、不能用模糊的语义分类做闭集。"AI 自我合理化"是结构性反模式，光靠教育（references 里的防合理化指南）无效，必须在工作流里加强制检查点（步骤 3）+ 独立审核（qa-reviewer 第 6 项）。每轮重做、不跨轮复用辩解 — 配合 stop-hook 压缩历史的现实约束。

### [2026-05-10] auto-fix 中"看似独立的两个 bug"应优先寻找共同上游脆弱点，一处合并修复
<!-- tags: autopilot, qa, auto-fix, root-cause, merge-fix, anti-symptomatic, bash, scripting -->
**Background**: QA 第 1 轮在 doctor SKILL.md Dim 8 worktree 健康抽查段同时发现 2 个独立失败：场景 5（脚本 exit=1 违反退出码 0 契约）+ 场景 8（在 worktree 内 MAIN_ROOT 错指）。表面看是两个独立 bug，可分别 fix。
**Choice**: auto-fix 不分头修两处，而是把脆弱的"路径比对+赋值变量+短路链"整体替换为一处合并修复——`awk '/^worktree / {n++; if (n==1) next; print $2}'` + done 后追加 `|| true`。复用 git porcelain 输出顺序保证（参 patterns 同期新增 [2026-05-10] git worktree list 第一项稳定 条目），同时消除两个 bug 来源，与契约原话"第一项跳过"逐字对齐。
**Alternatives rejected**: (1) 分别加 `|| true` 修退出码 + 用 `--git-common-dir` 重写 MAIN_ROOT —— 修了症状但 MAIN_ROOT 变量本身仍是脆弱设计（"路径比对"模式继续传染未来脚本）；(2) 加 `set -o pipefail` 并保留路径比对 —— 引入意外副作用且未消除根因；(3) 两处独立修但加注释 "TODO: 重构" —— TODO 永远不会做。
**Trade-offs**: 合并修复要求多读一份 git 文档（验证 porcelain 第一项契约稳定性），但换来更小、更对齐契约描述、删掉 1 个变量、删掉 1 个比对分支的代码。auto-fix 单轮成功（retry_count: 1 → 2 即过 review-accept）证明合并修复路径效率高。
**Lesson**: auto-fix 看到多个失败前，先问"它们是否共享同一脆弱点？"——如果是，找上游一处改可能同时灭掉所有症状；如果不是，再分头修。"分头修+加 || true" 是症状疗法，"识别脆弱模式整体替换" 是根本疗法。前提是有红队充分覆盖（本次 4 case A/B/C/D + 5 真实场景）防止合并修复引入新回归。

### [2026-05-10] 契约对齐采用 contract-checker agent + 集中 protocol，而非分散 prompt 铁律
<!-- tags: autopilot, contract, red-team, blue-team, contract-checker, agent, single-source-of-truth, skill-fragility, gojko, sbe, cdc, pact, dbc, contract-protocol -->
**Background**: 用户基于 relight 11 个 session 历史扫到 7 个红蓝契约不对齐真实案例（B 数据格式 / D 边界值 / H+A 路由签名 / C Mock）— 7/7 都是蓝队理解偏差方（红队不能改测试是规则），auto-fix 反复修不好。autopilot 设计文档无任何"契约"专属字段，红蓝队各自从自然语言归纳必然漂移。v1 方案是"4 处文件加 ⚠️ 章节 + 60 行模板"，被 skill 反审判 3 个致命问题（元任务陷阱 / 多 ⚠️ 章节稀释 / 占位符运行时崩）；同时业界深搜揭示 Gojko SBE 实证「纯纪律方案 88% 团队失败」，单 verifier 仅 +14% 改进，缺独立 contract-checker agent。
**Choice**: v2 重写为「单一真相 references/contract-protocol.md（CDC + DbC 谓词 + Pact example）+ implement 步骤 2.5 contract-checker Agent 字面校验（业界 SOTA 结构性新防线）+ frontmatter contract_required 历史豁免（旧 task 自动跳过，无元任务陷阱）+ 极小 prompt 改动（红/蓝队各加 1 行链接、不新增 ⚠️ 章节）+ 维度数去硬编码（消雷区 7）+ 1 个 atomic commit（承认强耦合不假装独立回滚）」。
**Alternatives rejected**: (1) v1 4 处 prompt 加 ⚠️ 章节 — 撞 [2026-04-17] 决策树后置跳读 anti-pattern + 跨文件描述漂移（业界 SBE 12% 兑现率必败）；(2) OpenAPI/Zod 强类型工具 — 重，prompt 不友好，覆盖不到非 HTTP API 场景；(3) panel consensus reviewer（CANDOR 实证 +15-25pp）— 成本太高，先验 contract-checker 单点收益再迭代；(4) implement 阶段 contract reconciliation 双向 handshake — 多 1 轮 Agent，Q2 brainstorm 已否决走 design 加严路线。
**Trade-offs**: 多 1 个 sonnet sub-agent cold-start ≈ 30k token / implement → 业界单 verifier 实证 +14%、本次为结构性新防线预期效果远超；新增 2 个 reference 文件（contract-protocol + contract-checker-prompt）≈ 170 行；任务从 7 扩到 10。换得：单一真相消除跨 4 文件描述漂移 + 历史豁免消除元任务陷阱 + checker 拦下 80% 字面 mismatch 不浪费红队 token。
**Evidence**: relight 7 个真实案例（含 burst-detector memberCount/manualOverride 字段缺失 / sprite buffer ≥1000 字节边界 / scanRouter 整路由 404）+ relight doctor-report 直接诊断「无 OpenAPI schema 红队推断 API 契约」+ skill 反审 3 致命问题报告 + 业界 14 个权威源（Martin Fowler CDC / Pact / Pactflow / Microsoft CDC playbook / Gojko SBE 10 年回顾 / MetaGPT arxiv 2308.00352 / CANDOR arxiv 2506.02943 / Bertrand Meyer DbC / Hypothesis / DevGuide contract-first）+ v2 plan-reviewer PASS 7/7 + Tier 0 红队 11/11 + Wave 2 Section A/B 19/19 ✅。
**Lesson**: skill / 框架级改动被 plan-reviewer PASS 不等于对 — 业界深搜（找 SOTA 模式 + 已知 anti-pattern）+ skill 反向审核（对照 best practice 检查脆弱性）应在 PASS 后**主动**触发二审。纯纪律方案（"在 MD 加章节 + 文本审"）业界实证 88% 失败，必须配独立自动化校验 agent。元任务陷阱通过 frontmatter 豁免字段 + setup.sh 写入新值的模式可推广到任何"新增强制门"场景。

### [2026-05-23] SKILL.md 重构任务的 Tier 1.5 必须含"不变量护栏" grep 场景
<!-- tags: autopilot, qa, tier-1.5, skill-refactor, invariant-guard, grep-pattern, terminology-network, reference-chain, false-improvement, anti-pseudo-optimization -->
**Scenario**: autopilot 任务对 SKILL.md 做"小幅改动 + 主动放弃大量伪优化"型重构（如 v3.34.1 仅 +3 行修改但显式放弃了 7 项被 best practice 筛除的伪优化）。如果 Tier 1.5 只验证"改动是否落地"（正向场景），无法防止下一轮其他 AI 编排器误以为某条被放弃的改动是"还没做完"而重新引入劣化（如下次直接拆 Wave 1a/1b/1c）。
**Lesson**: 当任务性质是"重构现有 SKILL.md / 简化文档结构 / 改流程顺序"时，Tier 1.5 场景必须**正反双面覆盖**——既验证改动落地，也设"不变量护栏"防止伪优化引入劣化：
- **术语网络保留**：枚举改动涉及章节的所有现有术语（Wave 1 / Wave 1.5 / Wave 2 / Tier 0-4 等），逐个 `rtk grep -cE "<term>"` 命中 ≥1 次。改名/删名即 ❌。
- **段落独立性保留**：现状若有 N 个独立标题段（如三段"前置"），grep `^#### 前置：` 必须命中 N 次。合并即 ❌。
- **判定步骤数保留**：现状若有 K 步检查清单，grep `\*\*步骤 [1-K] —` 必须命中 K 次。合并即 ❌。
- **历史决策引用链保留**：grep 改动相关章节中曾被 `[YYYY-MM-DD]` 决策原文引用的术语字面，必须仍命中。
- **不动章节零改动**：`git diff SKILL.md | grep "^@@"` 输出的 hunk 范围必须全部落在目标 Phase 行号区间内（如本次 L287-426 Phase: qa），其余 Phase 区域 hunk 数 == 0。
**实施模板**（在设计文档"真实测试场景"区直接套用）：
```
S-INV-1 [独立] — 术语网络完整保留
执行: 依次 `rtk grep -cE "Wave 1\b"` 等 N 个术语
预期: 每个 ≥1 次

S-INV-2 [独立] — 三段独立性保留
执行: `rtk grep -nE "^#### 前置：|^##### 前置：" SKILL.md`
预期: 命中 3 处独立标题

S-INV-3 [独立] — 步骤数保留
执行: `rtk grep -nE "\*\*步骤 [123] —"`
预期: 命中 3 个独立步骤标记

S-INV-4 — 不动章节零改动
执行: `git diff SKILL.md` 看 hunk 行号
预期: 全部在目标 Phase 区间内
```
**Evidence**: v3.34.1 本轮 10 个 Tier 1.5 场景中 7 个是不变量护栏（S4 术语网络 9 个/S5 三段前置/S6 三步判定/S7 auto-fix 零改动/S8 qa_scope 三档/S9 ⚠️ 复盘对照表/S10 早期判定阈值），全部 PASS。验证了 best practice 重审时筛除的 7 项伪优化（拆 Wave 1a/1b/1c、合并步骤、删 Wave 1.5、合并前置、qa_scope 表格化、应有场景类型前移、失败聚类）一项未被误引入。配合 [[skill-best-practice-5-dimensions]]（[2026-05-23] decisions）形成"设计前筛 + 测试时护栏"的双层防伪优化机制。

### [2026-05-09] 主对话需等待外部 UI 操作时，前台同步 Bash + 长 timeout 优于 run_in_background
<!-- tags: autopilot, claude-code, bash-tool, run-in-background, ux, html-review, blocking-call -->
**Scenario**: 涉及"用户在外部界面（浏览器/外部 GUI）操作 → 触发本地脚本完成 → Claude 主对话基于脚本输出继续"的功能，例如 HTML 评审、外部审批表单、远程触发。如果 Claude 用 `run_in_background: true` 把等待脚本扔后台，会破坏自动续上：用户操作完后还得回终端发一条消息（"我点完了"），Claude 才会去读结果文件——多一次无意义的二次操作。
**Lesson**: 这类场景必须**前台同步** Bash 工具调用（`run_in_background: false`），并把 `timeout` 显式设到 600000ms（工具最大值 10 分钟）。bash 阻塞期间用户在浏览器/外部 UI 操作，操作完成后脚本立即 stdout 输出 → bash 工具立即返回 → 主对话自动接住继续。代价是主对话挂起 ≤10 分钟，但 99% 场景用户在几十秒内完成；少数 >10 分钟超时场景应有 fallback（AskUserQuestion + preview）。这是工具调用的隐含语义，必须在 SKILL.md 显式写明（"前台同步 / 禁用 run_in_background / timeout=600000"），否则 Claude Agent 自由选择会偏向后台。
**Evidence**: v3.22 HTML plan review 上线时演示发现：第一次后台启动 → 用户点完按钮后还要回终端发消息触发我读 `/tmp/plan-review-out.json`，体验差。改前台同步后第二次演示 bash 立即返回 stdout JSON，0 次二次操作。文档锁定：SKILL.md 步骤 4c + html-review-guide.md 4c 调用规范段；红队 acceptance 加 C3h/C3i 断言。

### [2026-03-22] 外部审查后的修改必须重新验证
<!-- tags: autopilot, qa, post-review, validation, framer-motion -->
**Scenario**: little-bee 鼻字 NoseScene 通过 Gemini 评分 96/100 后，基于 Gemini 建议将 spring 动画改为 3 关键帧（[1, 0.88, 1.15]），未重新验证直接合入
**Lesson**: framer-motion 的 spring 动画只支持 2 关键帧，3 关键帧导致运行时崩溃。QA 全部"通过"后用户手动测试才发现。根因：评分后的修改绕过了所有验证层。规则：任何在外部审查/评分之后所做的代码修改，必须重新运行对应的验证（至少 tsc + 受影响测试）
**Evidence**: lb_case.md 行 1696-1706 运行时错误 "Only two keyframes currently supported with spring and inertia animations"，autopilot v2.13.0 新增 Post-Review Modification Rule

### [2026-03-22] Tier 1.5 验证场景必须匹配核心变更层级
<!-- tags: autopilot, qa, tier-1.5, ui-testing, smoke-test -->
**Scenario**: 鼻字 NoseScene.tsx（461 行 UI 组件）的验证方案只有数据库查询和音频索引检查——全是数据层测试，没有任何 UI 渲染场景
**Lesson**: Tier 1.5 的场景类型必须覆盖核心变更层级。UI 组件变更 → 必须有渲染/交互验证；API 变更 → 必须有端点调用。仅有数据层验证的 UI 任务是不完整的。如果设计阶段验证方案缺少匹配场景，QA 阶段必须自行补充
**Evidence**: lb_case.md Tier 1.5 全部通过但组件渲染时 framer-motion 崩溃，autopilot v2.13.0 新增变更类型覆盖检查

### [2026-03-24] 插件合并时红队路径假设容易出错
<!-- tags: autopilot, red-team, testing, file-path, merge -->
**Scenario**: 将 worktree-setup 合并到 autopilot 时，红队仅凭设计文档编写文件存在性验收测试，对项目目录结构做出错误假设——检查 `worktree.test.mjs`（实际是 `worktree.acceptance.test.mjs`）、检查 `references/knowledge-engineering.md`（实际路径是 `skills/autopilot/references/knowledge-engineering.md`）
**Lesson**: 红队信息隔离在"文件迁移/重组"类任务中有天然劣势：文件名和嵌套路径需要精确匹配，但红队只看设计文档无法确认真实路径。对此类任务，设计文档应在文件影响范围表中提供完整的绝对路径而非缩写，或在验证方案中给出精确的文件存在性检查命令
**Evidence**: 当时的 worktree-merge.acceptance.test.mjs 27 测试中 2 个因路径假设失败（25/27 通过），均为红队路径推测错误而非实现缺陷（该测试文件因绑定 v3.0.0 一次性迁移、长期不在 npm test 内、断言全面腐烂，已于 2026-05-10 删除）

### [2026-03-26] Tier 1.5 场景部分执行等于未执行
<!-- tags: autopilot, qa, tier-1.5, smoke-test, partial-execution -->
**Scenario**: little-bee-cli autopilot 全流程中，设计了 3 个真实测试场景（--help、hanzi list、hanzi search），但 QA 只执行了场景 1（--help），跳过了需要 server 的场景 2/3
**Lesson**: 48 个红/蓝队测试全通过但 4 个 bug（token 字段名不匹配、auth=false 不带 Cookie、CDN 缓存、endpoint 错误）全靠用户手动发现。根因：(1) Tier 1.5 场景部分执行但报告中只列出已执行的，遗漏不可见 (2) 红队 mock 过度跳过真实数据流 (3) 蓝队假设 endpoint 路径未运行时验证。修复：结果判定新增场景计数匹配检查，stop-hook QA prompt 注入 Tier 1.5 完整性提醒
**Evidence**: conversation-2026-03-26-003626.txt 行 2890-2978，AI 自述"偷懒了"

### [2026-03-30] SKILL.md 文档文本中的标识符会干扰红队正则测试
<!-- tags: autopilot, red-team, testing, indexOf, text-proximity, regex -->
**Scenario**: (1) 成本优化章节表格包含 agent 名称（plan-reviewer、红队、design-reviewer），红队验收测试用 `indexOf('agent-name')` + 2000 字符窗口查找 `model: "sonnet"`，首次匹配命中文档文本而非 Agent 调用行。(2) v3.8.0 步骤 2 文本"供步骤 3 的 Plan 审查使用"包含"步骤 3"，红队测试用 `/步骤\s*3/` 提取步骤 2 内容时正则提前截断，导致步骤 2 中的降级/隔离关键词无法被检测到。
**Lesson**: SKILL.md 中文档描述引用其他步骤编号或 agent 标识符时，会被红队测试的正则/indexOf 匹配机制误命中。两类缓解：(1) agent 名称用中文泛称，精确标识符只出现在技术定义处 (2) 跨步骤引用避免使用"步骤 N"格式，改用"后续 Plan 审查"等无编号泛称。核心原则：文档描述中的任何标识符都可能成为正则锚点。
**Evidence**:
- 案例 1: v3.5.2 红队 17 测试 2→3→1→0 失败修复 3 轮（成本优化表格中的 agent 名称触发 indexOf 误匹配）
- 案例 2: v3.8.0 红队 36 测试因"步骤 3"引用导致 step2Match 仅捕获 294 字符（预期 ~800），修复改为"后续 Plan 审查"
- 案例 3: v3.14.0 doctor Dim 12 章节内 inline code `### [日期]` 含 `## ` 子串触发红队 regex lookahead `##\s` 提前截断，章节抽取丢失第 5 项关键词「元信息」；修复改为"H3 三级标题（[日期] 开头）"文字描述。揭示 Markdown 章节标识符（`### `/`## `）在 inline code 中也是正则锚点

### [2026-05-07] 函数支持"测试 mock 输入"分支会掩盖生产路径 bug
<!-- tags: autopilot, red-team, dual-path, function-signature, qa-blind-spot, production-vs-test -->
**Scenario**: stop-hook.sh 的 `detect_smoke_eligible($1)` 为兼容红队测试用 invoke_detect 传入 mock diff 临时文件，新增了 $1 参数处理"测试模式分支"（如果 $1 是可读文件就当 raw diff 解析）；生产调用错写为 `detect_smoke_eligible "$STATE_FILE"`，状态文件路径被当作 mock diff，函数始终走"测试分支"对 state.md 做 `grep ^[+-]` → diff_lines 几乎总是 0 → 路径 C（≤30行/≤3文件）总满足 → smoke 永远触发，自动检测机制完全失效。
**Lesson**: 当函数同时支持"测试参数化输入"和"生产自动 fetch"两条分支时，红队验收测试只会覆盖前者（因为它本就是为前者设计）；生产路径会变成"红队铁律"的盲区。三层防御：(1) 函数文档明确语义（无参=生产/有参=测试）+ 参数命名对应（`diff_input` 而非 `state_file`）；(2) 红队测试外**必须**新增 1 个生产路径 smoke test（无参调用 + 真实 git 仓库）作为 Tier 1.5 场景；(3) Wave 2 qa-reviewer 应主动 grep 函数所有调用点，对照签名约定逐项验证。
**Evidence**: v3.17.0 第二轮 QA Wave 2 qa-reviewer 才抓到此 BLOCKER（line 428 错传 STATE_FILE）。第一轮 QA 红队 8/8 全过，因为 R5 用专用 invoke_detect 调用模式覆盖测试路径，没覆盖生产路径。修复仅需 1 行（删 "$STATE_FILE" 参数），但发现路径绕了完整一轮 QA + auto-fix。

### [2026-05-14] 契约规约中字段/占位符出现同义变体会让下游实现犹豫，必须单一字面量
<!-- tags: autopilot, contract, plan-reviewer, placeholder, naming, single-source-of-truth, blue-team, red-team, ambiguity -->
**Scenario**: 设计文档「契约规约」章节描述同一个注入点时给出两个候选占位符名（如 `{{AUTO_CLOSE_PREF}}` 字面字符串 vs `{{AUTO_CLOSE_PREF_CHECKED}}` 仅 checked 属性），即使作者意图是"或选其一"，蓝队读到 "or" 必然犹豫；红队也无法 grep 字面量写出确定性 fail 断言。
**Lesson**: 契约文档中的字段名 / 占位符名 / 错误码名 / 路由路径必须**单一字面量**，不允许"or 变体"或"等价别名"。如果实际存在多个注入位置，每个位置独立命名（如 `XX_VALUE` 和 `XX_CHECKED_ATTR`），并明确各自的渲染规则；不要让一个变量名在文档里有两种语义。该原则与 contract-protocol.md 的 single-source-of-truth 同源——契约规约本身也是 single source of truth，自身不能漂移。红队应专门加"禁止变体"反向断言（grep `不应出现的变体名` 不命中 fail）做回归防御。
**Evidence**: 本次 plan-reviewer Agent 在 design 阶段抓到 C-template-placeholders 节里 `{{AUTO_CLOSE_PREF}}` 与 `{{AUTO_CLOSE_PREF_CHECKED}}` 二义性，评为 80-90 级重要问题；收口为唯一 `{{AUTO_CLOSE_PREF}}` 注入到 `<body data-auto-close="...">`，并在红队 acceptance test 加 `C8d: 不含 {{AUTO_CLOSE_PREF_CHECKED}} 等禁止变体占位符` 反向断言做回归防御（plan-review-html.acceptance.test.sh）。如果蓝队按 "or" 实现挑了 `{{AUTO_CLOSE_PREF_CHECKED}}` 路径，contract-checker 会被迫接受（契约本就允许），缺陷会被掩盖到下次 redesign。

### [2026-05-14] 多占位符模板 str.replace 顺序敏感：原始用户内容占位必须最后替换
<!-- tags: template, str-replace, render-order, placeholder, pollution, marked-js, latent-bug, defense, regression -->
**Scenario**: 模板渲染用 `tmpl.replace('{{A}}', ...).replace('{{B}}', ...).replace('{{C}}', ...)` 链式全局替换多个占位符。当某个占位符的"值"（特别是"原始用户内容"如 markdown 文档、用户输入）字面引用了**其他占位符的名字**（例如契约规约文档自身讨论模板占位符），且这个占位符在替换链中被**先**注入，则后续 replace 会把注入内容里的字面量也一起替换 → 重复注入 / 越权替换。在 plan-review 场景中，design content 引用了 `{{MARKED_LIB}}` 字面量 3 次，被先注入后，下一步 `replace('{{MARKED_LIB}}', marked_lib)` 把全部 4 处（1 真占位 + 3 字面）全替换 → marked.min.js 被重复注入 3 倍体积到 design content 内 → marked.parse() 把其内嵌的 `'<a href="'+(e=s)+'"'` JS 片段当 markdown 自动链接渲染 → 生成畸形 `<a href="'+(e=s)+'">` → 用户点决策按钮时浏览器误触 navigate 到非法 URL。
**Lesson**: 多占位符 template 渲染必须遵守**单一替换顺序契约**——
(1) "**原始用户内容**"占位（markdown 文档 / 用户输入 / 富文本）**永远最后替换**，且替换后**不再有其它 replace 步骤**；
(2) 系统注入占位（库代码、配置值、boolean 字面）放在用户内容之前完成；
(3) 若必须支持任意顺序，切换到**单次扫描**的 template engine（`string.Template`、`format_map`、Jinja2 等），避免链式 `str.replace` 的相互污染；
(4) **acceptance test 必须含反向断言**——构造 design 内嵌占位符字面量的 mock 用例，校验渲染后这些字面量保留 + 系统占位只注入 1 次（特征字符串计数）。该 bug 是 latent 多版本（自 v3.22 引入 marked.js 起就存在），只有本次任务的设计文档元讨论占位符才首次触发。
**Evidence**: 现象 = 浏览器点击「通过」按钮后误 navigate 到 `http://localhost:59177/'+(e=s)+'`。证据链：`grep -c '(e=s)' /tmp/rendered.html` = 4（修复前），= 1（修复后，仅 marked.min.js 源码内）；HTML 文件体积 186KB → 80KB（减少 ≈3 倍 marked.js）。修复 `launch-plan-review.sh` python 渲染顺序：`{{MARKED_LIB}}` → `{{AUTO_CLOSE_PREF}}` → `{{DESIGN_CONTENT}}`（design content 最后注入）。回归防御 `plan-review-html.acceptance.test.sh` 新增 C11a/b/c 三个断言：marked 特征 `(e=s)` 计数 = 1 + design 内 `{{MARKED_LIB}}` 字面保留 + 渲染顺序 awk 校验。v3.27.0 → v3.27.1 hotfix（756a1ce）。该 pattern 关联 [2026-05-14] 契约规约中字段/占位符同义变体（前者是契约文档内命名一致，后者是渲染层面替换污染，互补）。

### [2026-05-14] HTML 模板用 dataset.X 设置 data-* 属性，红队字面 grep 命中失败 → 改 setAttribute
<!-- tags: dom-api, dataset, setattribute, acceptance-test, grep-literal, red-team, html-template, autopilot, plan-review -->
**Scenario**: HTML 模板内嵌 JS 用 `el.dataset.anchor = value` 在运行时设置 data-* 属性。DOM 上效果与 `el.setAttribute('data-anchor', value)` 完全等价（dataset 字段名 camelCase 自动映射 data-kebab-case）。但**模板源码**只保留 `dataset.anchor` 这个 JS 属性访问表达式，**不含字面字符串 `'data-anchor'`**。红队 acceptance test 若用 `renderedHTML.includes('data-anchor')` 这类**对模板源码 grep 字面 data-***的断言，dataset 写法会让断言失败。
**Lesson**: 契约 / 红队断言面向"产物可见字符串字面"时，蓝队实现侧选择 **`setAttribute('data-x', v)`** 而非 `dataset.x = v`。两种 API 在 DOM 行为上完全等价（后续 `dataset.x` 读取仍能命中 setAttribute 设置的属性），但前者在源码里保留 `'data-x'` 字面字符串，能被 grep 命中。同族反面：[[red-team-document-text-noise]]（[2026-03-30]）警示文档字面会"误命中"，组合起来形成 acceptance test 字面 grep 的双向陷阱——**字面要存在的地方必须显式存在；字面不该存在的地方必须显式隔离**。该原则只在"红队走字面字符串黑盒断言"的项目生效（典型：HTML/CSS/Shell 等无 AST 的产物），TS/JS AST 测试不适用。
**Evidence**: 本次蓝队最初用 `card.dataset.anchor = anchorId` / `card.dataset.state = 'new'` / `card.dataset.commentId = cid`，C6 契约要求 `data-anchor` 等字面存在；QA 轮次 1 Tier 0 红队 `必须含 data-anchor 字面` 测试 ❌ 失败。auto-fix 阶段 1 行替换 → `card.setAttribute('data-anchor', anchorId)` 等 → 36/36 通过。修复 commit 4d42d4c。Tier 1.5 grep 计数：`data-anchor` 字面 1 / `data-state` 字面 2 / `data-comment-id` 字面 1（修复后），== 0（修复前 — 仅 dataset.X JS 属性访问形式）。

### [2026-05-14] 事件委托双 listener 冲突：模板 JS 在 [data-choice] 守卫命中后立即 stopImmediatePropagation
<!-- tags: event-delegation, stopimmediatepropagation, click-handler, helper.js, autopilot, plan-review, dual-listener, pollution-defense -->
**Scenario**: autopilot visual-companion 的 server.cjs 自动把通用 `helper.js` 注入到模板 `</body>` 之前。helper.js 在 `document` 上委托监听 `[data-choice]` click，发的 payload **不含**新加的扩展字段（如 comments[]）。新版模板内嵌 JS 也需要监听 `[data-choice]` 来组装含扩展字段的完整 payload。两个 listener 都跑会让 server.cjs `appendFileSync` 落两行 events，`wait-decision.sh` tail 出第一行（无扩展字段）后立即退出 → 扩展数据丢失，调用方不知情。这是 [[multi-placeholder-replace-order]]（多占位符模板顺序敏感）在**事件分发层**的同源问题：相同信号被两个 handler 各处理一次。
**Lesson**: 模板 JS handler 用「`closest('[data-choice]')` 守卫命中后**立即**调 `e.stopImmediatePropagation()`」拦截 helper.js 的后注册 listener。**不要**放到 closest 之前的"绝对第一行"——那会阻断 helper.js 中所有其他 click 路径（如 toggleSelect、菜单关闭等），破坏面更大。位置选择要精确："命中目标后立即"是最小破坏面解法。事件注册顺序依赖：模板内嵌 `<script>` 写在 `</body>` 之前，server 注入 helper.js 也在 `</body>` 之前但晚于模板 script —— **模板 JS 先注册，先触发，能 stopImmediatePropagation 阻断 helper.js**。这种「模板 JS 早 + helper 通用 + stopImmediatePropagation」组合是「不改 helper.js 也能让特定按钮走专用 payload」的标准方案。设计文档措辞要避免"绝对第一行"这类**绝对位置**词汇——qa-reviewer 会按字面比对 ❌，但移动代码会引入更大破坏面；正确措辞是"守卫命中后立即"。
**Evidence**: design 阶段 plan-reviewer Agent 主动识别这个风险（80-90 级），蓝队按 D5b 实现；contract-checker 验证 `stopImmediatePropagation` 出现 7 次（含 abort 路径）。用户在浏览器端到端验收时连续加 2 条评论 + 点「反馈」→ shell stdout 单一 JSON 行含完整 `comments[]` 数组（payload `{"type":"click","choice":"revise","comments":[{...},{...}],...}`），证明 helper.js 未重复触发。auto-fix 阶段还修正了设计文档措辞："第一行"→"`closest('[data-choice]')` 守卫命中后立即"，避免后人误按字面挪代码。

