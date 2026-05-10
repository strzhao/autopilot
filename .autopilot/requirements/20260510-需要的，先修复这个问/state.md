---
active: true
phase: "done"
gate: ""
iteration: 6
max_iterations: 30
max_retries: 3
retry_count: 2
mode: ""
plan_mode: ""
fast_mode: false
brief_file: ""
next_task: ""
auto_approve: false
knowledge_extracted: "true"
qa_scope: ""
task_dir: "/Users/stringzhao/workspace/string-claude-code-plugin/.autopilot/requirements/20260510-需要的，先修复这个问"
session_id: eb1ae0d9-b2c1-4b9f-ab22-3992547fa5e6
started_at: "2026-05-10T01:52:03Z"
contract_required: true
---

## 目标
需要的，先修复这个问题，然后 🔴 P0：doctor 对 worktree 是"门口检查"，不进屋 这个问题也一起解决掉，这个很重要

> 📚 项目知识库已存在: .autopilot/。design 阶段请先加载相关知识上下文。

## 设计文档

### Context

修复 autopilot worktree 工具的两个真实问题：

**P0-1: tracked-dir 残留 symlink 自愈缺失**
- 位置：`plugins/autopilot/scripts/worktree.mjs:195-199`，`ensureSelectiveAutopilotLayout()` 函数内
- 现状：`trackedKind === 'dir'` 时只 `continue` 跳过新建 symlink，**不清理已存在的旧 symlink**
- 触发链：worktree 创建时 main 的 `.autopilot/requirements/` 还 untracked → 正常建 symlink → 之后 main commit 该目录变 tracked-dir → 残留 symlink → worktree 内 `git commit` / `lint-staged stash` 报 "is beyond a symbolic link"
- 实证：当前主仓库 `git ls-files .autopilot/` 显示 `requirements/` 已是 tracked-dir，任何早期 worktree 都会触发该问题
- 关联知识：[2026-03-25] 符号链接检测 ≠ worktree 检测，防御需多层（patterns.md）；[2026-05-04] Per-worktree 会话隔离（decisions.md）

**P0-2: doctor 对 worktree 是"门口检查"，不进屋**
- 位置：`plugins/autopilot/skills/autopilot-doctor/SKILL.md:175-198`，Dim 8 (Git 工作流)
- 现状：检查脚本只跑 `cat .autopilot/worktree-links` + `git worktree list`，不进入每个 worktree 检查它是否健康
- 漏掉的信号：broken symlink、缺 `node_modules`、缺 `local-config.json`、缺关键 SHARED 项
- 影响：用户在主仓库跑 `/autopilot doctor` 拿到高分，进 worktree 一脸懵
- 关联知识：[2026-05-05] Lint/健康检查能力优先 AI 语义判断而非正则脚本（decisions.md）——意味着 doctor 健康抽查应**输出原始信号**给 AI，而不是用 shell 计算分数

### 设计方案

#### 改动 1：worktree.mjs ensureSelectiveAutopilotLayout 增加残留 symlink 清理

把 `trackedKind === 'dir'` 分支从"仅 continue"扩展为"按 LEGACY_SHARED_AUTOPILOT_ITEMS 同款逻辑清理"：

```js
if (trackedKind === 'dir') {
  // 检查 dst 是否已是残留 symlink（worktree 创建时 main 还 untracked，
  // 之后 main 把它升级为 tracked-dir，导致 symlink 残留 → git commit 报
  // "is beyond a symbolic link"）。残留则 unlink + git checkout 恢复真实目录。
  let s = null;
  try { s = lstatSync(dst); } catch { /* not exists */ }
  if (s?.isSymbolicLink()) {
    log(`→ .autopilot/${item} 在主仓库已变 tracked 目录，清理残留 symlink`);
    unlinkSync(dst);
    try {
      gitSilent('-C', worktreePath, 'checkout', 'HEAD', '--', `.autopilot/${item}`);
      log(`   ✓ 从 git 恢复 .autopilot/${item}（真实目录）`);
    } catch (e) {
      log(`   ⚠ git checkout 失败 (${e.message})；如需要请手动恢复`);
    }
  } else {
    log(`   ⚠ .autopilot/${item} 在主仓库是 tracked 目录，跳过 symlink（git 不支持 tracked 路径穿过 symlink）`);
  }
  continue;
}
```

**与 LEGACY 路径的关系**：LEGACY_SHARED_AUTOPILOT_ITEMS（如 `'project'`）处理"曾在 SHARED 但已移除"的项；本次改动处理"仍在 SHARED 但 main 跟踪状态变化"的项。两者互补，逻辑核心一致（unlink + git checkout）。

#### 改动 2：doctor SKILL Dim 8 加 worktree 健康抽查

按 [2026-05-05] 决策——给 AI 输出**原始信号**，不在 shell 算分。在 Dim 8 检查脚本末尾追加：

```bash
# === worktree 健康抽查（v3.25+，输出原始信号供 AI 判断）===
echo "--- worktree health ---"
MAIN_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
git worktree list --porcelain 2>/dev/null | awk '/^worktree / {print $2}' | while read -r wt; do
  [ "$wt" = "$MAIN_ROOT" ] && continue  # 跳过主仓库自身
  echo "[worktree: $wt]"
  # 1. broken symlink in .autopilot/
  if [ -d "$wt/.autopilot" ]; then
    find "$wt/.autopilot" -maxdepth 1 -type l 2>/dev/null | while read -r link; do
      [ ! -e "$link" ] && echo "  broken-symlink: $(basename "$link")"
    done
  else
    echo "  missing: .autopilot/"
  fi
  # 2. node_modules（仅 Node 项目）
  [ -f "$wt/package.json" ] && [ ! -d "$wt/node_modules" ] && echo "  missing: node_modules"
  # 3. local-config.json（dev 端口）
  [ ! -f "$wt/local-config.json" ] && echo "  missing: local-config.json"
done
```

同步在评分指引下方追加段落：

> **worktree 健康抽查解读**：检查输出含 `broken-symlink` / `missing:` 时，**不直接扣分**，而是在改进建议中列出具体 worktree 路径并建议 `cd <wt> && /worktree-repair`。worktree 抽查为空（无 worktree 或全 PASS）→ 不影响 Dim 8 评分。

**为什么不调权重**：worktree 健康是"后置维护问题"，与 Dim 8 主项（pre-commit/lint-staged/.env.example）正交；继续用同一权重避免破坏校准。

### 范围控制（明确不做）

- ❌ 不调整 `SHARED_AUTOPILOT_ITEMS` 列表（`active` 该不该删是独立决策，留下次）
- ❌ 不改 doctor 评分权重表（不破坏现有校准）
- ❌ 不重写 worktree-repair SKILL.md frontmatter
- ❌ 不在 autopilot 主 SKILL.md 加"何时推荐 /worktree-repair"（属于 P0-3 范围，单独规划）

### 契约规约

#### worktree.mjs

| 项 | 输入 | 输出 |
|---|---|---|
| `ensureSelectiveAutopilotLayout(mainRoot, worktreePath)` | 字符串路径 | void；幂等；stderr log；不抛错 |
| 行为不变项 | trackedKind=='untracked'/'file' 路径 | 与 v3.24.0 完全一致 |
| 行为新增项 | trackedKind=='dir' && dst 是 symlink | unlink + `git -C worktreePath checkout HEAD -- .autopilot/<item>` |
| 行为新增项 | trackedKind=='dir' && dst 不存在/真实目录 | 仅 log，continue |
| 错误处理 | git checkout 失败 | 捕获、log warning、不抛错 |

#### doctor SKILL Dim 8

| 项 | 契约 |
|---|---|
| 检查脚本退出码 | 0（即使 worktree 抽查发现问题） |
| 主仓库自身处理 | `git worktree list --porcelain` 第一项跳过 |
| 无 worktree 场景 | 输出 `--- worktree health ---` 头但无后续行 |
| 评分权重 | 不调整 SKILL.md 的权重表（无论 L173 标题"8%"还是 L418 表"0.07"都不动；两处不一致是历史 bug，本次不修） |
| AI 解读规则 | broken-symlink / missing: 写入改进建议，不直接扣分 |

#### npm test

- 现有 76 用例必须全部通过（不破坏 worktree.acceptance.test.mjs / worktree-bootstrap.acceptance.test.mjs）
- 新增红队验收测试加入 npm test 脚本

### 验收场景（来自 scenario-generator）

1. **[高] worktree 残留 symlink 自愈**：main untracked → 创 worktree → main 提交该目录 → worktree 内 repair → symlink 变真实目录、git commit OK
2. **[高] 尚未 tracked 时不破坏现有 symlink**：main 仍 untracked → repair → symlink 保持
3. **[中] worktree 切到无 requirements 的旧分支**：repair 不凭空创建、不报错
4. **[中] 用户已 stash 未提交改动**：repair 不动 stash
5. **[高] doctor 抽查健康 worktree**：2 个健康 worktree → 报告标 PASS、不扣分
6. **[高] doctor 检出 broken worktree**：broken symlink + 缺 node_modules → 报告精确指出问题 + 建议 /worktree-repair
7. **[中] doctor 在主仓库自身运行**：无 worktree → 输出 health 头但无后续、不报错
8. **[中] doctor 在 worktree 内运行**：能正确识别当前 worktree

## 实现计划

### 任务 1: 修改 worktree.mjs ensureSelectiveAutopilotLayout

- 文件：`plugins/autopilot/scripts/worktree.mjs`
- 改动行：L195-199（替换 9 行 → ~20 行）
- 关键：`unlinkSync` + `gitSilent('-C', worktreePath, 'checkout', 'HEAD', '--', ...)` 与 L177-184 LEGACY 路径同构
- [ ] 替换分支逻辑
- [ ] 验证主路径仍走原逻辑（trackedKind ≠ 'dir' 时不变）

### 任务 2: 红队为 worktree.mjs 写新单元测试

- 文件：`plugins/autopilot/scripts/worktree.acceptance.test.mjs`（追加而非重写）
- 新增 describe('ensureSelectiveAutopilotLayout — tracked-dir 残留清理', ...)
- 测试用例（最少 4 个）：
  - case A: dst 是 symlink + main tracked-dir + main HEAD 含该目录 → unlink + git checkout 成功 → dst 变真实目录含 main HEAD 内容
  - case B: dst 是 symlink + main tracked-dir + worktree HEAD 不含该路径（旧分支）→ unlink + git checkout 失败被 catch + log warning → **dst 不存在（可接受结果）**，repair 整体仍 exit 0
  - case C: dst 不存在 + main tracked-dir → 仅 log，不调 unlink，不抛错
  - case D: dst 是真实目录 + main tracked-dir → 仅 log，不调 unlink，保持原状
- [ ] 测试用 mkdtemp + git init + 真实 git worktree 模拟（已有同套基础设施可参考）

### 任务 3: 修改 doctor SKILL.md Dim 8

- 文件：`plugins/autopilot/skills/autopilot-doctor/SKILL.md`
- 改动行：L175-198 区域追加（不替换原有检查脚本）
- [ ] 在 ``` 内追加 worktree 健康抽查 bash 段
- [ ] 评分标准表下方追加"worktree 健康抽查解读"段

### 任务 4: 跑全量 npm test 验证

- [ ] `npm test` → 所有现有 76 + 新增用例必须 PASS

### 任务 5: 手动验收（场景 1 + 5 + 6 + 7 + 8）

**场景 1 实证（worktree.mjs 改动）**：
```
cd /tmp && rm -rf wt-test && mkdir wt-test && cd wt-test && git init
echo "test" > a.md && git add a.md && git commit -m init
mkdir -p .autopilot && touch .autopilot/decisions.md && git add . && git commit -m '+autopilot'
git worktree add wt-1 -b wt-1
ln -s ../../.autopilot/requirements wt-1/.autopilot/requirements
mkdir -p .autopilot/requirements && touch .autopilot/requirements/spec.md
git add . && git commit -m '+req'
cd wt-1 && git status  # 期望：报 "beyond a symbolic link"
node /path/to/worktree.mjs repair "$(pwd)"
ls -la .autopilot/requirements  # 期望：真实目录
git status  # 期望：clean
```

**场景 5/6/7/8 实证（doctor 脚本段）**：将 SKILL.md 新加的 worktree 健康抽查 bash 段抽出来用 `bash -x` 独立执行验证：

- **场景 5（健康 worktree）**：build 2 个健康 worktree（symlink + node_modules + local-config.json 全在），跑脚本段 → stdout 应只有 `[worktree: ...]` 头无 `broken-symlink` / `missing:` 行
- **场景 6（broken worktree）**：构造 broken symlink + 删 node_modules，跑脚本段 → stdout 应含 `broken-symlink: <basename>` 和 `missing: node_modules`
- **场景 7（无 worktree）**：在 `git init` 的裸仓库（无 worktree add）跑脚本段 → 仅输出 `--- worktree health ---` 头无后续
- **场景 8（在 worktree 内运行）**：cd 进 worktree-A 跑脚本段 → MAIN_ROOT 应正确解析到主仓库，所有 worktree（含自身）被遍历不重复

**断言记录**：每个场景执行命令 + 实际 stdout 写入 QA 报告，对照期望逐项 ✅/❌

### 任务 6: 智能提交

- 走 autopilot-commit Agent
- 升级版本到 v3.25.0（新功能：tracked-dir 残留 symlink 自愈 + doctor worktree 健康抽查）

### 红队/蓝队信息隔离

- 蓝队负责任务 1、3
- 红队负责任务 2（仅看本设计文档的契约规约 + 验收场景，不读 worktree.mjs 实际改动）

## 红队验收测试

**新增 describe 块**：`ensureSelectiveAutopilotLayout — tracked-dir 残留清理`

文件：`plugins/autopilot/scripts/worktree.acceptance.test.mjs`（追加，不重写）

测试用例：
- ✅ case A: 残留 symlink 被替换为真实目录（worktree HEAD 含该路径）
- ✅ case B: worktree 旧分支不含 requirements — symlink 被清理（dst 不存在），函数不抛错
- ✅ case C: dst 不存在时函数不报错，不创建 symlink
- ✅ case D: dst 已是真实目录时函数不报错，目录内容不变

**导出验证**：`ensureSelectiveAutopilotLayout` 已在 worktree.mjs:134 用 `export function` 导出，红队 import 成功。

**自检**：每个 case 都有强断言（`assert.ok` / `assert.equal`），无 soft skip / try-catch 吞断言。

**全量回归**：`npm test` → 80 pass / 0 fail（76 旧 + 4 新）。

## 契约校验

**第 1 轮（2026-05-10T02:42:00Z）**：

contract-checker Agent 输出（model: sonnet）：
- pass: false
- mismatches:
  1. **[high] boundary**: 契约说"评分权重 不变（8%）"，SKILL.md L418 表里写 0.07，L173 标题写 8% — `plugins/autopilot/skills/autopilot-doctor/SKILL.md:418`
  2. **[medium] route**: 契约说"主仓库自身处理：第一项跳过"，实现按路径比对 `[ "$wt" = "$MAIN_ROOT" ] && continue`（功能等价但表述不同） — `plugins/autopilot/skills/autopilot-doctor/SKILL.md:192`

**编排器决策（不打回 implement）**：

1. **mismatch 1 是契约描述歧义，不是实现 bug**：SKILL.md L173 vs L418 的权重不一致是历史多处不同步 bug（在我本次改动之前就存在）。契约里"不变（8%）"的真实意图是"不动权重表"，不是"权重应该是 8%"。**已修正契约表述**为"不调整权重表"。
2. **mismatch 2 medium**：表述不同但功能等价。`第一项跳过`是契约口语化描述，实现用路径比对更稳健（即使 worktree list 顺序变化也对）。**接受，不阻断**。
3. **附加发现写入知识库**：SKILL.md 中至少 4 个 Dim（L173/280/328 vs L415/416/418/420）存在"标题权重 % vs 表里小数"的多处不一致，建议下次专项修复（关联 [2026-03-21] 多处引用同步 pattern）。

**结论**：✅ PASS（修正契约描述后），phase 前进到 qa。

## QA 报告

### 轮次 1（2026-05-10T02:50:00Z）— ❌ 2 个 Tier 1.5 失败 + 1 个 Tier 2 重要问题，phase → auto-fix

#### 变更分析
- 改动文件：worktree.mjs（21 行）+ worktree.acceptance.test.mjs（追加 4 case ~280 行）+ doctor SKILL.md（追加 16 行 bash + 1 段说明）
- 影响：低-中（worktree.mjs 是 hook 关键路径；SKILL.md 是 doctor 指引文档）
- 工具栈：node --test、shellcheck

#### Wave 1（命令执行）

**Tier 0+1: npm test**
- 执行: `npm test`
- 输出: `# tests 80 / # pass 80 / # fail 0 / duration 1017ms`
- 状态: ✅

**Tier 1: shellcheck**
- 执行: `find plugins -name '*.sh' -exec shellcheck {} +`
- 输出: `exit=0`，1 个 SC1003 info（lib.sh:106 非本次改动），不阻断
- 状态: ✅

无 tsc / build / E2E（项目无对应配置）。

#### Wave 1.5（真实测试场景，5 个，全部执行）

**场景 1 — worktree 残留 symlink 自愈** [高]
- 执行: 构造 main 先 commit `.autopilot/requirements/spec.md`，再创 worktree、手动建 symlink → `node worktree.mjs repair`
- 输出: 
  ```
  → .autopilot/requirements 在主仓库已变 tracked 目录，清理残留 symlink
     ✓ 从 git 恢复 .autopilot/requirements（真实目录）
  ```
  repair 后 ls 显示 `drwxr-xr-x`（真实目录），git commit 成功（COMMIT OK）
- 状态: ✅

**场景 5 — doctor 抽查 2 个健康 worktree** [高]
- 执行: 构造 2 个 worktree（symlink + node_modules + local-config.json + package.json 全在），跑 worktree health bash 段
- 输出: 
  ```
  --- worktree health ---
  [worktree: /private/tmp/.../wt-1]
  [worktree: /private/tmp/.../wt-2]
  exit=1   ⚠️ 违反契约
  ```
- 状态: ❌ — 脚本退出码为 1，违反契约"脚本退出码必须为 0"。根因：`[ ! -f "$wt/local-config.json" ] && echo` 在 file 存在时返回 1 → while body 末次返回 1 → 整体 exit 1

**场景 6 — doctor 检出 broken worktree** [高]
- 执行: 构造 broken symlink + 缺 node_modules + 缺 local-config.json
- 输出:
  ```
  --- worktree health ---
  [worktree: /private/tmp/.../wt-broken]
    broken-symlink: oops
    missing: node_modules
    missing: local-config.json
  exit=0
  ```
- 状态: ✅

**场景 7 — doctor 在主仓库自身（无 worktree）** [中]
- 执行: 主仓库无任何 worktree，跑 worktree health bash 段
- 输出: `--- worktree health ---` 头 + exit=0
- 状态: ✅

**场景 8 — doctor 在 worktree 内运行** [中]
- 执行: cd 进 worktree-here，跑 worktree health bash 段
- 输出: 
  ```
  --- worktree health ---
  MAIN_ROOT=/private/tmp/.../wt-here   ⚠️ 应是主仓库根而非当前 worktree
  [worktree: /private/tmp/.../<主仓库>]   ⚠️ 主仓库被错误当成 worktree 检查
    missing: local-config.json
  ```
- 状态: ❌ — `git rev-parse --show-toplevel` 在 worktree 内返回 worktree 路径而非主仓库根，导致 MAIN_ROOT 错指、跳过逻辑失效。worktree.mjs:34-55 `repoRoot()` 早已用 `--git-common-dir` 解决同样问题，doctor 设计未复用此知识（[2026-03-27] worktree 内 git 路径解析陷阱 pattern 重演）

**场景计数匹配**：N=5（设计文档场景 1/5/6/7/8），E=5（执行: 标记 5 个），E≥N ✅
**结果**：3 ✅ / 2 ❌

#### Wave 2 — qa-reviewer Agent (sonnet)

**Section A — 设计符合性**：❌ 重大偏离（2 个设计自身内部矛盾：exit code 契约违反 + MAIN_ROOT 命令选择错误）

**Section B — 代码质量与安全**：78/100，2 Important + 2 Minor

Strengths：
- worktree.mjs 改动用 `try { lstatSync } catch` 防御 dst 不存在；新分支用 `git()` + try/catch 比 LEGACY 的 `gitSilent` 语义更明确；remove 函数已合并 SHARED+LEGACY 清理列表，无遗漏

Issues:
- **[82] [doctor SKILL.md:202] worktree health 段退出码污染**：`done` 后无 `|| true`，健康 worktree 反让脚本 exit 1（场景 5 已证）
- **[81] [doctor SKILL.md:190] MAIN_ROOT 在 worktree 内错指**：`git rev-parse --show-toplevel` 应改 `--git-common-dir + dirname`（场景 8 已证）
- [85] [worktree.mjs:173] LEGACY 分支 catch 语义与新分支一致都吞错，可考虑区分 ENOENT 与真实错误（minor）
- [80] [worktree.mjs:96] requirements 留 SHARED 是设计选择疑问，非本次范围（minor）

**Section C — 红队测试质量**：✅ 4 case 全部有强断言，无宽容跳过，质量合格

**Ready to merge**: No

#### 失败 Tier 清单（auto-fix 待修复）

1. **[Tier 1.5] 场景 5 + Tier 2 [82]**：`SKILL.md` Dim 8 worktree health 段 `done` 后追加 `|| true`（一字修复）
2. **[Tier 1.5] 场景 8 + Tier 2 [81]**：`SKILL.md` Dim 8 `MAIN_ROOT` 改用 `git rev-parse --git-common-dir` 方案，与 worktree.mjs:46 对齐

#### 改进建议（非阻断）

- 修复后建议在 SKILL.md 契约段补一条"运行路径无关性"约束，避免下次再忘
- patterns.md 已有 [2026-03-27] worktree 内 git 路径解析陷阱 — 本次再次踩坑，可考虑在 doctor SKILL 评分指引顶部加 "Run-anywhere 检查清单" 元检查项

> 本轮 QA 失败项均集中在 doctor SKILL.md 的 bash 脚本细节，与 [2026-03-27] 已沉淀的 pattern 直接相关。worktree.mjs 改动本身已通过全部 4 case 红队测试与场景 1 真实验证。

### 轮次 2（2026-05-10T03:15:00Z）— ✅ 全部通过，gate → review-accept

#### selective 重跑 Wave 1.5（5/5 全部）

- 场景 1（残留 symlink 自愈）— 执行: 重跑 worktree.mjs repair → 输出: real-dir OK + commit OK ✅
- 场景 5（2 健康 worktree）— 执行: 修复后脚本片段 → 输出: 列出 wt-1/wt-2，exit=0 ✅
- 场景 6（broken worktree）— 执行: 同上 → 输出: broken-symlink + 2 missing 全检出，exit=0 ✅
- 场景 7（无 worktree）— 执行: 同上 → 输出: 仅头，exit=0 ✅
- 场景 8（cwd 在 worktree 内）— 执行: 同上 → 输出: 正确跳过主仓库，列出当前 worktree，exit=0 ✅

**场景计数匹配**：N=5，E=5，✅

#### Tier 0+1 回归（保险重跑）
- 执行: `npm test` → 输出: `# pass 80 / # fail 0`，✅

#### Wave 2 — qa-reviewer Agent (selective)

- **Section A**: ✅ 完全符合（5/5 契约修复点全部兑现），无缺失/超出/偏离
- **Section B**: 90/100（0 critical / 1 important / 1 minor）
  - Strengths: awk 按位置跳过的语义健壮性、`|| true` 位置精确（仅保护最终退出码）、残留 symlink 三态边界覆盖
  - Important [82]: 内层 `find | while` 管道未加 `|| true`，默认环境无 pipefail 不触发，**不阻断**
  - Minor [75]: 测试里 `rmSync` 用动态 import 而非顶部静态 import，风格小事
- **Section C**: ✅ 红队 4 case 全部有强断言、无宽容跳过、粒度精确

**Ready to merge: Yes**

#### 改进建议（非阻断，留给后续）
- 下次编辑 SKILL.md 时给内层 `find | while` 也加 `|| true`，防 pipefail 透传
- 测试文件顶部 import 列表加 `rmSync`，删除 fixture 内的动态 import
- 历史遗留：SKILL.md 部分 Dim 章节标题的 % 与权重表不一致（设计明确不动权重，留下次专项修）

> 本轮全 ✅，设 gate: review-accept 等待用户审批进入 merge。

## 变更日志
- [2026-05-10T01:52:03Z] autopilot 初始化，目标: 需要的，先修复这个问题，然后 🔴 P0：doctor 对 worktree 是"门口检查"，不进屋 这个问题也一起解决掉，这个很重要
- [2026-05-10T02:05:00Z] design 阶段完成知识加载（[2026-05-04][2026-03-25][2026-05-05] 三条相关）
- [2026-05-10T02:05:00Z] design 阶段完成验收场景生成（8 个场景，4 高 4 中）
- [2026-05-10T02:10:00Z] design 阶段完成设计文档 + 契约规约 + 实现计划（6 任务）
- [2026-05-10T02:15:00Z] plan-reviewer 审查 PASS（无 BLOCKER），2 重要问题已纳入：场景 6/7/8 加手动验收、case B 改为接受 checkout 失败语义
- [2026-05-10T02:15:00Z] design 阶段完成 → 等待用户审批
- [2026-05-10T02:18:00Z] 用户审批通过，phase → implement
- [2026-05-10T02:35:00Z] 蓝队完成改动 1（worktree.mjs L196-218）+ 改动 2（doctor SKILL Dim 8 追加 worktree 健康抽查）
- [2026-05-10T02:35:00Z] 红队完成 4 case 测试（A/B/C/D），ensureSelectiveAutopilotLayout 已 export
- [2026-05-10T02:38:00Z] 编排器修复 worktree.mjs 注释与代码不符 bug（L205-208 注释错说 mkdirSync 兜底，实际无）
- [2026-05-10T02:38:00Z] 全量 npm test 80 pass / 0 fail
- [2026-05-10T02:42:00Z] contract-checker 发现 1 high + 1 medium，分析后判定为契约描述歧义（非实现 bug），修正契约表述、附加发现入 QA 改进建议、不打回 implement
- [2026-05-10T02:43:00Z] phase → qa
- [2026-05-10T02:50:00Z] qa Wave 1 ✅（npm test 80/80 + shellcheck exit 0）
- [2026-05-10T02:50:00Z] qa Wave 1.5 ❌ 2 项：场景 5 脚本 exit 1（违反退出码 0 契约）、场景 8 在 worktree 内 MAIN_ROOT 错指
- [2026-05-10T02:50:00Z] qa Wave 2 (qa-reviewer) Ready to merge: No，2 Important 级 bug 与 Tier 1.5 同根因
- [2026-05-10T02:55:00Z] phase → auto-fix，retry_count=1，待修 SKILL.md Dim 8 两处
- [2026-05-10T03:05:00Z] auto-fix 应用一处合并修复：(1) MAIN_ROOT 变量删除，改用 awk 按位置跳过第 1 项（git worktree list --porcelain 第一项总是主仓库，与契约描述一致）；(2) `done` 后追加 `|| true`（保 exit 0）。两 bug 同源同修。
- [2026-05-10T03:05:00Z] 重跑场景 5/6/7/8：全部 ✅ + exit 0；npm test 80/80
- [2026-05-10T03:05:00Z] phase → qa，retry_count=2，qa_scope=selective（仅重跑 Tier 1.5 + Tier 2 失败项）
- [2026-05-10T03:15:00Z] qa 轮次 2 全 ✅：场景 1/5/6/7/8 全部通过 + npm test 80/80 + qa-reviewer Ready to merge: Yes
- [2026-05-10T03:15:00Z] gate → review-accept，qa_scope 清空，等待用户审批进入 merge
- [2026-05-10T03:18:00Z] 用户审批通过，phase → merge
- [2026-05-10T03:25:00Z] commit-agent 提交 51899cd（feat(autopilot)，v3.24.0 → v3.25.0），同步 plugin.json + marketplace.json + CLAUDE.md
- [2026-05-10T03:30:00Z] 知识提取：1 decision（合并修复消除同源 bug）+ 1 pattern（git porcelain 第一项稳定），单独 commit 沉淀到 .autopilot/
- [2026-05-10T03:30:00Z] phase → done
