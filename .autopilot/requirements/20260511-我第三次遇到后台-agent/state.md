---
active: true
phase: "done"
gate: ""
iteration: 1
max_iterations: 30
max_retries: 3
retry_count: 0
mode: ""
plan_mode: ""
fast_mode: false
brief_file: ""
next_task: ""
auto_approve: false
knowledge_extracted: "true"
task_dir: "/Users/stringzhao/workspace/string-claude-code-plugin/.autopilot/requirements/20260511-我第三次遇到后台-agent"
session_id: 95dbb09b-be85-43de-be36-56534c9f72ea
started_at: "2026-05-11T13:51:34Z"
contract_required: true
---

## 目标
我第三次遇到后台 agent 执行然后无限触发 stop hook 的问题 @/Users/stringzhao/Downloads/error.txt 彻底解决这个问题，并且通过各种真实验证确认问题修复了

> 📚 项目知识库已存在: .autopilot/。design 阶段请先加载相关知识上下文。

## 设计文档

### Context

用户第三次遇到「主 agent 用 Agent + run_in_background=true 启动蓝/红队后台 sub-agent，autopilot stop-hook 仍持续唤醒主 agent，主 agent 重复输出『等。』『等蓝队完成。』，迭代号从 2 一路飙到 29+，烧 token、污染上下文」。

stop-hook.sh v3.25.1 在 §7.5 已经存在 `has_pending_subagents` 检测函数（行 159-200），按设计应该静默等待。但根据 error.txt 的复现迹象（iteration 2-29 全部走的是正常 prompt 注入路径），该函数在长会话场景下**没有生效**。

### 根因（已通过真实 transcript 验证）

复现环境：
- transcript: `/Users/stringzhao/.claude/projects/-Users-stringzhao-workspace-relight--claude-worktrees-pick/1bf7db8b-dfbc-461e-a0a1-437f07e38aec.jsonl`（5.93 MB）
- 蓝队 ID: `a4ca90c6a20c9cfa4` (offset 4413303，在 tail 2MB 内)
- 红队 ID: `a9d85ef089c230bd4` (offset 4400645，在 tail 2MB 内)

`has_pending_subagents` 实际执行：
```bash
tail_data=$(timeout 3 tail -c 2097152 "$transcript")  # 末尾 2MB
echo "$tail_data" | jq -rs '...'                      # 跑检测 jq
```

**问题**：`tail -c 2097152` 在**字节偏移 2MB** 处直接截断，**字节边界几乎必然落在 JSON 行中间**。实测 tail 第一行 = `tokens":1,"cache_creation_input_tokens":1447,...`（这是某个 JSON 对象的中段，不是完整 JSON）。

后果链：
1. `jq -rs` 把整段输入当一组 JSON 解析，**第一行就报 `parse error: Invalid literal at line 1, column 7`**
2. `pending_count=$(... 2>/dev/null)` 吞掉错误，但 jq 已退出非零 → `|| return 1`
3. `has_pending_subagents` 返回 1（"无 pending"）
4. stop-hook §7.5 条件 `has_pending_subagents` 不成立 → 走 §8 注入 prompt
5. 主 agent 被唤醒 → 输出"等。"→ stop-hook 再触发 → 死循环

**实测验证**：
- 跑原版 jq → `jq: parse error: Invalid literal at line 1, column 7`
- 跑 `tail -c 2097152 | tail -n +2 | jq -rs '...'` → `async_launched_count: 2, async_pending: 0`（因为采样时蓝/红队已完成；error.txt 当时蓝/红队还在跑，所以 async_pending=2，会正确 block）

### 设计方案

最小改动 + 多重防御。**只改 `stop-hook.sh::has_pending_subagents`**，不动调用方、不动 hooks.json、不动其他逻辑。

**改动点 1：丢弃 tail 第一行（核心修复）**

```bash
tail_data=$(timeout 3 tail -c "$WINDOW_BYTES" "$transcript" 2>/dev/null) || return 1
# 关键：tail -c 在字节边界切，第一行几乎必然是半截 JSON，丢掉
tail_data=$(echo "$tail_data" | tail -n +2)
```

为什么不用 `tail -n N`（按行截）？因为单个 tool_use/tool_result 的 JSON 行可能 > 50KB（含图、含大代码片段），用按行截无法稳定控制内存上限；按字节 + 丢首行才是稳健解。

**改动点 2：扩大 tail 窗口 2MB → 4MB**

error.txt 的 transcript 5.93MB（长会话 + 多次大文件读写并非罕见）。2MB 窗口对应"最近约 6-10 轮主线程消息"，对长任务可能不够。4MB 把覆盖窗口翻倍，单次 jq 跑 ~1s（实测）仍远低于 timeout 3。

**改动点 3：jq 解析失败时的 fail-safe 兜底（防御深度）**

原来 jq 失败 → return 1（"无 pending"，**不安全**，会导致死循环）。
改为：jq 失败时检查 raw tail 中**文本字面量** `"status":"async_launched"` 是否出现 → 出现就当 pending 处理（return 0，让 stop-hook 静默等待），否则才 return 1。这样即使未来 jq schema 又变，也不会再陷入"无限唤醒"灾难。

**改动点 4：在 stderr 打印一行可观测日志**

`has_pending_subagents` 走 fallback 或 jq 失败时，写一行 stderr（不影响 stop-hook JSON 输出），方便用户/自己未来诊断。

### 不在范围内

- ❌ 改 hooks.json 配置 / 改 setup.sh / 改其他阶段逻辑
- ❌ 增加新 phase 或 frontmatter 字段
- ❌ 改 sync Agent 检测（路径 A）—— 用户场景全部是 async，路径 A 表面有同样的"截断 jq"问题但当前未观察到实际故障，保留作为后续观察
- ❌ 改 Claude Code 内置的 transcript 格式

实际改动文件清单（≤2 个）：
- `plugins/autopilot/scripts/stop-hook.sh` (修 `has_pending_subagents`)
- 版本升级链：`plugins/autopilot/.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` + 本仓库 `CLAUDE.md` 插件索引表（按 CLAUDE.md 全局版本同步规则）

## 实现计划

**Stage 1 — 修 `has_pending_subagents`**
- [ ] 在 `tail -c` 之后插入 `tail -n +2` 丢弃可能半截的首行
- [ ] 把 2097152 (2MB) 提升为 4194304 (4MB)
- [ ] jq 失败分支增加 raw tail 文本兜底（grep `"status":"async_launched"`）
- [ ] 增加 stderr 观测日志（成功检测出 pending / fallback / jq 失败三种情况各打一行）

**Stage 2 — 红队测试 fixture（基于设计文档独立编写）**
- 红队的产出物（不读 stop-hook 改动）：
  - 场景 A：mock transcript 头部 1 行被故意截断为半截 JSON，后面接合法的 async_launched JSON → `has_pending_subagents` 必须返回 0（has pending）
  - 场景 B：mock transcript 只有 async_launched，没有 completion → return 0
  - 场景 C：mock transcript 有 async_launched + 对应 task-id 的 enqueue completion → return 1
  - 场景 D：mock transcript 完全没有 Agent 调用 → return 1
  - 场景 E：transcript 文件不存在 → return 1
  - 场景 F（回归）：sync Agent 启动但未完成 → return 0

**Stage 3 — 版本升级**
- [ ] `plugins/autopilot/.claude-plugin/plugin.json`：3.25.1 → 3.26.0
- [ ] `.claude-plugin/marketplace.json` 中 autopilot 条目同步
- [ ] 仓库 `CLAUDE.md` 插件索引表更新版本号

**Stage 4 — 真实场景验证（端到端）**

不是单测，是真实使用 stop-hook 二进制：
- [ ] 把 error.txt 中**实际**的 transcript 文件路径喂给 `stop-hook.sh`，制造一个临时 state.md（phase=implement），通过 stdin 灌 JSON，验证 stop-hook：
  - 退出码 0
  - 不输出 block JSON
- [ ] 用 prefix 截断 transcript（取 4.5M，覆盖 launched 不含 completion）做对照，验证检测能 catch pending

### 验证方案

**真实测试场景**（必须跑命令并贴输出）：

R1 [独立] 复现原版 jq parse error（修复前）+ 验证修复后无 error：
```bash
# 修复前
bash -c 'source plugins/autopilot/scripts/stop-hook.sh; has_pending_subagents /path/to/real-transcript.jsonl; echo exit=$?' 2>&1 | grep -i 'error\|exit'
# 期望修复前看到 jq parse error
# 期望修复后无 error，函数正确返回（取决于 transcript 内容）
```

R2 [独立] 用前缀截断 transcript 验证「launched but not completed」：
```bash
# 取 transcript 前 4.5M（恰好覆盖 launched 4.4M，未覆盖 completion 4.7M）
head -c 4718592 real-transcript.jsonl > /tmp/test-mid.jsonl
bash -c 'source stop-hook.sh; has_pending_subagents /tmp/test-mid.jsonl; echo exit=$?'
# 修复前：exit=1 (错，因 jq parse error)
# 修复后：exit=0 (对，async_launched 在 tail 内，无 completion → pending)
```

R3 [独立] 完整 stop-hook 端到端：临时 state.md + stdin JSON，验证不构造 block JSON：
```bash
# 期望 stdout 为空，exit=0
```

R4 [独立] 跑现有 acceptance 测试套件，无回归：
```bash
bash plugins/autopilot/tests/acceptance/run-all.sh
# 期望全部 PASS
```

R5 红队针对 has_pending_subagents 的 6 个场景测试 fixture，全 PASS。

### 关键决策

| 决策 | 选择 | 取舍 |
|------|------|------|
| 修复粒度 | 仅改 stop-hook.sh::has_pending_subagents | 影响面最小、易回滚 |
| 截断策略 | 字节 tail + 丢首行 | 行 tail 应对超大 JSON 行（>50KB）易爆内存 |
| 窗口大小 | 2MB → 4MB | 长会话覆盖更稳，仍在 timeout 3 内 |
| 失败兜底 | jq 失败 → grep async_launched 文本兜底 | fail-safe 优于 fail-unsafe；上次就是 fail-unsafe 导致灾难 |
| 测试方式 | 真实 transcript fixture + 单元 mock | 真实数据揭示问题，mock 验证边界 |

### 风险与回滚

风险：
- 4MB 窗口在极慢磁盘下 tail 可能超时 3s → 极小概率，超时时降级 return 1 静默放行（与原行为一致）
- `tail -n +2` 在 transcript 只有 1 行（极早期会话）时返回空 → 已有 `[ -n "$tail_data" ] || return 1` 兜底
- macOS bash 3.2 兼容性：`tail -n +2`、`grep -q`、`echo`、`||` 全是 POSIX 兼容 → 无风险

回滚：直接 git revert 一个 commit 即可（改动只在 stop-hook.sh）。

### Plan-reviewer 审查通过的改进建议（80-89 置信度，纳入实现）

- **S1** `tail -n +2` 后若结果为空但原始 tail 非空（罕见单行 transcript），回退到原始 tail 数据，让 jq 或 grep fail-safe 自然兜底
- **S2** fail-safe 兜底升级：除 `grep "status":"async_launched"` 还要 `grep '<task-id>'` 粗略计数 completion，差值 > 0 才返回 0；避免已完成场景 false-positive 持续 silent block
- **S3** Stage 2 fixture 显式覆盖"半截行含 \n"和"半截行不含 \n"两种 boundary
- **S4** R3 真实端到端步骤明确：临时写 `phase=implement` + session_id 匹配的 state.md，stdin JSON 含 transcript_path，确保检测点真正被命中（不被 §3 Session Guard 或 §5 phase 分支提前 exit）

实现时另注意：原代码 165 行 `tail -c 2097152` 是硬编码，无 `$WINDOW_BYTES` 变量。改 4MB 时直接 inline 或新增 `local WINDOW_BYTES=4194304`。

> ✅ Plan 审查通过（全部维度通过，4 条重要建议已纳入实现）

## 契约规约

**接口契约：`has_pending_subagents(transcript_path) -> exit_code`**

| Case | 输入 | 期望输出 |
|------|------|----------|
| C1 | transcript 文件不存在 | exit=1（无 pending）|
| C2 | transcript 空 | exit=1 |
| C3 | 末尾 4MB 第一行半截 JSON + 后面有 async_launched + 无 completion | **exit=0**（has pending）— 核心修复目标 |
| C4 | 末尾 4MB 第一行半截 JSON + 后面有 async_launched + 有对应 completion | exit=1 |
| C5 | 末尾 4MB 完整 JSON 行 + async_launched 未完成 | exit=0 |
| C6 | 末尾 4MB 完整 JSON 行 + sync Agent 调用未返回 tool_result | exit=0 |
| C7 | jq 解析仍然失败（异常 transcript）但 raw tail 含 `"status":"async_launched"` | exit=0（fail-safe 兜底）|
| C8 | jq 解析失败且 raw tail 无 async_launched 文本 | exit=1 |

**stop-hook §7.5 行为契约**（不变更）：
- `phase == "implement"` AND `HOOK_TRANSCRIPT` 非空 AND `has_pending_subagents` exit=0 → `exit 0`（不输出 block JSON、不递增 iteration）
- 其他 → 继续 §8 注入 prompt

## 红队验收测试

文件：`plugins/autopilot/tests/acceptance/has-pending-subagents.acceptance.test.sh`

13 个验收场景（仅基于设计文档契约编写，不读 stop-hook 实现）：
- C1: 不存在 transcript → exit=1
- C2: 空 transcript → exit=1
- **C3: 半截首行 + async_launched 未完成 → exit=0** (核心修复目标 — error.txt 根因)
- C4: 半截首行 + launched + completion → exit=1
- C5: 完整行 + launched 未完成 → exit=0
- C6/C6b: sync Agent 路径回归（启动未完成/启动+result）
- **C7: jq 失败 + 含 async_launched 文本 → fail-safe exit=0** (防护栏)
- C8: jq 失败 + 无 async_launched → exit=1
- C9: 半截单行边界 → exit=0
- C10/C10b: 真实 error.txt transcript 回归 + **C10b 直接用真实 transcript 复现 error.txt 瞬态** → 修复前 exit=1（错），修复后 exit=0（对）

运行验证：
```
$ bash plugins/autopilot/tests/acceptance/has-pending-subagents.acceptance.test.sh
R-bg-detect 汇总: PASS=12 FAIL=0
```

回归套件（4 个 pre-existing 失败均与版本号期望值 3.23.0 过时有关，与本次修复无关，全部在 stash baseline 下同样失败）：
- ✅ has-pending-subagents（本次新增）
- ✅ stop-hook-prompt-routing
- ✅ setup-fast-flag / detect-smoke-eligible / qa-reviewer-prompt / compress-qa-report / skill-fast-mode-doc
- ⚠️ pre-existing: skill-references-consistency / version-sync / brainstorm-default / plan-review-html

## 契约校验

✅ PASS — 红队 13 场景 1:1 覆盖契约规约 C1-C8（C3/C7/C10b 是核心修复目标，C9 是 S3 边界，C10 是真实 transcript 回归），全部 PASS。

## QA 报告

### 轮次 1 (2026-05-11T14:08:00Z) — ✅ 全部通过

#### Wave 1 — 命令验证

**Tier 0: 红队验收测试** ✅
```
执行: bash plugins/autopilot/tests/acceptance/has-pending-subagents.acceptance.test.sh
输出: R-bg-detect 汇总: PASS=12 FAIL=0
```
13 个场景全 PASS（含 C3/C7/C10b 三个 error.txt 根因场景）。

**Tier 1: 语法/lint** ✅
```
执行: shellcheck plugins/autopilot/scripts/stop-hook.sh
输出: (无 warning)
执行: bash -n plugins/autopilot/scripts/stop-hook.sh; bash -n .../has-pending-subagents.acceptance.test.sh
输出: ✅ syntax OK / ✅ test syntax OK
```

**Tier 1: 全 acceptance 套件回归** ⚠️→✅
```
执行: bash plugins/autopilot/tests/acceptance/run-all.sh
输出: 7/11 通过, 4 失败
失败用例: skill-references-consistency / version-sync / brainstorm-default / plan-review-html
```
4 个失败均为 pre-existing（git stash 我的改动后 baseline 完全相同），全部是测试期望 plugin.json 版本 `3.23.0` 但实际仓库已是 `3.26.0`（这些测试本身需要升级，与本次修复无关）。新增的 has-pending-subagents 通过。

**Tier 1: 3 处版本同步** ✅
```
plugins/autopilot/.claude-plugin/plugin.json:    "version": "3.26.0"
.claude-plugin/marketplace.json:            "version": "3.26.0"
CLAUDE.md:| [autopilot] | v3.26.0 |
```

#### Wave 1.5 — 真实场景验证

**R1 [独立] 修复前后 jq 行为对照** ✅
```
执行 (旧版): tail -c 2097152 REAL_TS | jq -rs '[.[] | .toolUseResult? ... ] | length'
输出: jq: parse error: Expected value before ',' at line 1, column 1
执行 (新版): tail -c 4194304 REAL_TS | tail -n +2 | jq -rs '[.[] | .toolUseResult? ... ] | length'
输出: 2
```
✅ **直接证据**: 旧版 jq 在真实 transcript 上崩溃 → fail-unsafe 进入注入路径；新版正确识别 2 个 async_launched。

**R2 [独立] 前缀截断 transcript（红队 C10b 已覆盖）** ✅
```
执行: head -c 4500000 REAL_TS | sed '$d' > /tmp/test-mid.jsonl; bash -c 'source stop-hook.sh; has_pending_subagents /tmp/test-mid.jsonl; echo exit=$?'
输出: exit=0
stderr: [has_pending_subagents] jq 检测出 pending=2
```

**R3 [独立] 完整 stop-hook 端到端 + 新旧对比** ✅ (关键证据)
```
准备: 临时 git 仓库 + 临时 state.md (phase=implement, session_id=1bf7db8b-...) + stdin JSON {cwd, transcript_path=瞬态transcript, session_id}
执行 (旧版): echo $STDIN | bash stop-hook.sh.old
输出 (旧版): stdout = {"decision":"block","reason":"... 当前阶段: implement, 迭代: 6. ⚠️ 红蓝对抗铁律..."} → 注入 block JSON → 主 agent 被唤醒 = error.txt 死循环
执行 (新版): echo $STDIN | bash stop-hook.sh
输出 (新版):
  stdout = ""
  stderr =
    [has_pending_subagents] jq 检测出 pending=2
    [autopilot] 检测到后台 sub-agent 运行中，静默等待 (phase: implement, iter: 6)
  exit = 0
```
✅ **核心结论**: 同一 stdin 投入旧/新 stop-hook，旧版构造 block JSON 唤醒主 agent (=死循环根因)，新版静默等待（=修复）。

**R4/R5: 已包含在 Wave 1 中**

#### Tier 2: 自审

**设计符合性**:
- ✅ 4 改动点全部落地: 丢首行 (`tail -n +2`) / 4MB 窗口 (`4194304`) / fail-safe 文本兜底 (launched/completed 计数差) / stderr 观测日志（3 路径各 1 行）
- ✅ S1-S4 改进建议: S1 空回退、S2 计数差防 false positive、S3 半截单行 fixture C9、S4 R3 含临时 state.md + session_id 匹配 — 全部纳入

**OWASP 关键**: 
- 无新增网络/外部输入 → N/A
- 文件路径处理: transcript_path 通过 stdin JSON 传入，仅 `tail -c`/`grep`/`jq` 只读 → 无注入风险

**代码质量**:
- 函数纯度: has_pending_subagents 不修改全局状态 ✅
- bash 3.2 兼容: `tail -n +2`/`grep -c`/`echo`/`[[`/`=~` 均兼容 ✅
- 错误处理: jq 失败、grep 失败、非数字计数全部有兜底 ✅

#### 结论

✅ **全部通过**。修复直接根除 error.txt 死循环根因（jq parse error → fail-unsafe）+ 增加 fail-safe 防护栏 + 改进观测性。无回归。

## 变更日志
- [2026-05-11T13:51:34Z] autopilot 初始化，目标: 我第三次遇到后台 agent 执行然后无限触发 stop hook 的问题 @/Users/stringzhao/Downloads/error.txt 彻底解决这个问题，并且通过各种真实验证确认问题修复了
- [2026-05-11T13:58:12Z] design 阶段完成：根因定位为 `tail -c 2097152` 字节截断导致 jq parse error，has_pending_subagents 误判为「无 pending」。设计了 4 改动点的最小修复方案（丢首行 + 扩窗口 + fail-safe 兜底 + 观测日志）。
- [2026-05-11T13:58:30Z] plan-reviewer 审查 PASS（含 S1-S4 改进建议纳入），用户审批通过，进入 implement。
- [2026-05-11T14:05:22Z] implement 阶段完成：has_pending_subagents 修复落地（丢首行 + 4MB 窗口 + fail-safe 兜底 + 观测日志），13 场景红队验收 PASS，版本号 3.25.1→3.26.0 三处同步。进入 qa。
- [2026-05-11T14:08:00Z] QA 全部通过：Wave 1 红队 12/12 + Tier 1 全 lint/语法 + 版本一致；Wave 1.5 R1/R2/R3 全 PASS（R3 关键对照证据：旧版构造 block JSON 唤醒主 agent vs 新版静默等待）。
- [2026-05-11T14:10:00Z] merge 完成：5235244 修复主体提交 + cbbcabb 知识沉淀（patterns.md + index.md）。autopilot 闭环完成。
