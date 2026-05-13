# Patterns & Lessons

### [2026-05-11] tail -c + jq 流式解析必须丢首行 + 走 fail-safe 兜底，否则在长会话下死循环
<!-- tags: autopilot, stop-hook, jq, tail, byte-cut, fail-safe, fail-unsafe, has-pending-subagents, parse-error, detection-function -->
**Scenario**: stop-hook v3.25.x 用 `tail -c 2097152 $transcript | jq -rs '...'` 检测后台 sub-agent 是否在跑。短会话下 transcript < 2MB 时 tail 直接拿到完整文件，jq 正常工作。但当会话超长（实测 5.93MB transcript），`tail -c` 会从字节偏移 2MB 处直接截断，几乎必然落在 JSON 行中段（实测首行 = `tokens":1,"cache_creation_input_tokens":1447,...`，非合法 JSON）。jq -rs 第一行解析就报 `parse error: Invalid literal at line 1, column 1` 退出非零，函数 `|| return 1` 走错误降级。
**Lesson**: 两条独立护栏，缺一不可——
(1) 解析前必须丢弃首行（`tail -c N | tail -n +2`），把字节切的破损行从输入剔除；首行删后剩余 ~(N - 一行) 仍是合法 JSON 流。
(2) 解析失败时**不能**走"视为无 pending"的 fail-unsafe 路径——这是上次灾难的根源（[2026-05-07] 决策的 Trade-offs 节"transcript 损坏/jq 失败时降级返回 1"被实证为反 pattern）。改为：用 grep 在 raw tail 扫文本字面量 `"status":"async_launched"` / `<status>completed</status>`，launched - completed > 0 即视为 pending（fail-safe）。这样 jq schema 未来再变、tail 切再奇怪，"无限唤醒"灾难不会重演。
任何在 hook 里跑的"探测函数"（决定是否阻塞 / 是否唤醒 AI），都必须默认 fail-safe，不能 fail-unsafe——错误降级方向就是这类函数的安全分界。
**Evidence**: v3.25.1 → v3.26.0 升级，error.txt 复现真实 transcript 5.93MB，蓝/红队 ID 在 4.4M offset 处。R1 直接证据：旧版 `tail -c 2097152 $REAL | jq -rs ...` 报 `parse error: Expected value before ',' at line 1, column 1`，新版 `tail -c 4194304 $REAL | tail -n +2 | jq -rs ...` 输出 `2`（正确检测 2 个 async_launched）。R3 端到端对照：同一 stdin 投入旧/新 stop-hook，旧版构造 block JSON 唤醒主 agent（=死循环根因），新版 stdout 空 + stderr "静默等待"（=修复）。新增 `has-pending-subagents.acceptance.test.sh` 13 场景全 PASS（C3/C7/C10b 是 error.txt 三个根因场景）。

### [2026-05-10] git worktree list --porcelain 第一项稳定为主仓库，按位置跳过优于按路径比对
<!-- tags: git, worktree, porcelain, position-stable, run-anywhere, doctor, autopilot, path-resolution -->
**Scenario**: 在仓库内任意位置（主仓库 / linked worktree）运行的脚本，需要遍历"非主仓库"的 worktree。
**Lesson**: `git worktree list --porcelain` 输出顺序是 git 的稳定契约——第 1 项总是主仓库（main worktree），无论 cwd 在哪。优于"算出 main 路径再按字符串比对"——后者依赖 `git rev-parse --show-toplevel`，在 worktree 内返回 worktree 自身路径而非主仓库根，必须配 `--git-common-dir + dirname` 才正确（参 worktree.mjs:46 `repoRoot()`）。按位置跳过既避开这个解析陷阱，又使代码"运行路径无关"——这是写"在任何子目录都要工作"的脚本时的稳定模式。
**Evidence**: doctor SKILL Dim 8 worktree 健康抽查初版 `MAIN_ROOT=$(git rev-parse --show-toplevel); [ "$wt" = "$MAIN_ROOT" ] && continue`，cwd 在 worktree 内时 MAIN_ROOT 错指当前 worktree → 主仓库被误当 worktree 检查（场景 8 失败）。改 `awk '/^worktree / {n++; if (n==1) next; print $2}'` 后场景 8 通过，同时删掉 MAIN_ROOT 变量。这条 pattern 是 [2026-03-27] "Worktree 路径解析统一处理策略"的精简补丁——不是所有场景都需要 `--git-common-dir`，能用 porcelain 顺序就别引入 path 解析。

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

### [2026-05-09] 主对话需等待外部 UI 操作时，前台同步 Bash + 长 timeout 优于 run_in_background
<!-- tags: autopilot, claude-code, bash-tool, run-in-background, ux, html-review, blocking-call -->
**Scenario**: 涉及"用户在外部界面（浏览器/外部 GUI）操作 → 触发本地脚本完成 → Claude 主对话基于脚本输出继续"的功能，例如 HTML 评审、外部审批表单、远程触发。如果 Claude 用 `run_in_background: true` 把等待脚本扔后台，会破坏自动续上：用户操作完后还得回终端发一条消息（"我点完了"），Claude 才会去读结果文件——多一次无意义的二次操作。
**Lesson**: 这类场景必须**前台同步** Bash 工具调用（`run_in_background: false`），并把 `timeout` 显式设到 600000ms（工具最大值 10 分钟）。bash 阻塞期间用户在浏览器/外部 UI 操作，操作完成后脚本立即 stdout 输出 → bash 工具立即返回 → 主对话自动接住继续。代价是主对话挂起 ≤10 分钟，但 99% 场景用户在几十秒内完成；少数 >10 分钟超时场景应有 fallback（AskUserQuestion + preview）。这是工具调用的隐含语义，必须在 SKILL.md 显式写明（"前台同步 / 禁用 run_in_background / timeout=600000"），否则 Claude Agent 自由选择会偏向后台。
**Evidence**: v3.22 HTML plan review 上线时演示发现：第一次后台启动 → 用户点完按钮后还要回终端发消息触发我读 `/tmp/plan-review-out.json`，体验差。改前台同步后第二次演示 bash 立即返回 stdout JSON，0 次二次操作。文档锁定：SKILL.md 步骤 4c + html-review-guide.md 4c 调用规范段；红队 acceptance 加 C3h/C3i 断言。

### [2026-05-09] macOS `tail -F | grep -m1 | timeout` 退出码语义不可靠，依赖 stdout 非空判成功
<!-- tags: bash, macos, tail, grep, timeout, exit-code, event-watching, wait-decision, autopilot -->
**Scenario**: 实现"watch 一个 append-only 文件，匹配第一行符合条件的内容后退出"的 bash 脚本。直觉写法 `timeout 30 tail -F file | grep -m1 PATTERN`，期望成功匹配 → exit 0，超时 → exit 124。
**Lesson**: macOS（BSD tail + GNU coreutils timeout）下，**即使 grep -m1 匹配成功**，tail 进程不会因为 grep 关闭管道（SIGPIPE）主动退出，外层 timeout 持续到时限到达 → 整个管道被 SIGTERM 杀死 → 退出码 = 124（超时码），与真正超时无法区分。三种修复方案：(1) 调用方以"stdout 非空且为合法 JSON"作为成功判据，不查退出码；(2) 脚本内用 FIFO + 后台 tail + while read 循环，匹配后主动 `kill $TAIL_PID`；(3) 用 `head -1` 替代 grep（但需要预过滤）。autopilot 同时采用 (1)+(2) 双保险，并在 SKILL.md 文档明确写"以 stdout 非空判成功"。
**Evidence**: wait-decision.sh 实现时遇到，Plan 审查 `references/plan-reviewer-prompt.md` 的"BLOCKER 级"阶段已发现并预警（设计文档「Plan 审查改进建议 1」记录）。修复后红队 22 项断言通过（含超时场景 stdout 为空 + 退出码非 0 的双重断言 C1g）。

### [2026-05-06] 新增兜底路径暴露 create / repair 功能不对称
<!-- tags: autopilot, worktree, repair, create, asymmetry, fallback, idempotent, bootstrap -->
**Scenario**: v3.15.0 新增 SessionStart hook 兜底初始化 worktree，调用 `worktree.mjs::repair()`。实测发现 worktree 缺 `local-config.json`（dev 端口配置），导致 dev server 抢占默认端口
**Lesson**: 新增"兜底/恢复"路径调用既有 secondary 函数（如 repair）时，必须确认该函数 feature-complete——独立完成全部初始化。原 create() 流程是「create() → 内部调 repair() + 末尾写额外文件」，create() 在 repair 之外做的副作用都是隐式 gap，任何只走 repair 的新路径都会漏。同时，bootstrap "已配好" silent-exit 的检查项必须是 "已配置态" 完整指纹，否则受影响的存量安装永远不会被 SessionStart 自愈。诊断口径：列出 create() 调 repair 后做的所有副作用 → 逐项确认 repair 是否做 → 是否进入 silent-exit 检查
**Evidence**: v3.15.1 修复：抽 `writeLocalConfig(worktreePath)` 到 repair() 末尾（幂等：仅当 .git 是文件且 local-config.json 不存在时写），create() 删重复逻辑；同步更新 worktree-bootstrap.sh 的"已配好"检查链补 `[ -f local-config.json ]`，让存量受影响 worktree 在下次 SessionStart 自动 repair

### [2026-05-04] Worktree 检测使用 .git 文件/目录区分法
<!-- tags: autopilot, worktree, shell, detection -->
**Scenario**: 需要在 shell 脚本中判断当前是否在 git worktree 中，以决定 active 指针存储路径
**Lesson**: `[[ -f "$PROJECT_ROOT/.git" ]]` → worktree（.git 是文件指向主仓库），`[[ -d "$PROJECT_ROOT/.git" ]]` → 主仓库（.git 是目录）。此方法比 `git worktree list | grep` 更快且无外部命令依赖
**Evidence**: `git worktree` 约定 .git 在 worktree 中为文件（内容 `gitdir: ../.git/worktrees/<name>`），在非 worktree 中为目录。lib.sh 中 get_worktree_name() 已验证

### [2026-03-21] 多处引用同一数据（版本号 / 计数 / 路径）容易长期不同步
<!-- tags: autopilot, doctor, consistency, version, dimension, lint -->
**Scenario**: 文档中多处引用同一数据（版本号、维度计数、模块数量、特定路径等）时，单一升级流程或人工记忆无法保证全部位置同步更新
**Lesson**: 同一数据散布在多处时，应优先选择以下机制之一：(1) 集中化为单一来源（如 CLAUDE.md 项目元数据中央仓库）+ 派生引用 (2) 自动化 lint / 健康检查工具发现不一致 (3) 升级脚本主动搜索全部出现位置而非硬编码文件清单。仅靠"提醒人工同步"会反复失败
**Evidence**:
- 案例 1: README.md autopilot 标题版本号停留了多个版本未与 CLAUDE.md 更新日志同步，autopilot-commit 升级流程仅覆盖 plugin.json/package.json
- 案例 2: v3.14.0 升级 doctor Dim 11→12，但 CLAUDE.md L58 "11 维度评分" 和 L79 "11 维度加权评分（11 项枚举）" 同步遗漏，由 Tier 2b code-quality-reviewer Agent 在 QA 阶段发现并 auto-fix 修复——此即 Dim 12 知识库健康度维度本身需要解决的问题

### [2026-03-21] Skill 插件 Progressive Disclosure 重构模式
<!-- tags: skill, progressive-disclosure, plugin, refactoring -->
**Scenario**: npm-toolkit SKILL.md 内联所有内容（排障/模板/高级用法），导致行数膨胀（195+311 行），不符合 <500 行最佳实践
**Lesson**: 按信息频率拆分：核心流程（每次都需要）保留在 SKILL.md，低频内容（排障/高级模式/工具选型）外置到 `references/` 目录。引用用相对路径 `See [references/xxx.md](references/xxx.md)`。拆分后 SKILL.md 精简 30-40%，Claude 按需加载 references 文件。关键：引用只保持一层深度（SKILL.md → references/），不嵌套引用
**Evidence**: npm-toolkit 重构：npm-publish 195→165 行（-15%），github-actions-setup 311→196 行（-37%），3 个 references 文档（106+224+239 行），24/24 验收测试通过

### [2026-03-22] 通用编排器不应替代领域专业 Skill
<!-- tags: autopilot, skill-delegation, implement, domain-workflow -->
**Scenario**: 用户用 `/autopilot` 批量添加 8 个汉字到 little-bee 项目，目标描述中明确提到"使用 add-hanzi skill"，但蓝队 Agent 从零实现而非调用已有 Skill
**Lesson**: 领域 Skill 封装了经过验证的工作流（步骤顺序、工具链约定、资产管理），蓝队 Agent 从零实现会导致：(1) 全量覆盖型脚本误删数据（audio-index 丢失 147 字配置） (2) 工具链约定不了解（上传到错误 Blob store、MiniMax 文件路径混乱） (3) 大量 API 调用浪费（音频生成 3 轮 144 次调用，96 次浪费）。解决：implement 阶段新增路由判断，设计文档声明委托 Skill 时走委托路径
**Evidence**: little-bee conversation-2026-03-22-111711.txt，5028 行对话记录，autopilot v2.12.0 新增 Skill 委托机制

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

### [2026-03-21] HTML comment tags 比 YAML frontmatter 更适合 AI 知识标签
<!-- tags: knowledge, tags, ai-parsing -->
**Scenario**: 需要为知识条目添加可检索的标签元数据
**Lesson**: 使用 `<!-- tags: tag1, tag2 -->` HTML comment 格式优于 YAML frontmatter。原因：(1) 不影响 Markdown 渲染的可读性 (2) AI 解析简单（正则即可） (3) 与 Markdown 标题行紧邻，上下文关联清晰 (4) Git diff 友好
**Evidence**: 红队验收测试 41/41 通过，AI 能正确识别和匹配 HTML comment 中的 tags（knowledge-upgrade.acceptance.test.mjs:85-91）

### [2026-03-24] SKILL.md 步骤标题需包含可搜索的"步骤"前缀
<!-- tags: autopilot, skill, naming-convention, testing -->
**Scenario**: 红队验收测试用 regex `/(?:步骤|step|Step)\s*N/` 提取 SKILL.md Phase: design 的步骤内容，但实际标题格式是 `#### N. Title`（无"步骤"前缀），导致 7/7 步骤测试全部失败
**Lesson**: SKILL.md 的步骤标题应使用 `#### 步骤 N. Title` 格式而非裸数字 `#### N. Title`。(1) 中文"步骤"前缀让步骤可被正则稳定提取 (2) 与文档内文中"继续到步骤 5"的引用格式一致 (3) 对 AI 解析更友好。auto-fix 只需在 Phase: design 的 6 个步骤标题前加"步骤"前缀即可修复
**Evidence**: tests/plan-reviewer.acceptance.test.mjs 第 154-163 行 regex 匹配失败，修复后 17/17 测试通过

### [2026-03-24] 插件合并时红队路径假设容易出错
<!-- tags: autopilot, red-team, testing, file-path, merge -->
**Scenario**: 将 worktree-setup 合并到 autopilot 时，红队仅凭设计文档编写文件存在性验收测试，对项目目录结构做出错误假设——检查 `worktree.test.mjs`（实际是 `worktree.acceptance.test.mjs`）、检查 `references/knowledge-engineering.md`（实际路径是 `skills/autopilot/references/knowledge-engineering.md`）
**Lesson**: 红队信息隔离在"文件迁移/重组"类任务中有天然劣势：文件名和嵌套路径需要精确匹配，但红队只看设计文档无法确认真实路径。对此类任务，设计文档应在文件影响范围表中提供完整的绝对路径而非缩写，或在验证方案中给出精确的文件存在性检查命令
**Evidence**: 当时的 worktree-merge.acceptance.test.mjs 27 测试中 2 个因路径假设失败（25/27 通过），均为红队路径推测错误而非实现缺陷（该测试文件因绑定 v3.0.0 一次性迁移、长期不在 npm test 内、断言全面腐烂，已于 2026-05-10 删除）

### [2026-03-25] 符号链接检测 ≠ worktree 检测，防御需多层
<!-- tags: worktree, knowledge, symlink, fallback, defense-in-depth -->
**Scenario**: autopilot merge 阶段知识提取检查 `.autopilot` 是否为符号链接来判断是否在 worktree 中。little-bee 项目的 worktree 中符号链接缺失（可能是旧 worktree 或 hook 失败），导致知识被提交到 worktree 分支而非主仓库
**Lesson**: 单一检测机制不可靠时必须设计 fallback 链。符号链接是"机制"不是"状态"——机制可能失败但状态（是否在 worktree）不变。正确做法：(1) 检查符号链接 → (2) 检查 `.git` 是否为文件（worktree 的可靠标志） → (3) 回退到正常路径。同时在预防层确保符号链接尽可能存在（repair() 预创建）
**Evidence**: little-bee eager-jingling-kay worktree 日志第 1508-1519 行：AI 检测到非符号链接后直接走 fallback 本地提交，知识丢失在 worktree 分支

### [2026-03-26] Tier 1.5 场景部分执行等于未执行
<!-- tags: autopilot, qa, tier-1.5, smoke-test, partial-execution -->
**Scenario**: little-bee-cli autopilot 全流程中，设计了 3 个真实测试场景（--help、hanzi list、hanzi search），但 QA 只执行了场景 1（--help），跳过了需要 server 的场景 2/3
**Lesson**: 48 个红/蓝队测试全通过但 4 个 bug（token 字段名不匹配、auth=false 不带 Cookie、CDN 缓存、endpoint 错误）全靠用户手动发现。根因：(1) Tier 1.5 场景部分执行但报告中只列出已执行的，遗漏不可见 (2) 红队 mock 过度跳过真实数据流 (3) 蓝队假设 endpoint 路径未运行时验证。修复：结果判定新增场景计数匹配检查，stop-hook QA prompt 注入 Tier 1.5 完整性提醒
**Evidence**: conversation-2026-03-26-003626.txt 行 2890-2978，AI 自述"偷懒了"

### [2026-03-27] Skill 规范不应硬编码项目特定的文件路径
<!-- tags: autopilot-commit, skill, version, hardcoding, claude-md -->
**Scenario**: autopilot-commit SKILL.md 硬编码了 3 个版本文件路径（plugin.json/package.json/CLAUDE.md），但遗漏了 marketplace.json，导致 4 个插件版本长期不同步（最大差 6 个版本）
**Lesson**: Skill 规范应引导 AI 从项目文档（CLAUDE.md）中自主发现需要操作的文件，而非硬编码固定路径。硬编码的问题：(1) 新增文件时必须同步修改 Skill 规范 (2) 不同项目结构不同，硬编码不通用 (3) AI 按列表执行时容易"完成列表=完成任务"的心态遗漏列表外的文件。正确做法：CLAUDE.md 集中维护项目特定信息，Skill 规范只描述通用流程（发现→更新→校验）
**Evidence**: marketplace.json autopilot 版本 3.0.1 vs plugin.json 3.3.1（差 6 个版本），eb0e38c 修复后仍未覆盖

### [2026-03-30] SKILL.md 文档文本中的标识符会干扰红队正则测试
<!-- tags: autopilot, red-team, testing, indexOf, text-proximity, regex -->
**Scenario**: (1) 成本优化章节表格包含 agent 名称（plan-reviewer、红队、design-reviewer），红队验收测试用 `indexOf('agent-name')` + 2000 字符窗口查找 `model: "sonnet"`，首次匹配命中文档文本而非 Agent 调用行。(2) v3.8.0 步骤 2 文本"供步骤 3 的 Plan 审查使用"包含"步骤 3"，红队测试用 `/步骤\s*3/` 提取步骤 2 内容时正则提前截断，导致步骤 2 中的降级/隔离关键词无法被检测到。
**Lesson**: SKILL.md 中文档描述引用其他步骤编号或 agent 标识符时，会被红队测试的正则/indexOf 匹配机制误命中。两类缓解：(1) agent 名称用中文泛称，精确标识符只出现在技术定义处 (2) 跨步骤引用避免使用"步骤 N"格式，改用"后续 Plan 审查"等无编号泛称。核心原则：文档描述中的任何标识符都可能成为正则锚点。
**Evidence**:
- 案例 1: v3.5.2 红队 17 测试 2→3→1→0 失败修复 3 轮（成本优化表格中的 agent 名称触发 indexOf 误匹配）
- 案例 2: v3.8.0 红队 36 测试因"步骤 3"引用导致 step2Match 仅捕获 294 字符（预期 ~800），修复改为"后续 Plan 审查"
- 案例 3: v3.14.0 doctor Dim 12 章节内 inline code `### [日期]` 含 `## ` 子串触发红队 regex lookahead `##\s` 提前截断，章节抽取丢失第 5 项关键词「元信息」；修复改为"H3 三级标题（[日期] 开头）"文字描述。揭示 Markdown 章节标识符（`### `/`## `）在 inline code 中也是正则锚点

### [2026-04-12] "从缓存同步源码" 操作会连带回退不相关的文件改动
<!-- tags: autopilot, cache-sync, regression, stop-hook, source-of-truth -->
**Scenario**: v2.8.0 在 stop-hook.sh 和 setup.sh 中实现了 knowledge_extracted 守卫，同时 SKILL.md 大幅重写意外丢失了 v2.9.0~v2.10.0 的功能。v2.13.0 的修复方案是"从插件缓存同步源码回来"，但缓存中的 stop-hook.sh/setup.sh 是 pre-v2.8.0 版本（缓存只更新了 SKILL.md），导致 knowledge_extracted 守卫被连带回退。
**Lesson**: 插件缓存是只读副本，其中的文件版本可能落后于源码。"从缓存同步"时必须逐文件 diff 审查，不能批量覆盖。特别是多个文件在同一版本被修改时，缓存可能只包含部分文件的更新。核心原则：源码是唯一真相，缓存永远不应反向覆盖源码。
**Evidence**: commit 4f7fe50 的 diff 显示 stop-hook.sh 丢失了 18 行 knowledge_extracted 守卫代码，setup.sh 丢失 knowledge_extracted 字段。从 v2.13.1 到 v3.12.1（跨 20+ 版本）知识提取完全失效，claude-code-buddy 项目 9 个已完成任务零知识沉淀。

### [2026-04-17] SKILL.md 决策树中后置章节会被 AI 跳过
<!-- tags: autopilot, skill, decision-tree, priority, plan-mode, auto-approve -->
**Scenario**: SKILL.md Phase: design "⚠️ 关键规则" 只检查 plan_mode，auto_approve 快速路径作为独立章节在后面。auto-chain 子任务 auto_approve=true 时 AI 按关键规则"立即 EnterPlanMode"，跳过了后面的 Auto-Approve 快速路径
**Lesson**: AI 执行 SKILL.md 时，⚠️ 标记的"关键规则"具有最高指令权重——AI 读到"立即"就行动，不会继续扫描后续章节是否有例外。所有决策分支必须集中在同一个决策树中，不能分散到多个独立章节。修复：将 auto_approve 检查提升为关键规则决策树的第一优先级
**Evidence**: case 文件显示 AI 输出"Brief 模式…进入 Plan Mode"后立即调用 EnterPlanMode。stop-hook prompt 虽正确注入"跳过 Plan Mode"，但 SKILL.md 结构性指令优先级更高

### [2026-04-17] Early-exit 守卫阻断后续添加的合法代码路径
<!-- tags: autopilot, stop-hook, guard, early-exit, ordering, knowledge-extracted -->
**Scenario**: stop-hook.sh 的 knowledge_extracted 守卫（v2.8.0）在 phase=done 时检查并 exit 0 回滚到 merge。v3.12.1 在守卫之后添加了 Case 0.5（项目 design auto-chain），但 Case 0.5 永远无法执行——守卫先触发 exit，后续代码全部不可达
**Lesson**: Shell 脚本中带 `exit 0` 的守卫会创建隐式的顺序依赖：守卫之后添加的任何新路径都需要先通过守卫。新增 phase=done 的合法路径时，必须同步审查所有前置守卫是否需要豁免。检查方法：搜索 `exit 0` 前的条件判断，确认新路径是否被覆盖
**Evidence**: autopilot.case 行 494 "知识提取回滚" — 项目 design 完成后守卫误触发，Case 0.5 auto-chain 被短路，首个 DAG 任务未自动启动。修复：守卫内增加 mode=project+brief_file="" 和 mode=project-qa 豁免

### [2026-05-07] Cache 命中率高不等于 token 成本低
<!-- tags: token-analysis, prompt-cache, methodology, autopilot -->
**Scenario**: autopilot 优化分析时直觉认为「session 总 token = SKILL.md 加载 × N 轮 + 工具调用」，倾向于优化 SKILL.md 大小。但 5 天 Top 5 session 数据显示：cache_read 占 95-99%（最高 session 116.8M token / 1119 turns，cache_create 几乎为 0）。这意味着 prompt cache 已经把 SKILL.md / references 重复加载这部分压平了。真实成本驱动是：(1) sub-agent cold start（每次 ~500K，无法被 parent cache 共享）；(2) Bash 大输出 / 文件全量 Read 进入累积上下文（每个后续 turn 都要 cache_read 这些累积内容）；(3) 状态文件膨胀（同上）。
**Lesson**: 用「绝对 token 数据 per-session」而非「cache 命中率 %」作为优化决策依据。命中率高反而说明该路径的 token 已经被有效平摊，对该路径继续做小优化 ROI 极低；应转向 cache 无法覆盖的成本源。具体方法：`jq` 解析 ~/.claude/projects/*/jsonl 累加单个 session 的 input/output/cache_read/cache_create，按总量降序找 top sessions，看 cache_create 异常值或大 Bash 输出，定位真实漏点。
**Evidence**: 本轮（2026-05-07）三项优化均针对 cache 无法覆盖的成本：合并 qa reviewer（减 cold start）、stop-hook 自动压缩 QA 报告（减累积 Read 成本）。SKILL.md 行数从 699 → 675 仅减 24 行的"防合理化指南抽离"反而是收益最低的一项——前两轮已经把 SKILL.md 优化到 cache 命中率 95%+。

### [2026-05-07] 函数支持"测试 mock 输入"分支会掩盖生产路径 bug
<!-- tags: autopilot, red-team, dual-path, function-signature, qa-blind-spot, production-vs-test -->
**Scenario**: stop-hook.sh 的 `detect_smoke_eligible($1)` 为兼容红队测试用 invoke_detect 传入 mock diff 临时文件，新增了 $1 参数处理"测试模式分支"（如果 $1 是可读文件就当 raw diff 解析）；生产调用错写为 `detect_smoke_eligible "$STATE_FILE"`，状态文件路径被当作 mock diff，函数始终走"测试分支"对 state.md 做 `grep ^[+-]` → diff_lines 几乎总是 0 → 路径 C（≤30行/≤3文件）总满足 → smoke 永远触发，自动检测机制完全失效。
**Lesson**: 当函数同时支持"测试参数化输入"和"生产自动 fetch"两条分支时，红队验收测试只会覆盖前者（因为它本就是为前者设计）；生产路径会变成"红队铁律"的盲区。三层防御：(1) 函数文档明确语义（无参=生产/有参=测试）+ 参数命名对应（`diff_input` 而非 `state_file`）；(2) 红队测试外**必须**新增 1 个生产路径 smoke test（无参调用 + 真实 git 仓库）作为 Tier 1.5 场景；(3) Wave 2 qa-reviewer 应主动 grep 函数所有调用点，对照签名约定逐项验证。
**Evidence**: v3.17.0 第二轮 QA Wave 2 qa-reviewer 才抓到此 BLOCKER（line 428 错传 STATE_FILE）。第一轮 QA 红队 8/8 全过，因为 R5 用专用 invoke_detect 调用模式覆盖测试路径，没覆盖生产路径。修复仅需 1 行（删 "$STATE_FILE" 参数），但发现路径绕了完整一轮 QA + auto-fix。

### [2026-05-07] Shell 脚本要支持外部 source 测试，必须用 BASH_SOURCE[0]
<!-- tags: bash, shell, testing, source, BASH_SOURCE, autopilot, stop-hook -->
**Scenario**: stop-hook.sh 第 18 行 `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"` 在直接执行时 `$0` 是脚本路径，但被 source 时 `$0` 是调用者 shell（通常 `bash`），导致 `dirname "$0"` 取错路径，进而 `source "$SCRIPT_DIR/lib.sh"` 找不到文件，配合 `trap 'exit 0' ERR` 让整个 source 静默失败。红队测试的 invoke_compress 路径因此根本没成功调用 compress_qa_report 函数，但测试中早期断言（基于原文件内容）误 PASS 掩盖了真问题，只有最严格的断言（轮次 1 应被压缩）暴露失败。
**Lesson**: bash 脚本中所有用于「定位脚本自身目录」的逻辑必须用 `${BASH_SOURCE[0]}` 而非 `$0`。同时为了让函数可被外部独立测试，应在 main 逻辑前添加 source 守卫：`if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then return 0 2>/dev/null || exit 0; fi`。两者一起才能兼容直接执行 + 外部 source 两种用法。这也提示红队测试设计：早期/弱断言可能因「函数没真正运行 + 原文件刚好满足」而误 PASS，需要至少一个能 distinguish「函数有效执行」与「函数从未运行」的强断言。
**Evidence**: 本轮 implement 合流时红队 R1 fail「轮次 1 仍 4 行」，调试发现 source 静默失败导致函数从未被调用。修复 dirname + 加 source 守卫后 R1 全过。

### [2026-05-07] 顶层 `trap 'exit 0' ERR` 拦截函数内 `|| return 1` 短路链
<!-- tags: bash, trap-err, return, source-mode, testing, stop-hook, autopilot -->
**Scenario**: `stop-hook.sh` 顶层 `trap 'exit 0' ERR` 是为脚本主流程兜底（任何未预期错误放行）。新增 `has_pending_subagents` 函数用 `[ -n "$transcript" ] && [ -f "$transcript" ] || return 1` 短路链做错误降级，期望 `return 1` 表示"无 pending"。生产代码通过 `if has_pending_subagents "$x"; then ... fi` 调用，在 if 条件保护下 ERR 不触发——看起来一切正常。但红队测试通过 `bash -c 'source stop-hook.sh; has_pending_subagents ""'` 顶层裸调用，所有错误降级路径返回的 1 全部被 ERR trap 转成 exit 0，spawnSync 拿到 status=0 与函数 return 1 不一致，10 个测试有 7 个失败。
**Lesson**: bash ERR trap 对"函数返回非零"的触发条件取决于调用上下文：在 `if`/`while`/`until` 条件、`||` `&&` 链、`!` 否定中调用 → 不触发；裸调用（顶层 simple command）→ 触发。这意味着脚本的"生产正确性"和"测试可观察性"在 trap ERR 存在时是两套语义。修复模式：trap 仅在直接执行模式安装（`if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then trap 'exit 0' ERR; fi`），让 source 测试模式下函数 return 直接传递给 spawnSync。子 shell 包装也行不通——子 shell 仍继承父 shell 的 ERR trap。
**Evidence**: 实测 `trap "echo TRAP; exit 0" ERR; foo() { return 1; }; foo` 输出 `TRAP` 退出，但 `if foo; then ...; fi` 不触发。本次 QA 轮次 1 红队测试 7/10 失败，root cause 定位通过 5 行最小复现脚本在 `bash -c` 中直接验证。

### [2026-05-08] 字段反转默认值 + 复用现有 flag 优于新增 flag
<!-- tags: autopilot, design-decision, yagni, flag-design, default-inversion -->
**Scenario**: 用户提议「把行为 X 默认化」（例如 brainstorm 默认开启）时，简单实现是新增一个 opt-out flag。但很多时候现有的某个 flag 已经隐含了"opt out X"语义，复用比新增更优。
**Pattern**: 三步决策——(1) 列出 X 当前的所有使用模式（auto / explicit-on / explicit-off / 默认行为）；(2) 检查现有 escape hatch flag 是否能覆盖"opt-out X"语义，如果耦合可接受 → 直接扩展该 flag 语义；(3) 仅当中间档（非 X 但需要某些子项）真实存在高频需求时才新增 flag。
**Counter-example**: 本次 brainstorm 默认化任务初版方案 B 设计了 --quick 新增 flag，与现有 --fast 中间档差距其实很小（仅 sub-agent 审查严格性差异）；用户在审批时主动提出复用 --fast，方案演进为 B'，flag 数量从 +1 变为 0，决策树从 4→3 档进一步简化。
**Lesson**: flag 设计的 YAGNI 原则——"假想中间需求"不应作为新 flag 的设计依据。如果未来真出现高频需求再加 flag 也不晚，向前兼容性只在不删字段时存在风险。事实弃用的字段应保留兼容期（不立即删除）以避免历史持久化文件解析错误。

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
