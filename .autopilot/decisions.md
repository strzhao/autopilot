### [2026-05-06] Plugin hooks.json 不接收 `claude -w` 派发的 WorktreeCreate 事件
<!-- tags: claude-code, plugin, hooks, worktree, event-dispatch, sessionstart, fallback -->
**Background**: autopilot plugin 在 `plugins/autopilot/hooks/hooks.json` 注册了 WorktreeCreate hook 做 worktree 初始化（symlink + pnpm install + local-config.json）。用户跑 `claude code -w <name>` 创建 worktree 时，hook 完全没触发——worktree 是裸的，缺 node_modules / .env / local-config.json，`.autopilot` 是 git 检出实仓而非符号链接。
**Choice**: 在 plugin hooks.json **同时**注册 `SessionStart` hook 作为兜底。每次 session 启动检测 cwd 是否为未配置 worktree（`.git` 是文件 + `.autopilot` 不是 symlink 或缺 node_modules），是就调 `worktree.mjs repair`；主仓库 / 已配好 worktree silent exit 保证幂等。
**Alternatives rejected**: (1) 让用户在 `~/.claude/settings.json` 注册 WorktreeCreate hook —— 需硬编码 plugin 缓存路径，每次 plugin 升级需更新；(2) 修改 worktree.mjs 让脚本主动轮询 —— 与 hook 模型背离，复杂度高。
**Trade-offs**: SessionStart 每次 session 都触发 → 每次启动多几毫秒（已配好场景 silent exit）；裸 worktree 首次 session 卡几十秒装依赖 vs 用户拿到不可用 worktree，前者可接受。
**Evidence**: hook wrapper + log 对照实证（详见 commit 27289dc 的 HANDOFF 文档）—— plugin hooks.json 的 wrapper 0 字节日志，user-settings 的同 wrapper 收到完整 stdin payload。GitHub issue [#36205](https://github.com/anthropics/claude-code/issues/36205) 已报但只覆盖 settings.json 场景，未提到 plugin hooks.json gap。
**Lesson**: Plugin hook 事件派发**不是覆盖所有 events**——写 plugin hook 时不能假设 hooks.json 注册的 event 都会被触发，必须用实证验证（wrapper + log）。已知 SessionStart 在 plugin hooks.json **会**派发，可作为高频兜底事件。

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
