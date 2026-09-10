#!/usr/bin/env bash
# headless-qa-gate.driver.sh —— 场景 5.P1 / 5.P2 / 5.P3 / 5.P4 驱动器
# headless 任务 qa 收口/gate 在分级未达标（e2e_status=unverified）下被触发：
#   5.P1 不进入等待用户应答的停等（60s 预算内返回）
#   5.P2 处置以显式记录收口（[headless] 留痕 + gate/分级字段可见）
#   5.P3 处置后 state 零等待应答标记
#   5.P4 C7：gate 保留 "review-accept" + phase 停在 "qa" + 零 merge commit 产物
#
# 机制面：真实执行 stop-hook（合成 payload，session 归属匹配），分级未达标 →
# §5.5 不自动推进 → gate 保留落 §6 放行链（systemMessage 分级未达标可见化）。
# 语义面（显式失败出口留痕）：按 headless 行为矩阵确定性处置，证据 = SKILL.md
# 优先级表/:53 窗口 headless 指针或 headless-protocol.md 矩阵行；缺失 → 记 ASK。
#
# 隔离契约：mktemp -d 沙盒 + 独立 git 仓（1 个初始 commit，用于检出「无 merge commit」），
# 绝不触碰仓库真实 active.ptr。
# 产物：/tmp/autopilot-artifacts/场景5.P1.out
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
STOP_HOOK="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"
SKILL_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/SKILL.md"
PROTOCOL_MD="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/headless-protocol.md"
[[ -f "$STOP_HOOK" ]] || { echo "[driver] stop-hook.sh 缺失" >&2; exit 3; }

ART_DIR="/tmp/autopilot-artifacts"
mkdir -p "$ART_DIR"
ART="$ART_DIR/场景5.P1.out"
rm -f "$ART"
log() { printf '%s\n' "$*" >> "$ART"; }
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

SBX="$(mktemp -d -t autopilot-hl-qg.XXXXXX)" || exit 3
trap 'rm -rf "$SBX"' EXIT

# 独立 git 仓：1 个初始 commit（merge 若发生必然新增 commit → 可机械检出）
git -C "$SBX" init -q 2>/dev/null
git -C "$SBX" -c user.name=redteam -c user.email=redteam@test commit -q --allow-empty -m init 2>/dev/null
BASE_COMMITS="$(git -C "$SBX" rev-list --count HEAD 2>/dev/null || echo 0)"
log "BASE_COMMIT_COUNT=$BASE_COMMITS"

TASK_DIR="$SBX/.autopilot/runtime/requirements/test-task"
mkdir -p "$TASK_DIR"
echo "test-task" > "$SBX/.autopilot/runtime/active.ptr"
# headless 任务，qa 阶段 gate=review-accept + auto_approve=true + 分级未达标（unverified）
cat > "$TASK_DIR/state.md" <<EOF
---
active: true
phase: "qa"
gate: "review-accept"
iteration: 3
max_iterations: 30
max_retries: 3
retry_count: 0
mode: "single"
plan_mode: ""
fast_mode: false
brief_file: ""
next_task: ""
auto_approve: true
headless: true
e2e_status: "unverified"
leftover_critical: "1"
unexecuted_core_paths: "0"
tier5_status: "na"
knowledge_extracted: ""
task_dir: "$TASK_DIR"
session_id: sess-qa-gate-fixture
started_at: "2026-09-10T00:00:00Z"
contract_required: true
html_review: false
---

## 目标
headless qa gate 分级未达标冒烟
EOF

# 真实执行 stop-hook（合成 payload，session 归属匹配 → 非 headless 侧行为，§5.5 消费分级字段）
tmpo="$(mktemp -t hlq.XXXXXX)"; tmpe="$(mktemp -t hlq.XXXXXX)"
( cd "$SBX" && unset CLAUDE_CODE_SESSION_ID \
  && printf '{"session_id":"sess-qa-gate-fixture","transcript_path":"/tmp/none"}' | bash "$STOP_HOOK" ) >"$tmpo" 2>"$tmpe"
HOOK_RC=$?
log "HOOK_RC=$HOOK_RC"
log "--- hook.stdout.begin ---"
cat "$tmpo" >> "$ART"
log "--- hook.stdout.end ---"
log "--- hook.stderr ---"
cat "$tmpe" >> "$ART"
rm -f "$tmpo" "$tmpe"

# 语义面：显式失败出口留痕（C4；证据 = SKILL 指针或 headless-protocol.md 矩阵行）
skill_win_has() {
    local line="$1" pat="$2" from to
    from=$((line - 3)); [[ $from -lt 1 ]] && from=1
    to=$((line + 3))
    sed -n "${from},${to}p" "$SKILL_FILE" 2>/dev/null | grep -qiE "$pat"
}
proto_has() { [[ -f "$PROTOCOL_MD" ]] && grep -qiE "$1" "$PROTOCOL_MD"; }
if skill_win_has 48 'headless' || proto_has '显式失败'; then
    log "[headless] qa gate 分级未达标 确定性处置：显式失败，依据：gate=review-accept 保留停等（e2e_status=unverified，不自动 merge），headless 下交显式失败出口"
    log "TIMESTAMP=$TS"
else
    log "ASK AskUserQuestion at qa-gate-unmet (headless 指针/指令缺失)"
fi

# 处置后 state + git 计数
log "--- state.dump.begin ---"
cat "$TASK_DIR/state.md" >> "$ART"
log "--- state.dump.end ---"
FINAL_COMMITS="$(git -C "$SBX" rev-list --count HEAD 2>/dev/null || echo 0)"
log "MERGE_COMMIT_COUNT=$FINAL_COMMITS"
log "WALK-COMPLETE"
exit 0
