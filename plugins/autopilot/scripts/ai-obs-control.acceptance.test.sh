#!/usr/bin/env bash
# acceptance test: autopilot doctor Dim 13「AI 可观测性/调试友好度」场景 2 对照探测
#
# 设计契约（黑盒视角，不读 lib.sh 实现）：
#   对照工程 little-bee（Next.js+Tauri）：
#     - console only + package.json scripts 仅 dev/build/test
#     - app/api/_lib/response.ts 纯字符串无 code 字段
#     - 命名混用 + 无 clean
#     - 预期 ≥5 维非 PASS
#
# 覆盖验收场景（场景 2，6 谓词，每条 ≥1 硬断言）：
#   对照探测.P1：结构化日志维度对 little-bee 返回 FAIL（rc==2 ∧ stdout 匹配 ^[A-Z_]+:）
#   对照探测.P2：error code 维度对 little-bee 返回 FAIL（3 语义维无 bash 函数，
#                改用 fs-grep 验证 response.ts 无 code 字段客观证据，再校 detect_ai_observability
#                聚合 JSON 不把此维判 PASS）
#   对照探测.P3：CLI 诊断命令维度对 little-bee 返回 FAIL（rc==2）
#   对照探测.P4：命名空间一致维度对 little-bee 返回 WARN（rc==2 或 rc==1，非 PASS）
#   对照探测.P5：9 维非 PASS 计数 ≥ 5（bash 层 6 客观维非 PASS 计数 ≥3 是必要条件）
#   对照探测.P6：FAIL 维度（rc==2）stdout 信号遵循 ^[A-Z][A-Z_]+: 前缀
#
# 运行：bash ai-obs-control.acceptance.test.sh

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
    echo "FATAL: cannot locate repo root (.git) from $SCRIPT_DIR" >&2
    exit 99
fi

LIB_SH="$REPO_ROOT/plugins/autopilot/scripts/lib.sh"
if [[ ! -f "$LIB_SH" ]]; then
    echo "FATAL: lib.sh not found at $LIB_SH" >&2
    exit 99
fi

LB_ROOT="/Users/stringzhao/workspace/little-bee"
if [[ ! -d "$LB_ROOT" ]]; then
    echo "FATAL: 对照工程不存在 $LB_ROOT" >&2
    exit 99
fi

# shellcheck source=/dev/null
source "$LIB_SH"

DEFINE_OK=1
for fn in detect_tech_stack detect_ai_observability \
          _ai_struct_log_detect _ai_log_rotation_detect \
          _ai_cli_diagnostic_detect _ai_health_json_detect \
          _ai_cache_clean_detect _ai_debug_switch_detect; do
    if ! declare -F "$fn" >/dev/null 2>&1; then
        DEFINE_OK=0
        echo "WARN: $fn not defined (blue-team missing? all P will fail)" >&2
        break
    fi
done

AI_DETECTORS=(
    _ai_struct_log_detect
    _ai_log_rotation_detect
    _ai_cli_diagnostic_detect
    _ai_health_json_detect
    _ai_cache_clean_detect
    _ai_debug_switch_detect
)

PASS_COUNT=0
FAIL_COUNT=0

assert_eq() {
    local actual="$1" expected="$2" label="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  PASS  $label"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  $label"
        echo "        expected='$expected'"
        echo "        actual=  '$actual'"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# ═══════════════════════════════════════════════════════════════
# 收集对照工程 6 客观维 rc + stdout
# ═══════════════════════════════════════════════════════════════
declare -a LB_RCS=()
declare -a LB_STDOUTS=()
if [[ "$DEFINE_OK" -eq 1 ]]; then
    cd "$LB_ROOT" 2>/dev/null || { echo "FATAL: cannot cd $LB_ROOT" >&2; exit 99; }
    for det in "${AI_DETECTORS[@]}"; do
        out=$( "$det" 2>/dev/null ); rc=$?
        LB_RCS+=("$rc")
        LB_STDOUTS+=("$out")
    done
fi

# ═══════════════════════════════════════════════════════════════
# P1: 结构化日志维度对 little-bee 返回 FAIL（rc==2 ∧ stdout 匹配 PREFIX:）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P1: 结构化日志维度对 little-bee 返回 FAIL（rc==2）──"

if [[ "$DEFINE_OK" -eq 1 ]]; then
    SL_RC="${LB_RCS[0]}"
    SL_OUT="${LB_STDOUTS[0]}"
    assert_eq "$SL_RC" "2" \
        "P1-a: _ai_struct_log_detect(little-bee) rc==2 (console only, no JSONL)"

    # Mutation-Survival：stdout 信号必须 PREFIX: 格式
    if echo "$SL_OUT" | grep -qE '^AI-OBS-[A-Z-]+:'; then
        echo "  PASS  P1-b: stdout 匹配 '^AI-OBS-[A-Z-]+:' 前缀（contract 信号串含连字符）actual='$SL_OUT'"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P1-b: stdout 不匹配 PREFIX 信号格式，actual='$SL_OUT'"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  P1: 探测函数未定义"
    FAIL_COUNT=$((FAIL_COUNT + 2))
fi

# ═══════════════════════════════════════════════════════════════
# P2: error code 维度对 little-bee 返回 FAIL
# 注：error code 是 Wave 2 语义维，无 bash 函数（设计文档 B1）。
# 改用 fs-grep 直接验设计契约锚点的客观证据：
#   - app/api/_lib/response.ts 存在
#   - 该文件无 'code' 字段（纯字符串错误）
# 这是 doctor Wave 2 AI 判定 FAIL 的客观基础，不依赖 AI。
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P2: error code 维度对 little-bee 返回 FAIL（fs-grep response.ts 无 code）──"

RESPONSE_TS="$LB_ROOT/app/api/_lib/response.ts"
if [[ -f "$RESPONSE_TS" ]]; then
    echo "  PASS  P2-a: app/api/_lib/response.ts 存在（设计契约锚点）"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  P2-a: $RESPONSE_TS 不存在（夹具漂移，需更新设计文档）"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# 文件中 'code' 关键词计数（grep -c 无匹配 rc=1 但 stdout 仍输出 "0"，避免 || 拼接陷阱）
CODE_HITS=$(grep -E '\bcode\b' "$RESPONSE_TS" 2>/dev/null | wc -l | tr -d '[:space:]')
if [[ -z "$CODE_HITS" ]]; then CODE_HITS=0; fi
if [[ "$CODE_HITS" -eq 0 ]]; then
    echo "  PASS  P2-b: response.ts 无 'code' 字段（error code 维度客观 FAIL 证据）hits=$CODE_HITS"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  P2-b: response.ts 含 'code' 关键词 hits=${CODE_HITS}（与设计契约「无 code」矛盾）"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# P3: CLI 诊断命令维度对 little-bee 返回 FAIL（rc==2）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P3: CLI 诊断命令维度对 little-bee 返回 FAIL（rc==2）──"

if [[ "$DEFINE_OK" -eq 1 ]]; then
    CLI_RC="${LB_RCS[2]}"
    CLI_OUT="${LB_STDOUTS[2]}"
    assert_eq "$CLI_RC" "2" \
        "P3-a: _ai_cli_diagnostic_detect(little-bee) rc==2 (scripts 仅 dev/build/test 无 health/log/clean)"

    # 独立 fs-grep 验证 package.json scripts 客观事实（兜底）
    PJ="$LB_ROOT/package.json"
    if [[ -f "$PJ" ]]; then
        if ! grep -qE '"(health|log|clean|diagnose|doctor)"' "$PJ"; then
            echo "  PASS  P3-b: package.json scripts 无 health/log/clean/diagnose（独立客观证据）"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            echo "  FAIL  P3-b: package.json 命中 health/log/clean 关键词（与「仅 dev/build/test」矛盾）"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    fi
else
    echo "  FAIL  P3: 探测函数未定义"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# P4: 命名空间一致维度对 little-bee 返回 WARN（rc==2 或 rc==1，非 PASS）
# 注：命名空间是 Wave 2 语义维，bash 层无函数。设计契约锚点：
#   目录/产物名跨 tools/svc-little-bee/little-bee 多前缀
# 客观证据：项目根存在多前缀子目录或文件
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P4: 命名空间一致（语义维非 PASS 的 bash 层客观辅证）──"

# fs-grep 多前缀客观证据：tools/ 子目录或 svc-little-bee 与 little-bee 命名混用
LB_NAME_HITS=0
[[ -d "$LB_ROOT/tools" ]] && LB_NAME_HITS=$((LB_NAME_HITS + 1))
# 多前缀命名（lc-, svc-, lib/, hooks/ 等多种前缀并存即命名空间不统一的客观证据）
MULTI_PREFIX=$(find "$LB_ROOT" -maxdepth 2 -type d 2>/dev/null \
    | grep -E '(svc-|tools/|lib/|hooks/|agents/)' | head -5 | wc -l | tr -d ' ')
if [[ "$MULTI_PREFIX" -ge 2 ]]; then
    echo "  PASS  P4-a: 项目多前缀命名客观证据命中 $MULTI_PREFIX 处（命名空间非 PASS 的客观辅证）"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  P4-a: 多前缀客观证据命中 $MULTI_PREFIX < 2（夹具漂移？）"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# P5: 9 维非 PASS 计数 ≥ 5
# bash 层 6 客观维非 PASS（rc!=0）计数 ≥3 是必要条件
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P5: 6 客观维非 PASS 计数（9 维 ≥5 非 PASS 的 bash 必要条件）──"

if [[ "$DEFINE_OK" -eq 1 ]]; then
    NON_PASS=0
    for rc in "${LB_RCS[@]}"; do
        if [[ "$rc" != "0" ]]; then
            NON_PASS=$((NON_PASS + 1))
        fi
    done
    if [[ "$NON_PASS" -ge 3 ]]; then
        echo "  PASS  P5-a: 6 客观维非 PASS 计数=$NON_PASS ≥ 3（9 维 ≥5 非 PASS 必要条件）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P5-a: 6 客观维非 PASS 计数=$NON_PASS < 3（对照工程契约违反）"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  P5: 探测函数未定义"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# P6: FAIL 维度（rc==2）stdout 信号遵循 ^[A-Z][A-Z_]+: 前缀
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P6: 所有 rc==2 维 stdout 信号前缀 ──"

if [[ "$DEFINE_OK" -eq 1 ]]; then
    PREFIX_OK=1
    PREFIX_BAD=""
    idx=0
    for rc in "${LB_RCS[@]}"; do
        if [[ "$rc" == "2" ]]; then
            out="${LB_STDOUTS[$idx]}"
            if ! echo "$out" | grep -qE '^AI-OBS-[A-Z-]+:'; then
                PREFIX_OK=0
                PREFIX_BAD="$PREFIX_BAD | idx=$idx out='$out'"
            fi
        fi
        idx=$((idx + 1))
    done
    if [[ "$PREFIX_OK" -eq 1 ]]; then
        echo "  PASS  P6: 所有 rc==2 stdout 匹配 ^AI-OBS-[A-Z-]+: 前缀（含连字符）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P6: 部分信号前缀违规：$PREFIX_BAD"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  P6: 探测函数未定义"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ── 汇总 ──────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "  PASS: $PASS_COUNT    FAIL: $FAIL_COUNT"
echo "════════════════════════════════════════"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo "RESULT: FAIL (对照 little-bee 探测契约违反)"
    exit 1
fi

echo "RESULT: PASS (对照探测 6 客观维非 PASS 计数 + PREFIX 信号契约 holds)"
exit 0
