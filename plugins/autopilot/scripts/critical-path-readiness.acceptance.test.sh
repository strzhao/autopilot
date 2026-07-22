#!/usr/bin/env bash
# acceptance test: autopilot doctor Dim 14「命脉链路 readiness 覆盖」契约闭集
#
# 红队视角（黑盒）：基于设计文档 + ## 验收场景 16 条预注册谓词编写。
# 不读蓝队新增的 Dim 14 实现段 / reference 实现内容，只做 fs-grep / 求和 / 枚举闭集检查。
#
# 设计契约（源自 state.md ## 设计文档 / ## 契约规约）：
#   C1: SKILL.md 维度数 13 → 14（新增 Dim 14「命脉链路 readiness 覆盖」）
#   C2: 权重 Σ(14 维) = 1.00（精确），容差 ±0.001
#   C3: Dim 14 权重 == 0.07，其余 13 维 sum == 0.93
#   C4: 6 维匀权（只降不增）：Dim1 0.14→0.12 / Dim2 0.11→0.10 / Dim3 0.10→0.09
#       / Dim4 0.10→0.09 / Dim5 0.07→0.06 / Dim10 0.07→0.06
#   C5: Dim 14 判分枚举 = {na, pass, warn, fail} 闭集
#   C6: 纯 AI 语义——lib.sh 不新增 critical_path/readiness/vital_path 函数
#   C7: reference 文件存在且非空（references/critical-path-readiness-principles.md）
#   C8: 命脉无覆盖应降级（warn/fail/降级语义），非假绿 A 级
#   C9: 红队验收测试自身存在且 exit 0 + stdout 含 PASS（场景6.P2 自举）
#
# 覆盖验收场景（场景 1-7 共 16 条谓词，每条 ≥1 硬断言）：
#   场景1.P1：SKILL.md 含 `^### Dim 14` 标题行（matches==1）
#   场景1.P2：SKILL.md 含「命脉链路」(count>=1)
#   场景1.P3：reference 存在且 bytes>=1
#   场景2.P1：四档 {na,pass,warn,fail} 在 Dim 14 章节内全部出现（count 各 >=1）
#   场景3.P1：权重表维度行数 == 14
#   场景3.P2：14 维权重 sum ∈ [0.999, 1.001]
#   场景4.P1：`Dim 14.*0\.07` 行上下文锚定（matches==1，正向判别 baseline 0）
#   场景4.P2：其余 13 维 sum ∈ [0.929, 0.931]
#   场景4.P3：六维各自权重精确（Dim1==0.12/Dim2==0.10/Dim3==0.09/Dim4==0.09/Dim5==0.06/Dim10==0.06）
#   场景5.P1：lib.sh 无 critical_path/readiness_check/vital_path 函数（count==0）
#   场景5.P1.NEGATE：lib.sh 无 detect_critical_path()（matches==0）
#   场景6.P1：本测试文件自身存在（stat，自举）
#   场景6.P2：本测试脚本 exit 0 + stdout 含 PASS（自举断言，由汇总段保证）
#   场景6.P3：脚本内覆盖 >=3 项不变量断言（Dim14存在/权重和=1.00/reference非空 三项 grep）
#   场景7.P1：SKILL.md Dim 14 章节附近含降级语义（warn/fail/降级）
#   场景7.P2：命脉段含 warn/fail/降级/不评A 任一（matches>=1）
#   场景7.P3.NEGATE：未覆盖附近 pass/na 不共现（co_occurrence==0）
#
# 运行：bash critical-path-readiness.acceptance.test.sh

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
REFERENCE="$REPO_ROOT/plugins/autopilot/skills/autopilot-doctor/references/critical-path-readiness-principles.md"
SELF_TEST="$REPO_ROOT/plugins/autopilot/scripts/critical-path-readiness.acceptance.test.sh"

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
# 场景1.P1: SKILL.md 含 `^### Dim 14` 标题行（matches == 1）
# 精确 H3 标题锚定，防兼容性矩阵/注释提及"Dim 14"误匹配（plan-reviewer 重要2）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 场景1.P1: SKILL.md 含 ^### Dim 14 标题（matches == 1）──"

# 用 grep -cE 直接计数（set -u 无 set -e，rc=1 不触发退出，$(...) 捕获 "0" 无双输出）
DIM14_H3_COUNT=$(grep -cE '^###[[:space:]]+Dim[[:space:]]+14\b' "$SKILL_MD" 2>/dev/null)
if [[ -z "$DIM14_H3_COUNT" ]]; then DIM14_H3_COUNT=0; fi

# Mutation-Survival：baseline（未实施）==0 → 实施 ==1；no-op mutation 必 FAIL
if [[ "$DIM14_H3_COUNT" -eq 1 ]]; then
    echo "  PASS  场景1.P1: ### Dim 14 标题唯一定义（count=${DIM14_H3_COUNT}）"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  场景1.P1: ### Dim 14 标题 count=${DIM14_H3_COUNT}（应 == 1）"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# 场景1.P2: SKILL.md 出现「命脉链路」维度名（count >= 1）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 场景1.P2: SKILL.md 含「命脉链路」(count >= 1) ──"

CRITICAL_PATH_MENTIONS=$(grep -cE '命脉链路' "$SKILL_MD" 2>/dev/null)
if [[ -z "$CRITICAL_PATH_MENTIONS" ]]; then CRITICAL_PATH_MENTIONS=0; fi

if [[ "$CRITICAL_PATH_MENTIONS" -ge 1 ]]; then
    echo "  PASS  场景1.P2: SKILL.md 提及「命脉链路」 count=${CRITICAL_PATH_MENTIONS}"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  场景1.P2: SKILL.md 无「命脉链路」字面（应 count >= 1）"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# 场景1.P3: reference 存在且 bytes >= 1
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 场景1.P3: reference 存在且非空（exists AND bytes >= 1）──"

if [[ -f "$REFERENCE" ]]; then
    REF_BYTES=$(wc -c < "$REFERENCE" | tr -d '[:space:]')
    if [[ -z "$REF_BYTES" ]]; then REF_BYTES=0; fi
    if [[ "$REF_BYTES" -ge 1 ]]; then
        echo "  PASS  场景1.P3: reference 存在且非空（bytes=${REF_BYTES}）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  场景1.P3: reference 存在但空文件（bytes=0）"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  场景1.P3: reference 不存在 $REFERENCE"
    REF_BYTES=0
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# 场景2.P1: 四档 {na, pass, warn, fail} 在 Dim 14 章节内全部出现
# 定位 Dim 14 章节（### Dim 14 起 → 下一个 ### 或文件尾）
# assert: count(na)>=1 AND count(pass)>=1 AND count(warn)>=1 AND count(fail)>=1
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 场景2.P1: Dim 14 章节四档枚举 {na,pass,warn,fail} 各 >=1 ──"

# 提取 Dim 14 章节文本（从 ### Dim 14 起，到下一个同级 ### 或 EOF）
# awk 段：进入 Dim 14 段后输出，直到遇到下一个 ^### 且非 Dim 14 段首行
# 注：BSD/macOS awk 不支持 \b 单词边界，用 [^0-9] 匹配 Dim 14 后非数字（: 或 空格）
DIM14_SECTION=$(awk '
    /^###[[:space:]]+Dim[[:space:]]+14[^0-9]/ { in_section=1; print; next }
    in_section && /^###[[:space:]]/ { exit }
    in_section { print }
' "$SKILL_MD" 2>/dev/null)

FOUR_TIER_PASS=1
FOUR_TIER_DETAIL=""
for tier in na pass warn fail; do
    # 在 Dim 14 段内 grep 单词边界（防 pass 匹配 password 等）
    TIER_COUNT=$(printf '%s' "$DIM14_SECTION" | grep -cE "\b${tier}\b" 2>/dev/null)
    if [[ -z "$TIER_COUNT" ]]; then TIER_COUNT=0; fi
    FOUR_TIER_DETAIL="${FOUR_TIER_DETAIL} ${tier}=${TIER_COUNT}"
    if [[ "$TIER_COUNT" -lt 1 ]]; then
        FOUR_TIER_PASS=0
    fi
done

if [[ "$FOUR_TIER_PASS" -eq 1 ]]; then
    echo "  PASS  场景2.P1: Dim 14 章节四档枚举全出现（${FOUR_TIER_DETAIL# }）"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  场景2.P1: Dim 14 章节四档不全出现（${FOUR_TIER_DETAIL# }）"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# 场景3.P1: 权重表维度行数 == 14
# observe: awk 匹配权重表 `| 0.` 行计数
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 场景3.P1: 权重表维度行数 == 14 ──"

WEIGHT_ROWS=$(awk '
    /^\|[[:space:]]*Dim[[:space:]]+[0-9]/ && /0\.[0-9]+/ { print }
' "$SKILL_MD" 2>/dev/null)
# 注：grep -c BRE 模式 '^|' 匹配行首竖线（字面），ERE 的 | 是元字符需转义
WEIGHT_ROW_COUNT=$(printf '%s' "$WEIGHT_ROWS" | grep -c '^|' 2>/dev/null)
if [[ -z "$WEIGHT_ROW_COUNT" ]]; then WEIGHT_ROW_COUNT=0; fi

# Mutation-Survival：baseline ==13 → 实施 ==14；no-op mutation 必 FAIL
if [[ "$WEIGHT_ROW_COUNT" -eq 14 ]]; then
    echo "  PASS  场景3.P1: 权重表维度行数 == 14"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  场景3.P1: 权重表维度行数 == ${WEIGHT_ROW_COUNT}（应 == 14）"
    echo "        rows: $(echo "$WEIGHT_ROWS" | tr '\n' '|')"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# 场景3.P2: 14 维权重 sum ∈ [0.999, 1.001]
# observe: awk 求和
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 场景3.P2: 14 维权重 sum ∈ [0.999, 1.001] ──"

WEIGHT_SUM=$(awk '
    /^\|[[:space:]]*Dim[[:space:]]+[0-9]/ && /0\.[0-9]+/ {
        if (match($0, /0\.[0-9]+/)) print substr($0, RSTART, RLENGTH)
    }
' "$SKILL_MD" 2>/dev/null | awk '{s+=$1} END {printf "%.4f", s}')

# bc 不可用兜底：用 awk 比较
SUM_IN_RANGE=$(awk -v s="$WEIGHT_SUM" 'BEGIN {
    if (s >= 0.999 && s <= 1.001) print "1"; else print "0"
}')

if [[ "$SUM_IN_RANGE" == "1" ]]; then
    echo "  PASS  场景3.P2: 权重 sum=${WEIGHT_SUM} ∈ [0.999, 1.001]"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  场景3.P2: 权重 sum=${WEIGHT_SUM} 越界 [0.999, 1.001]"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# 场景4.P1: `Dim 14.*0\.07` 行上下文锚定（matches == 1）
# 正向判别：baseline（未实施）此锚定==0 → 实施==1；避 Dim5/6/8/10 也=0.07 误匹配
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 场景4.P1: Dim 14 权重 == 0.07（行上下文锚定 matches == 1）──"

DIM14_007_COUNT=$(grep -cE 'Dim[[:space:]]+14.*0\.07' "$SKILL_MD" 2>/dev/null)
if [[ -z "$DIM14_007_COUNT" ]]; then DIM14_007_COUNT=0; fi

# Mutation-Survival：Dim 14 行必须含 0.07；改 0.06/0.08 必 FAIL
if [[ "$DIM14_007_COUNT" -eq 1 ]]; then
    echo "  PASS  场景4.P1: Dim 14 行含 0.07（matches=${DIM14_007_COUNT}）"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  场景4.P1: Dim 14.*0\.07 matches=${DIM14_007_COUNT}（应 == 1，baseline 0 → 实施 1）"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# 场景4.P2: 其余 13 维 sum ∈ [0.929, 0.931]
# observe: 14 维总和 - 0.07
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 场景4.P2: 其余 13 维 sum ∈ [0.929, 0.931] ──"

# 由 WEIGHT_SUM 减去 0.07 得 remaining（与场景3.P2 同源）
REMAINING_SUM=$(awk -v s="$WEIGHT_SUM" 'BEGIN {printf "%.4f", s - 0.07}')
REMAINING_IN_RANGE=$(awk -v r="$REMAINING_SUM" 'BEGIN {
    if (r >= 0.929 && r <= 0.931) print "1"; else print "0"
}')

if [[ "$REMAINING_IN_RANGE" == "1" ]]; then
    echo "  PASS  场景4.P2: 其余 13 维 sum=${REMAINING_SUM} ∈ [0.929, 0.931]"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  场景4.P2: 其余 13 维 sum=${REMAINING_SUM} 越界 [0.929, 0.931]"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# 场景4.P3: 六维各自权重精确（只降不增契约，防 AI 改别维度凑 sum 骗过）
# observe: grep 权重表 6 行各自锚定
#   Dim 1.*0\.12 / Dim 2.*0\.10 / Dim 3.*0\.09 / Dim 4.*0\.09 / Dim 5.*0\.06 / Dim 10.*0\.06
# assert: 六联立各自 matches == 1
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 场景4.P3: 六维各自权重精确（Dim1==0.12/Dim2==0.10/Dim3==0.09/Dim4==0.09/Dim5==0.06/Dim10==0.06）──"

# 六维（编号,期望权重）平行数组（bash 3.2 兼容，不用 declare -A 关联数组）
SIX_DIM_NUMS=(1 2 3 4 5 10)
SIX_DIM_WEIGHTS=("0.12" "0.10" "0.09" "0.09" "0.06" "0.06")

SIX_DIM_PASS=1
SIX_DIM_DETAIL=""
SIX_IDX=0
while [[ "$SIX_IDX" -lt "${#SIX_DIM_NUMS[@]}" ]]; do
    dim_num="${SIX_DIM_NUMS[$SIX_IDX]}"
    expected="${SIX_DIM_WEIGHTS[$SIX_IDX]}"
    # grep 权重表行：`| Dim N: ... | 0.XX |` 上下文锚定
    # 用 Dim N + 0.XX 同行锚定（权重表行格式）
    # 转义 expected 的小数点（bash 参数展开，避免 sed）
    expected_re="${expected//./\\.}"
    DIM_MATCHES=$(grep -cE "^[|][[:space:]]*Dim[[:space:]]+${dim_num}[:：][^|]*[|][[:space:]]*${expected_re}[[:space:]]*[|]" "$SKILL_MD" 2>/dev/null)
    if [[ -z "$DIM_MATCHES" ]]; then DIM_MATCHES=0; fi
    SIX_DIM_DETAIL="${SIX_DIM_DETAIL} Dim${dim_num}=${DIM_MATCHES}(exp ${expected})"
    if [[ "$DIM_MATCHES" -ne 1 ]]; then
        SIX_DIM_PASS=0
    fi
    SIX_IDX=$((SIX_IDX + 1))
done

if [[ "$SIX_DIM_PASS" -eq 1 ]]; then
    echo "  PASS  场景4.P3: 六维各自权重精确匹配（六联立各自 matches==1）"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  场景4.P3: 六维权重联立失败（${SIX_DIM_DETAIL# }）"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# 场景5.P1: lib.sh 不新增 critical_path/readiness_check/vital_path 函数（count == 0）
# 纯 AI 语义约束（对齐 Dim 13 客观 bash 路线区分）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 场景5.P1: lib.sh 无 critical_path/readiness_check/vital_path 函数（count == 0）──"

# bash 函数定义模式：fn() { 或 function fn {
# 注意：只看定义，不看 grep -rn 调用/comment 提及
READINESS_FUNCS=$(grep -cE '^(function[[:space:]]+)?(critical_path|readiness_check|vital_path)[a-z_]*[[:space:]]*\(\)' "$LIB_SH" 2>/dev/null)
if [[ -z "$READINESS_FUNCS" ]]; then READINESS_FUNCS=0; fi

# Mutation-Survival：baseline ==0 → 蓝队违规加 bash 函数 → 实施 >=1 必 FAIL
if [[ "$READINESS_FUNCS" -eq 0 ]]; then
    echo "  PASS  场景5.P1: lib.sh 无 critical_path/readiness/vital_path 函数（count==0，纯 AI 语义）"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  场景5.P1: lib.sh 含 readiness 类 bash 函数 count=${READINESS_FUNCS}（应 == 0，违反纯 AI 语义契约）"
    echo "        matches: $(grep -E '^(function[[:space:]]+)?(critical_path|readiness_check|vital_path)[a-z_]*[[:space:]]*\(\)' "$LIB_SH" 2>/dev/null)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# 场景5.P1.NEGATE: lib.sh 无 detect_critical_path()（matches == 0）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 场景5.P1.NEGATE: lib.sh 无 detect_critical_path()（matches == 0）──"

DETECT_CRITICAL_PATH=$(grep -cE '^(function[[:space:]]+)?detect_critical_path[[:space:]]*\(\)' "$LIB_SH" 2>/dev/null)
if [[ -z "$DETECT_CRITICAL_PATH" ]]; then DETECT_CRITICAL_PATH=0; fi

if [[ "$DETECT_CRITICAL_PATH" -eq 0 ]]; then
    echo "  PASS  场景5.P1.NEGATE: lib.sh 无 detect_critical_path()（matches==0，negate 通过）"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  场景5.P1.NEGATE: lib.sh 含 detect_critical_path() matches=${DETECT_CRITICAL_PATH}（应 == 0）"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# 场景6.P1: 本红队验收测试文件自身存在（自举）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 场景6.P1: critical-path-readiness.acceptance.test.sh 存在（self）──"

# 优先 plugins/autopilot/scripts/ 下（合流后路径），回退当前 staging（开发期）
SELF_PATH=""
SELF_SRC_PATH="${BASH_SOURCE[0]:-}"
if [[ -f "$SELF_TEST" ]]; then
    SELF_PATH="$SELF_TEST"
elif [[ -n "$SELF_SRC_PATH" ]] && [[ -f "$SELF_SRC_PATH" ]]; then
    SELF_PATH="$SELF_SRC_PATH"
fi

if [[ -n "$SELF_PATH" ]] && [[ -f "$SELF_PATH" ]]; then
    echo "  PASS  场景6.P1: 红队测试文件存在（${SELF_PATH}）"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  场景6.P1: 红队测试文件不存在"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# 场景6.P3: 本测试脚本内覆盖 >=3 项不变量断言
# observe: 脚本内 grep 三项断言计数（Dim14存在 / 权重和=1.00 / reference非空）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 场景6.P3: 脚本内覆盖 >=3 项不变量（Dim14存在/权重和=1.00/reference非空）──"

# 检查本脚本是否含三项断言关键词（脚本源 = BASH_SOURCE 或 SELF_PATH）
SELF_SRC=""
if [[ -n "$SELF_PATH" ]] && [[ -f "$SELF_PATH" ]]; then
    SELF_SRC=$(cat "$SELF_PATH" 2>/dev/null)
else
    SELF_SRC=""
fi

INVARIANT_HITS=0
# Dim 14 存在断言（grep Dim 14 标题行）
if echo "$SELF_SRC" | grep -qE 'Dim[[:space:]]+14\b.*标题'; then
    INVARIANT_HITS=$((INVARIANT_HITS + 1))
elif echo "$SELF_SRC" | grep -qE '\^###[[:space:]]\+Dim'; then
    INVARIANT_HITS=$((INVARIANT_HITS + 1))
fi
# 权重和=1.00 断言（sum 或 0.999 或 1.001）
if echo "$SELF_SRC" | grep -qE '0\.999|1\.001|权重.*sum'; then
    INVARIANT_HITS=$((INVARIANT_HITS + 1))
fi
# reference 非空断言（bytes 或 reference 存在）
if echo "$SELF_SRC" | grep -qiE 'reference.*存在|bytes.*[>:=][[:space:]]*1|critical-path-readiness-principles'; then
    INVARIANT_HITS=$((INVARIANT_HITS + 1))
fi

if [[ "$INVARIANT_HITS" -ge 3 ]]; then
    echo "  PASS  场景6.P3: 脚本覆盖 ${INVARIANT_HITS}/3 项不变量（Dim14存在/权重和/reference非空）"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  场景6.P3: 脚本仅覆盖 ${INVARIANT_HITS}/3 项不变量"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# 场景7.P1: SKILL.md Dim 14 章节附近含降级语义（warn/fail/降级）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 场景7.P1: Dim 14 章节附近含降级语义（count >= 1）──"

# 用场景2.P1 提取的 DIM14_SECTION（Dim 14 章节）
# 若段落提取为空，回退全文 grep（dim 14 行号附近，宽松）
DOWNGRADE_COUNT=0
if [[ -n "$DIM14_SECTION" ]]; then
    DOWNGRADE_COUNT=$(printf '%s' "$DIM14_SECTION" | grep -cE '降级|warn|fail' 2>/dev/null)
fi
if [[ -z "$DOWNGRADE_COUNT" ]]; then DOWNGRADE_COUNT=0; fi

if [[ "$DOWNGRADE_COUNT" -ge 1 ]]; then
    echo "  PASS  场景7.P1: Dim 14 章节含降级语义（count=${DOWNGRADE_COUNT}）"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  场景7.P1: Dim 14 章节无降级语义（warn/fail/降级 任一）"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# 场景7.P2: 命脉段含 warn/fail/降级/不评A 任一（matches >= 1）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 场景7.P2: 命脉段含 warn/fail/降级/不评A 任一（matches >= 1）──"

# 「命脉段」= Dim 14 章节 + 报告矩阵 Dim 14 行（宽松提取，防断言过严）
# 用 SKILL.md 全文 grep 命脉 + warn/fail/降级/不评A（同行或邻近）
# 同一行内同时含「命脉」与降级语义词（awk 单遍扫描，避免 grep 管道）
VITAL_DOWNGRADE=$(awk '
    /命脉/ && (/warn/ || /fail/ || /降级/ || /不评A/ || /非A/) { c++ }
    END { print c+0 }
' "$SKILL_MD" 2>/dev/null)
if [[ -z "$VITAL_DOWNGRADE" ]]; then VITAL_DOWNGRADE=0; fi

if [[ "$VITAL_DOWNGRADE" -ge 1 ]]; then
    echo "  PASS  场景7.P2: 命脉 + 降级语义共现（matches=${VITAL_DOWNGRADE}）"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  场景7.P2: 命脉行无 warn/fail/降级/不评A 共现"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# 场景7.P3.NEGATE: 未覆盖附近 pass/na 不共现（co_occurrence == 0）
# 防 AI 把「命脉未覆盖」记为 pass/na 放行（假绿）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 场景7.P3.NEGATE: 未覆盖附近 pass/na 不共现（co_occurrence == 0）──"

# 检查「未覆盖」字面同行是否含 pass/na（放行词）
# awk 单遍：同行同时含「未覆盖」与 pass/na 单词 → 计数
# co_occurrence==0 通过，>=1 FAIL（防假绿放行）
BAD_CO_OCCUR=$(awk '
    /未覆盖/ && (/[[:space:]"(]pass([^a-zA-Z]|$)/ || /[[:space:]"(]na([^a-zA-Z]|$)/) { c++ }
    END { print c+0 }
' "$SKILL_MD" 2>/dev/null)
if [[ -z "$BAD_CO_OCCUR" ]]; then BAD_CO_OCCUR=0; fi

# negate：co_occurrence == 0 才 PASS
if [[ "$BAD_CO_OCCUR" -eq 0 ]]; then
    echo "  PASS  场景7.P3.NEGATE: 未覆盖不与 pass/na 放行共现（co_occurrence==0，negate 通过）"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  场景7.P3.NEGATE: 未覆盖附近出现 pass/na 放行共现 co_occurrence=${BAD_CO_OCCUR}（应 == 0）"
    echo "        matches: $(grep -E '未覆盖' "$SKILL_MD" 2>/dev/null | grep -E '\b(pass|na)\b' 2>/dev/null)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# 场景6.P2 自举保障：本脚本 exit 0 且 stdout 含 "PASS"
#   由末尾 RESULT: PASS 行 + exit 0 保证（任何 FAIL_COUNT > 0 即 exit 1）
#   此处仅注释化说明，不做自身 fork 跑（避免递归/死锁）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 场景6.P2: exit 0 + stdout 含 PASS（由末尾 RESULT 行保证，自举）──"
if [[ "$FAIL_COUNT" -eq 0 ]]; then
    echo "  PASS  场景6.P2: 当前 FAIL_COUNT==0 → 末尾 RESULT: PASS + exit 0（自举断言）"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  场景6.P2: FAIL_COUNT=${FAIL_COUNT} > 0 → 末尾 RESULT: FAIL + exit 1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ── 汇总 ──────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  PASS: $PASS_COUNT    FAIL: $FAIL_COUNT"
echo "══════════════════════════════════════════════════════════════"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo "RESULT: FAIL (Dim 14 契约闭集违反：16 谓词之一未通过)"
    exit 1
fi

echo "RESULT: PASS (Dim 14 契约闭集 16 谓词全通过：维度数/权重Σ/匀权/枚举/reference/纯AI语义/降级语义)"
exit 0
