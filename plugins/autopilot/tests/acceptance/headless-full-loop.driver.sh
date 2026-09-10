#!/usr/bin/env bash
# headless-full-loop.driver.sh —— 场景 1.P2 / 1.P3 驱动器
# headless 档位下全流程确定性闭环冒烟：design 交互点确定性处置（行为矩阵）→
# stop-hook block 续跑走查（implement → qa(§5.5 达标) → merge → done）→ 终态。
#
# 降级口径（QA 预算约束，设计实现计划步骤 8）：合成 payload 状态机走查 + grep 代理断言，
# 不驱动真实 AI 会话；编排器语义活按行为矩阵做确定性模拟，每个决策点以 SKILL.md 指针 +
# 指令关键字的存在性为证据（缺失 → 记 ASK AskUserQuestion，由主套件 negate 断言挂掉）。
#
# 隔离契约：全程在 mktemp -d 沙盒执行 setup.sh / stop-hook（PROJECT_ROOT 解析为沙盒），
# 绝不触碰仓库真实 .autopilot/runtime/active.ptr。
# 产物：/tmp/autopilot-artifacts/场景1.P2.out（驱动日志 + state dump，1.P3 fs-grep 消费）
# 退出码：0=走查完成；3=前置失效（headless 未发射等）；4=协议走查停摆（无 block JSON）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_find_repo_root() {
    local d="$SCRIPT_DIR"
    while [[ -n "$d" && "$d" != "/" ]]; do
        [[ -f "$d/.claude-plugin/marketplace.json" ]] && { echo "$d"; return 0; }
        d=$(dirname "$d")
    done
    return 1
}
REPO_ROOT="$(_find_repo_root)" || { echo "[driver] 无法定位 REPO_ROOT" >&2; exit 3; }
SETUP_SH="$REPO_ROOT/plugins/autopilot/scripts/setup.sh"
STOP_HOOK="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"
SKILL_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/SKILL.md"
PROTOCOL_MD="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/headless-protocol.md"
[[ -f "$SETUP_SH" && -f "$STOP_HOOK" ]] || { echo "[driver] setup.sh/stop-hook.sh 缺失" >&2; exit 3; }

ART_DIR="/tmp/autopilot-artifacts"
mkdir -p "$ART_DIR"
ART="$ART_DIR/场景1.P2.out"
rm -f "$ART"
log() { printf '%s\n' "$*" >> "$ART"; }

SBX="$(mktemp -d -t autopilot-hl-loop.XXXXXX)" || exit 3
trap 'rm -rf "$SBX"' EXIT

# 模拟宿主 harness 的 CLAUDE_CODE_SESSION_ID 泄漏（uuid 形态，非 sess_ 前缀）。
# headless 契约：setup.sh --headless 必须将 state session_id 写空（Guard 1 首轮认领），
# 否则本走查首轮 stop-hook 即被 Guard 2 静默放行 → WALK-STALL → 主套件 1.P2 挂掉。
HOST_LEAK_SESSION_ID="a07d6b51-ecc8-4c7f-9f3a-3f62526527ca"
HOOK_SESSION="sess-fullloop-$$_$RANDOM"

# frontmatter 内 upsert（POSIX awk）
state_set_fm() {
    local f="$1" key="$2" val="$3"
    awk -v key="$key" -v val="$val" '
        n == 0 && /^---[[:space:]]*$/ { n = 1; print; next }
        n == 1 {
            if ($0 ~ "^" key ":") { print key ": " val; done = 1; next }
            if ($0 ~ "^---[[:space:]]*$") { if (!done) print key ": " val; print; n = 2; next }
            print; next
        }
        { print }
    ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

skill_win_has() {
    local line="$1" pat="$2" from to
    from=$((line - 3)); [[ $from -lt 1 ]] && from=1
    to=$((line + 3))
    sed -n "${from},${to}p" "$SKILL_FILE" 2>/dev/null | grep -qiE "$pat"
}
proto_has() { [[ -f "$PROTOCOL_MD" ]] && grep -qiE "$1" "$PROTOCOL_MD"; }

# 决策点协议：deterministic → 记 RESOLUTION（不含挂起标记词）；指令缺失 → 记 ASK（主套件 negate 挂掉）
resolve_point() { # <label> <skill_line> <directive_ERE>
    local label="$1" line="$2" rx="$3"
    if skill_win_has "$line" 'headless' && { skill_win_has "$line" "$rx" || proto_has "$rx"; }; then
        log "RESOLUTION $label deterministic (no-ask) evidence=skill:$line+protocol"
        return 0
    fi
    log "ASK AskUserQuestion at $label (headless 指针/指令缺失 skill:$line)"
    return 1
}

# 1) headless 初始化（带泄漏 env —— 见文件头说明）
out="$( cd "$SBX" && export CLAUDE_CODE_SESSION_ID="$HOST_LEAK_SESSION_ID" \
        && bash "$SETUP_SH" --headless "为工程补齐 README 的安装一节" 2>&1 )"
rc=$?
log "SETUP_RC=$rc"
[[ "$rc" -eq 0 ]] || { log "PRECONDITION-FAIL setup rc=$rc"; printf '%s\n' "$out" >> "$ART"; exit 3; }

STATE="$SBX/.autopilot/runtime/requirements/$(cat "$SBX/.autopilot/runtime/active.ptr" 2>/dev/null | tr -d '[:space:]')/state.md"
[[ -f "$STATE" ]] || { log "PRECONDITION-FAIL state.md 缺失"; exit 3; }
grep -q '^headless: true' "$STATE" || { log "PRECONDITION-FAIL headless 字段未发射"; exit 3; }
grep -qE '^session_id:[[:space:]]*"?$' "$STATE" || { log "PRECONDITION-FAIL headless 未清空 session_id（Guard 1 无法认领，泄漏陷阱复现）"; exit 3; }
log "HEADLESS_FIELD=hit SESSION_BLANKED=yes"

# 2) design 阶段交互点确定性处置（行为矩阵；语义活按矩阵模拟，证据=指针+指令存在性）
resolve_point "complexity-split(step1)"  85  '单任务'
resolve_point "brainstorm-delegation"    58  '自答|自行回答|推演关键问题'
resolve_point "guardrail-step4"          127 '预授权'
# 模拟编排器落盘：设计文档 + 步骤 4 同轮 auto_approve=true + phase=implement（§7.6 行：停等不触发）
printf '\n## 设计文档\nheadless 冒烟设计文档（确定性处置假设：单任务模式）\n\n## 实现计划\n冒烟实现计划\n' >> "$STATE"
state_set_fm "$STATE" auto_approve "true"
state_set_fm "$STATE" phase '"implement"'

# 3) stop-hook block 续跑走查
call_hook() { # <step-label> → stdout 落日志；要求协议应答时置 $2=expect-block
    local step="$1" expect="${2:-}"
    local tmpo tmpe o rc
    tmpo="$(mktemp -t hlc.XXXXXX)"; tmpe="$(mktemp -t hlc.XXXXXX)"
    ( cd "$SBX" && unset CLAUDE_CODE_SESSION_ID \
      && printf '{"session_id":"%s","transcript_path":"/tmp/none"}' "$HOOK_SESSION" | bash "$STOP_HOOK" ) >"$tmpo" 2>"$tmpe"
    rc=$?
    log "--- hook.$step rc=$rc ---"
    cat "$tmpo" >> "$ART"
    o="$(cat "$tmpo")"; rm -f "$tmpo" "$tmpe"
    if [[ "$expect" == "expect-block" ]]; then
        printf '%s' "$o" | grep -q '"decision"' || { log "WALK-STALL at ${step}（期望 block JSON 协议应答，实际无 decision）rc=$rc"; exit 4; }
    fi
    return "$rc"
}

call_hook "implement" "expect-block"
state_set_fm "$STATE" e2e_status '"verified"'
state_set_fm "$STATE" leftover_critical '"0"'
state_set_fm "$STATE" unexecuted_core_paths '"0"'
state_set_fm "$STATE" tier5_status '"na"'
state_set_fm "$STATE" gate '"review-accept"'
state_set_fm "$STATE" phase '"qa"'

call_hook "qa-gate-met" "expect-block"
# §5.5 达标应机械自动清 gate 进 merge（行为矩阵：§5.5 行不变）；未推进则编排器按流程自推进
if grep -qE '^phase:[[:space:]]*"merge"' "$STATE"; then
    log "AUTO_MERGE_FIRED=yes"
else
    log "AUTO_MERGE_FIRED=no-driver-advanced"
    state_set_fm "$STATE" gate '""'
    state_set_fm "$STATE" phase '"merge"'
fi

# merge 阶段：知识提取后设 phase=done（既有流程，行为不变）
state_set_fm "$STATE" knowledge_extracted '"true"'
state_set_fm "$STATE" phase '"done"'
call_hook "done"   # 终态释放：单任务清理 + 静默放行（不要求 JSON）

# 4) 终态与产物
log "--- state.dump.begin ---"
cat "$STATE" >> "$ART"
log "--- state.dump.end ---"
if [[ -f "$SBX/.autopilot/runtime/active.ptr" ]]; then
    log "ACTIVE_PTR_PRESENT=yes"
else
    log "ACTIVE_PTR_PRESENT=no"
fi
log "FINAL_PHASE=$(grep -E '^phase:' "$STATE" | head -1 | sed -E 's/^phase:[[:space:]]*"?([^"]*)"?$/\1/')"
log "DRIVER-WALK-COMPLETE"
exit 0
