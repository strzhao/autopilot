# Knowledge Engineering Reference

Detailed rules for the knowledge consumption (design phase) and extraction (merge phase) steps in the autopilot pipeline.

## Knowledge Directory Structure (Three-Layer Progressive Disclosure)

```
.autopilot/
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

## Patterns
- [2026-03-20] worktree 内 git 路径解析陷阱 | tags: git, worktree, path | → patterns.md

## Domain Knowledge
- frontend: 3 entries | → domains/frontend.md
```

**索引条目格式**: `- [YYYY-MM-DD] {title} | tags: tag1, tag2, tag3 | → {file_path}`

每次提取新知识时同步更新 index.md；索引条目与内容条目保持一一对应。

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

Tags 使用 `<!-- tags: ... -->` HTML comment 格式；每个条目 2-5 个标签，逗号分隔。

## Anti-Overfitting Principles

知识库的最大敌人是"过拟合"——把一次特定运行的具体细节（版本号、路径、计数）混入应该是通用原则的字段。这导致知识在 6 个月后或在另一个项目中完全失效。

### Principle-Evidence 分离

每个字段有其允许的抽象层级：

| 字段 | 允许 | 禁止 |
|------|------|------|
| `Lesson` / `Choice` | 可迁移的 principle（无具体值） | 版本号、文件路径、行号、计数、日期 |
| `Evidence` | 具体证据（命令输出、版本号、文件名、错误信息） | 抽象原则（已在 Lesson 表达） |
| `Background` / `Scenario` | 触发条件描述 | 运行时临时状态 |

**核心判断标准**：删掉 Evidence 字段后，Lesson/Choice 字段必须仍然独立成立、语义完整。

### 写入后 5 问自检清单

写完 `Lesson` / `Choice` 字段后，逐项回答：

1. **这条 lesson 在 6 个月后还成立吗？**（检查是否依赖当时的版本/环境）
2. **这条 lesson 在另一个项目还有效吗？**（检查是否过于项目特定）
3. **把版本号换成"某个版本"后 lesson 还成立吗？**（检查是否包含版本号）
4. **删掉 Evidence 后 Lesson 还独立成立吗？**（检查是否需要 Evidence 才能理解）
5. **Lesson 行有具体数值/版本号/路径/计数吗？**（有则移到 Evidence）

如任意一问回答为"否"，需要修改 Lesson/Choice 字段，将具体内容下移到 Evidence。

### 反例 vs 正例

**❌ 反例**（过拟合 — Lesson 含具体值）：
```markdown
### [2026-03-27] Skill 规范中 40px 间距不兼容 Claude Code v2.1.3
<!-- tags: skill, spacing, claude-code -->
**Scenario**: 在 Claude Code v2.1.3 中使用 skill 文档时
**Lesson**: 间距需要精确设置为 40px，否则在 v2.1.3 中会崩溃（见 line 347 报错）
**Evidence**: line 347: "spacing must be exactly 40px", claude-code@2.1.3 npm error log
```

**✅ 正例**（抽象 — Lesson 是可迁移 principle，Evidence 保留具体值）：
```markdown
### [2026-03-27] Skill 文档中禁止硬编码工具版本相关的数值
<!-- tags: skill, compatibility, hardcoded-values -->
**Scenario**: 编写 Skill 规范文档时涉及布局参数
**Lesson**: 避免在 Skill 规范中硬编码与工具版本耦合的具体数值；改为描述约束条件和语义意图
**Evidence**: Claude Code v2.1.3 因 Skill.md 中的 "spacing: 40px" 硬编码报错（line 347），升级到 v2.2.0 后默认值变化导致原值失效
```

## Integration over Append

写新条目前，先搜索已有条目是否有相似主题。如果有，**优先合并**（升级抽象层级）而非新建——这避免知识库膨胀和碎片化，让相关教训集中在一条 entry 中形成更强的信号。

### 决策规则

| 情形 | 行动 |
|------|------|
| index.md 中 tags 重叠 ≥2 且语义相似 | **合并**：修订 Lesson（抽象层级升级）+ 在 Evidence 字段并列多个案例 |
| index.md 中 tags 重叠 ≥2 但 principle 明显不同 | **新建**：两条 entry 分别保留 |
| 完全没有 tags 重叠 | **新建** |
| Lesson 已完全被已有条目覆盖 | **跳过**（在 index.md 条目旁标注 "evidence updated [date]" 即可） |

### 合并示例

**合并前**（两条分散条目）：
```
- [2026-03-15] worktree 中 git 路径解析失败 | tags: git, worktree, path | → patterns.md
- [2026-03-27] worktree 符号链接 .autopilot 解析报错 | tags: worktree, symlink, path | → patterns.md
```

**合并后**（一条聚合条目，Evidence 并列多案例）：
```markdown
### [2026-03-27] Git Worktree 中路径解析的统一处理策略
<!-- tags: git, worktree, path, symlink -->
**Scenario**: 在 git worktree 环境中访问共享路径（知识库、配置文件）时
**Lesson**: 在 worktree 中不能假设相对路径和符号链接与主仓库一致；应使用 `git rev-parse --git-common-dir` 解析主仓库路径，并检测 `.git` 是文件（worktree）还是目录（主仓库）
**Evidence**: (案例 1: 2026-03-15) `git rev-parse --show-toplevel` 在 worktree 中返回 worktree 根而非主仓库 | (案例 2: 2026-03-27) `.autopilot` 符号链接在 `worktree-repair` 未运行时不存在，`realpath` 报错
```

### 步骤 0：搜索已有条目（Execution Steps 前置步骤）

在执行提取写入前，先：

1. 从本次工作主题提取 2-3 个关键 tag（如 `worktree`, `testing`, `api-routes`）
2. 读取 `index.md`，找 tags 重叠 ≥2 的候选条目（最多 top 3）
3. 决策：
   - 相似主题 → **合并**：修订 Lesson + 在 Evidence 字段扩充新案例
   - 不同 principle → **新建**：继续正常写入流程
   - 完全覆盖 → **跳过**：不写入，仅在 index.md 标注证据日期

## Consumption Rules (Design Phase) — Two-Phase Retrieval

Before entering Plan Mode, scan `.autopilot/` if it exists. 分两阶段执行，控制加载量：

**Phase 1 — Index Scan (<=5s)**: 读取 `index.md`，用当前目标关键词匹配 tags，确定需加载的文件列表（最多 3 个）。

**Phase 2 — Selective Load (<=10s)**: 按 Phase 1 文件列表读取内容，判断相关性，携带相关条目进入 Plan Mode，并在设计文档的 `## 相关历史知识` 中引用。

**Fallback**: 无 `index.md` 时直接全量加载 `decisions.md` 和 `patterns.md`（<=10s）。

**Skip conditions**: 目录不存在、文件为空、或无条目与当前目标匹配时跳过。Never block on knowledge loading.

## Extraction Rules (Merge Phase)

After autopilot-commit completes, review the full autopilot run to extract knowledge worth preserving.

### Record a Decision When
- 设计文档包含 option A vs option B 的权衡分析
- 明确拒绝了某个备选方案并有理由
- 做出了非显而易见的技术选择

### Record a Pattern/Lesson When
- auto-fix 需要 >1 轮调试才解决
- QA 暴露了项目特有的陷阱或约定
- 发现了可复用的代码模式或反模式
- 同类型失败出现在多个 QA Tier

### Do NOT Record
- 无调试洞见的常规 bug 修复；标准实现无设计权衡；CLAUDE.md 中已有的信息

### Execution Steps

0. **搜索已有条目**（Integration over Append）：按「步骤 0：搜索已有条目」执行——提取 2-3 个 tag → 检索 index.md → 决策合并/新建/跳过
1. 分析状态文件（设计文档、QA 报告、变更日志、auto-fix 历程）中的候选条目
2. 有值得记录的条目：
   a. `mkdir -p .autopilot/`
   b. 从设计文档和代码变更中自动生成 tags
   c. 确定目标文件：通用决策 → `decisions.md`；通用模式 → `patterns.md`；领域特定 → `domains/{domain}.md`
   d. 追加条目（含 `<!-- tags: ... -->`）到目标文件，**写入后执行 Anti-Overfitting 5 问自检**（Lesson/Choice 字段无具体值）
   e. 更新 `index.md`（不存在则创建）
   f. 全局文件 >100 行时建议用户迁移领域条目到 `domains/`
   g. 确定知识库 git 提交上下文（见下方 Worktree-Aware Extraction）
3. 无值得记录的内容 → 变更日志追加"知识提取：本次无新增"后跳过

**Time limit**: 2 分钟内完成。宁可少写高质量条目，不要穷举。

## Worktree-Aware Extraction

When running in a git worktree (v3.18+ 选择性 symlink 模式)，`.autopilot/` 是真实目录，里面的共享知识项（`decisions.md`、`patterns.md`、`index.md`、`domains/` 等）以 symlink 指向主仓库 `.autopilot/<item>`。检测知识应该提交到哪个仓库时，**检查共享项是否为 symlink**，而不是检查 `.autopilot` 自身。

#### Step 1: 选择性 symlink 模式（happy path，v3.18+）
`test -L .autopilot/decisions.md` → 共享项是 symlink

- 解析主仓库并在那里提交：
  ```bash
  KNOWLEDGE_REAL=$(realpath .autopilot/decisions.md)
  MAIN_REPO=$(cd "$(dirname "$KNOWLEDGE_REAL")/.." && git rev-parse --show-toplevel)
  git -C "$MAIN_REPO" add .autopilot/
  git -C "$MAIN_REPO" commit -m "docs(knowledge): extract {brief summary}"
  ```

#### Step 1b: 旧版全量 symlink（v3.17 及更早）
`test -L .autopilot` → `.autopilot` 整体是 symlink

- 同步骤 1，但解析路径换成 `.autopilot` 自身：
  ```bash
  KNOWLEDGE_REAL=$(realpath .autopilot)
  MAIN_REPO=$(cd "$KNOWLEDGE_REAL" && git rev-parse --show-toplevel)
  git -C "$MAIN_REPO" add .autopilot/ && git -C "$MAIN_REPO" commit -m "docs(knowledge): ..."
  ```
- （可选）建议用户跑 `worktree-repair` skill 升级到选择性 symlink。

#### Step 2: 在 worktree 中但 symlink 全部缺失（fallback + self-heal）
`test -f .git` → 是 worktree（.git 是文件而非目录），但 `.autopilot/decisions.md` 也不是 symlink

1. 解析主仓库根：`COMMON_DIR=$(git rev-parse --git-common-dir); MAIN_REPO=$(cd "$COMMON_DIR/.." && pwd)`
2. 复制知识到主仓库并提交：`mkdir -p "$MAIN_REPO/.autopilot/"; cp -r .autopilot/decisions.md .autopilot/patterns.md .autopilot/index.md .autopilot/domains "$MAIN_REPO/.autopilot/" 2>/dev/null; git -C "$MAIN_REPO" add .autopilot/; git -C "$MAIN_REPO" commit -m "docs(knowledge): ..."`
3. 自愈：建议跑 `worktree-repair` skill 重建选择性 symlink

#### Step 3: Normal repo (no worktree)
`test -d .git` → 正常 git 仓库，使用标准操作：`git add .autopilot/ && git commit -m "docs(knowledge): ..."`

## Domain Partition Guide

当全局文件超过 100 行时，识别可聚合的同领域条目，创建 `domains/{domain}.md`，迁移后更新 `index.md` 中的路径引用，并从全局文件删除已迁移条目。**迁移操作需要用户确认。**

**常见领域划分**: frontend, backend, testing, infra, database, auth, performance

## Size Management

- 全局文件（decisions.md / patterns.md）超 100 行 → 追加警告注释并通知用户建议迁移
- 领域文件（domains/*.md）超 150 行 → 追加警告注释并通知用户建议拆分或裁剪旧条目
- 不要自动迁移——知识整理需要人工判断

运行 `/autopilot doctor` 可获得知识库健康度评估（Dim 12），包括过拟合密度扫描、重复主题检测、文件大小健康度分析和索引一致性检查。
