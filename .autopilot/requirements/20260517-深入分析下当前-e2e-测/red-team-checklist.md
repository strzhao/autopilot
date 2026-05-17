# 红队验收清单

> 本清单由红队（验证者）根据设计文档产出，用于 QA 阶段逐项验证蓝队产出。
> 依据来源：state.md `## 设计文档`、`## 实现计划`、`## 验收场景`、`## 契约规约` 4 个章节。
> **禁止含糊判断**：每条检查必须给出明确的 通过 / 不通过 / 待 AI 判断 结论。

---

## 一、文件存在性检查（结构性，可机械验证）

- [ ] **CHECK_1**: 单一真相源文件存在
  - 验证命令：`test -f /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/test-mutation-survival.md && echo OK || echo FAIL`
  - 期望结果：输出 `OK`
  - 验证依据：契约规约「文件路径契约」——"新建文件路径：`plugins/autopilot/skills/autopilot/references/test-mutation-survival.md`（不使用 `test-no-op-resistance.md` 等其他命名）"

- [ ] **CHECK_2**: 单一真相源文件行数不少于 80 行（设计要求约 120 行）
  - 验证命令：`wc -l /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/test-mutation-survival.md | awk '{print ($1 >= 80) ? "OK" : "FAIL: only " $1 " lines"}'`
  - 期望结果：输出 `OK`
  - 验证依据：设计文档「单一真相源文件设计」——"新建约 120 行"；OST 表格"行数 ≥80"

- [ ] **CHECK_3**: `red-team-prompt.md` 路径不变（文件仍存在）
  - 验证命令：`test -f /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/red-team-prompt.md && echo OK || echo FAIL`
  - 期望结果：输出 `OK`
  - 验证依据：契约规约「文件路径契约」——4 个被修改 prompt 文件路径不变

- [ ] **CHECK_4**: `scenario-generator-prompt.md` 路径不变（文件仍存在）
  - 验证命令：`test -f /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/scenario-generator-prompt.md && echo OK || echo FAIL`
  - 期望结果：输出 `OK`
  - 验证依据：契约规约「文件路径契约」

- [ ] **CHECK_5**: `plan-reviewer-prompt.md` 路径不变（文件仍存在）
  - 验证命令：`test -f /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/plan-reviewer-prompt.md && echo OK || echo FAIL`
  - 期望结果：输出 `OK`
  - 验证依据：契约规约「文件路径契约」

- [ ] **CHECK_6**: `qa-reviewer-prompt.md` 路径不变（文件仍存在）
  - 验证命令：`test -f /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/qa-reviewer-prompt.md && echo OK || echo FAIL`
  - 期望结果：输出 `OK`
  - 验证依据：契约规约「文件路径契约」

- [ ] **CHECK_7**: `plugin.json` 存在
  - 验证命令：`test -f /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/.claude-plugin/plugin.json && echo OK || echo FAIL`
  - 期望结果：输出 `OK`
  - 验证依据：CLAUDE.md「版本管理」——plugin.json 是插件系统版本检测文件

- [ ] **CHECK_8**: `marketplace.json` 存在
  - 验证命令：`test -f /Users/stringzhao/workspace/string-claude-code-plugin/.claude-plugin/marketplace.json && echo OK || echo FAIL`
  - 期望结果：输出 `OK`
  - 验证依据：CLAUDE.md「版本管理」

---

## 二、字面契约检查（grep -F 严格大小写敏感）

> 验证依据总纲：契约规约「字面字符串契约」表格，验证方法明确要求"使用大小写敏感的 `grep -F`，禁止 `grep -i` 模糊匹配"。

### 契约 1：`Mutation-Survival 自检` 出现在 `red-team-prompt.md` 铁律段

- [ ] **CHECK_9**: 正向命中（必须存在）
  - 命令：`grep -F "Mutation-Survival 自检" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/red-team-prompt.md`
  - 期望结果：至少命中 1 行
  - 契约依据：「字面字符串契约」第 1 行——"`Mutation-Survival 自检` 必须出现在 `red-team-prompt.md` 铁律段标题"

- [ ] **CHECK_10**: 反向检查——禁止小写变体（必须未命中）
  - 命令：`grep -F "mutation-survival 自检" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/red-team-prompt.md`
  - 期望结果：无输出（exit code 1）
  - 契约依据：「字面字符串契约」——"严格 —— 不接受 `mutation-survival 自检` 变体"

- [ ] **CHECK_11**: 反向检查——禁止空格变体（必须未命中）
  - 命令：`grep -F "Mutation Survival 自检" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/red-team-prompt.md`
  - 期望结果：无输出（exit code 1）
  - 契约依据：「字面字符串契约」——"不接受 `Mutation Survival 自检`（连字符不得省略）"

### 契约 2：`Mental Mutation 5 问` 出现在 `red-team-prompt.md` 或 `test-mutation-survival.md`

- [ ] **CHECK_12**: `red-team-prompt.md` 或 `test-mutation-survival.md` 至少其中一个命中
  - 命令：
    ```
    grep -F "Mental Mutation 5 问" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/red-team-prompt.md /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/test-mutation-survival.md
    ```
  - 期望结果：至少命中 1 行
  - 契约依据：「字面字符串契约」第 2 行——"`Mental Mutation 5 问` 严格，`Mental Mutation` 首字母大写"

- [ ] **CHECK_13**: 反向检查——禁止小写变体（两文件均不得命中）
  - 命令：
    ```
    grep -F "mental mutation 5 问" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/red-team-prompt.md /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/test-mutation-survival.md
    ```
  - 期望结果：无输出（exit code 1）
  - 契约依据：「字面字符串契约」——首字母大写严格要求

### 契约 3：`Observable State Transitions` 出现在 `scenario-generator-prompt.md` 场景字段名

- [ ] **CHECK_14**: 正向命中（必须存在）
  - 命令：`grep -F "Observable State Transitions" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/scenario-generator-prompt.md`
  - 期望结果：至少命中 1 行
  - 契约依据：「字面字符串契约」第 3 行——"`Observable State Transitions` 严格——三词全部首字母大写"

- [ ] **CHECK_15**: 反向检查——禁止小写变体（必须未命中）
  - 命令：`grep -F "observable state transitions" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/scenario-generator-prompt.md`
  - 期望结果：无输出（exit code 1）
  - 契约依据：「字面字符串契约」——三词全部首字母大写，严格

- [ ] **CHECK_16**: 反向检查——禁止首字母缺失变体（必须未命中）
  - 命令：`grep -F "observable State Transitions" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/scenario-generator-prompt.md`
  - 期望结果：无输出（exit code 1）
  - 契约依据：同上

### 契约 4：`Mutation-Survival 抗性` 出现在 `plan-reviewer-prompt.md` 维度 #8 标题

- [ ] **CHECK_17**: 正向命中（必须存在）
  - 命令：`grep -F "Mutation-Survival 抗性" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/plan-reviewer-prompt.md`
  - 期望结果：至少命中 1 行
  - 契约依据：「字面字符串契约」第 4 行——"`Mutation-Survival 抗性` 严格"

- [ ] **CHECK_18**: 反向检查——禁止小写变体（必须未命中）
  - 命令：`grep -F "mutation-survival 抗性" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/plan-reviewer-prompt.md`
  - 期望结果：无输出（exit code 1）
  - 契约依据：「字面字符串契约」——严格大小写

### 契约 5：`Tautological` 出现在 `qa-reviewer-prompt.md` Section C 检查项 #4

- [ ] **CHECK_19**: 正向命中（必须存在）
  - 命令：`grep -F "Tautological" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/qa-reviewer-prompt.md`
  - 期望结果：至少命中 1 行（Section C 检查项 #4 标题中）
  - 契约依据：「字面字符串契约」第 5 行——"`Tautological` 严格——首字母大写"

- [ ] **CHECK_20**: 反向检查——禁止纯小写变体（必须未命中）
  - 命令：`grep -F "tautological" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/qa-reviewer-prompt.md`
  - 期望结果：无输出（exit code 1）
  - 契约依据：「字面字符串契约」——首字母大写严格

### 契约 6：引用串 `references/test-mutation-survival.md` 出现在全部 4 个 prompt 文件

- [ ] **CHECK_21**: `red-team-prompt.md` 包含引用串
  - 命令：`grep -F "references/test-mutation-survival.md" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/red-team-prompt.md`
  - 期望结果：至少命中 1 行
  - 契约依据：「字面字符串契约」第 6 行——"`references/test-mutation-survival.md` 必须在 4 个 prompt 文件各自至少出现 1 次（引用串），路径全小写带连字符"

- [ ] **CHECK_22**: `scenario-generator-prompt.md` 包含引用串
  - 命令：`grep -F "references/test-mutation-survival.md" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/scenario-generator-prompt.md`
  - 期望结果：至少命中 1 行
  - 契约依据：「字面字符串契约」第 6 行

- [ ] **CHECK_23**: `plan-reviewer-prompt.md` 包含引用串
  - 命令：`grep -F "references/test-mutation-survival.md" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/plan-reviewer-prompt.md`
  - 期望结果：至少命中 1 行
  - 契约依据：「字面字符串契约」第 6 行

- [ ] **CHECK_24**: `qa-reviewer-prompt.md` 包含引用串
  - 命令：`grep -F "references/test-mutation-survival.md" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/qa-reviewer-prompt.md`
  - 期望结果：至少命中 1 行
  - 契约依据：「字面字符串契约」第 6 行

- [ ] **CHECK_25**: 引用串全小写——反向检查禁止大写路径变体（4 个文件均不得命中）
  - 命令：`grep -rF "references/Test-Mutation-Survival.md" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/`
  - 期望结果：无输出（exit code 1）
  - 契约依据：「字面字符串契约」——"路径全小写带连字符"

---

## 三、版本号同步检查

> 版本号契约：v3.31.0（不使用 v3.30.1 / v4.0.0 等），必须在 3 处（+条件性 1 处）同步出现。

- [ ] **CHECK_26**: `plugin.json` 版本号已升级到 v3.31.0
  - 命令：`grep -F '"version"' /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/.claude-plugin/plugin.json`
  - 期望结果：输出行包含 `"version": "3.31.0"` 或 `"version":"3.31.0"`
  - 验证依据：契约规约「版本号契约」——"`plugins/autopilot/.claude-plugin/plugin.json` 的 `version` 字段"

- [ ] **CHECK_27**: `plugin.json` 不再包含旧版本号 v3.30.0
  - 命令：`grep -F "3.30.0" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/.claude-plugin/plugin.json`
  - 期望结果：无输出（exit code 1）
  - 验证依据：版本号已替换，旧版本号不应保留

- [ ] **CHECK_28**: `marketplace.json` 中 autopilot 条目版本号已升级到 v3.31.0
  - 命令：`grep -F "3.31.0" /Users/stringzhao/workspace/string-claude-code-plugin/.claude-plugin/marketplace.json`
  - 期望结果：至少命中 1 行
  - 验证依据：契约规约「版本号契约」——"`.claude-plugin/marketplace.json` autopilot 条目的 version 字段"

- [ ] **CHECK_29**: `marketplace.json` 中 autopilot 旧版本号已清除
  - 命令：`grep -F "3.30.0" /Users/stringzhao/workspace/string-claude-code-plugin/.claude-plugin/marketplace.json`
  - 期望结果：无输出（exit code 1）
  - 验证依据：版本号唯一性

- [ ] **CHECK_30**: `CLAUDE.md` 插件索引表 autopilot 行版本号已升级到 v3.31.0
  - 命令：`grep -F "v3.31.0" /Users/stringzhao/workspace/string-claude-code-plugin/CLAUDE.md`
  - 期望结果：至少命中 1 行（在插件索引 autopilot 行中）
  - 验证依据：契约规约「版本号契约」——"`CLAUDE.md` 插件索引表格 autopilot 行的 `vX.Y.Z` 列"

- [ ] **CHECK_31**: `CLAUDE.md` 插件索引表 autopilot 行旧版本号已清除
  - 命令：`grep -F "v3.30.0" /Users/stringzhao/workspace/string-claude-code-plugin/CLAUDE.md`
  - 期望结果：无输出（exit code 1）
  - 验证依据：版本号唯一性

- [ ] **CHECK_32**: `package.json` 版本号（条件性——仅当文件不存在时跳过，存在则必须同步）
  - 命令：`[ ! -f /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/package.json ] && echo "SKIP: file not found" || grep -F '"version"' /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/package.json`
  - 期望结果：`SKIP: file not found`（已验证该文件不存在）或包含 `"3.31.0"` 的行
  - 验证依据：契约规约「版本号契约」——"`plugins/autopilot/package.json` 的 version 字段（如该文件存在）"

---

## 四、最小集 + 纯追加 + 可独立回滚检查

### 4.1 git diff 纯追加确认

- [ ] **CHECK_33**: `red-team-prompt.md` 改动是纯追加（deletions 应为 0 或极少）
  - 命令：`cd /Users/stringzhao/workspace/string-claude-code-plugin && git diff --stat plugins/autopilot/skills/autopilot/references/red-team-prompt.md`
  - 期望结果：显示 `insertions(+)` 数字 **远大于** `deletions(-)` 数字；理想：deletions == 0
  - 验证依据：设计文档「所有改动遵循最小集 + 纯追加 + 可独立回滚原则」；红队 prompt 追加约 5-6 行

- [ ] **CHECK_34**: `scenario-generator-prompt.md` 改动是纯追加
  - 命令：`cd /Users/stringzhao/workspace/string-claude-code-plugin && git diff --stat plugins/autopilot/skills/autopilot/references/scenario-generator-prompt.md`
  - 期望结果：insertions 远大于 deletions；理想：deletions == 0
  - 验证依据：设计文档——追加约 3 行

- [ ] **CHECK_35**: `plan-reviewer-prompt.md` 改动是纯追加
  - 命令：`cd /Users/stringzhao/workspace/string-claude-code-plugin && git diff --stat plugins/autopilot/skills/autopilot/references/plan-reviewer-prompt.md`
  - 期望结果：insertions 远大于 deletions；理想：deletions == 0
  - 验证依据：设计文档——追加约 4 行

- [ ] **CHECK_36**: `qa-reviewer-prompt.md` 改动是纯追加
  - 命令：`cd /Users/stringzhao/workspace/string-claude-code-plugin && git diff --stat plugins/autopilot/skills/autopilot/references/qa-reviewer-prompt.md`
  - 期望结果：insertions 远大于 deletions；理想：deletions == 0
  - 验证依据：设计文档——追加约 8 行

### 4.2 现有铁律段未被删除（回归检查）

- [ ] **CHECK_37**: `red-team-prompt.md` 原有"宽容跳过"反模式铁律段仍存在
  - 命令：`grep -F "宽容跳过" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/red-team-prompt.md`
  - 期望结果：至少命中 1 行
  - 验证依据：契约规约「不变量契约」——"现有反模式条目（宽容跳过模式 / 缺失断言）不删除、不修改"

- [ ] **CHECK_38**: `red-team-prompt.md` 原有"缺失断言"铁律段仍存在
  - 命令：`grep -F "try" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/red-team-prompt.md`
  - 期望结果：至少命中 1 行（原有 try-catch 吞断言反模式说明行）
  - 验证依据：契约规约「不变量契约」

- [ ] **CHECK_39**: `red-team-prompt.md` 原有"## ⚠️ 铁律"一级标题仍存在
  - 命令：`grep -F "## ⚠️ 铁律" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/red-team-prompt.md`
  - 期望结果：至少命中 1 行
  - 验证依据：契约规约「不变量契约」——"现有章节结构保持不变"

- [ ] **CHECK_40**: `red-team-prompt.md` 原有"## ⚠️ 测试质量铁律（必读）"二级标题仍存在
  - 命令：`grep -F "## ⚠️ 测试质量铁律（必读）" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/red-team-prompt.md`
  - 期望结果：至少命中 1 行
  - 验证依据：契约规约「不变量契约」——"现有铁律段保持不变"

- [ ] **CHECK_41**: `plan-reviewer-prompt.md` 原有"E2E 强制条件"规则仍存在
  - 命令：`grep -F "E2E 强制条件" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/plan-reviewer-prompt.md`
  - 期望结果：至少命中 1 行
  - 验证依据：契约规约「不变量契约」——"现有铁律段不删除"

- [ ] **CHECK_42**: `plan-reviewer-prompt.md` 原有维度 1-7（审查维度）结构仍完整
  - 命令：`grep -F "契约完整性" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/plan-reviewer-prompt.md`
  - 期望结果：至少命中 1 行（原有维度 7 契约完整性仍存在）
  - 验证依据：契约规约「不变量契约」——"现有章节结构保持不变"

- [ ] **CHECK_43**: `qa-reviewer-prompt.md` 原有 Section C 检查项 1（宽容跳过模式）仍存在
  - 命令：`grep -F "宽容跳过模式" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/qa-reviewer-prompt.md`
  - 期望结果：至少命中 1 行
  - 验证依据：契约规约「不变量契约」——"现有反模式条目不删除"

- [ ] **CHECK_44**: `qa-reviewer-prompt.md` 原有 Section C 检查项 2（缺失断言）仍存在
  - 命令：`grep -F "缺失断言" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/qa-reviewer-prompt.md`
  - 期望结果：至少命中 1 行
  - 验证依据：契约规约「不变量契约」——"现有反模式条目不删除"

- [ ] **CHECK_45**: `qa-reviewer-prompt.md` 原有 Section C 检查项 3（断言粒度过粗）仍存在
  - 命令：`grep -F "断言粒度过粗" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/qa-reviewer-prompt.md`
  - 期望结果：至少命中 1 行
  - 验证依据：契约规约「不变量契约」——"现有反模式条目不删除"

- [ ] **CHECK_46**: `scenario-generator-prompt.md` 原有 6 个"每个场景包含"字段（验证层级）仍存在
  - 命令：`grep -F "验证层级" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/scenario-generator-prompt.md`
  - 期望结果：至少命中 1 行
  - 验证依据：契约规约「不变量契约」——"现有章节结构保持不变"

### 4.3 SKILL.md 未被修改

- [ ] **CHECK_47**: `SKILL.md` 无任何改动
  - 命令：`cd /Users/stringzhao/workspace/string-claude-code-plugin && git diff plugins/autopilot/skills/autopilot/SKILL.md`
  - 期望结果：**无输出**（空 diff）
  - 验证依据：契约规约「不变量契约」——"`SKILL.md` 主体不修改（避免触动决策树后置章节被 AI 跳过的已知风险，见 patterns.md 2026-04-17）"

---

## 五、设计语义符合性检查（需 AI 人工判断）

> 以下条目无法用 grep / bash 机械验证，QA 阶段需由 AI 读取对应文件内容并做语义判断。

- [ ] **CHECK_48**: `test-mutation-survival.md` 的 Mental Mutation 5 问表格是否完整覆盖设计文档规定的 5 种 mutation 类型？
  - 验证方式：AI 读取 `test-mutation-survival.md`，逐一核对下列 5 种类型是否全部在表格中出现（按设计文档命名）：
    1. **No-op Mutation**（把 handler 改为空函数）
    2. **Conditional Flip**（把 `if (X)` 改为 `if (!X)` 或 `if (true)`）
    3. **Boundary Mutation**（把 `===` 改为 `>=`、`<` 改为 `<=`）
    4. **Return-Value Mutation**（把返回值改为 happy-path 默认值）
    5. **State-Update Skip**（跳过 `setState` / `dispatch`）
  - 通过标准：5 种类型全部存在，且每种含"自问内容"和"适用层级"两列
  - 判断类型：**待 AI 判断**

- [ ] **CHECK_49**: `test-mutation-survival.md` 是否包含 7 个设计要求的章节结构，且顺序符合设计文档规定？
  - 验证方式：AI 读取文件，确认以下 7 个结构节均存在：
    1. 概念定义（含 Tautological test 引用 Coulman 2016）
    2. 触发范围（含"纯渲染/纯数据契约/纯函数单元测试不触发"说明）
    3. Mental Mutation 5 问（表格）
    4. 反模式清单（3 类，含 Stable Element Assertion / Click Chain Without Mid-Asserts / Timer-Only Wait）
    5. 正模式清单（3 类，含 Observable State Transition / State-Driven Wait / Negative Path Verification）
    6. 审查侧检查清单（含 plan-reviewer / qa-reviewer 各自检查点）
    7. 适用边界（明确列出 4 类不触发场景）
  - 通过标准：7 个节全部存在，且每节内容有实质性内容（非仅标题）
  - 判断类型：**待 AI 判断**

- [ ] **CHECK_50**: 反模式清单是否给出 case.txt 风格的 TypeScript/Playwright 代码示例？
  - 验证方式：AI 读取 `test-mutation-survival.md`，在反模式清单章节检查：
    - 是否有 TypeScript/Playwright 代码块（以 ` ```ts ` 或 ` ```typescript ` 标记）
    - 代码示例是否引用了 case.txt 中出现的真实 API（如 `page.locator`、`toBeVisible`、`waitForTimeout`）或等价模式
    - 每种反模式是否至少有 1 个 Before 代码示例（错误写法）
  - 通过标准：3 类反模式各自至少含 1 个 TypeScript 代码示例
  - 判断类型：**待 AI 判断**

- [ ] **CHECK_51**: 适用边界章节是否明确列出设计文档规定的 4 类不触发场景？
  - 验证方式：AI 读取 `test-mutation-survival.md` 适用边界章节，核对是否覆盖以下 4 类：
    1. 纯渲染断言（"页面加载后显示用户名"）
    2. 纯数据契约断言（API 响应字段验证）
    3. 纯函数单元测试（输入→输出）
    4. Negative testing（断言"无变化"本身就是 mutation-resistant）
  - 通过标准：4 类全部在"不触发"列表中明确列出，且对"Negative testing"给出"不触发原因"说明
  - 判断类型：**待 AI 判断**

- [ ] **CHECK_52**: 4 个 prompt 中追加的内容是否都通过引用串 `references/test-mutation-survival.md` 指向单一真相源，而非将完整规则内联在 prompt 文件中？
  - 验证方式：AI 读取 4 个 prompt 文件的 git diff，确认：
    - 新增内容中核心规则细节（5 问表格、反/正模式清单等）不在 prompt 文件内联，而是引用 reference
    - 每个 prompt 追加的内容是 **1-8 行铁律触发** + `references/test-mutation-survival.md` 引用
  - 通过标准：4 个 prompt 追加内容均符合"触发铁律 + 引用串"模式，无内联完整规则
  - 判断类型：**待 AI 判断**

- [ ] **CHECK_53**: `plan-reviewer-prompt.md` 中追加的维度 #8 是否包含"仅当变更涉及用户交互"的触发条件限定？
  - 验证方式：AI 读取 `plan-reviewer-prompt.md` 的新增维度 #8，检查是否有等价于"仅当变更涉及用户交互且有 E2E/集成/交互测试场景时检查"的语义限定
  - 通过标准：维度 #8 明确声明触发条件，不是无条件触发
  - 判断类型：**待 AI 判断**

- [ ] **CHECK_54**: `qa-reviewer-prompt.md` 中追加的检查项 #4 是否包含 3 个子检查问题（对应设计文档 Section C #4 的 3 个子问题）？
  - 验证方式：AI 读取 `qa-reviewer-prompt.md` 新增检查项 #4，核对是否包含：
    1. "每次用户交互调用后是否至少有 1 个断言验证仅由该交互产生的可观察状态变化"
    2. "测试最终断言的元素/属性是否仅在功能正确时才出现/匹配（断言 stable element visible 是反模式）"
    3. "`waitForTimeout(N)` 后的断言是否仅检查页面初始状态即满足的条件"
  - 通过标准：3 个子问题语义等价内容全部存在
  - 判断类型：**待 AI 判断**

- [ ] **CHECK_55**: `scenario-generator-prompt.md` 追加的 OST 字段是否包含"纯渲染类场景填 N/A"的说明？
  - 验证方式：AI 读取 `scenario-generator-prompt.md` 新增 OST 字段定义，检查是否有等价于"纯渲染类场景填 N/A"的说明（防止场景生成器对所有场景无差别要求 OST，产生误报）
  - 通过标准：OST 字段定义中明确给出"不适用时的填写规范"
  - 判断类型：**待 AI 判断**

---

## 六、9 个验收场景的清单化映射

### S1 — 红队生成测试含 state 变化断言，不再仅断言元素存在

- [ ] **CHECK_S1**: `red-team-prompt.md` 的新增铁律段是否要求每个交互后有 OST 断言？
  - 验证方式：AI 读取 `red-team-prompt.md` 追加的"Mutation-Survival 自检铁律"段，确认：
    - 铁律要求"测试涉及用户交互/状态变化（click / input / submit / dispatch）时，必须在每个交互断言后过 Mental Mutation 5 问"
    - 铁律要求"选择能 kill 至少 No-op mutation 的断言"（即不能只 `toBeVisible` on stable element）
  - 通过标准：铁律段语义上强制要求每次 click 后有非 stable element 断言
  - 判断类型：**待 AI 判断**
  - 对应场景：Scenario 1 Happy Path

### S2 — 反 no-op 自检显式触发——红队 reasoning 输出含 mutation 自问内容

- [ ] **CHECK_S2**: `red-team-prompt.md` 追加的铁律是否明确指示红队对每个交互执行 Mental Mutation 5 问自问？
  - 验证方式：AI 确认 `red-team-prompt.md` 新增内容包含"Mental Mutation 5 问"明确触发指令，且触发条件与 Scenario 2 描述的"红队完成测试草稿后"吻合
  - 通过标准：追加内容明确列出 5 问触发机制，可驱动 sub-agent 在 reasoning 中执行自问
  - 判断类型：**待 AI 判断**
  - 对应场景：Scenario 2 Happy Path

### S3 — Plan 审查标记缺少 OST 的设计方案

- [ ] **CHECK_S3a**: `plan-reviewer-prompt.md` 维度 #8 正向命中（grep 机械验证）
  - 命令：`grep -F "Mutation-Survival 抗性" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/plan-reviewer-prompt.md`
  - 期望结果：至少命中 1 行（同 CHECK_17，此处关联 Scenario 3）
  - 判断类型：**机械验证**

- [ ] **CHECK_S3b**: 维度 #8 是否声明"仅断言终态/stable 元素 visible → BLOCKER（≥91）"？
  - 验证方式：AI 读取维度 #8 内容，确认包含置信度阈值 ≥91 + BLOCKER 标记
  - 通过标准：维度 #8 明确将"仅有终态/stable 元素 visible 断言"列为 BLOCKER
  - 判断类型：**待 AI 判断**
  - 对应场景：Scenario 3 Happy Path

### S4 — QA 审查拦截 `toBeVisible() on stable element` 已有测试

- [ ] **CHECK_S4a**: `qa-reviewer-prompt.md` 包含 `Tautological` 关键字（grep 机械验证）
  - 命令：`grep -F "Tautological" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/qa-reviewer-prompt.md`
  - 期望结果：至少命中 1 行（同 CHECK_19，此处关联 Scenario 4）
  - 判断类型：**机械验证**

- [ ] **CHECK_S4b**: 检查项 #4 是否明确将"断言 stable element visible"列为 BLOCKER（置信度 90+）？
  - 验证方式：AI 读取 `qa-reviewer-prompt.md` 检查项 #4，确认：
    - `toBeVisible()` on stable element 被明确列为反模式触发条件
    - 置信度阈值 ≥90，标记为 BLOCKER
  - 通过标准："`断言 stable element visible → 反模式`" 语义明确存在，BLOCKER 标记存在
  - 判断类型：**待 AI 判断**
  - 对应场景：Scenario 4 Happy Path

### S5 — SSR hydration 场景红队主动要求等待 hydration

- [ ] **CHECK_S5**: `test-mutation-survival.md` 是否提及 hydration / SSR 相关的 No-op Mutation 场景？
  - 验证方式：AI 读取 `test-mutation-survival.md`，检查反模式示例或正模式示例中是否覆盖了 SSR hydration mismatch 导致 click 成为 no-op 的场景（对应 case.txt 实证 bug）
  - 通过标准：文件中有 SSR/hydration 相关的 No-op Mutation 描述，或反模式"Click Chain Without Mid-Asserts"的示例展示了 hydration 无效 click 的场景
  - 判断类型：**待 AI 判断**
  - 对应场景：Scenario 5 Edge Case

### S6 — 纯展示型目标不触发反 no-op 规则，无误报

- [ ] **CHECK_S6a**: `test-mutation-survival.md` 适用边界章节包含"纯渲染断言"不触发说明（grep）
  - 命令：`grep -F "纯渲染" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/test-mutation-survival.md`
  - 期望结果：至少命中 1 行
  - 判断类型：**机械验证**

- [ ] **CHECK_S6b**: `plan-reviewer-prompt.md` 维度 #8 的触发条件是否明确排除纯展示型目标？
  - 验证方式：AI 读取维度 #8 触发条件说明，确认"纯渲染/无交互"场景不触发此维度
  - 通过标准：触发条件语义上只在"变更涉及用户交互"时激活，不会对纯展示型场景产生 BLOCKER
  - 判断类型：**待 AI 判断**
  - 对应场景：Scenario 6 Edge Case

### S7 — 4 个 prompt 阶段对"什么是有效断言"判定一致（引用同一 reference）

- [ ] **CHECK_S7**: 4 个 prompt 文件全部包含引用串 `references/test-mutation-survival.md`（grep 机械验证）
  - 命令：
    ```bash
    for f in red-team-prompt.md scenario-generator-prompt.md plan-reviewer-prompt.md qa-reviewer-prompt.md; do
      echo -n "$f: "; grep -cF "references/test-mutation-survival.md" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/$f || echo 0
    done
    ```
  - 期望结果：4 个文件各自输出 ≥1（同 CHECK_21~24，此处为一致性汇总检查）
  - 判断类型：**机械验证**
  - 对应场景：Scenario 7 Integration

### S8 — 旧测试传入 QA 审查被标记 no-op 风险（含行号 + 改进建议）

- [ ] **CHECK_S8**: `qa-reviewer-prompt.md` Section C 检查项 #4 是否要求输出行号信息和改进建议？
  - 验证方式：AI 读取 `qa-reviewer-prompt.md` 的检查项 #4 及其输出格式要求，确认：
    - BLOCKER 报告格式包含"行号"或"file:line"信息要求
    - 包含改进建议（如"需增加 OST 断言"说明）
  - 通过标准：检查项 #4 或其关联的输出格式章节要求提供定位信息（行号）和改进建议，而非仅报告 BLOCKER
  - 判断类型：**待 AI 判断**
  - 对应场景：Scenario 8 Error Scenario

### S9 — little-ant 项目 hydration bug 在新规则下会被识别（回归验证）

- [ ] **CHECK_S9a**: `test-mutation-survival.md` 包含"No-op Mutation"（grep）
  - 命令：`grep -F "No-op Mutation" /Users/stringzhao/workspace/string-claude-code-plugin/plugins/autopilot/skills/autopilot/references/test-mutation-survival.md`
  - 期望结果：至少命中 1 行
  - 判断类型：**机械验证**

- [ ] **CHECK_S9b**: `test-mutation-survival.md` 包含等价于 case.txt 的"click handler 变为 no-op 测试仍通过"反模式说明（AI 判断）
  - 验证方式：AI 读取 `test-mutation-survival.md` 反模式清单，确认：
    - 包含"Click Chain Without Mid-Asserts"反模式或等价描述
    - 该反模式的说明明确指出"click handler 实际为 no-op 时测试仍通过"这一核心缺陷
    - 对应的正模式要求在每次 click 后验证状态变化（计数 / aria-pressed / 类名 / 文本内容）
  - 通过标准：反模式描述 + 正模式对比完整，能让读取该文件的 sub-agent 理解应断言什么
  - 判断类型：**待 AI 判断**
  - 对应场景：Scenario 9 Integration / 回归验证

---

## 汇总

### 总条数统计

| 章节 | 条数 | 判断类型 |
|------|------|---------|
| 一、文件存在性检查 | 8 条（CHECK_1~8） | 全部机械验证 |
| 二、字面契约检查 | 17 条（CHECK_9~25） | 全部机械验证 |
| 三、版本号同步检查 | 7 条（CHECK_26~32） | 全部机械验证 |
| 四、最小集+纯追加+回滚检查 | 15 条（CHECK_33~47） | 全部机械验证 |
| 五、设计语义符合性检查 | 8 条（CHECK_48~55） | 全部待 AI 判断 |
| 六、9 个验收场景映射 | 16 条（CHECK_S1~S9b） | 机械验证 8 条 + 待 AI 判断 8 条 |
| **合计** | **71 条** | **机械验证 55 条 / AI 判断 16 条** |

### Scenario → CHECK 编号映射

| Scenario | 对应 CHECK 编号 |
|----------|---------------|
| S1 — 红队生成测试含 state 变化断言 | CHECK_S1, CHECK_9, CHECK_37, CHECK_40 |
| S2 — 反 no-op 自检显式触发 | CHECK_S2, CHECK_12 |
| S3 — Plan 审查标记缺少 OST 的方案 | CHECK_S3a (=CHECK_17), CHECK_S3b |
| S4 — QA 审查拦截 stable element visible | CHECK_S4a (=CHECK_19), CHECK_S4b |
| S5 — SSR hydration 场景主动等待 | CHECK_S5 |
| S6 — 纯展示型目标不误报 | CHECK_S6a, CHECK_S6b |
| S7 — 4 个 prompt 判定标准一致 | CHECK_S7 (= CHECK_21~24 汇总), CHECK_52 |
| S8 — 旧测试被标记 no-op 风险 | CHECK_S8, CHECK_S4b |
| S9 — little-ant hydration bug 被识别 | CHECK_S9a, CHECK_S9b, CHECK_50 |

### 机械验证 vs AI 判断汇总

**可由 grep / bash 机械验证（55 条）**：CHECK_1~47、CHECK_S3a、CHECK_S4a、CHECK_S6a、CHECK_S7、CHECK_S9a

**需要 AI 语义判断（16 条）**：CHECK_48~55、CHECK_S1、CHECK_S2、CHECK_S3b、CHECK_S4b、CHECK_S5、CHECK_S6b、CHECK_S8、CHECK_S9b
