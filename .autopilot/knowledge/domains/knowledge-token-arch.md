<!-- domain: progressive disclosure / token 优化 / sub-agent / 架构 / doctor -->
# Knowledge & Token Architecture

### [2026-05-05] Lint / 健康检查能力优先 AI 语义判断而非正则脚本
<!-- tags: autopilot, doctor, lint, ai-judgment, knowledge-engineering, design-principle -->
**Background**: 知识库 Lint 设计需要识别"过拟合条目"（如硬编码 UI 高度的具体数值而非"动态读取 UI 高度"原则）。最初方案是写独立脚本用正则匹配版本号 / 行号 / 文件名列表等模式做检测。
**Choice**: Lint 能力通过 AI Agent 阅读知识库文件做语义评估，集成到 autopilot-doctor 作为 Wave 2 串行 AI 判断维度，不写脚本。
**Alternatives rejected**: (1) 独立 Lint 脚本（Node.js / Shell）—— 正则无法识别"硬编码具体数值是过拟合"vs"抽象原则是 principle"的语义差异，会大量误报或漏报；(2) 独立 Skill 入口（如 `/autopilot:knowledge-lint`）—— 增加用户认知面，集成既有维度入口更聚合。
**Trade-offs**: AI 判断比脚本慢且消耗更多 token，但能识别脚本无法捕获的语义模式。原则推广：所有"评分 / 审查 / 质量判断 / 模糊匹配"类功能默认选 AI Agent，只有"格式校验 / 性能敏感 / 输出可被 AI 后处理的纯数据收集"才选代码。

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

### [2026-04-03] merge 阶段 Agent 化优于 Skill 调用
<!-- tags: autopilot, token-optimization, merge, agent, cost -->

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

### [2026-05-14] per-user 偏好持久化采用 `~/.autopilot/` 形成与项目级 `.autopilot/` 的命名对称
<!-- tags: autopilot, prefs, persistence, user-level, project-level, naming-convention, dotfile, single-source-of-truth -->
**Background**: plan review 浏览器审批引入「提交后自动关闭」开关需要跨多次 autopilot 任务、跨项目、跨 worktree 持久化偏好。candidate 位置三选一：用户级 dotfile / Claude plugin 数据目录 / XDG 规范目录。同时 visual-companion server 每次启动 PORT 随机，浏览器端 localStorage 在 `127.0.0.1:RANDOM_PORT` 之间不能跨源复用，废客户端持久化方案。
**Choice**: `~/.autopilot/prefs.json` —— 与项目级 `.autopilot/` 知识库形成「per-user 全局偏好 + per-repo 本地知识」的命名对称；单一写入口（Node 端 server 进程通过 `prefs.cjs.setPref` 落盘），损坏 JSON / 文件缺失 / 字段缺失三层 fallback 到默认值，永不让审批 UI 因偏好文件损坏白屏。
**Alternatives rejected**: (1) `~/.claude/autopilot/prefs.json` — 与 `~/.claude/plugins/cache/` 共一级，cache 同步流程容易把"只读副本"语义覆盖到"可写偏好"，制造同步事故；(2) XDG `~/.config/autopilot/` — macOS 用户对 `~/.config` 习惯弱，对 dotfile 清理工具反而更不兼容；(3) localStorage 浏览器端 — 随机端口让同源策略失效，跨会话不可复用。
**Trade-offs**: dotfile 在 cloud sync 工具（Dropbox/iCloud）下默认不会同步 `~/.autopilot/`，跨机器需手动 symlink——可接受，偏好本身极简（单 boolean），用户首次访问设一次即可。

### [2026-03-21] 多处引用同一数据（版本号 / 计数 / 路径）容易长期不同步
<!-- tags: autopilot, doctor, consistency, version, dimension, lint -->
**Scenario**: 文档中多处引用同一数据（版本号、维度计数、模块数量、特定路径等）时，单一升级流程或人工记忆无法保证全部位置同步更新
**Lesson**: 同一数据散布在多处时，应优先选择以下机制之一：(1) 集中化为单一来源（如 CLAUDE.md 项目元数据中央仓库）+ 派生引用 (2) 自动化 lint / 健康检查工具发现不一致 (3) 升级脚本主动搜索全部出现位置而非硬编码文件清单。仅靠"提醒人工同步"会反复失败
**Evidence**:
- 案例 1: README.md autopilot 标题版本号停留了多个版本未与 CLAUDE.md 更新日志同步，autopilot-commit 升级流程仅覆盖 plugin.json/package.json
- 案例 2: v3.14.0 升级 doctor Dim 11→12，但 CLAUDE.md L58 "11 维度评分" 和 L79 "11 维度加权评分（11 项枚举）" 同步遗漏，由 Tier 2b code-quality-reviewer Agent 在 QA 阶段发现并 auto-fix 修复——此即 Dim 12 知识库健康度维度本身需要解决的问题

### [2026-03-22] 通用编排器不应替代领域专业 Skill
<!-- tags: autopilot, skill-delegation, implement, domain-workflow -->
**Scenario**: 用户用 `/autopilot` 批量添加 8 个汉字到 little-bee 项目，目标描述中明确提到"使用 add-hanzi skill"，但蓝队 Agent 从零实现而非调用已有 Skill
**Lesson**: 领域 Skill 封装了经过验证的工作流（步骤顺序、工具链约定、资产管理），蓝队 Agent 从零实现会导致：(1) 全量覆盖型脚本误删数据（audio-index 丢失 147 字配置） (2) 工具链约定不了解（上传到错误 Blob store、MiniMax 文件路径混乱） (3) 大量 API 调用浪费（音频生成 3 轮 144 次调用，96 次浪费）。解决：implement 阶段新增路由判断，设计文档声明委托 Skill 时走委托路径
**Evidence**: little-bee conversation-2026-03-22-111711.txt，5028 行对话记录，autopilot v2.12.0 新增 Skill 委托机制

### [2026-03-21] HTML comment tags 比 YAML frontmatter 更适合 AI 知识标签
<!-- tags: knowledge, tags, ai-parsing -->
**Scenario**: 需要为知识条目添加可检索的标签元数据
**Lesson**: 使用 `<!-- tags: tag1, tag2 -->` HTML comment 格式优于 YAML frontmatter。原因：(1) 不影响 Markdown 渲染的可读性 (2) AI 解析简单（正则即可） (3) 与 Markdown 标题行紧邻，上下文关联清晰 (4) Git diff 友好
**Evidence**: 红队验收测试 41/41 通过，AI 能正确识别和匹配 HTML comment 中的 tags（knowledge-upgrade.acceptance.test.mjs:85-91）

### [2026-05-07] Cache 命中率高不等于 token 成本低
<!-- tags: token-analysis, prompt-cache, methodology, autopilot -->
**Scenario**: autopilot 优化分析时直觉认为「session 总 token = SKILL.md 加载 × N 轮 + 工具调用」，倾向于优化 SKILL.md 大小。但 5 天 Top 5 session 数据显示：cache_read 占 95-99%（最高 session 116.8M token / 1119 turns，cache_create 几乎为 0）。这意味着 prompt cache 已经把 SKILL.md / references 重复加载这部分压平了。真实成本驱动是：(1) sub-agent cold start（每次 ~500K，无法被 parent cache 共享）；(2) Bash 大输出 / 文件全量 Read 进入累积上下文（每个后续 turn 都要 cache_read 这些累积内容）；(3) 状态文件膨胀（同上）。
**Lesson**: 用「绝对 token 数据 per-session」而非「cache 命中率 %」作为优化决策依据。命中率高反而说明该路径的 token 已经被有效平摊，对该路径继续做小优化 ROI 极低；应转向 cache 无法覆盖的成本源。具体方法：`jq` 解析 ~/.claude/projects/*/jsonl 累加单个 session 的 input/output/cache_read/cache_create，按总量降序找 top sessions，看 cache_create 异常值或大 Bash 输出，定位真实漏点。
**Evidence**: 本轮（2026-05-07）三项优化均针对 cache 无法覆盖的成本：合并 qa reviewer（减 cold start）、stop-hook 自动压缩 QA 报告（减累积 Read 成本）。SKILL.md 行数从 699 → 675 仅减 24 行的"防合理化指南抽离"反而是收益最低的一项——前两轮已经把 SKILL.md 优化到 cache 命中率 95%+。

