#!/usr/bin/env bash
# headless-brainstorm-delegation.driver.sh —— 场景 4.P1 / 4.P2 驱动器
# headless 任务推进触发 brainstorm Q&A 委托（复用未命中）→ 不委托交互式 Q&A、
# 编排器自答（推演关键问题与假设写入 brainstorm.md 留痕）→ 60s 预算内返回不挂起。
#
# 降级口径：合成状态机走查 + grep 代理断言（证据 = SKILL.md :57-59 窗口 headless 指针 +
# 「自答」类指令，或 references/headless-protocol.md 行为矩阵行）；证据缺失 → 记 ASK
# AskUserQuestion（主套件 negate/count 断言挂掉）。
#
# 隔离契约：mktemp -d 沙盒内真实 setup.sh --headless 建任务，绝不触碰仓库真实 active.ptr。
# 产物：/tmp/autopilot-artifacts/场景4.P1.out（驱动日志 + brainstorm.md dump + 处置留痕）
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
SKILL_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/SKILL.md"
PROTOCOL_MD="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/headless-protocol.md"
[[ -f "$SETUP_SH" ]] || { echo "[driver] setup.sh 缺失" >&2; exit 3; }

ART_DIR="/tmp/autopilot-artifacts"
mkdir -p "$ART_DIR"
ART="$ART_DIR/场景4.P1.out"
rm -f "$ART"
log() { printf '%s\n' "$*" >> "$ART"; }
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

SBX="$(mktemp -d -t autopilot-hl-bd.XXXXXX)" || exit 3
trap 'rm -rf "$SBX"' EXIT

skill_win_has() {
    local line="$1" pat="$2" from to
    from=$((line - 3)); [[ $from -lt 1 ]] && from=1
    to=$((line + 3))
    sed -n "${from},${to}p" "$SKILL_FILE" 2>/dev/null | grep -qiE "$pat"
}
proto_has() { [[ -f "$PROTOCOL_MD" ]] && grep -qiE "$1" "$PROTOCOL_MD"; }

# headless 任务 + 复用未命中（沙盒全新，无任何 brainstorm.md 可复用 → 委托点必被触发）
( cd "$SBX" && export CLAUDE_CODE_SESSION_ID="a07d6b51-ecc8-4c7f-9f3a-3f62526527ca" \
        && bash "$SETUP_SH" --headless "为工程补齐 README 的安装一节" ) >/dev/null 2>&1
rc=$?
log "SETUP_RC=$rc"
[[ "$rc" -eq 0 ]] || { log "PRECONDITION-FAIL setup rc=$rc"; exit 3; }
TASK_DIR="$SBX/.autopilot/runtime/requirements/$(cat "$SBX/.autopilot/runtime/active.ptr" 2>/dev/null | tr -d '[:space:]')"
[[ -f "$TASK_DIR/state.md" ]] || { log "PRECONDITION-FAIL state.md 缺失"; exit 3; }

# 复用扫描（既有行为：扫描 requirements/*/brainstorm.md，无相关产物 → 委托点）
REUSE_HIT="$(find "$SBX/.autopilot/runtime/requirements" -name 'brainstorm.md' 2>/dev/null | head -1)"
log "BRAINSTORM_REUSE_HIT=$([[ -n "$REUSE_HIT" ]] && echo yes || echo no)"

if [[ -n "$REUSE_HIT" ]]; then
    # 复用命中即用（既有行为不变，行为矩阵 brainstorm 行左列）
    log "RESOLUTION brainstorm-delegation reuse-hit (existing behavior unchanged)"
else
    # CONTRACT_AMBIGUOUS: SKILL 替换行措辞未冻结；指令锚取行为矩阵单元格字面「自答/推演关键问题」
    if skill_win_has 58 'headless' && { skill_win_has 58 '自答|自行回答|推演关键问题' || proto_has '自答|自行回答|推演关键问题'; }; then
        log "RESOLUTION brainstorm-delegation deterministic (no-ask) evidence=skill:58+protocol"
        # 编排器自答：推演关键问题与假设写入 brainstorm.md 留痕（非交互 Q&A）
        cat > "$TASK_DIR/brainstorm.md" <<EOF
# brainstorm（headless 自答留痕）

## 探索的目的与约束
- 目标：为工程补齐 README 的安装一节
- headless 档位：Q&A 委托确定性化为编排器自答，不挂起等待用户应答

## 关键问题与假设（推演）
- 关键问题 1：安装方式（源码/插件市场）？假设：插件市场安装为主，README 补安装一节
- 关键问题 2：前置依赖版本？假设：以 plugin.json 与 marketplace.json 现状为准
EOF
        log "[headless] brainstorm 委托 确定性处置：放行（编排器自答），依据：复用未命中，推演关键问题与假设写入 brainstorm.md 留痕"
        log "TIMESTAMP=$TS"
    else
        log "ASK AskUserQuestion at brainstorm-delegation (headless 指针/指令缺失)"
        log "[headless-missing] brainstorm 委托未确定性化"
    fi
fi

log "--- brainstorm.dump.begin ---"
[[ -f "$TASK_DIR/brainstorm.md" ]] && cat "$TASK_DIR/brainstorm.md" >> "$ART"
log "--- brainstorm.dump.end ---"
log "WALK-COMPLETE"
exit 0
