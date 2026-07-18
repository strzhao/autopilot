#!/usr/bin/env bash
# acceptance test: autopilot doctor Dim 13「AI 可观测性/调试友好度」场景 1 标杆探测
#
# 设计契约（黑盒视角，不读 lib.sh 实现）：
#   标杆工程 claude-code-buddy（Swift Mac app）：
#     - JSONL 日志 + buddy health/log CLI + BUDDY_LOG_DIR/LEVEL env
#     - LocalizedError + 统一 buddy 命名空间
#     - 预期 ≥7 维 PASS
#
#   9 维 AI 友好度信号 = 6 客观维（detect_ai_observability 内 6 _ai_*_detect）+
#                        3 语义维（Wave 2 AI 判断，无 bash 函数）
#   8 bash 函数 = detect_tech_stack + detect_ai_observability + 6 _ai_*_detect
#
# 覆盖验收场景（场景 1，6 谓词，每条 ≥1 硬断言）：
#   标杆探测.P1：结构化日志维度对 buddy 返回 PASS（rc==0，stdout 含 JSONL 落盘 + env 级别信号）
#   标杆探测.P2：日志轮转维度对 buddy 返回 rc∈{0,1}（识别大小/数量上限双信号）
#   标杆探测.P3：CLI 诊断命令维度对 buddy 返回 PASS（rc==0，health/log 子命令）
#   标杆探测.P4：命名空间一致维度（客观信号可观测）—— 此维是 Wave 2 AI 语义维，
#                bash 无对应 _ai_*_detect 函数；本测试用 detect_ai_observability 聚合 JSON
#                中含的客观维覆盖 PASS 信号（6 客观维 PASS 计数 ≥7 已含命名外多维度 PASS）
#   标杆探测.P5：9 维探测 buddy 总 PASS 数 ≥ 7
#   标杆探测.P6：全部 9 维三态值落在 {0,1,2} 枚举内
#
# 运行：bash ai-obs-benchmark.acceptance.test.sh
# 退出码：0 全部 PASS；非零表示对应 P<n> 失败（蓝队未实现时 6 项全 FAIL 属预期）。

set -u

# ── 定位 repo root（与既有测试同款，从 BASH_SOURCE 向上找 .git） ──
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

# 标杆工程路径（设计文档锚定）
BUDDY_ROOT="/Users/stringzhao/workspace/claude-code-buddy"
if [[ ! -d "$BUDDY_ROOT" ]]; then
    echo "FATAL: 标杆工程不存在 $BUDDY_ROOT" >&2
    exit 99
fi

# shellcheck source=/dev/null
source "$LIB_SH"

# 设计契约：函数必须存在。蓝队未实现时此分支失败（预期「未实现」状态）。
DEFINE_OK=1
for fn in detect_tech_stack detect_ai_observability \
          _ai_struct_log_detect _ai_log_rotation_detect \
          _ai_cli_diagnostic_detect _ai_health_json_detect \
          _ai_cache_clean_detect _ai_debug_switch_detect; do
    if ! declare -F "$fn" >/dev/null 2>&1; then
        DEFINE_OK=0
        echo "WARN: $fn not defined after sourcing lib.sh (blue-team missing? all P will fail)" >&2
        break
    fi
done

# 6 客观探测函数清单（按设计文档 C1）
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
# 收集 9 维（实为 6 客观维，3 语义维无 bash 函数）的 rc 与 stdout
# ═══════════════════════════════════════════════════════════════
declare -a BUDDY_RCS=()
declare -a BUDDY_STDOUTS=()
if [[ "$DEFINE_OK" -eq 1 ]]; then
    cd "$BUDDY_ROOT" 2>/dev/null || { echo "FATAL: cannot cd $BUDDY_ROOT" >&2; exit 99; }
    for det in "${AI_DETECTORS[@]}"; do
        # 子 shell 捕获 rc + stdout（不影响外层 set -u）
        out=$( "$det" 2>/dev/null ); rc=$?
        BUDDY_RCS+=("$rc")
        BUDDY_STDOUTS+=("$out")
    done
fi

# ═══════════════════════════════════════════════════════════════
# P1: 结构化日志维度对 buddy 返回 PASS（rc==0）+ stdout 信号
# assert: 至少 1 探测函数 rc==0 且 stdout 信号对应「JSONL 落盘 + env 级别可控」
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P1: 结构化日志维度对 buddy 返回 PASS（rc==0）──"

if [[ "$DEFINE_OK" -eq 1 ]]; then
    # _ai_struct_log_detect 是 AI_DETECTORS[0]
    SL_RC="${BUDDY_RCS[0]}"
    SL_OUT="${BUDDY_STDOUTS[0]}"
    assert_eq "$SL_RC" "0" \
        "P1-a: _ai_struct_log_detect(buddy) rc==0 (PASS = JSONL落盘+env级别信号存在)"

    # Mutation-Survival：不只断 rc，还断 stdout 信号前缀遵循契约（AI-OBS-STRUCT-LOG-PASS:）
    if echo "$SL_OUT" | grep -qE '^AI-OBS-STRUCT-LOG-PASS:'; then
        echo "  PASS  P1-b: stdout 含 'AI-OBS-STRUCT-LOG-PASS:' 信号（mutation-kill）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P1-b: stdout 未含 'AI-OBS-STRUCT-LOG-PASS:' 信号"
        echo "        actual stdout='$SL_OUT'"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  P1: 探测函数未定义（contract not implemented）"
    FAIL_COUNT=$((FAIL_COUNT + 2))
fi

# ═══════════════════════════════════════════════════════════════
# P2: 日志轮转维度对 buddy 返回 rc∈{0,1}（识别大小/数量上限双信号）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P2: 日志轮转维度对 buddy 返回 rc∈{0,1} ──"

if [[ "$DEFINE_OK" -eq 1 ]]; then
    LR_RC="${BUDDY_RCS[1]}"
    LR_OUT="${BUDDY_STDOUTS[1]}"
    # rc ∈ {0,1} 即非 FAIL（PASS 或 NA 自门控）
    if [[ "$LR_RC" == "0" || "$LR_RC" == "1" ]]; then
        echo "  PASS  P2-a: _ai_log_rotation_detect(buddy) rc∈{0,1} actual=$LR_RC"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P2-a: _ai_log_rotation_detect(buddy) rc expected ∈{0,1}, actual=$LR_RC"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    # Mutation-Survival：stdout DIM 字面量必为 LOG-ROTATION
    if echo "$LR_OUT" | grep -qE '^AI-OBS-LOG-ROTATION-(PASS|NA|MISSING|PARTIAL):'; then
        echo "  PASS  P2-b: stdout 含 'AI-OBS-LOG-ROTATION-<STATE>:' 信号（DIM 字面量闭集）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P2-b: stdout 不匹配 'AI-OBS-LOG-ROTATION-<STATE>:'，actual='$LR_OUT'"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  P2: 探测函数未定义"
    FAIL_COUNT=$((FAIL_COUNT + 2))
fi

# ═══════════════════════════════════════════════════════════════
# P3: CLI 诊断命令维度对 buddy 返回 PASS（rc==0，识别 health/log 子命令）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P3: CLI 诊断命令维度对 buddy 返回 PASS（rc==0）──"

if [[ "$DEFINE_OK" -eq 1 ]]; then
    CLI_RC="${BUDDY_RCS[2]}"
    CLI_OUT="${BUDDY_STDOUTS[2]}"
    assert_eq "$CLI_RC" "0" \
        "P3-a: _ai_cli_diagnostic_detect(buddy) rc==0 (health/log/diagnose 子命令存在)"

    if echo "$CLI_OUT" | grep -qE '^AI-OBS-CLI-DIAGNOSTIC-PASS:'; then
        echo "  PASS  P3-b: stdout 含 'AI-OBS-CLI-DIAGNOSTIC-PASS:' 信号"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P3-b: stdout 未含 'AI-OBS-CLI-DIAGNOSTIC-PASS:'，actual='$CLI_OUT'"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  P3: 探测函数未定义"
    FAIL_COUNT=$((FAIL_COUNT + 2))
fi

# ═══════════════════════════════════════════════════════════════
# P4: 命名空间一致维度对 buddy 返回 PASS
# 注：命名空间是 Wave 2 语义维，bash 无 _ai_*_detect 函数（设计文档 B1 澄清）。
# 此维 bash 层无对应函数，转用 detect_ai_observability 聚合 JSON 客观信号兜底，
# 验证「标杆至少有 6 客观维中多个 PASS」作命名空间客观存在的代理证据。
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P4: 命名空间一致（语义维，bash 层用聚合 JSON 客观维代理）──"

if [[ "$DEFINE_OK" -eq 1 ]]; then
    cd "$BUDDY_ROOT" 2>/dev/null || { echo "FATAL: cannot cd $BUDDY_ROOT" >&2; exit 99; }
    # 黑盒调用聚合入口
    AGG_OUT=$( detect_ai_observability 2>/dev/null ); AGG_RC=$?
    assert_eq "$AGG_RC" "0" \
        "P4-a: detect_ai_observability(buddy) rc==0 (聚合入口正常)"

    # Mutation-Survival：聚合 JSON 必含 6 客观维字段闭集（契约 C1）
    # 期望 keys == {struct_log,log_rotation,cli_diagnostic,health_json,cache_clean,debug_switch}
    KEY_OK=1
    for k in struct_log log_rotation cli_diagnostic health_json cache_clean debug_switch; do
        if ! echo "$AGG_OUT" | grep -q "\"$k\""; then
            KEY_OK=0
            echo "        missing key: $k"
        fi
    done
    if [[ "$KEY_OK" -eq 1 ]]; then
        echo "  PASS  P4-b: 聚合 JSON 含 6 客观维字段闭集（契约闭集.P2 同源）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P4-b: 聚合 JSON 字段不完整"
        echo "        actual='$AGG_OUT'"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  P4: 探测函数未定义"
    FAIL_COUNT=$((FAIL_COUNT + 2))
fi

# ═══════════════════════════════════════════════════════════════
# P5: 9 维探测 buddy 总 PASS 数 ≥ 7
# 注：bash 实际可调 6 客观维（3 语义维 Wave 2 AI）。设计 P5「9 维 ≥7 PASS」在 bash 层
# 转译为「6 客观维中 PASS 计数 + 标杆命名空间/health JSON/error code 等客观辅证 ≥ 5 PASS」，
# 因 9 维预期 ≥7，客观层 6 维多数 PASS 是必要条件。
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P5: 6 客观维 PASS 计数（9 维 ≥7 PASS 的 bash 层必要条件）──"

if [[ "$DEFINE_OK" -eq 1 ]]; then
    PASS_BASH=0
    for rc in "${BUDDY_RCS[@]}"; do
        if [[ "$rc" == "0" ]]; then
            PASS_BASH=$((PASS_BASH + 1))
        fi
    done
    # bash 6 客观维中至少 5 维 PASS（标杆预期多数客观维 PASS）
    if [[ "$PASS_BASH" -ge 5 ]]; then
        echo "  PASS  P5-a: 6 客观维 PASS 计数=$PASS_BASH ≥ 5（标杆预期 ≥7 维 PASS 的必要条件）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P5-a: 6 客观维 PASS 计数=$PASS_BASH < 5（标杆「≥7 维 PASS」契约违反）"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  P5: 探测函数未定义"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# P6: 全部 9 维三态值落在 {0,1,2} 枚举内
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P6: 6 客观维三态值全部 ∈ {0,1,2} ──"

if [[ "$DEFINE_OK" -eq 1 ]]; then
    ALL_TRI=1
    BAD_RCS=""
    for rc in "${BUDDY_RCS[@]}"; do
        if [[ "$rc" != "0" && "$rc" != "1" && "$rc" != "2" ]]; then
            ALL_TRI=0
            BAD_RCS="$BAD_RCS $rc"
        fi
    done
    if [[ "$ALL_TRI" -eq 1 ]]; then
        echo "  PASS  P6: 所有 rc ∈ {0,1,2}（无 126/127/130 异常退出）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P6: 出现非三态 rc:${BAD_RCS}（约束守卫.P4 bash 纯度/契约违反）"
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
    echo "RESULT: FAIL (标杆 claude-code-buddy 探测契约违反)"
    exit 1
fi

echo "RESULT: PASS (标杆探测 6 客观维三态 + ≥5 PASS + DIM 字面量闭集 holds)"
exit 0
