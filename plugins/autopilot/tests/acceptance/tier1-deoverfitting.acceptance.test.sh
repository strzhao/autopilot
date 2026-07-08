#!/usr/bin/env bash
# Tier1 去过拟合反面案例：验收级测试
# 红队（验证者）脚本 — 断言全部来自设计意图，不读蓝队实现文件推导期望值。
#
# 谓词来源：Tier 1 AI-First 反过拟合「纯减法」编辑验收谓词（9 条）
#
# 覆盖谓词：
#   正向（编辑必须生效）：P1 P2 P3 P4 P5 P6 P7
#   护栏（合理规则未被误伤）：P8 P9
#
# 失败策略：任一 check 失败 → 累计 fail 计数；结尾 exit 1（有失败）或 exit 0（全通过）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SKILL_DIR="$REPO_ROOT/plugins/autopilot/skills/autopilot"
REF_DIR="$SKILL_DIR/references"

PLAN_REVIEWER="$REF_DIR/plan-reviewer-prompt.md"
QA_REVIEWER="$REF_DIR/qa-reviewer-prompt.md"
SKILL_MD="$SKILL_DIR/SKILL.md"
DESIGN_MODES="$REF_DIR/design-modes.md"
IMPLEMENT_PHASE="$REF_DIR/implement-phase.md"
AUTO_FIX_PHASE="$REF_DIR/auto-fix-phase.md"
RED_TEAM_PROMPT="$REF_DIR/red-team-prompt.md"

FAILS=0

fail() {
    echo "[FAIL] $1" >&2
    FAILS=$((FAILS + 1))
}

pass() {
    echo "[PASS] $1"
}

# ── 前置：目标文件必须存在 ────────────────────────────────────────────────────
for f in \
    "$PLAN_REVIEWER" \
    "$QA_REVIEWER" \
    "$SKILL_MD" \
    "$DESIGN_MODES" \
    "$IMPLEMENT_PHASE" \
    "$AUTO_FIX_PHASE" \
    "$RED_TEAM_PROMPT"; do
    if [[ ! -f "$f" ]]; then
        fail "前置：目标文件不存在: $f"
    fi
done

# ── P1：plan-reviewer-prompt.md 不含伪精度数字 ───────────────────────────────
# 谓词：grep -nE '≥91|（≥91）|\(≥91\)|80-90（重要）|91-100（BLOCKER）' 应无匹配
echo ""
echo "--- P1: plan-reviewer-prompt.md 不含伪精度数字 ---"
if [[ -f "$PLAN_REVIEWER" ]]; then
    # 单独检查每个伪精度模式
    PSEUDO_PATTERNS=('≥91' '（≥91）' '\(≥91\)' '80-90（重要）' '91-100（BLOCKER）')
    P1_FAIL=0
    for pat in "${PSEUDO_PATTERNS[@]}"; do
        matched=$(grep -nE "$pat" "$PLAN_REVIEWER" 2>/dev/null || true)
        if [[ -n "$matched" ]]; then
            fail "P1: plan-reviewer-prompt.md 仍含伪精度数字模式「${pat}」，命中行：$matched"
            P1_FAIL=1
        fi
    done
    if [[ $P1_FAIL -eq 0 ]]; then
        pass "P1: plan-reviewer-prompt.md 不含伪精度数字（≥91 / 80-90（重要）/ 91-100（BLOCKER） 均已清除）"
    fi
else
    fail "P1: $PLAN_REVIEWER 不存在，无法检查"
fi

# ── P2：plan-reviewer-prompt.md 中 BLOCKER 出现次数 ≥3 ──────────────────────
# 谓词：行为锚点保留；<3 = FAIL
echo ""
echo "--- P2: plan-reviewer-prompt.md 含 BLOCKER ≥3 次 ---"
if [[ -f "$PLAN_REVIEWER" ]]; then
    blocker_count=$(grep -c "BLOCKER" "$PLAN_REVIEWER" 2>/dev/null || echo 0)
    if [[ "$blocker_count" -lt 3 ]]; then
        fail "P2: plan-reviewer-prompt.md BLOCKER 出现 ${blocker_count} 次 < 3，行为锚点被误删（<3=FAIL）"
    else
        pass "P2: plan-reviewer-prompt.md BLOCKER 出现 ${blocker_count} 次 ≥3，行为锚点保留"
    fi
else
    fail "P2: $PLAN_REVIEWER 不存在，无法检查"
fi

# ── P3：plan-reviewer-prompt.md 含「契约完整性」且含「Mutation-Survival」──────
# 谓词：维度未丢；缺=FAIL
echo ""
echo "--- P3: plan-reviewer-prompt.md 含「契约完整性」且含「Mutation-Survival」 ---"
if [[ -f "$PLAN_REVIEWER" ]]; then
    P3_FAIL=0
    if ! grep -q "契约完整性" "$PLAN_REVIEWER" 2>/dev/null; then
        fail "P3: plan-reviewer-prompt.md 缺少「契约完整性」，维度被误删"
        P3_FAIL=1
    fi
    if ! grep -q "Mutation-Survival" "$PLAN_REVIEWER" 2>/dev/null; then
        fail "P3: plan-reviewer-prompt.md 缺少「Mutation-Survival」，维度被误删"
        P3_FAIL=1
    fi
    if [[ $P3_FAIL -eq 0 ]]; then
        pass "P3: plan-reviewer-prompt.md 含「契约完整性」和「Mutation-Survival」，维度完整"
    fi
else
    fail "P3: $PLAN_REVIEWER 不存在，无法检查"
fi

# ── P4：plan-reviewer-prompt.md 不含「子任务 ≤8」，且含「范围蔓延」 ───────────
# 谓词：子任务数量阈值（规则脚本）已删，范围蔓延（AI语义判断）保留；任一不满足=FAIL
echo ""
echo "--- P4: plan-reviewer-prompt.md 不含「子任务 ≤8」，且含「范围蔓延」 ---"
if [[ -f "$PLAN_REVIEWER" ]]; then
    P4_FAIL=0
    if grep -q "子任务 ≤8" "$PLAN_REVIEWER" 2>/dev/null; then
        fail "P4: plan-reviewer-prompt.md 仍含「子任务 ≤8」，伪精度阈值未清除"
        P4_FAIL=1
    fi
    if ! grep -q "范围蔓延" "$PLAN_REVIEWER" 2>/dev/null; then
        fail "P4: plan-reviewer-prompt.md 缺少「范围蔓延」，AI 语义判断锚点被误删"
        P4_FAIL=1
    fi
    if [[ $P4_FAIL -eq 0 ]]; then
        pass "P4: plan-reviewer-prompt.md 不含「子任务 ≤8」，且含「范围蔓延」"
    fi
else
    fail "P4: $PLAN_REVIEWER 不存在，无法检查"
fi

# ── P5：qa-reviewer-prompt.md 不含「≥30%」，含「语义判断为准」，
#        且三类反模式标题各自仍存在 ──────────────────────────────────────────────
# 谓词：≥30% 伪精度已删；AI 语义判断锚点保留；反模式三标题不能丢；任一不满足=FAIL
echo ""
echo "--- P5: qa-reviewer-prompt.md 反过拟合检查 ---"
if [[ -f "$QA_REVIEWER" ]]; then
    P5_FAIL=0
    if grep -q "≥30%" "$QA_REVIEWER" 2>/dev/null; then
        fail "P5: qa-reviewer-prompt.md 仍含「≥30%」伪精度数字"
        P5_FAIL=1
    fi
    if ! grep -q "语义判断为准" "$QA_REVIEWER" 2>/dev/null; then
        fail "P5: qa-reviewer-prompt.md 缺少「语义判断为准」，AI 语义判断锚点被误删"
        P5_FAIL=1
    fi
    for title in "宽容跳过模式" "缺失断言" "Tautological"; do
        if ! grep -q "$title" "$QA_REVIEWER" 2>/dev/null; then
            fail "P5: qa-reviewer-prompt.md 缺少反模式标题「${title}」"
            P5_FAIL=1
        fi
    done
    if [[ $P5_FAIL -eq 0 ]]; then
        pass "P5: qa-reviewer-prompt.md 不含≥30%，含语义判断为准，三类反模式标题完整"
    fi
else
    fail "P5: $QA_REVIEWER 不存在，无法检查"
fi

# ── P6：SKILL.md 不含「最多 3 个」且不含「少于 5 个文件」，含「自行决定」；
#        design-modes.md 仍含「1 个 Explore agent 快速分析」 ────────────────────
# 谓词：Auto-Approve 路径反向护栏；任一不满足=FAIL
echo ""
echo "--- P6: SKILL.md 与 design-modes.md Auto-Approve 路径护栏 ---"
P6_FAIL=0
if [[ -f "$SKILL_MD" ]]; then
    # 用「（最多 3 个）」精确匹配 Explore agent 旧计数措辞，
    # 避免误命中 L77 知识加载配置「最多 3 个文件」（范围外，应保留）
    if grep -q "（最多 3 个）" "$SKILL_MD" 2>/dev/null; then
        fail "P6: SKILL.md 仍含 Explore 计数旧措辞「（最多 3 个）」，伪精度阈值未清除"
        P6_FAIL=1
    fi
    if grep -q "少于 5 个文件" "$SKILL_MD" 2>/dev/null; then
        fail "P6: SKILL.md 仍含「少于 5 个文件」，伪精度阈值未清除"
        P6_FAIL=1
    fi
    if ! grep -q "自行决定" "$SKILL_MD" 2>/dev/null; then
        fail "P6: SKILL.md 缺少「自行决定」，AI 判断授权锚点被误删"
        P6_FAIL=1
    fi
else
    fail "P6: $SKILL_MD 不存在，无法检查"
    P6_FAIL=1
fi

if [[ -f "$DESIGN_MODES" ]]; then
    if ! grep -q "1 个 Explore agent 快速分析" "$DESIGN_MODES" 2>/dev/null; then
        fail "P6: design-modes.md 缺少「1 个 Explore agent 快速分析」，Auto-Approve 路径反向护栏被误删"
        P6_FAIL=1
    fi
else
    fail "P6: $DESIGN_MODES 不存在，无法检查"
    P6_FAIL=1
fi
if [[ $P6_FAIL -eq 0 ]]; then
    pass "P6: SKILL.md 不含伪精度阈值，含自行决定；design-modes.md Auto-Approve 路径护栏完整"
fi

# ── P7：implement-phase.md 与 auto-fix-phase.md 均不含「| 借口 | 现实 |」，
#        且两文件均含「anti-rationalization」 ────────────────────────────────────
# 谓词：表格式借口现实对比已删，anti-rationalization 纯文字锚点保留；任一不满足=FAIL
echo ""
echo "--- P7: implement-phase.md 与 auto-fix-phase.md anti-rationalization 检查 ---"
P7_FAIL=0
for f_label in "$IMPLEMENT_PHASE:implement-phase.md" "$AUTO_FIX_PHASE:auto-fix-phase.md"; do
    f="${f_label%%:*}"
    label="${f_label##*:}"
    if [[ -f "$f" ]]; then
        if grep -q "| 借口 | 现实 |" "$f" 2>/dev/null; then
            fail "P7: $label 仍含「| 借口 | 现实 |」表格，应已删除"
            P7_FAIL=1
        fi
        if ! grep -q "anti-rationalization" "$f" 2>/dev/null; then
            fail "P7: $label 缺少「anti-rationalization」，关键锚点被误删"
            P7_FAIL=1
        fi
    else
        fail "P7: $f 不存在，无法检查"
        P7_FAIL=1
    fi
done
if [[ $P7_FAIL -eq 0 ]]; then
    pass "P7: implement-phase.md 与 auto-fix-phase.md 均不含「| 借口 | 现实 |」，且均含 anti-rationalization"
fi

# ── P8：护栏 — 信息隔离铁律、终止边界未被误伤 ──────────────────────────────────
# 谓词：
#   - red-team-prompt.md 含「绝对不能」且含「实现代码」（或「只看设计」）
#   - auto-fix-phase.md 仍含「默认不允许修改红队验收测试」
#   - SKILL.md 仍含「最多 2 轮」（终止边界本次故意不动）
echo ""
echo "--- P8: 护栏 — 信息隔离铁律 + 终止边界未被误伤 ---"
P8_FAIL=0
if [[ -f "$RED_TEAM_PROMPT" ]]; then
    if ! grep -q "绝对不能" "$RED_TEAM_PROMPT" 2>/dev/null; then
        fail "P8: red-team-prompt.md 缺少「绝对不能」，信息隔离铁律被误删"
        P8_FAIL=1
    fi
    # 「实现代码」或「只看设计」二者满足其一即可
    if ! grep -q "实现代码" "$RED_TEAM_PROMPT" 2>/dev/null && \
       ! grep -q "只看设计" "$RED_TEAM_PROMPT" 2>/dev/null; then
        fail "P8: red-team-prompt.md 缺少「实现代码」和「只看设计」，信息隔离铁律被误删（需满足其一）"
        P8_FAIL=1
    fi
else
    fail "P8: $RED_TEAM_PROMPT 不存在，无法检查"
    P8_FAIL=1
fi

if [[ -f "$AUTO_FIX_PHASE" ]]; then
    if ! grep -q "默认不允许修改红队验收测试" "$AUTO_FIX_PHASE" 2>/dev/null; then
        fail "P8: auto-fix-phase.md 缺少「默认不允许修改红队验收测试」，红队保护护栏被误删（默认禁+例外语义）"
        P8_FAIL=1
    fi
else
    fail "P8: $AUTO_FIX_PHASE 不存在，无法检查"
    P8_FAIL=1
fi

if [[ -f "$SKILL_MD" ]]; then
    if ! grep -q "最多 2 轮" "$SKILL_MD" 2>/dev/null; then
        fail "P8: SKILL.md 缺少「最多 2 轮」，终止边界被误删（本次故意不动）"
        P8_FAIL=1
    fi
else
    fail "P8: $SKILL_MD 不存在，无法检查"
    P8_FAIL=1
fi
if [[ $P8_FAIL -eq 0 ]]; then
    pass "P8: 信息隔离铁律（red-team-prompt.md）+ 红队保护（auto-fix-phase.md）+ 终止边界（SKILL.md 最多 2 轮）护栏完整"
fi

# ── P9：无断链 — 被编辑文件中所有 references/xxx.md 引用目标均存在 ───────────────
# 谓词：对上述被编辑文件，grep 出 references/xxx.md 引用，逐一确认目标存在
echo ""
echo "--- P9: 无断链 — references/xxx.md 引用一致性检查 ---"
P9_FAIL=0

# 被编辑的 6 个目标文件（只检查这些文件里的引用）
EDITED_FILES=(
    "$PLAN_REVIEWER"
    "$QA_REVIEWER"
    "$SKILL_MD"
    "$DESIGN_MODES"
    "$IMPLEMENT_PHASE"
    "$AUTO_FIX_PHASE"
)

for f in "${EDITED_FILES[@]}"; do
    [[ ! -f "$f" ]] && continue
    # 提取所有形如 references/xxx.md 的引用（允许相对路径前缀变体）
    # 同时兼容 ./references/xxx.md 和 references/xxx.md
    while IFS= read -r ref_path; do
        # 规范化：剥到最后一个 references/ 之后，兼容裸「references/x.md」与「./references/x.md」「../references/x.md」
        ref_rel="${ref_path##*references/}"
        target="$REF_DIR/$ref_rel"
        if [[ ! -f "$target" ]]; then
            fail "P9: 断链检测 — 文件 $(basename "$f") 引用 references/${ref_rel}，但目标不存在: $target"
            P9_FAIL=1
        fi
    done < <(grep -oE '(\.?\.?/?references/[a-zA-Z0-9_.-]+\.md)' "$f" 2>/dev/null | sort -u || true)
done

if [[ $P9_FAIL -eq 0 ]]; then
    pass "P9: 所有 references/xxx.md 引用均无断链"
fi

# ── 汇总 ─────────────────────────────────────────────────────────────────────
echo ""
echo "============================================"
if [[ $FAILS -eq 0 ]]; then
    echo " [OK] tier1-deoverfitting 全部 9 条谓词通过"
    echo "============================================"
    exit 0
else
    echo " [FAIL] tier1-deoverfitting: $FAILS 条谓词失败（详见上方 FAIL 行）"
    echo "============================================"
    exit 1
fi
