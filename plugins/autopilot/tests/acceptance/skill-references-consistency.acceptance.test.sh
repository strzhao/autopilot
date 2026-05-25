#!/usr/bin/env bash
# R3: 验证 SKILL.md 引用一致性 + anti-rationalization.md 抽离
# 红队测试 — 仅基于设计文档
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SKILL_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/SKILL.md"
ANTI_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/anti-rationalization.md"

fail() {
    echo "[FAIL] R3: $1" >&2
    exit 1
}

pass() {
    echo "[PASS] R3: $1"
}

# 前置：SKILL.md 存在
[[ -f "$SKILL_FILE" ]] || fail "SKILL.md 不存在: $SKILL_FILE"

# 断言 1：SKILL.md 引用 qa-reviewer-prompt.md
qa_ref_count=$(grep -c "references/qa-reviewer-prompt.md" "$SKILL_FILE" || true)
if [[ "$qa_ref_count" -lt 1 ]]; then
    fail "SKILL.md 应至少引用一次 references/qa-reviewer-prompt.md（找到 $qa_ref_count 次）"
fi
pass "SKILL.md 引用 qa-reviewer-prompt.md ($qa_ref_count 次)"

# 断言 2：SKILL.md 引用 anti-rationalization.md
anti_ref_count=$(grep -c "references/anti-rationalization.md" "$SKILL_FILE" || true)
if [[ "$anti_ref_count" -lt 1 ]]; then
    fail "SKILL.md 应至少引用一次 references/anti-rationalization.md（找到 $anti_ref_count 次）"
fi
pass "SKILL.md 引用 anti-rationalization.md ($anti_ref_count 次)"

# 断言 3：qa 阶段段落不再引用旧的两个 prompt 文件
# 提取从「## Phase: qa」到下一个「## Phase:」之间的内容
QA_SECTION=$(awk '
    /^## Phase: *qa/ { in_qa=1; print; next }
    in_qa && /^## Phase:/ && !/^## Phase: *qa/ { in_qa=0 }
    in_qa { print }
' "$SKILL_FILE")

if [[ -z "$QA_SECTION" ]]; then
    # 兼容大小写或其他 phase 标题写法
    QA_SECTION=$(awk '
        /^##.*[Pp]hase.*qa/ { in_qa=1; print; next }
        in_qa && /^##.*[Pp]hase/ && !/qa/ { in_qa=0 }
        in_qa { print }
    ' "$SKILL_FILE")
fi

if [[ -z "$QA_SECTION" ]]; then
    fail "无法从 SKILL.md 定位 qa 阶段段落（找不到 '## Phase: qa' 或类似标题）"
fi

# 在 qa 段落内 grep 旧 prompt 文件名
old_design_in_qa=$(echo "$QA_SECTION" | grep -c "design-reviewer-prompt.md" || true)
old_quality_in_qa=$(echo "$QA_SECTION" | grep -c "code-quality-reviewer-prompt.md" || true)

if [[ "$old_design_in_qa" -gt 0 ]]; then
    fail "qa 阶段段落不应再引用 design-reviewer-prompt.md（仍找到 $old_design_in_qa 次），主流程应只引用合并后的 qa-reviewer-prompt.md"
fi
if [[ "$old_quality_in_qa" -gt 0 ]]; then
    fail "qa 阶段段落不应再引用 code-quality-reviewer-prompt.md（仍找到 $old_quality_in_qa 次），主流程应只引用合并后的 qa-reviewer-prompt.md"
fi
pass "qa 阶段段落不再引用旧的 design-reviewer / code-quality-reviewer prompt"

# 断言 4：SKILL.md 总行数 < 615
# v3.36 Tier 5 量化指标引入，预留 ~10 行空间
total_lines=$(wc -l < "$SKILL_FILE" | tr -d ' ')
if [[ "$total_lines" -ge 615 ]]; then
    fail "SKILL.md 行数 $total_lines >= 615，防合理化指南未有效抽离（v3.36 阈值 615，预留 Tier 5 ~10 行空间）"
fi
pass "SKILL.md 行数 $total_lines < 615"

# 断言 5：anti-rationalization.md 存在且包含三阶段标识
[[ -f "$ANTI_FILE" ]] || fail "anti-rationalization.md 不存在: $ANTI_FILE"

# 三阶段：implement / qa / auto-fix（接受中英文/相近关键词）
has_implement=0
has_qa=0
has_autofix=0
if grep -qiE "implement|实现" "$ANTI_FILE"; then has_implement=1; fi
if grep -qiE "(^|[^a-z])qa([^a-z]|$)|质量审查|质量评审" "$ANTI_FILE"; then has_qa=1; fi
if grep -qiE "auto[-_ ]?fix|自动修复" "$ANTI_FILE"; then has_autofix=1; fi

if [[ $has_implement -eq 0 ]]; then
    fail "anti-rationalization.md 缺少 implement / 实现 阶段标识"
fi
if [[ $has_qa -eq 0 ]]; then
    fail "anti-rationalization.md 缺少 qa / 质量审查 阶段标识"
fi
if [[ $has_autofix -eq 0 ]]; then
    fail "anti-rationalization.md 缺少 auto-fix / 自动修复 阶段标识"
fi
pass "anti-rationalization.md 包含三阶段（implement / qa / auto-fix）"

# 断言 6：SKILL.md merge 阶段段落必须包含 next_task（防 Auto-Chain 步骤回归）
# 回归历史：cdad541 内联还原时漏掉 Auto-Chain 步骤，导致 AI 永不设置 next_task，
# 子任务完成后 stop-hook 静默释放，project 模式 auto next 失效约 1 个月。
MERGE_SECTION=$(awk '
    /^## Phase: *merge/ { in_merge=1; print; next }
    in_merge && /^## / && !/^## Phase: *merge/ { in_merge=0 }
    in_merge { print }
' "$SKILL_FILE")

if [[ -z "$MERGE_SECTION" ]]; then
    fail "无法从 SKILL.md 定位 merge 阶段段落（找不到 '## Phase: merge'）"
fi

next_task_in_merge=$(echo "$MERGE_SECTION" | grep -c "next_task" || true)
if [[ "$next_task_in_merge" -lt 1 ]]; then
    fail "SKILL.md merge 阶段段落必须提及 next_task（Auto-Chain 步骤），否则 project 模式自动链接失效"
fi
# 同时要求显式的 Auto-Chain 步骤标题（否则可能只是清理段附带提到 next_task，仍漏 Auto-Chain 指令）
auto_chain_heading=$(echo "$MERGE_SECTION" | grep -cE "^#### [0-9.]+ Auto-Chain" || true)
if [[ "$auto_chain_heading" -lt 1 ]]; then
    fail "SKILL.md merge 阶段段落必须有 '#### N. Auto-Chain ...' 标题段，单提 next_task 不够（防 cdad541 类回归）"
fi
pass "SKILL.md merge 阶段段落包含 next_task ($next_task_in_merge 次) + Auto-Chain 段标题 ($auto_chain_heading 个)"

echo "[OK ] R3 skill-references-consistency — 全部断言通过"
exit 0
