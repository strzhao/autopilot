#!/usr/bin/env bash
# knowledge-inbox 协议锁测试
# 锁 knowledge inbox 收件箱零冲突机制的关键协议文案：
#   T1  写侧禁写聚合层（任意会话只写 inbox/ 独立新文件）
#   T2  inbox 文件名契约（YYYY-MM-DD-<slug>.md / slug 字符集与长度 / -2 递增）
#   T3  主检出侧判定（.git 为目录可收编；worktree .git 为文件永不收编）
#   T4  收编步骤（触发 ≥1 → 语义合并 → 重建 index ≤100 行 → 删已收编文件）
#   T5  union 冲突处置（同日同 slug 撞名：两文件都保留、其一改名，禁丢弃任侧）
#   T6  两跳消费文案（SKILL.md 步骤 0 + plan-reviewer 维度 9 + Consumption Rules）
#   T7  doctor inbox 积压阈值（>10 提醒收编）
#   T8  decisions 禁手工全局序号（含防并行撞号动机）
#   T9  错误契约三句（tags 2-5 / mkdir -p / union 两文件都保留）
#   T10 残余风险豁免援引（prose-iron-law-to-hook）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SKILL_MD="$REPO_ROOT/plugins/autopilot/skills/autopilot/SKILL.md"
KE_MD="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/knowledge-engineering.md"
PR_MD="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/plan-reviewer-prompt.md"
DOCTOR_MD="$REPO_ROOT/plugins/autopilot/skills/autopilot-doctor/SKILL.md"

PASS_COUNT=0
FAIL_COUNT=0
fail() { echo "[FAIL] knowledge-inbox: $1" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }
pass() { echo "[PASS] knowledge-inbox: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }

for f in "$SKILL_MD" "$KE_MD" "$PR_MD" "$DOCTOR_MD"; do
    [[ -f "$f" ]] || { echo "[FATAL] knowledge-inbox: 目标文件不存在: $f" >&2; exit 1; }
done

# ── T1 写侧禁写聚合层 ──────────────────────────────────────────────────
if grep -qF '禁止直接写聚合层' "$KE_MD" && grep -qF '.autopilot/knowledge/inbox/' "$SKILL_MD"; then
    pass "T1 写侧只写 inbox/ 独立新文件、禁直写聚合层（KE + SKILL.md）"
else
    fail "T1 缺写侧禁令（KE.md 禁直写聚合层 / SKILL.md inbox 写目标）"
fi

# ── T2 inbox 文件名契约 ────────────────────────────────────────────────
if grep -qF 'YYYY-MM-DD-<slug>.md' "$KE_MD" \
    && grep -qF '[a-z0-9-]' "$KE_MD" \
    && grep -qF '≤40 字符' "$KE_MD" \
    && grep -qF '递增' "$KE_MD" && grep -qF -- '-2' "$KE_MD"; then
    pass "T2 文件名契约：YYYY-MM-DD-<slug>.md + slug [a-z0-9-] ≤40 + 同名 -2 递增"
else
    fail "T2 文件名契约缺失（格式 / slug 约束 / -2 递增）"
fi

# ── T3 主检出侧判定（场景：.git 目录=主检出可收编；.git 文件=worktree 永不收编）──
if grep -qF '`.git` 是目录' "$KE_MD" && grep -qF '`.git` 是文件' "$KE_MD" \
    && grep -qF '永不收编' "$KE_MD"; then
    pass "T3 收编主体判据 = .git 是目录；worktree（.git 是文件）永不收编"
else
    fail "T3 收编主体判据 / worktree 禁止语义缺失"
fi

# ── T4 收编步骤 ────────────────────────────────────────────────────────
if grep -qF 'Collection Protocol' "$KE_MD" \
    && grep -qF '≥ 1' "$KE_MD" \
    && grep -qF '重建' "$KE_MD" \
    && grep -qF '删除已收编' "$KE_MD" \
    && grep -qF '≤100 行' "$KE_MD"; then
    pass "T4 收编步骤：触发（inbox ≥1）→ 语义合并 → 重建 index（≤100 行）→ 删已收编文件"
else
    fail "T4 收编步骤文案缺失（触发/合并/重建/删除）"
fi

# ── T5 union 冲突处置（含同日同 slug 跨分支撞名）────────────────────────
if grep -qF '两侧条目都保留' "$KE_MD" && grep -qF '禁丢弃任侧' "$KE_MD" \
    && grep -qF '撞名' "$KE_MD" && grep -qiF 'union' "$KE_MD"; then
    pass "T5 union 处置：撞名两文件都保留、其一改名，禁丢弃任侧"
else
    fail "T5 union 冲突处置文案缺失（撞名/改名/保留双侧）"
fi

# ── T6 两跳消费文案（design 步骤 0 与 plan-reviewer 盲区对照两处）────────
if grep -qE '两跳发现.*inbox' "$SKILL_MD" \
    && grep -qF 'inbox' "$PR_MD" && grep -qF '两跳发现' "$PR_MD" \
    && grep -qF '两跳' "$KE_MD"; then
    pass "T6 两跳消费：SKILL.md 步骤 0 + plan-reviewer 维度 9 + Consumption Rules 均有 inbox 列举发现"
else
    fail "T6 两跳消费文案缺失（SKILL.md 步骤 0 / plan-reviewer 维度 9 / KE.md）"
fi

# ── T7 doctor inbox 积压阈值 ──────────────────────────────────────────
if grep -qF 'inbox' "$DOCTOR_MD" && grep -qE '> ?10' "$DOCTOR_MD"; then
    pass "T7 doctor Dim 12 inbox 积压计数信号（>10 提醒收编）"
else
    fail "T7 doctor 缺 inbox 积压阈值（>10）信号"
fi

# ── T8 禁手工全局序号（含防并行撞号动机）────────────────────────────────
if grep -qF '禁止手工维护全局序号' "$KE_MD" && grep -qF '撞号' "$KE_MD"; then
    pass "T8 decisions 条目禁手工全局序号 + 防并行撞号动机"
else
    fail "T8 禁序号句 / 撞号动机缺失"
fi

# ── T9 错误契约三句（tags 2-5 / mkdir -p / union 保留双侧）──────────────
if grep -qF '2-5' "$KE_MD" && grep -qF 'mkdir -p' "$KE_MD" \
    && grep -qF '两侧条目都保留' "$KE_MD"; then
    pass "T9 错误契约三句：tags 2-5 个 / inbox 不存在 mkdir -p / 冲突 union 两文件都保留"
else
    fail "T9 错误契约三句缺失（tags 2-5 / mkdir -p / union 保留双侧）"
fi

# ── T10 残余风险豁免援引 ──────────────────────────────────────────────
if grep -qF 'prose-iron-law-to-hook' "$KE_MD"; then
    pass "T10 残余风险显式记录并援引 [2026-06-02] prose-iron-law-to-hook 决策"
else
    fail "T10 残余风险豁免援引缺失（prose-iron-law-to-hook）"
fi

echo ""
echo "─────────────────────────────────────────"
echo "knowledge-inbox 汇总: PASS=$PASS_COUNT FAIL=$FAIL_COUNT"
echo "─────────────────────────────────────────"
[[ $FAIL_COUNT -gt 0 ]] && exit 1
exit 0
