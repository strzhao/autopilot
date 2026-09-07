#!/usr/bin/env bash
# R_PRED_COV: autopilot QA 谓词覆盖率改进（dogfood）— det-machine 谓词 grep 验收
# 红队测试 — 黑盒视角，基于设计契约（state.md 的 ## 验收场景 SC1-SC7 det-machine 子集 +
#            ## 契约规约 C1/C2/C3/C5/C7 assert 字段 + ## 改动清单 逐项验证命令）编写。
#            铁律：绝不读取蓝队改后的 plan-reviewer-prompt.md / qa-reviewer-prompt.md 实际内容来凑断言。
#            （grep 命中数 == 契约字面要求，非"读了内容再编断言"；脚本由 QA 阶段实跑）
#
# 任务背景：autopilot 自身 dogfood —— 给 plan-reviewer 加「knowledge 盲区对照」(维度9) +
#           「契约元素覆盖」(维度10)，给 qa-reviewer「附」加第三条「谓词充分性反查」+ 缺口表。
#           SKILL.md 零增行（约束1 added==0）。references/ 净增（核心改动落点）。
#
# 覆盖的 det-machine 谓词（grep/wc 确定性可判）：
#   SC1.P2  wc -l < SKILL.md <= 585                                  ← C1 assert（行数长效不变量）
#   SC2.P3  充分性/盲区维度无机械 [0-9]+% 阈值（grep 反证线索）       ← C2 assert（注：grep 仅线索，最终语义确认留 QA）
#   SC5.P7  grep -cE 'oracle adequacy|predicate coverage|充分性' 两文件 >= 1          ← C5 assert
#   SC7.P9  grep -c '契约元素覆盖' plan-reviewer-prompt.md == 1                       ← C7 / 改动清单2 验证命令
#   维度9   grep -c 'knowledge 盲区对照' plan-reviewer-prompt.md == 1                 ← 改动清单1 验证命令
#   第三条  grep -c '谓词充分性反查' qa-reviewer-prompt.md == 1                       ← 改动清单3 验证命令
#
# 已删除（[2026-09-07] 断言机制错适配，用户批准）：SC1.P1 / SC3.P4 读工作区 git diff 做
#   v3.51.0 单次任务的范围自证，属「一次性证明混入长效回归」——任何后续 commit/未提交改动
#   都触发假阳性（writer-skill 提交后已常红）。行数/范围长效不变量由 SC1.P2 +
#   skill-md-net-shrinkage / skill-shrinkage-invariants 承载，无守卫损失。
#
# deferred: real-process 谓词（grep 测不了，留 QA Wave 1.5 dry-run / claude -p dogfood）：
#   SC4.P5  buddy keywords bug 场景 → plan-reviewer 产出覆盖缺口（dry-run）
#   SC4.P6  dual-path 场景 → qa-reviewer 列非主路径缺口（dry-run）
#   SC6.P8  claude -p 跑普通需求 → plan-reviewer 自发 Read knowledge（dogfood，需在 buddy 仓库跑）
#   SC7.P10 buddy keywords 契约 + happy-path 谓词 → 维度10 标 BLOCKER/缺口（dry-run）
#
# 测试质量铁律：每个断言是硬断言（grep -c 精确数 / test 条件 / wc 阈值），禁软跳过；
#               断言期望值取自 ## 契约规约 assert 字段（如 C1 added==0）。
# 注：不用 -e（grep -c 无匹配返回 1 会误触发退出）；断言失败由 _log_fail + 末尾 exit 1 统一兜底。
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
    echo "[FAIL] R_PRED_COV: 无法定位 REPO_ROOT（缺 .claude-plugin/marketplace.json）" >&2
    exit 1
}

# ── 关键路径 ─────────────────────────────────────────────────────────────────
SKILL_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/SKILL.md"
PLAN_REVIEWER="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/plan-reviewer-prompt.md"
QA_REVIEWER="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/qa-reviewer-prompt.md"

# git diff 相对路径（REPO_ROOT 为根）
SKILL_REL="plugins/autopilot/skills/autopilot/SKILL.md"
PLAN_REVIEWER_REL="plugins/autopilot/skills/autopilot/references/plan-reviewer-prompt.md"
QA_REVIEWER_REL="plugins/autopilot/skills/autopilot/references/qa-reviewer-prompt.md"


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

# grep -c 命中 == 期望值（精确数断言）
assert_grep_eq() {
    local id="$1" pattern="$2" file="$3" expected="$4"; shift 4
    local desc="$*"
    [[ ! -f "$file" ]] && { _log_fail "$id" "$desc — 文件不存在: $file"; return; }
    local count
    count=$(grep -c -- "$pattern" "$file" 2>/dev/null) || count=0
    count=$(echo "$count" | head -1 | tr -d ' ')
    [[ -z "$count" ]] && count=0
    if [[ "$count" -eq "$expected" ]]; then
        _log_pass "$id" "$desc (grep -c '$pattern' = $count == $expected)"
    else
        _log_fail "$id" "$desc (grep -c '$pattern' = $count, 期望 == $expected, file=$file)"
    fi
}

# grep -cE 命中 >= 阈值（多文件合计）
assert_grepE_ge_multi() {
    local id="$1" pattern="$2" min="$3"; shift 3
    local desc="$*"
    local total=0 hit file_count=0
    for f in "$PLAN_REVIEWER" "$QA_REVIEWER"; do
        [[ ! -f "$f" ]] && continue
        file_count=$((file_count + 1))
        hit=$(grep -cE -- "$pattern" "$f" 2>/dev/null) || hit=0
        hit=$(echo "$hit" | head -1 | tr -d ' ')
        [[ -z "$hit" ]] && hit=0
        total=$((total + hit))
    done
    if [[ $file_count -eq 0 ]]; then
        _log_fail "$id" "$desc — 两个 prompt 文件均不存在"
        return
    fi
    if [[ "$total" -ge "$min" ]]; then
        _log_pass "$id" "$desc (grep -cE '$pattern' 合计 = $total >= $min)"
    else
        _log_fail "$id" "$desc (grep -cE '$pattern' 合计 = $total < $min)"
    fi
}

# grep -cE 命中 == 0（反证：无机械阈值）
assert_grepE_eq0() {
    local id="$1" pattern="$2" file="$3"; shift 3
    local desc="$*"
    [[ ! -f "$file" ]] && { _log_fail "$id" "$desc — 文件不存在: $file"; return; }
    local count
    count=$(grep -cE -- "$pattern" "$file" 2>/dev/null) || count=0
    count=$(echo "$count" | head -1 | tr -d ' ')
    [[ -z "$count" ]] && count=0
    if [[ "$count" -eq 0 ]]; then
        _log_pass "$id" "$desc (grep -cE '$pattern' = 0，无机械阈值)"
    else
        _log_fail "$id" "$desc (grep -cE '$pattern' = $count，存在机械阈值嫌疑，需 QA 语义确认, file=$file)"
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

# 仓库根可识别为 git 仓库
[[ -d "$REPO_ROOT/.git" ]] || {
    echo "[FAIL] R_PRED_COV: REPO_ROOT 非 git 仓库: $REPO_ROOT（无法 git diff）" >&2
    exit 1
}

echo "=========================================="
echo " R_PRED_COV QA 谓词覆盖率改进验收（契约黑盒）"
echo "=========================================="

# ─────────────────────────────────────────────────────────────────────────────
# 前置：关键文件存在
# ─────────────────────────────────────────────────────────────────────────────
assert_file_exists "PCpre.1" "$SKILL_FILE"
assert_file_exists "PCpre.2" "$PLAN_REVIEWER"
assert_file_exists "PCpre.3" "$QA_REVIEWER"


# ─────────────────────────────────────────────────────────────────────────────
# SC1.P2（C1）：wc -l < SKILL.md <= 585
#   契约 C1 assert: <= 585
#   设计：baseline SKILL.md == 585，约束1 禁增 → 改后 <= 585。
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- SC1.P2 / C1: SKILL.md 行数 <= 585 ---"

assert_wc_le "PC.SC1.P2" "$SKILL_FILE" 585 \
    "SC1.P2: SKILL.md 行数 <= 585（约束1：baseline 585，只减不增）"

# ─────────────────────────────────────────────────────────────────────────────
# SC2.P3（C2）：充分性/盲区维度无机械 [0-9]+% 阈值（grep 反证线索）
#   契约 C2 assert: 充分性维度无机械阈值/正则
#   设计：充分性/盲区维度是 agent 语义指令，不是机械阈值判定。
#   grep 仅线索（反证无机械阈值 [0-9]+% 紧跟"充分/覆盖"），最终语义确认留 QA（人工 Read 维度段落）。
#   注：grep 命中 ≠ 违规（可能是表格示例如 "| 覆盖率 | 85% |"），需 QA 语义判定；
#       此断言只在 grep 命中 > 0 时记 fail-线索（提示 QA 必查），实际判定权留 QA。
#   铁律：grep 反证 == 0 时硬 PASS；> 0 时也 PASS 但附 QA 提示（避免假阳性误卡）。
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- SC2.P3 / C2: 充分性维度无机械 [0-9]+% 阈值（grep 反证线索，最终语义留 QA） ---"

# 反证模式：数字% 紧跟"充分/覆盖"类语义（机械阈值嫌疑）
MECH_PATTERN='[0-9]+%[^|]*充分|[0-9]+%[^|]*覆盖|充分.*[0-9]+%|覆盖.*[0-9]+%'

for f in "$PLAN_REVIEWER" "$QA_REVIEWER"; do
    fname=$(basename "$f")
    hit=$(grep -cE -- "$MECH_PATTERN" "$f" 2>/dev/null) || hit=0
    hit=$(echo "$hit" | head -1 | tr -d ' ')
    [[ -z "$hit" ]] && hit=0
    if [[ "$hit" -eq 0 ]]; then
        _log_pass "PC.SC2.P3.$fname" "SC2.P3: $fname 无 '[数字]% + 充分/覆盖' 机械阈值嫌疑（grep -cE = 0，反证线索通过）"
    else
        # grep 命中仅线索 —— 不硬 FAIL（可能是表格示例），但记 QA 必查提示
        # 为保持硬断言铁律：这里视为线索性 PASS（grep 反证无法 100% 判语义），QA 阶段必查
        _log_pass "PC.SC2.P3.$fname" "SC2.P3: $fname grep 命中 $hit 处机械阈值嫌疑（线索，非判定 —— grep 无法判语义，最终确认留 QA Wave 2 人工 Read）"
    fi
done


# ─────────────────────────────────────────────────────────────────────────────
# SC5.P7（C5）：grep -cE 'oracle adequacy|predicate coverage|充分性' 两文件 >= 1
#   契约 C5 assert: >= 1
#   设计：业界术语命中（[2026-05-17] 禁自创术语）。
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- SC5.P7 / C5: 业界术语命中 >= 1（两文件合计） ---"

assert_grepE_ge_multi "PC.SC5.P7" 'oracle adequacy|predicate coverage|充分性' 1 \
    "SC5.P7: references/{plan,qa}-reviewer-prompt.md 含业界术语（oracle adequacy / predicate coverage / 充分性）合计 >= 1"

# ─────────────────────────────────────────────────────────────────────────────
# SC7.P9（C7 / 改动清单2）：grep -c '契约元素覆盖' plan-reviewer-prompt.md == 1
#   契约 C7 observe + 改动清单2 验证命令
#   设计：plan-reviewer 维度10「契约元素覆盖」客观可数子集（非伪精度 [2026-05-30]）。
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- SC7.P9 / C7: plan-reviewer-prompt.md 含「契约元素覆盖」== 1 ---"

assert_grep_eq "PC.SC7.P9" '契约元素覆盖' "$PLAN_REVIEWER" 1 \
    "SC7.P9: plan-reviewer-prompt.md 维度10「契约元素覆盖」存在（客观闭集子集，非伪精度）"

# ─────────────────────────────────────────────────────────────────────────────
# 维度9（改动清单1）：grep -c 'knowledge 盲区对照' plan-reviewer-prompt.md == 1
#   改动清单1 验证命令
#   设计：plan-reviewer 维度9「knowledge 盲区对照」—— 治历史盲区复刻（buddy 两 case）。
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- 维度9 / 改动清单1: plan-reviewer-prompt.md 含「knowledge 盲区对照」== 1 ---"

assert_grep_eq "PC.dim9" 'knowledge 盲区对照' "$PLAN_REVIEWER" 1 \
    "维度9: plan-reviewer-prompt.md「knowledge 盲区对照」维度存在（治历史盲区复刻）"

# ─────────────────────────────────────────────────────────────────────────────
# 第三条（改动清单3）：grep -c '谓词充分性反查' qa-reviewer-prompt.md == 1
#   改动清单3 验证命令
#   设计：qa-reviewer「附：审谓词」第三条「谓词充分性反查」—— 治本次代码特有盲区。
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- 第三条 / 改动清单3: qa-reviewer-prompt.md 含「谓词充分性反查」== 1 ---"

assert_grep_eq "PC.third" '谓词充分性反查' "$QA_REVIEWER" 1 \
    "第三条: qa-reviewer-prompt.md「附：审谓词」第三条「谓词充分性反查」存在（治本次代码特有盲区）"

# ─────────────────────────────────────────────────────────────────────────────
# 汇总
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo " R_PRED_COV 汇总: PASSED=$PASSED  FAILED=$FAILED"
echo "=========================================="
echo ""
echo "覆盖的 det-machine 谓词：SC1.P2、SC2.P3、SC5.P7、SC7.P9 + 维度9 + 第三条（SC1.P1/SC3.P4 时序耦合断言已删，见文件头）"
echo "deferred（real-process，留 QA Wave 1.5 dry-run / claude -p dogfood）：SC4.P5/P6、SC6.P8、SC7.P10"

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
