#!/usr/bin/env bash
# R_STEP4_MECH: 步骤 4 改写后的行数收缩硬约束 + headless 档位语义 + 机械层零改动（场景3.P1、6.P1、7.P1、7.P3）
# 红队验收测试 — 仅基于设计文档（state.md 的 ## 设计文档 契约规约 C4/C5/C7 + ## 验收场景 SSOT）编写。
#            铁律：期望值字面量逐字取自谓词 assert/negate 与契约规约；
#            绝不读取蓝队改后的 SKILL.md / references/** / scripts/** 内容来凑断言（TDD 红灯）。
#
# 谓词映射（逐条 det-machine 谓词 → ≥1 硬断言，期望值字面量取自该谓词 assert/negate）：
#   场景3.P1 → B1.1 `git diff --numstat` (added - deleted) ≤ 0 ∧ B1.2 `476 ≤ wc -l ≤ 478`（C4 双向：净减 + 下界防下游 ±3 行窗口滑出）
#   场景6.P1 → B2.1 headless-protocol.md 同行共现 `guardrail` ∧ `必问` 计数 == 0
#              ∧ B2.2 含 `例外` 与 `不问` 的行 ≥ 1 ∧ B2.3 文件内 `预授权` 仍存在（C7：headless-mode 硬断言依赖）
#   场景7.P1 → B3.1 stop-hook.sh diff == `1 added / 1 deleted`
#              ∧ B3.2 变更行为 `PROMPT=` 文案行 ∧ B3.3 新文案含 `步骤 4` 判据语义
#              ∧ B3.4 除该 PROMPT 行外无其它 `+`/`-` 行（无逻辑/变量/分支改动）
#   场景7.P3 → B4.1 `lib.sh` diff 行数 == 0 ∧ B4.2 `scripts/` 变更文件 ⊆ C5 白名单
#              ∧ B4.3 setup.sh diff == 1 增 1 删（≤ 2 行，C5 白名单）
#
# CONTRACT_AMBIGUOUS（必须提请补声明，不得静默择一）：
#   场景7.P3 assert 字面为「`scripts/` 下变更文件**仅** `setup.sh`」，但契约 C5 同时允许
#   `stop-hook.sh` 的 1 行 PROMPT 文案变更，且场景7.P1 要求该变更必须发生——两者字面互斥
#   （「仅 setup.sh」成立时 7.P1 必红，反之亦然），本 SSOT 无任何实现能同时满足。
#   本测试按 C5（变更白名单 {`stop-hook.sh` 1 行 PROMPT, `setup.sh` 1 行 PHASE_FLOW} + `lib.sh` 零变更）
#   实现 B4.2：断言 scripts/ 变更集合 ⊆ 白名单 ∧ lib.sh 0 行 ∧ setup.sh ≤ 2 行——白名单外任一文件被改仍硬失败；
#   并保留 B4.3 对 setup.sh 的 1 增 1 删硬约束。请补声明统一 C5 与 7.P3 口径。
#
# 变更基线解析（两种性质，勿混用）：
#   ① 滚动契约（场景3.P1「SKILL.md 只减不增」）→ 三步 fallback：工作区 vs HEAD；
#      HEAD~1；最近一次触碰该路径的 commit 自身 diff。约束的是"任何一次改动"，
#      故每次运行都重新指向最新的那次改动，是正确语义。
#   ② 一次性契约（场景7.P1/7.P3「v3.72.0 那次改动限于 C5 白名单」）→ **显式钉死 rev 区间**
#      （CHANGE_PIN_SPEC）。期望值与 :1203 行号都是该次改动的历史事实，用 fallback 会被
#      后续提交 latch 到新 commit 而恒红（[2026-09-25] 修复，详见场景7.P1 段注释）。
#   两者皆空 / 取不到 → 判 FAIL（无变更可归因 = 减法未发生 / 变更不可定位），绝不静默放行。
#
# artifact: /tmp/autopilot-artifacts/场景{3.P1,6.P1,7.P1,7.P3}.out

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
    echo "[FAIL] R_STEP4_MECH: 无法定位 REPO_ROOT（缺 .claude-plugin/marketplace.json）" >&2
    exit 1
}

[[ -d "$REPO_ROOT/.git" || -f "$REPO_ROOT/.git" ]] || {
    echo "[FAIL] R_STEP4_MECH: REPO_ROOT 非 git 仓库: ${REPO_ROOT}" >&2
    exit 1
}

SKILL_REL="plugins/autopilot/skills/autopilot/SKILL.md"
SKILL_FILE="$REPO_ROOT/$SKILL_REL"
PROTOCOL_MD="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/headless-protocol.md"
STOP_HOOK_REL="plugins/autopilot/scripts/stop-hook.sh"
STOP_HOOK_FILE="$REPO_ROOT/$STOP_HOOK_REL"
SCRIPTS_REL="plugins/autopilot/scripts"
LIB_REL="plugins/autopilot/scripts/lib.sh"
SETUP_REL="plugins/autopilot/scripts/setup.sh"

ART_DIR="${AUTOPILOT_ARTIFACT_DIR:-/tmp/autopilot-artifacts}"
ART_NESTED="$ART_DIR/design-step4"
mkdir -p "$ART_NESTED"

PASS_N=0
FAIL_N=0
FAIL_MSGS=()

pass() {
    echo "[PASS] R_STEP4_MECH: $1"
    PASS_N=$((PASS_N + 1))
}

fails() {
    echo "[FAIL] R_STEP4_MECH: $1" >&2
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

# ── 变更基线解析：打印可用的 diff rev spec（可含两个 rev），无则 rc1 ──────────
resolve_change_spec() { # <relpath>
    local rel="$1"
    local c out
    if [[ -n "$(git -C "$REPO_ROOT" diff --numstat HEAD -- "$rel" 2>/dev/null || true)" ]]; then
        echo "HEAD"
        return 0
    fi
    if [[ -n "$(git -C "$REPO_ROOT" diff --numstat HEAD~1 -- "$rel" 2>/dev/null || true)" ]]; then
        echo "HEAD~1"
        return 0
    fi
    c="$(git -C "$REPO_ROOT" log -n1 --format=%H -- "$rel" 2>/dev/null || true)"
    if [[ -n "$c" ]]; then
        out="$(git -C "$REPO_ROOT" diff --numstat "$c^" "$c" -- "$rel" 2>/dev/null || true)"
        if [[ -n "$out" ]]; then
            echo "$c^ $c"
            return 0
        fi
    fi
    return 1
}

# ── 在给定 rev spec 下取某路径的 numstat（added deleted）；无输出打印 "0 0" ──
numstat_of() { # <revspec> <relpath>
    local spec="$1" rel="$2" line added deleted
    # shellcheck disable=SC2086  # spec 可为两个 rev（"<sha>^ <sha>"），需按词拆分
    line="$(git -C "$REPO_ROOT" diff --numstat $spec -- "$rel" 2>/dev/null || true)"
    if [[ -z "$line" ]]; then
        echo "0 0"
        return 0
    fi
    added="$(printf '%s\n' "$line" | awk '{s+=$1} END{print s+0}')"
    deleted="$(printf '%s\n' "$line" | awk '{s+=$2} END{print s+0}')"
    echo "$added $deleted"
}

# ── 前置：受检文件存在（缺失即硬失败，不允许静默跳过） ───────────────────────
[[ -f "$SKILL_FILE" ]] || fails "SKILL.md 不存在: $SKILL_FILE"
[[ -f "$STOP_HOOK_FILE" ]] || fails "stop-hook.sh 不存在: $STOP_HOOK_FILE"

echo "=========================================="
echo " R_STEP4_MECH 行数收缩 + headless 档位语义 + 机械层零改动（场景3/6/7）"
echo "=========================================="

# ═══════════════════════════════════════════════════════════════════════════
# 场景3.P1：SKILL.md 净增行数 ≤ 0 且 476 ≤ wc -l ≤ 478（C4 双向）
# ═══════════════════════════════════════════════════════════════════════════
SKILL_SPEC="$(resolve_change_spec "$SKILL_REL" || true)"
SKILL_ADDED=0
SKILL_DELETED=0
SKILL_SPEC_DESC="(无)"
if [[ -n "$SKILL_SPEC" ]]; then
    read -r SKILL_ADDED SKILL_DELETED <<<"$(numstat_of "$SKILL_SPEC" "$SKILL_REL")"
    SKILL_SPEC_DESC="$SKILL_SPEC"
fi
SKILL_LINES=0
if [[ -f "$SKILL_FILE" ]]; then
    SKILL_LINES=$(wc -l < "$SKILL_FILE" | tr -d ' ')
fi

write_art "场景3.P1.out" "SKILL.md=$SKILL_REL
diff 基线 spec = ${SKILL_SPEC_DESC}  (① HEAD 工作区 / ② HEAD~1 已提交 / ③ 最近触碰 commit)
added=${SKILL_ADDED} deleted=${SKILL_DELETED}  net=$((SKILL_DELETED - SKILL_ADDED))
wc -l=${SKILL_LINES}  (期望 476 <= wc -l <= 478)
基线 478 行；C4：k=2 净删 → 476 下界防下游 ±3 行窗口滑出"

[[ -n "$SKILL_SPEC" ]] || fails "场景3.P1: 无法定位 SKILL.md 变更（HEAD/HEAD~1/最近触碰 commit 三步 diff 皆空）——减法未发生的 no-op 不可判定，判 FAIL"
[[ "$SKILL_ADDED" -le "$SKILL_DELETED" ]] || fails "场景3.P1: SKILL.md 净增行数 $((SKILL_ADDED - SKILL_DELETED)) > 0（added=${SKILL_ADDED} > deleted=${SKILL_DELETED}；C4 要求净减/持平）"
[[ "$SKILL_LINES" -ge 476 ]] || fails "场景3.P1: SKILL.md wc -l = ${SKILL_LINES} < 476 下界（C4 下界用于防 headless-mode skill_win_has 348/362 的 ±3 行窗口滑出）"
[[ "$SKILL_LINES" -le 478 ]] || fails "场景3.P1: SKILL.md wc -l = ${SKILL_LINES} > 478 上界（只减不增契约被破）"
if [[ -n "$SKILL_SPEC" && "$SKILL_ADDED" -le "$SKILL_DELETED" && "$SKILL_LINES" -ge 476 && "$SKILL_LINES" -le 478 ]]; then
    pass "场景3.P1: SKILL.md 净收缩 + 行数窗口（added=${SKILL_ADDED} deleted=${SKILL_DELETED} wc -l=${SKILL_LINES} ∈ [476, 478]）"
fi

# ═══════════════════════════════════════════════════════════════════════════
# 场景6.P1：headless 档位语义收敛（guardrail 必问 → 例外征询）+ 预授权保留（C7）
# ═══════════════════════════════════════════════════════════════════════════
PROTO_GUARDRAIL_ASK=0
PROTO_EXCEPTION_NOASK=0
PROTO_PREAUTH=0
if [[ -f "$PROTOCOL_MD" ]]; then
    PROTO_GUARDRAIL_ASK=$(grep -F 'guardrail' "$PROTOCOL_MD" | grep -cF '必问' || true)
    PROTO_EXCEPTION_NOASK=$(grep -E '例外' "$PROTOCOL_MD" | grep -cF '不问' || true)
    PROTO_PREAUTH=$(grep -cF '预授权' "$PROTOCOL_MD" || true)
fi

write_art "场景6.P1.out" "headless-protocol.md 行为矩阵
同行共现 guardrail ∧ 必问 = ${PROTO_GUARDRAIL_ASK} (期望 0)
同行含 例外 ∧ 不问 = ${PROTO_EXCEPTION_NOASK} (期望 >= 1)
预授权 = ${PROTO_PREAUTH} (期望 >= 1，C7 headless-mode:826 硬断言依赖)"

[[ -f "$PROTOCOL_MD" ]] || fails "场景6.P1: headless-protocol.md 不存在: $PROTOCOL_MD"
[[ "$PROTO_GUARDRAIL_ASK" -eq 0 ]] || fails "场景6.P1(negate): headless-protocol.md 仍含同行共现 'guardrail' ∧ '必问' x${PROTO_GUARDRAIL_ASK}（应 == 0，档位旧差异陈述未收敛）"
[[ "$PROTO_EXCEPTION_NOASK" -ge 1 ]] || fails "场景6.P1: headless-protocol.md 无含 '例外' 与 '不问' 的行（命中 ${PROTO_EXCEPTION_NOASK} < 1，新语义未落地）"
[[ "$PROTO_PREAUTH" -ge 1 ]] || fails "场景6.P1(C7): headless-protocol.md '预授权' 字样消失（命中 ${PROTO_PREAUTH} < 1；headless-mode 硬断言 grep -qF 预授权 依赖）"
if [[ "$PROTO_GUARDRAIL_ASK" -eq 0 && "$PROTO_EXCEPTION_NOASK" -ge 1 && "$PROTO_PREAUTH" -ge 1 ]]; then
    pass "场景6.P1: 档位语义收敛（guardrail∧必问 0 / 例外∧不问 x${PROTO_EXCEPTION_NOASK} / 预授权保留 x${PROTO_PREAUTH}）"
fi

# ═══════════════════════════════════════════════════════════════════════════
# 场景7.P1：stop-hook.sh 改动限于 1 行散文文案
# ═══════════════════════════════════════════════════════════════════════════
# 变更基线钉死（[2026-09-25] 修复）：场景7 是**针对 v3.72.0「design 步骤 4 自治」那次改动**的
# 范围契约（期望值与 :1203 行号均逐字取自那次的契约规约 C4/C5），属一次性历史事实而非永久
# 不变量——stop-hook.sh 后续必然要有逻辑修复（v3.73.1 的 TaskStop 修复即 +50/−8）。
# 原三步 fallback（HEAD 工作区 / HEAD~1 / 最近触碰 commit）是「定位待测改动」的机制，只在
# 该改动仍是最新改动时成立；一旦后续提交触碰 scripts/ 就 latch 到新 commit，使 C5 白名单恒红
# （v3.73.0/v3.73.1 之后即如此，与本次改动无关）。故改为显式钉死的 rev 区间；区间取不到
# （如历史被改写）仍判 FAIL——保留「无变更可归因即判红」的语义，不静默放行。
# 注：场景3.P1（SKILL.md 只减不增）仍用 fallback 解析，因其契约是**滚动**的（约束"任何一次
# 对 SKILL.md 的改动"），与场景7 的一次性契约性质不同。
CHANGE_PIN_SPEC="e1af09c^ e1af09c"   # v3.72.0：design 步骤 4 改 AI-First 自治
CHANGE_PIN_DESC="e1af09c (v3.72.0 design 步骤 4 自治)"
HOOK_SPEC=""
if [[ -n "$(git -C "$REPO_ROOT" diff --numstat $CHANGE_PIN_SPEC -- "$STOP_HOOK_REL" 2>/dev/null || true)" ]]; then
    HOOK_SPEC="$CHANGE_PIN_SPEC"
fi
HOOK_ADDED=0
HOOK_DELETED=0
HOOK_PLUS_BODY=""
HOOK_MINUS_BODY=""
HOOK_PLUS_N=0
HOOK_MINUS_N=0
if [[ -n "$HOOK_SPEC" ]]; then
    read -r HOOK_ADDED HOOK_DELETED <<<"$(numstat_of "$HOOK_SPEC" "$STOP_HOOK_REL")"
    # shellcheck disable=SC2086  # spec 可为两个 rev，需按词拆分
    HOOK_DIFF="$(git -C "$REPO_ROOT" diff -U0 $HOOK_SPEC -- "$STOP_HOOK_REL" 2>/dev/null || true)"
    HOOK_PLUS_BODY="$(printf '%s\n' "$HOOK_DIFF" | grep '^+[^+]' || true)"
    HOOK_MINUS_BODY="$(printf '%s\n' "$HOOK_DIFF" | grep '^-[^-]' || true)"
    HOOK_PLUS_N=$(printf '%s\n' "$HOOK_PLUS_BODY" | grep -c . || true)
    HOOK_MINUS_N=$(printf '%s\n' "$HOOK_MINUS_BODY" | grep -c . || true)
fi

HOOK_MINUS_IS_PROMPT=0
HOOK_PLUS_IS_PROMPT=0
HOOK_PLUS_HAS_STEP4=0
HOOK_PLUS_HAS_OLD_PHRASE=0
printf '%s\n' "$HOOK_MINUS_BODY" | grep -qF 'PROMPT=' && HOOK_MINUS_IS_PROMPT=1
printf '%s\n' "$HOOK_PLUS_BODY" | grep -qF 'PROMPT=' && HOOK_PLUS_IS_PROMPT=1
printf '%s\n' "$HOOK_PLUS_BODY" | grep -qF '步骤 4' && HOOK_PLUS_HAS_STEP4=1
printf '%s\n' "$HOOK_PLUS_BODY" | grep -qF '请求用户审批' && HOOK_PLUS_HAS_OLD_PHRASE=1

write_art "场景7.P1.out" "stop-hook.sh=$STOP_HOOK_REL
diff 基线 spec = ${HOOK_SPEC:-(无)}  [钉死：${CHANGE_PIN_DESC}]
added=${HOOK_ADDED} deleted=${HOOK_DELETED}  (期望 1 / 1)
+ 行数=${HOOK_PLUS_N}  - 行数=${HOOK_MINUS_N}  (期望各 1)
新行含 PROMPT= : ${HOOK_PLUS_IS_PROMPT}
新行含 步骤 4 判据语义 : ${HOOK_PLUS_HAS_STEP4}
新行残留 请求用户审批 : ${HOOK_PLUS_HAS_OLD_PHRASE} (期望 0)
旧行含 PROMPT= : ${HOOK_MINUS_IS_PROMPT}
C5：仅允许 :1203 兜底 PROMPT 的 1 句文案变更（无逻辑/变量/分支改动）"

[[ -n "$HOOK_SPEC" ]] || fails "场景7.P1: 钉死区间取不到 stop-hook.sh 变更（${CHANGE_PIN_DESC}）——C5 要求 :1203 兜底 PROMPT 文案必须改，未改判 FAIL"
[[ "$HOOK_ADDED" -eq 1 && "$HOOK_DELETED" -eq 1 ]] || fails "场景7.P1: stop-hook.sh diff 非 '1 added / 1 deleted'（实际 ${HOOK_ADDED} / ${HOOK_DELETED}）"
[[ "$HOOK_PLUS_N" -eq 1 && "$HOOK_MINUS_N" -eq 1 ]] || fails "场景7.P1: diff 含其它 +/- 行（+ 行 ${HOOK_PLUS_N} / - 行 ${HOOK_MINUS_N}，期望各 1；C5 禁逻辑/变量/分支改动）"
[[ "$HOOK_MINUS_IS_PROMPT" -eq 1 ]] || fails "场景7.P1: 被删除行不是 'PROMPT=' 文案行（改动越界 C5 白名单）"
[[ "$HOOK_PLUS_IS_PROMPT" -eq 1 ]] || fails "场景7.P1: 新增行不是 'PROMPT=' 文案行（改动越界 C5 白名单）"
[[ "$HOOK_PLUS_HAS_STEP4" -eq 1 ]] || fails "场景7.P1: 新 PROMPT 文案不含 '步骤 4' 判据语义（A22：应指向 SKILL.md 步骤 4 判据）"
[[ "$HOOK_PLUS_HAS_OLD_PHRASE" -eq 0 ]] || fails "场景7.P1(negate): 新 PROMPT 文案仍含 '请求用户审批'（旧方向未清除，机械层反向下令未消除）"
if [[ -n "$HOOK_SPEC" && "$HOOK_ADDED" -eq 1 && "$HOOK_DELETED" -eq 1 && "$HOOK_PLUS_N" -eq 1 && "$HOOK_MINUS_N" -eq 1 \
    && "$HOOK_MINUS_IS_PROMPT" -eq 1 && "$HOOK_PLUS_IS_PROMPT" -eq 1 && "$HOOK_PLUS_HAS_STEP4" -eq 1 && "$HOOK_PLUS_HAS_OLD_PHRASE" -eq 0 ]]; then
    pass "场景7.P1: stop-hook.sh 改动限于 1 行 PROMPT 文案（1/1，新文案含步骤 4 判据，无逻辑改动）"
fi

# ═══════════════════════════════════════════════════════════════════════════
# 场景7.P3：lib.sh 逐字节不变 + scripts/ 变更白名单（C5 后半）
# ═══════════════════════════════════════════════════════════════════════════
SCOPE_SPEC=""
if [[ -n "$(git -C "$REPO_ROOT" diff --name-only $CHANGE_PIN_SPEC -- "$SCRIPTS_REL" 2>/dev/null || true)" ]]; then
    SCOPE_SPEC="$CHANGE_PIN_SPEC"
fi
SCRIPTS_CHANGED=""
LIB_STAT="(未解析)"
LIB_ADDED=0
LIB_DELETED=0
SETUP_ADDED=0
SETUP_DELETED=0
SETUP_OK=0
WHITELIST_VIOLATION=""
WHITELIST_VIOLATION_N=0

if [[ -n "$SCOPE_SPEC" ]]; then
    # shellcheck disable=SC2086  # spec 可为两个 rev，需按词拆分
    SCRIPTS_CHANGED="$(git -C "$REPO_ROOT" diff --name-only $SCOPE_SPEC -- "$SCRIPTS_REL" 2>/dev/null || true)"
    # shellcheck disable=SC2086
    LIB_RAW="$(git -C "$REPO_ROOT" diff --numstat $SCOPE_SPEC -- "$LIB_REL" 2>/dev/null || true)"
    LIB_STAT="${LIB_RAW:-(空)}"
    read -r LIB_ADDED LIB_DELETED <<<"$(numstat_of "$SCOPE_SPEC" "$LIB_REL")"
    read -r SETUP_ADDED SETUP_DELETED <<<"$(numstat_of "$SCOPE_SPEC" "$SETUP_REL")"
    if [[ "$SETUP_ADDED" -eq 1 && "$SETUP_DELETED" -eq 1 ]]; then
        SETUP_OK=1
    fi
    # C5 白名单闭集：scripts/ 下仅允许 stop-hook.sh（1 行 PROMPT）与 setup.sh（1 行 PHASE_FLOW）
    if [[ -n "$SCRIPTS_CHANGED" ]]; then
        while IFS= read -r changed; do
            [[ -z "$changed" ]] && continue
            case "$changed" in
                "$SETUP_REL" | "$STOP_HOOK_REL") ;;
                *)
                    WHITELIST_VIOLATION_N=$((WHITELIST_VIOLATION_N + 1))
                    WHITELIST_VIOLATION="${WHITELIST_VIOLATION}${changed} "
                    ;;
            esac
        done <<<"$SCRIPTS_CHANGED"
    fi
fi

N_SCRIPTS_CHANGED=0
if [[ -n "$SCRIPTS_CHANGED" ]]; then
    N_SCRIPTS_CHANGED=$(printf '%s\n' "$SCRIPTS_CHANGED" | grep -c . || true)
fi

write_art "场景7.P3.out" "diff 基线 spec = ${SCOPE_SPEC:-(无)}  [钉死：${CHANGE_PIN_DESC}]
scripts/ 下变更文件（C5 白名单 = {${STOP_HOOK_REL} 1 行 PROMPT, ${SETUP_REL} 1 行 PHASE_FLOW}）:
${SCRIPTS_CHANGED:-(空)}
白名单外变更 = ${WHITELIST_VIOLATION_N} 个 ${WHITELIST_VIOLATION:-(无)}
lib.sh numstat = ${LIB_STAT}  → added=${LIB_ADDED} deleted=${LIB_DELETED} (期望 0 / 0)
setup.sh numstat = added=${SETUP_ADDED} deleted=${SETUP_DELETED} (期望 1 / 1，diff 行数 <= 2)
C5：lib.sh 逐字节不变；scripts/ 另仅允许 setup.sh 的 PHASE_FLOW 横幅 1 行
CONTRACT_AMBIGUOUS：场景7.P3「仅 setup.sh」与 C5/场景7.P1（stop-hook.sh 必改 1 行）字面互斥，本测试按 C5 白名单闭集实现"

[[ -n "$SCOPE_SPEC" ]] || fails "场景7.P3: 钉死区间取不到 scripts/ 变更基线（${CHANGE_PIN_DESC}）"
[[ "$LIB_ADDED" -eq 0 && "$LIB_DELETED" -eq 0 ]] || fails "场景7.P3(C5): lib.sh 被改动（added=${LIB_ADDED} deleted=${LIB_DELETED}，应 0/0 逐字节不变）"
[[ "$N_SCRIPTS_CHANGED" -ge 1 ]] || fails "场景7.P3(C5): scripts/ 下无任何变更（预期至少 setup.sh 的 PHASE_FLOW 1 行）"
[[ "$WHITELIST_VIOLATION_N" -eq 0 ]] || fails "场景7.P3(C5): scripts/ 白名单外仍有变更 x${WHITELIST_VIOLATION_N}（${WHITELIST_VIOLATION}）"
[[ "$SETUP_ADDED" -le 1 && "$SETUP_DELETED" -le 1 && $((SETUP_ADDED + SETUP_DELETED)) -le 2 ]] || fails "场景7.P3(C5): setup.sh diff 行数 $((SETUP_ADDED + SETUP_DELETED)) > 2（应 1 增 1 删）"
[[ "$SETUP_OK" -eq 1 ]] || fails "场景7.P3(C5): setup.sh 未按 C5 白名单改动（实际 added=${SETUP_ADDED} deleted=${SETUP_DELETED}，期望 1/1：PHASE_FLOW 横幅文案）"
if [[ -n "$SCOPE_SPEC" && "$LIB_ADDED" -eq 0 && "$LIB_DELETED" -eq 0 && "$N_SCRIPTS_CHANGED" -ge 1 \
    && "$WHITELIST_VIOLATION_N" -eq 0 && "$SETUP_OK" -eq 1 ]]; then
    pass "场景7.P3: lib.sh 0/0 未变 + scripts/ 变更 ⊆ C5 白名单（setup.sh 1/1；stop-hook.sh 1 行由场景7.P1 独立约束）"
fi

# ═══════════════════════════════════════════════════════════════════════════
# 汇总
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "=========================================="
echo " R_STEP4_MECH 汇总: PASS=${PASS_N}  FAIL=${FAIL_N}"
echo "=========================================="
echo "覆盖谓词: 场景3.P1/6.P1/7.P1/7.P3"

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
