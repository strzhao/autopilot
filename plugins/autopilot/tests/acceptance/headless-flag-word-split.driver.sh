#!/usr/bin/env bash
# headless-flag-word-split.driver.sh —— 场景 3.P4 驱动器
# 复现 live specimen 形态：目标未加引号 → shell 分词后以多 argv token 调 setup.sh。
# 契约（C2）：文本中的 --fast/--standard 字面量不被识别为档位 flag（档位字段为空），
# 且目标文本逐字保留（两字面量都在，长度与输入一致）。
#
# 隔离契约：mktemp -d 沙盒内真实执行 setup.sh，绝不触碰仓库真实 active.ptr。
# 产物：/tmp/autopilot-artifacts/场景3.P4.out（主套件断言消费的证据行）
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
[[ -f "$SETUP_SH" ]] || { echo "[driver] setup.sh 缺失" >&2; exit 3; }

ART_DIR="/tmp/autopilot-artifacts"
mkdir -p "$ART_DIR"
ART="$ART_DIR/场景3.P4.out"
rm -f "$ART"

SBX="$(mktemp -d -t autopilot-hl-ws.XXXXXX)" || exit 3
trap 'rm -rf "$SBX"' EXIT

# 未加引号的多 argv token 形态（6 个独立 token——用户 shell 分词后的等价形态）
TOKENS=(策略：先按 --fast 跑一轮，再用 --standard 复核)
INPUT_BYTES="$(printf '%s' "${TOKENS[*]}" | wc -c | tr -d ' ')"

out="$( cd "$SBX" && unset CLAUDE_CODE_SESSION_ID && bash "$SETUP_SH" "${TOKENS[@]}" 2>&1 )"
rc=$?
echo "SETUP_RC=$rc" >> "$ART"
[[ "$rc" -eq 0 ]] || { printf '%s\n' "$out" >> "$ART"; echo "DRIVER-FAIL setup rc=$rc" >> "$ART"; exit 0; }

slug="$(cat "$SBX/.autopilot/runtime/active.ptr" 2>/dev/null | head -1 | tr -d '[:space:]')"
STATE="$SBX/.autopilot/runtime/requirements/$slug/state.md"
[[ -f "$STATE" ]] || { echo "DRIVER-FAIL state.md 缺失" >> "$ART"; exit 0; }

# 档位字段原值（去引号；空档位=基线发射形态 `fast_mode: ` 或 `fast_mode: ""`）
fast_raw="$(grep -E '^fast_mode:' "$STATE" | head -1 | sed -E 's/^fast_mode:[[:space:]]*//')"
fast_val="$(printf '%s' "$fast_raw" | sed -E 's/^"([^"]*)"$/\1/')"
echo "FAST_MODE_VALUE=$fast_val" >> "$ART"

goal="$(awk '/^## 目标/{f=1;next} f&&NF{print;exit}' "$STATE")"
GOAL_BYTES="$(printf '%s' "$goal" | wc -c | tr -d ' ')"
if printf '%s' "$goal" | grep -qF -- '--fast'; then echo "GOAL_HAS_FAST=yes" >> "$ART"; else echo "GOAL_HAS_FAST=no" >> "$ART"; fi
if printf '%s' "$goal" | grep -qF -- '--standard'; then echo "GOAL_HAS_STANDARD=yes" >> "$ART"; else echo "GOAL_HAS_STANDARD=no" >> "$ART"; fi
if [[ "$GOAL_BYTES" -eq "$INPUT_BYTES" ]]; then echo "GOAL_BYTES_MATCH=yes" >> "$ART"; else echo "GOAL_BYTES_MATCH=no ($GOAL_BYTES != $INPUT_BYTES)" >> "$ART"; fi
echo "STATE_GOAL=$goal" >> "$ART"
echo "DRIVER-COMPLETE" >> "$ART"
exit 0
