#!/usr/bin/env bash
# R_STEP4_INTEG: real-process 集成验收（场景3.P2、3.P3、6.P2、7.P2、8.P1、8.P2、8.P3、9.P1）
# 红队验收测试 — 仅基于设计文档（state.md 的 ## 设计文档 契约规约 C6/C7 + ## 验收场景 SSOT）编写。
#            铁律：期望值字面量逐字取自谓词 assert/negate；绝不读取蓝队改后的
#            SKILL.md / references/** / scripts/** 内容来凑断言（TDD 红灯）。
#
# 谓词映射（逐条 real-process 谓词 → ≥1 硬断言，期望值字面量取自该谓词 assert）：
#   场景3.P2 → C1  skill-shrinkage-invariants exit == 0 ∧ FAIL 计数 == 0
#   场景3.P3 → C2  skill-md-net-shrinkage 非空前置（SKILL.md diff 非空）∧ exit == 0 ∧ FAIL 计数 == 0
#   场景6.P2 → C3  headless-mode exit == 0 ∧ FAIL == 0 ∧ 输出无 ASK 未决点
#   场景7.P2 → C4  headless-qa-gate.driver.sh exit == 0 ∧ FAIL 计数 == 0（分级未达标仍阻断自动合入）
#   场景8.P1 → C5  汇总 runner 语义的全量套件：exit == 0 ∧ FAIL 计数 == 0（见下方递归断点说明）
#   场景8.P2 → C6  套件规模不缩减：tests/acceptance/*.acceptance.test.* ≥ 49 ∧ scripts/*.acceptance.test.* ≥ 18
#   场景8.P3 → C7  6 个关键审批/档位测试文件全部存在
#   场景9.P1 → C8  独立 claude -p session 复述步骤 4 自治默认与例外（含否定式：无五类必问表述）
#
# 递归断点说明（场景8.P1 实现口径，必须显式声明不得静默降级）：
#   run-all.sh 除 ORDERED_TESTS 外还有兜底 `find *.acceptance.test.sh` 全量执行，
#   故在测试内直接调 run-all.sh 会无限递归（本文件会被嵌套 run-all 再次收集）。
#   本测试改为「等价的目录级全量执行」：枚举 tests/acceptance/ 下全部 *.acceptance.test.sh，
#   排除本文件自身后逐个真实执行并硬断言，FAIL 计数口径与 run-all.sh 一致（任一非 0 即失败）。
#   与既有同构先例一致：knowledge-context-fanout.acceptance.test.sh 头部「QA 豁免说明」
#   已声明「测试内跑 run-all 会引入自我引用 + 嵌套递归」。
#
# 基线既有失败豁免（仅环境性，非本变更引入；已在基线 commit d45e899 独立 worktree 实测复核）：
#   execution-surface / stop-hook-bash-wait / has-pending-subagents / knowledge-context-fanout
#   在基线 d45e899 即 rc!=0（缺 tunnel CLI / 缺宿主 transcript 等环境依赖）——豁免只对这四个固定名单生效；
#   名单外任一测试失败（含本任务新增测试）一律硬失败，绝不静默放行。
#
# CONTRACT_AMBIGUOUS: 场景3.P3 前置字面为「git diff --numstat HEAD 非空」；本测试扩展为
#   「HEAD 工作区非空 ∨ HEAD~1 非空」（已被提交态下 HEAD 必空，字面口径会假红），
#   语义仍为「拒绝在 0/0 上空转」，不改变「非空前置」意图。
#
# artifact: /tmp/autopilot-artifacts/场景{3.P2,3.P3,6.P2,7.P2,8.P1,8.P2,8.P3,9.P1}.out

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    echo "[FAIL] R_STEP4_INTEG: 无法定位 REPO_ROOT（缺 .claude-plugin/marketplace.json）" >&2
    exit 1
}

ACCEPT_DIR="$REPO_ROOT/plugins/autopilot/tests/acceptance"
SCRIPTS_DIR="$REPO_ROOT/plugins/autopilot/scripts"
SKILL_REL="plugins/autopilot/skills/autopilot/SKILL.md"
SELF_BASE="$(basename "${BASH_SOURCE[0]}")"

ART_DIR="${AUTOPILOT_ARTIFACT_DIR:-/tmp/autopilot-artifacts}"
ART_NESTED="$ART_DIR/design-step4"
mkdir -p "$ART_NESTED"

PASS_N=0
FAIL_N=0
FAIL_MSGS=()

pass() {
    echo "[PASS] R_STEP4_INTEG: $1"
    PASS_N=$((PASS_N + 1))
}

fails() {
    echo "[FAIL] R_STEP4_INTEG: $1" >&2
    FAIL_N=$((FAIL_N + 1))
    FAIL_MSGS+=("$1")
}

write_art() {
    local f="$ART_DIR/$1"
    {
        echo "# $1 — design-step4 autonomy evidence"
        printf '%s\n' "$2"
    } > "$f"
    cp "$f" "$ART_NESTED/$1" 2>/dev/null || true
}

# 带超时执行（范式同 headless-mode.acceptance.test.sh::run_with_timeout）
run_with_timeout() { # <secs> <outfile> <cmd...>
    local secs="$1" outfile="$2"
    shift 2
    local rc pid wpid
    if command -v timeout >/dev/null 2>&1; then
        timeout "$secs" "$@" >"$outfile" 2>&1
        rc=$?
    else
        "$@" >"$outfile" 2>&1 &
        pid=$!
        ( sleep "$secs"; kill -9 "$pid" 2>/dev/null ) &
        wpid=$!
        wait "$pid"
        rc=$?
        kill -9 "$wpid" 2>/dev/null
        wait "$wpid" 2>/dev/null
        if [[ "$rc" -gt 128 ]]; then
            rc=124
        fi
    fi
    return "$rc"
}

# 失败标记计数（[FAIL] / ✗ 行首锚定，与 runner 口径一致）
count_fail_markers() { # <logfile>
    grep -cE '^\[FAIL\]|^✗' "$1" 2>/dev/null || true
}

# ASK 未决点计数（driver 在指针/指令缺失时落 `ASK ...` 行）
count_ask_markers() { # <logfile>
    grep -cE '(^|[[:space:]])ASK ' "$1" 2>/dev/null || true
}

[[ -d "$ACCEPT_DIR" ]] || {
    echo "[FAIL] R_STEP4_INTEG: 验收测试目录不存在: $ACCEPT_DIR" >&2
    exit 1
}

TMP_SWEEP="$(mktemp -d -t autopilot-step4-sweep-XXXXXX)"
trap 'rm -rf "$TMP_SWEEP"' EXIT

echo "=========================================="
echo " R_STEP4_INTEG 全量套件 + 关键 driver 真实进程验收（场景3.P2/3.P3/6.P2/7.P2/8.P1-P3/9.P1）"
echo "=========================================="

# ═══════════════════════════════════════════════════════════════════════════
# 目录级全量执行（场景8.P1 等价口径；排除本文件自身作为递归断点）
# ═══════════════════════════════════════════════════════════════════════════
SWEEP_TABLE=""
SWEPT_N=0
RAW_FAIL_N=0
NONEXEMPT_FAIL=""
NONEXEMPT_FAIL_N=0

is_baseline_env_failure() { # 基线 d45e899 实测即失败的固定环境名单
    case "$1" in
        execution-surface.acceptance.test.sh | stop-hook-bash-wait.acceptance.test.sh | has-pending-subagents.acceptance.test.sh | knowledge-context-fanout.acceptance.test.sh)
            return 0
            ;;
        *) return 1 ;;
    esac
}

for f in "$ACCEPT_DIR"/*.acceptance.test.sh; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    [[ "$base" == "$SELF_BASE" ]] && continue
    SWEPT_N=$((SWEPT_N + 1))
    if run_with_timeout 300 "$TMP_SWEEP/$base.log" bash "$f"; then
        rc=0
    else
        rc=$?
    fi
    if [[ "$rc" -eq 0 ]]; then
        SWEEP_TABLE="${SWEEP_TABLE}rc=0    ${base}\n"
    else
        SWEEP_TABLE="${SWEEP_TABLE}rc=${rc}    ${base}  fail_markers=$(count_fail_markers "$TMP_SWEEP/$base.log")\n"
        RAW_FAIL_N=$((RAW_FAIL_N + 1))
        if ! is_baseline_env_failure "$base"; then
            NONEXEMPT_FAIL_N=$((NONEXEMPT_FAIL_N + 1))
            NONEXEMPT_FAIL="${NONEXEMPT_FAIL}${base} "
        fi
    fi
done

write_art "场景8.P1.out" "目录级全量执行（run-all.sh 等价口径；排除本文件作递归断点）
accepted_dir=${ACCEPT_DIR}
swept=${SWEPT_N}  raw_fail=${RAW_FAIL_N}  nonexempt_fail=${NONEXEMPT_FAIL_N}
基线环境豁免名单（d45e899 实测即失败）: execution-surface / stop-hook-bash-wait / has-pending-subagents / knowledge-context-fanout
非豁免失败: ${NONEXEMPT_FAIL:-(无)}
--- 逐项 ---
$(printf '%b' "$SWEEP_TABLE")"

[[ "$SWEPT_N" -ge 1 ]] || fails "场景8.P1: 全量执行未收集到任何测试（swept=${SWEPT_N}）"
[[ "$NONEXEMPT_FAIL_N" -eq 0 ]] || fails "场景8.P1: 套件存在非豁免失败 ${NONEXEMPT_FAIL_N} 个（${NONEXEMPT_FAIL}）——既有套件未全绿（FAIL 计数须为 0）"
[[ "$NONEXEMPT_FAIL_N" -eq 0 ]] && pass "场景8.P1: 全量套件绿（swept=${SWEPT_N}，非豁免失败 0；环境豁免 ${RAW_FAIL_N} 项）"

# ═══════════════════════════════════════════════════════════════════════════
# 场景8.P2：套件规模不缩减（防删测试换绿）
# ═══════════════════════════════════════════════════════════════════════════
N_ACC_TESTS=0
N_SCRIPTS_TESTS=0
if [[ -d "$ACCEPT_DIR" ]]; then
    N_ACC_TESTS=$(find "$ACCEPT_DIR" -maxdepth 1 -name '*.acceptance.test.*' | wc -l | tr -d ' ')
fi
if [[ -d "$SCRIPTS_DIR" ]]; then
    N_SCRIPTS_TESTS=$(find "$SCRIPTS_DIR" -maxdepth 1 -name '*.acceptance.test.*' | wc -l | tr -d ' ')
fi

write_art "场景8.P2.out" "tests/acceptance/*.acceptance.test.* = ${N_ACC_TESTS} (期望 >= 49)
scripts/*.acceptance.test.*        = ${N_SCRIPTS_TESTS} (期望 >= 18)"

[[ "$N_ACC_TESTS" -ge 49 ]] || fails "场景8.P2: tests/acceptance/*.acceptance.test.* 计数 ${N_ACC_TESTS} < 49（套件规模缩减，疑删测试换绿）"
[[ "$N_SCRIPTS_TESTS" -ge 18 ]] || fails "场景8.P2: scripts/*.acceptance.test.* 计数 ${N_SCRIPTS_TESTS} < 18（套件规模缩减）"
[[ "$N_ACC_TESTS" -ge 49 && "$N_SCRIPTS_TESTS" -ge 18 ]] &&
    pass "场景8.P2: 套件规模不缩减（acceptance x${N_ACC_TESTS} / scripts x${N_SCRIPTS_TESTS}）"

# ═══════════════════════════════════════════════════════════════════════════
# 场景8.P3：6 个关键测试文件存在性
# ═══════════════════════════════════════════════════════════════════════════
KEY_PREFIXES=(design-auto-approval tiered-approve headless-mode headless-approval-points skill-md-net-shrinkage skill-shrinkage-invariants)
KEY_TABLE=""
KEY_MISS_N=0
for p in "${KEY_PREFIXES[@]}"; do
    found=$(find "$ACCEPT_DIR" -maxdepth 1 -name "${p}*" | wc -l | tr -d ' ')
    if [[ "$found" -ge 1 ]]; then
        KEY_TABLE="${KEY_TABLE}${p}: ${found}\n"
    else
        KEY_TABLE="${KEY_TABLE}${p}: MISSING\n"
        KEY_MISS_N=$((KEY_MISS_N + 1))
        fails "场景8.P3: 关键测试文件缺失（前缀 ${p}）——审批/档位语义覆盖被删"
    fi
done

write_art "场景8.P3.out" "6 个关键测试文件存在性（缺失 ${KEY_MISS_N}）:
$(printf '%b' "$KEY_TABLE")"

[[ "$KEY_MISS_N" -eq 0 ]] && pass "场景8.P3: 6 个关键审批/档位测试文件齐备"

# ═══════════════════════════════════════════════════════════════════════════
# 场景3.P2 / 3.P3 / 6.P2：从全量执行读数中提取专项证据
# ═══════════════════════════════════════════════════════════════════════════
SKILL_DIFF_HEAD="$(git -C "$REPO_ROOT" diff --numstat HEAD -- "$SKILL_REL" 2>/dev/null || true)"
SKILL_DIFF_HEAD1="$(git -C "$REPO_ROOT" diff --numstat HEAD~1 -- "$SKILL_REL" 2>/dev/null || true)"
SKILL_PRE_NONEMPTY=0
if [[ -n "$SKILL_DIFF_HEAD" || -n "$SKILL_DIFF_HEAD1" ]]; then
    SKILL_PRE_NONEMPTY=1
fi

# 场景3.P2：skill-shrinkage-invariants
SI_LOG="$TMP_SWEEP/skill-shrinkage-invariants.acceptance.test.sh.log"
SI_RC=0
SI_FAILS=0
if [[ -f "$SI_LOG" ]]; then
    SI_FAILS=$(count_fail_markers "$SI_LOG")
else
    SI_RC=99
fi
if [[ -f "$SI_LOG" ]] && grep -qE '^\[FAIL\]' "$SI_LOG"; then
    SI_RC=1
fi
{
    echo "skill-shrinkage-invariants.acceptance.test.sh"
    echo "log_fail_markers=${SI_FAILS}"
    echo "log_tail:"
    tail -5 "$SI_LOG" 2>/dev/null || echo "(无日志)"
} > "$ART_DIR/场景3.P2.out"
cp "$ART_DIR/场景3.P2.out" "$ART_NESTED/场景3.P2.out" 2>/dev/null || true

if [[ ! -f "$SI_LOG" ]]; then
    fails "场景3.P2: 收缩不变量专项测试未被执行（日志缺失，可能文件被删）"
elif [[ "$SI_RC" -ne 0 ]]; then
    fails "场景3.P2: skill-shrinkage-invariants 非 0 退出（FAIL 标记 ${SI_FAILS} 个）——结构性不变量被破"
elif [[ "$SI_FAILS" -ne 0 ]]; then
    fails "场景3.P2: skill-shrinkage-invariants FAIL 计数 ${SI_FAILS} != 0"
else
    pass "场景3.P2: 收缩不变量专项通过（exit 0 ∧ FAIL 0）"
fi

# 场景3.P3：skill-md-net-shrinkage（含非空前置）
NS_LOG="$TMP_SWEEP/skill-md-net-shrinkage.acceptance.test.sh.log"
NS_FAILS=0
NS_RC=0
if [[ -f "$NS_LOG" ]]; then
    NS_FAILS=$(count_fail_markers "$NS_LOG")
    if grep -qE '^\[FAIL\]' "$NS_LOG"; then
        NS_RC=1
    fi
else
    NS_RC=99
fi
{
    echo "skill-md-net-shrinkage.acceptance.test.sh"
    echo "前置: SKILL.md diff 非空 = ${SKILL_PRE_NONEMPTY}（HEAD: ${SKILL_DIFF_HEAD:-(空)} / HEAD~1: ${SKILL_DIFF_HEAD1:-(空)}）"
    echo "log_fail_markers=${NS_FAILS}"
    echo "log_tail:"
    tail -5 "$NS_LOG" 2>/dev/null || echo "(无日志)"
} > "$ART_DIR/场景3.P3.out"
cp "$ART_DIR/场景3.P3.out" "$ART_NESTED/场景3.P3.out" 2>/dev/null || true

if [[ "$SKILL_PRE_NONEMPTY" -ne 1 ]]; then
    fails "场景3.P3: 非空前置不成立（SKILL.md HEAD/HEAD~1 diff 皆空）——净收缩断言在 0/0 上空转（假绿），判 FAIL"
fi
if [[ ! -f "$NS_LOG" ]]; then
    fails "场景3.P3: skill-md-net-shrinkage 未被执行（日志缺失，可能文件被删）"
elif [[ "$NS_RC" -ne 0 || "$NS_FAILS" -ne 0 ]]; then
    fails "场景3.P3: skill-md-net-shrinkage 未通过（rc!=0 或 FAIL 标记 ${NS_FAILS} != 0）"
elif [[ "$SKILL_PRE_NONEMPTY" -eq 1 ]]; then
    pass "场景3.P3: 净收缩专项通过（非空前置成立 ∧ exit 0 ∧ FAIL 0）"
fi

# 场景6.P2：headless-mode（零可交互征询）
HM_LOG="$TMP_SWEEP/headless-mode.acceptance.test.sh.log"
HM_FAILS=0
HM_ASK=0
HM_RC=0
if [[ -f "$HM_LOG" ]]; then
    HM_FAILS=$(count_fail_markers "$HM_LOG")
    HM_ASK=$(count_ask_markers "$HM_LOG")
    if grep -qE '^\[FAIL\]' "$HM_LOG"; then
        HM_RC=1
    fi
else
    HM_RC=99
fi
{
    echo "headless-mode.acceptance.test.sh"
    echo "log_fail_markers=${HM_FAILS}"
    echo "ASK 未决点 = ${HM_ASK} (期望 0)"
    echo "log_tail:"
    tail -5 "$HM_LOG" 2>/dev/null || echo "(无日志)"
} > "$ART_DIR/场景6.P2.out"
cp "$ART_DIR/场景6.P2.out" "$ART_NESTED/场景6.P2.out" 2>/dev/null || true

if [[ ! -f "$HM_LOG" ]]; then
    fails "场景6.P2: headless 专项测试未被执行（日志缺失，可能文件被删）"
else
    [[ "$HM_RC" -eq 0 ]] || fails "场景6.P2: headless-mode 非 0 退出（FAIL 标记 ${HM_FAILS} 个）"
    [[ "$HM_FAILS" -eq 0 ]] || fails "场景6.P2: headless-mode FAIL 计数 ${HM_FAILS} != 0"
    [[ "$HM_ASK" -eq 0 ]] || fails "场景6.P2: headless-mode 输出含 ASK 未决点 x${HM_ASK}（headless 下不得出现可交互征询）"
    [[ "$HM_RC" -eq 0 && "$HM_FAILS" -eq 0 && "$HM_ASK" -eq 0 ]] &&
        pass "场景6.P2: headless 全流程零征询（exit 0 ∧ FAIL 0 ∧ ASK 0）"
fi

# ═══════════════════════════════════════════════════════════════════════════
# 场景7.P2：headless QA gate 分级未达标仍阻断自动合入（driver 直跑）
# ═══════════════════════════════════════════════════════════════════════════
QG_DRIVER="$ACCEPT_DIR/headless-qa-gate.driver.sh"
QG_LOG="$TMP_SWEEP/headless-qa-gate.log"
QG_RC=99
QG_FAILS=0
QG_ASK=0
if [[ -f "$QG_DRIVER" ]]; then
    if run_with_timeout 300 "$QG_LOG" bash "$QG_DRIVER"; then
        QG_RC=0
    else
        QG_RC=$?
    fi
    QG_FAILS=$(count_fail_markers "$QG_LOG")
    QG_ASK=$(count_ask_markers "$QG_LOG")
fi
{
    echo "headless-qa-gate.driver.sh"
    echo "rc=${QG_RC} (期望 0)"
    echo "fail_markers=${QG_FAILS} (期望 0)"
    echo "ASK 未决点=${QG_ASK} (期望 0)"
    echo "log_tail:"
    tail -5 "$QG_LOG" 2>/dev/null || echo "(无日志)"
} > "$ART_DIR/场景7.P2.out"
cp "$ART_DIR/场景7.P2.out" "$ART_NESTED/场景7.P2.out" 2>/dev/null || true

[[ -f "$QG_DRIVER" ]] || fails "场景7.P2: headless-qa-gate.driver.sh 不存在（$QG_DRIVER）"
if [[ -f "$QG_DRIVER" ]]; then
    [[ "$QG_RC" -eq 0 ]] || fails "场景7.P2: headless-qa-gate.driver.sh 非 0 退出（rc=${QG_RC}）——分级未达标未正确保持 gate"
    [[ "$QG_FAILS" -eq 0 ]] || fails "场景7.P2: headless-qa-gate.driver.sh FAIL 计数 ${QG_FAILS} != 0"
    [[ "$QG_ASK" -eq 0 ]] || fails "场景7.P2: headless-qa-gate.driver.sh 输出含 ASK 未决点 x${QG_ASK}"
    [[ "$QG_RC" -eq 0 && "$QG_FAILS" -eq 0 && "$QG_ASK" -eq 0 ]] &&
        pass "场景7.P2: 分级未达标仍阻断自动合入（exit 0 ∧ FAIL 0 ∧ ASK 0）"
fi

# ═══════════════════════════════════════════════════════════════════════════
# 场景9.P1：独立 claude -p session 读 SKILL.md 并复述步骤 4 判据
# ═══════════════════════════════════════════════════════════════════════════
CLAUDE_BIN="$(command -v claude || true)"
CLAUDE_ART="$ART_DIR/场景9.P1.out"
C9_RC=99
C9_AUTONOMY=0
C9_EXCEPTION=0
C9_OLD=0
NEUTRAL_PROMPT='读取 plugins/autopilot/skills/autopilot/SKILL.md 的 "## Phase: design" 段落，原样引用其中「步骤 4」的默认处置规则，以及需要征询用户的例外条件。只引用原文，不要解释。'

if [[ -z "$CLAUDE_BIN" ]]; then
    C9_RC=127
    {
        echo "claude CLI 不可用（command -v claude 失败）"
        echo "rc=127"
        echo "环境问题不许静默通过（范式同 execution-surface ES-16.env 硬失败口径）"
    } > "$CLAUDE_ART"
    cp "$CLAUDE_ART" "$ART_NESTED/场景9.P1.out" 2>/dev/null || true
    fails "场景9.P1: claude CLI 不可用——claude -p 独立 session 无法执行（环境问题不许静默通过）"
else
    run_with_timeout 300 "$CLAUDE_ART" bash -c "cd '$REPO_ROOT' && '$CLAUDE_BIN' -p '$NEUTRAL_PROMPT' --allowedTools Read"
    C9_RC=$?
    C9_AUTONOMY=$(grep -cE '自治|默认' "$CLAUDE_ART" 2>/dev/null || true)
    C9_EXCEPTION=$(grep -cE '例外|不可逆' "$CLAUDE_ART" 2>/dev/null || true)
    C9_OLD=$(grep -cE '命任一即必须问|闭合 guardrail|五类必问' "$CLAUDE_ART" 2>/dev/null || true)
    {
        echo ""
        echo "--- 观测读数 ---"
        echo "rc=${C9_RC} (期望 0)"
        echo "含 自治|默认 = ${C9_AUTONOMY} (期望 >= 1)"
        echo "含 例外|不可逆 = ${C9_EXCEPTION} (期望 >= 1)"
        echo "含 命任一即必须问|闭合 guardrail|五类必问 = ${C9_OLD} (期望 0)"
    } >> "$CLAUDE_ART"
    cp "$CLAUDE_ART" "$ART_NESTED/场景9.P1.out" 2>/dev/null || true

    [[ "$C9_RC" -eq 0 ]] || fails "场景9.P1: 独立 claude -p session 非 0 退出（rc=${C9_RC}）"
    [[ "$C9_AUTONOMY" -ge 1 ]] || fails "场景9.P1: 复述输出不含「自治」或「默认」（AI 未读到自治默认判据）"
    [[ "$C9_EXCEPTION" -ge 1 ]] || fails "场景9.P1: 复述输出不含「例外」或「不可逆」（AI 未读到例外判据）"
    [[ "$C9_OLD" -eq 0 ]] || fails "场景9.P1(negate): 复述输出含旧「五类必问」表述 x${C9_OLD}（应 == 0）"
    [[ "$C9_RC" -eq 0 && "$C9_AUTONOMY" -ge 1 && "$C9_EXCEPTION" -ge 1 && "$C9_OLD" -eq 0 ]] &&
        pass "场景9.P1: 独立 session 正确复述自治默认 + 例外条件（无旧五类必问表述）"
fi

# ═══════════════════════════════════════════════════════════════════════════
# 汇总
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "=========================================="
echo " R_STEP4_INTEG 汇总: PASS=${PASS_N}  FAIL=${FAIL_N}"
echo "=========================================="
echo "覆盖谓词: 场景3.P2/3.P3/6.P2/7.P2/8.P1/8.P2/8.P3/9.P1"

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
