### [2026-05-23] 工具产物的 git 管理边界用"目录拓扑即语义"而非"SKILL.md 规则提醒"
<!-- tags: autopilot, file-management, gitignore, topology-as-semantic, knowledge-runtime-split, layered-defense, commit-amnesia, doctor-dim, single-source-of-truth -->
**Background**: 用户痛点："AI 在 commit 时经常忘记保存 autopilot 的文件"。原因诊断：`.autopilot/` 顶层平铺混合"持久知识库"（decisions.md / patterns.md / index.md / domains/）+ "单次任务状态"（active / requirements/<slug>/state.md / brainstorm.md）+ "per-worktree session"（sessions/）+ "临时产物"（sub-agent / doctor-report.md / visual/）；`.gitignore` 仅有一条 `**/visual/`，导致 27 个 state.md 误入库长期累积；`autopilot-commit` SKILL.md 只有含糊一句"如果 .autopilot/ 有新增内容确认 CLAUDE.md 中有提及"，AI 在 `git status` 看到混合改动时无法判断。
**Choice**: `.autopilot/` 二级分层 → `knowledge/`（git 入库）+ `runtime/`（gitignored），配合"三层防御"：(1) **Layer 1 拓扑**：`.gitignore` 单条 `.autopilot/runtime/` 物理拦截 runtime 不出现在 `git status`；(2) **Layer 2 显式**：`autopilot-commit` 新增 5.c 子节强制检查知识库变更并显式 `git add`；(3) **Layer 3 巡检**：`autopilot-doctor` Dim 12 加子项 6「文件分类正确性」长期诊断 `.gitignore` 规则 + `git ls-files` 误入库检测。同时 `setup.sh` 内置幂等迁移逻辑（触发条件 `decisions.md 存在 && knowledge/ 不存在`），老用户首次升级自动迁移；`worktree.mjs` 新增 `cleanupStaleLinks()` helper 清理 v3.34 残留 symlink；本仓库一次性 `git mv` 知识库 + `git rm --cached` 27+ 误入库 runtime 文件。
**Alternatives rejected**: (1) **方案 A 不重组目录、仅扩展 .gitignore 黑名单 + SKILL.md 文字提示**——治标，AI 仍依赖记忆规则；27 个误入库文件需手工剥离。(2) **方案 C 深改命名（requirements/→runs/, sessions/→worktrees/）**——语义最准但 setup.sh / SKILL.md / 测试 ~20+ 处路径硬编码全改，性价比低。(3) **P1-P7 工具本身的结构性改造**（state.md 拆分 / brainstorm 复用 / 历史 design 跨任务复用等）——超出本次目标范围，用户决策为单独议题。
**Trade-offs**: 接受 27 个历史 state.md 显示为 deletion（git mv + git rm --cached 联合产生），换"runtime 永远不会再误入库"的结构性保证。代价：协作者拉取该 commit 后会看到大量 deletion——通过 commit message 显式说明 + 设计文档链接缓解。
**Evidence**: 64 文件改动（+390 / -10456），最关键的削减是把"知识库 + 任务状态混合"拓扑剥离为两个独立目录。红队 acceptance test `autopilot-file-mgmt.acceptance.test.sh` 12 断言全 PASS；QA 两轮（轮次 2 selective auto-fix 修了"version-sync TARGET_VERSION 硬编码盲区"——见 patterns.md [2026-05-09] Update [2026-05-23]）；commit `651ba81`，v3.34.1 → v3.35.0。
**Lesson**: "AI 经常忘记做 X" 类痛点的根治不应该是"在 SKILL.md 里加更多提醒"，而是改变拓扑/语义让 X 变成自然结果。本案"AI 忘记 commit autopilot 文件"的根因不在 commit skill 写得不够明确，而在 `.autopilot/` 顶层把"该提交"和"不该提交"混在一起——AI 看到混合改动必然要"判断"，判断就会出错。把判断从"AI 每次记规则"降级为"目录名即答案"，是结构性根治。同样思路适用于：所有"AI 每次需要记得做 X"类规则，先看能否用文件拓扑/命名/默认值消除"记忆需求"，再考虑写进 SKILL.md。

### [2026-05-23] 改 SKILL.md 前必须用 Skill Authoring Best Practice 5 条原则筛改进
<!-- tags: autopilot, skill, best-practice, anti-pseudo-optimization, refactor-discipline, terminology-network, reference-chain, false-improvement -->
**Background**: 用户启动 autopilot 任务"分析 QA 阶段顺序/并行度合理性"。fast 模式 design 阶段编排器初版方案识别 10 个改进点（P1-P10），含拆 Wave 1a/1b/1c、删 Wave 1.5 术语、合并三段前置、qa_scope 表格化、合并判定步骤等"看似优雅"的重构。HTML 评审 round 1 用户反馈"skill 优化非常难，容易劣化，要谨慎"。读 document/skill_best_practices.md 后，用 5 条原则（Concise / Smart / Consistent / Freedom / Over-org）逐项重审，**10 个改进点中 7 个被识别为伪优化**，最终仅保留 3 项最小变动（+3 行）。
**Choice**: 把"5 条原则筛改进"写入 [[skill-optimization-caution]] 记忆，并把判定矩阵作为 design 阶段重审模板：(1) Concise — 改动是否真的"去除已知信息"？格式变换（bullet↔表格）不算；(2) Smart — 是否解决"AI 不懂"？还是只让人类阅读更舒服？(3) Consistent — 改名/合并是否打破现有术语网络（红队 grep / 历史决策原文引用）？(4) Freedom — QA 判定是 low-freedom，合并简化检查清单 = AI 漏步骤；(5) Over-org — 引入新层级（Wave 1a/1b/1c）增加阅读维度，除非真有依赖矛盾否则不拆。每个改进点过 5 维矩阵，触犯任一条即视为伪优化。
**Alternatives rejected**: (1) 跟随首版 10 项改动方案 — 拆 Wave 1a/1b/1c 引入新术语层（违反 Consistent + Over-org）、合并步骤 1+2 让 AI 跳过格式检查（违反 Freedom）、删 Wave 1.5 术语断 [2026-05-16] 历史决策原文引用链（违反 Consistent）；(2) 只用"减少行数"作单一指标 — qa_scope 4 行 → 表格 7 行不是简化（违反 Concise 本质）；(3) 把重审作为 plan-reviewer Agent 第 7 维 — 拉远反馈链路，best practice 适合 fast 模式编排器内联自审而非另起 Agent。
**Trade-offs**: 设计阶段需多读 ~45KB 的 best practice 文档（首次进入此领域时），但换得对 SKILL.md 的改动从激进 +15 行重构降为保守 +3 行修复；避免引入"看似合理实则破坏术语网络/引用链/进程局部性"的劣化。代价：用户期望的"简化"诉求被部分驳回（如删 Wave 1.5 术语），需在评审时清晰解释"为什么不做"。
**Evidence**: 本次 P2/P3/P4/P6/P7/P8/P10 全部因 5 条原则筛除（state.md 重审矩阵记录每项触犯的维度）。最终 diff 仅 5 增 2 减全在 Phase: qa 区域；QA 10 个 Tier 1.5 场景中 7 个是"不变量护栏"（验证 9 个 Wave/Tier 术语、3 段独立前置、3 步判定、qa_scope 三档、⚠️ 复盘对照表均完整保留），全部 PASS。Phase: auto-fix 零改动。commit 2dd7557 v3.34.1。
**Lesson**: SKILL.md 的每条措辞往往与多份历史决策、红队测试 grep、跨阶段引用绑定，**改名/合并/重组多数是伪优化**，会断引用链/破坏术语网络/触发 AI 跳步骤。Claude 天然倾向于看到"冗余/不优雅"就提议重构，必须用 best practice 5 维矩阵作为外部检查点强制筛选。真正值得改的特征：修复事实矛盾、消除真实歧义、补充注脚澄清、删除真正死代码；其他 90% 的"优化提议"都属于格式偏好/术语重命名/过度组织，应主动放弃。同族条目：[[skill-minimal-change-append-only]]（[2026-05-09]）侧重单次改动的最小集原则，本条侧重事前用 5 条原则筛全部候选改动。

### [2026-05-17] skill 引入新概念优先业界对齐命名，禁止自创术语
<!-- tags: autopilot, skill, naming, terminology, industry-alignment, llm-friendly, mutation-testing, tautological-test, semantic-anchor, prompt-engineering -->
**Background**: autopilot e2e 优化任务首版方案命名为「反 no-op 自检」（中文自创 framing），preview 给用户审批时被用户驳回："我有很多概念并不理解"。深度业界调研后发现：同一概念在业内已有正式命名（Coulman 2016 "Tautological Test" / PIT-Stryker "Mutation Testing" / "Observable State Transition"），且这些术语在 sub-agent 训练语料中高频出现，识别度远高于自创词。
**Choice**: 重命名为「Mutation-Survival 自检（反 no-op）」，主标题用业界术语 + 括注中文 framing。reference 文件名 `test-mutation-survival.md` 而非 `test-no-op-resistance.md`，3 类反/正模式名（Stable Element Assertion / Observable State Transition / Negative Path Verification）全部业界对齐。Mental Mutation 5 问的 5 个 mutation 类型严格采用 PIT/Stryker mutator 命名（No-op / Conditional Flip / Boundary / Return-Value / State-Update Skip）。
**Alternatives rejected**: (1) 纯自创中文命名「反 no-op 自检」—— sub-agent 训练语料无 anchor，理解需逐字读 prompt 全文；用户也需被科普才能审批，AskUserQuestion 被驳回是直接证据。(2) 纯英文学术术语「Tautological Test Resistance」—— 中文用户阅读门槛过高，违反全局 CLAUDE.md「首选语言中文」。(3) 自创中文 + 英文括注「反空操作自检 (Anti-Tautological)」—— 中文翻译"空操作"对应 "no-op" 而非 "tautological"，语义错配。
**Trade-offs**: 业界术语首次出现时仍需对用户做 1 次科普（本次用了 case.txt 实际代码 before/after 对照表），但科普成本低于"使用自创术语 + 每次 sub-agent 调用都从 0 解释"。reference 文件中保留 5 类业界证据脚注（Coulman / arXiv / Meta / Playwright）增强术语可追溯性。
**Evidence**: 首版 AskUserQuestion preview 用「反 no-op 自检 / Tautological Test / Observable State Transitions」三个术语堆叠，用户驳回；改用 case.txt 完整代码做 5 个概念 before/after 科普后审批通过。业界证据：arXiv 2506.02954 MutGen / arXiv 2410.10628 LLM 测试 smell / Meta InfoQ 2026/01 / Coulman 2016 / Playwright 官方文档 5 处 SOTA 都用相同命名。final commit 741d2c9 reference 文件名 + prompt 字面契约全部业界对齐。
**Lesson**: prompt 工程的"命名一致性"不止是单一真相源（一处真相不重复 N 处文件），还包括"与 LLM 训练语料锚点对齐"——业界术语是免费的语义压缩，自创词是 prompt token 的浪费且推理负担。决策路径：引入新概念前先做业界 1-2 轮搜索（找 SOTA paper + 主流工具 mutator 命名 + 经典 anti-pattern 文献），存在公认术语即采纳；缺失才考虑自创。同时面向中文用户：业界术语作主标题、中文 framing 作括注，不要倒置。

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

### [2026-05-09] 修改脆弱 skill 时遵循"最小集 + 纯追加 + 可独立回滚"
<!-- tags: autopilot, skill, fragility, minimal-change, append-only, rollback, tdd-quality, defensive-edit -->
**Background**: 用户基于 relight 项目 c3648c2 回归（红队 22 PASS / 1 FAIL，PASS 大半是 if/else 包裹断言的假阳性 + CI 红 autopilot 不看）提出 7 条改进（P0-P3）。但用户明确"skill 非常脆弱，不要导致任何劣化"。需要在改进收益和回退风险间取舍。
**Choice**: 这次只做 P0+P3 共 4 处最小集，全部走"纯追加段落、零删除/零结构改动"的策略。具体：(1) red-team-prompt 加铁律段在 `## ⚠️ 铁律` 之后、`## 目标` 之前；(2) merge-phase 加 2.5 CI 验证步骤在已有 2 和 3 之间；(3) qa-reviewer 加 Section C；(4) anti-rationalization 加红队 Agent 视角段。明确不动 SKILL.md 主决策树（防 [2026-04-17] 后置章节跳读）、phase 流程顺序、frontmatter 字段、autopilot 默认 commit-only 行为。每处可独立 `git revert -- <file>` 撤销。
**Alternatives rejected**: (1) 一次性做全部 7 条 P0-P3 → 涉及 plan-reviewer/scenario-generator/auto-chain/红队 prompt 等 6+ 文件协调，劣化面最大；(2) 只做 P3 anti-rationalization → 漏掉本次 relight 实际触发的两条核心防线（红队铁律 + CI 不看）；(3) 在 SKILL.md 主决策树插新规则 → 历史教训明确指出后置章节会被跳读，新增主规则反而劣化。
**Trade-offs**: P1（跨语言契约消费者字段、破坏性变更扫描）和 P2（场景生成器输出直连 / auto-chain CI 信心）留给下一轮——relight 案例中这两条是次要原因，本轮不动不会重现核心回归。代价：下次再有 mac App 这种跨语言消费方被改时，红队仍可能漏掉。
**Evidence**: 4 处改动 git diff `references/` 0 删除行（场景 6 守门）；qa-reviewer Wave 2 给整体评分 97/100 / 0 critical / 0 important；29 个红队硬断言 PASS；merge step 2.5 dogfooding 在本地 commit 未 push 时正确触发降级跳过。
**Lesson**: 对脆弱 skill / prompt 的改动，"最小集 + 纯追加" 优于"完整重构"。每处改动独立成块、可独立回滚、可独立单测，比"一次到位的优雅设计"更安全。设计阶段先列"非目标"清单（明确不做哪些）能防止范围溢出。

### [2026-05-09] 引入新能力时优先复用现有内部基础设施，再考虑引入新栈
<!-- tags: autopilot, integration, dependency-discipline, infrastructure-reuse, plugin-design, html-review, visual-companion -->
**Background**: 想给 autopilot design 阶段步骤 4 加 HTML 浏览器评审路径，业内有现成方案 plannotator（Bun + React + 单文件 HTML 打包）可参考甚至直接用。
**Choice**: **不引入** plannotator 的 Bun + React 栈。复用 autopilot 自身的 `scripts/visual-companion/`（Node 原生 http + 手写 RFC 6455 WebSocket + helper.js click 事件捕获 + events JSONL 文件回流），只补 3 个文件（plan-review-template.html / wait-decision.sh / launch-plan-review.sh）+ 一次性 build-time 复制 marked.min.js（35KB MIT）。0 runtime 依赖，0 新增 npm 包。
**Alternatives rejected**: (1) 直接引入 plannotator monorepo —— Bun 不在 autopilot 用户日常环境，引入相当于强制依赖运行时；(2) 自己写 200 行正则 markdown 渲染 —— 表格/嵌套列表边界 case 多，不如 marked.js 35KB 一次到位。
**Trade-offs**: 复用既有基础设施时间成本 ~1.5h vs 引入 + 调通新栈 ≥1d；功能完整度对齐 plannotator 的 v1（用户主路径足够），段落级评论/截图上传等高级功能列入 future work。
**Evidence**: 17 个文件改动，1352 lines 新增（含 35KB marked.min.js + 数百行 HTML/CSS）；红队 22 项断言全 PASS；端到端 approve / revise+中文 feedback 全验证通过。
**Lesson**: 评估"引入新框架/库"前，先盘点项目内是否已有可复用的中性能力（HTTP server、事件总线、文件 IO 抽象）。能 0 依赖就 0 依赖——尤其对插件类项目，每个 runtime 依赖都会传染到所有用户。

### [2026-05-06] Plugin hooks.json 不接收 `claude -w` 派发的 WorktreeCreate 事件
<!-- tags: claude-code, plugin, hooks, worktree, event-dispatch, sessionstart, fallback -->
**Background**: autopilot plugin 在 `plugins/autopilot/hooks/hooks.json` 注册了 WorktreeCreate hook 做 worktree 初始化（symlink + pnpm install + local-config.json）。用户跑 `claude code -w <name>` 创建 worktree 时，hook 完全没触发——worktree 是裸的，缺 node_modules / .env / local-config.json，`.autopilot` 是 git 检出实仓而非符号链接。
**Choice**: 在 plugin hooks.json **同时**注册 `SessionStart` hook 作为兜底。每次 session 启动检测 cwd 是否为未配置 worktree（`.git` 是文件 + `.autopilot` 不是 symlink 或缺 node_modules），是就调 `worktree.mjs repair`；主仓库 / 已配好 worktree silent exit 保证幂等。
**Alternatives rejected**: (1) 让用户在 `~/.claude/settings.json` 注册 WorktreeCreate hook —— 需硬编码 plugin 缓存路径，每次 plugin 升级需更新；(2) 修改 worktree.mjs 让脚本主动轮询 —— 与 hook 模型背离，复杂度高。
**Trade-offs**: SessionStart 每次 session 都触发 → 每次启动多几毫秒（已配好场景 silent exit）；裸 worktree 首次 session 卡几十秒装依赖 vs 用户拿到不可用 worktree，前者可接受。
**Evidence**: hook wrapper + log 对照实证（详见 commit 27289dc 的 HANDOFF 文档）—— plugin hooks.json 的 wrapper 0 字节日志，user-settings 的同 wrapper 收到完整 stdin payload。GitHub issue [#36205](https://github.com/anthropics/claude-code/issues/36205) 已报但只覆盖 settings.json 场景，未提到 plugin hooks.json gap。
**Lesson**: Plugin hook 事件派发**不是覆盖所有 events**——写 plugin hook 时不能假设 hooks.json 注册的 event 都会被触发，必须用实证验证（wrapper + log）。已知 SessionStart 在 plugin hooks.json **会**派发，可作为高频兜底事件。

### [2026-05-08] Design 阶段移除 Plan Mode，用 AskUserQuestion 替代 ExitPlanMode 审批
<!-- tags: autopilot, plan-mode, design, AskUserQuestion, approval-gate, simplification -->
**Background**: design 阶段依赖 Claude Code 的 EnterPlanMode/ExitPlanMode 实现"探索→设计→审批"流程。deep 模式下需要先在 Plan Mode 外做 brainstorm（Phase A），再进入 Plan Mode 做 plan（Phase B），实质上同一件事做了两遍。Plan Mode 的写入禁止作为安全网已不再必要（AI 指令遵循能力足够）。
**Choice**: 完全移除 Plan Mode 依赖。所有设计模式统一为"探索 → 写设计文档到状态文件 → 审查 → AskUserQuestion 审批"。deep 模式合并为单流程（brainstorm + design 一气呵成）。审批门从 ExitPlanMode 改为 AskUserQuestion（通过/修改/放弃 三选一）。
**Alternatives rejected**: (1) 只在 deep 模式去掉 Plan Mode 而标准模式保留——导致两套逻辑并存，维护成本不降；(2) 把 brainstorm 合并进 Plan Mode 内部——Plan Mode 禁止 Write，brainstorm.md 写入需要 workaround。
**Trade-offs**: 失去 Plan Mode 提供的写入保护（理论上 AI 可能在设计阶段误写文件）；换来更简洁的流程和更小的 SKILL 文件（减少 ~36 行）。设计文档直接写入状态文件消除了 plan file → state file 的复制步骤。
**Lesson**: 当 AI 能力提升使得某个机制级保护变得冗余时，应该果断移除而非继续维护兼容代码。AskUserQuestion 是一个足够好的审批门替代，因为它保留了用户选择权且无需模式切换开销。

### [2026-05-05] Lint / 健康检查能力优先 AI 语义判断而非正则脚本
<!-- tags: autopilot, doctor, lint, ai-judgment, knowledge-engineering, design-principle -->
**Background**: 知识库 Lint 设计需要识别"过拟合条目"（如硬编码 UI 高度的具体数值而非"动态读取 UI 高度"原则）。最初方案是写独立脚本用正则匹配版本号 / 行号 / 文件名列表等模式做检测。
**Choice**: Lint 能力通过 AI Agent 阅读知识库文件做语义评估，集成到 autopilot-doctor 作为 Wave 2 串行 AI 判断维度，不写脚本。
**Alternatives rejected**: (1) 独立 Lint 脚本（Node.js / Shell）—— 正则无法识别"硬编码具体数值是过拟合"vs"抽象原则是 principle"的语义差异，会大量误报或漏报；(2) 独立 Skill 入口（如 `/autopilot:knowledge-lint`）—— 增加用户认知面，集成既有维度入口更聚合。
**Trade-offs**: AI 判断比脚本慢且消耗更多 token，但能识别脚本无法捕获的语义模式。原则推广：所有"评分 / 审查 / 质量判断 / 模糊匹配"类功能默认选 AI Agent，只有"格式校验 / 性能敏感 / 输出可被 AI 后处理的纯数据收集"才选代码。

### [2026-05-04] Per-worktree 会话隔离通过 sessions/<name>/ 子目录实现
<!-- tags: autopilot, worktree, session-isolation, architecture -->
**Background**: worktree.mjs 将整个 `.autopilot/` 符号链接共享到所有 worktree，导致 active 指针和 requirements 全局共享，旧任务状态干扰新 worktree。
**Choice**: active 指针和 requirements 目录改 per-worktree 隔离，知识文件（decisions/patterns/index）保持共享。非 worktree 沿用 `.autopilot/active`，worktree 使用 `.autopilot/sessions/<name>/active`。worktree.mjs remove() 自动清理 session 目录。
**Alternatives rejected**: (1) active 文件编码 worktree 名称 — 需额外解析，增加复杂度；(2) 完全隔离 `.autopilot/` — 知识文件无法共享

### [2026-03-21] 知识工程采用三层 Progressive Disclosure 而非单层扩展
<!-- tags: knowledge, architecture, progressive-disclosure -->
**Background**: 知识工程 v2.6.0 使用两个平面文件（decisions.md + patterns.md），随着知识积累会导致全量加载效率下降。需要升级架构。
**Choice**: 三层 Progressive Disclosure — index.md 索引层 → 全局文件内容层 → domains/ 领域分区层
**Alternatives rejected**: (1) 直接扩展文件数量（无索引层，加载时仍需全量扫描）；(2) 数据库存储（过重，违背 Markdown + Git 的简洁哲学）；(3) YAML frontmatter 元数据（增加解析复杂度，AI 处理 HTML comment tags 更自然）
**Trade-offs**: 索引层增加了维护成本（每次提取需同步 index.md），但换来按需加载的精确性。向后兼容通过 fallback 机制保证。

### [2026-03-26] doctor Dim 1 测试金字塔分层评估优于文件计数
<!-- tags: autopilot, doctor, testing, test-pyramid, scoring -->
**Background**: ai-todo 项目有 287 个单元测试文件但 0 个 API Route 测试和 0 个 E2E 测试，doctor Dim 1 仍给 9-10 分。根因是 Dim 1 只检查文件数量不区分测试类型。
**Choice**: 引入测试金字塔三层检测（L1 单元 + L2 API/集成 + L3 E2E），仅有 L1 最高 6 分，需两层以上覆盖才能 7+。
**Alternatives rejected**: (1) 单独新增 Dim 11（E2E 测试），增加维度会打破权重平衡；(2) 在 Dim 5 CI 中检测，CI 维度关注 pipeline 不关注测试类型。
**Trade-offs**: 已有项目得分会降低（破坏性变更），但这正是目标——暴露之前隐藏的测试层次缺口。N/A 处理（无 API 路由的项目 L2 不降分）避免误伤。

### [2026-03-27] SKILL.md Phase 分片优于状态文件索引
<!-- tags: autopilot, skill, progressive-disclosure, token-optimization -->
**Background**: autopilot SKILL.md 643 行超过 500 行最佳实践限制，需要优化 token 开销。考虑了两个方向：(1) SKILL.md 拆分为 phase 参考文件；(2) 状态文件引入多层索引。
**Choice**: SKILL.md Phase 分片（643→106 行核心路由 + 5 个 phase 文件按需加载），stop-hook prompt 注入阶段文件路径引导。
**Alternatives rejected**: 状态文件多层索引——索引和内容在同一文件中无法物理隔离（不像 knowledge/index.md 是独立文件），AI 做 Read 就全拿到了，索引形同虚设。维护成本（每次更新索引的额外 Edit）> 收益。
**Trade-offs**: 每次 phase 切换增加 1 次 Read 调用加载 phase 文件，但系统提示减少 ~520 行，延缓上下文压缩，净效果正向。

### [2026-04-03] merge 阶段 Agent 化优于 Skill 调用
<!-- tags: autopilot, token-optimization, merge, agent, cost -->

### [2026-04-10] 运行时文件统一迁移到 .autopilot/ 而非逐个豁免
<!-- tags: autopilot, file-path, permission, claude-code, migration -->
**Background**: Claude Code 将 `.claude/` 硬编码为受保护目录，即使 bypassPermissions 开启仍弹权限确认。豁免列表仅含 commands/agents/skills/worktrees 四个子目录。autopilot 状态文件、诊断报告、worktree-links 三个运行时文件在 `.claude/` 下反复触发确认，严重影响自动驾驶体验。
**Choice**: 全部迁移到 `.autopilot/`（与知识库同级），setup.sh 添加旧路径自动迁移逻辑。知识库迁移条件从检查目录存在改为检查 `index.md` 存在（避免 mkdir -p 创建空目录后迁移被跳过的协调 bug）。
**Alternatives rejected**: (1) PreToolUse Hook 自动 approve（绕过安全机制，不是正解）；(2) 只迁移状态文件（worktree-links 和 doctor-report 同样触发弹窗，不彻底）
**Trade-offs**: 需要存量用户迁移（setup.sh 自动处理），SKILL.md 中 ~15 处路径引用需同步更新。但一次性迁移后彻底消除权限弹窗，长期收益远大于短期成本。
**Background**: 成本分析显示 autopilot 单日消耗 100M tokens（$809.73），其中 merge 阶段的 Skill: autopilot-commit 调用单次消耗 3-5M tokens——因为在编排器主线程运行，继承了完整的设计文档、QA 报告、所有工具调用历史等父上下文。93.35% 的 tokens 是 cache_read。
**Choice**: merge 阶段改用 Agent 工具启动 commit-agent（model: sonnet），Agent 获得独立的新鲜上下文窗口，只包含显式传入的 git diff + 设计目标 + commit 规则。同时新增 stop-hook merge 分支注入 Agent 路径提醒。QA 报告压缩：历史轮次压缩为一行摘要，只保留最新完整报告。
**Alternatives rejected**: SKILL.md 路由器瘦身（572→85 行）——之前尝试过出过问题，不再重复。
**Trade-offs**: Agent 无法执行需要用户交互的操作（代码测验、ai-todo 同步），但主链路模式下这些步骤已跳过。独立 /autopilot commit 仍走 Skill 路径不受影响。预估综合日总成本降低 ~40-60%。

### [2026-05-07] Sub-agent 数量是 token 优化的真正杠杆，不是 SKILL.md 加载
<!-- tags: autopilot, token-optimization, sub-agent, cold-start, qa-reviewer -->
**Background**: 第三轮 token 优化分析近 5 天 Top 5 autopilot session（共 430.2M token，最高单 session 116.8M / 1119 turns）。数据显示 cache_read 占 95-99%，意味着 SKILL.md 重复加载已被 prompt cache 充分覆盖。前两轮优化（2026-03-27 SKILL.md Phase 分片、2026-04-03 merge Agent 化）方向收敛，但 token 仍快速消耗。
**Choice**: 把 qa 阶段的两个并行 reviewer Agent（design-reviewer + code-quality-reviewer）合并为一个 qa-reviewer Agent，新建 `references/qa-reviewer-prompt.md` 同时承担 Section A 设计符合性 + Section B 代码质量与安全。每 run 节省 ~500K-1M token（一次 Agent cold start + 重复 Read 同一批变更文件）。
**Alternatives rejected**: (1) 继续抽离 SKILL.md 内容到 references — 已被 prompt cache 覆盖收益小；(2) 删除 plan-reviewer 或验收场景生成器 — 关乎设计质量，激进改动风险高；(3) 强制 turn 数量上限 — 用户主动 revise 是正当行为不应技术性阻断。
**Trade-offs**: 失去两个独立视角的"双盲交叉验证"（设计 vs 代码质量），但实际两个 Agent 都在审查同一批代码，关注点互补不重叠。
**Lesson**: 优化 token 不能只看「文件大小 / 加载频次」这种容易测量的指标——prompt cache 已经把这些重复成本拍平。真正的杠杆是「无法被 cache 共享的 fresh context」——每个 sub-agent 都是一次独立的 cold start，且都要 Read 同一批变更文件。优化的优先级应该是「减少 sub-agent 调用次数」 ＞「减少单 Agent prompt 大小」 ＞「减少 SKILL.md 文件大小」。

### [2026-05-07] 双轨道 fast track：显式 flag + hook 自动检测互为兜底
<!-- tags: autopilot, token-optimization, fast-mode, dual-track, self-correction, hook -->
**Background**: 优化 sub-agent 数量是 token 关键杠杆（详见同日 sub-agent 决策条目），但单一触发机制各有局限：纯 user flag 依赖人工判断会漏覆盖；纯 hook 自动只能后置生效（implement 完成后才能拿到 diff），无法砍 design 阶段的 plan-reviewer / scenario-generator。
**Choice**: 双轨道并行 — 轨道 A 显式 `fast_mode` flag 由 setup.sh 写入 frontmatter（design 阶段砍 plan-reviewer + scenario-generator，qa 阶段砍 qa-reviewer）；轨道 B stop-hook `detect_smoke_eligible` 按 git diff 体积自动设 `qa_scope: smoke`（仅 qa 阶段砍 qa-reviewer）。两轨道并行：用户标 fast 但实际大任务 → B 检测 diff 超阈值时降级 fast_mode 为 false；用户没标但任务实际小 → B 自动兜底。
**Alternatives rejected**: (1) 纯 user flag — 漏覆盖未标注的小任务；(2) 纯 hook 自动 — 砍不到 design 阶段串行 sub-agent；(3) 引入新 `mode` 值 — 破坏 `mode`（结构维度 single/project）vs effort 维度的正交性，应作为独立字段（与 `auto_approve` / `plan_mode` 同 pattern）。
**Trade-offs**: 多 1 个 frontmatter 字段 + 1 个 CLI flag。架构复杂度可控（复用现有 `qa_scope` 字段加 "smoke" 取值）。预期 sub-agent 数 7→4，token -30%~40%，wall-clock -30%。
**Lesson**: token / 速度优化的"显式入口 + 自动兜底 + 自我修正"三件套是健壮模式。任何依赖单一信号（用户判断 / 静态规则 / 运行时检测）的优化都有覆盖盲区，组合可形成互补。

### [2026-05-07] AI 自觉的优化机制不可靠，结构性优化必须由 hook 硬编码兜底
<!-- tags: autopilot, hook, automation, ai-discipline, stop-hook, hard-coded -->
**Background**: SKILL.md 第 469 行（旧版）声明「写入前先将所有历史轮次报告压缩为一行摘要」，依赖 AI 在每次写 QA 报告前自觉执行。实际审查 stop-hook.sh 发现 `grep -n "压缩\|历史轮次" stop-hook.sh` 0 matches——完全没有自动化机制。多轮 QA 后状态文件膨胀至 7-15K tokens，30 轮迭代每次 phase 入口 Read 都付出此成本（累计 450K 浪费）。
**Choice**: 在 `plugins/autopilot/scripts/stop-hook.sh` 新增 `compress_qa_report` 函数（awk 状态机识别 `## QA 报告` 区域 + `### 轮次 N` 块），在 phase 转入 qa 或 auto-fix 时自动调用，幂等可重入。SKILL.md 措辞同步从「AI 写入前先压缩」改为「stop-hook 已自动压缩，AI 仅追加新轮次」。
**Alternatives rejected**: 加更强的 SKILL.md 警告语 + 防合理化提醒——本质还是依赖 AI 自觉，已被实践证伪。
**Trade-offs**: shell + awk 解析 markdown 不如 AI 智能（边缘格式可能漏处理），但「确定执行 + 简单逻辑」比「依赖自觉 + 复杂逻辑」可靠得多；幂等设计让边缘 case 失败也不会导致状态破坏。
**Lesson**: 凡是「依赖 AI 在每个循环正确执行」的优化机制，都应当评估是否能下沉到 hook / 工具层硬编码。AI 在长 session / 多任务交错 / 注意力分散时会遗忘软约束；而 hook 是确定性执行。这条原则适用于：状态压缩、文件清理、版本同步、变更日志追加等机械性操作。

### [2026-05-07] Stop hook 利用 transcript_path 检测后台 sub-agent 等待状态
<!-- tags: autopilot, stop-hook, sub-agent, transcript, token-optimization, hard-coded, implement -->
**Background**: implement 阶段主 agent 启动并行蓝队/红队 sub-agent (5-10 分钟)，自身无事可做就结束响应。Stop hook 此前完全感知不到后台 sub-agent，照常按 phase 注入 implement 阶段的"红蓝对抗铁律"长 prompt → 主 agent 被唤醒，看到指引但 sub-agent 还在跑只能输出"还在等"再次结束响应 → Stop hook 又触发又注入 → 短时间连续 3-5 次无效 iteration（error.txt 实证 iter 3→4→5→6 全空转），每次主 agent 唤醒消耗大量 token + 污染上下文。
**Choice**: 在 `stop-hook.sh` 利用 stdin JSON 已有但此前未使用的 `transcript_path` 字段，新增 `has_pending_subagents` 函数：`tail -c 2MB` + jq 解析主线程（`isSidechain==false`）启动的 Agent/Task `tool_use` id 集合 A，对比 `tool_result.tool_use_id` 集合 R，差集即未完成 sub-agent。守卫**仅在 phase=implement** 时启用（保守取向，design/qa/merge 阶段 sub-agent 都是短时不会触发本问题），pending 时 `exit 0` 静默放行不递增 iteration。
**Alternatives rejected**: (1) 注册 SubagentStop hook — Claude Code 在 sub-agent 完成时已自动让 tool_result 入流激活主 agent，注册 SubagentStop 对主 agent 唤醒无直接增量；(2) 主 agent 写 `awaiting_subagents` 状态字段 — 违反"hook 硬编码兜底，不依赖 AI 自觉"原则（同日另一条决策确立的设计原则）；(3) 主 agent 启动 sub-agent 后用 Monitor 阻塞等待 — error.txt 显示 AI 自己尝试过此方案，但 Monitor 也是后台任务、主 agent 仍 idle 触发 stop-hook，不解决问题。
**Trade-offs**: 多 ~25 行 bash + jq 解析（实测 5MB 文件 < 2s，stop-hook 10s 总超时内充裕）；transcript 损坏/jq 失败时降级返回 1（视为无 pending 走原路径），优先避免 autopilot 永久卡死而非追求精确性。仅 implement 阶段启用 = 未来若 design/qa/merge 也出现长时间 sub-agent 等待需扩展 phase 列表。
**Lesson**: Claude Code Hook 的 stdin JSON 提供 `session_id`/`cwd`/`transcript_path` 等丰富上下文，原作者可能只用了其中一部分。当 hook 决策依赖"运行时进行中状态"而非"持久化文件状态"时，transcript 解析是 zero-dependency 的可靠信号源——它是 Claude Code 写入的事实记录，不需要主 agent 配合写状态字段。tail + jq 集合差是处理大 JSONL 的高效模式。

### [2026-05-08] Design 阶段默认含 brainstorm Q&A，--fast 复用为快速通道
<!-- tags: autopilot, brainstorm, design, fast-mode, default-inversion, simplification, yagni -->
**Background**: v3.20.0（9c770a8 之后）design 阶段默认走 standard 路径——直接写设计文档无 Q&A 探索，仅 `--deep` flag 显式触发交互式 brainstorm。用户实际诉求"模糊任务希望默认有 brainstorm"在显式 flag 下经常错过。同时四档决策树（auto_approve / plan_mode:deep / fast_mode / standard）心智模型偏重。
**Choice**: 默认值反转——空 `plan_mode` 即触发 brainstorm + 完整 sub-agent 审查；`--fast` 语义扩展为「跳过 brainstorm + 砍 scenario-generator + 砍 plan-reviewer」一档式快速通道；`--deep` flag 保留为兼容期 deprecation（行为同默认），plan_mode 字段事实弃用。决策树从 4 档简化为 3 档（auto_approve / fast_mode / 默认）。
**Alternatives rejected**: (1) 方案 A 完全删除 plan_mode 字段 — 与 9c770a8 简化方向冲突，"明确意图任务"无 escape hatch；(2) 方案 B 新增 `--quick` flag 单独控制"跳过 brainstorm" — flag 数量膨胀，中间档"无 brainstorm + 严格审查"实际低频；(3) 方案 C 编排器自动判断意图清晰度 — 违反知识库已沉淀的 "AI 自觉机制不可靠" pattern。
**Trade-offs**: 接受语义耦合——「无 brainstorm + 完整 sub-agent 审查」中间档消失。用户对明确小任务必须用 --fast（同时砍审查）；如未来出现"明确意图但需要严格审查"高频需求再单独加 --quick 不晚。
**Evidence**: v3.20.0→v3.21.0；setup.sh / stop-hook.sh / SKILL.md / state-file-guide.md 同步；3 个现有验收测试更新 + 1 新增 brainstorm-default.acceptance.test.sh（17 assertion / 10 核心契约）。Tier 1.5 三个真实场景（默认 / --fast / --deep 兼容）全 PASS。
**Lesson**: 当用户提议"默认化某行为 X"时，不要直接照做——先评估 X 当前的使用模式分布，复用现有 escape hatch flag 通常优于新增 flag。本次 plan_mode 字段事实上只有 2 个有效值（""空 / "deep"），是 boolean 用 string 表达，本身就有简化空间——这种"语义冗余字段"重构时可顺势清理为 dead field（保留兼容期防止历史 state.md 解析报错）。关联 9c770a8 形成「Plan Mode 移除 → brainstorm 默认化」决策链，方向一致：把通用流程做减法、把高质量行为提升为默认。

### [2026-05-14] per-user 偏好持久化采用 `~/.autopilot/` 形成与项目级 `.autopilot/` 的命名对称
<!-- tags: autopilot, prefs, persistence, user-level, project-level, naming-convention, dotfile, single-source-of-truth -->
**Background**: plan review 浏览器审批引入「提交后自动关闭」开关需要跨多次 autopilot 任务、跨项目、跨 worktree 持久化偏好。candidate 位置三选一：用户级 dotfile / Claude plugin 数据目录 / XDG 规范目录。同时 visual-companion server 每次启动 PORT 随机，浏览器端 localStorage 在 `127.0.0.1:RANDOM_PORT` 之间不能跨源复用，废客户端持久化方案。
**Choice**: `~/.autopilot/prefs.json` —— 与项目级 `.autopilot/` 知识库形成「per-user 全局偏好 + per-repo 本地知识」的命名对称；单一写入口（Node 端 server 进程通过 `prefs.cjs.setPref` 落盘），损坏 JSON / 文件缺失 / 字段缺失三层 fallback 到默认值，永不让审批 UI 因偏好文件损坏白屏。
**Alternatives rejected**: (1) `~/.claude/autopilot/prefs.json` — 与 `~/.claude/plugins/cache/` 共一级，cache 同步流程容易把"只读副本"语义覆盖到"可写偏好"，制造同步事故；(2) XDG `~/.config/autopilot/` — macOS 用户对 `~/.config` 习惯弱，对 dotfile 清理工具反而更不兼容；(3) localStorage 浏览器端 — 随机端口让同源策略失效，跨会话不可复用。
**Trade-offs**: dotfile 在 cloud sync 工具（Dropbox/iCloud）下默认不会同步 `~/.autopilot/`，跨机器需手动 symlink——可接受，偏好本身极简（单 boolean），用户首次访问设一次即可。

### [2026-05-17] brainstorm 抽离为独立 skill：解决"指令优先级"而非"主 SKILL 行数"
<!-- tags: autopilot, brainstorm, skill-extraction, indication-priority, references-postpone, hard-gate, superpowers, design-prediction -->
**Background**: 用户反馈"brainstorm 执行效果没和 skill 对齐都阉割了 + 主 SKILL 太大"，提议抽离 brainstorm 为独立 skill。根因诊断：`patterns.md` 2026-04-17「SKILL.md 决策树中后置章节会被 AI 跳过」直接命中 —— brainstorm-guide.md 在 references 后置位置必然被 AI 部分跳过。设计时预估"净减 ~64 行"。
**Choice**: 抽离独立 skill `autopilot-brainstorm`，主 SKILL 通过 `Skill: "autopilot-brainstorm"` 工具显式委托。新 skill 借鉴 superpowers brainstorming 风格三件套：`<HARD-GATE>` + Anti-Pattern「这太简单不需要 brainstorm」 + 强制 Checklist。职责严格限定：只做 Q&A + 方案共识，输出 `$TASK_DIR/brainstorm.md` 后交回主 SKILL（plan-reviewer / 审批门 / state.md 写入留在主 SKILL，避免 SSOT 违反让 fast/auto_approve 路径复用）。
**Alternatives rejected**: (1) 不抽离主 SKILL 前置 brainstorm —— 主 SKILL 反涨到 ~720 行与瘦身诉求冲突；(2) 抽离 + 同步拆所有 phase 文件 —— 改动 5x，违反「最小集 + 可独立回滚」；(3) 顺手把 plan-reviewer 也抽 skill —— 反优化（plan-reviewer 已用 Agent 工具，fresh context 隔离，抽 skill 反而倒退到主线程继承父上下文，对照 2026-04-03 决策）。
**Trade-offs**: 主 SKILL 实际净减 **2 行**（644→642），距离设计预估 ~64 行偏差 32 倍 —— **预估错误根因**：brainstorm-guide.md 89 行内容从未内嵌主 SKILL，本来就是独立 reference 文件，主 SKILL 中只有 4 行引用链接。R3 acceptance test（<600 行）持续 FAIL 属 pre-existing 红线，未本次解决，作为 follow-up 任务记录。
**Lesson**: 抽 skill 有 2 个独立价值维度需分别评估：(1) **指令优先级**（description 触发 + HARD-GATE 让 AI 全神贯注）—— brainstorm 抽离对此有效；(2) **主 SKILL token / 行数节约** —— 仅当被抽内容真实占据主 SKILL 行数时才有效。若被抽内容已是 reference 文件（只在主 SKILL 留链接），抽 skill 对维度 (2) 几乎零贡献。设计阶段判断"抽 skill 能减多少行"必须 **grep 计行**（grep `references/X.md` 出现位置 + 估实际占行）而非按 reference 文件大小估算。本次预估失准未被 plan-reviewer 捕获，因为审查只看"任务列表完整性"不验证"行数预估准确性"—— 未来 plan-reviewer 可加一条："设计承诺的量化指标（行数 / 性能数 / token 数）是否有可执行的事前验证命令？"
**Evidence**: 17 个文件 +921/-141；新 skill `autopilot-brainstorm/SKILL.md` 100 行；主 SKILL 644→642（净减 2）；红队 acceptance 17/17 PASS（C1-C10 + B1-B4）；contract-checker PASS（mismatches 空）。commit `7b003c0`。R3 follow-up：deep 削主 SKILL 需走原方案 C 抽全 phase 文件（design 段 164 行 → 步骤 3+4+5b 共 80 行可抽），保守减 ~67 行可跨过 600 红线，激进减 ~100 行到 ~540 行。

### [2026-05-19] plan-review HTML 演进走"扩展点"路径而非改 SKILL.md
<!-- tags: autopilot, plan-review, skill-fragility, extension-point, decoupling, html-template, sso-isolation, launch-script -->
**Background**: 用户提需求"优化 plan review html，左侧增加目录"时强调"skill 非常脆弱，最小化改动"。探索发现 SKILL.md 调用 `launch-plan-review.sh` 仅一处 Bash 命令；`launch-plan-review.sh` 自治完成 server 启动、内容提取、HTML 渲染、浏览器打开、决策等待、server 关闭全流程；HTML 模板本身是独立资产。
**Choice**: 把 plan-review HTML 体系视为"扩展点架构"——HTML/CSS/JS 演进（包括加 TOC、改阅读体验、调样式）一律只动 `plan-review-template.html` 一个文件，不触碰 SKILL.md / launch-plan-review.sh / helper.js / server.cjs / frame-template.html / prefs.cjs。设计阶段把这条作为契约规约「副作用清单」明确入档，红队产出独立断言（验收场景 9）证明 `git diff --name-only` 仅含目标文件。
**Alternatives rejected**: (1) 服务端预生成 TOC 注入（Python 端 markdown 解析）—— 改动 launch-plan-review.sh 引入新依赖，扩大耦合面；(2) 把 TOC 逻辑拆到独立 JS 文件让 launch-script 注入 —— 模板已采用全内联（内嵌 marked.min.js + 样式 + JS），新建外部依赖反而打破现有内聚约定。
**Trade-offs**: 单文件容易膨胀（本次 1321→1652 行 +334），可读性靠 CSS 分段注释维护；但相比触碰多个 skill 资产带来的脆性风险（SKILL.md 改一行重写整段、launch-script 协议变更需同步红队全部）这种集中度是值得的。
**Lesson**: 设计 skill 时，把"易变的 UI / 表达层"通过"自治脚本入口"与 skill 主流程隔离，是降低 skill 脆性的有效架构手段。需求落到 UI 层时，skill 改动半径应该是 0；只在 UI 调用协议变化（脚本签名、stdout 格式）时才触及 skill。判断方式：对照 SKILL.md 中调用入口的 Bash 命令，如果新需求不改变命令的输入/输出契约，那么 skill 改动量应当为 0。
**Evidence**: commit `9b936f6`，`git diff --name-only HEAD~1` 仅含 `plan-review-template.html` + 新增红队测试 + 版本同步文件 + .autopilot 流程产物。SKILL.md / launch-plan-review.sh / helper.js / server.cjs / frame-template.html / prefs.cjs / marked.min.js 均 0 行改动。验收场景 9 红队 31 个 grep 断言全 PASS。
