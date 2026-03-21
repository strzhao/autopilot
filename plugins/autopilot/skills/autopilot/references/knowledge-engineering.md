# Knowledge Engineering Reference

Detailed rules for the knowledge consumption and extraction steps in the autopilot pipeline.

## Knowledge Directory Structure (Three-Layer Progressive Disclosure)

```
.claude/knowledge/
├── index.md              # Layer 1: 索引层（轻量元数据，always loaded）
├── decisions.md          # Layer 2: 全局决策日志（保持兼容）
├── patterns.md           # Layer 2: 全局模式教训（保持兼容）
└── domains/              # Layer 2: 领域分区（按需加载）
    ├── frontend.md
    ├── testing.md
    └── ...
```

- **Layer 1 (Index)**: `index.md` 是路由层，每个条目只有标题 + 标签 + 位置，不含完整内容。Design 阶段 always loaded。
- **Layer 2 (Content)**: `decisions.md`、`patterns.md` 和 `domains/*.md` 是内容层，按需加载。
- **向后兼容**: 无 `index.md` 或无 `domains/` 均 fallback 到全量加载原有文件。

All content files use append-only Markdown, tracked in git. Each file stays ≤100 lines (全局文件); exceeding this triggers a domain migration suggestion.

## Index File Format (index.md)

`index.md` 作为路由层，记录所有知识条目的元数据。格式：

```markdown
# Knowledge Index

## Decisions
- [2026-03-20] worktree 使用 Node.js 重写而非 Shell | tags: worktree, shell, nodejs | → decisions.md
- [2026-03-18] autopilot 状态文件使用绝对路径 | tags: autopilot, worktree, path | → decisions.md

## Patterns
- [2026-03-20] worktree 内 git 路径解析陷阱 | tags: git, worktree, path | → patterns.md
- [2026-03-16] 单元测试全通过但真实场景失败 | tags: testing, smoke-test, qa | → patterns.md

## Domain Knowledge
- frontend: 3 entries | → domains/frontend.md
- testing: 2 entries | → domains/testing.md
```

**索引条目格式**: `- [YYYY-MM-DD] {title} | tags: tag1, tag2, tag3 | → {file_path}`

**规则**:
- 每次提取新知识时同步更新 index.md
- Domain Knowledge 部分只记录领域名称和条目数量
- 索引条目与内容条目保持一一对应

## Knowledge Formats

### Decision Log Entry (decisions.md / domains/*.md)

```markdown
### [YYYY-MM-DD] {one-line title}
<!-- tags: tag1, tag2, tag3 -->
**Background**: Why this decision was needed
**Choice**: What was selected
**Alternatives rejected**: Options considered but not chosen, and why
**Trade-offs**: Consequences of this choice
```

### Pattern / Lesson Entry (patterns.md / domains/*.md)

```markdown
### [YYYY-MM-DD] {one-line title}
<!-- tags: tag1, tag2, tag3 -->
**Scenario**: When this applies
**Lesson**: Specific practice or anti-pattern
**Evidence**: Concrete example from this autopilot run (command output, file:line, error message)
```

**Tags 规则**:
- 使用 `<!-- tags: ... -->` HTML comment 格式，不影响可读性
- 标签从设计文档和代码变更中自动提取（模块名、技术栈、问题类型）
- 每个条目 2-5 个标签，用逗号分隔

## Consumption Rules (Design Phase) — Two-Phase Retrieval

Before entering Plan Mode, scan `.claude/knowledge/` if it exists. 分两阶段执行，控制加载量：

### Phase 1: Index Scan (<=5s)

1. 检查 `.claude/knowledge/index.md` 是否存在
2. 如果存在：读取 `index.md`，用当前目标的关键词匹配 tags
3. 确定需要加载的文件列表（最多 3 个文件）
4. 进入 Phase 2

### Phase 2: Selective Load (<=10s)

1. 按 Phase 1 确定的文件列表，读取匹配的知识文件
2. 判断哪些条目与当前目标相关（同模块、同技术、类似问题）
3. 将相关条目作为内部上下文带入后续 Plan Mode
4. 在设计文档的 `## 相关历史知识` 中引用相关条目

### Fallback: No Index

如果 `index.md` 不存在（旧项目或首次使用）：
1. 回退到全量加载：读取 `decisions.md` 和 `patterns.md`（<=10s）
2. 判断相关性，携带相关条目进入 Plan Mode
3. 首次提取时自动创建 `index.md`

**Skip conditions**: Directory does not exist, files are empty, or no entries match the current goal. Never block on knowledge loading.

## Extraction Rules (Merge Phase)

After autopilot-commit completes, review the full autopilot run to extract knowledge worth preserving.

### Input Sources

- `## 设计文档` in state file (design decisions, trade-offs)
- `## QA 报告` in state file (failure patterns, fix history)
- `## 变更日志` in state file (process events)
- Auto-fix repair history (debugging insights)

### Record a Decision When

- The design document contains "option A vs option B" trade-off analysis
- A specific alternative was explicitly rejected with reasoning
- A non-obvious technical choice was made (uncommon pattern, counter-intuitive approach)

### Record a Pattern/Lesson When

- Auto-fix required >1 debugging round to resolve a failure
- QA exposed a project-specific pitfall or convention
- A reusable code pattern or anti-pattern was discovered
- The same type of failure appeared in multiple QA tiers

### Do NOT Record

- Routine bug fixes with no debugging insight
- Standard implementations with no design trade-off
- Obvious choices with no real alternatives
- Information already captured in CLAUDE.md

### Execution Steps

1. Analyze input sources for candidate entries
2. If worth recording:
   a. `mkdir -p .claude/knowledge/`
   b. Auto-generate tags from design document and code changes (module names, tech stack, problem type)
   c. Determine target file:
      - General decision → `decisions.md`
      - General pattern → `patterns.md`
      - Domain-specific entry → `domains/{domain}.md` (create if not exists)
   d. Append entries (with `<!-- tags: ... -->`) to the target file
   e. Update `index.md`: add index entry for each new knowledge entry (create `index.md` if not exists)
   f. Check line count for global files: if >100 lines, suggest migrating domain-specific entries to `domains/`
   g. `git add .claude/knowledge/ && git commit -m "docs(knowledge): extract {brief summary}"`
3. If nothing worth recording: append "知识提取：本次无新增" to the changelog and skip

**Time limit**: Complete knowledge extraction within 2 minutes. Prefer recording fewer high-quality entries over exhaustive documentation.

### Domain Partition Guide

当全局文件（`decisions.md` / `patterns.md`）超过 100 行时，建议按领域迁移：

1. 识别可聚合的条目（同一技术领域、同一模块的多个条目）
2. 创建 `domains/{domain}.md`，将相关条目迁移过去
3. 更新 `index.md` 中对应条目的 `→ {file_path}` 指向
4. 从全局文件中移除已迁移的条目

**常见领域划分**: frontend, backend, testing, infra, database, auth, performance

**注意**: 迁移操作需要用户确认，不要自动执行。提示用户并说明迁移理由。

## Size Management

### Global Files (decisions.md / patterns.md)

When a global knowledge file exceeds 100 lines:
1. Append `<!-- Warning: This file exceeds 100 lines. Consider migrating domain-specific entries to domains/. -->` at the end
2. Notify the user: suggest reviewing entries and migrating domain-specific ones to `domains/{domain}.md`
3. Do not auto-migrate — knowledge curation requires human judgment

### Domain Files (domains/*.md)

Each domain file stays <=150 lines. Exceeding this triggers:
1. Append `<!-- Warning: This file exceeds 150 lines. Review and prune older entries. -->` at the end
2. Notify the user: suggest pruning stale entries or further splitting the domain
