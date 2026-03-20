# Knowledge Engineering Reference

Detailed rules for the knowledge consumption and extraction steps in the autopilot pipeline.

## Knowledge Directory Structure

```
.claude/knowledge/
├── decisions.md          # Decision log: WHY choices were made
└── patterns.md           # Patterns & lessons: reusable insights from QA/debug
```

Both files use append-only Markdown, tracked in git. Each file stays ≤150 lines; exceeding this triggers a user review prompt.

## Knowledge Formats

### Decision Log Entry (decisions.md)

```markdown
### [YYYY-MM-DD] {one-line title}
**Background**: Why this decision was needed
**Choice**: What was selected
**Alternatives rejected**: Options considered but not chosen, and why
**Trade-offs**: Consequences of this choice
```

### Pattern / Lesson Entry (patterns.md)

```markdown
### [YYYY-MM-DD] {one-line title}
**Scenario**: When this applies
**Lesson**: Specific practice or anti-pattern
**Evidence**: Concrete example from this autopilot run (command output, file:line, error message)
```

## Consumption Rules (Design Phase)

Before entering Plan Mode, scan `.claude/knowledge/` if it exists:

1. Read `decisions.md` and `patterns.md` (≤10 seconds total)
2. Judge relevance by matching entry topics against the current goal — same module, same technology, or similar problem type
3. Carry relevant entries as internal context into Plan Mode
4. Include relevant entries in the optional `## 相关历史知识` section of the design document

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
   - `mkdir -p .claude/knowledge/`
   - Append entries to the appropriate file (decisions.md / patterns.md)
   - Check line count: if >150 lines, append a warning comment and notify user to review and prune
   - `git add .claude/knowledge/ && git commit -m "docs(knowledge): extract {brief summary}"`
3. If nothing worth recording: append "知识提取：本次无新增" to the changelog and skip

**Time limit**: Complete knowledge extraction within 2 minutes. Prefer recording fewer high-quality entries over exhaustive documentation.

## Size Management

When a knowledge file exceeds 150 lines:
1. Append `<!-- ⚠️ This file exceeds 150 lines. Review and prune older entries to maintain compliance quality. -->` at the end
2. Notify the user: suggest reviewing and archiving stale entries
3. Do not auto-prune — knowledge curation requires human judgment
