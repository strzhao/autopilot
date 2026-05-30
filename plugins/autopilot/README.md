# autopilot — AI 自动驾驶工程套件

> **v3.40.0**：合入 **Tier 1 AI-First 反过拟合减法**——此前以 v3.37.1 在独立工作树完成、未随 v3.38/v3.39 进 main，本版补合并升版。删除 prompt/references 中「用刚性数字/正则替 AI 做语义判断」的过拟合规则，改为 AI 自适应：plan-reviewer 去伪精度置信度分数线（≥91/80-90/<80 + 子任务 ≤8 硬上限 → BLOCKER/重要语义二分 + 范围蔓延语义判断）、qa-reviewer Section C 正则转语义、Explore agent 计数自适应（按代码面自行决定，不再裸计数 1-2/最多3/<5文件）、防合理化去重恢复 SSOT。合理护栏（信息隔离/终止边界/契约/客观门禁）一律保留——AI First ≠ 删护栏，只删限制 AI 发挥的伪精度。附 `tests/acceptance/tier1-deoverfitting.acceptance.test.sh` 9 条不变量护栏 grep（编辑生效 + 护栏未误伤双向断言）。纯 prompt/markdown 减法，零脚本改动。

> **v3.39.0**：**谓词传动轴接线**——收尾 v3.38.0 谓词闸门的未竟环节。诊断发现 v3.38.0 只统一了两端的"语言"（生成器产 EARS-OST 谓词、QA 闸门据谓词放行），却没接通中间的"数据流"：生成器产的谓词写进 `## 验收场景` 后无人消费，闸门说的"预注册验收谓词"是个**无上游来源、无执行者、无报告落点的悬空引用**；`## 验收场景`（谓词）/`## 验证方案`（散文场景）/`## 红队验收测试`（红队据设计文档自写）三个语义重叠的区域互不连通，谓词成孤岛。本版让 **`## 验收场景` 成为全链路谓词唯一权威源（SSOT）**，五处接线贯通：① design 步骤 2 编排器**冻结写入** `## 验收场景`；② 红队**双消费**——新增谓词输入，每条 `det-machine`/`real-process` 谓词须对应 ≥1 个硬断言（期望值取自 `assert:`），`visual-residue` 留 QA 真机（论证：谓词=设计意图前身，与设计文档同级，读它不破信息隔离铁律）；③ Tier 1.5 主驱动从散文场景改为谓词清单，**执行者=编排器**，对每条谓词驱动真实产物→观测→产 `(谓词, artifact, PASS/FAIL)` 三元组，`## 验证方案` 降为"如何驱动产物"的前置说明（此处即下一步 harness 的挂载点）；④ 闸门补"三元组来自 Tier 1.5 谓词求值"，闭合悬空引用；⑤ qa-report Tier 1.5 区升为三元组表，qa-reviewer Section C 扩"审谓词质量"（tautological 谓词打回 + artifact 真实性核验）。附：文档化 state.md `## 验收场景` 区域、修正 qa-report 过期 `## QA 报告` 区域引用。**本版只接数据流，不做 harness**（按栈探明驱动/观测+脚手架生成，是接线落地后的独立下一步）。

> **v3.38.0**：QA 验证从"打分制"改"**谓词闸门**"——根治"测试全绿仍出厂不可用"的抽卡问题（动机：claude-code-buddy 一个 launcher 项目 864 测全绿 + SC 全覆盖，真机却"输入框完全不可用 / 回车弹 Keychain"）。① 验收场景的 OST 升级为 **EARS-OST + 观测绑定**：`When/While/If + shall` 冻结意图（消歧）+ `observe/assert/channel` 机器谓词，`channel ∈ det-machine（数字/exit/文件/AX 属性，零主观）｜ real-process（真子进程/真 API 一次冒烟）｜ visual-residue（仅 AX 表达不了的纯视觉，二值清单）`；GUI 断言强制走可达性树、禁 golden-image 像素快照当回归门（基线易漂移、re-record 即失值）。② qa-reviewer 删"整体评分 X/100 + Ready to merge"，改二值 + Critical（审查者只供 Critical 事实，不下放行结论）。③ 结果判定改 **谓词闸门**：每条预注册谓词产出 `(谓词, artifact, PASS/FAIL)` 三元组，**PASS 必须引真实 artifact**，无法观测（INCONCLUSIVE）记 FAIL，闸门 = ∀谓词 PASS + 0 Critical（无分数、无 Ready to merge）。④ 封两个自审逃生口：smoke 模式与 qa-reviewer 失败时**不再"编排器自审"**（自审无独立性、是抽卡来源），改重试或 review-accept 等人。⑤ 反 tautological 检查前移到 design 阶段审谓词（`height>=44` 合格 / `element visible` 打回）。附：清理 5 个孤儿 QA 文档（-403 行：qa-phase/project-qa-guide/code-quality-reviewer-prompt/design-reviewer-prompt/review-checklist）+ 补 project-qa playbook 入 autopilot-project（修复 mode=project-qa 此前无 live playbook 的潜伏 bug）+ 移除 plan-review-toc 过期工作树守卫。选型对齐业界：EARS（Mavin/AWS Kiro）/ DbC（Meyer）/ property-based / RULERS 抗 LLM-judge 方差，结论是 autopilot 已有 OST+DbC 等价语法、只缺观测绑定，故增强不嫁接。

> **v3.36.3**：修复 project 模式 auto-chain 失效**双链第 2 环**（v3.36.1-3 三连击至此双链 4 环全修）。根因：stop-hook 三处 Case 切换 state 文件后（Case 0.5 project-design → 首子任务、Case 1 AI next_task auto-chain、Case 2-ALL_DONE 全任务完成 → project-qa）**只重读了 `PHASE/ITERATION/MAX_ITERATIONS`，未重读 `GATE/AUTO_APPROVE`**。导致旧 state 若残留 `gate=review-accept`（v3.36.2 修了「当前 state 卡 review-accept」但没修「下游 Case 切换时旧 GATE 变量过期」），第 6 步审批门用旧 GATE 变量误命中、notify + exit 0、新 state 的 block JSON 永不输出。现场证据：claude-code-buddy 002→003 卡死，stop.txt 显示 AI 自己写「Stop-hook 接管推进到 task 003」但实际 stop-hook 静默 exit。修复：stop-hook.sh 三处 Case 各加 2 行 `GATE=$(get_field "gate" || true)` + `AUTO_APPROVE=$(get_field "auto_approve" || true)`，共 12 行新增零删除。R12 第 6 条断言完整 fixture 复现 002→003 卡死并验证修复。SKILL.md merge §5 顺手加「确认 gate 清空」软性提醒（防御主力靠 stop-hook，不依赖 AI 行为）。

> **v3.36.2**：修复 project 模式 auto-chain 失效**双链第 3 环**。根因：stop-hook 第 6 步处理 review-accept gate 时**完全不看 `auto_approve` 字段**，与 design 阶段 auto_approve 跳过审批的逻辑不对称；auto-chain 子任务 QA 通过设 gate=review-accept 后被静默 exit、永不进 merge。修复：stop-hook.sh 第 5.5 节插入 14 行短路（三条件 AND：`gate=="review-accept"` && `phase=="qa"` && `auto_approve=="true"` → 清 gate + phase→merge + 落入下方 block JSON 注入路径）；新增 `auto-approve-gate-bypass.acceptance.test.sh`（R12，5 条断言：正向 + 双向反向行为 + 2 个版本同步守护）。附范围扩大根治 v3.36.1 漏修的硬编码盲区：`brainstorm-default` / `plan-review-html` / `brainstorm-skill-extract` / `tier5-quantitative` 4 个 acceptance test 的 `TARGET_VERSION="3.x.0"` 改为从 plugin.json 动态读，根治 [2026-05-09] knowledge 警告的「acceptance test 隐藏版本同步盲区」（升一次版本只需改 plugin.json 一处）。全套件 9/16 → 13/16 PASS。

> **v3.36.1**：修复 project 模式 auto-chain 失效回归（cdad541 引入约 1 个月）。根因：SKILL.md merge 章节在 "恢复完整内联" 时漏掉 Auto-Chain 评估步骤，导致 AI 永不设置 `next_task`，stop-hook 静默释放、子任务完成后无法自动链接下一个任务。修复：SKILL.md merge §2 补回 Auto-Chain 评估段（4 行）+ §5 清理交叉引用；`skill-references-consistency.acceptance.test.sh` 新增双重 CI 守护（merge 章节必须含 `next_task` **且**含 `#### N. Auto-Chain` 标题段）。dry-run 双向验证：删段 → 测试 FAIL exit 1，恢复 → PASS exit 0。

> **v3.36.0**：QA 阶段新增 **Tier 5 量化指标门禁**（Wave 1 内并行）— Stryker mutation score ≥ 60% + Istanbul/c8 coverage line ≥ 80% / branch ≥ 70%。工具可用时**强制**，任一未达 → ❌ → auto-fix（**不可 ⚠️ 复盘绕过**，与 Tier 3.5 不阻塞模式区分）；两子项均无工具 → N/A + ⚠️ 不阻塞 + doctor 推荐安装。设计依据：Meta FSE 2025（mutation-targeted 32% vs coverage-targeted 5.3%；约 50% LLM 测试无法 kill 任何 mutation）。同步精简 `references/test-mutation-survival.md` 从 201 → 60 行为"工具不可用时降级清单"，保留 5 类核心 mutator + Mutation-Survival 自检铁律兜底。CI 阈值 SKILL.md 行数从 < 600 上调到 < 615 预留空间。新增 `references/quantitative-metrics.md`（含 `tier5-report.json` schema 完整定义 + 双向语义对偶 + 降级矩阵 4 状态）；`autopilot-doctor` Dim 1 扩展 L4 量化工具检测 + `detect_quantitative_tools()` 函数。

> **v3.35.0**：`.autopilot/` 目录二级分层 — `knowledge/`（git 入库，跨任务持久知识）+ `runtime/`（gitignored，单次运行产物）。三层防御解决「AI 在 commit 时遗忘 autopilot 文件」痛点：(1) `.gitignore` 单条规则 `.autopilot/runtime/` 拦截所有运行时产物；(2) `autopilot-commit` 新增 5.c 子节显式检查知识库变更；(3) `autopilot-doctor` Dim 12 新增子项 6「文件分类正确性」长期巡检。`setup.sh` 内置幂等迁移逻辑，老用户首次升级自动迁移旧布局；`worktree.mjs` 新增 `cleanupStaleLinks()` helper 清理 v3.34 残留 symlink。版本号 acceptance test 同步动态化（消灭 [2026-05-09] 已知盲区）。

> **v3.33.0**：brainstorm 抽离为独立 skill（autopilot-brainstorm），主 SKILL 通过 `Skill: "autopilot-brainstorm"` 显式委托；删除 references/brainstorm-guide.md，visual-companion-guide.md 随迁至新 skill；新 skill 借鉴 superpowers brainstorming 的 HARD-GATE / Anti-Pattern / Checklist 强语言风格，解决 brainstorm 在 references 后置位置被 AI 跳过的痛点。主 SKILL 实际净减 2 行（644→642，原设计预估 ~64 行偏乐观——brainstorm-guide.md 89 行内容从未内嵌主 SKILL，只是 4 行引用链接被删除）。
>
> **v3.24.0**：契约规约协议 — 集中 references/contract-protocol.md（DbC 谓词 + Pact example）+ 新增 contract-checker agent 在蓝队完成后自动校验实现 vs 契约字面一致性 + 历史豁免机制（contract_required frontmatter）。基于 relight 7 个红蓝契约不对齐案例 + 业界 CDC/MetaGPT/CANDOR SOTA 模式落地。
>
> **v3.23.0**：基于 relight 项目回归案例（c3648c2 删除字段映射 + 路由，CI 红但流程过）加固 TDD 质量。4 处铁律改动：(1) red-team-prompt 加测试质量铁律段，禁止 `if (status === expected) {assert} else {warn}` 等宽容跳过模式；(2) merge-phase 新增 2.5 CI 验证步骤，commit 后已 push 时通过 gh run watch 等 CI 结论，CI 失败回 auto-fix（不改变 commit-only 默认行为）；(3) qa-reviewer 加 Section C 红队测试质量审查；(4) anti-rationalization 加红队 Agent 视角反模式段。
>
> **v3.22.1**：修复 stop-hook 对 `run_in_background=true` 的 Agent 无法识别的 bug — async tool_result 启动瞬间就回流，原 sync 检测误判完成。新增 async pending 检测路径（toolUseResult.isAsync + queue-operation 完成事件比对），与 sync 检测合并判定。
>
> **v3.22.0**：design 阶段步骤 4「请求审批」新增可选 HTML 浏览器评审路径（复用 visual-companion，0 runtime 依赖；内嵌 marked.min.js 提供原生 markdown 渲染——标题/列表/表格/代码块）。环境变量 `AUTOPILOT_HTML_REVIEW=1` 或 frontmatter `html_review: true` 开启，默认仍走 AskUserQuestion + preview，preview 末尾含开启提示。
>
> **v3.17.1**：修复 stop-hook 在 implement 阶段对后台 sub-agent 无感知导致主 agent 反复无效唤醒的 bug（解析 transcript_path 检测主线程 pending Agent，仅 implement 阶段静默放行）。
>
> **v3.17.0**：新增 `--fast` 快速模式（design 阶段 1 个 Explore agent + 编排器自审，QA 阶段 smoke 模式，自动检测小 diff 降级）。

从目标描述到代码合并，全程自动化。人只在两个审批门介入：**设计审批** 和 **验收审批**。

## 工作流程

```
用户输入目标 → AI 设计方案 → [审批门 1] → 并行分叉:
    蓝队(编码) + 红队(仅看设计写验收测试) → 合流 → AI 全面测试(红队测试优先)
    → AI 自动修复 ←→ AI 重新测试(循环) → [审批门 2] → AI 合并代码
```

## 快速开始

```bash
# 推荐：在 worktree 中运行（隔离代码改动）
claude -w autopilot-avatar

# 启动全流程闭环
/autopilot 实现用户头像上传功能，支持裁剪和压缩

# AI 自动完成设计后，审批设计方案
/autopilot approve

# 或者要求修改
/autopilot revise 需要支持 WebP 格式

# AI 自动完成编码和测试后，验收代码
/autopilot approve

# 独立使用智能提交（不需要全流程）
/autopilot commit
```

## 命令

| 命令 | 说明 |
|------|------|
| `/autopilot <目标>` | 启动全流程闭环 |
| `/autopilot commit` | 智能提交（React 优化 + 代码测验 + 任务同步） |
| `/autopilot doctor` | 工程健康度诊断（评估 autopilot 兼容性） |
| `/autopilot doctor --fix` | 诊断 + 自动修复低分项 |
| `/autopilot approve` | 批准当前审批门 |
| `/autopilot revise <反馈>` | 要求修改当前阶段产出 |
| `/autopilot status` | 查看当前状态 |
| `/autopilot cancel` | 取消并清理 |
| `/autopilot --help` | 显示帮助 |

## 选项

| 选项 | 默认值 | 说明 |
|------|--------|------|
| `--max-iterations` | 30 | 最大迭代次数 |
| `--max-retries` | 3 | QA 失败后自动修复的最大重试次数 |

## 阶段说明

### 1. Design（设计）
AI 分析目标，探索代码库，产出设计文档和实现计划。完成后进入审批门。

### 2. Implement（实现）— 红蓝对抗
并行启动两个 AI Agent：
- **蓝队（实现者）**：按计划逐任务编码，TDD 模式
- **红队（验证者）**：仅看设计文档编写验收测试，不能看实现代码

信息隔离确保测试独立于实现，验证"应该做什么"而非"已经做了什么"。

### 3. QA（质量检查）
五层质量检查：
- **Tier 0**: 红队验收测试（最高优先级，失败 = 实现不符合设计）
- **Tier 1**: 类型检查、Lint、单元测试、构建验证（融合 local-test 智能验证策略）
- **Tier 2a**: 设计符合性（先做）
- **Tier 2b**: 代码质量（后做）— 模式一致性、安全审查、边界处理
- **Tier 3**: Dev server 启动、API 端点验证、导入完整性
- **Tier 3.5**: 性能保障验证（条件性，需前端项目 + 性能工具就位 + 本次变更涉及前端）
- **Tier 4**: 回归检查

### 4. Auto-fix（自动修复）
QA 发现问题时，按系统化调试方法论（观察 → 假设 → 验证 → 修复）逐项修复。**铁律：不允许修改红队测试**——如果实现通不过验收测试，问题在实现而非测试。最多重试 3 次。

### 5. Merge（合并）
调用 autopilot-commit 完成智能提交，生成完成报告。

## 智能提交（/autopilot commit）

独立于全流程闭环，可单独使用：
- 三阶段并行执行模型（分析 → 并行优化 → 提交）
- 自动检测 React 代码并调用最佳实践优化
- Bugfix 验证：检测到 bugfix 自动补充单测
- 提交前代码理解测验（监督者视角）
- CLAUDE.md 智能更新 + 版本自动升级
- ai-todo 任务同步
- 高质量中文提交信息

## 工程诊断（/autopilot doctor）

扫描项目工程基础设施，输出 11 维度加权评分（S/A/B/C/D/F 等级）：
- 测试基础设施（17%）、类型安全（12%）、代码质量工具链（11%）、构建系统（11%）
- CI/CD（7%）、项目结构（7%）、文档质量（7%）、Git 工作流（7%）
- 依赖健康（6%）、AI 就绪度（7%）、性能保障（8%）

输出 autopilot 兼容性矩阵（哪些功能可用/降级/不可用）和 Top 3 改进建议。

使用 `--fix` 自动修复低分项（每个修复前确认）。报告保存到 `.autopilot/runtime/doctor-report.md`。

## 可追溯性

所有过程记录在 `.autopilot/autopilot.local.md` 状态文件中：
- 目标描述、设计文档、实现计划
- 红队验收测试和验收标准
- 每轮 QA 报告（完整保留历史）
- 变更日志（时间戳 + 每个关键事件）

## Worktree 自动初始化机制

autopilot plugin 通过 `WorktreeCreate` hook 在 worktree 创建时配置环境（symlink、依赖安装、`local-config.json`）。但 Claude Code 当前版本（≤ 2.1.128）有一个已知 gap，详见 [issue #36205](https://github.com/anthropics/claude-code/issues/36205)：**`claude -w` 触发的 `WorktreeCreate` hook 只派发给 user/project `settings.json`，不派发给 plugin 的 `hooks.json`**。

为此 plugin 同时注册了 `SessionStart` hook 作为兜底：每次 session 启动时检测 cwd 是否为未配置的 worktree，是就自动 repair。代价是 worktree 首次启动 session 时会卡几十秒（pnpm install）。

如想跳过兜底延迟、在 worktree 创建瞬间就完成初始化，可在 `~/.claude/settings.json` 直接注册 `WorktreeCreate` hook 调 `worktree.mjs create`，但需硬编码 plugin 缓存路径（plugin 升级后需更新）。

## 与其他插件的配合

- **worktree（内置）**: 建议在 worktree 中运行，隔离代码改动
- **ralph-loop**: 两者互斥（共用 Stop hook 机制）
