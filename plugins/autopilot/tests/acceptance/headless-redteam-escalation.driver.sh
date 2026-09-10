#!/usr/bin/env bash
# headless-redteam-escalation.driver.sh —— 场景 9.P1 / 9.P2 / 9.P3 驱动器
# 红队测试失败且证据链不闭合（U 类，本走查取 U2 谓词 SSOT 冲突）在 headless 下触发
# 升级判定点：不 AskUserQuestion、留痕 + 保守处置（不改红队测试，实现修复优先）、
# 记入 QA 报告遗留区，60s 预算内返回。
#
# 降级口径：合成状态机走查 + grep 代理断言（证据 = SKILL.md :348/:362 窗口 headless 指针 +
# 「保守处置」指令，或 references/headless-protocol.md 矩阵行）；证据缺失 → 记 ASK
# AskUserQuestion（主套件 negate/count 断言挂掉）且不写遗留条目。
#
# 隔离契约：mktemp -d 沙盒内真实 setup.sh --headless 建任务，绝不触碰仓库真实 active.ptr。
# 产物：/tmp/autopilot-artifacts/场景9.P1.out（驱动日志 + U_ID + 处置留痕 + qa-report dump + state dump）
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
ART="$ART_DIR/场景9.P1.out"
rm -f "$ART"
log() { printf '%s\n' "$*" >> "$ART"; }
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
U_ID="U2"   # 谓词 SSOT 冲突：断言与验收场景预注册谓词矛盾且证据链不闭合

SBX="$(mktemp -d -t autopilot-hl-rt.XXXXXX)" || exit 3
trap 'rm -rf "$SBX"' EXIT

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

# headless 任务（红队 U 类失败发生在此任务的 auto-fix 阶段）
( cd "$SBX" && export CLAUDE_CODE_SESSION_ID="a07d6b51-ecc8-4c7f-9f3a-3f62526527ca" \
        && bash "$SETUP_SH" --headless "为工程补齐 README 的安装一节" ) >/dev/null 2>&1
rc=$?
log "SETUP_RC=$rc"
[[ "$rc" -eq 0 ]] || { log "PRECONDITION-FAIL setup rc=$rc"; exit 3; }
TASK_DIR="$SBX/.autopilot/runtime/requirements/$(cat "$SBX/.autopilot/runtime/active.ptr" 2>/dev/null | tr -d '[:space:]')"
STATE="$TASK_DIR/state.md"
[[ -f "$STATE" ]] || { log "PRECONDITION-FAIL state.md 缺失"; exit 3; }
log "U_CLASS_FAILURE=$U_ID (谓词 SSOT 冲突，证据链不闭合) phase=auto-fix"

# 升级判定点：headless 下不 AskUserQuestion，保守处置
# CONTRACT_AMBIGUOUS: SKILL 替换行措辞未冻结；指令锚取行为矩阵单元格字面「保守处置」
if { skill_win_has 348 'headless' && skill_win_has 348 '保守处置'; } \
   || { skill_win_has 362 'headless' && skill_win_has 362 '保守处置'; } \
   || proto_has '保守处置'; then
    log "RESOLUTION redteam-u-escalation deterministic (no-ask) evidence=skill:348|362+protocol"
    log "[headless] 红队 $U_ID 升级判定 确定性处置：保守处置，依据：$U_ID 证据链不闭合，不改红队测试、实现修复优先，遗留记入 QA 报告"
    log "TIMESTAMP=$TS"
    # 变更日志留痕（C4 机械可 grep 锚）
    printf '\n## 变更日志\n- [%s] [headless] 红队 %s 升级判定 确定性处置：保守处置，依据：%s 证据链不闭合，不改红队测试实现修复优先\n' "$TS" "$U_ID" "$U_ID" >> "$STATE"
    # QA 报告遗留区条目（样板词「遗留」不满足断言——必须落具体 U 编号条目）
    cat > "$TASK_DIR/qa-report.md" <<EOF
# QA 报告（headless 冒烟）

### 遗留问题
- [$U_ID] 红队测试断言与验收场景预注册谓词疑似矛盾且证据链不闭合——headless 保守处置：不改红队测试，实现修复优先，遗留待人工复核

### 风险
- $U_ID 处置为保守路径，红队测试未被修改，判定权留给人
EOF
else
    log "ASK AskUserQuestion at redteam-u-escalation (headless 指针/指令缺失)"
fi

log "--- qa-report.begin ---"
[[ -f "$TASK_DIR/qa-report.md" ]] && cat "$TASK_DIR/qa-report.md" >> "$ART"
log "--- qa-report.end ---"
log "--- state.dump.begin ---"
cat "$STATE" >> "$ART"
log "--- state.dump.end ---"
log "WALK-COMPLETE"
exit 0
