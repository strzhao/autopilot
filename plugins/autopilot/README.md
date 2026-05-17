# autopilot — AI 自动驾驶工程套件

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

使用 `--fix` 自动修复低分项（每个修复前确认）。报告保存到 `.autopilot/doctor-report.md`。

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
