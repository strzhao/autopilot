#!/usr/bin/env bash
# R_STEP4_GUARD: design 阶段「步骤 4 审批 = AI 自治」判据的长效双重 grep 守护（契约 C10 / 场景10.P1 + 场景10.P2）
# 红队验收测试 — 仅基于设计文档（state.md 的 ## 设计文档 + ## 验收场景 SSOT）编写。
#            铁律：本文件断言的是「文本内容」，故所有期望值字面量全部取自契约规约 C1-C10 与场景10 谓词，
#            绝不读取蓝队改后的 SKILL.md / references/** / scripts/** 内容来凑断言（TDD 红灯）。
#
# 依据 [2026-07-19]：减法删「执行指令」必须配 scene 5 双重 grep 长效守护（跨任务），
#   否则未来任一次减法可再把判据删掉而无人发现。本文件即该守护。
#
# 谓词映射（逐条 det-machine 谓词 → ≥1 硬断言，期望值字面量取自谓词 assert）：
#   场景10.P1 [det-machine]: 该文件存在 ∧ 含 `#### 步骤 4\.` 标题 grep ∧ 含 `AI 自治`
#                            ∧ 含 `[design-auto]` ∧ 含 `AskUserQuestion` ∧ 含 `# REVERSE-CHECK`
#   场景10.P2 [real-process]:  exit == 0 ∧ FAIL == 0 ∧ 本文件名出现在 run-all.sh `ORDERED_TESTS`
#                              （注册半：本文件自断言；执行半：本文件自身 exit 0 即证据，FAIL 计数落 artifact）
#
# 受护文本（C10 逐字）：`## Phase: design` 段内 `^#### 步骤 4\.` 标题 + `AI 自治` + `[design-auto]`
#                       + 例外路径字面 `AskUserQuestion`。
# 注：`AI 自治` 字面来自契约 C10（守护锚点），不来自 C2（C2 列的是 `[design-auto]`/`auto_approve: true`
#     /`phase: "implement"`/`同轮`/`AskUserQuestion`/`先看方案`/`先给我审`）；两者共同构成本守护断言集。
# CONTRACT_AMBIGUOUS: C2（区间必含字面清单）未列 `AI 自治`，而 C10 要求守护测试断言 `AI 自治`。
#   本测试按 C10（守护契约）执行——若实现侧最终未落 `AI 自治` 字面，需先补声明再调本断言，不得静默弱化。
#
# 反向验证（铁律「减法变更必须配反向谓词」）：见 `# REVERSE-CHECK` 段——以真实区间文本为基，
#   逐个删除受护字面构造 4 个 mutation，断言 checker 对每个 mutation 必须返回非 0；
#   任一 mutation 仍被判定 PASS（= checker 是 no-op，删光也能过）→ 本测试非 0 退出。
#   因此：受护文本一旦被删，本守护必然以非 0 退出。
#
# artifact: /tmp/autopilot-artifacts/场景10.P1.out（静态字面观测 + REVERSE-CHECK 读数）
#           /tmp/autopilot-artifacts/场景10.P2.out（注册观测 + FAIL 计数）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# REPO_ROOT 稳健探测：从 SCRIPT_DIR 往上找 .claude-plugin/marketplace.json
# （兼容暂存区 .autopilot/runtime/requirements/<task>/acceptance-staging/ 与目标位 tests/acceptance/ 两种落位）
_find_repo_root() {
    local d="$SCRIPT_DIR"
    while [[ -n "$d" && "$d" != "/" ]]; do
        if [[ -f "$d/.claude-plugin/marketplace.json" ]]; then
            echo "$d"
            return 0
        fi
        d=$(dirname "$d")
    done
    return 1
}

REPO_ROOT="$(_find_repo_root)" || {
    echo "[FAIL] R_STEP4_GUARD: 无法定位 REPO_ROOT（缺 .claude-plugin/marketplace.json）" >&2
    exit 1
}

SKILL_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/SKILL.md"
RUN_ALL="$REPO_ROOT/plugins/autopilot/tests/acceptance/run-all.sh"
SELF_FILE="${BASH_SOURCE[0]}"
SELF_BASE="$(basename "$SELF_FILE")"

ART_DIR="${AUTOPILOT_ARTIFACT_DIR:-/tmp/autopilot-artifacts}"
ART_NESTED="$ART_DIR/design-step4"
mkdir -p "$ART_NESTED"

PASS_N=0
FAIL_N=0
FAIL_MSGS=()

pass() {
    echo "[PASS] R_STEP4_GUARD: $1"
    PASS_N=$((PASS_N + 1))
}

fails() {
    echo "[FAIL] R_STEP4_GUARD: $1" >&2
    FAIL_N=$((FAIL_N + 1))
    FAIL_MSGS+=("$1")
}

# ── 提取 `## Phase: design` 段（C10 逐字要求） ─────────────────────────────────
extract_phase_design() {
    awk '
        /^## Phase: *design/ { in_p = 1 }
        in_p && /^## / && !/^## Phase: *design/ { in_p = 0 }
        in_p { print }
    ' "$1"
}

# ── 提取步骤 4 区间（契约 C1 作用域：`#### 步骤 4.` 至下一 `#### `） ──────────
extract_step4_region() {
    awk '
        /^#### 步骤 4\./ { in_r = 1 }
        in_r && /^#### / && !/^#### 步骤 4\./ { in_r = 0 }
        in_r { print }
    '
}

# ── checker：受护四要素（标题 + 内容三要素） ─────────────────────────────────
# 返回 0 = 受护文本齐备；返回 1 = 缺任一要素。
check_protected() { # <region text>
    local region="$1"
    # ① 步骤 4 标题（C3 保留契约 + C10 标题 grep）
    printf '%s\n' "$region" | grep -qE '^#### 步骤 4\.' || return 1
    # ② AI 自治 判据锚点（C10）
    printf '%s\n' "$region" | grep -qF 'AI 自治' || return 1
    # ③ [design-auto] 留痕锚点（C2 + C10）
    printf '%s\n' "$region" | grep -qF '[design-auto]' || return 1
    # ④ 例外路径 AskUserQuestion（C2 + C10）
    printf '%s\n' "$region" | grep -qF 'AskUserQuestion' || return 1
    return 0
}

echo "=========================================="
echo " R_STEP4_GUARD design 步骤 4 自治判据长效守护（C10 / 场景10）"
echo "=========================================="

[[ -f "$SKILL_FILE" ]] || fails "SKILL.md 不存在: $SKILL_FILE"
[[ -f "$RUN_ALL" ]] || fails "run-all.sh 不存在: $RUN_ALL"
[[ -f "$SELF_FILE" ]] || fails "本测试文件不存在: $SELF_FILE"

# ═══════════════════════════════════════════════════════════════════════════
# 场景10.P1 [det-machine]：守护测试静态字面齐备（四条字面 + 反向验证段标记）
# ═══════════════════════════════════════════════════════════════════════════
SELF_HAS_TITLE_GREP=0
SELF_HAS_AI_AUTONOMY=0
SELF_HAS_DESIGN_AUTO=0
SELF_HAS_ASK=0
SELF_HAS_REVERSE=0

grep -qF '#### 步骤 4\.' "$SELF_FILE" && SELF_HAS_TITLE_GREP=1
grep -qF 'AI 自治' "$SELF_FILE" && SELF_HAS_AI_AUTONOMY=1
grep -qF '[design-auto]' "$SELF_FILE" && SELF_HAS_DESIGN_AUTO=1
grep -qF 'AskUserQuestion' "$SELF_FILE" && SELF_HAS_ASK=1
grep -qF '# REVERSE-CHECK' "$SELF_FILE" && SELF_HAS_REVERSE=1

[[ "$SELF_HAS_TITLE_GREP" -eq 1 ]] || fails "场景10.P1: 本文件不含 '#### 步骤 4\\.' 标题 grep 字面（C10 要求标题 grep + 字段 grep 双重）"
[[ "$SELF_HAS_TITLE_GREP" -eq 1 ]] && pass "场景10.P1: 含 '#### 步骤 4\\.' 标题 grep 字面"

[[ "$SELF_HAS_AI_AUTONOMY" -eq 1 ]] || fails "场景10.P1: 本文件不含「AI 自治」字面（C10 受护锚点缺失）"
[[ "$SELF_HAS_AI_AUTONOMY" -eq 1 ]] && pass "场景10.P1: 含「AI 自治」字面"

[[ "$SELF_HAS_DESIGN_AUTO" -eq 1 ]] || fails "场景10.P1: 本文件不含 '[design-auto]' 字面（C2 留痕锚点缺失）"
[[ "$SELF_HAS_DESIGN_AUTO" -eq 1 ]] && pass "场景10.P1: 含 '[design-auto]' 字面"

[[ "$SELF_HAS_ASK" -eq 1 ]] || fails "场景10.P1: 本文件不含 'AskUserQuestion' 字面（C2 例外路径缺失）"
[[ "$SELF_HAS_ASK" -eq 1 ]] && pass "场景10.P1: 含 'AskUserQuestion' 字面"

[[ "$SELF_HAS_REVERSE" -eq 1 ]] || fails "场景10.P1: 本文件不含 '# REVERSE-CHECK' 可识别标记（C10 反向验证段缺失）"
[[ "$SELF_HAS_REVERSE" -eq 1 ]] && pass "场景10.P1: 含 '# REVERSE-CHECK' 反向验证段标记"

# ═══════════════════════════════════════════════════════════════════════════
# 受护文本正向断言（C10 守护对象本体）
# ═══════════════════════════════════════════════════════════════════════════
PHASE_DESIGN="$(extract_phase_design "$SKILL_FILE")"
STEP4_REGION=""
REGION_LINES=0
TITLE_N=0
AI_N=0
DA_N=0
ASK_N=0
CHECKER_OK=0

if [[ -n "$PHASE_DESIGN" ]]; then
    STEP4_REGION="$(printf '%s\n' "$PHASE_DESIGN" | extract_step4_region)"
    REGION_LINES="$(printf '%s\n' "$STEP4_REGION" | grep -c . || true)"
    TITLE_N="$(printf '%s\n' "$PHASE_DESIGN" | grep -cE '^#### 步骤 4\.' || true)"
    AI_N="$(printf '%s\n' "$STEP4_REGION" | grep -cF 'AI 自治' || true)"
    DA_N="$(printf '%s\n' "$STEP4_REGION" | grep -cF '[design-auto]' || true)"
    ASK_N="$(printf '%s\n' "$STEP4_REGION" | grep -cF 'AskUserQuestion' || true)"
    check_protected "$STEP4_REGION" && CHECKER_OK=1
fi

[[ -n "$PHASE_DESIGN" ]] || fails "无法从 SKILL.md 定位 '## Phase: design' 段落（提取为空）"
[[ -n "$PHASE_DESIGN" ]] && pass "## Phase: design 段可解析"
[[ -n "$STEP4_REGION" ]] || fails "无法从 ## Phase: design 段定位 '#### 步骤 4.' 区间（提取为空）"
[[ "$REGION_LINES" -ge 1 ]] || fails "步骤 4 区间为空（C1 作用域不可解析）"
[[ "$REGION_LINES" -ge 1 ]] && pass "步骤 4 区间可解析（非空行 ${REGION_LINES} 行）"

[[ "$TITLE_N" -ge 1 ]] || fails "## Phase: design 段内无 '^#### 步骤 4\\.' 标题（C3/C10：标题被删）"
[[ "$TITLE_N" -ge 1 ]] && pass "## Phase: design 段含 '^#### 步骤 4\\.' 标题 x${TITLE_N}"

[[ "$AI_N" -ge 1 ]] || fails "步骤 4 区间不含「AI 自治」（C10 受护锚点被删；命中 ${AI_N}）"
[[ "$AI_N" -ge 1 ]] && pass "步骤 4 区间含「AI 自治」x${AI_N}"

[[ "$DA_N" -ge 1 ]] || fails "步骤 4 区间不含 '[design-auto]'（C2 留痕锚点被删；命中 ${DA_N}）"
[[ "$DA_N" -ge 1 ]] && pass "步骤 4 区间含 '[design-auto]' x${DA_N}"

[[ "$ASK_N" -ge 1 ]] || fails "步骤 4 区间不含 'AskUserQuestion'（C2 例外路径被删；命中 ${ASK_N}）"
[[ "$ASK_N" -ge 1 ]] && pass "步骤 4 区间含 'AskUserQuestion' x${ASK_N}"

[[ "$CHECKER_OK" -eq 1 ]] || fails "步骤 4 区间未通过受护四要素 checker（标题/AI 自治/[design-auto]/AskUserQuestion）"
[[ "$CHECKER_OK" -eq 1 ]] && pass "步骤 4 区间通过受护四要素 checker"

# ═══════════════════════════════════════════════════════════════════════════
# REVERSE-CHECK：反向验证段（mutation kill，删除受护文本必须非 0 退出）
#   方法：以真实区间文本为基，逐个删除受护字面构造 4 个 mutation，
#   断言 check_protected 对每个 mutation 必须返回非 0。
#   任一 mutation 仍判 PASS → checker 是 no-op（删光也能过）→ fail → 本文件非 0 退出。
# ═══════════════════════════════════════════════════════════════════════════
MUT_KILLED=0
MUT_SURVIVED=0
REVERSE_LOG=""

if [[ -n "$STEP4_REGION" ]]; then
    # mutation ①：删含 'AI 自治' 的行
    MUT1="$(printf '%s\n' "$STEP4_REGION" | grep -vF 'AI 自治' || true)"
    if check_protected "$MUT1"; then
        MUT_SURVIVED=$((MUT_SURVIVED + 1))
        REVERSE_LOG="${REVERSE_LOG}mutation[AI 自治] SURVIVED (no-op checker)\n"
    else
        MUT_KILLED=$((MUT_KILLED + 1))
        REVERSE_LOG="${REVERSE_LOG}mutation[AI 自治] killed\n"
    fi

    # mutation ②：删含 '[design-auto]' 的行
    MUT2="$(printf '%s\n' "$STEP4_REGION" | grep -vF '[design-auto]' || true)"
    if check_protected "$MUT2"; then
        MUT_SURVIVED=$((MUT_SURVIVED + 1))
        REVERSE_LOG="${REVERSE_LOG}mutation[[design-auto]] SURVIVED (no-op checker)\n"
    else
        MUT_KILLED=$((MUT_KILLED + 1))
        REVERSE_LOG="${REVERSE_LOG}mutation[[design-auto]] killed\n"
    fi

    # mutation ③：删含 'AskUserQuestion' 的行（例外路径）
    MUT3="$(printf '%s\n' "$STEP4_REGION" | grep -vF 'AskUserQuestion' || true)"
    if check_protected "$MUT3"; then
        MUT_SURVIVED=$((MUT_SURVIVED + 1))
        REVERSE_LOG="${REVERSE_LOG}mutation[AskUserQuestion] SURVIVED (no-op checker)\n"
    else
        MUT_KILLED=$((MUT_KILLED + 1))
        REVERSE_LOG="${REVERSE_LOG}mutation[AskUserQuestion] killed\n"
    fi

    # mutation ④：删步骤 4 标题行
    MUT4="$(printf '%s\n' "$STEP4_REGION" | grep -vE '^#### 步骤 4\.' || true)"
    if check_protected "$MUT4"; then
        MUT_SURVIVED=$((MUT_SURVIVED + 1))
        REVERSE_LOG="${REVERSE_LOG}mutation[^#### 步骤 4\\.] SURVIVED (no-op checker)\n"
    else
        MUT_KILLED=$((MUT_KILLED + 1))
        REVERSE_LOG="${REVERSE_LOG}mutation[^#### 步骤 4\\.] killed\n"
    fi
else
    fails "REVERSE-CHECK: 步骤 4 区间提取为空，无法构造 mutation（受护文本已整体缺失）"
fi

# ═══════════════════════════════════════════════════════════════════════════
# 场景10.P2 [real-process]：注册半 —— 本文件名出现在 run-all.sh ORDERED_TESTS
#   执行半（exit 0 ∧ FAIL 0）由本文件自身运行证明；FAIL 计数落 artifact 场景10.P2.out。
# ═══════════════════════════════════════════════════════════════════════════
ORDERED_BLOCK=""
REGISTERED=0
if [[ -f "$RUN_ALL" ]]; then
    ORDERED_BLOCK="$(awk '/^ORDERED_TESTS=\(/{f=1} f{print} f && /^\)/{exit}' "$RUN_ALL")"
fi
if [[ -n "$ORDERED_BLOCK" ]] && printf '%s\n' "$ORDERED_BLOCK" | grep -qF "$SELF_BASE"; then
    REGISTERED=1
fi

[[ -n "$ORDERED_BLOCK" ]] || fails "场景10.P2: 无法从 run-all.sh 解析 ORDERED_TESTS 数组（注册表不可读）"
[[ -n "$ORDERED_BLOCK" ]] && pass "场景10.P2: run-all.sh ORDERED_TESTS 数组可解析"

[[ "$REGISTERED" -eq 1 ]] || fails "场景10.P2: ${SELF_BASE} 未登记于 run-all.sh 的 ORDERED_TESTS（新测试必须登记，否则 runner 不执行守护）"
[[ "$REGISTERED" -eq 1 ]] && pass "场景10.P2: ${SELF_BASE} 已登记于 run-all.sh ORDERED_TESTS"

# ═══════════════════════════════════════════════════════════════════════════
# REVERSE-CHECK 结论断言 + artifact 落盘（FAIL 计数在全部断言之后写，读数真实）
# ═══════════════════════════════════════════════════════════════════════════
[[ "$MUT_SURVIVED" -eq 0 ]] || fails "REVERSE-CHECK: ${MUT_SURVIVED} 个 mutation 未被 kill（checker 为 no-op，删光受护文本也能 PASS）"
[[ "$MUT_KILLED" -eq 4 ]] || fails "REVERSE-CHECK: mutation 数不等于 4（killed=${MUT_KILLED}），反向验证段覆盖不完整"
[[ "$MUT_SURVIVED" -eq 0 && "$MUT_KILLED" -eq 4 ]] &&
    pass "REVERSE-CHECK: 4 个受护文本 mutation 全部被 kill（删除受护文本 → checker 非 0 → 本测试非 0 退出）"

{
    echo "# 场景10.P1 — 守护测试静态字面观测 + REVERSE-CHECK 读数（design-step4 autonomy guard）"
    echo "file=$SELF_BASE"
    echo "title_grep(#### 步骤 4\\.)=$SELF_HAS_TITLE_GREP"
    echo "AI 自治=$SELF_HAS_AI_AUTONOMY"
    echo "[design-auto]=$SELF_HAS_DESIGN_AUTO"
    echo "AskUserQuestion=$SELF_HAS_ASK"
    echo "# REVERSE-CHECK=$SELF_HAS_REVERSE"
    echo "region_lines=$REGION_LINES"
    echo "MUT_KILLED=$MUT_KILLED"
    echo "MUT_SURVIVED=$MUT_SURVIVED"
    printf '%b' "$REVERSE_LOG"
} > "$ART_DIR/场景10.P1.out"
cp "$ART_DIR/场景10.P1.out" "$ART_NESTED/场景10.P1.out" 2>/dev/null || true

{
    echo "# 场景10.P2 — 守护测试注册观测（design-step4 autonomy guard）"
    echo "self=$SELF_BASE"
    echo "run_all=$RUN_ALL"
    echo "ordered_tests_registered=$REGISTERED"
    echo "FAIL=$FAIL_N"
} > "$ART_DIR/场景10.P2.out"
cp "$ART_DIR/场景10.P2.out" "$ART_NESTED/场景10.P2.out" 2>/dev/null || true

echo ""
echo "=========================================="
echo " R_STEP4_GUARD 汇总: PASS=${PASS_N}  FAIL=${FAIL_N}"
echo "=========================================="
echo "覆盖谓词: 场景10.P1/10.P2 + REVERSE-CHECK（C10 反向验证）"

if [[ "$FAIL_N" -gt 0 ]]; then
    echo ""
    echo "失败明细："
    for m in "${FAIL_MSGS[@]}"; do
        echo "   - $m"
    done
    echo ""
    echo "FAIL"
    exit 1
fi

echo "PASS"
exit 0
