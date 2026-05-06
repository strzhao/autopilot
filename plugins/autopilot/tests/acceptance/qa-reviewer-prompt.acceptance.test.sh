#!/usr/bin/env bash
# R2: 验证 qa-reviewer-prompt.md 的存在性与必需要素
# 红队测试 — 仅基于设计文档，不读蓝队实现
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
PROMPT_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/qa-reviewer-prompt.md"

fail() {
    echo "[FAIL] R2: $1" >&2
    exit 1
}

pass() {
    echo "[PASS] R2: $1"
}

# 断言 1：文件存在
[[ -f "$PROMPT_FILE" ]] \
    || fail "qa-reviewer-prompt.md 不存在: $PROMPT_FILE"
pass "文件存在"

# 断言 2：Section A（设计符合性）标识
if grep -q "Section A" "$PROMPT_FILE" || grep -q "设计符合性" "$PROMPT_FILE"; then
    pass "包含 Section A / 设计符合性 标识"
else
    fail "缺少 Section A 或「设计符合性」关键 token（设计审查能力标识）"
fi

# 断言 3：Section B（代码质量）标识
if grep -q "Section B" "$PROMPT_FILE" || grep -q "代码质量" "$PROMPT_FILE"; then
    pass "包含 Section B / 代码质量 标识"
else
    fail "缺少 Section B 或「代码质量」关键 token（代码质量审查能力标识）"
fi

# 断言 4：OWASP（安全审查标识）
grep -q "OWASP" "$PROMPT_FILE" \
    || fail "缺少 OWASP 关键 token（安全审查能力标识）"
pass "包含 OWASP 安全审查标识"

# 断言 5：置信度（评分规则标识，允许变体）
if grep -q "置信度" "$PROMPT_FILE"; then
    pass "包含「置信度」评分规则标识"
else
    fail "缺少「置信度」关键 token（评分规则标识，可能写成「置信度 ≥80」「置信度评分」等）"
fi

# 断言 6：行数在合理范围（80–200 行）
line_count=$(wc -l < "$PROMPT_FILE" | tr -d ' ')
if [[ "$line_count" -lt 80 ]]; then
    fail "文件行数 $line_count < 80，内容过于简略，可能未真正合并两类审查能力"
fi
if [[ "$line_count" -gt 200 ]]; then
    fail "文件行数 $line_count > 200，可能爆炸或未做有效合并（合并目标是减少 token）"
fi
pass "行数 $line_count 在合理范围 [80, 200]"

echo "[OK ] R2 qa-reviewer-prompt — 全部断言通过"
exit 0
