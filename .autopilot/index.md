# Knowledge Index

## Decisions
- [2026-05-05] Lint / 健康检查能力优先 AI 语义判断而非正则脚本 | tags: autopilot, doctor, lint, ai-judgment, knowledge-engineering, design-principle | → decisions.md
- [2026-05-04] Per-worktree 会话隔离通过 sessions/<name>/ 子目录实现 | tags: autopilot, worktree, session-isolation, architecture | → decisions.md
- [2026-03-21] 知识工程采用三层 Progressive Disclosure 而非单层扩展 | tags: knowledge, architecture, progressive-disclosure | → decisions.md
- [2026-03-26] doctor Dim 1 测试金字塔分层评估优于文件计数 | tags: autopilot, doctor, testing, test-pyramid, scoring | → decisions.md
- [2026-03-27] SKILL.md Phase 分片优于状态文件索引 | tags: autopilot, skill, progressive-disclosure, token-optimization | → decisions.md
- [2026-04-03] merge 阶段 Agent 化优于 Skill 调用 | tags: autopilot, token-optimization, merge, agent, cost | → decisions.md
- [2026-04-10] 运行时文件统一迁移到 .autopilot/ 而非逐个豁免 | tags: autopilot, file-path, permission, claude-code, migration | → decisions.md

## Patterns
- [2026-05-04] Worktree 检测使用 .git 文件/目录区分法 | tags: autopilot, worktree, shell, detection | → patterns.md
- [2026-03-21] 多处引用同一数据（版本号 / 计数 / 路径）容易长期不同步 | tags: autopilot, doctor, consistency, version, dimension, lint | → patterns.md
- [2026-03-21] Skill 插件 Progressive Disclosure 重构模式 | tags: skill, progressive-disclosure, plugin, refactoring | → patterns.md
- [2026-03-22] 通用编排器不应替代领域专业 Skill | tags: autopilot, skill-delegation, implement, domain-workflow | → patterns.md
- [2026-03-22] 外部审查后的修改必须重新验证 | tags: autopilot, qa, post-review, validation, framer-motion | → patterns.md
- [2026-03-22] Tier 1.5 验证场景必须匹配核心变更层级 | tags: autopilot, qa, tier-1.5, ui-testing, smoke-test | → patterns.md
- [2026-03-21] HTML comment tags 比 YAML frontmatter 更适合 AI 知识标签 | tags: knowledge, tags, ai-parsing | → patterns.md
- [2026-03-24] SKILL.md 步骤标题需包含可搜索的"步骤"前缀 | tags: autopilot, skill, naming-convention, testing | → patterns.md
- [2026-03-24] 插件合并时红队路径假设容易出错 | tags: autopilot, red-team, testing, file-path, merge | → patterns.md
- [2026-03-25] 符号链接检测 ≠ worktree 检测，防御需多层 | tags: worktree, knowledge, symlink, fallback, defense-in-depth | → patterns.md
- [2026-03-26] Tier 1.5 场景部分执行等于未执行 | tags: autopilot, qa, tier-1.5, smoke-test, partial-execution | → patterns.md
- [2026-03-27] Skill 规范不应硬编码项目特定的文件路径 | tags: autopilot-commit, skill, version, hardcoding, claude-md | → patterns.md
- [2026-03-30] SKILL.md 文档文本中的标识符会干扰红队正则测试 | tags: autopilot, red-team, testing, indexOf, text-proximity, regex | → patterns.md
- [2026-04-12] "从缓存同步源码"操作会连带回退不相关的文件改动 | tags: autopilot, cache-sync, regression, stop-hook, source-of-truth | → patterns.md
- [2026-04-17] SKILL.md 决策树中后置章节会被 AI 跳过 | tags: autopilot, skill, decision-tree, priority, plan-mode, auto-approve | → patterns.md
- [2026-04-17] Early-exit 守卫阻断后续添加的合法代码路径 | tags: autopilot, stop-hook, guard, early-exit, ordering, knowledge-extracted | → patterns.md
