# Patterns & Lessons

### [2026-05-04] Worktree 检测使用 .git 文件/目录区分法
<!-- tags: autopilot, worktree, shell, detection -->
**Scenario**: 需要在 shell 脚本中判断当前是否在 git worktree 中，以决定 active 指针存储路径
**Lesson**: `[[ -f "$PROJECT_ROOT/.git" ]]` → worktree（.git 是文件指向主仓库），`[[ -d "$PROJECT_ROOT/.git" ]]` → 主仓库（.git 是目录）。此方法比 `git worktree list | grep` 更快且无外部命令依赖
**Evidence**: `git worktree` 约定 .git 在 worktree 中为文件（内容 `gitdir: ../.git/worktrees/<name>`），在非 worktree 中为目录。lib.sh 中 get_worktree_name() 已验证

### [2026-03-21] README.md 版本号与 CLAUDE.md 长期不同步
**Scenario**: 插件版本在 CLAUDE.md 更新日志中迭代（v2.0.0 → v2.9.0），但 README.md 标题行版本号从未同步更新
**Lesson**: autopilot-commit 的版本升级步骤只检查 `.claude-plugin/plugin.json` 和 `package.json`，不会自动同步 README.md 中的版本号。多处记录版本号时，升级流程应覆盖所有版本出现位置，或在 autopilot-commit 中增加 README 版本同步检查
**Evidence**: README.md L54 `autopilot (v2.0.0)` 停留了 9 个版本未更新，CLAUDE.md 已记录到 v2.9.0。`grep "autopilot.*v2" README.md CLAUDE.md` 可复现不一致

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
**Evidence**: worktree-merge.acceptance.test.mjs 27 测试中 2 个因路径假设失败（25/27 通过），均为红队路径推测错误而非实现缺陷

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
**Evidence**: v3.5.2 红队 17 测试 2→3→1→0 失败修复 3 轮；v3.8.0 红队 36 测试因"步骤 3"引用导致 step2Match 仅捕获 294 字符（预期 ~800），修复改为"后续 Plan 审查"后通过

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
