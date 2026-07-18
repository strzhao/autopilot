#!/usr/bin/env bash
# acceptance test: autopilot doctor Dim 13 边界情形（场景 6）
#
# 设计契约（黑盒视角，不读 lib.sh 实现）：
#   纯脚本项目无 package.json/logs 目录：
#     - 多数维 na（rc==1）或 FAIL（rc==2）
#     - 不崩溃；report 显示 N/A
#
# 覆盖验收场景（场景 6，4 谓词，每条 ≥1 硬断言）：
#   边界情形.P1：纯脚本项目 ≥5 维返回 na 或 FAIL
#   边界情形.P2：探测函数无异常退出码（所有 rc ∈ {0,1,2}，无 126/127/130）
#   边界情形.P3：探测函数 stderr 无未捕获异常栈（不含 command not found/syntax error/Traceback）
#   边界情形.P4：doctor 报告对 na 维显示 N/A 标记（SKILL.md 必含 N/A 处理逻辑）
#
# 运行：bash ai-obs-edge-case.acceptance.test.sh

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
    echo "FATAL: lib.sh not found at $LIB_SH" >&2
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

# ── 构造纯脚本项目夹具（无 package.json/logs 目录） ──
TMP_PURE="$(mktemp -d -t autopilot-pure-XXXXXX)"
cleanup() {
    [[ -n "$TMP_PURE" ]] && [[ -d "$TMP_PURE" ]] && rm -rf "$TMP_PURE"
}
trap cleanup EXIT

# 仅放一个 .sh 脚本 + README，无任何 package.json/Info.plist/go.mod 等
cat > "$TMP_PURE/my-tool.sh" <<'EOF'
#!/usr/bin/env bash
echo "hello"
EOF
cat > "$TMP_PURE/README.md" <<'EOF'
# my-tool
Pure bash project, no deps.
EOF

PASS_COUNT=0
FAIL_COUNT=0

# ═══════════════════════════════════════════════════════════════
# 收集 6 客观维 rc + stderr（在纯脚本项目夹具中）
# ═══════════════════════════════════════════════════════════════
declare -a PURE_RCS=()
declare -a PURE_STDOUTS=()
PURE_STDERR_ALL=""
if [[ "$DEFINE_OK" -eq 1 ]]; then
    cd "$TMP_PURE" 2>/dev/null || { echo "FATAL: cannot cd $TMP_PURE" >&2; exit 99; }
    for det in "${AI_DETECTORS[@]}"; do
        # 显式捕获 stderr 到独立文件
        _err_file="$(mktemp -t pure-stderr-XXXXXX)"
        out=$( "$det" 2>"$_err_file" ); rc=$?
        err="$(cat "$_err_file")"
        rm -f "$_err_file"
        PURE_RCS+=("$rc")
        PURE_STDOUTS+=("$out")
        if [[ -n "$err" ]]; then
            PURE_STDERR_ALL="$PURE_STDERR_ALL
$err"
        fi
    done
    unset _err_file
fi

# ═══════════════════════════════════════════════════════════════
# P1: 纯脚本项目 ≥5 维返回 na 或 FAIL
# bash 层 6 客观维 rc∈{1,2}（自门控 na 或 warn FAIL）计数 ≥4 是必要条件
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P1: 纯脚本项目 6 客观维 rc∈{1,2} 计数 ──"

if [[ "$DEFINE_OK" -eq 1 ]]; then
    NA_FAIL=0
    for rc in "${PURE_RCS[@]}"; do
        if [[ "$rc" == "1" || "$rc" == "2" ]]; then
            NA_FAIL=$((NA_FAIL + 1))
        fi
    done
    # 9 维 ≥5 是 bash 层 6 维中 ≥4 的必要条件（na 优先，自门控）
    if [[ "$NA_FAIL" -ge 4 ]]; then
        echo "  PASS  P1: 纯脚本 6 客观维 na/FAIL 计数=$NA_FAIL ≥ 4（≥5 维 na/FAIL 必要条件）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P1: 纯脚本 na/FAIL 计数=$NA_FAIL < 4（边界情形契约违反）"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    # Mutation-Survival：纯脚本项目至少有 1 维返回 rc=1（自门控 na，对齐 solve-don't-punt）
    NA_ONLY=0
    for rc in "${PURE_RCS[@]}"; do
        if [[ "$rc" == "1" ]]; then
            NA_ONLY=$((NA_ONLY + 1))
        fi
    done
    if [[ "$NA_ONLY" -ge 1 ]]; then
        echo "  PASS  P1-b: 纯脚本项目 ≥1 维 na 自门控（rc==1 计数=${NA_ONLY}，对齐 solve-don't-punt）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P1-b: 纯脚本项目无 rc==1（自门控未生效，违反 solve-don't-punt）"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  P1: 探测函数未定义"
    FAIL_COUNT=$((FAIL_COUNT + 2))
fi

# ═══════════════════════════════════════════════════════════════
# P2: 探测函数无异常退出码（所有 rc ∈ {0,1,2}，无 126/127/130）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P2: 探测函数无异常退出码 ──"

if [[ "$DEFINE_OK" -eq 1 ]]; then
    ALL_TRI=1
    BAD_RCS=""
    for rc in "${PURE_RCS[@]}"; do
        if [[ "$rc" != "0" && "$rc" != "1" && "$rc" != "2" ]]; then
            ALL_TRI=0
            BAD_RCS="$BAD_RCS $rc"
        fi
    done
    if [[ "$ALL_TRI" -eq 1 ]]; then
        echo "  PASS  P2: 纯脚本探测所有 rc ∈ {0,1,2}（无 126/127/130）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P2: 出现异常 rc:$BAD_RCS"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  P2: 探测函数未定义"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# P3: 探测函数 stderr 无未捕获异常栈
# assert: 不含 command not found / syntax error / Traceback
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P3: 探测函数 stderr 无未捕获异常栈 ──"

if [[ "$DEFINE_OK" -eq 1 ]]; then
    if echo "$PURE_STDERR_ALL" | grep -qE '(command not found|syntax error|Traceback|line [0-9]+:)'; then
        echo "  FAIL  P3: stderr 含异常栈"
        echo "        stderr='$PURE_STDERR_ALL'"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        echo "  PASS  P3: stderr 无未捕获异常栈（command not found/syntax error/Traceback）"
        PASS_COUNT=$((PASS_COUNT + 1))
    fi
else
    echo "  FAIL  P3: 探测函数未定义"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# P4: doctor 报告对 na 维显示 N/A 标记
# CONTRACT_AMBIGUOUS: 报告产物路径依赖 doctor 真跑，本测试静态契约层：
#                     SKILL.md 必含 N/A 处理逻辑（Dim 13 满分不计入 → 对齐 Dim 11/12）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P4: SKILL.md 含 Dim 13 N/A 处理逻辑 ──"

if [[ -f "$SKILL_MD" ]]; then
    # 设计契约 C2 N/A 条件：纯脚本项目（detect_tech_stack 全 false）→ Dim 13 满分不计入
    # SKILL.md 必含 N/A 处理规则
    if grep -qE '(N/A|NA|不计入|满分不计入|纯脚本)' "$SKILL_MD"; then
        echo "  PASS  P4-a: SKILL.md 含 N/A/不计入 关键词（na 维处理逻辑）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P4-a: SKILL.md 无 N/A 处理逻辑"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    # Mutation-Survival：Dim 13 段必须明确引用 detect_tech_stack 全 false 触发 N/A
    if grep -qE 'detect_tech_stack' "$SKILL_MD"; then
        echo "  PASS  P4-b: SKILL.md 引用 detect_tech_stack（Dim 13 自门控入口）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P4-b: SKILL.md 未引用 detect_tech_stack（Dim 13 Wave 1 收集契约违反）"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  P4: SKILL.md 不存在"
    FAIL_COUNT=$((FAIL_COUNT + 2))
fi

# ── 汇总 ──────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "  PASS: $PASS_COUNT    FAIL: $FAIL_COUNT"
echo "════════════════════════════════════════"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo "RESULT: FAIL (边界情形契约违反：na/异常/stderr/N/A 处理)"
    exit 1
fi

echo "RESULT: PASS (边界情形 4 谓词 holds)"
exit 0
