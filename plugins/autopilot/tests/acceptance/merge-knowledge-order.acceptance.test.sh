#!/usr/bin/env bash
# Merge phase knowledge-order contract test
# 锁 commit/知识沉淀顺序前置 + 净减行 + worktree 兜底契约
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../" && pwd)"
SKILL_MD="$REPO_ROOT/plugins/autopilot/skills/autopilot/SKILL.md"
KE_MD="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/knowledge-engineering.md"
MP_MD="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/merge-phase.md"

PASS_COUNT=0
FAIL_COUNT=0
fail() { echo "[FAIL] merge-knowledge-order: $1" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }
pass() { echo "[PASS] merge-knowledge-order: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }

# P1: 知识提取与沉淀步骤在 commit Agent 步骤之前（均在 Phase: merge 内）
mline=$(grep -n '^## Phase: merge' "$SKILL_MD" | head -1 | cut -d: -f1 || true)
kline=$(grep -n '^#### 1\. 知识提取与沉淀' "$SKILL_MD" | head -1 | cut -d: -f1 || true)
cline=$(grep -n '^#### 3\. 调用 commit Agent' "$SKILL_MD" | head -1 | cut -d: -f1 || true)
mline=${mline:-0}; kline=${kline:-0}; cline=${cline:-0}
if [[ "$kline" -eq 0 || "$cline" -eq 0 ]]; then
  fail "P1 未找到知识提取或 commit Agent 步骤"
elif [[ "$kline" -gt "$mline" && "$kline" -lt "$cline" ]]; then
  pass "P1 知识提取步骤在 commit Agent 步骤之前"
else
  fail "P1 顺序错误：knowledge=$kline, commit=$cline"
fi

# P2: knowledge-engineering.md 不再以 commit 后为提取时机
if grep -qF 'After autopilot-commit completes' "$KE_MD"; then
  fail "P2 knowledge-engineering.md 仍含 After autopilot-commit completes"
else
  pass "P2 knowledge-engineering.md 已删 After autopilot-commit completes"
fi

# P3: 旧 Worktree-Aware 立即提交脚本章节已删除
if grep -q '^## Worktree-Aware Extraction' "$KE_MD"; then
  fail "P3 knowledge-engineering.md 仍含 Worktree-Aware Extraction 旧提交脚本章节"
else
  pass "P3 knowledge-engineering.md 已删 Worktree-Aware Extraction 旧提交脚本章节"
fi

# P4: SKILL.md 不再声明知识库单独 commit
if grep -qF '单独 git commit' "$SKILL_MD"; then
  fail "P4 SKILL.md 仍含单独 git commit"
else
  pass "P4 SKILL.md 已删单独 git commit"
fi

# P5 已删除（[2026-09-07] 断言机制错适配，用户批准）：原断言「stop-hook.sh 无未提交改动」
# 读工作区 git 状态做历史任务的一次性自证，任何后续任务未提交改动 stop-hook.sh 即假阳性
#（p0-qa-dedup 实证）。实质不变量由 P3/P4/P6/P7 承载。

# P6: 五文件合计行数净减（基线 999）
total=$(cat \
  "$SKILL_MD" \
  "$MP_MD" \
  "$KE_MD" \
  "$REPO_ROOT/plugins/autopilot/skills/autopilot/references/commit-agent-prompt.md" \
  "$REPO_ROOT/plugins/autopilot/skills/autopilot/references/phase-checklists.md" \
  | wc -l | tr -d ' ')
if [[ "$total" -lt 999 ]]; then
  pass "P6 五文件合计 $total 行 < 999"
else
  fail "P6 五文件合计 $total 行，未净减"
fi

# P7: worktree 兜底逻辑存在
if grep -q 'symlink' "$KE_MD" && grep -q 'git status --porcelain' "$KE_MD"; then
  pass "P7 worktree 兜底逻辑存在（symlink + git status --porcelain）"
else
  fail "P7 worktree 兜底逻辑缺失"
fi

echo ""
echo "─────────────────────────────────────────"
echo "merge-knowledge-order 汇总: PASS=$PASS_COUNT FAIL=$FAIL_COUNT"
echo "─────────────────────────────────────────"
[[ $FAIL_COUNT -gt 0 ]] && exit 1
exit 0
