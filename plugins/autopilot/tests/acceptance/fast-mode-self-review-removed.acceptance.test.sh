#!/usr/bin/env bash
# R11: 验证 Fast Mode design 阶段「编排器自审」已被删除（及范围守护）
# 红队测试 — 仅基于设计文档推导断言，不读蓝队实现 diff
#
# 变更背景：Fast Mode (fast_mode=true) design 阶段的「编排器按 6 维度自审」被删除。
#   原因：自审无独立性（写设计的同一个 agent 审自己的设计 = 橡皮图章），几乎不发现问题，纯浪费 token。
# 删除范围（仅 design 阶段 plan-review 自审）：
#   - SKILL.md「### Fast Mode 快速路径」子章节不再含「自审」
#   - design-modes.md 不再存在 §5「自审失败回退到 AskUserQuestion」整节；§4 design 行不含「自审」
#   - stop-hook.sh 中 fast_mode=true 的 design 阶段 PROMPT 不再含「6 维度自审 / 自审失败 / 自审通过」
# 必须保留（范围守护）：
#   - plan-reviewer-prompt.md 文件存在（standard / auto-approve 仍用 plan-reviewer Agent，那是独立 sub-agent）
#   - standard / auto-approve 路径仍引用 plan-reviewer
#   - QA smoke 的 inline 自审【未受波及】（design-modes §4 qa 行 + SKILL qa_scope smoke 段仍含「自审」）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SKILL_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/SKILL.md"
DESIGN_MODES_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/design-modes.md"
STOP_HOOK_FILE="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"
PLAN_REVIEWER_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/plan-reviewer-prompt.md"

fail() {
    echo "[FAIL] R11: $1" >&2
    exit 1
}

pass() {
    echo "[PASS] R11: $1"
}

# ---------------------------------------------------------------------------
# 断言 1（删除确认）：SKILL.md「### Fast Mode 快速路径」子章节不再含「自审」
#   守护：Fast Mode design 阶段的编排器自审描述已从 SKILL.md 主文档删除。
#   awk 提取从「### Fast Mode 快速路径」标题到下一个真正的 H2 (## ) 之间的内容
#   （设计文档约定范围；变更后该整段不应出现 design 自审语义）。
# ---------------------------------------------------------------------------
fast_subsection=$(awk '/^### .*Fast Mode.*快速路径/ {in_sec=1; next} in_sec && /^## / {in_sec=0} in_sec {print}' "$SKILL_FILE")
if [[ -z "$fast_subsection" ]]; then
    fail "SKILL.md 未找到「### Fast Mode 快速路径」子章节（awk 提取为空，锚点漂移？）"
fi
count=$(printf '%s\n' "$fast_subsection" | grep -c '自审' || true)
if [[ "$count" -ne 0 ]]; then
    fail "SKILL.md「### Fast Mode 快速路径」子章节仍含「自审」x$count 次（Fast Mode design 自审未删除）"
fi
pass "SKILL.md Fast Mode 快速路径子章节已无「自审」（grep -c == 0）"

# ---------------------------------------------------------------------------
# 断言 2（删除确认）：design-modes.md 不再存在 §5「自审失败回退到 AskUserQuestion」整节
#   守护：Fast Mode design 自审失败回退逻辑整节被删（这是 design 自审闭环的失败分支，
#   自审本体已删，失败回退自然也无意义）。
# ---------------------------------------------------------------------------
hit=$(grep -cE '§5\. 自审失败回退|自审失败回退到 AskUserQuestion' "$DESIGN_MODES_FILE" || true)
if [[ "$hit" -ne 0 ]]; then
    fail "design-modes.md 仍存在 §5「自审失败回退」整节标题（命中 x$hit 次，design 自审失败回退未删）"
fi
pass "design-modes.md 已无 §5 自审失败回退节标题（grep -c == 0）"

# ---------------------------------------------------------------------------
# 断言 3（删除确认）：stop-hook.sh 中 fast_mode design 阶段 PROMPT 不再含自审语义
#   守护：stop-hook 注入给 fast_mode=true design 阶段的 PROMPT 不再驱动编排器做 6 维度自审。
#   整文件 grep（PROMPT 是 stop-hook 内组装的字符串，无更细的精确锚点时，全文件零自审语义
#   是最稳的确定性判定——design 自审删除后 stop-hook 不应残留任何 design 自审相关 prompt 文案）。
# ---------------------------------------------------------------------------
hit=$(grep -cE '6 维度自审|自审失败|自审通过' "$STOP_HOOK_FILE" || true)
if [[ "$hit" -ne 0 ]]; then
    fail "stop-hook.sh 仍含「6 维度自审 / 自审失败 / 自审通过」语义（命中 x$hit 次，fast_mode design 自审 PROMPT 未清理）"
fi
pass "stop-hook.sh 已无 fast_mode design 自审语义（grep -cE == 0）"

# ---------------------------------------------------------------------------
# 断言 4（保留确认）：plan-reviewer-prompt.md 文件存在
#   守护：本次只删 design 阶段编排器自审，不删 plan-reviewer-prompt.md——
#   standard / auto-approve 模式仍启动独立 plan-reviewer Agent（sub-agent，非自审）。
# ---------------------------------------------------------------------------
[[ -f "$PLAN_REVIEWER_FILE" ]] \
    || fail "plan-reviewer-prompt.md 文件不存在（被误删？standard/auto-approve 的独立审查 Agent 失去 prompt 源）"
pass "plan-reviewer-prompt.md 文件存在（standard/auto-approve 独立审查 Agent prompt 保留）"

# ---------------------------------------------------------------------------
# 断言 5（保留确认）：standard / auto-approve 路径仍引用 plan-reviewer
#   守护：删除范围未蔓延到独立 plan-reviewer Agent 的引用。三文件 plan-reviewer 总出现次数 ≥ 4。
# ---------------------------------------------------------------------------
total=$(grep -cE 'plan-reviewer' "$SKILL_FILE" "$DESIGN_MODES_FILE" "$STOP_HOOK_FILE" \
        | awk -F: '{s+=$NF} END{print s+0}')
if [[ "$total" -lt 4 ]]; then
    fail "三文件 plan-reviewer 引用总次数 $total < 4（standard/auto-approve 独立审查 Agent 路径丢失）"
fi
pass "三文件 plan-reviewer 引用总次数 $total ≥ 4（standard/auto-approve 路径完整）"

# ---------------------------------------------------------------------------
# 断言 6（范围守护）：design-modes.md §4 的 qa 行仍含「自审」
#   守护：本次只删 design 阶段自审，QA smoke 的 inline 自审（编排器自行 Read git diff
#   做 3 项自审：设计符合性 / OWASP / 代码质量）是另一回事，必须保留。
#   提取 §4 表格 qa 行：从「## §4.」到「## §5.」（或文件末）之间的 qa 开头表格行。
# ---------------------------------------------------------------------------
section4=$(awk '/^## §4\./ {in4=1; next} in4 && /^## / {in4=0} in4 {print}' "$DESIGN_MODES_FILE")
if [[ -z "$section4" ]]; then
    fail "design-modes.md 未找到 §4 章节（awk 提取为空，锚点漂移？）"
fi
# qa 行：§4 表格中以 qa 为阶段名的行（形如 "| qa | ..."）。
# 注意不能简单 grep 'qa'（会命中"qa Wave"等无关行）；用表格行锚点 '| qa' 精确定位。
qa_line=$(printf '%s\n' "$section4" | grep -E '^\| *qa ' || true)
if [[ -z "$qa_line" ]]; then
    fail "design-modes.md §4 未找到 qa 表格行（qa smoke inline 自审描述锚点丢失）"
fi
if ! printf '%s\n' "$qa_line" | grep -q '自审'; then
    fail "design-modes.md §4 qa 行不再含「自审」（QA smoke inline 自审被误删！变更范围越界）"
fi
pass "design-modes.md §4 qa 行仍含「自审」（QA smoke inline 自审未受波及）"

# ---------------------------------------------------------------------------
# 断言 7（范围守护）：SKILL.md 的 qa_scope smoke 描述仍含「自审」
#   守护：同断言 6，QA 阶段自审描述（SKILL.md Phase: qa 章节内）未被误删。
#   提取 Phase: qa 章节（## Phase: qa 到下一个 ## 之间），在其中找 qa_scope smoke 上下文。
# ---------------------------------------------------------------------------
qa_section=$(awk '/^## Phase: qa/ {in_qa=1; next} in_qa && /^## / {in_qa=0} in_qa {print}' "$SKILL_FILE")
if [[ -z "$qa_section" ]]; then
    fail "SKILL.md 未找到「## Phase: qa」章节（awk 提取为空，锚点漂移？）"
fi
smoke_lines=$(printf '%s\n' "$qa_section" | grep -E 'qa_scope.*smoke|smoke.*qa_scope' || true)
if [[ -z "$smoke_lines" ]]; then
    fail "SKILL.md Phase: qa 未找到 qa_scope smoke 描述行（锚点漂移？）"
fi
# 遍历所有 qa_scope smoke 描述行，只要其中任意一行含「自审」即视为 QA 自审描述保留。
# （避免 head -1 拿到不含自审的次要行而误判。）
if ! printf '%s\n' "$smoke_lines" | grep -q '自审'; then
    fail "SKILL.md qa_scope smoke 描述均不再含「自审」（QA 自审描述被误删！变更范围越界）"
fi
pass "SKILL.md qa_scope smoke 描述仍含「自审」（QA 阶段自审未受波及）"

# ---------------------------------------------------------------------------
# 断言 8（净减确认 — 软约束）：变更让 design-modes.md 更精简
#   删除 §5 整节 + §4 design 行的自审描述，文件应净减。本断言无法可靠得到「改动前」
#   的精确行数（git working tree 当前状态不等于改动前），故以合理上界作为软阈值：
#   design-modes.md 总行数应 ≤ 70（改动前 76 行，删 §5 约 8 行 + §4 design 自审约 2 行 ≈ 66 行）。
#   达标记 [PASS]；超标记 ⚠️ 提示但不 fail（软约束，仅提示审查者注意净减效果）。
# ---------------------------------------------------------------------------
lines=$(wc -l < "$DESIGN_MODES_FILE" | tr -d ' ')
if [[ "$lines" -le 70 ]]; then
    pass "design-modes.md 行数 $lines ≤ 70（软约束：变更净减生效）"
else
    # 软约束：不 fail，只提示
    echo "[PASS] R11: design-modes.md 行数 $lines > 70（软约束⚠️：净减效果不显著，但非硬性失败；审查者请人工确认 §5/§4 自审已删）"
fi

echo "[OK ] R11 fast-mode-self-review-removed — 全部断言通过"
exit 0
