# Patterns & Lessons（热区：近 30 天活跃决策）

### [2026-06-02] `$(cmd || true); rc=$?` 把退出码永久吞成 0；要保留 rc 又不触发 trap ERR 用 `cmd || rc=$?`
<!-- tags: bash, exit-code, command-substitution, or-true, rc-masking, trap-err, double-signal, stop-hook, lib-sh, defensive-edit, qa-reviewer-catch -->
**Scenario**: stop-hook 在顶层有 `trap 'exit 0' ERR`，为防函数返回非零误触发 trap 早退，蓝队给"读取 tamper 守卫结果"写成 `out=$(check || true); rc=$?`。设计本是"双信号判定（rc==2 或 stdout 含 TAMPER）"，但 qa-reviewer 读实际代码发现 rc 分支永远不触发。
**Lesson**: `rc=$?` 取的是它**前一条命令**的退出码；而 `x=$(cmd || true)` 这条赋值的退出码是 `true`（=0），所以紧跟的 `rc=$?` **永远是 0**，把真实 rc 彻底吞掉（这里让"双信号"退化成"单信号"，rc==2 死分支）。要既保留真实 rc、又不让非零触发顶层 `trap ERR`，用 `rc=0; out=$(cmd) || rc=$?`——`||` 列表左侧命令非零**不触发 ERR trap**（bash 规则：&&/|| 列表中除最后一条外的命令失败不触发 errexit/ERR），右侧 `rc=$?` 拿到真实码。这是 [2026-05-07] "顶层 trap 'exit 0' ERR 拦截函数内 || return 1" 的同族续：trap ERR 环境下任何"捕获子命令 rc"都要用 `|| rc=$?` 而非 `|| true`。
**Evidence**: 改 `_tamper_rc=0; _tamper_out=$(acceptance_tests_tampered "$lk") || _tamper_rc=$?` 后，脚本复测篡改场景 `rc=2` 真值捕获、clean `rc=0`、no-lock `rc=1` 三态正确；双信号恢复。同批 qa-reviewer 还逮出 `awk '{print $2}'` 解析"双空格分隔含空格路径"会截断 → 改 `${line#*  }` 参数扩展（按双空格切，保留路径内空格）。

### [2026-05-31] 用"静默放行/等待"修死循环时，必须补"用户可见 + 活性自救"，否则把吵闹死循环换成无声卡死（反面同族）
<!-- tags: autopilot, stop-hook, silent-wait, liveness, observability, exit-0, iteration-freeze, max-iterations-backstop, system-message, false-positive-stall, inverse-failure-mode, has-pending-subagents -->
**Scenario**: v3.40.2 为治 merge 近似死循环（§9 反复唤醒 commit-agent），引入 §7.5「检测到 pending sub-agent 就静默等待」——裸 `exit 0` + 仅 `echo >&2`。深度审计（对抗+盲扫双 agent）发现这是上次 bug 的**反面同族**，三条致命属性：① `exit 0` 在 §8 iteration 递增**之前** → 等待期 iteration 冻结 → §7 `max_iterations` backstop **永不触发**（计数器不动，30 也到不了）；② 只 echo stderr（Stop hook 的 stderr 用户看不到）→ 零用户信号；③ 若 `has_pending_subagents` 假阳性（sub-agent 崩溃没写完成标记 / Claude Code transcript schema 漂移，见 [[tail-c-jq流式解析丢首行fail-safe]]）→ autopilot **永久静默卡死**，唯一出路 `/autopilot cancel` 但用户无从得知。
**Lesson**: 修一个「失控循环」最容易的解是「让它停下」（silent exit / 静默等待）——但**「停下」若不可见且无活性兜底，就是把『吵闹的错』换成『无声的错』，后者更难诊断**。任何「条件满足就 exit 0 不再前进」的放行/等待路径，动手前自检三问：
- **可见吗？** 用户能看到"我在等什么/为什么停"吗？stderr 不算（hook 的 stderr 不展示）。→ 用 `{"systemMessage":...}`（不带 `decision:block`，不唤醒 AI，不破坏 Claude Code 经 tool_result 的自然恢复）让等待可见。
- **有活性兜底吗？** 这条路径会不会因某个永真的假阳性条件而**永远**走下去？若 exit 早于计数器递增，原有的 max-iteration backstop 就被绕过了——要么让用户可见后自救（最小解），要么加独立活性守卫。
- **方向同源**：本案直接复用 §7.6（[[对齐阶段design按phase边界放行]]）已验证的 systemMessage 放行模式延伸到 §7.5——零新增状态字段、单点纯追加。与 [[自门控横切检测不要加phase门控]] 互补：那条治「检测在哪些点生效」，本条治「检测命中后那条 exit 路径的可见性与活性」。
**Evidence**: 红队 `silent-wait-visibility.acceptance.test.sh` 10/10 PASS（P0 放行码 exit 0 + P1-P5 + 自救提示 + 全阶段泛化），mutation 自检（注入 `decision:block` → P2+场景D 转红 PASS=7）证非 tautological；qa-reviewer 复盘抓出 P2 对 pretty-JSON `"decision": "block"`（冒号后有空格）用无空格精确串恒真 → auto-fix 改带空格容错正则 + mutation 复验。commit 5e41eb5 / v3.40.4。

### [2026-05-31] 断言"stdout 含某 JSON 键"易成 tautological — mutation 落点若也输出该键则断言失效
<!-- tags: autopilot, test-quality, tautological-assertion, mutation-survival, json-key-grep, stop-hook, acceptance-test, no-op-mutation, false-green -->
**Scenario**: `design-phase-hold` 红队测试场景1 P5 验证"§7.6 放行时输出 systemMessage 暂停说明"，初版断言 `grep -q '"systemMessage"'`。qa-reviewer Section C 抓出：删掉 §7.6（no-op mutation）后 standard design 落到 §9 输出 block JSON——而 **§9 的 block JSON 本身就含 `systemMessage` 键**（值 `"autopilot iteration N | phase: design"`）。所以 P5 在 mutation 存活时仍 PASS，没 kill mutation（同场景 P2 靠 `decision:block` 能 kill，但 P5 个体给了虚假绿）。
**Lesson**: 断言"输出含某 JSON 键/字段名"时，必须先问：**这个键在 mutation 落点（被测代码改坏后流量会去的其他分支）的输出里也出现吗？** 若出现，该断言无法区分"正确分支"与"mutation"，是 tautological。修法：断言被测分支**专属**的内容标志，而非通用键名——本案改为 `"systemMessage" 键 ∧ §7.6 专属文案标志「用户尚未确认」`（§9 的 systemMessage 值绝不含此标志）。**最小自检**：删被测代码重跑，该断言必须转红；不转红就是 tautological（[[Mutation-Survival自检反no-op]]）。这类陷阱在"两条分支输出同一种结构/JSON、只是字段值不同"时尤其隐蔽。
**Evidence**: P5 加强为双条件后重跑 20/20 PASS；mutation 复验（删 §7.6）P5 **正确转红**（连同 P2、场景7 共 6 断言 FAIL，PASS=14/20）。qa-reviewer 第 1 轮判此为 Section C Critical → auto-fix 修测试断言力（非削弱，是加强）。commit 5cbee5f / v3.40.3。

### [2026-05-31] 自门控的横切检测函数不要再加 phase/条件门控 — 否则退化成 flag-asymmetry
<!-- tags: autopilot, stop-hook, has-pending-subagents, self-gating, phase-gate, flag-asymmetry, cross-cutting-detection, commit-agent, near-infinite-loop, regression-recurrence -->
**Scenario**: stop-hook §7.5「后台 sub-agent 静默等待」检查被 `[[ "$PHASE" == "implement" ]]` 死门控（当初保守限制，注释假设「design/qa/merge 的 sub-agent 都 <2分钟」）。但 merge 阶段 commit-agent 用 `Agent` 工具启动、常 `run_in_background=true`（异步路径 B），运行数分钟。期间主 agent 结束响应 → Stop hook 触发 → 因 phase≠implement 整段检查被跳过 → 反复注入「启动 commit-agent」prompt + 递增 iteration → 近似死循环（实测 iteration 6/7/8 连发）。红蓝对抗的 implement 阶段早就修好了同样的等待逻辑，merge 漏修。
**Lesson**: 一个检测函数若**「无目标时零副作用返回」**（`has_pending_subagents` 无 pending → 返回 1 → 调用方走正常流程，行为与不调用完全一致），那它就是**自门控**的——给它再叠加 `phase==X` / 其他条件限定，不是变安全，而是把它退化成 flag-asymmetry「半生效」bug：检测只在一个转换点生效，其他转换点裸奔。
- **判据**：动手加「仅在 X 情况下才跑这个检测」前，先问「这个检测在非 X 情况下跑会有副作用吗？」。**无副作用 → 删掉条件，让它全局生效**；有副作用 → 才需要条件，且必须枚举所有该生效的点（见 [[flag-asymmetry-half-effective-bug]]）。
- **本次修复**：`if [[ "$PHASE" == "implement" ]] && [[ -n "$HOOK_TRANSCRIPT" ]] && has_pending_subagents ...` → `if [[ -n "$HOOK_TRANSCRIPT" ]] && has_pending_subagents ...`。一行减法，从结构上消灭「未来任何阶段引入长 agent 都要再改这里」的复发面。
- **与 [[flag-asymmetry-half-effective-bug]]（[2026-05-26]）的关系**：那条是「新增 flag 字段要枚举所有转换点」；本条是其特例的**反向收敛**——当检测本身自门控时，正确解不是「枚举所有 phase 补齐」，而是「去掉 phase 限定」。两条共享元规律：横切关注点的「在哪些点生效」必须与其语义一致，不能凭「保守起见先限一个 phase」拍脑袋。
**Evidence**: 新红队集成测试 `stop-hook-pending-gate.acceptance.test.mjs` 4/4 PASS（merge+pending静默 / merge+无pending注入 / qa泛化 / implement回归）；编排器独立驱动真实 stop-hook：merge+pending→stdout 空、merge+无pending→注入 commit-agent block JSON。commit 4863f50 / v3.40.2。

### [2026-05-17] documentation-only 变更的 QA 降级模式：Tier 1/3.5 N/A、Tier 1.5 用产出审阅替代浏览器冒烟
<!-- tags: autopilot, qa, documentation-only, markdown, tier-1.5, smoke-test, content-review, prompt-engineering, fallback -->
**Scenario**: autopilot 任务的输出全部是 markdown prompt / reference 文件（无 .ts/.js/.py 可执行代码、无 dev server、无 API endpoint、无 UI 渲染），但任务被声明 contract_required: true 且有 9 个验收场景，必须走完整 QA 流程。Wave 1 的 tsc / lint / build / bundle-size 全部 N/A，Wave 1.5 真实场景验证无 dev server 可启动。
**Lesson**: QA 流程对 documentation-only 变更应做以下结构性降级，不能因"无可执行代码"跳过 QA 或全标 N/A 蒙混：
- **Wave 1 Tier 1（基础验证）**：替换为"字面契约 grep -F 严格正向+反向、引用串完整性、版本号同步、纯追加 deletions=0 验证"。语言工具链不适用即 N/A，不是 ❌。
- **Wave 1 Tier 4（回归）**：替换为"现有铁律/章节/不变量字面保留验证"（grep 原版关键词必须命中、`git diff SKILL.md` 必须为空）。
- **Wave 1.5 真实场景验证**：用"Read 蓝队完整产出做内容审阅"替代"启动浏览器/curl"。每个验收场景对应一段 Read，记录"证据 = 蓝队文件 X 第 Y 节包含 Z 段落"，等价于浏览器场景的"点击 X 后看到 Y"。
- **必须标注 deferred 而非 PASS** 当某个场景确实无法通过 Read 完全验证时（如"模拟 sub-agent 收到新 prompt 后输出行为"）—— deferred 是合规结果，PASS 不是。
- **qa-reviewer Section A/B/C 仍照常启动**：纯 markdown 项目的 Section B 关注 markdown 结构 / prompt 工程清晰度 / 链接完整性 / 业界证据可追溯性，而非 OWASP / SQL 注入。
**Evidence**: 本次任务 7 个修改文件 + 1 个新建（reference）+ 0 行可执行代码。Tier 1 tsc/lint/build 全标 N/A 但 Tier 0+Tier 4 给出 17 条正反向 grep 验证；Wave 1.5 9 场景全部以"Read test-mutation-survival.md 第 N 节 / Read 4 prompt 改动 diff" 为证据；qa-reviewer Section B 按 markdown 维度审查，0 Critical / 0 Important / 2 Minor。最终评分 96/100、Ready to merge: Yes。本模式可迁移至任何 prompt-only / docs-only / 配置-only 任务。

### [2026-05-17] 设计阶段量化承诺（行数 / token 数 / 性能数）必须 grep 验证而非估算
<!-- tags: autopilot, design, prediction, quantitative-commitment, grep-verify, estimate-bias, plan-reviewer, skill-extraction -->
**Scenario**: 设计 brainstorm 抽离 skill 时，设计文档承诺"主 SKILL 净减 ~64 行（644→~580）"。实际实施后只减 2 行（644→642），偏差 32 倍。根因：被抽离的 `references/brainstorm-guide.md` 89 行内容**从未内嵌主 SKILL**，本来就在独立 reference 文件，主 SKILL 中只有 4 行引用链接（被删除后又添加 6 行新委托段落，净减 2 行）。设计时按"reference 文件大小 ≈ 主 SKILL 节约量"估算，违背了实际架构。
**Lesson**: 设计文档中所有**量化承诺**（X 行节约 / Y% token 降低 / Z 倍性能提升）必须配套**可执行的事前验证命令**写入设计文档。例如行数承诺应写"已 grep 主 SKILL.md 全文 `references/brainstorm-guide.md` 出现 N 次，每次占 K 行，删除可净减 N×K 行；新增段落预估 M 行，净减 = N×K - M"。无可执行验证的承诺一律标"预估，待 implement 后实测"。plan-reviewer Agent 应新增一条审查规则：「设计文档中所有量化指标是否有事前验证命令或明确标注'预估'？」—— 本次 plan-reviewer 通过但未捕获，因为只看任务完整性不看预估准确性。
**Evidence**: brainstorm 抽离任务 design phase 写"净减 ~64 行"，implement 后实测主 SKILL 644→642 行；qa-reviewer Section A 第一次发现并标为 ⚠️。R3 acceptance test（<600 行）持续 FAIL，未跨越红线。修正措辞：README.md 顶部从"主 SKILL 精简 ~64 行"改为"实际净减 2 行（644→642，原设计预估 ~64 行偏乐观——brainstorm-guide.md 89 行内容从未内嵌主 SKILL，只是 4 行引用链接被删除）"。关联 [[brainstorm-skill-extraction-decision]]。

### [2026-05-19] 静态 HTML 模板的 Tier 1.5 用 Chrome DevTools MCP + file:// 直接 evaluate_script
<!-- tags: autopilot, qa, tier-1.5, smoke-test, html-template, chrome-devtools-mcp, file-protocol, server-bypass -->
**Scenario**: QA Tier 1.5 要验证纯静态 HTML 模板的运行时行为（DOM 结构、JS 函数副作用、CSS computed style）。模板配套的服务端启动脚本是阻塞的（等用户决策）—— 不能直接复用做自动化验证。
**Lesson**: 对于"渲染层 = 静态 HTML 占位符替换"型资产，Tier 1.5 不必启动配套 server，复用渲染逻辑本地写出 HTML 后用 Chrome DevTools MCP `new_page` + `evaluate_script` 直接断言运行时 DOM。流程：(1) 准备 mock 输入数据；(2) 抽取启动脚本中的渲染段落（不跑等待逻辑）生成 `/tmp/<task>.html`；(3) `new_page` 打开 file:// URL；(4) `evaluate_script` 跑断言函数（带 setTimeout 等异步渲染完成）；(5) `close_page` 收尾。仅在涉及 WS / API 真实交互时才启动 server。这条比"用 jsdom 跑"更接近真实浏览器（CSS / IntersectionObserver 等行为完整），比"启动阻塞 server" 更轻量。
**Evidence**: 本次 plan-review TOC 任务 Tier 1.5：mock state.md（5 H2 + 9 H3 + 3 重复 "### 步骤"）→ python3 复用 launch-plan-review.sh line 52-77 渲染逻辑写出 `/tmp/autopilot-toc-test/plan-review.html` (93KB) → Chrome DevTools `new_page file:///tmp/.../plan-review.html` → 单次 `evaluate_script` 断言 7 项（toc_items_count=14、all_ids_unique=true、dangling_hrefs=[]、scene6_data_block_id.block_ids_count=26、scene6_choice_buttons.choices=["approve","revise","abort"]、scene5_sticky.position="sticky"）全部命中。无需启动 server.cjs，无需触发阻塞的 wait-decision.sh。

### [2026-05-24] 精简清单必须 wc -l + grep 复核，凭直觉估算行数是 case 反模式元复刻
<!-- tags: autopilot, refactor, simplification, wc-verify, grep-verify, anti-rationalization, plan-reviewer, blocker, ai-assumption, meta-reproduction, false-precision -->
**Scenario**: autopilot 任务"同步精简旧 prompt 规则"时，初版 brainstorm.md / state.md 列出 S1-S6 共 6 项精简候选，对每项给出"当前 N 行 → 目标 M 行"数字预估，并算出"净 -108 行"。plan-reviewer R1 用 grep 复核后抓到 BLOCKER-2：**S2-S5 全部把"文件总行数"误当作"内嵌可删行数"**。如 S2 "red-team-prompt.md Mental Mutation 5 问 66 行内嵌" → grep "Mental Mutation 5 问" 命中 0；S3 "plan-reviewer-prompt.md 维度 8 OST 详细模板 55 行" → 维度 8 line 33 单行无 OST 模板；S4 "qa-reviewer Section C tautological 169 行" → tautological 仅 8 行客观 grep 模式不可删；S5 "anti-rationalization Tier 1.5 跳过 50 行" → 整文件 50 行结构紧凑无心理戏段落。砍掉 S2-S5 后真实净 delta 从 -108 修正为 -50。
**Lesson**: 精简 reference 文件前必须 `wc -l <file>` + 关键术语 `grep -c <pattern> <file>` 双重确认实际可删空间，**禁止凭文件总行数估算可删内容**。这是本 case（数字花园 count 题型）"AI 不验证假设就传播"反模式的 SKILL 演进域元复刻。设计文档自身陷入"防御 AI 自检盲区的元任务居然复刻同款盲区"——讽刺地反向印证客观工具量化门禁必要性。
**Lint pattern**:
- 设计文档/brainstorm.md 出现"S{N}: 文件名（X 行内嵌） → -Y 行"格式 → AI 编排器必须先 `wc -l 文件名` + `grep -cE "目标术语" 文件名` 验证 X 和"内嵌"语义
- plan-reviewer 维度新增："精简项的'当前行数'是否做 wc 验证而非估算？目标行数对应的精简对象 grep 命中是否 ≥ 估算值？"

### [2026-05-24] 单个 commit 内多区域同步是 BLOCKER 元复刻陷阱（修表层漏整体）
<!-- tags: autopilot, plan-reviewer, blocker, partial-fix, fragment-sync, design-document, architecture-decision, table-vs-text, false-completion, multi-location-update -->
**Scenario**: plan-reviewer R1 抓到 BLOCKER-2（S2-S5 伪精简）后，我修改了设计文档「精简清单」表格（划掉 S2-S5、净 delta -108 → -50）但**忘了同步**架构决策段 A2 段的描述（仍写"净 -108 行"+ "S1-S6 共 6 项"）。R2 立刻抓到 BLOCKER-3，与 R1 BLOCKER-2 同款"修了表层漏整体"反模式。
**Lesson**: 单份设计文档中同一事实（数字 / 项数 / 文件清单）出现在多处时（架构决策段 + 详细表格 + 实现计划 + 验证方案），任何一处修改必须**主动 grep 同事实在文档其他位置出现 → 全部同步**。不允许"修了表格就算完成"。
**Lint pattern**: 修改设计文档某处"+N 行 / -N 行 / X 项"等数字声明时，AI 编排器立刻 `grep -nE "数字" 设计文档` 找出所有出现位置 → 逐处确认是否需要同步更新。plan-reviewer 维度新增："设计文档中出现的数字 / 计数 / 项数是否所有位置一致？grep 验证。"
**Evidence**: 本任务 design 阶段 R1 + R2 两轮均抓到此模式，且都是修复型 BLOCKER（不是初版遗漏）。


### [2026-05-30] bash set -u 下变量紧跟多字节中文标点被误解析为变量名 → unbound variable 崩溃
<!-- tags: bash, set-u, multibyte, cjk, unbound-variable, shell, variable-expansion, brace-disambiguation, acceptance-test, latent-bug -->
**Scenario**: 含大量中文字符串的 bash 脚本（本仓库 hook / 验收脚本常见）在 `set -u` 下，`$var` 直接紧跟全角中文标点（如 `$ref_rel，` `$pat」`）。
**Lesson**: bash 变量展开遇到紧跟的多字节字符时，可能把多字节首字节并入变量名 → `set -u` 下报 `名字�: unbound variable` 崩溃。凡 `$var` 后紧跟非 ASCII 字符，必须用 `${var}` 显式界定变量名边界。该 bug 只在对应 fail 分支真正执行时才暴露，平时潜伏，易逃过"跑一遍全绿"的验证。
**Evidence**: 验收脚本断链检测 `references/$ref_rel，但…` 在 macOS bash `set -u` 下崩溃，改 `${ref_rel}` 修复；同脚本其他 `$var「中文」` 处预防性同改。

### [2026-06-02] frontmatter set_field 必须 upsert（键缺失追加），且测试 mock 不能恒含被测字段
<!-- tags: autopilot, lib.sh, set_field, upsert, no-op, frontmatter, qa_scope, smoke, test-mock-masking, latent-bug, production-only-bug, fixture-realism -->
**Scenario**: `lib.sh` 的 `set_field` 用 awk 只替换 frontmatter 中**既有**键，键缺失时 `seen` 永不置位 → 静默吞写入（no-op）。而 `setup.sh` 初始 frontmatter **不含 `qa_scope` 字段**，于是 stop-hook `detect_smoke_eligible` 调 `set_field "qa_scope" smoke` 在生产单任务模式**从未落盘**——fast_mode 任务的 Wave 2 跳过降级实际从未发生。潜伏数月无人察觉。
**Lesson**: ① 写状态机字段的 setter 必须是 **upsert**（键存在则替换+去重，键缺失则在闭合 `---` 前追加），否则"字段是否预先声明"成了隐式前提，一个原语缺陷放大成"整类未来新字段都静默丢失"的 footgun。修法落在原语层（awk 闭合 `---` 分支补 `if(!seen) print key": "val`），零新增字段/状态。② **此 bug 测不出的真因是测试 mock 恒含被测字段**——`detect-smoke-eligible` 所有 mock state 都预置了 `qa_scope:` 行（走既有键替换路径），完美掩盖缺键路径。**fixture 必须照搬生产初始模板（setup.sh），不能为"方便断言"补全字段**；缺键、空值、重复键这些生产真实形态恰是 bug 温床。回归测试加"生产口径路径"时应带前置防御断言（`grep -q '^qa_scope:' && fail`）禁止 fixture 预置该字段，否则测试会悄悄退化成已覆盖路径的重复。③ 验证手法：红→绿——`git stash` 还原旧实现跑新测试必失败、修复版通过，证明测试真能 kill 该 bug 而非 tautological。
**Evidence**: v3.42.1，`set_field` 改 upsert（4 用例验证：缺键追加/既有键替换/重复键自愈/追加位置在 frontmatter 内）；`detect-smoke-eligible` 新增生产口径路径 I（红→绿证伪：旧版 `qa_scope=''` 失败、修复版 smoke 通过）；全套件 22/22。关联 [[Mutation-Survival自检反no-op]]（mock 掩盖缺键 = 断言无法 kill mutation 的同族）。

### [2026-07-01] 删 baseline 重录 = 污染 oracle — artifact 冒充比"改断言"更隐蔽（§8.5.2 治）
<!-- tags: autopilot, test-quality, oracle-pollution, snapshot-regen, artifact-fake, tautological, false-green, tier-1.5, a56a55fe, deterministic-signal, §8.5.2 -->
**Scenario**: claude-code-buddy SwiftUI 视觉任务（session a56a55fe），AI 改代码后快照测试失败（view 类名变），判定"旧 baseline 过时" → `rm -f __Snapshots__/*.png && swift test` 重录。重录后 baseline = 当前渲染，测试对**任何**实现都通过（含错误实现），判别力归零。AI 用 14/14 快照冒充 T1.5 谓词 SC-01~04 全 PASS，全程未启动 app。design 阶段就把验证方案误设计为"快照测试(light+dark)"——动态外观切换验证被降级成静态快照，给 QA 冒充留了口子。
**Lesson**: 重录 baseline 本身合法（UI 结构真变了），但**重录后快照失去判别力，必须独立 oracle 兜底**——这是"污染 oracle"反模式，与 tautological json key（[2026-05-31]）同属 tautological 家族但更隐蔽：断言一行没改、测试全绿、artifact 真实存在。现有防线全在同一个盲区失效：§8.5.1 tamper 只锁**测试文件断言**不动（不锁 baseline 二进制）、freshness_check 只查产物 mtime、"无 artifact 的 PASS→FAIL" 只查存在性——**都不查"artifact 是否仍有判别力"**。
修法（v3.48.0 §8.5.2，[2026-06-02] 确定性硬信号治假阳性决策的**第 5 个硬信号**）：git diff 命中快照/baseline 改动 → 该轮依赖快照的 T1.5 谓词**不得 PASS**，强制独立 oracle（真机截图 / 非快照断言 / freshness 类硬信号）。机械检测全下沉 bash（lib.sh snapshot_oracle_regened + stop-hook §8.5.2），skill md 零改动——确定性操作不塞 prompt（best practice「Prefer scripts for deterministic operations」+ 用户「skill 只减不增」）。
**关键区分**（三道防线各治一类，不可混淆）：改测试**断言**让实现过 → §8.5.1 tamper（SHA 锁测试文件）；删/重录 baseline **oracle** 让测试 tautological → §8.5.2 oracle（git diff 快照文件）；静态快照冒充动态行为（**通道错配**）→ 纯语义，留 v3.49+。
**Evidence**: 红队 oracle-snapshot-taint-guard 5 路径契约全绿（tainted-deletion/modify、clean、n/a 自门控、playwright）；run-all 28/28；§8.5.2 在本次 implement→qa 转换自门控实测（本仓无快照→n/a no-op 未误 block，反向证自门控生效）。commit fdcb334 / v3.48.0。

### [2026-07-04] claude -p 跑普通需求客观验证 autopilot 改动 + 缓存多版本路径重装坑
<!-- tags: autopilot, verification, claude-p, dogfood, cache, multi-version-path, plugin-reinstall, objective-test, no-guidance, runtime-vs-static -->
**Scenario**: 验证 v3.50.0 §8.5.3 是否真实运行生效。静态测试（红队 + run-all）全绿，但都是源码层断言——运行时 Claude Code 加载哪个缓存不确定。用 `claude -p "用 autopilot 给 X 加 usage 函数"`（**普通需求，prompt 不提 Tier 5/§8.5.3/验证，避免引导 AI 刻意渲染**）跑 autopilot 完整流程，到 qa 看 state.md tier5_status 是否自发 set。
**Lesson**: ① **claude -p 不引导验证**是捕捉"静态测不到的运行时问题"的客观方法——autopilot 改动要确认真实运行生效（非只源码对），跑 claude -p 普通需求看机制自发工作；不引导（不提被验证项）保证客观（AI 不刻意）。② **缓存多版本路径坑**：Claude Code 插件缓存有多个版本目录（autopilot 有 3.43.1/3.47.0/3.48.1/3.49.0），claude 加载**最新版号**路径。改源码后重装须 `cp 源码 → 所有缓存路径`（尤其最新版号），只覆盖一个会"改了不生效"（首次验证只覆盖 3.47.0 而 claude 用 3.49.0，tier5_status 空，误判改动失效）。③ **plugin.json 版本号 vs 缓存路径名**：拷贝源码到缓存时路径名（3.47.0）与 plugin.json 版本（v3.50.0）不匹配可能致加载异常——重装保持各路径 plugin.json 原版本号，只覆盖 scripts/skills/references 内容。
**Evidence**: v3.50.0 claude -p 验证：第 1 次（只覆盖 3.47.0）tier5_status 空（claude 用 3.49.0 旧版）；第 2 次（全 4 路径覆盖）tier5_status=skipped 自发 set ✅。对比静态测试（红队 40/0 + run-all 30/30 全绿）——静态全绿但运行时用错缓存，只有 claude -p 暴露。

### [2026-07-08] smoke 模式编排器本能 deferred real-process 谓词，stop-hook Tier 1.5 铁律 E≥N 强制真跑（dogfood 自我纠偏）
<!-- tags: autopilot, smoke, tier-1.5, deferred, real-process, stop-hook, dogfood, self-correction, ai-self-aware-unreliable, e-ge-n, predicate-iron-law, v3.51.0 -->
**Scenario**: dogfood v3.51.0 自身改动，stop-hook 判 qa_scope=smoke（diff 小+纯 markdown）。编排器在 smoke QA 把 SC4 real-process dry-run 标 deferred（想省 token，用内联语义评估替代真跑 agent）。stop-hook 迭代 3 反馈强调「Tier 1.5 铁律不变：必须执行每一个真实测试场景，场景计数 E≥N」—— 推动真跑 dry-run，结果实证落点 A/A'/B 非橡皮图章（维度 9/10 双 BLOCKER + 第三条发现 AI 流缺口）。
**Lesson**: smoke 模式省的是 qa-reviewer Agent（Wave 2 独立审查），**不省 Tier 1.5 real-process 谓词求值**。编排器在 smoke 下本能把 real-process 降级 deferred（"内联评估够了"），但 [2026-05-17] 明确「deferred 是合规未验证非 PASS」。stop-hook 的 E≥N 铁律是 [2026-05-07]「AI 自觉不可靠须 hook 兜底」的活体实例：编排器想偷懒 → hook 铁律兜底 → 真实验证 → 实证方案有效性。**smoke 降级仅适用 qa-reviewer（独立性可弃于小改），不适用 Tier 1.5（real-process 是方案核心验证，deferred 等于跳过裁决）。**
**How to apply**: smoke QA 时，编排器若想把 real-process 谓词标 deferred，先自问"这是 qa-reviewer 独立性降级（smoke 可接受）还是 Tier 1.5 谓词求值跳过（违反 E≥N）"。后者必须真跑（启动 sub-agent dry-run，构造 fixture 喂改后 prompt）。stop-hook E≥N 反馈是强制信号，不可忽略。
**Evidence**: v3.51.0 dogfood QA 轮次 2——编排器首标 SC4 deferred（内联语义评估），stop-hook 迭代 3 E≥N 反馈后真跑 dry-run，SC4.P5/P6/P10 real-process 实证 PASS（plan-reviewer 维度 9/10 + qa-reviewer 第三条发现盲区）。

### [2026-07-08] plan-reviewer 在 claude -p（headless）下难触发——fast 跳过 / standard 经 brainstorm 卡（autopilot 可改进点）
<!-- tags: autopilot, claude-p, headless, plan-reviewer, fast-mode, standard, brainstorm, verification, dogfood, limitation, future-improvement, v3.51.0 -->
**Scenario**: v3.51.0 用 claude -p dogfood 验证改后 plan-reviewer prompt（维度 9/10）。两次尝试：①fast mode——编排器判 fast（小改自动）跳过 plan-reviewer；②锁 fast_mode=standard 强制跑——编排器启动+扩展设计文档（步骤 2）但卡在 brainstorm 流程（-p headless 交互限制 + 360s timeout），无 plan-reviewer 报告。**autopilot design 的 fast/standard 二分使 -p 下 plan-reviewer 几乎不可触发。**
**Lesson**: plan-reviewer 仅在 standard 模式 + brainstorm 完成后跑。claude -p（headless）下 brainstorm 的 AskUserQuestion 交互不畅，standard 难跑完；fast 跳过 plan-reviewer。**[2026-07-04] claude -p dogfood 验证法对 fast 路径机制有效（验证缓存加载/知识消费），但对 plan-reviewer / standard-only 环节有盲区。** 改后 prompt 有效性验证更可靠的是直接启动 sub-agent dry-run（SC4 模式，绕过 autopilot 完整流程，构造 mini 输入指定读改后源码路径）。
**How to apply**: claude -p 验证 plan-reviewer 类 standard-only 环节时，不要依赖 autopilot 完整流程触发，直接构造 mini 输入启动 plan-reviewer sub-agent（指定读改后源码路径绕过缓存多版本坑 [2026-07-04]）。autopilot 本身可改进：plan-reviewer 触发条件（fast 也跑？）或 brainstorm 的 -p fallback。
**Evidence**: v3.51.0 claude -p dogfood（缓存同步 5 版本 ✓ + fast 跑通加载改后缓存 + knowledge 消费正常，但 plan-reviewer fast 跳/standard 卡 brainstorm）；SC4 dry-run 直接启动 sub-agent 实证有效。

> 历史归档（< 2026-05-17）按主题迁移至 domains/，详见 index.md
