#!/usr/bin/env bash
# acceptance test: autopilot doctor Dim 13 契约闭集（场景 8，I2/I3/I4 修复验证）
#
# 设计契约（黑盒视角，不读 lib.sh 实现）：
#   C1: detect_tech_stack → JSON 7 字段 {node,swift,go,python,rust,java,primary}
#       primary ∈ {node,swift,go,python,rust,java,unknown}
#   C1: detect_ai_observability → JSON 6 字段各 {status,value}，status ∈ {pass,warn,na}
#   C1: PARTIAL 触发路径（health 命令存在但输出非 JSON 等）
#   C2: 权重表小数 sum=1.00（Dim 13=0.05，其余 12 维 sum=0.95）
#
# 覆盖验收场景（场景 8，3 谓词，每条 ≥1 硬断言）：
#   契约闭集.P1：PARTIAL 状态可触发（构造夹具，stdout 含 AI-OBS-HEALTH-JSON-PARTIAL:）
#   契约闭集.P2：detect_tech_stack 返回 7 字段闭集 + primary 合法
#   契约闭集.P3：权重表小数 sum=1.00
#
# 运行：bash ai-obs-contract-closure.acceptance.test.sh

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

LIB_SH="$REPO_ROOT/plugins/autopilot/scripts/lib.sh"
SKILL_MD="$REPO_ROOT/plugins/autopilot/skills/autopilot-doctor/SKILL.md"
if [[ ! -f "$LIB_SH" ]]; then
    echo "FATAL: lib.sh 不存在" >&2
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
        echo "WARN: $fn not defined (blue-team missing?)" >&2
        break
    fi
done

PASS_COUNT=0
FAIL_COUNT=0

# ═══════════════════════════════════════════════════════════════
# P1: PARTIAL 状态可触发
# 构造夹具：health 命令存在但输出非 JSON（jq 解析失败）
# assert: detect_ai_observability 返回的 health_json.status == "warn"
#         且 stdout 含 AI-OBS-HEALTH-JSON-PARTIAL: 信号
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P1: PARTIAL 状态可触发（health 存在但输出非 JSON）──"

# 构造夹具：含 package.json + scripts.health，但 health 命令输出非 JSON
TMP_PARTIAL="$(mktemp -d -t autopilot-partial-XXXXXX)"
cleanup() {
    [[ -n "$TMP_PARTIAL" ]] && [[ -d "$TMP_PARTIAL" ]] && rm -rf "$TMP_PARTIAL"
}
trap cleanup EXIT

cat > "$TMP_PARTIAL/package.json" <<'EOF'
{
  "name": "partial-fixture",
  "scripts": {
    "health": "echo 'health: ok (not JSON)'",
    "log": "echo 'log: line1'"
  }
}
EOF

# 创建一个 logs 目录占位（确保结构完整）
mkdir -p "$TMP_PARTIAL/logs"

if [[ "$DEFINE_OK" -eq 1 ]]; then
    cd "$TMP_PARTIAL" 2>/dev/null || { echo "FATAL: cannot cd $TMP_PARTIAL" >&2; exit 99; }

    # 直接调 _ai_health_json_detect（黑盒，应识别 health 命令存在但 jq 解析失败 → PARTIAL）
    HJ_OUT=$( _ai_health_json_detect 2>/dev/null ); HJ_RC=$?

    # 期望：rc=2（PARTIAL 归为 warn 等价 rc=2）或 stdout 含 PARTIAL 信号
    # 注：PARTIAL 在三态中归 rc=2（warn）+ STATE=PARTIAL 信号
    # 设计契约 C1 I2：PARTIAL = 信号部分存在（health 命令存在但输出 jq 解析失败）。
    # 夹具 package.json scripts.health 存在但输出非 JSON —— 蓝队应识别为 PARTIAL 而非 MISSING。
    # 若 FAIL：说明蓝队未把 npm scripts.health 视作「health 命令存在」信号源（设计契约违反）。
    if echo "$HJ_OUT" | grep -qE 'AI-OBS-HEALTH-JSON-PARTIAL:'; then
        echo "  PASS  P1-a: _ai_health_json_detect 输出含 AI-OBS-HEALTH-JSON-PARTIAL: 信号（PARTIAL 触发）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P1-a: _ai_health_json_detect 未输出 PARTIAL 信号（蓝队判 MISSING，未识别 npm scripts.health）"
        echo "        rc=$HJ_RC stdout='$HJ_OUT'"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    # Mutation-Survival：聚合入口 detect_ai_observability health_json.status == "warn"
    AGG_OUT=$( detect_ai_observability 2>/dev/null ); AGG_RC=$?
    # 提取 health_json.status 值（粗 JSON 解析，无 jq 依赖）
    HJ_STATUS=$(echo "$AGG_OUT" | grep -oE '"health_json"[[:space:]]*:[[:space:]]*\{[^}]*\}' \
        | grep -oE '"status"[[:space:]]*:[[:space:]]*"[a-z]+"' \
        | grep -oE '"[a-z]+"$' | tr -d '"')
    if [[ "$HJ_STATUS" == "warn" ]]; then
        echo "  PASS  P1-b: detect_ai_observability health_json.status==${HJ_STATUS}（PARTIAL→warn）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P1-b: detect_ai_observability health_json.status='$HJ_STATUS' 期望 'warn'"
        echo "        agg stdout='$AGG_OUT'"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  P1: 探测函数未定义"
    FAIL_COUNT=$((FAIL_COUNT + 2))
fi

# ═══════════════════════════════════════════════════════════════
# P2: detect_tech_stack 返回 7 字段闭集 + primary 合法
# 对标杆/对照工程各调一次
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P2: detect_tech_stack 7 字段闭集 + primary 合法 ──"

TS_CLOSURE="node swift go python rust java primary"
PRIMARY_CLOSURE='node|swift|go|python|rust|java|unknown'

check_tech_stack() {
    local project_root="$1" label="$2"
    if [[ ! -d "$project_root" ]]; then
        echo "  FAIL  $label: $project_root 不存在"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return
    fi
    cd "$project_root" 2>/dev/null || { echo "  FAIL  $label: cannot cd"; FAIL_COUNT=$((FAIL_COUNT + 1)); return; }
    local out rc
    out=$( detect_tech_stack 2>/dev/null ); rc=$?

    if [[ "$rc" -ne 0 ]]; then
        echo "  FAIL  $label-a: detect_tech_stack rc=$rc 期望 0"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        echo "  PASS  $label-a: detect_tech_stack rc==0"
        PASS_COUNT=$((PASS_COUNT + 1))
    fi

    # 检查 7 字段闭集
    local missing=""
    for k in $TS_CLOSURE; do
        if ! echo "$out" | grep -q "\"$k\""; then
            missing="$missing $k"
        fi
    done
    if [[ -z "$missing" ]]; then
        echo "  PASS  $label-b: 含 7 字段闭集 {node,swift,go,python,rust,java,primary}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  $label-b: 缺字段：$missing"
        echo "        out='$out'"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    # primary 合法性
    local primary_val
    primary_val=$(echo "$out" | grep -oE '"primary"[[:space:]]*:[[:space:]]*"[a-z]+"' \
        | grep -oE '"[a-z]+"$' | tr -d '"')
    if echo "$primary_val" | grep -qE "^($PRIMARY_CLOSURE)\$"; then
        echo "  PASS  $label-c: primary='$primary_val' ∈ 闭集 {node,swift,go,python,rust,java,unknown}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  $label-c: primary='$primary_val' 不在闭集"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    # Mutation-Survival：detect_tech_stack 输出无 7 字段外的额外键
    # 提取所有 JSON 顶层键，与闭集比对
    local all_keys
    all_keys=$(echo "$out" | grep -oE '"[a-z_]+"' | tr -d '"' | sort -u | tr '\n' ' ')
    local unexpected=""
    for k in $all_keys; do
        local in_closure=0
        for c in $TS_CLOSURE; do
            if [[ "$k" == "$c" ]]; then in_closure=1; break; fi
        done
        if [[ "$in_closure" -eq 0 ]]; then
            unexpected="$unexpected $k"
        fi
    done
    if [[ -z "$unexpected" ]]; then
        echo "  PASS  $label-d: 无闭集外额外键（闭集精确）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  $label-d: 含闭集外键：$unexpected"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

if [[ "$DEFINE_OK" -eq 1 ]]; then
    check_tech_stack "/Users/stringzhao/workspace/claude-code-buddy" "P2-buddy"
    check_tech_stack "/Users/stringzhao/workspace/little-bee" "P2-lb"
else
    echo "  FAIL  P2: 探测函数未定义"
    FAIL_COUNT=$((FAIL_COUNT + 8))
fi

# ═══════════════════════════════════════════════════════════════
# P3: 权重表小数 sum=1.00
# Dim 13=0.05，其余 12 维 sum=0.95
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P3: SKILL.md 权重表小数 sum=1.00 ──"

if [[ -f "$SKILL_MD" ]]; then
    # 提取权重段（设计文档：约行 429-440），特征：含 0.XX 小数 + Dim 行
    # 红队信息隔离：不读 SKILL.md 实际结构，用宽容提取——
    # 任何同时含 `Dim N` 和 `0.XX` 小数的行，提取该行所有 0.XX-0.99 的小数
    # （权重必在 [0,1) 区间；排除 v3.57.0 这类版本号——它们不是 0.XX 形式）
    # 只提取权重表行（^| Dim N ... | 0.XX |）每行一个权重值，避免抓说明文字的多余 0.XX
    WEIGHT_NUMS=$(awk '
        /^\|[[:space:]]*Dim[[:space:]]+[0-9]/ && /0\.[0-9]+/ {
            if (match($0, /0\.[0-9]+/)) print substr($0, RSTART, RLENGTH)
        }
    ' "$SKILL_MD" 2>/dev/null)

    if [[ -z "$WEIGHT_NUMS" ]]; then
        echo "  FAIL  P3: SKILL.md 未提取到权重小数（结构变更？）"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        # 求和（bash 算浮点用 awk）
        WEIGHT_SUM=$(echo "$WEIGHT_NUMS" | awk '{s+=$1} END {printf "%.4f", s}')
        # 容差 1e-9
        if awk -v s="$WEIGHT_SUM" 'BEGIN {exit !(s >= 0.9999 && s <= 1.0001)}'; then
            echo "  PASS  P3-a: 权重小数 sum=$WEIGHT_SUM ≈ 1.00（13 维权重归一）"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            echo "  FAIL  P3-a: 权重小数 sum=$WEIGHT_SUM 偏离 1.00（容差 ±0.0001）"
            echo "        weights: $(echo "$WEIGHT_NUMS" | tr '\n' ' ')"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi

        # Mutation-Survival：必含 Dim 13 权重 0.05
        if echo "$WEIGHT_NUMS" | grep -qE '^0\.0[0-9]+$'; then
            # 至少有一个 ≤0.05 的小权重（Dim 13=0.05 新增的标志）
            HAS_SMALL=$(echo "$WEIGHT_NUMS" | awk '$1 <= 0.05 {print "y"}' | head -1)
            if [[ -n "$HAS_SMALL" ]]; then
                echo "  PASS  P3-b: 权重表含 ≤0.05 小权重（Dim 13 保守权重）"
                PASS_COUNT=$((PASS_COUNT + 1))
            else
                echo "  FAIL  P3-b: 权重表无 ≤0.05 小权重（Dim 13 缺失？）"
                FAIL_COUNT=$((FAIL_COUNT + 1))
            fi
        else
            echo "  FAIL  P3-b: 权重表无 ≤0.05 小权重"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    fi
else
    echo "  FAIL  P3: SKILL.md 不存在"
    FAIL_COUNT=$((FAIL_COUNT + 2))
fi

# ── 汇总 ──────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "  PASS: $PASS_COUNT    FAIL: $FAIL_COUNT"
echo "════════════════════════════════════════"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo "RESULT: FAIL (契约闭集违反：PARTIAL/7 字段/权重 sum)"
    exit 1
fi

echo "RESULT: PASS (契约闭集 3 谓词 + PARTIAL 触发 + 7 字段闭集 + 权重 sum=1.00 holds)"
exit 0
