<!-- domain: worktree 检测 / symlink / git porcelain / session 隔离 / 文件管理 -->
# Worktree & Git

### [2026-05-06] Plugin hooks.json 不接收 `claude -w` 派发的 WorktreeCreate 事件
<!-- tags: claude-code, plugin, hooks, worktree, event-dispatch, sessionstart, fallback -->
**Background**: autopilot plugin 在 `plugins/autopilot/hooks/hooks.json` 注册了 WorktreeCreate hook 做 worktree 初始化（symlink + pnpm install + local-config.json）。用户跑 `claude code -w <name>` 创建 worktree 时，hook 完全没触发——worktree 是裸的，缺 node_modules / .env / local-config.json，`.autopilot` 是 git 检出实仓而非符号链接。
**Choice**: 在 plugin hooks.json **同时**注册 `SessionStart` hook 作为兜底。每次 session 启动检测 cwd 是否为未配置 worktree（`.git` 是文件 + `.autopilot` 不是 symlink 或缺 node_modules），是就调 `worktree.mjs repair`；主仓库 / 已配好 worktree silent exit 保证幂等。
**Alternatives rejected**: (1) 让用户在 `~/.claude/settings.json` 注册 WorktreeCreate hook —— 需硬编码 plugin 缓存路径，每次 plugin 升级需更新；(2) 修改 worktree.mjs 让脚本主动轮询 —— 与 hook 模型背离，复杂度高。
**Trade-offs**: SessionStart 每次 session 都触发 → 每次启动多几毫秒（已配好场景 silent exit）；裸 worktree 首次 session 卡几十秒装依赖 vs 用户拿到不可用 worktree，前者可接受。
**Evidence**: hook wrapper + log 对照实证（详见 commit 27289dc 的 HANDOFF 文档）—— plugin hooks.json 的 wrapper 0 字节日志，user-settings 的同 wrapper 收到完整 stdin payload。GitHub issue [#36205](https://github.com/anthropics/claude-code/issues/36205) 已报但只覆盖 settings.json 场景，未提到 plugin hooks.json gap。
**Lesson**: Plugin hook 事件派发**不是覆盖所有 events**——写 plugin hook 时不能假设 hooks.json 注册的 event 都会被触发，必须用实证验证（wrapper + log）。已知 SessionStart 在 plugin hooks.json **会**派发，可作为高频兜底事件。

### [2026-05-04] Per-worktree 会话隔离通过 sessions/<name>/ 子目录实现
<!-- tags: autopilot, worktree, session-isolation, architecture -->
**Background**: worktree.mjs 将整个 `.autopilot/` 符号链接共享到所有 worktree，导致 active 指针和 requirements 全局共享，旧任务状态干扰新 worktree。
**Choice**: active 指针和 requirements 目录改 per-worktree 隔离，知识文件（decisions/patterns/index）保持共享。非 worktree 沿用 `.autopilot/active`，worktree 使用 `.autopilot/sessions/<name>/active`。worktree.mjs remove() 自动清理 session 目录。
**Alternatives rejected**: (1) active 文件编码 worktree 名称 — 需额外解析，增加复杂度；(2) 完全隔离 `.autopilot/` — 知识文件无法共享

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

### [2026-05-10] git worktree list --porcelain 第一项稳定为主仓库，按位置跳过优于按路径比对
<!-- tags: git, worktree, porcelain, position-stable, run-anywhere, doctor, autopilot, path-resolution -->
**Scenario**: 在仓库内任意位置（主仓库 / linked worktree）运行的脚本，需要遍历"非主仓库"的 worktree。
**Lesson**: `git worktree list --porcelain` 输出顺序是 git 的稳定契约——第 1 项总是主仓库（main worktree），无论 cwd 在哪。优于"算出 main 路径再按字符串比对"——后者依赖 `git rev-parse --show-toplevel`，在 worktree 内返回 worktree 自身路径而非主仓库根，必须配 `--git-common-dir + dirname` 才正确（参 worktree.mjs:46 `repoRoot()`）。按位置跳过既避开这个解析陷阱，又使代码"运行路径无关"——这是写"在任何子目录都要工作"的脚本时的稳定模式。
**Evidence**: doctor SKILL Dim 8 worktree 健康抽查初版 `MAIN_ROOT=$(git rev-parse --show-toplevel); [ "$wt" = "$MAIN_ROOT" ] && continue`，cwd 在 worktree 内时 MAIN_ROOT 错指当前 worktree → 主仓库被误当 worktree 检查（场景 8 失败）。改 `awk '/^worktree / {n++; if (n==1) next; print $2}'` 后场景 8 通过，同时删掉 MAIN_ROOT 变量。这条 pattern 是 [2026-03-27] "Worktree 路径解析统一处理策略"的精简补丁——不是所有场景都需要 `--git-common-dir`，能用 porcelain 顺序就别引入 path 解析。

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

### [2026-03-25] 符号链接检测 ≠ worktree 检测，防御需多层
<!-- tags: worktree, knowledge, symlink, fallback, defense-in-depth -->
**Scenario**: autopilot merge 阶段知识提取检查 `.autopilot` 是否为符号链接来判断是否在 worktree 中。little-bee 项目的 worktree 中符号链接缺失（可能是旧 worktree 或 hook 失败），导致知识被提交到 worktree 分支而非主仓库
**Lesson**: 单一检测机制不可靠时必须设计 fallback 链。符号链接是"机制"不是"状态"——机制可能失败但状态（是否在 worktree）不变。正确做法：(1) 检查符号链接 → (2) 检查 `.git` 是否为文件（worktree 的可靠标志） → (3) 回退到正常路径。同时在预防层确保符号链接尽可能存在（repair() 预创建）
**Evidence**: little-bee eager-jingling-kay worktree 日志第 1508-1519 行：AI 检测到非符号链接后直接走 fallback 本地提交，知识丢失在 worktree 分支

