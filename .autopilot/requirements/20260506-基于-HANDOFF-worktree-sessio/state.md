---
active: true
phase: "merge"
gate: ""
iteration: 3
max_iterations: 30
max_retries: 3
retry_count: 0
mode: ""
plan_mode: ""
brief_file: ""
next_task: ""
auto_approve: false
knowledge_extracted: ""
task_dir: "/Users/stringzhao/workspace/string-claude-code-plugin/.autopilot/requirements/20260506-基于-HANDOFF-worktree-sessio"
session_id: 4bf08f73-95b9-464d-ae0b-5d43e1d2faad
started_at: "2026-05-05T16:08:25Z"
---

## 目标
基于 HANDOFF-worktree-sessionstart-fallback.md 里的方案，了解后直接接入 plan review 环节

> 📚 项目知识库已存在: .autopilot/。design 阶段请先加载相关知识上下文。

## 设计文档

### Context
`claude code -w <name>` 创建 worktree 时 Claude Code（≤ 2.1.128）只派发 `WorktreeCreate` hook 给 user/project `settings.json`，不派发给 plugin `hooks.json`。autopilot 现有的 worktree 自动初始化（symlink + pnpm install + local-config.json）完全不跑，用户拿到裸 worktree。已通过 hook wrapper + log 对照实证锁定根因（详见 HANDOFF-worktree-sessionstart-fallback.md 第 31-82 行）。

修复方案：plugin `hooks.json` 注册 `SessionStart` hook（plugin hooks.json 接收的事件），每次 session 启动时检测 cwd 是否为未配置的 worktree，是就调用现有 `worktree.mjs repair`。**纯 plugin 内改动**。代价：worktree 首次启动 session 卡几十秒（pnpm install），可接受。

### 核心思路
`claude -w` 时序：`git worktree add` → 启动 session → 派发 `SessionStart`。已实证 plugin hooks.json **能接收 `SessionStart`**。新增 hook 即可在 session 启动瞬间检测并 repair。

幂等保障：
- 主仓库（`.git` 是目录）→ silent exit
- 已配好（`.autopilot` symlink + `node_modules` 都在）→ silent exit
- 仅未配好 worktree → 触发 repair

### 五处改动

**改动 1**：`plugins/autopilot/hooks/hooks.json` 在现有 3 个 hook 之外新增 `SessionStart` 字段，command 指向 `${CLAUDE_PLUGIN_ROOT}/scripts/worktree-bootstrap.sh`，timeout 300。

**改动 2**：新增 `plugins/autopilot/scripts/worktree-bootstrap.sh`：
- 用 `jq -r '.cwd // ""'` 解析 stdin（与 stop-hook.sh 风格一致），失败 fallback 到 `pwd`
- `[ -f "$CWD/.git" ] || exit 0` → 主仓库 silent
- `[ -L "$CWD/.autopilot" ] && [ -d "$CWD/node_modules" ] && exit 0` → 已配好 silent
- 否则 `echo "[autopilot] ..." >&2` + `node ${CLAUDE_PLUGIN_ROOT}/scripts/worktree.mjs repair "$CWD" >&2`
- repair 失败用 `|| { ... }` 包住打印失败提示，最终始终 `exit 0` 不阻断 session
- chmod +x

**改动 3**：新增 `plugins/autopilot/scripts/worktree-bootstrap.acceptance.test.mjs`，沿用现有 `*.acceptance.test.mjs` 约定（`node:test` + `execFile` + `mkdtemp`），覆盖 5 个场景。

**改动 4**：根 `package.json` 的 `test` 脚本末尾追加 `plugins/autopilot/scripts/worktree-bootstrap.acceptance.test.mjs`（保持显式列表风格，避免 glob 误触）。

**改动 5**：`README.md` + `plugins/autopilot/README.md` 加「Worktree 自动初始化机制」段落（说明 WorktreeCreate hook + 已知 gap #36205 + SessionStart 兜底 + 首次卡顿成本 + 用户可选优化）。

**版本同步**：
- `plugins/autopilot/.claude-plugin/plugin.json` → 3.15.0
- `.claude-plugin/marketplace.json` autopilot 条目 → 3.15.0
- `CLAUDE.md` 标题 `(v3.14.0)` → `(v3.15.0)`
- `CLAUDE.md` 更新日志新增 2026-05-06 条目

### 范围控制（明确**不**做）
- ❌ 不修改 `worktree.mjs`（脚本本身已实证正确）
- ❌ 不修改 `WorktreeCreate` / `WorktreeRemove` / `Stop` hook 配置
- ❌ 不在 user-settings 注册 hook
- ❌ 不引入新依赖

### 风险与缓解
| 风险 | 缓解 |
|------|------|
| 主仓库 session 也被触发 | `.git` 是文件 silent exit |
| 已配好 worktree 重复 repair | symlink + node_modules 双重检测后 silent exit |
| stdin JSON 解析失败 | jq 失败 fallback 到 pwd |
| repair 失败（pnpm 网络问题） | `|| { ... }` 包住，最终 `exit 0` |
| 时序竞态 | repair 函数本身幂等，下次 session 启动会再次重跑 |

## 实现计划

按依赖顺序执行（其中红队测试由独立 Agent 编写，与蓝队并行）：

- [x] 1. **蓝队**：新增 `plugins/autopilot/scripts/worktree-bootstrap.sh` + `chmod +x` ✅
- [x] 2. **蓝队**：修改 `plugins/autopilot/hooks/hooks.json` 新增 `SessionStart` 字段 ✅
- [x] 3. **红队**：新增 `plugins/autopilot/scripts/worktree-bootstrap.acceptance.test.mjs`（9 个场景） ✅
- [x] 4. **蓝队**：更新 `package.json` `test` 脚本追加新测试文件 ✅
- [x] 5. **蓝队**：更新 `README.md` 和 `plugins/autopilot/README.md` 加「Worktree 自动初始化机制」段落 ✅
- [x] 6. **蓝队**：同步升级 3 处版本号 + CLAUDE.md 更新日志 ✅
- [x] 7. **QA**：跑 ShellCheck + 跑 `npm test` ✅

### 验证方案

**真实测试场景**（Tier 1.5，自动化为 acceptance test）：

| # | 场景 | 通过条件 |
|---|------|----------|
| 1 [独立] | 主仓库 stdin → silent | exit 0、stderr 无 `[autopilot]` 输出 |
| 2 [独立] | 已配好 worktree → silent | exit 0、stderr 无 `[autopilot]` 输出 |
| 3 [独立] | 裸 worktree → repair | exit 0、stderr 含 `[autopilot] worktree 检测到未配置`、子进程调用 `worktree.mjs repair $CWD` |
| 4 [独立] | repair 失败 → 不阻断 | exit 0、stderr 含 `[autopilot] repair 失败` |
| 5 [独立] | 非法 JSON → fallback pwd | exit 0、按 pwd 走主仓库分支 silent |
| 6 (e2e) | `claude -w newname` 端到端 | worktree 下 `.autopilot` symlink + node_modules + local-config.json 齐全（**需用户手动在新会话验证，不纳入 acceptance test**） |

**执行策略**：场景 1-5 通过 `npm test`（含新测试文件）一键自动化；场景 6 由用户在 QA 阶段开新 claude session 人工验收。

### 验收标准（供红队 Agent 使用）
1. 主仓库 silent exit（exit 0 + stderr 空）
2. 已配置 worktree silent exit（exit 0 + stderr 空）
3. 未配置 worktree 触发 repair（exit 0 + stderr 进度提示 + 实际调用 worktree.mjs repair 子进程）
4. repair 失败不阻断（exit 0 + stderr 失败提示）
5. stdin 容错（非法 JSON / 空 / 缺 cwd 时 fallback 到 pwd）
6. hooks.json JSON 合法且 SessionStart 配置正确
7. 3 处版本号 + CLAUDE.md 标题同步升至 3.15.0
8. `npm test` 命令包含新测试文件

## 红队验收测试

**测试文件**：`plugins/autopilot/scripts/worktree-bootstrap.acceptance.test.mjs`（9 个测试 case，覆盖 5 个核心场景 + 协议附加断言）

**信息隔离声明**：红队 Agent 仅基于状态文件 `## 设计文档` 中的黑盒契约编写，未读取蓝队新写的 `worktree-bootstrap.sh` 实现。Mock 策略：通过 `CLAUDE_PLUGIN_ROOT` 环境变量重定向到临时目录，里面放 ESM 兼容的 mock `worktree.mjs`，记录调用参数到 calllog 文件。

**验收标准覆盖矩阵**：

| 测试 case | 验收标准 | 验证要点 |
|-----------|----------|----------|
| 主仓库 silent exit | 标准 1 | `.git` 是目录 → exit 0 + stderr 空 |
| 已配好 worktree silent exit | 标准 2 | symlink + node_modules → exit 0 + stderr 空（幂等） |
| 裸 worktree 触发 repair（无 symlink） | 标准 3 | exit 0 + stderr 含 `[autopilot] worktree 检测到未配置` + mock calllog 含 `repair <cwd>` |
| 裸 worktree 触发 repair（symlink 存在但非 link） | 标准 3 边界 | 验证"非 symlink 的 .autopilot"也触发 repair |
| repair 失败不阻断 | 标准 4 | mock 退 1 → 父脚本 exit 0 + stderr 含失败提示 + calllog 仍存在 |
| 非法 JSON fallback | 标准 5 | `{garbage}` 输入 → exit 0 + stdout 空 |
| 空 stdin fallback | 标准 5 边界 | 空输入 → exit 0 + 不崩溃 |
| stdout 协议（主仓库） | 标准 1 + 输出协议 | stdout 永远为空字节 |
| stdout 协议（裸 worktree） | 标准 3 + 输出协议 | repair 子进程不污染父 stdout |

**红队对设计文档歧义点的处理**：
1. 标准 4 stderr 措辞（中文 vs 英文）→ 断言放宽为 `stderr.includes('repair') && (含 失败/fail/error 之一)` 容忍语言差异
2. 标准 5 fallback 后行为依赖运行时 pwd → 测试用主仓库目录验证 fallback 后 silent，worktree fallback 已由标准 3/4 充分覆盖

## QA 报告

### 轮次 1（2026-05-06T02:00:00Z）— ✅ 全部通过

#### 变更分析
git diff --stat：8 个文件变更（1 新脚本 + 1 新测试 + 6 个修改的 JSON/MD 配置）。分类：CLI/Hook 脚本 + 配置 + 测试 + 文档。影响半径：中等（多文件但都聚焦于一个 feature）。

#### Wave 1 — 命令执行结果

| Tier | 检查项 | 状态 | 证据 |
|------|--------|------|------|
| Tier 0 | 红队验收测试 | ✅ | `node --test worktree-bootstrap.acceptance.test.mjs` → 9 pass, 0 fail |
| Tier 1 | ShellCheck on bash 脚本 | ✅ | `npx shellcheck plugins/autopilot/scripts/worktree-bootstrap.sh` → exit 0 |
| Tier 1 | JSON 合法性（4 文件） | ✅ | hooks.json / package.json / marketplace.json / plugin.json 全部 `JSON.parse` 通过 |
| Tier 1 | 全套单元/契约测试（npm test）| ✅ | 53/53 pass，0 fail（原 44 + 新 9） |
| Tier 1 | 类型检查（tsc） | N/A | 项目无 TypeScript |
| Tier 1 | 构建（build） | N/A | 项目无构建步骤（纯插件配置） |
| Tier 3 | 集成验证（dev server / API） | N/A | 项目为 hook 脚本插件，无 dev server / API 端点 |
| Tier 3.5 | 性能保障（Lighthouse / Web Vitals） | N/A | 非前端项目 |
| Tier 4 | 回归检查 | ✅ | 既有 44 测试零回归 |

#### Wave 1.5 — 真实场景验证（5/5 全部独立执行）

| # | 场景 | 执行 | 输出 |
|---|------|------|------|
| 1 | 主仓库 stdin → silent | `node --test --test-name-pattern="场景 1" plugins/autopilot/scripts/worktree-bootstrap.acceptance.test.mjs` | `ok 1 - 场景 1：主仓库 session — .git 是目录` (1 pass) |
| 2 | 已配好 worktree → silent | `node --test --test-name-pattern="场景 2" plugins/autopilot/scripts/worktree-bootstrap.acceptance.test.mjs` | `ok 1 - 场景 2：已配好 worktree — silent exit` (1 pass) |
| 3 | 裸 worktree → repair | `node --test --test-name-pattern="场景 3" plugins/autopilot/scripts/worktree-bootstrap.acceptance.test.mjs` | `ok 1 - 场景 3：裸 worktree — 触发 repair` (2 pass，含边界 case：非 symlink 的 .autopilot) |
| 4 | repair 失败 → 不阻断 | `node --test --test-name-pattern="场景 4" plugins/autopilot/scripts/worktree-bootstrap.acceptance.test.mjs` | `ok 1 - 场景 4：裸 worktree + repair 失败 — exit 0 不阻断` (1 pass) |
| 5 | 非法 JSON → fallback pwd | `node --test --test-name-pattern="场景 5" plugins/autopilot/scripts/worktree-bootstrap.acceptance.test.mjs` | `ok 1 - 场景 5：非法 stdin JSON — 优雅降级` (2 pass，含空 stdin 边界) |
| 6 | `claude -w newname` 端到端 | **N/A — 由用户在新会话手动验收** | 设计文档明确标注「不纳入 acceptance test」，merge 后请用户跑一次新建 worktree 验证：`.autopilot` symlink + `node_modules` + `local-config.json` 三件套齐全 |

**场景计数匹配检查**：设计文档共定义 6 个场景（1-5 自动化 + 6 手动 e2e）；本轮 Wave 1.5 自动化执行 5 个（场景 6 显式标注由用户手动验收），共 5 个 `执行:` 标记，对应自动化部分全覆盖。✅

#### Wave 2 — AI 双 Agent 审查

##### Tier 2a 设计符合性（design-reviewer Agent）
- **覆盖率**: 13/13 需求已实现（100%）
- **范围问题**: 无遗漏 / 无超出范围 / 无偏离
- **总结**: ✅ 设计符合 — 5 处改动 + 8 项验收标准 + 4 处版本同步全部对齐
- **关键验证**：通过 git diff 确认仅**新增** SessionStart 字段，原有 3 个 hook 字节级一致；脚本的 4 个分支逻辑（主仓库/已配/裸/失败）与设计 1:1 对应

##### Tier 2b 代码质量（code-quality-reviewer Agent）
- **统计**: 0 critical / 1 important / 0 minor
- **Strengths（Agent 列出 5 项）**:
  - L17/20/23/26/30: $CWD 全部双引号引用，set -e 与 || 组合处理正确
  - jq 与 stop-hook.sh 风格一致（macOS 内置 /usr/bin/jq 可用）
  - 测试清理完整（Promise.all + after()）
  - 幂等性严格：「.autopilot 必须是 symlink」防止 git checkout 覆盖后漏修复
  - CLAUDE_PLUGIN_ROOT 未定义时 node 调用失败被 || catch，安全降级

- **Important 问题（置信度 82）⚠️**:
  - 文件: `plugins/autopilot/hooks/hooks.json` SessionStart 配置
  - 问题: `"statusMessage": "检查 worktree 配置..."` 在主仓库 session（占绝大多数）也会闪现，但脚本毫秒级 silent exit，造成 UI 噪音
  - 对照: Stop hook（也每次触发）无 statusMessage；WorktreeCreate/Remove 有 statusMessage 因为操作本身耗时
  - 修复建议: 移除 SessionStart 的 statusMessage 字段（首次 worktree repair 进度已通过 stderr 的 `[autopilot] ...` 输出告知用户）
  - 性质: 不影响功能正确性，仅 UX 退化

- **Assessment**: Ready to merge: **Yes, with fix**

#### 结果判定

- **场景计数匹配**：✅（5 自动化 `执行:` 标记 + 1 显式标注手动 = 6 场景全覆盖）
- **格式检查**：✅（所有 Wave 1.5 场景均含 `执行:` 命令 + `输出:` 真实测试结果）
- **Wave 1/1.5/2 全部 ✅，无 ❌，1 个 ⚠️（statusMessage UI 噪音）**

→ `gate: "review-accept"`

#### 用户审批选项

- `/autopilot approve` 接受现状，进入 merge 阶段（statusMessage 警告可在后续 patch 升级中处理）
- `/autopilot revise 移除 SessionStart 的 statusMessage` 回到 implement 阶段做小改动后重跑 QA

## 变更日志
- [2026-05-06T01:09:01Z] 用户批准验收，进入合并阶段
- [2026-05-05T16:08:25Z] autopilot 初始化，目标: 基于 HANDOFF-worktree-sessionstart-fallback.md 里的方案，了解后直接接入 plan review 环节
- [2026-05-06T00:00:00Z] 知识上下文加载完成（index.md 含 worktree/session-isolation/symlink/defense-in-depth 等相关条目）
- [2026-05-06T00:00:00Z] 进入 Plan Mode，基于 HANDOFF 整合设计文档（核心思路 + 五处改动 + 范围控制 + 风险缓解 + 6 场景验证方案）
- [2026-05-06T00:00:00Z] plan-reviewer agent 审查通过：6/6 维度 PASS，0 BLOCKER；2 个重要问题已吸收（stdin 解析改用 jq、新增改动 5 更新 package.json test 列表）
- [2026-05-06T00:00:00Z] 用户审批通过 ExitPlanMode；设计文档和实现计划复制到状态文件，phase → implement
- [2026-05-06T01:00:00Z] 蓝红队并行启动：蓝队完成 5 处改动（bootstrap.sh + hooks.json + package.json + 2 个 README + 4 处版本号）；红队完成 acceptance test（9 case，ESM mock + CLAUDE_PLUGIN_ROOT 重定向策略）
- [2026-05-06T01:00:00Z] 合流验证 npm test：53 tests pass，0 fail（含原有 44 + 红队新增 9）；所有蓝队任务标 [x]，phase → qa
- [2026-05-06T02:00:00Z] QA Wave 1：ShellCheck exit 0，4 个 JSON 全合法，npm test 53/53 pass
- [2026-05-06T02:00:00Z] QA Wave 1.5：5 个真实场景独立执行（场景 1/2/3/4/5），全部 pass；场景 6 (e2e) 标注由用户手动验收
- [2026-05-06T02:00:00Z] QA Wave 2：design-reviewer 13/13 需求 100% 覆盖；code-quality-reviewer 0 critical / 1 important（statusMessage UI 噪音，置信度 82，⚠️ 不阻塞）
- [2026-05-06T02:00:00Z] QA 全部 ✅（1 ⚠️ 不阻塞），phase 不变 / gate → review-accept
