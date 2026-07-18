#!/usr/bin/env bash
# acceptance test: autopilot doctor Dim 13 编号对齐 + Dim 13 唯一性（场景 7）
#
# 设计契约（黑盒视角，不读 SKILL.md/lib.sh 实现）：
#   Dim 编号集合 = {1..13} 连续无缺
#   Dim 13 在 SKILL.md 唯一定义（无重复 ## Dim 13 标题）
#   lib.sh 含 ≥8 新函数服务 Dim 13
#   6 客观探测函数覆盖 6 客观信号
#
# 覆盖验收场景（场景 7，4 谓词，每条 ≥1 硬断言）：
#   编号对齐.P1：Dim 编号集合 == {1..13}
#   编号对齐.P2：Dim 13 在 SKILL.md 唯一定义（无 2 处独立 ## Dim 13 标题）
#   编号对齐.P3：lib.sh 含 ≥8 新函数
#   编号对齐.P4：6 客观探测函数覆盖 6 客观信号关键词
#
# 运行：bash ai-obs-dim-numbering.acceptance.test.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT=""
_search="$SCRIPT_DIR"
while [[ -n "$_search" ]] && [[ "$_search" != "/" ]]; do
    if [[ -d "$_search/.git" ]]; then
        REPO_ROOT="$_search"
        break
    fi
    _search="$(dirname "$_search")"
done
unset _search

if [[ -z "$REPO_ROOT" ]]; then
    echo "FATAL: cannot locate repo root" >&2
    exit 99
fi

SKILL_MD="$REPO_ROOT/plugins/autopilot/skills/autopilot-doctor/SKILL.md"
LIB_SH="$REPO_ROOT/plugins/autopilot/scripts/lib.sh"
if [[ ! -f "$SKILL_MD" ]]; then
    echo "FATAL: SKILL.md 不存在 $SKILL_MD" >&2
    exit 99
fi
if [[ ! -f "$LIB_SH" ]]; then
    echo "FATAL: lib.sh 不存在 $LIB_SH" >&2
    exit 99
fi

PASS_COUNT=0
FAIL_COUNT=0

# ═══════════════════════════════════════════════════════════════
# P1: Dim 编号集合 == {1..13}
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P1: SKILL.md Dim 编号集合 == {1..13} ──"

# 提取 Dim 编号集合（空格分隔，避免换行/尾部空白比较陷阱）
DIM_NUMS_STR=$(grep -oE '^#+\s*Dim\s+[0-9]+' "$SKILL_MD" 2>/dev/null \
    | grep -oE '[0-9]+$' | sort -n | uniq | tr '\n' ' ' | sed 's/ $//')
EXPECTED_STR=$(seq 1 13 | tr '\n' ' ' | sed 's/ $//')

# 比对集合（空格分隔字符串相等）
if [[ "$DIM_NUMS_STR" == "$EXPECTED_STR" ]]; then
    echo "  PASS  P1: Dim 编号集合 == {1..13}（连续无缺）"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  P1: Dim 编号集合不匹配"
    echo "        expected: '$EXPECTED_STR'"
    echo "        actual:   '$DIM_NUMS_STR'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Mutation-Survival：精确 grep "Dim 13" 必命中（仅 grep Dim 1 会漏）
if grep -qE '^#+\s*Dim\s+13\b' "$SKILL_MD"; then
    echo "  PASS  P1-b: SKILL.md 含 ## Dim 13 标题（精确匹配）"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  P1-b: SKILL.md 无 ## Dim 13 标题"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# P2: Dim 13 在 SKILL.md 唯一定义
# assert: ≥1 命中且无 2 处独立 ## Dim 13 标题
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P2: Dim 13 在 SKILL.md 唯一定义 ──"

# 精确 ## 标题（独立定义段）
# 注：grep -c 无匹配时 rc=1 但 stdout 仍输出 "0"，与 `|| echo 0` 拼接会得 "0\n0"。
# 改用 grep -E ... | wc -l 避免 rc/stdout 双输出陷阱。
# 唯一定义 = H3 标题（^### Dim 13）唯一；H4 子段（#### Dim 13 续）是 Wave 2 续段不算独立定义
DIM13_HEADERS=$(grep -E '^###[[:space:]]+Dim[[:space:]]+13\b' "$SKILL_MD" 2>/dev/null | wc -l | tr -d '[:space:]')
if [[ -z "$DIM13_HEADERS" ]]; then DIM13_HEADERS=0; fi
# Mutation-Survival：必为 1（非 0、非 ≥2）
if [[ "$DIM13_HEADERS" -eq 1 ]]; then
    echo "  PASS  P2: Dim 13 标题唯一定义（count=${DIM13_HEADERS}）"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  P2: Dim 13 标题 count=${DIM13_HEADERS}（应 == 1，0=缺失/≥2=重复）"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# P3: lib.sh 含 ≥8 新函数（detect_tech_stack + detect_ai_observability + 6 _ai_*_detect）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P3: lib.sh 含 ≥8 新 Dim 13 服务函数 ──"

EXPECTED_FUNCS=(
    detect_tech_stack
    detect_ai_observability
    _ai_struct_log_detect
    _ai_log_rotation_detect
    _ai_cli_diagnostic_detect
    _ai_health_json_detect
    _ai_cache_clean_detect
    _ai_debug_switch_detect
)

DEFINED_COUNT=0
UNDEFINED_FUNCS=""
for fn in "${EXPECTED_FUNCS[@]}"; do
    # bash 函数定义模式：fn() { 或 function fn {
    if grep -qE "^${fn}[[:space:]]*\(\)" "$LIB_SH" 2>/dev/null \
        || grep -qE "^function[[:space:]]+${fn}[[:space:]]*" "$LIB_SH" 2>/dev/null; then
        DEFINED_COUNT=$((DEFINED_COUNT + 1))
    else
        UNDEFINED_FUNCS="$UNDEFINED_FUNCS $fn"
    fi
done

if [[ "$DEFINED_COUNT" -ge 8 ]]; then
    echo "  PASS  P3: lib.sh 含 $DEFINED_COUNT/8 新函数（覆盖 detect_tech_stack + detect_ai_observability + 6 _ai_*_detect）"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  P3: lib.sh 仅 $DEFINED_COUNT/8 函数定义（缺失：${UNDEFINED_FUNCS}）"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# P4: 6 客观探测函数覆盖 6 客观信号
# 6 _ai_*_detect 函数名/注释语义命中 6 客观信号关键词
#   结构化日志/日志轮转/CLI诊断/health JSON/缓存清理/debug开关
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P4: 6 _ai_*_detect 函数语义覆盖 6 客观信号 ──"

# 函数名 → 信号关键词映射（设计文档锚定）
# _ai_struct_log_detect → struct_log（结构化日志）
# _ai_log_rotation_detect → log_rotation（日志轮转）
# _ai_cli_diagnostic_detect → cli_diagnostic（CLI 诊断）
# _ai_health_json_detect → health_json（health JSON）
# _ai_cache_clean_detect → cache_clean（缓存清理）
# _ai_debug_switch_detect → debug_switch（debug 开关）
SIGNAL_FUNCS=(
    "_ai_struct_log_detect:struct_log"
    "_ai_log_rotation_detect:log_rotation"
    "_ai_cli_diagnostic_detect:cli_diagnostic"
    "_ai_health_json_detect:health_json"
    "_ai_cache_clean_detect:cache_clean"
    "_ai_debug_switch_detect:debug_switch"
)

SIGNAL_HITS=0
SIGNAL_MISS=""
for pair in "${SIGNAL_FUNCS[@]}"; do
    fn="${pair%%:*}"
    if grep -qE "^${fn}[[:space:]]*\(\)" "$LIB_SH" 2>/dev/null; then
        SIGNAL_HITS=$((SIGNAL_HITS + 1))
    else
        SIGNAL_MISS="$SIGNAL_MISS $fn"
    fi
done

if [[ "$SIGNAL_HITS" -ge 6 ]]; then
    echo "  PASS  P4: 6 _ai_*_detect 函数全部定义，语义覆盖 6 客观信号"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  P4: 6 客观信号函数缺失：${SIGNAL_MISS}（命中 $SIGNAL_HITS/6）"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Mutation-Survival：检测_ai_*_detect 命名闭集（除 6 个外不应有其他 _ai_*_detect）
ALL_AI_DETECT=$(grep -oE '^_ai_[a-z_]+_detect[[:space:]]*\(\)' "$LIB_SH" 2>/dev/null \
    | sed -E 's/[[:space:]]*\(\)//' | sort -u)
EXPECTED_AI_DETECT=$(echo "_ai_cache_clean_detect
_ai_cli_diagnostic_detect
_ai_debug_switch_detect
_ai_health_json_detect
_ai_log_rotation_detect
_ai_struct_log_detect" | sort -u)

if [[ "$ALL_AI_DETECT" == "$EXPECTED_AI_DETECT" ]]; then
    echo "  PASS  P4-b: _ai_*_detect 命名闭集精确匹配 6 函数（无多余/缺失）"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  P4-b: _ai_*_detect 命名闭集破裂"
    echo "        expected: $(echo "$EXPECTED_AI_DETECT" | tr '\n' ' ')"
    echo "        actual:   $(echo "$ALL_AI_DETECT" | tr '\n' ' ')"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ── 汇总 ──────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  PASS: $PASS_COUNT    FAIL: $FAIL_COUNT"
echo "══════════════════════════════════════════════════════════════"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo "RESULT: FAIL (编号对齐契约违反)"
    exit 1
fi

echo "RESULT: PASS (Dim 编号 1-13 连续 + Dim 13 唯一 + 8 函数 + 6 客观信号覆盖 holds)"
exit 0
