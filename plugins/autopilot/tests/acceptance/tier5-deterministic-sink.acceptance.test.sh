#!/usr/bin/env bash
# R-T5DS: 验证 autopilot Tier 5 确定性下沉实现（v3.48.0+ 契约）
# 红队测试 — 仅基于设计文档「契约规约」编写（黑盒），不读蓝队 tier5 实现函数体
#
# 设计文档 SSOT：.autopilot/runtime/requirements/20260703-…/state.md
#   ## 契约规约（接口签名 / 状态字段 / 守卫触发 / SSOT / 错误契约）
#
# 覆盖契约点：
#   C1  lib.sh 三函数定义存在（detect_quantitative_tools / tier5_coverage_check / tier5_mutation_check）
#   C2  detect_quantitative_tools 契约：无工具 fixture → JSON 5 个 bool 全 false（含 istanbul=false）
#   C3  detect_quantitative_tools 有工具检测：package.json 含 @stryker + stryker.conf.js → stryker=true
#   C4  tier5_coverage_check 契约：coverage-summary.json + changed_files → line/branch 数字 + file 级过滤
#   C5  tier5_mutation_check 契约：mutation.json killed=60/total=100 → kill_rate=60 passed=true；
#                                 killed=59/total=100 → kill_rate=59 passed=false
#   C6  stop-hook §8.5.3 守卫存在（grep 锚点 "8.5.3" + tier5_status）
#   C7  幂等前置（B1）：守卫含 tier5_status 空判断（不覆盖编排器已设的 pass/fail）
#   C8  路径区分（B2）：tier5 缺失 block 回 qa 补判，非 auto-fix 推进
#   C9  tier5_status 字段在 references/state-file-guide.md
#   C10 SKILL.md Tier 5 锚点 + 减行（锚点指向 quantitative-metrics.md，行数 ≤ 改前 587）
#   C11 SSOT（B3）：doctor SKILL.md 仍含 detect_quantitative_tools 字面（不破 T5c.1）
#   C12 错误契约（solve-don't-punt）：tier5_coverage_check 给不存在文件 → {passed:false} rc=0
#
# 预注册验收场景（P1/P2 det-machine）：
#   P1  无工具 fixture → detect_quantitative_tools 全 false；§8.5.3 → set tier5_status=na + systemMessage 含"测试有效性维度未验证"
#   P2  vitest+coverage fixture → Tier 5 栏合规出现（tier5_status ∈ {na,skipped,pass,fail}，不再沉默缺席）
#
# 测试质量铁律：不允许"宽容跳过"，每个断言失败必须 exit 1
# 注：不用 -e（grep -c 无匹配返回 1 会误触发退出）；断言失败由 _log_fail + 末尾 exit 1 统一兜底
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# REPO_ROOT 稳健探测：从 SCRIPT_DIR 往上找 .claude-plugin/marketplace.json
# （兼容暂存区 .autopilot/runtime/requirements/<slug>/acceptance-staging/ 与
#   合流后 plugins/autopilot/tests/acceptance/ 两种部署位置，治深度差）
_find_repo_root() {
    local d="$SCRIPT_DIR"
    while [[ -n "$d" && "$d" != "/" ]]; do
        if [[ -f "$d/.claude-plugin/marketplace.json" ]]; then
            echo "$d"; return 0
        fi
        d=$(dirname "$d")
    done
    return 1
}
REPO_ROOT="$(_find_repo_root)" || {
    echo "[FAIL] R-T5DS: 无法定位 REPO_ROOT（缺 .claude-plugin/marketplace.json）" >&2
    exit 1
}

# ── 关键路径 ─────────────────────────────────────────────────────────────────
# 注：stop-hook.sh 在 scripts/ 下（非 hooks/，hooks/hooks.json 是匹配规则配置）
LIB_SH="$REPO_ROOT/plugins/autopilot/scripts/lib.sh"
STOP_HOOK="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"
SKILL_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/SKILL.md"
QM_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/quantitative-metrics.md"
STATE_GUIDE="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/state-file-guide.md"
DOCTOR_SKILL="$REPO_ROOT/plugins/autopilot/skills/autopilot-doctor/SKILL.md"
PLUGIN_JSON="$REPO_ROOT/plugins/autopilot/.claude-plugin/plugin.json"

# ── 计数器 ───────────────────────────────────────────────────────────────────
PASSED=0
FAILED=0
FAILURES=()

_log_pass() {
    local id="$1"; shift
    echo "✓ $id $*"
    PASSED=$((PASSED + 1))
}

_log_fail() {
    local id="$1"; shift
    echo "✗ $id $*" >&2
    FAILED=$((FAILED + 1))
    FAILURES+=("$id $*")
}

assert_file_exists() {
    local id="$1"; local f="$2"
    if [[ -f "$f" ]]; then _log_pass "$id" "file exists: $f"
    else _log_fail "$id" "file MISSING: $f"; fi
}

# grep -c 命中 >= 阈值
assert_grep_ge() {
    local id="$1" pattern="$2" file="$3" min="$4"; shift 4
    local desc="$*"
    [[ ! -f "$file" ]] && { _log_fail "$id" "$desc — 文件不存在: $file"; return; }
    local count
    count=$(grep -c -- "$pattern" "$file" 2>/dev/null) || count=0
    count=$(echo "$count" | head -1 | tr -d ' ')
    [[ -z "$count" ]] && count=0
    if [[ "$count" -ge "$min" ]]; then
        _log_pass "$id" "$desc (grep -c '$pattern' = $count >= $min)"
    else
        _log_fail "$id" "$desc (grep -c '$pattern' = $count < $min, file=$file)"
    fi
}

# grep -cE 命中 >= 阈值
assert_grepE_ge() {
    local id="$1" pattern="$2" file="$3" min="$4"; shift 4
    local desc="$*"
    [[ ! -f "$file" ]] && { _log_fail "$id" "$desc — 文件不存在: $file"; return; }
    local count
    count=$(grep -cE -- "$pattern" "$file" 2>/dev/null) || count=0
    count=$(echo "$count" | head -1 | tr -d ' ')
    [[ -z "$count" ]] && count=0
    if [[ "$count" -ge "$min" ]]; then
        _log_pass "$id" "$desc (grep -cE '$pattern' = $count >= $min)"
    else
        _log_fail "$id" "$desc (grep -cE '$pattern' = $count < $min, file=$file)"
    fi
}

# wc -l 行数 <= 阈值
assert_wc_le() {
    local id="$1" file="$2" max="$3"; shift 3
    local desc="$*"
    [[ ! -f "$file" ]] && { _log_fail "$id" "$desc — 文件不存在: $file"; return; }
    local lines
    lines=$(wc -l < "$file" | tr -d ' ')
    if [[ "$lines" -le "$max" ]]; then
        _log_pass "$id" "$desc (wc -l = $lines <= $max)"
    else
        _log_fail "$id" "$desc (wc -l = $lines > $max, file=$file)"
    fi
}

# 在子 shell 中 source lib.sh，仅定义函数不触发主流程（lib.sh 无 main guard，
# 函数体只在被调用时执行；stop-hook.sh 有 BASH_SOURCE guard 防 sourced 时跑主流程）
invoke_lib() {
    # 用法：invoke_lib <func> <args...>
    # 返回：函数 stdout 通过 echo，rc 通过 $?
    bash -c "
        set -uo pipefail
        source '${LIB_SH}' 2>/dev/null
        \"\$@\"
    " _ "$@"
}

echo "=========================================="
echo " R-T5DS Tier 5 确定性下沉验收（契约黑盒）"
echo "=========================================="

# ─────────────────────────────────────────────────────────────────────────────
# 前置：关键文件存在
# ─────────────────────────────────────────────────────────────────────────────
assert_file_exists "T5pre.1" "$LIB_SH"
assert_file_exists "T5pre.2" "$STOP_HOOK"
assert_file_exists "T5pre.3" "$SKILL_FILE"
assert_file_exists "T5pre.4" "$QM_FILE"
assert_file_exists "T5pre.5" "$STATE_GUIDE"
assert_file_exists "T5pre.6" "$DOCTOR_SKILL"
assert_file_exists "T5pre.7" "$PLUGIN_JSON"

# ─────────────────────────────────────────────────────────────────────────────
# C1：lib.sh 三函数定义存在（黑盒：grep 函数签名，不读 body）
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- C1: lib.sh 三函数定义存在 ---"

assert_grepE_ge "T5ds.C1a" '^(detect_quantitative_tools|function detect_quantitative_tools)\s*\(\)' "$LIB_SH" 1 \
    "C1: detect_quantitative_tools() 函数定义在 lib.sh"

assert_grepE_ge "T5ds.C1b" '^(tier5_coverage_check|function tier5_coverage_check)\s*\(\)' "$LIB_SH" 1 \
    "C1: tier5_coverage_check() 函数定义在 lib.sh"

assert_grepE_ge "T5ds.C1c" '^(tier5_mutation_check|function tier5_mutation_check)\s*\(\)' "$LIB_SH" 1 \
    "C1: tier5_mutation_check() 函数定义在 lib.sh"

# ─────────────────────────────────────────────────────────────────────────────
# C2：detect_quantitative_tools 契约 — 无工具 fixture → 5 个 bool 全 false（含 istanbul=false）
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- C2: detect_quantitative_tools 无工具 fixture 全 false（含 istanbul=false） ---"

# 准备无工具 fixture 目录：package.json 无 stryker/c8/nyc/istanbul/jest coverage；无 stryker.conf/.c8rc/.nycrc
TMP_C2="$(mktemp -d)"
TMP_C3=""; TMP_C4=""; TMP_C5=""; TMP_C12=""
trap 'rm -rf "$TMP_C2" "$TMP_C3" "$TMP_C4" "$TMP_C5" "$TMP_C12" 2>/dev/null' EXIT

# 无工具 package.json（无 stryker/c8/nyc/istanbul deps，无 collectCoverage 字段）
cat > "$TMP_C2/package.json" <<'EOF'
{
  "name": "no-quant-tools-fixture",
  "version": "1.0.0",
  "devDependencies": {
    "lodash": "^4.17.21"
  }
}
EOF

# detect_quantitative_tools 必须能基于 cwd 探测，故 cd 到 fixture 目录调用
out_c2=$(cd "$TMP_C2" && invoke_lib detect_quantitative_tools); rc_c2=$?

# 断言：rc=0（错误契约：无 package.json 也不抛错，全 false rc=0）
if [[ $rc_c2 -ne 0 ]]; then
    _log_fail "T5ds.C2.0" "C2: detect_quantitative_tools rc 应=0（无工具全 false），实际 rc=$rc_c2"
else
    _log_pass "T5ds.C2.0" "C2: detect_quantitative_tools rc=0（无工具全 false）"
fi

# 断言：JSON 含 5 个 bool 字段全 false
# 用 jq 解析（设计契约输出 JSON {stryker,c8,nyc,istanbul,jest_coverage}）
for field in stryker c8 nyc istanbul jest_coverage; do
    val=$(echo "$out_c2" | jq -r --arg f "$field" '.[$f]' 2>/dev/null)
    if [[ "$val" == "false" ]]; then
        _log_pass "T5ds.C2.${field}" "C2: detect_quantitative_tools 输出 .$field = false（无工具）"
    else
        _log_fail "T5ds.C2.${field}" "C2: detect_quantitative_tools 输出 .$field 应=false，实际='$val'（stdout='$out_c2'）"
    fi
done

# 额外断言：5 个字段必须都存在（JSON schema 闭合，防蓝队漏 istanbul）
fields_present=$(echo "$out_c2" | jq -r 'keys | length' 2>/dev/null)
if [[ "$fields_present" -ge 5 ]]; then
    _log_pass "T5ds.C2.keys" "C2: JSON 字段数 >= 5（防漏 istanbul 欠拟合，治 I4）"
else
    _log_fail "T5ds.C2.keys" "C2: JSON 字段数应 >= 5，实际=${fields_present}（stdout='$out_c2'）"
fi

# ─────────────────────────────────────────────────────────────────────────────
# C3：detect_quantitative_tools 有工具检测 — stryker fixture → stryker=true
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- C3: detect_quantitative_tools stryker fixture → stryker=true ---"

TMP_C3="$(mktemp -d)"

# package.json 含 @stryker-mutator/core 依赖
cat > "$TMP_C3/package.json" <<'EOF'
{
  "name": "stryker-fixture",
  "version": "1.0.0",
  "devDependencies": {
    "@stryker-mutator/core": "^8.0.0",
    "@stryker-mutator/jest-runner": "^8.0.0"
  }
}
EOF

# stryker.conf.js 存在（检测路径锚点）
cat > "$TMP_C3/stryker.conf.js" <<'EOF'
module.exports = { config: { testRunner: 'jest' } };
EOF

out_c3=$(cd "$TMP_C3" && invoke_lib detect_quantitative_tools); rc_c3=$?

if [[ $rc_c3 -ne 0 ]]; then
    _log_fail "T5ds.C3.0" "C3: detect_quantitative_tools rc 应=0，实际 rc=$rc_c3"
else
    _log_pass "T5ds.C3.0" "C3: detect_quantitative_tools rc=0（stryker fixture）"
fi

stryker_val=$(echo "$out_c3" | jq -r '.stryker' 2>/dev/null)
if [[ "$stryker_val" == "true" ]]; then
    _log_pass "T5ds.C3.stryker" "C3: stryker=true（@stryker-mutator/core + stryker.conf.js）"
else
    _log_fail "T5ds.C3.stryker" "C3: stryker 应=true，实际='$stryker_val'（stdout='$out_c3'）"
fi

# ─────────────────────────────────────────────────────────────────────────────
# C4：tier5_coverage_check 契约 — coverage-summary.json + changed_files → line/branch 数字 + file 级过滤
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- C4: tier5_coverage_check 契约（line=85 branch=60 + file 级过滤） ---"

TMP_C4="$(mktemp -d)"

# 标准 istanbul/c8/vitest coverage-summary.json fixture
# total line=85/branch=60；src/a.js 全覆盖；src/b.js 有未覆盖行
cat > "$TMP_C4/coverage-summary.json" <<'EOF'
{
  "total": {
    "lines": { "total": 100, "covered": 85, "pct": 85 },
    "branches": { "total": 50, "covered": 30, "pct": 60 },
    "functions": { "total": 20, "covered": 18, "pct": 90 },
    "statements": { "total": 100, "covered": 85, "pct": 85 }
  },
  "/abs/src/a.js": {
    "lines": { "total": 50, "covered": 50, "pct": 100 },
    "branches": { "total": 25, "covered": 25, "pct": 100 }
  },
  "/abs/src/b.js": {
    "lines": { "total": 50, "covered": 35, "pct": 70 },
    "branches": { "total": 25, "covered": 5, "pct": 20 }
  }
}
EOF

# changed_files 列表：只含 src/b.js（I1 治：file 级过滤，非全量）
cat > "$TMP_C4/changed_files.txt" <<'EOF'
src/b.js
EOF

# tier5_coverage_check <coverage_summary.json> <changed_files_list>
out_c4=$(invoke_lib tier5_coverage_check "$TMP_C4/coverage-summary.json" "$TMP_C4/changed_files.txt"); rc_c4=$?

if [[ $rc_c4 -ne 0 ]]; then
    _log_fail "T5ds.C4.0" "C4: tier5_coverage_check rc 应=0，实际 rc=$rc_c4"
else
    _log_pass "T5ds.C4.0" "C4: tier5_coverage_check rc=0"
fi

# 断言 line=85（契约接口签名 line:int，取 total 数字，不取 pct 阈值判定）
line_val=$(echo "$out_c4" | jq -r '.line // .line_pct // empty' 2>/dev/null)
if [[ "$line_val" == "85" ]]; then
    _log_pass "T5ds.C4.line" "C4: 输出 .line = 85（total line pct）"
else
    _log_fail "T5ds.C4.line" "C4: 输出 .line 应=85，实际='$line_val'（stdout='$out_c4'）"
fi

# 断言 branch=60
branch_val=$(echo "$out_c4" | jq -r '.branch // .branch_pct // empty' 2>/dev/null)
if [[ "$branch_val" == "60" ]]; then
    _log_pass "T5ds.C4.branch" "C4: 输出 .branch = 60（total branch pct）"
else
    _log_fail "T5ds.C4.branch" "C4: 输出 .branch 应=60，实际='$branch_val'（stdout='$out_c4'）"
fi

# 断言 uncovered_critical 是 changed_files 的子集（file 级过滤）
# 契约：uncovered_critical = changed_files 的未覆盖行（非全量，治 I1）
# 此 fixture changed_files=[src/b.js]，b.js 有未覆盖 → uncovered_critical 应含 b.js 条目，不含 a.js
uc_count=$(echo "$out_c4" | jq -r '.uncovered_critical | length' 2>/dev/null)
if [[ "$uc_count" -gt 0 ]]; then
    # 校验所有条目 file 都在 changed_files 中（子集约束）
    uc_files=$(echo "$out_c4" | jq -r '.uncovered_critical[].file' 2>/dev/null | sort -u)
    has_outsider=0
    for f in $uc_files; do
        if ! grep -qx "$f" "$TMP_C4/changed_files.txt" 2>/dev/null; then
            # 容忍 basename 形式（fixture 用 src/b.js，coverage key 用 /abs/src/b.js）
            base=$(basename "$f")
            if ! grep -qx ".*$base" "$TMP_C4/changed_files.txt" 2>/dev/null; then
                has_outsider=1
                _log_fail "T5ds.C4.filter" "C4: uncovered_critical 含 changed_files 之外文件: ${f}（file 级过滤失效）"
            fi
        fi
    done
    [[ $has_outsider -eq 0 ]] && _log_pass "T5ds.C4.filter" "C4: uncovered_critical 是 changed_files 子集（file 级过滤生效，治 I1）"
else
    # b.js 有未覆盖行（pct=70），若 uc_count=0 说明 file 级过滤未生效或未输出
    _log_fail "T5ds.C4.filter" "C4: uncovered_critical 应含 b.js 未覆盖条目（b.js line pct=70），实际 length=${uc_count}（stdout='$out_c4'）"
fi

# ─────────────────────────────────────────────────────────────────────────────
# C5：tier5_mutation_check 契约 — killed=60/total=100 → kill_rate=60 passed=true；
#                         killed=59/total=100 → kill_rate=59 passed=false
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- C5: tier5_mutation_check 契约（阈值 60） ---"

TMP_C5="$(mktemp -d)"

# Case 1: killed=60/totalValid=100 → kill_rate=60, passed=true
cat > "$TMP_C5/mutation_pass.json" <<'EOF'
{
  "files": [],
  "mutants": [],
  "schemaVersion": "1.0",
  "thresholds": { "high": 80, "low": 60, "break": 60 },
  "testRunner": "jest",
  "framework": {
    "name": "Stryker",
    "version": "8.0.0"
  },
  "metrics": {
    "killed": 60,
    "timeout": 0,
    "survived": 40,
    "noCoverage": 0,
    "runtimeErrors": 0,
    "compileErrors": 0,
    "totalDetected": 60,
    "totalUndetected": 40,
    "totalCovered": 100,
    "totalValid": 100,
    "totalInvalid": 0,
    "mutationScore": 60,
    "mutationScoreBasedOnCoveredCode": 60
  }
}
EOF

out_c5p=$(invoke_lib tier5_mutation_check "$TMP_C5/mutation_pass.json")
kr_p=$(echo "$out_c5p" | jq -r '.kill_rate // empty' 2>/dev/null)
# 注：bool 字段不能用 `// empty`（jq 把 false 视为 null-ish 会吞掉），用 tostring
ps_p=$(echo "$out_c5p" | jq -r '.passed | tostring' 2>/dev/null)

if [[ "$kr_p" == "60" ]]; then
    _log_pass "T5ds.C5.1a" "C5: kill_rate=60（killed=60/totalValid=100）"
else
    _log_fail "T5ds.C5.1a" "C5: kill_rate 应=60，实际='$kr_p'（stdout='$out_c5p'）"
fi
if [[ "$ps_p" == "true" ]]; then
    _log_pass "T5ds.C5.1b" "C5: passed=true（kill_rate=60 >= 阈值 60）"
else
    _log_fail "T5ds.C5.1b" "C5: passed 应=true（边界 60 >= 60），实际='$ps_p'（stdout='$out_c5p'）"
fi

# Case 2: killed=59/totalValid=100 → kill_rate=59, passed=false
cat > "$TMP_C5/mutation_fail.json" <<'EOF'
{
  "files": [],
  "mutants": [],
  "schemaVersion": "1.0",
  "thresholds": { "high": 80, "low": 60, "break": 60 },
  "metrics": {
    "killed": 59,
    "timeout": 0,
    "survived": 41,
    "noCoverage": 0,
    "runtimeErrors": 0,
    "compileErrors": 0,
    "totalDetected": 59,
    "totalUndetected": 41,
    "totalCovered": 100,
    "totalValid": 100,
    "totalInvalid": 0,
    "mutationScore": 59,
    "mutationScoreBasedOnCoveredCode": 59
  }
}
EOF

out_c5f=$(invoke_lib tier5_mutation_check "$TMP_C5/mutation_fail.json")
kr_f=$(echo "$out_c5f" | jq -r '.kill_rate // empty' 2>/dev/null)
ps_f=$(echo "$out_c5f" | jq -r '.passed | tostring' 2>/dev/null)

if [[ "$kr_f" == "59" ]]; then
    _log_pass "T5ds.C5.2a" "C5: kill_rate=59（killed=59/totalValid=100）"
else
    _log_fail "T5ds.C5.2a" "C5: kill_rate 应=59，实际='$kr_f'（stdout='$out_c5f'）"
fi
if [[ "$ps_f" == "false" ]]; then
    _log_pass "T5ds.C5.2b" "C5: passed=false（kill_rate=59 < 阈值 60）"
else
    _log_fail "T5ds.C5.2b" "C5: passed 应=false（59 < 60），实际='$ps_f'（stdout='$out_c5f'）"
fi

# ─────────────────────────────────────────────────────────────────────────────
# C6：stop-hook §8.5.3 守卫存在（grep 锚点 "8.5.3" + tier5_status）
# 注：黑盒静态契约断言——sourced 时 stop-hook.sh:334 有 BASH_SOURCE guard return 0，
# §8.5.3 主流程不执行，故只能 grep 锚点（不能端到端触发）
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- C6: stop-hook §8.5.3 守卫存在（grep 锚点） ---"

assert_grep_ge "T5ds.C6.1" "8.5.3" "$STOP_HOOK" 1 \
    "C6: stop-hook.sh 含 §8.5.3 锚点字符串"

assert_grep_ge "T5ds.C6.2" "tier5_status" "$STOP_HOOK" 1 \
    "C6: stop-hook.sh 含 tier5_status 字段操作（守卫/校验）"

# ─────────────────────────────────────────────────────────────────────────────
# C7：幂等前置（B1）— 守卫含 tier5_status 空判断（不覆盖编排器已设的 pass/fail）
# 设计文档契约：「tier5_status 非空时守卫跳过自动 set」
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- C7: 幂等前置（B1）— tier5_status 空判断模式 ---"

# 幂等前置：守卫 block 含 get_enum_field/get_field tier5_status + 空判断（-z / == "" / is null）
# grep 锚点：tier5_status 附近有空判断模式（-z / 空 / null）
if grep -qE '(get_enum_field|get_field).*tier5_status' "$STOP_HOOK" 2>/dev/null \
   && grep -qE '\-z.*tier5_status|tier5_status.*==.*("")|\|.*\|.*tier5_status|tier5_status.*null' "$STOP_HOOK" 2>/dev/null; then
    _log_pass "T5ds.C7.1" "C7: 守卫含 tier5_status 空判断（幂等前置，治 B1）"
else
    _log_fail "T5ds.C7.1" "C7: 守卫未检测到 tier5_status 空判断模式（幂等前置缺失，治 B1）"
fi

# ─────────────────────────────────────────────────────────────────────────────
# C8：路径区分（B2）— tier5 缺失 block 回 qa 补判，非 auto-fix 推进
# 设计文档契约：「tier5_status 缺失 block = 回 qa 补判定，不走 auto-fix，不耗 retry_count」
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- C8: 路径区分（B2）— block 回 qa 非 auto-fix ---"

# 断言：stop-hook.sh 提到 tier5 与 review-accept gate 的关联（block/补判/reason）
# 锚点：tier5 + block + review-accept 附近，或"只补 Tier 5" prompt 注入
if grep -qE 'review-accept.*tier5|tier5.*review-accept|tier5.*block|block.*tier5|补.*Tier 5|Tier 5.*补|补判' "$STOP_HOOK" 2>/dev/null; then
    _log_pass "T5ds.C8.1" "C8: stop-hook 含 tier5 block 回 qa 补判逻辑（路径区分，治 B2）"
else
    _log_fail "T5ds.C8.1" "C8: stop-hook 未检测到 tier5 block 路径区分（治 B2 缺失）"
fi

# ─────────────────────────────────────────────────────────────────────────────
# C9：tier5_status 字段在 references/state-file-guide.md
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- C9: tier5_status 字段在 state-file-guide.md ---"

assert_grep_ge "T5ds.C9.1" "tier5_status" "$STATE_GUIDE" 1 \
    "C9: state-file-guide.md 含 tier5_status 字段（任务 4 文档同步）"

# ─────────────────────────────────────────────────────────────────────────────
# C10：SKILL.md Tier 5 锚点 + 减行（净减，≤ 改前 587）
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- C10: SKILL.md Tier 5 锚点 + 减行 ---"

assert_grep_ge "T5ds.C10.1" "Tier 5: 量化指标门禁" "$SKILL_FILE" 1 \
    "C10: SKILL.md 含 'Tier 5: 量化指标门禁' 入口锚点（保留）"

assert_grep_ge "T5ds.C10.2" "quantitative-metrics.md" "$SKILL_FILE" 1 \
    "C10: SKILL.md Tier 5 锚点指向 references/quantitative-metrics.md（删段留锚点）"

# 净减行：SKILL.md 当前 587 行，设计文档要求「净减 ~6-8 行」，断言 ≤ 587
# （307-314 重复段 8 行删 → 替换 1 行锚点 = 净减 7 行；断言 ≤ 587 给蓝队留容差但禁止增）
assert_wc_le "T5ds.C10.3" "$SKILL_FILE" 587 \
    "C10: SKILL.md 总行数 ≤ 587（设计文档要求净减，治 skill 脆弱性）"

# 307-314 重复段已删：旧阈值 60/80/70 + na 文案段不应在 SKILL.md 大段重复出现
# 锚点：SKILL.md 不应再含「两子项均无工具」大段 na 文案细节（已收敛 qm.md）
# 用宽松断言：SKILL.md 不应同时含 Stryker + Istanbul + c8 三者 + 阈值数字（旧重复段特征）
if grep -cE 'Stryker.*mutation.*60|mutation score.*60|line.*80.*branch.*70' "$SKILL_FILE" 2>/dev/null | grep -qE '^[0-9]+$'; then
    skill_t5_detail_count=$(grep -cE 'Stryker.*mutation.*60|mutation score.*60|line.*80.*branch.*70' "$SKILL_FILE" 2>/dev/null)
    if [[ "$skill_t5_detail_count" -eq 0 ]]; then
        _log_pass "T5ds.C10.4" "C10: SKILL.md 不含阈值 60/80/70 重复细节段（已收敛 qm.md）"
    else
        _log_fail "T5ds.C10.4" "C10: SKILL.md 仍含阈值重复细节段 $skill_t5_detail_count 处（307-314 未删干净）"
    fi
else
    _log_pass "T5ds.C10.4" "C10: SKILL.md 不含阈值 60/80/70 重复细节段（已收敛 qm.md）"
fi

# ─────────────────────────────────────────────────────────────────────────────
# C11：SSOT（B3）— doctor SKILL.md 仍含 detect_quantitative_tools 字面（不破 T5c.1）
# 设计文档 SSOT 归属：detect_quantitative_tools 唯一实现 = lib.sh；
# doctor SKILL.md 改引用 lib.sh，但保留函数名字面满足红队 T5c.1
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- C11: SSOT（B3）— doctor SKILL.md 含 detect_quantitative_tools 字面 ---"

assert_grep_ge "T5ds.C11.1" "detect_quantitative_tools" "$DOCTOR_SKILL" 1 \
    "C11: doctor SKILL.md 保留 detect_quantitative_tools 函数名字面（SSOT 引用，不破 T5c.1，治 B3）"

# ─────────────────────────────────────────────────────────────────────────────
# C12：错误契约（solve-don't-punt）— tier5_coverage_check 给不存在文件 → {passed:false} rc=0
# 设计文档错误契约：「tier5_coverage_check 文件缺失/格式错 → {passed:false,...} rc=0（不抛错给编排器）」
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- C12: 错误契约 — 不存在文件 → passed=false rc=0（不抛错） ---"

TMP_C12="$(mktemp -d)"

out_c12=$(invoke_lib tier5_coverage_check "$TMP_C12/nonexistent-coverage.json" "$TMP_C12/changed.txt"); rc_c12=$?

if [[ $rc_c12 -eq 0 ]]; then
    _log_pass "T5ds.C12.1" "C12: tier5_coverage_check 不存在文件 rc=0（不抛错给编排器）"
else
    _log_fail "T5ds.C12.1" "C12: tier5_coverage_check 不存在文件 rc 应=0，实际 rc=${rc_c12}（违反 solve-don't-punt）"
fi

# passed 必须是 false（不是抛错、不是空）。注：bool 用 tostring 防 jq // empty 吞 false
passed_c12=$(echo "$out_c12" | jq -r '.passed | tostring' 2>/dev/null)
if [[ "$passed_c12" == "false" ]]; then
    _log_pass "T5ds.C12.2" "C12: 不存在文件 → .passed=false（错误契约）"
else
    _log_fail "T5ds.C12.2" "C12: 不存在文件 → .passed 应=false，实际='$passed_c12'（stdout='$out_c12'）"
fi

# uncovered_critical 应为空数组（错误时降级为空，不产伪数据）
uc_c12=$(echo "$out_c12" | jq -r '.uncovered_critical | length' 2>/dev/null)
if [[ "$uc_c12" == "0" ]]; then
    _log_pass "T5ds.C12.3" "C12: 不存在文件 → uncovered_critical=[]（降级空数组）"
else
    _log_fail "T5ds.C12.3" "C12: 不存在文件 → uncovered_critical 应=[]，实际 length=${uc_c12}（stdout='$out_c12'）"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 汇总
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo " R-T5DS 汇总: PASSED=$PASSED  FAILED=$FAILED"
echo "=========================================="

if [[ $FAILED -gt 0 ]]; then
    echo ""
    echo "失败明细："
    for f in "${FAILURES[@]}"; do
        echo "   - $f"
    done
    echo ""
    echo "FAIL"
    exit 1
fi

echo "PASS"
exit 0
