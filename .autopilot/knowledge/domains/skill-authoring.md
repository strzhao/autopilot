<!-- domain: SKILL.md 改动纪律 / 命名 / best-practice / progressive-disclosure / 版本同步 -->
# Skill Authoring

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

### [2026-05-08] Design 阶段移除 Plan Mode，用 AskUserQuestion 替代 ExitPlanMode 审批
<!-- tags: autopilot, plan-mode, design, AskUserQuestion, approval-gate, simplification -->
**Background**: design 阶段依赖 Claude Code 的 EnterPlanMode/ExitPlanMode 实现"探索→设计→审批"流程。deep 模式下需要先在 Plan Mode 外做 brainstorm（Phase A），再进入 Plan Mode 做 plan（Phase B），实质上同一件事做了两遍。Plan Mode 的写入禁止作为安全网已不再必要（AI 指令遵循能力足够）。
**Choice**: 完全移除 Plan Mode 依赖。所有设计模式统一为"探索 → 写设计文档到状态文件 → 审查 → AskUserQuestion 审批"。deep 模式合并为单流程（brainstorm + design 一气呵成）。审批门从 ExitPlanMode 改为 AskUserQuestion（通过/修改/放弃 三选一）。
**Alternatives rejected**: (1) 只在 deep 模式去掉 Plan Mode 而标准模式保留——导致两套逻辑并存，维护成本不降；(2) 把 brainstorm 合并进 Plan Mode 内部——Plan Mode 禁止 Write，brainstorm.md 写入需要 workaround。
**Trade-offs**: 失去 Plan Mode 提供的写入保护（理论上 AI 可能在设计阶段误写文件）；换来更简洁的流程和更小的 SKILL 文件（减少 ~36 行）。设计文档直接写入状态文件消除了 plan file → state file 的复制步骤。
**Lesson**: 当 AI 能力提升使得某个机制级保护变得冗余时，应该果断移除而非继续维护兼容代码。AskUserQuestion 是一个足够好的审批门替代，因为它保留了用户选择权且无需模式切换开销。

### [2026-03-27] SKILL.md Phase 分片优于状态文件索引
<!-- tags: autopilot, skill, progressive-disclosure, token-optimization -->
**Background**: autopilot SKILL.md 643 行超过 500 行最佳实践限制，需要优化 token 开销。考虑了两个方向：(1) SKILL.md 拆分为 phase 参考文件；(2) 状态文件引入多层索引。
**Choice**: SKILL.md Phase 分片（643→106 行核心路由 + 5 个 phase 文件按需加载），stop-hook prompt 注入阶段文件路径引导。
**Alternatives rejected**: 状态文件多层索引——索引和内容在同一文件中无法物理隔离（不像 knowledge/index.md 是独立文件），AI 做 Read 就全拿到了，索引形同虚设。维护成本（每次更新索引的额外 Edit）> 收益。
**Trade-offs**: 每次 phase 切换增加 1 次 Read 调用加载 phase 文件，但系统提示减少 ~520 行，延缓上下文压缩，净效果正向。

### [2026-05-08] Design 阶段默认含 brainstorm Q&A，--fast 复用为快速通道
<!-- tags: autopilot, brainstorm, design, fast-mode, default-inversion, simplification, yagni -->
**Background**: v3.20.0（9c770a8 之后）design 阶段默认走 standard 路径——直接写设计文档无 Q&A 探索，仅 `--deep` flag 显式触发交互式 brainstorm。用户实际诉求"模糊任务希望默认有 brainstorm"在显式 flag 下经常错过。同时四档决策树（auto_approve / plan_mode:deep / fast_mode / standard）心智模型偏重。
**Choice**: 默认值反转——空 `plan_mode` 即触发 brainstorm + 完整 sub-agent 审查；`--fast` 语义扩展为「跳过 brainstorm + 砍 scenario-generator + 砍 plan-reviewer」一档式快速通道；`--deep` flag 保留为兼容期 deprecation（行为同默认），plan_mode 字段事实弃用。决策树从 4 档简化为 3 档（auto_approve / fast_mode / 默认）。
**Alternatives rejected**: (1) 方案 A 完全删除 plan_mode 字段 — 与 9c770a8 简化方向冲突，"明确意图任务"无 escape hatch；(2) 方案 B 新增 `--quick` flag 单独控制"跳过 brainstorm" — flag 数量膨胀，中间档"无 brainstorm + 严格审查"实际低频；(3) 方案 C 编排器自动判断意图清晰度 — 违反知识库已沉淀的 "AI 自觉机制不可靠" pattern。
**Trade-offs**: 接受语义耦合——「无 brainstorm + 完整 sub-agent 审查」中间档消失。用户对明确小任务必须用 --fast（同时砍审查）；如未来出现"明确意图但需要严格审查"高频需求再单独加 --quick 不晚。
**Evidence**: v3.20.0→v3.21.0；setup.sh / stop-hook.sh / SKILL.md / state-file-guide.md 同步；3 个现有验收测试更新 + 1 新增 brainstorm-default.acceptance.test.sh（17 assertion / 10 核心契约）。Tier 1.5 三个真实场景（默认 / --fast / --deep 兼容）全 PASS。
**Lesson**: 当用户提议"默认化某行为 X"时，不要直接照做——先评估 X 当前的使用模式分布，复用现有 escape hatch flag 通常优于新增 flag。本次 plan_mode 字段事实上只有 2 个有效值（""空 / "deep"），是 boolean 用 string 表达，本身就有简化空间——这种"语义冗余字段"重构时可顺势清理为 dead field（保留兼容期防止历史 state.md 解析报错）。关联 9c770a8 形成「Plan Mode 移除 → brainstorm 默认化」决策链，方向一致：把通用流程做减法、把高质量行为提升为默认。

### [2026-05-25] SKILL.md 关键 step 必须有「双重 grep」长效 CI 守护，单 grep 会被弱条件骗过
<!-- tags: autopilot, skill-md, ci-guard, regression-prevention, acceptance-test, double-grep, inline-refactor, llm-instruction, behavior-contract -->
**Scenario**: cdad541（2026-04-28）commit message 自称 "fix(autopilot): 恢复 SKILL.md 完整内联"，但实际把 Phase: merge 章节的 §2 Auto-Chain 评估步骤整段删了，仅保留 commit/handoff/知识/总结/清理。AI 因此再也读不到「Edit `next_task` 字段」的指令，project 模式 auto-chain 失效约 1 个月。stop-hook 基础设施正常，但 AI 永不写 `next_task`，子任务完成后 stop-hook 静默释放。回归持续 27 天才被发现，因为现有 acceptance test 只有 `wc -l < 615` 行数守护和「Phase: qa 段不引用旧 prompt」类断言，没有任何测试守护 merge 段的关键 step 文本。
**Lesson**: 对每个被 LLM 当指令读的关键 step（SKILL.md 的「写 `next_task`」、「调用 commit-agent」、「跑红队 Agent」等），acceptance test 必须**双重 grep**而不是单 grep：
- **关键字段名** grep：merge 段必须含 `next_task` 字面（catch 删字段）
- **显式 step 标题** grep：merge 段必须含 `^#### N\. Auto-Chain` 类标题段（catch 删 step 段但保留交叉引用的情形）

只设字段名 grep 会被弱条件骗过 — 我第一版加的守护只 grep `next_task`，但删 §2 后 §5 清理段仍有「如已设置 `next_task`...」交叉引用，单 grep 命中 1 次仍 PASS。必须强化为「字段 grep + 步骤标题 grep」AND 关系，才能真 catch 删段回归。

**实施模板**（直接套用到 `skill-references-consistency.acceptance.test.sh`）：
```bash
SECTION=$(awk '/^## Phase: <name>/{f=1;print;next} f&&/^## /&&!/<name>/{f=0} f' "$SKILL_FILE")
field_hits=$(echo "$SECTION" | grep -c "<critical_field>" || true)
heading_hits=$(echo "$SECTION" | grep -cE "^#### [0-9.]+ <Step Title>" || true)
[[ "$field_hits" -lt 1 ]] && fail "段内 <field> 字面消失（catch 删字段）"
[[ "$heading_hits" -lt 1 ]] && fail "段内 '#### N. <Step>' 标题消失（catch 删段保留交叉引用）"
```
反向验证铁律：写完守护必须**删掉受护内容跑一遍**确认 FAIL exit 非 0，再恢复确认 PASS。我第一版没做反向测试就交付，结果用户层面才发现守护无效。

**与 [[skill-refactor-invariant-guard]]（[2026-05-23] patterns）的分工**：
- 2026-05-23 「不变量护栏」是 **in-task Tier 1.5**，防当前 refactor 任务引入伪优化（一次性，跟改动绑定）
- 2026-05-25 「双重 grep CI 守护」是 **cross-task acceptance test**，防未来任何 refactor 漏掉关键 step（长效，跟具体改动解耦）
- 两者互补：前者控本轮，后者控未来轮。SKILL.md 任何「LLM 指令型」step 都应加后者，前者按任务复杂度选用。

**验证 LLM 行为回归的成本边界**：CI 静态 grep ≈ 零成本，能 catch 「指令文字消失」类回归（本次类型）。但 catch 不到「AI 读了文字但不执行」类。后者需 LLM-in-the-loop e2e（~$0.09/run sonnet + 2-3 工作日搭建 + flakiness），单 fix 边际价值低，建议「静态守护 + 实地观察」组合即可，除非同类回归频次超 ROI 阈值（如月 ≥ 3 次）。

**Evidence**: v3.36.1 修复时新增 `skill-references-consistency.acceptance.test.sh` 断言 6，反向 dry-run：删 SKILL.md §2 → `[FAIL] exit 1`，恢复 → `[PASS] exit 0`。CI 全绿 (run 26408635622，Unit Tests + ShellCheck success)。

### [2026-05-10] skill 改动应一处真相不重复 N 处文件
<!-- tags: autopilot, skill, single-source-of-truth, drift, integration, sbe, gojko, contract, references -->
**Scenario**: 给 autopilot 加契约规约能力，初版 v1 方案在 4 处文件（state-file-guide / plan-reviewer / red-team / blue-team）分别写「契约逐字一致」规则的不同表述。skill 反审指出这正是 [Gojko SBE 10 年回顾] 实证的 12% 兑现率 anti-pattern — 同一规则在 4 处用不同语言描述，3 个月内必出现 1-2 处不同步，业界 88% 团队靠纪律维持 spec-as-truth 失败。
**Lesson**: skill 加新能力时，先建一个 `references/<concept>-protocol.md` 作为单一真相源（含完整规则 + 完整示例 + 反例），其他文件**只引用、不重复**。例如本次 v2: contract-protocol.md 集中所有契约协议规则；state-file-guide / plan-reviewer / red-team / blue-team 4 处仅写 1-3 行+「详情参 references/contract-protocol.md」链接。这样规则演进只需改一处，杜绝跨文件描述漂移。已存在的 progressive-disclosure 重构 pattern（[2026-03-21]）是同模式应用。
**Evidence**: v1 4 处文件分散描述 vs v2 单一 contract-protocol.md + 4 处链接，diff 行数 v2 比 v1 少 ~40%；skill 反审在 v1 揭示「跨文件措辞漂移」⚠️，v2 重写后这条风险标记为已修；本次 11/11 红队 acceptance 中 C8/C9 两项验证「⚠️ 章节数不变」+ C10 验证「占位符不存在」均通过。

### [2026-05-10] frontmatter 加豁免字段是 skill 演进的元任务安全模式
<!-- tags: autopilot, skill, evolution, meta-task, frontmatter, opt-in, historical-exemption, contract-required, setup-sh -->
**Scenario**: skill 引入新强制门（如 plan-reviewer 维度 7 必须有 ## 契约规约 章节）时，会立即卡死所有当前 phase=design 未推进的 state.md（含本次任务自身、其他 worktree 在跑、历史搁置任务），新规则上线即所有 autopilot session 卡住。这是 skill 升级的"元任务陷阱"，必修项。
**Lesson**: 在 setup.sh / lib.sh 创建新 state.md 时，frontmatter 显式写入豁免开关字段（如 `contract_required: true`），新规则的 enforcement 路径（plan-reviewer 维度 / contract-checker agent）都先读这个字段，缺失或 false 直接跳过。旧 state.md 无此字段 → 视为 false → 自动豁免，不卡历史任务；新 task 由 setup.sh 强制启用。这个模式可推广到任何「新增 phase 门 / 新增 reviewer 维度 / 新增 lint」场景，保证 skill 平滑升级。
**Evidence**: 本次 v3.24.0 升级，本任务自身 state.md（先于 setup.sh 改动创建）frontmatter 无 contract_required 字段，contract-checker 步骤 2.5 自动跳过 — 这是预期行为且实测通过；C5/C6 红队 acceptance 验证字段说明 + 写入位置正确；skill 反审给元任务陷阱 ⚠️ 在 v2 后标记为已修。

### [2026-05-10] 红/蓝队 prompt 改动应在现有 ⚠️ 铁律 内追加 bullet，禁止新增 ⚠️ 章节
<!-- tags: autopilot, red-team, blue-team, prompt, warning-section, anti-pattern, decision-tree, dilution, contract -->
**Scenario**: 给红队 prompt 加新规则（如「契约逐字一致」），最直觉的做法是新增 `## ⚠️ 契约优先铁律` 章节。但红队 prompt 已有 `## ⚠️ 铁律` 和 `## ⚠️ 测试质量铁律` 两个 ⚠️ 章节，再加第三个就撞 [2026-04-17] decision「SKILL.md 决策树中后置章节会被 AI 跳过」anti-pattern — AI 读到第一个 ⚠️ 立即行动，后续 ⚠️ 章节优先级被稀释，新规则形同虚设。
**Lesson**: 红/蓝队 prompt 加新规则时，**绝对不新增 ⚠️ 章节**。改在现有 ⚠️ 铁律章节内追加 1 条 bullet，或加在 `## 工作规则` 编号列表末尾。例如本次 v2: 红队规则加在 `## ⚠️ 铁律`（line 9）章节内的 bullet 列表末尾；蓝队规则加在 `## 工作规则`（9 条 → 10 条）末尾。⚠️ 章节数严格保持改动前数量（红队 = 2，蓝队 = 0），由 acceptance test 硬断言锁死。
**Evidence**: v1 提案被 skill 反审判「多 ⚠️ 章节稀释」致命问题，v2 改为现有章节追加 bullet；C8/C9 两项红队 acceptance 硬断言「红队 ⚠️ 章节数 = 2」「蓝队 ⚠️ 章节数 = 0」均 PASS；占位符变量 EXPECTED_FIELD_NAME_FROM_CONTRACT 在 v1 prompt 中（运行时崩 lint），v2 移除后 C10 acceptance 验证 0 命中。

### [2026-05-09] acceptance test 中 `TARGET_VERSION="X.Y.Z"` 是版本同步规则的隐藏盲区
<!-- tags: autopilot, version-sync, acceptance-test, hardcoded, regression, blind-spot, autopilot-commit -->
**Scenario**: autopilot v3.22.1 → v3.23.0 升级时，蓝队按 CLAUDE.md 版本管理规则同步了 plugin.json + marketplace.json + CLAUDE.md 三处版本号，但 `plugins/autopilot/tests/acceptance/{version-sync,brainstorm-default,plan-review-html}.acceptance.test.sh` 中的 `TARGET_VERSION="3.22.0"` / `"3.22.1"` 硬编码字符串没被同步规则覆盖，导致 Tier 1 bash acceptance 3 个测试 fail（断言形如 `plugin.json 版本 '3.23.0' != 期望 '3.22.1'`）。
**Lesson**: CLAUDE.md 列出的版本同步范围只是"运行时版本号"层（plugin.json/marketplace.json/CLAUDE.md），但 acceptance 测试文件本身也会出现版本号字符串作为"上一版本契约"硬断言。autopilot-commit skill 的版本同步 grep 范围必须扩展到 `find . -path '*/acceptance/*' -name '*.test.sh'` 中的 `TARGET_VERSION=` 行，以及类似 `expected: '3.X.Y'` 模式的 mjs 测试。同样适用于 README.md 顶部"上一版本变更说明"段——v3.17.0 时建立的契约要求每升一版加一句话变更说明，蓝队 T5 同样漏过，被 version-sync.acceptance.test.sh 的 R8 断言抓住。
**Evidence**: 本次 wave 1 selective auto-fix 修了 4 处：3 个 bash 测试 TARGET_VERSION + 1 处 README 顶部变更说明。修完 run-all.sh 7/10 → 10/10。下次 autopilot-commit 优化时把 acceptance test + README 一并加入 grep。
**Update [2026-05-23]**：根治方案落地——把 `TARGET_VERSION="X.Y.Z"` 改为 `TARGET_VERSION=$(grep '"version"' plugin.json | sed ...)`，从 plugin.json 动态读取作为 single source of truth。此后 acceptance test 自动跟随 plugin.json 升级，**永久消除该盲区**（commit `651ba81`，v3.35.0）。优于"扩大 grep 范围"治标方案，因为治标方案要求每个新增 hardcoded 位置都被记得纳入 grep，仍依赖人工自律；动态化是结构性根治。

### [2026-07-03] 删 skill 时引用链 grep 须覆盖仓库根 README.md（不只 plugins/）
<!-- tags: autopilot, skill, reference-chain, grep-scope, blind-spot, dead-code-removal, qa-reviewer, readme, dogfood -->
**Scenario**: 删 autopilot 死代码 skill（worktree-repair）时，设计探针 grep 限定在 `plugins/ document/ .claude-plugin/`，命中 doctor SKILL.md:230 + knowledge-engineering.md:145，漏了**仓库根 README.md:59**「Worktree 自动初始化」章节的 `/worktree-repair 可手动修复配置缺失` 活指引文案。skill 删除后该指引变悬空引用（用户照做 → skill not found）。
**Lesson**: 删 skill / 改跨文件引用时，引用链清零 grep 范围必须覆盖**仓库根 README.md**——autopilot 仓库根 README 有「Worktree 自动初始化」等章节含**活指引文案**（非 changelog），删 skill 后会变悬空。与 [2026-05-09]（版本同步盲区）同族但不同维度：那条治版本号 grep 范围，本条治**引用链活引用** grep 范围。兜底防线：qa-reviewer Section A「不信任、独立验证」能发现探针遗漏（本案 [置信度 88] 抓住），但探针阶段覆盖仓库根 README 能更早、省一次 auto-fix iteration。
**Evidence**: v3.49.0 删 worktree-repair，设计探针漏 README.md:59，qa-reviewer Section A 独立审查发现悬空活引用 → auto-fix 改 SessionStart 自动 repair 口径。关联 [2026-06-18] 零价值环节删除（死代码删除判据）、[2026-05-09]（同族 grep 范围盲区）。

### [2026-03-21] Skill 插件 Progressive Disclosure 重构模式
<!-- tags: skill, progressive-disclosure, plugin, refactoring -->
**Scenario**: npm-toolkit SKILL.md 内联所有内容（排障/模板/高级用法），导致行数膨胀（195+311 行），不符合 <500 行最佳实践
**Lesson**: 按信息频率拆分：核心流程（每次都需要）保留在 SKILL.md，低频内容（排障/高级模式/工具选型）外置到 `references/` 目录。引用用相对路径 `See [references/xxx.md](references/xxx.md)`。拆分后 SKILL.md 精简 30-40%，Claude 按需加载 references 文件。关键：引用只保持一层深度（SKILL.md → references/），不嵌套引用
**Evidence**: npm-toolkit 重构：npm-publish 195→165 行（-15%），github-actions-setup 311→196 行（-37%），3 个 references 文档（106+224+239 行），24/24 验收测试通过

### [2026-03-24] SKILL.md 步骤标题需包含可搜索的"步骤"前缀
<!-- tags: autopilot, skill, naming-convention, testing -->
**Scenario**: 红队验收测试用 regex `/(?:步骤|step|Step)\s*N/` 提取 SKILL.md Phase: design 的步骤内容，但实际标题格式是 `#### N. Title`（无"步骤"前缀），导致 7/7 步骤测试全部失败
**Lesson**: SKILL.md 的步骤标题应使用 `#### 步骤 N. Title` 格式而非裸数字 `#### N. Title`。(1) 中文"步骤"前缀让步骤可被正则稳定提取 (2) 与文档内文中"继续到步骤 5"的引用格式一致 (3) 对 AI 解析更友好。auto-fix 只需在 Phase: design 的 6 个步骤标题前加"步骤"前缀即可修复
**Evidence**: tests/plan-reviewer.acceptance.test.mjs 第 154-163 行 regex 匹配失败，修复后 17/17 测试通过

### [2026-03-27] Skill 规范不应硬编码项目特定的文件路径
<!-- tags: autopilot-commit, skill, version, hardcoding, claude-md -->
**Scenario**: autopilot-commit SKILL.md 硬编码了 3 个版本文件路径（plugin.json/package.json/CLAUDE.md），但遗漏了 marketplace.json，导致 4 个插件版本长期不同步（最大差 6 个版本）
**Lesson**: Skill 规范应引导 AI 从项目文档（CLAUDE.md）中自主发现需要操作的文件，而非硬编码固定路径。硬编码的问题：(1) 新增文件时必须同步修改 Skill 规范 (2) 不同项目结构不同，硬编码不通用 (3) AI 按列表执行时容易"完成列表=完成任务"的心态遗漏列表外的文件。正确做法：CLAUDE.md 集中维护项目特定信息，Skill 规范只描述通用流程（发现→更新→校验）
**Evidence**: marketplace.json autopilot 版本 3.0.1 vs plugin.json 3.3.1（差 6 个版本），eb0e38c 修复后仍未覆盖

### [2026-04-17] SKILL.md 决策树中后置章节会被 AI 跳过
<!-- tags: autopilot, skill, decision-tree, priority, plan-mode, auto-approve -->
**Scenario**: SKILL.md Phase: design "⚠️ 关键规则" 只检查 plan_mode，auto_approve 快速路径作为独立章节在后面。auto-chain 子任务 auto_approve=true 时 AI 按关键规则"立即 EnterPlanMode"，跳过了后面的 Auto-Approve 快速路径
**Lesson**: AI 执行 SKILL.md 时，⚠️ 标记的"关键规则"具有最高指令权重——AI 读到"立即"就行动，不会继续扫描后续章节是否有例外。所有决策分支必须集中在同一个决策树中，不能分散到多个独立章节。修复：将 auto_approve 检查提升为关键规则决策树的第一优先级
**Evidence**: case 文件显示 AI 输出"Brief 模式…进入 Plan Mode"后立即调用 EnterPlanMode。stop-hook prompt 虽正确注入"跳过 Plan Mode"，但 SKILL.md 结构性指令优先级更高

### [2026-05-08] 字段反转默认值 + 复用现有 flag 优于新增 flag
<!-- tags: autopilot, design-decision, yagni, flag-design, default-inversion -->
**Scenario**: 用户提议「把行为 X 默认化」（例如 brainstorm 默认开启）时，简单实现是新增一个 opt-out flag。但很多时候现有的某个 flag 已经隐含了"opt out X"语义，复用比新增更优。
**Pattern**: 三步决策——(1) 列出 X 当前的所有使用模式（auto / explicit-on / explicit-off / 默认行为）；(2) 检查现有 escape hatch flag 是否能覆盖"opt-out X"语义，如果耦合可接受 → 直接扩展该 flag 语义；(3) 仅当中间档（非 X 但需要某些子项）真实存在高频需求时才新增 flag。
**Counter-example**: 本次 brainstorm 默认化任务初版方案 B 设计了 --quick 新增 flag，与现有 --fast 中间档差距其实很小（仅 sub-agent 审查严格性差异）；用户在审批时主动提出复用 --fast，方案演进为 B'，flag 数量从 +1 变为 0，决策树从 4→3 档进一步简化。
**Lesson**: flag 设计的 YAGNI 原则——"假想中间需求"不应作为新 flag 的设计依据。如果未来真出现高频需求再加 flag 也不晚，向前兼容性只在不删字段时存在风险。事实弃用的字段应保留兼容期（不立即删除）以避免历史持久化文件解析错误。


### [2026-07-08] skill md 减行硬约束下，新守卫逻辑全部下沉 bash，skill md 删散文净减行
<!-- tags: autopilot, skill, shrink-only, enforce-bash, stop-hook, lib-sh, predicate-guard, mock-cheating, trust-chain, mechanical-enforcement, v3.52.0 -->
**Scenario**: 给 autopilot 加 QA 谓词驱动证据守卫（治编排器用 mock 单测输出冒充 Tier 1.5 真实产物），但项目已有 `skill-md-net-shrinkage.acceptance.test.sh` 硬断言锁死 skill md 四文件（red-team/blue-team/implement-phase/SKILL.md）合计净行数只能减不能增。新守卫若写在 SKILL.md 会违反约束。
**Choice**: 执法力量全部下沉 stop-hook.sh / lib.sh（bash，不计 md 减行约束）：lib.sh +2 校验函数（validate_predicate_driver 反向判定 + validate_predicate_artifacts 存在性校验），stop-hook +§5.7 gate=review-accept 时机械执法。skill md 反向做减法——删除被守卫取代的散文要求（"每条 PASS 必须引真实 artifact"等），SKILL.md 净删 3 行。谓词格式规约（driver/artifact 字段）写到减行约束外的 scenario-generator-prompt.md / state-file-guide.md。
**Alternatives rejected**: (1) 在 SKILL.md 加守卫指令 → 违反减行硬约束，acceptance test FAIL；(2) 用 frontmatter 豁免字段绕过减行约束 → 治标不治本，且本次守卫自门控（无 driver 字段则 no-op）不需要新字段；(3) 引入 verify/run skill 做真机验证 → 用户明确"skill 只能减不能增加"，且增加 skill 调用违背最小依赖。
**Trade-offs**: 守卫逻辑在 bash 不在 SKILL.md 决策树，规避 [[2026-04-17]]「后置章节跳读」风险（AI 不会跳过 bash 守卫）。代价：skill md 失去"需产出 artifact 路径"的引导——用 state-file-guide.md（约束外）补一行精简指令 + §5.7 block reason 文案承担引导。这是 [[2026-06-24]]「机械活下沉 hook / 智力活留 agent」模式在"减行约束"场景的应用：bash 执法不受 md 行数限制，skill md 做减法反而把散文压力转移给机械守卫。
**Evidence**: v3.52.0（commit d9bee50）§5.7 上线。红队测试 predicate-driver-guard.acceptance.test.sh 21 断言全绿（8 条 det-machine 谓词）；独立 subagent 盲测 7 场景（合规放行/mock 冒充 block/artifact 缺失 block/旧 task no-op/反向判定边界）全符合预期；skill-md-net-shrinkage PASS（SKILL.md 净删 3 行）；CI success（run 28926783901）。治 session a14383e0 实证：编排器用 mock overmind 冒充 /api/align/issues 真实驱动，§5.7 现在精确拦截（driver=node-script + observe 含 curl → block）。
**Lesson**: 当 skill md 有减行/零增硬约束时，新守卫的执法逻辑必须下沉 bash（stop-hook/lib.sh），skill md 删散文做减法（被守卫取代的要求删掉）。关键判据：守卫是"机械活"（可 bash 判定）还是"智力活"（需 AI 判断）——机械活下沉不受 md 约束，智力活才留 skill。本次 driver 类型一致性 + artifact 存在性都是机械活，完美适合 bash。关联 [[2026-06-24]]（机械活下沉 hook 总则）、[[2026-07-08]] smoke Tier 1.5 铁律（铁律已有但缺机械执法，本次补）。
