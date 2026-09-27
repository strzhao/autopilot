# Knowledge Engineering Reference

Detailed rules for the knowledge inbox (write side, any session), consumption (design phase), and collection (merge phase, primary checkout only) in the autopilot pipeline.

## Knowledge Directory Structure (Inbox + Three-Layer Progressive Disclosure)

```
.autopilot/knowledge/
├── inbox/                # Layer 0: 收件箱（写侧唯一目标，一任务一独立文件，正式知识层）
├── index.md              # Layer 1: 收编基索引（仅由收编动作重建，always loaded）
├── decisions.md          # Layer 2: 全局决策日志（聚合层，仅收编侧可写）
├── patterns.md           # Layer 2: 全局模式教训（聚合层，仅收编侧可写）
└── domains/              # Layer 2: 领域分区（聚合层，仅收编侧可写，按需加载）
    ├── frontend.md
    ├── testing.md
    └── ...
```

- **Layer 0 (Inbox)**: `inbox/` 是任意会话 merge 阶段的唯一写目标——每条知识一个独立新文件，写入即正式知识（非待处理队列）。并行会话各写各文件，git merge 零冲突。
- **Layer 1 (Index)**: `index.md` 是**收编基索引**——仅由收编动作重建，不含 inbox 条目（inbox 由目录列举发现）。每个条目只有标题 + 标签 + 位置，不含完整内容。Design 阶段 always loaded。
- **Layer 2 (Content)**: `decisions.md`、`patterns.md` 和 `domains/*.md` 是聚合内容层，仅收编侧可写，按需加载。
- **向后兼容**: 无 `index.md` 或无 `domains/` 均 fallback 到全量加载原有文件；无 `inbox/` 目录时写侧 `mkdir -p` 后写入。

All content files use append-only Markdown, tracked in git. Each file stays ≤100 lines (全局文件); exceeding this triggers a domain migration suggestion.

## Inbox Protocol (Write Side — Any Session)

任意会话（主检出或 worktree）merge 阶段提取知识时，**只写 `inbox/` 独立新文件，禁止直接写聚合层四类文件**（`index.md` / `decisions.md` / `patterns.md` / `domains/*.md`）：

1. `mkdir -p .autopilot/knowledge/inbox/`（目录不存在时创建，solve, don't defer）
2. 文件名 `YYYY-MM-DD-<slug>.md`：slug ∈ `[a-z0-9-]` 且 ≤40 字符（取自本次主题关键词）
3. 同名文件已存在 → 文件名后缀 `-2` 递增（如 `<slug>-2.md`），原文件保留
4. 条目格式沿用 Knowledge Formats（H3 `[YYYY-MM-DD] 标题` + `<!-- tags: ... -->` + 字段模板，tags 2-5 个）
5. **写入后**执行 Anti-Overfitting 5 问自检 + 时效锚点标注（写侧义务不变）
6. **写侧不做 Integration**——语义合并整体移到收编侧（Collection Protocol）。写 = 新文件，冲突按构造消失；写侧**不更新 `index.md`**、不写聚合层

**worktree 说明**：`inbox/` 是真实 git 跟踪目录（不在 SHARED_AUTOPILOT_ITEMS symlink 列表），新文件随分支 merge 零冲突——这是收件箱机制的存在理由。

## Index File Format (index.md — 收编基)

`index.md` 作为收编基索引，仅收录已收编进聚合层的条目元数据。格式：

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

索引**仅由收编动作重建**（见 Collection Protocol），重建后 ≤100 行，索引条目与聚合层内容条目保持一一对应。**inbox 条目不进索引**——消费端通过 `ls inbox/` 列举发现（两跳，见 Consumption Rules）。

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

**条目唯一标识 = H3 标题行 `[YYYY-MM-DD] {title}`，禁止手工维护全局序号**（如 ⑯、#16）——并行会话各自收编时全局序号必然撞号重复，序号也无消费价值；需要排序以日期为准。

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

## Integration over Append (Collection Side)

收编侧把 inbox 条目并入聚合层时，先搜索已有条目是否有相似主题。如果有，**优先合并**（升级抽象层级）而非新建——这避免知识库膨胀和碎片化，让相关教训集中在一条 entry 中形成更强的信号。

### 决策规则

| 情形 | 行动 |
|------|------|
| index.md 中 tags 重叠 ≥2 且语义相似 | **合并**：修订 Lesson（抽象层级升级）+ 在 Evidence 字段并列多个案例 |
| index.md 中 tags 重叠 ≥2 但 principle 明显不同 | **新建**：两条 entry 分别保留 |
| 完全没有 tags 重叠 | **新建** |
| Lesson 已完全被已有条目覆盖 | **跳过**（在 index.md 条目旁标注 "evidence updated [date]" 即可） |

### 合并示例

两条分散条目（git 路径解析失败 / symlink 解析报错）→ 合并为一条聚合条目：Lesson 统一为「worktree 中不假设相对路径与 symlink 和主仓库一致，用 `git rev-parse --git-common-dir` 解析」，Evidence 字段并列 `(案例 1: 日期)` `(案例 2: 日期)` 多案例。

### 步骤 0：搜索已有条目（收编前置步骤）

收编写入聚合层前，先：

1. 从积压条目主题提取 2-3 个关键 tag（如 `worktree`, `testing`, `api-routes`）
2. 读取 `index.md`，找 tags 重叠 ≥2 的候选条目（最多 top 3）
3. 决策：
   - 相似主题 → **合并**：修订 Lesson + 在 Evidence 字段扩充新案例
   - 不同 principle → **新建**：追加为新条目
   - 完全覆盖 → **跳过**：不写入，仅在 index.md 标注证据日期

## Consumption Rules (Design Phase) — Two-Hop Retrieval

Before entering Plan Mode, scan `.autopilot/` if it exists. 消费分**两跳**执行，控制加载量：

**Phase 1 — Index Scan (<=5s)**: 读取 `index.md`（收编基），用当前目标关键词匹配 tags，确定需加载的文件列表（最多 3 个）。

**Phase 2 — Inbox Scan (<=5s)**: `ls .autopilot/knowledge/inbox/` 列举收件箱，按文件名/主题关键词按需读取未收编条目——条目自足，**未收编同样可发现可消费**（发现不依赖收编）。

**Selective Load (<=10s)**: 按两跳命中读取内容，判断相关性，携带相关条目进入 Plan Mode，并在设计文档的 `## 相关历史知识` 中引用。

**Staleness Awareness（时效性核对）**: 加载的条目若日期距今 >180 天（≈ autopilot 季度迭代周期），引用其代码事实（字段名 / `file:line` / Tier 编号 / 函数名）作为依据前，**必须先用 grep/Read 核对当前源码**——knowledge 是 point-in-time 观察非 live state，旧条目里的代码引用可能已随版本变更（字段重命名、函数迁移、Tier 重编号）。不阻断加载，仅在引用为"事实依据"时核对（对齐 memdir `memoryFreshnessText` 哲学；本机制源于 [2026-06-17] memdir 对比调研）。

**Fallback**: 无 `index.md` 时直接全量加载 `decisions.md` 和 `patterns.md`（<=10s），inbox 两跳照常执行。

**Skip conditions**: 目录不存在、文件为空、或无条目与当前目标匹配时跳过。Never block on knowledge loading.

## Extraction Rules (Merge Phase)

Before commit Agent, review the full autopilot run to extract knowledge worth preserving. **写目标 = `inbox/` 独立新文件**（Inbox Protocol）——commit Agent will include them via `git add -A` (normal repo) or the routing below (worktree)。

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

0. 分析状态文件（设计文档、QA 报告、变更日志、auto-fix 历程）中的候选条目
1. 有值得记录的条目 → 按 Inbox Protocol 写 `inbox/YYYY-MM-DD-<slug>.md`：
   a. `mkdir -p .autopilot/knowledge/inbox/`，自动生成 tags（模块名/技术栈/问题类型，2-5 个）
   b. 独立新文件（同名 `-2` 递增），条目含 `<!-- tags: ... -->`，**写入后执行 Anti-Overfitting 5 问自检**（Lesson/Choice 字段无具体值）
   c. **时效锚点标注**：若条目 Evidence 含代码事实引用（`file:line` / 字段名 / 函数名 / Tier 编号），在该条目的 **Evidence 字段内**（禁止追加在 Lesson/Choice 行或条目标题——违反 Principle-Evidence 分离）追加 `（核对锚点：YYYY-MM-DD 源码版本）`，为 Consumption 阶段的时效核对留可机读时间锚
2. 写侧到此为止：不做 Integration（语义合并移收编侧）、不更新 `index.md`、不写聚合层
3. 无值得记录的内容 → 直接跳过（无需任何记录）

**主检出侧收编**：写完本次 inbox 条目后，若本检出是主检出侧（`.git` 为目录）→ 执行 Collection Protocol；worktree 会话到此为止（永不收编）。

**Time limit**: 2 分钟内完成。宁可少写高质量条目，不要穷举。

## Collection Protocol (Primary Checkout Only)

**收编主体判定 = `.git` 是目录**（主检出侧）；worktree 检出 `.git` 是文件，**永不收编**（聚合层 symlink 写穿面归零）。

**触发条件**：主检出侧 ∧ `inbox/` 文件数 ≥ 1（merge 阶段写完本次条目后检查）。收编是聚合优化非正确性依赖——永不发生系统仍正确（inbox 是正式知识层，消费端两跳可发现）。

**收编步骤**：

1. 读 `inbox/` 全部积压条目
2. 按「步骤 0：搜索已有条目」+ Integration over Append 决策规则，语义合并进 `decisions.md` / `patterns.md` / `domains/*.md`（升级抽象层级 / 扩充 Evidence，非照搬）
3. 重写 `index.md` 收编基（索引与聚合层条目一一对应，重建后 ≤100 行）
4. 删除已收编的 inbox 文件

**冲突处置（union）**：收编/合并遇 git 冲突——含并行会话同日同 slug 跨分支 add/add 撞名——**两侧条目都保留、其一改名，禁丢弃任侧**，禁静默取单侧。

**残余风险（显式记录）**：主检出侧并行会话同时收编可能互相冲突。按 AI First 原则不新增机械守卫（援引 [2026-06-02] prose-iron-law-to-hook 决策），豁免理由：git merge 冲突本身即确定性 backstop（撞了必报冲突，不会静默丢数据）+ doctor Dim 12 inbox 积压计数（>10 提醒收编）提供事后确定性信号。

## Commit Routing

知识文件写入后**不立即 `git commit`**。提交职责由 commit Agent / worktree 路由承担：

- **普通模式**：commit Agent 的 `git add -A` 自动包含 `.autopilot/knowledge/`（含 inbox 新文件）改动，与代码一次 commit。
- **worktree 模式**：聚合层四类文件（`index.md`/`decisions.md`/`patterns.md`/`domains`）是 symlink 指向主仓库，worktree 的 commit Agent 不会包含它们；`inbox/` 是真实目录，inbox 新文件随分支 merge 自然合入。commit Agent 之后，编排器在主仓库执行兜底提交：

```bash
# 定位主仓库（knowledge/ 任一文件是 symlink 时取 realpath）
K_ITEM=".autopilot/knowledge/decisions.md"
if [ -L "$K_ITEM" ]; then
  MAIN_REPO=$(cd "$(dirname "$(realpath "$K_ITEM")")/.." && git rev-parse --show-toplevel)
  if [ -n "$(git -C "$MAIN_REPO" status --porcelain .autopilot/)" ]; then
    git -C "$MAIN_REPO" add .autopilot/
    git -C "$MAIN_REPO" commit -m "docs(knowledge): <brief summary>"
  fi
fi
```

普通模式下 `$K_ITEM` 不是 symlink，上述脚本不执行；主仓库=当前仓库，commit Agent 已提交 → `git status --porcelain` 为空 → 跳过。

## Legacy Migration（存量迁移，一次性）

旧布局（无 inbox）存量不阻塞任何流程——收编永不发生系统仍正确。升级到本协议后按需一次性迁移（建议单独会话执行，需用户确认）：

1. `mkdir -p .autopilot/knowledge/inbox/`，将未收编的孤儿条目移入 `inbox/`（保持条目格式）
2. 执行一次 Collection Protocol：存量条目语义收编进聚合层 + 重建 `index.md` + 清空 inbox
3. 重建时 `index.md` 若已超 100 行红线（本仓现状 136 行即超线，首次 dogfood 收编即需压缩）：条目一行一条、合并同主题、领域条目指向 `domains/*.md`

## Domain Partition Guide

当全局文件超过 100 行时，识别可聚合的同领域条目，创建 `domains/{domain}.md`，迁移后更新 `index.md` 中的路径引用，并从全局文件删除已迁移条目。**迁移操作需要用户确认。**

**常见领域划分**: frontend, backend, testing, infra, database, auth, performance

## Size Management

- 全局文件（decisions.md / patterns.md）超 100 行 → 追加警告注释并通知用户建议迁移
- 领域文件（domains/*.md）超 150 行 → 追加警告注释并通知用户建议拆分或裁剪旧条目
- 不要自动迁移——知识整理需要人工判断

运行 `/autopilot doctor` 可获得知识库健康度评估（Dim 12），包括过拟合密度扫描、重复主题检测、文件大小健康度分析、索引一致性检查和 inbox 积压计数（>10 提醒收编）。
