<!-- domain: stop-hook 兜底逻辑 / 状态机字段 / flag-asymmetry / pending-subagent 检测 -->
# Stop-Hook & State Machine

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

### [2026-05-26] 「状态机切换 state file 后必须重读所有缓存到内存的字段」+「修第 1 个 bug 时不问第 N 个」三连击复刻
<!-- tags: autopilot, stop-hook, state-switch, stale-variable, cached-field, gate-reread, multi-link-failure, regression-recurrence, meta-lesson -->
**Scenario**: project auto-chain 失效在 v3.36.0 突然双坏，前后用了 **3 个版本（v3.36.1/v3.36.2/v3.36.3）** 才修完，每次发版都"自称修复完成"但实际还有下一环卡死。**v3.36.1** 修 SKILL.md merge §2 漏写 Auto-Chain step（AI 不写 next_task）；发版后用户在 claude-code-buddy 跑 project 模式仍卡死 → **v3.36.2** 修 stop-hook 不在 auto_approve=true 时跳过 review-accept gate；发版后用户跑到 002→003 仍卡死 → **v3.36.3** 终于发现 stop-hook 三处 Case 切换 state 后只重读 PHASE/ITERATION/MAX_ITERATIONS、**没重读 GATE/AUTO_APPROVE**（缓存到内存的旧 state 变量过期）。三次都是看着报错"修了最显眼的那环"，没系统排查整条链。

**Lesson**（分两层）：

**第 1 层 — 技术教训**：状态切换型脚本（stop-hook 这类「读 state → 处理 → 切到新 state → 继续处理」）在切换后必须**重读所有该状态相关的变量**，不只是当时业务最关心的几个。可操作清单：
- 列出 stop-hook 启动时从 state 读到内存的**全部变量**（PHASE / GATE / ITERATION / MAX_ITERATIONS / AUTO_APPROVE / NEXT_TASK / BRIEF_FILE / RETRY_COUNT ...）
- 每个 Case 切换后**全部重读**，不要挑「业务用得到的」— 因为下游分支可能用到当时没意识到的变量（本次就是「第 6 步审批门读 GATE，但切换处只想到了 phase」）
- 或者**抽函数**：`reload_state_vars()` 封装所有 `get_field` 调用，切换后调一次。比单点 grep 防御更强

**第 2 层 — 元教训：「单一根因偏见」反模式**
- 每次只修「看着像 root cause 的那一环」，不全链路排查
- v3.36.1 commit message 自称「修复 project 模式 auto-chain 失效回归」— 是字面意义的回归修复，但只修了 1/4 环就发布；v3.36.2 commit message 自称「修复双链第 2 环」（编号错了，实际是第 3 环），发版又卡；v3.36.3 终于把整条链画出来才看清还有第 2 环
- **修复模式建议（迁出本次三连击痛苦）**：
  1. 看到「X auto-chain 失效」类报告，**先画出从 X→Y 的完整状态机转换图**，标出每个 state 字段在每个转换点被读写的次数
  2. 用「我修了 A，那 B/C/D 是不是同样模式」**主动反问**，而不是"修完看似 OK 就发版"
  3. **每发一个 fix 都要追问"如果我这次修复有效，下一次同类 bug 还会从哪个角度出现"** — 这是「半生效 bug」(2026-05-26 patterns) 的元防御

**与 [[flag-asymmetry-half-effective-bug]]（[2026-05-26] patterns）的关系**：
- 那条是「同一 flag 在不同 phase 转换点的处理对称性」（数据流对称性）
- 本条是「状态切换后内存变量重读完整性」（时序对称性）
- 共享元规律：**任何"切换/新增/分支"动作都要追问"现有的其他对称点是否需要同步"**，否则形成"半生效"型 bug。本条进一步加上**「修第 1 个 bug 时强制画整链路」**的过程规约

**Evidence**:
- v3.36.3 修复后 R12 6/6 PASS（含双链第 2 环复现 fixture）；CI run 26450162873 success
- 三连击成本：3 个 patch 提交 + 3 次 CI + 3 次知识沉淀 ≈ 半天工作量，本可在 v3.36.1 一次性修完
- 用户痛苦证据：claude-code-buddy 002→003 卡死 18 分钟（stop.txt "Baked for 26m 30s" 跑完只为最后 stop-hook silent exit），是「修完一环看着 OK 但实际还卡」的真实代价

### [2026-05-26] 状态机新增「flag」字段时，所有读取该字段的转换点必须同步处理 — 否则形成「半生效」bug
<!-- tags: autopilot, stop-hook, state-machine, flag-asymmetry, auto-approve, review-accept, transition-coverage, double-link, regression-pattern -->
**Scenario**: v3.36.2 修的是 project auto-chain 失效**双链第 2 环**。stop-hook 在 phase=design 时正确处理了 `auto_approve=true` 跳过 AskUserQuestion 审批（line 553-555），但 phase=qa 通过后设的 `gate=review-accept` 在第 6 步「审批门检查」(line 491-497) **完全不看 auto_approve**，导致 auto-chain 子任务在 QA 后全部卡死等用户审批。bug 现场：claude-code-buddy 项目 001-launcher-skeleton 子任务 phase=qa + gate=review-accept + auto_approve=true，iteration 3 轮 stop-hook 全部 notify + exit 0，永不进 merge。整个 v3.36.1（修第 3 环 next_task）之前的 project 模式 auto-chain 双链皆坏，但**因为第 2 环卡死优先**，第 3 环的 bug 从未被触发到，所以 v3.36.1 也只是「修了一个不会触发的环节」，端到端仍坏。
**Lesson**: 状态机引入新「flag」字段（如 `auto_approve` 控制是否跳过人工审批）时，必须**枚举该字段所有应该影响的转换点**，逐个改造，而不是只改第一个想到的入口。可操作清单：
- **改前**：grep 现有代码所有读 flag 的位置（`grep -n "flag_name" *.sh`）；列出该 flag 应当影响的**所有状态转换边**（如 auto_approve 应影响：design→implement 审批、qa→merge 审批、auto-fix→qa 重试、implement→qa 失败等所有有"用户介入"语义的边）
- **改时**：每个转换边都要写一遍「if flag → 跳过；else → 现状」分支；同一个 flag 不应在 phase A 跳过审批、phase B 不跳过审批，除非显式记录例外（如本次的 phase 限定 qa 排除 auto-fix max_retries 兜底场景）
- **改后必测「跨 phase 双向反向」**：正向（flag=true 应该跳过）+ 反向 A（flag=false 现状不变）+ 反向 B（flag=true 但 phase 是兜底场景应该不跳过）。R12 就是这个模式的实例（3 条断言覆盖正向 + 双向反向）
- **元层防御**：「双链 / 多链 bug」很常见 — 一个流程任意一环坏都会停下，所以一个环修复后端到端仍坏是常态。修第 1 个 bug 时**问自己「这条链上还有没有可能同样的失效模式」**，而不是只看 stacktrace 的第一个错。本次 v3.36.1 修了第 3 环，但当时未问「QA→merge 之间的审批门是否也漏了 auto_approve」—— 应该问。

**与 [[asymmetric-fallback]]（[2026-05-06] patterns）的关系**：
- 2026-05-06 是「create/repair 新增的兜底路径与原 happy path 功能不对称」（功能集对称性）
- 2026-05-26 是「同一 flag 在不同 phase 转换点的处理对称性」（数据流对称性）
- 共享元规律：**新增分支 / 新增字段 / 新增路径都要追问「现有的其他对称点是否需要同步改造」**，否则会形成"半生效"型 bug，比纯回归更难发现（因为局部测试都过、只有端到端才坏）

**Evidence**:
- v3.36.2 修复后 R12 5/5 PASS（含 2 个反向）、CI run 26412840931 success。
- 端到端：v3.36.1 (next_task 修复) + v3.36.2 (review-accept gate 修复) 双链同修，project 模式 auto-chain 才真正端到端 work。
- 「修第 1 环不问第 N 环」是本次教训的核心 — v3.36.1 commit message 自称「修了 cdad541 引入的 project 模式 auto-chain 失效回归」，但实际只修了 1/2 个环节，发布即用即坏。下次修复 X 链路时强制问「这条链上还有没有同样模式的失效点」。

### [2026-05-11] tail -c + jq 流式解析必须丢首行 + 走 fail-safe 兜底，否则在长会话下死循环
<!-- tags: autopilot, stop-hook, jq, tail, byte-cut, fail-safe, fail-unsafe, has-pending-subagents, parse-error, detection-function -->
**Scenario**: stop-hook v3.25.x 用 `tail -c 2097152 $transcript | jq -rs '...'` 检测后台 sub-agent 是否在跑。短会话下 transcript < 2MB 时 tail 直接拿到完整文件，jq 正常工作。但当会话超长（实测 5.93MB transcript），`tail -c` 会从字节偏移 2MB 处直接截断，几乎必然落在 JSON 行中段（实测首行 = `tokens":1,"cache_creation_input_tokens":1447,...`，非合法 JSON）。jq -rs 第一行解析就报 `parse error: Invalid literal at line 1, column 1` 退出非零，函数 `|| return 1` 走错误降级。
**Lesson**: 两条独立护栏，缺一不可——
(1) 解析前必须丢弃首行（`tail -c N | tail -n +2`），把字节切的破损行从输入剔除；首行删后剩余 ~(N - 一行) 仍是合法 JSON 流。
(2) 解析失败时**不能**走"视为无 pending"的 fail-unsafe 路径——这是上次灾难的根源（[2026-05-07] 决策的 Trade-offs 节"transcript 损坏/jq 失败时降级返回 1"被实证为反 pattern）。改为：用 grep 在 raw tail 扫文本字面量 `"status":"async_launched"` / `<status>completed</status>`，launched - completed > 0 即视为 pending（fail-safe）。这样 jq schema 未来再变、tail 切再奇怪，"无限唤醒"灾难不会重演。
任何在 hook 里跑的"探测函数"（决定是否阻塞 / 是否唤醒 AI），都必须默认 fail-safe，不能 fail-unsafe——错误降级方向就是这类函数的安全分界。
**Evidence**: v3.25.1 → v3.26.0 升级，error.txt 复现真实 transcript 5.93MB，蓝/红队 ID 在 4.4M offset 处。R1 直接证据：旧版 `tail -c 2097152 $REAL | jq -rs ...` 报 `parse error: Expected value before ',' at line 1, column 1`，新版 `tail -c 4194304 $REAL | tail -n +2 | jq -rs ...` 输出 `2`（正确检测 2 个 async_launched）。R3 端到端对照：同一 stdin 投入旧/新 stop-hook，旧版构造 block JSON 唤醒主 agent（=死循环根因），新版 stdout 空 + stderr "静默等待"（=修复）。新增 `has-pending-subagents.acceptance.test.sh` 13 场景全 PASS（C3/C7/C10b 是 error.txt 三个根因场景）。

### [2026-04-12] "从缓存同步源码" 操作会连带回退不相关的文件改动
<!-- tags: autopilot, cache-sync, regression, stop-hook, source-of-truth -->
**Scenario**: v2.8.0 在 stop-hook.sh 和 setup.sh 中实现了 knowledge_extracted 守卫，同时 SKILL.md 大幅重写意外丢失了 v2.9.0~v2.10.0 的功能。v2.13.0 的修复方案是"从插件缓存同步源码回来"，但缓存中的 stop-hook.sh/setup.sh 是 pre-v2.8.0 版本（缓存只更新了 SKILL.md），导致 knowledge_extracted 守卫被连带回退。
**Lesson**: 插件缓存是只读副本，其中的文件版本可能落后于源码。"从缓存同步"时必须逐文件 diff 审查，不能批量覆盖。特别是多个文件在同一版本被修改时，缓存可能只包含部分文件的更新。核心原则：源码是唯一真相，缓存永远不应反向覆盖源码。
**Evidence**: commit 4f7fe50 的 diff 显示 stop-hook.sh 丢失了 18 行 knowledge_extracted 守卫代码，setup.sh 丢失 knowledge_extracted 字段。从 v2.13.1 到 v3.12.1（跨 20+ 版本）知识提取完全失效，claude-code-buddy 项目 9 个已完成任务零知识沉淀。

### [2026-04-17] Early-exit 守卫阻断后续添加的合法代码路径
<!-- tags: autopilot, stop-hook, guard, early-exit, ordering, knowledge-extracted -->
**Scenario**: stop-hook.sh 的 knowledge_extracted 守卫（v2.8.0）在 phase=done 时检查并 exit 0 回滚到 merge。v3.12.1 在守卫之后添加了 Case 0.5（项目 design auto-chain），但 Case 0.5 永远无法执行——守卫先触发 exit，后续代码全部不可达
**Lesson**: Shell 脚本中带 `exit 0` 的守卫会创建隐式的顺序依赖：守卫之后添加的任何新路径都需要先通过守卫。新增 phase=done 的合法路径时，必须同步审查所有前置守卫是否需要豁免。检查方法：搜索 `exit 0` 前的条件判断，确认新路径是否被覆盖
**Evidence**: autopilot.case 行 494 "知识提取回滚" — 项目 design 完成后守卫误触发，Case 0.5 auto-chain 被短路，首个 DAG 任务未自动启动。修复：守卫内增加 mode=project+brief_file="" 和 mode=project-qa 豁免

