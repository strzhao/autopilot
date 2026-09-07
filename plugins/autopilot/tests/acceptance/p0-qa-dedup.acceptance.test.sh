#!/usr/bin/env bash
# R_QA_DEDUP: p0-qa-dedup（v3.63.0）QA 重复执行合并 ×3 验收测试
# 红队测试 — 黑盒视角，仅基于 state.md 的「## 契约规约」C1-C4 与「## 验收场景」
#            场景 1-8/10 谓词字面量编写，绝不读取蓝队改后实现凑断言（TDD 红灯）。
#
# 三大目标：
#   ① Tier 1 ∪ Tier 5 coverage 合并单次执行（复用契约 + 降级不变性）
#   ② contract-checker 独立 agent 并入 qa-reviewer Section D（含彻底清扫）
#   ③ context.md 探针产物化（四节契约 + 三模板统一引用）
#   ④ v3.63.0 版本三处同步 + description 清扫
#
# 谓词映射（state.md ## 验收场景）：
#   场景1.P1/P2  复用契约文本 + 验收测试断言存在
#   场景2.P1/P2  无 coverage 工具降级分支契约 + 验收测试断言存在
#   场景3.P1/P2  Section D 定义（逐条比对 + severity）+ 验收测试断言存在
#   场景4.P1     Section D 的 N/A 分支规则
#   场景5.P1/P2  [negate] contract-checker 委托/执行引用计数 == 0
#   场景6.P1/P2  context.md 四节契约 + 空节 N/A 规则
#   场景7.P1/P2  三 prompt 引用 context.md + [negate] 独立自扫描段计数 == 0
#   场景8.P1/P2/P3 版本 3.63.0 三处同步 + description 无 contract-checker
#   场景10.P1    smoke 行保留 Section D
#   （场景9.P1 run-all 回归由编排器 QA 执行，本文件不覆盖）
#
# 锚点来源：全部取自契约规约/谓词字面量（`## Section D: 契约符合性`、
#           `severity=high|medium|low`、context.md 四节名、`3.63.0`、
#           `contract-checker` 计数 == 0），no-op 时全部不存在 → kill no-op。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 兼容两种落位：staging 区（acceptance-staging/，repo 根在 ../../../..，
#              即 .autopilot/runtime/requirements/<slug>/acceptance-staging 上溯 4 级）
#              与最终目标目录（tests/acceptance/，repo 根在 ../../../..）
if [[ -d "$SCRIPT_DIR/../../../../.claude-plugin" ]]; then
    REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../" && pwd)"
else
    REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
fi

SKILL_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/SKILL.md"
REF_DIR="$REPO_ROOT/plugins/autopilot/skills/autopilot/references"
QUANT_FILE="$REF_DIR/quantitative-metrics.md"
QA_PROMPT_FILE="$REF_DIR/qa-reviewer-prompt.md"
BLUE_PROMPT_FILE="$REF_DIR/blue-team-prompt.md"
RED_PROMPT_FILE="$REF_DIR/red-team-prompt.md"
SKILLS_DIR="$REPO_ROOT/plugins/autopilot/skills"
SCRIPTS_DIR="$REPO_ROOT/plugins/autopilot/scripts"
PLUGIN_JSON="$REPO_ROOT/plugins/autopilot/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
TESTS_DIR="$REPO_ROOT/plugins/autopilot/tests/acceptance"

fail() {
    echo "[FAIL] R_QA_DEDUP: $1" >&2
    exit 1
}

pass() {
    echo "[PASS] R_QA_DEDUP: $1"
}

# 前置：关键文件存在
[[ -f "$SKILL_FILE" ]]      || fail "SKILL.md 不存在: $SKILL_FILE"
[[ -d "$REF_DIR" ]]         || fail "references/ 不存在: $REF_DIR"
[[ -f "$QA_PROMPT_FILE" ]]  || fail "qa-reviewer-prompt.md 不存在: $QA_PROMPT_FILE"
[[ -f "$BLUE_PROMPT_FILE" ]] || fail "blue-team-prompt.md 不存在: $BLUE_PROMPT_FILE"
[[ -f "$RED_PROMPT_FILE" ]] || fail "red-team-prompt.md 不存在: $RED_PROMPT_FILE"
[[ -f "$PLUGIN_JSON" ]]     || fail "plugin.json 不存在: $PLUGIN_JSON"
[[ -f "$MARKETPLACE_JSON" ]] || fail "marketplace.json 不存在: $MARKETPLACE_JSON"
[[ -f "$CLAUDE_MD" ]]       || fail "CLAUDE.md 不存在: $CLAUDE_MD"

# ---------------------------------------------------------------------------
# 场景 1：有 coverage 工具项目——Tier 1 与 Tier 5 合并为单次 coverage 执行
# ---------------------------------------------------------------------------

# 场景1.P1 [det-machine]：SKILL.md（或其 reference）声明 Tier 5 coverage 判定
#   复用 Tier 1 的 coverage 产物而非再次执行套件
#   assert: contains 「复用/不二次执行」语义契约文本
#   锚点：同一行含 Tier ?1 且含 复用|不二次执行|不再执行|同一次执行
#   （no-op 时 Tier 1/Tier 5 表述各自独立，无此类复用文本 → FAIL）
REUSE_LINES=$(grep -hE 'Tier ?1' "$SKILL_FILE" "$QUANT_FILE" 2>/dev/null \
    | grep -cE '复用|不二次执行|不再(执行|重跑|运行)|同一次执行' || true)
if [[ "$REUSE_LINES" -lt 1 ]]; then
    fail "场景1.P1: SKILL.md/quantitative-metrics.md 未见「Tier 5 复用 Tier 1 coverage 产物（不二次执行套件）」语义契约文本"
fi
pass "场景1.P1: Tier 5 复用 Tier 1 coverage 产物契约文本存在（$REUSE_LINES 行）"

# 场景1.P2 [det-machine]：tests/acceptance/ 下存在锁定「单次执行/产物复用」契约的断言
#   assert: 存在且断言数 >= 1 针对复用契约
#   锚点：本任务测试文件标记 p0-qa-dedup + 复用锚点（no-op 时无此文件 → FAIL）
P2_FILE_COUNT=$(grep -rlF 'p0-qa-dedup' "$TESTS_DIR" --include='*.acceptance.test.sh' 2>/dev/null \
    | xargs grep -lE '复用|不二次执行|同一次执行' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$P2_FILE_COUNT" -lt 1 ]]; then
    fail "场景1.P2: tests/acceptance/ 下无锁定 coverage 复用契约的验收测试（p0-qa-dedup）"
fi
pass "场景1.P2: 复用契约验收断言存在（$P2_FILE_COUNT 个测试文件）"

# ---------------------------------------------------------------------------
# 场景 2：无 coverage 工具项目——Tier 1 / Tier 5 行为完全不变（降级不变性）
# ---------------------------------------------------------------------------

# 场景2.P1 [det-machine]：SKILL.md（或其 reference）声明无 coverage 工具时
#   Tier 1 / Tier 5 行为与改动前完全一致
#   assert: contains 「无 coverage 工具 → 行为不变/降级」分支契约文本
#   （no-op 时文档无「无 coverage 工具」降级分支表述 → FAIL）
DEGRADE_LINES=$(grep -rhE '(无|未检出|没有) ?coverage ?工具[^。]{0,80}(不变|原样|逐字节|降级)' \
    "$SKILL_FILE" "$REF_DIR" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$DEGRADE_LINES" -lt 1 ]]; then
    fail "场景2.P1: SKILL.md/references/ 未见「无 coverage 工具 → 行为不变/原样/降级」分支契约文本"
fi
pass "场景2.P1: 无 coverage 工具降级分支契约文本存在（$DEGRADE_LINES 行）"

# 场景2.P2 [det-machine]：验收测试含降级路径断言
#   assert: 存在针对无工具分支的断言（本文件即载体；no-op 时无 p0-qa-dedup 标记文件 → FAIL）
DEGRADE_TEST_COUNT=$(grep -rlF 'p0-qa-dedup' "$TESTS_DIR" --include='*.acceptance.test.sh' 2>/dev/null \
    | xargs grep -lE '无 ?coverage ?工具|降级' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$DEGRADE_TEST_COUNT" -lt 1 ]]; then
    fail "场景2.P2: tests/acceptance/ 下无针对无 coverage 工具降级分支的验收断言"
fi
pass "场景2.P2: 降级路径验收断言存在（$DEGRADE_TEST_COUNT 个测试文件）"

# ---------------------------------------------------------------------------
# 场景 3：契约检查并入 qa-reviewer Section D——有契约规约时逐条比对
# ---------------------------------------------------------------------------

# 场景3.P1 [det-machine]：qa-reviewer prompt/reference 定义 Section D 逐条契约
#   比对且每条含 severity
#   assert: contains Section D 定义 ∧ 逐条比对语义 ∧ severity 字段要求
#   锚点（谓词/C2 字面量）：`## Section D: 契约符合性`、`severity=high|medium|low`
SECTION_D_FILES=$(grep -rlF 'Section D: 契约符合性' "$REF_DIR" 2>/dev/null || true)
if [[ -z "$SECTION_D_FILES" ]]; then
    fail "场景3.P1: references/ 下无文件定义「Section D: 契约符合性」"
fi
SECTION_D_FIRST_FILE=$(echo "$SECTION_D_FILES" | head -1)

# 逐条比对语义（逐条/比对/契约符合）
if ! grep -qE '逐条|比对|契约符合' "$SECTION_D_FIRST_FILE"; then
    fail "场景3.P1: $(basename "$SECTION_D_FIRST_FILE") 含 Section D 标题但缺逐条比对语义"
fi
# severity 字段要求（C2 字面量 severity=high|medium|low）
if ! grep -qE 'severity=(high|medium|low)' "$SECTION_D_FIRST_FILE"; then
    fail "场景3.P1: $(basename "$SECTION_D_FIRST_FILE") 含 Section D 标题但缺 severity=high|medium|low 字段要求"
fi
# severity=high 计入 Critical（复用谓词闸门 0 Critical 既有机制）
if ! grep -qF 'Critical' "$SECTION_D_FIRST_FILE"; then
    fail "场景3.P1: $(basename "$SECTION_D_FIRST_FILE") 含 Section D 标题但未规定 severity=high 计入 Critical"
fi
pass "场景3.P1: Section D 定义完整（标题 + 逐条比对 + severity + Critical 联动）于 $(basename "$SECTION_D_FIRST_FILE")"

# 场景3.P2 [det-machine]：验收测试断言 Section D 契约存在（含 severity 要求）
#   锚点：tests/acceptance/ 下含「Section D: 契约符合性」字面量的测试文件（no-op 时无 → FAIL）
SECTION_D_TEST_COUNT=$(grep -rlF 'Section D: 契约符合性' "$TESTS_DIR" --include='*.acceptance.test.sh' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$SECTION_D_TEST_COUNT" -lt 1 ]]; then
    fail "场景3.P2: tests/acceptance/ 下无针对 Section D 格式的验收断言"
fi
pass "场景3.P2: Section D 格式验收断言存在（$SECTION_D_TEST_COUNT 个测试文件）"

# ---------------------------------------------------------------------------
# 场景 4：Section D 的 N/A 分支——无契约要求时输出 N/A
# ---------------------------------------------------------------------------

# 场景4.P1 [det-machine]：contract_required=false 或设计文档无契约规约 → Section D 输出 N/A
#   assert: contains 「N/A」分支规则文本
#   锚点：Section D 定义文件同时含 N/A 与 contract_required=false/缺失/无契约 分支表述
if ! grep -qF 'N/A' "$SECTION_D_FIRST_FILE"; then
    fail "场景4.P1: $(basename "$SECTION_D_FIRST_FILE") 缺 Section D 的 N/A 分支规则"
fi
if ! grep -qE 'contract_required ?= ?false|contract_required 为 false|缺失.{0,30}N/A|无契约' "$SECTION_D_FIRST_FILE"; then
    fail "场景4.P1: $(basename "$SECTION_D_FIRST_FILE") 未规定 contract_required=false/契约缺失 → Section D 输出 N/A 的分支"
fi
pass "场景4.P1: Section D 的 N/A 分支规则存在（contract_required=false/契约缺失 → N/A）"

# ---------------------------------------------------------------------------
# 场景 5：contract-checker 独立 agent 彻底取消（双 negate）
# ---------------------------------------------------------------------------

# 场景5.P1 [det-machine, negate]：plugins/autopilot/skills/ 下全部 md 的
#   contract-checker 委托引用计数 == 0（README.md 历史 changelog 条目豁免——
#   README 不在 skills/ 目录内，本口径天然豁免）
#   no-op 时 SKILL.md 步骤 2.5 / fast 行 / design-modes / state-file-guide /
#   contract-protocol 多处残留 → FAIL
CHECKER_MD_COUNT=$(grep -rn 'contract-checker' "$SKILLS_DIR" --include='*.md' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$CHECKER_MD_COUNT" -ne 0 ]]; then
    echo "--- 残留引用 ---" >&2
    grep -rn 'contract-checker' "$SKILLS_DIR" --include='*.md' 2>/dev/null >&2
    fail "场景5.P1: skills/ 下 md 残留 contract-checker 引用 $CHECKER_MD_COUNT 处（应 == 0）"
fi
pass "场景5.P1: skills/ 下全部 md contract-checker 引用计数 == 0"

# contract-checker-prompt.md 文件本身应删除（并入 qa-reviewer Section D）
if [[ -f "$REF_DIR/contract-checker-prompt.md" ]]; then
    fail "场景5.P1: contract-checker-prompt.md 仍存在（应删除，已并入 qa-reviewer Section D）"
fi
pass "场景5.P1: contract-checker-prompt.md 已删除"

# 场景5.P2 [det-machine, negate]：bash 脚本（stop-hook.sh / setup.sh）中
#   contract-checker 执行路径引用计数 == 0
#   no-op 时 stop-hook.sh fast prompt 短语 / setup.sh 文案残留 → FAIL
CHECKER_SH_COUNT=$(grep -rn 'contract-checker' "$SCRIPTS_DIR" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$CHECKER_SH_COUNT" -ne 0 ]]; then
    echo "--- 残留引用 ---" >&2
    grep -rn 'contract-checker' "$SCRIPTS_DIR" 2>/dev/null >&2
    fail "场景5.P2: scripts/ 残留 contract-checker 执行引用 $CHECKER_SH_COUNT 处（应 == 0）"
fi
pass "场景5.P2: scripts/ contract-checker 执行引用计数 == 0"

# ---------------------------------------------------------------------------
# 场景 6：design 阶段探针产物化——context.md 生成与格式契约
# ---------------------------------------------------------------------------

# 场景6.P1 [det-machine]：SKILL.md（或 design reference）规定编排器把
#   技术栈/测试框架/测试命令/构建命令写入任务目录 context.md 且为四个固定小节
#   assert: contains context.md 文件名 ∧ 四个小节主题全部出现
#   锚点（C1 字面量）：context.md、技术栈、测试框架、测试命令、构建命令
CONTEXT_FILES=$(grep -rlF 'context.md' "$SKILL_FILE" "$REF_DIR" 2>/dev/null || true)
if [[ -z "$CONTEXT_FILES" ]]; then
    fail "场景6.P1: SKILL.md/references/ 无任何文件提及 context.md（探针产物化未落地）"
fi
FOUR_SECTION_FILE=""
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if grep -qF '技术栈' "$f" && grep -qF '测试框架' "$f" \
        && grep -qF '测试命令' "$f" && grep -qF '构建命令' "$f"; then
        FOUR_SECTION_FILE="$f"
        break
    fi
done <<< "$CONTEXT_FILES"
if [[ -z "$FOUR_SECTION_FILE" ]]; then
    fail "场景6.P1: 含 context.md 的文件中无一同时具备四个固定小节（技术栈/测试框架/测试命令/构建命令）"
fi
pass "场景6.P1: context.md 四节契约（技术栈/测试框架/测试命令/构建命令）存在于 $(basename "$FOUR_SECTION_FILE")"

# 场景6.P2 [det-machine]：某探针小节无内容时该节写字面 N/A
#   assert: contains 空节→N/A 规则文本
#   锚点：context.md 契约文件同时含 N/A 规则
if ! grep -qF 'N/A' "$FOUR_SECTION_FILE"; then
    fail "场景6.P2: $(basename "$FOUR_SECTION_FILE") 定义 context.md 四节但缺空节写 N/A 规则"
fi
pass "场景6.P2: context.md 空节 → N/A 规则存在"

# ---------------------------------------------------------------------------
# 场景 7：下游 prompt 统一引用 context.md（跨层级数据流）
# ---------------------------------------------------------------------------

# 场景7.P1 [det-machine]：蓝队/红队/qa-reviewer 三处 prompt 均引用 context.md 路径
#   assert: 三处均 contains context.md 引用（no-op 时三文件均无 → FAIL）
for f in "$BLUE_PROMPT_FILE" "$RED_PROMPT_FILE" "$QA_PROMPT_FILE"; do
    if ! grep -qF 'context.md' "$f"; then
        fail "场景7.P1: $(basename "$f") 未引用 context.md（三处下游 prompt 应统一 Read 探针产物）"
    fi
done
pass "场景7.P1: 蓝队/红队/qa-reviewer 三处 prompt 均引用 context.md"

# 场景7.P2 [det-machine, negate]：三处下游 prompt 不再含独立的
#   「扫描项目发现测试框架/技术栈」指令段落
#   assert: 独立 full-scan 指令段计数 == 0
#   白名单豁免（谓词原文）：「缺项再补充扫描」单句允许存在
#   no-op 时蓝队「先扫描项目的测试框架…」、红队「自行扫描」残留 → FAIL
for f in "$BLUE_PROMPT_FILE" "$RED_PROMPT_FILE" "$QA_PROMPT_FILE"; do
    SCAN_COUNT=$(grep -nE '自行扫描|先扫描项目|扫描项目.{0,20}(发现|测试框架|技术栈)' "$f" 2>/dev/null \
        | grep -vF '缺项再补充扫描' | wc -l | tr -d ' ')
    if [[ "$SCAN_COUNT" -ne 0 ]]; then
        echo "--- 残留自扫描指令段（$(basename "$f")） ---" >&2
        grep -nE '自行扫描|先扫描项目|扫描项目.{0,20}(发现|测试框架|技术栈)' "$f" 2>/dev/null \
            | grep -vF '缺项再补充扫描' >&2
        fail "场景7.P2: $(basename "$f") 残留独立自扫描指令段 $SCAN_COUNT 处（应 == 0，白名单仅豁免「缺项再补充扫描」单句）"
    fi
done
pass "场景7.P2: 三处 prompt 独立自扫描指令段计数 == 0（豁免「缺项再补充扫描」单句）"

# ---------------------------------------------------------------------------
# 场景 8：版本升级 v3.63.0 四处同步（C4：plugin.json / marketplace.json /
#         CLAUDE.md 三处 == 3.63.0；package.json 实证不存在，vacuously true）
# ---------------------------------------------------------------------------

# 场景8.P1 [det-machine]：plugin.json version == "3.63.0"
#   （no-op 时为 3.62.0 → FAIL）
if ! grep -qF '"3.63.0"' "$PLUGIN_JSON"; then
    fail "场景8.P1: plugin.json version 字段不含 \"3.63.0\""
fi
pass "场景8.P1: plugin.json version == 3.63.0"

# 场景8.P2 [det-machine]：marketplace.json autopilot 条目 version == "3.63.0"
#   ∧ marketplace.json 与 plugin.json 的 description 均不残留 contract-checker 活文案
#   （no-op 时 marketplace autopilot 条目为 3.62.0 且 description 含 contract-checker → FAIL）
if ! grep -qF '"3.63.0"' "$MARKETPLACE_JSON"; then
    fail "场景8.P2: marketplace.json autopilot 条目不含 \"3.63.0\""
fi
pass "场景8.P2: marketplace.json autopilot 条目 version == 3.63.0"

for jf in "$PLUGIN_JSON" "$MARKETPLACE_JSON"; do
    DESC_LINE_COUNT=$(grep -c '"description"' "$jf" || true)
    if [[ "$DESC_LINE_COUNT" -lt 1 ]]; then
        fail "场景8.P2: $(basename "$jf") 未找到 description 字段（断言口径失效）"
    fi
    DESC_CHECKER_COUNT=$(grep '"description"' "$jf" | grep -c 'contract-checker' || true)
    if [[ "$DESC_CHECKER_COUNT" -ne 0 ]]; then
        fail "场景8.P2: $(basename "$jf") description 残留 contract-checker 活文案 $DESC_CHECKER_COUNT 处（应 == 0）"
    fi
done
pass "场景8.P2: plugin.json / marketplace.json description 均无 contract-checker 活文案"

# 场景8.P3 [det-machine]：CLAUDE.md 插件索引表 autopilot 行标注 v3.63.0
#   锚点：含 [autopilot](plugins/autopilot/) 链接的表格行须含 v3.63.0
#   （no-op 时为 v3.62.0 → FAIL）
AUTOPILOT_ROW=$(grep -F '[autopilot](plugins/autopilot/)' "$CLAUDE_MD" || true)
if [[ -z "$AUTOPILOT_ROW" ]]; then
    fail "场景8.P3: CLAUDE.md 插件索引表未找到 autopilot 行（断言口径失效）"
fi
if ! echo "$AUTOPILOT_ROW" | grep -qF 'v3.63.0'; then
    fail "场景8.P3: CLAUDE.md 插件索引 autopilot 行未标注 v3.63.0"
fi
pass "场景8.P3: CLAUDE.md 插件索引 autopilot 行 == v3.63.0"

# ---------------------------------------------------------------------------
# 场景 10：smoke 路径契约校验保留（质量闸门不动）
# ---------------------------------------------------------------------------

# 场景10.P1 [det-machine]：qa_scope=smoke ∧ contract_required=true 时
#   SKILL.md 规定 qa-reviewer 审查范围包含 Section D
#   assert: qa_scope smoke 表述行 contains "Section D"
#   （no-op 时 smoke 行为「Section A 关键项 + OWASP」，无 Section D → FAIL）
SMOKE_SECTION_D_COUNT=$(grep -i 'smoke' "$SKILL_FILE" | grep -c 'Section D' || true)
if [[ "$SMOKE_SECTION_D_COUNT" -lt 1 ]]; then
    fail "场景10.P1: SKILL.md smoke 表述行不含 Section D（smoke 路径契约校验丢失，违反质量闸门不动）"
fi
pass "场景10.P1: SKILL.md smoke 行保留 Section D 契约校验（$SMOKE_SECTION_D_COUNT 行）"

echo "[OK ] R_QA_DEDUP p0-qa-dedup — 全部断言通过（场景 1/2/3/4/5/6/7/8/10）"
exit 0
