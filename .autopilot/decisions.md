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
**Background**: 成本分析显示 autopilot 单日消耗 100M tokens（$809.73），其中 merge 阶段的 Skill: autopilot-commit 调用单次消耗 3-5M tokens——因为在编排器主线程运行，继承了完整的设计文档、QA 报告、所有工具调用历史等父上下文。93.35% 的 tokens 是 cache_read。
**Choice**: merge 阶段改用 Agent 工具启动 commit-agent（model: sonnet），Agent 获得独立的新鲜上下文窗口，只包含显式传入的 git diff + 设计目标 + commit 规则。同时新增 stop-hook merge 分支注入 Agent 路径提醒。QA 报告压缩：历史轮次压缩为一行摘要，只保留最新完整报告。
**Alternatives rejected**: SKILL.md 路由器瘦身（572→85 行）——之前尝试过出过问题，不再重复。
**Trade-offs**: Agent 无法执行需要用户交互的操作（代码测验、ai-todo 同步），但主链路模式下这些步骤已跳过。独立 /autopilot commit 仍走 Skill 路径不受影响。预估综合日总成本降低 ~40-60%。
