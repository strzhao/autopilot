#!/usr/bin/env bash
# R7: 验证 SKILL.md 包含 fast_mode 决策树优先级 + Fast Mode 快速路径子章节 +
#     QA smoke 行为描述 + frontmatter 字段表更新
# 红队测试 — 仅基于设计文档编写，不读取蓝队实现
#
# 设计文档要求：
#   改动点 3：SKILL.md design ⚠️ 关键规则块决策树前 3 位含 fast_mode 分支（优先级 3）
#   改动点 3：新增 ### Fast Mode 快速路径 子章节，含 EnterPlanMode/ExitPlanMode/1个Explore agent/
#             不启动 scenario-generator/编排器自审/不启动 plan-reviewer
#   改动点 4：qa 阶段 qa_scope:smoke 分支：只跑 Wave 1 + Wave 1.5，
#             不启动 qa-reviewer Agent，编排器 inline 自审
#   改动点 1：frontmatter 字段表中有 fast_mode 字段说明（默认 false）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SKILL_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/SKILL.md"

fail() {
    echo "[FAIL] R7: $1" >&2
    exit 1
}

pass() {
    echo "[PASS] R7: $1"
}

[[ -f "$SKILL_FILE" ]] || fail "SKILL.md 不存在: $SKILL_FILE"

# ═══════════════════════════════════════════════════════
# 改动点 3-A：fast_mode 分支在决策树 ⚠️ 关键规则块中
# ═══════════════════════════════════════════════════════

# 断言 1：SKILL.md 整体含 fast_mode 字段引用
fast_mode_count=$(grep -c "fast_mode" "$SKILL_FILE" || true)
if [[ "$fast_mode_count" -lt 1 ]]; then
    fail "SKILL.md 中找不到 fast_mode（改动点 1/3/4 均需要此字段）"
fi
pass "SKILL.md 包含 fast_mode 引用（共 $fast_mode_count 次）"

# 断言 2：⚠️ 关键规则块 / 决策树段落中存在 fast_mode 分支
# 策略：提取 ⚠️ 或 "关键规则" 紧邻段落内容，检查 fast_mode 出现
rules_section=$(awk '
    /⚠️|关键规则|决策树/ { in_block=1; depth=0 }
    in_block { print }
    in_block && /^## / && !/⚠️|关键规则|决策树/ { in_block=0 }
' "$SKILL_FILE")

if [[ -z "$rules_section" ]]; then
    fail "SKILL.md 中找不到 ⚠️ 关键规则 / 决策树 段落（设计要求此块必须含 fast_mode 分支）"
fi

if ! echo "$rules_section" | grep -q "fast_mode"; then
    fail "⚠️ 关键规则/决策树段落中不含 fast_mode 分支（设计要求前 3 优先级包含 fast_mode: true 分支）"
fi
pass "⚠️ 关键规则/决策树段落中包含 fast_mode 分支"

# 断言 3：决策树 fast_mode 分支位于 auto_approve 与标准模式之间（行号顺序）
# auto_approve 应在 fast_mode 之前出现（在 ⚠️ 块内）
rules_auto_line=$(echo "$rules_section" | grep -n "auto_approve" | head -1 | cut -d: -f1)
rules_fast_line=$(echo "$rules_section" | grep -n "fast_mode" | head -1 | cut -d: -f1)

if [[ -z "$rules_auto_line" ]]; then
    fail "⚠️ 关键规则块中未找到 auto_approve（设计决策树第 1 优先级应为 auto_approve: true）"
fi
if [[ -z "$rules_fast_line" ]]; then
    fail "⚠️ 关键规则块中未找到 fast_mode（设计决策树第 3 优先级应为 fast_mode: true）"
fi
if [[ "$rules_fast_line" -le "$rules_auto_line" ]]; then
    fail "决策树中 fast_mode 行($rules_fast_line) 应在 auto_approve 行($rules_auto_line) 之后（优先级 3 > 1）"
fi
pass "决策树优先级顺序：auto_approve(${rules_auto_line}) < fast_mode(${rules_fast_line}) — 正确"

# 断言 4：决策树含 plan_mode deep 分支，且位于 auto_approve 后 fast_mode 前
rules_plan_line=$(echo "$rules_section" | grep -n "plan_mode\|deep" | head -1 | cut -d: -f1)
if [[ -z "$rules_plan_line" ]]; then
    fail "⚠️ 关键规则块中未找到 plan_mode/deep（设计决策树第 2 优先级应为 plan_mode: deep）"
fi
if [[ "$rules_plan_line" -le "$rules_auto_line" ]] || [[ "$rules_plan_line" -ge "$rules_fast_line" ]]; then
    fail "决策树优先级顺序违反：plan_mode(${rules_plan_line}) 应在 auto_approve(${rules_auto_line}) 之后、fast_mode(${rules_fast_line}) 之前"
fi
pass "决策树优先级顺序完整：auto_approve < plan_mode:deep < fast_mode — 正确"

# ═══════════════════════════════════════════════════════
# 改动点 3-B：Fast Mode 快速路径子章节
# ═══════════════════════════════════════════════════════

# 断言 5：存在 Fast Mode 快速路径子章节标题
# 设计文档: "新增 ### Fast Mode 快速路径（仅 fast_mode=true 时）子章节"
if ! grep -qE '^### .*[Ff]ast [Mm]ode.*快速路径|^### .*快速路径.*[Ff]ast [Mm]ode' "$SKILL_FILE"; then
    fail "SKILL.md 中找不到 ### Fast Mode 快速路径 子章节标题"
fi
pass "SKILL.md 包含 ### Fast Mode 快速路径 子章节"

# 提取 Fast Mode 子章节内容（从标题到下一个 ### 或 ## 为止）
fast_section=$(awk '
    /^### .*[Ff]ast [Mm]ode.*快速路径|^### .*快速路径.*[Ff]ast [Mm]ode/ { in_block=1; print; next }
    in_block && /^##/ { in_block=0 }
    in_block { print }
' "$SKILL_FILE")

if [[ -z "$fast_section" ]]; then
    fail "无法提取 Fast Mode 快速路径子章节内容"
fi

# 断言 6：Fast Mode 子章节含 EnterPlanMode
if ! echo "$fast_section" | grep -qiE "EnterPlanMode|enter.*plan.*mode"; then
    fail "Fast Mode 子章节缺少 EnterPlanMode 步骤（设计要求步骤 1：EnterPlanMode）"
fi
pass "Fast Mode 子章节包含 EnterPlanMode"

# 断言 7：Fast Mode 子章节含 ExitPlanMode
if ! echo "$fast_section" | grep -qiE "ExitPlanMode|exit.*plan.*mode"; then
    fail "Fast Mode 子章节缺少 ExitPlanMode 步骤（设计要求步骤 5：ExitPlanMode）"
fi
pass "Fast Mode 子章节包含 ExitPlanMode"

# 断言 8：Fast Mode 子章节含 1 个 Explore agent 的描述
if ! echo "$fast_section" | grep -qiE "Explore.*[Aa]gent|1.*[Ee]xplore|[Ee]xplore"; then
    fail "Fast Mode 子章节缺少 Explore agent 描述（设计要求步骤 2：1 个 Explore agent）"
fi
pass "Fast Mode 子章节包含 Explore agent 描述"

# 断言 9：Fast Mode 子章节不启动 scenario-generator（描述中有明确排除）
if ! echo "$fast_section" | grep -qiE "scenario.generator|scenario_generator"; then
    fail "Fast Mode 子章节未提及 scenario-generator（设计要求明确说明不启动 scenario-generator）"
fi
pass "Fast Mode 子章节包含 scenario-generator 相关描述（明确不启动）"

# 断言 10：Fast Mode 子章节描述编排器自审（不启动 plan-reviewer）
if ! echo "$fast_section" | grep -qiE "plan.reviewer|plan_reviewer|自审"; then
    fail "Fast Mode 子章节未提及 plan-reviewer 或自审（设计要求编排器自审，不启动 plan-reviewer Agent）"
fi
pass "Fast Mode 子章节包含 plan-reviewer/自审 描述"

# ═══════════════════════════════════════════════════════
# 改动点 4：QA smoke 分支行为
# ═══════════════════════════════════════════════════════

# 提取 QA 阶段章节
qa_section=$(awk '
    /^## Phase:.*qa|^## .*QA.*[Pp]hase|^## .*[Qq][Aa]/ { in_qa=1; print; next }
    in_qa && /^## / && !/[Qq][Aa]/ { in_qa=0 }
    in_qa { print }
' "$SKILL_FILE")

if [[ -z "$qa_section" ]]; then
    fail "无法从 SKILL.md 提取 QA 阶段章节"
fi

# 断言 11：QA 章节含 qa_scope smoke 分支
if ! echo "$qa_section" | grep -qE '"smoke"|smoke'; then
    fail "QA 章节未包含 smoke 分支（改动点 4 要求扩展 qa_scope: smoke 行为描述）"
fi
pass "QA 章节包含 qa_scope smoke 分支"

# 断言 12：smoke 分支描述 Wave 1 的运行
smoke_subsection=$(awk '
    /smoke/ { in_block=1 }
    in_block { print }
    in_block && /^###/ && !/smoke/ { in_block=0 }
' <<< "$qa_section")

if ! echo "$smoke_subsection" | grep -qiE "Wave 1|wave1|第一波"; then
    fail "smoke 分支未描述 Wave 1（设计要求只跑 Wave 1 + Wave 1.5）"
fi
pass "smoke 分支包含 Wave 1 描述"

# 断言 13：smoke 分支描述 Wave 1.5
if ! echo "$smoke_subsection" | grep -qiE "Wave 1\.5|wave1\.5|wave 1.5"; then
    fail "smoke 分支未描述 Wave 1.5（设计要求只跑 Wave 1 + Wave 1.5）"
fi
pass "smoke 分支包含 Wave 1.5 描述"

# 断言 14：smoke 分支描述不启动 qa-reviewer Agent
if ! echo "$smoke_subsection" | grep -qiE "qa.reviewer|qa_reviewer"; then
    fail "smoke 分支未提及 qa-reviewer（设计要求描述不启动 qa-reviewer Agent）"
fi
pass "smoke 分支包含 qa-reviewer 相关描述（不启动）"

# 断言 15：smoke 分支描述编排器 inline 自审
if ! echo "$smoke_subsection" | grep -qiE "inline|自审|inline.*自审|自审.*inline"; then
    fail "smoke 分支未提及 inline 自审（设计要求编排器对 diff 做 inline 自审）"
fi
pass "smoke 分支包含 inline 自审描述"

# ═══════════════════════════════════════════════════════
# 改动点 1：frontmatter 字段表中含 fast_mode 字段说明
# ═══════════════════════════════════════════════════════

# 断言 16：frontmatter 字段表中存在 fast_mode 字段描述
# 通常在 SKILL.md 中有字段说明表，fast_mode 默认 false 应在其中出现
if ! grep -qE '\bfast_mode\b.*false|false.*\bfast_mode\b' "$SKILL_FILE"; then
    fail "SKILL.md 字段说明表中未找到 fast_mode 及其默认值 false（改动点 1 要求 frontmatter 字段表更新）"
fi
pass "SKILL.md 字段说明表包含 fast_mode 及默认值 false"

echo "[OK ] R7 skill-fast-mode-doc — 全部断言通过"
exit 0
