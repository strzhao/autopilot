#!/usr/bin/env bash
# interactive-parity.driver.sh —— 场景 7.P3 驱动器
# 交互模式（不传 headless flag）闭环冒烟：headless 专用自动放行留痕必须为 0（negate）。
# 同时校验交互模式 state 零 headless 字段（与主套件 7.P1 双保险）。
#
# 隔离契约：mktemp -d 沙盒内真实执行 setup.sh 与 stop-hook（合成 payload），
# 绝不触碰仓库真实 active.ptr。
# 产物：/tmp/autopilot-artifacts/场景7.P3.out（驱动日志 + 计数证据行）
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
[[ -f "$SETUP_SH" && -f "$STOP_HOOK" ]] || { echo "[driver] setup.sh/stop-hook.sh 缺失" >&2; exit 3; }

ART_DIR="/tmp/autopilot-artifacts"
mkdir -p "$ART_DIR"
ART="$ART_DIR/场景7.P3.out"
rm -f "$ART"
log() { printf '%s\n' "$*" >> "$ART"; }

SBX="$(mktemp -d -t autopilot-hl-ip.XXXXXX)" || exit 3
trap 'rm -rf "$SBX"' EXIT
HOOK_SESSION="sess-interactive-parity-$$_$RANDOM"

# 交互模式初始化（无 headless flag；清空泄漏 env 保证纯基线语义）
( cd "$SBX" && unset CLAUDE_CODE_SESSION_ID \
        && bash "$SETUP_SH" "为工程补齐 README 的安装一节" ) >/dev/null 2>&1
rc=$?
log "SETUP_RC=$rc"
[[ "$rc" -eq 0 ]] || { log "PRECONDITION-FAIL setup rc=$rc"; exit 3; }
STATE="$SBX/.autopilot/runtime/requirements/$(cat "$SBX/.autopilot/runtime/active.ptr" 2>/dev/null | tr -d '[:space:]')/state.md"
[[ -f "$STATE" ]] || { log "PRECONDITION-FAIL state.md 缺失"; exit 3; }

# 交互模式闭环冒烟：design 阶段一轮 stop-hook 合成 payload（协议应答走查，交互提问行为不受影响）
tmpo="$(mktemp -t hlip.XXXXXX)"
( cd "$SBX" && unset CLAUDE_CODE_SESSION_ID \
  && printf '{"session_id":"%s","transcript_path":"/tmp/none"}' "$HOOK_SESSION" | bash "$STOP_HOOK" ) >"$tmpo" 2>/dev/null
log "HOOK_RC=$?"
log "--- hook.stdout.begin ---"
cat "$tmpo" >> "$ART"
log "--- hook.stdout.end ---"
rm -f "$tmpo"

# headless 专用自动放行留痕计数（沙盒任务目录全量 + 本驱动日志）
TRACE_COUNT="$(grep -rF '[headless]' "$SBX/.autopilot" 2>/dev/null | wc -l | tr -d ' ')"
LOG_COUNT="$(grep -cF '[headless]' "$ART" 2>/dev/null || true)"
FIELD_COUNT="$(grep -c -E '^headless:' "$STATE" 2>/dev/null || true)"
TOTAL=$((TRACE_COUNT + LOG_COUNT))
log "HEADLESS_TRACE_COUNT=$TOTAL"
log "HEADLESS_FIELD_COUNT=$FIELD_COUNT"
log "--- state.dump.begin ---"
cat "$STATE" >> "$ART"
log "--- state.dump.end ---"
log "WALK-COMPLETE"
exit 0
