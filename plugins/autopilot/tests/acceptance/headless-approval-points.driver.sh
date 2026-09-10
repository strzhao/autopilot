#!/usr/bin/env bash
# headless-approval-points.driver.sh —— 场景 2.P1 / 2.P2 / 2.P4 / 2.P5 驱动器
# headless 任务中的四个 AskUserQuestion 交互点确定性处置走查：
#   2.P1 design 审批点（步骤 4 审批问）→ 不问、放行、留痕
#   2.P2 高风险 guardrail（5 类闭合标准任一：不可逆操作/删数据）→ 不问、放行、留痕
#   2.P4 design 步骤 1 复杂度分流（mode 空）→ 不问、按单任务继续 + 假设留痕
#   2.P5 SKILL.md:53 Auto-Approve/Fast 环节失败回退点 → 不问、显式失败出口留痕
#
# 降级口径：合成状态机走查 + grep 代理断言（证据 = SKILL.md 指针行 ±3 窗口 + headless
# 指令关键字，或 references/headless-protocol.md 行为矩阵行）；证据缺失 → 记 ASK
# AskUserQuestion（主套件 negate 断言挂掉），不写留痕。
#
# 隔离契约：headless 任务在 mktemp -d 沙盒内以真实 setup.sh --headless 创建，
# 绝不触碰仓库真实 .autopilot/runtime/active.ptr。
# 产物：/tmp/autopilot-artifacts/场景2.P1.out（design 审批点留痕，含时间戳）
#       /tmp/autopilot-artifacts/场景2.P2.out（guardrail 留痕）
#       /tmp/autopilot-artifacts/场景2.P4.out（复杂度分流驱动日志 + 留痕）
#       /tmp/autopilot-artifacts/场景2.P5.out（:53 回退驱动日志 + 留痕）
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
A1="$ART_DIR/场景2.P1.out"; A2="$ART_DIR/场景2.P2.out"
A4="$ART_DIR/场景2.P4.out"; A5="$ART_DIR/场景2.P5.out"
rm -f "$A1" "$A2" "$A4" "$A5"

SBX="$(mktemp -d -t autopilot-hl-ap.XXXXXX)" || exit 3
trap 'rm -rf "$SBX"' EXIT
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

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
resolved() { # <label> <skill_line> <directive_ERE>
    skill_win_has "$2" 'headless' && { skill_win_has "$2" "$3" || proto_has "$3"; }
}

# headless 任务 state（真实 setup.sh --headless；泄漏 env 模拟宿主，headless 须清空 session）
out="$( cd "$SBX" && export CLAUDE_CODE_SESSION_ID="a07d6b51-ecc8-4c7f-9f3a-3f62526527ca" \
        && bash "$SETUP_SH" --headless "为工程补齐 README 的安装一节" 2>&1 )"
rc=$?
[[ "$rc" -eq 0 ]] || { echo "[driver] headless 初始化失败 rc=$rc: $out" >&2; exit 3; }
STATE="$SBX/.autopilot/runtime/requirements/$(cat "$SBX/.autopilot/runtime/active.ptr" 2>/dev/null | tr -d '[:space:]')/state.md"
[[ -f "$STATE" ]] || { echo "[driver] state.md 缺失" >&2; exit 3; }

# ── 2.P4 复杂度分流（design 步骤 1，mode 为空）──
# CONTRACT_AMBIGUOUS: SKILL 替换行措辞未冻结；指令锚取行为矩阵单元格字面「单任务」
if resolved "complexity-split" 85 '单任务'; then
    {
        printf '[headless] design 步骤 1 复杂度分流 确定性处置：放行（不问），依据：单任务假设（项目/单任务分流问省略，按单任务继续）\n'
        printf 'POINT complexity-split resolution=deterministic (no-ask)\n'
        printf 'TIMESTAMP=%s\n' "$TS"
    } >> "$A4"
    state_set_fm "$STATE" mode '"single"'   # 分流假设落盘：按单任务继续
else
    printf 'ASK AskUserQuestion at complexity-split (headless 指针/指令缺失)\n' >> "$A4"
fi

# ── 2.P1 design 审批点（步骤 4 审批问）──
if resolved "design-approval-step4" 127 '预授权'; then
    {
        printf '[headless] design 步骤 4 审批点 确定性处置：放行，依据：headless 预授权放行（不发起询问，auto_approve 同轮照设）\n'
        printf 'POINT design-approval-step4 resolution=deterministic (no-ask)\n'
        printf 'TIMESTAMP=%s\n' "$TS"
    } > "$A1"
    state_set_fm "$STATE" auto_approve "true"
else
    printf 'ASK AskUserQuestion at design-approval-step4 (headless 指针/指令缺失)\n' > "$A1"
fi

# ── 2.P2 高风险 guardrail（5 类闭合标准之一：不可逆操作——删数据）──
if resolved "guardrail-step4" 127 '预授权'; then
    {
        printf '[headless] guardrail 触发（类别：不可逆操作——删数据） 确定性处置：放行，依据：guardrail 类别=不可逆操作，headless 预授权放行 + 变更日志留痕\n'
        printf 'POINT guardrail-step4 resolution=deterministic (no-ask)\n'
        printf 'TIMESTAMP=%s\n' "$TS"
    } > "$A2"
else
    printf 'ASK AskUserQuestion at guardrail-step4 (headless 指针/指令缺失)\n' > "$A2"
fi

# ── 2.P5 SKILL.md:53 Auto-Approve/Fast 环节失败回退点 ──
# 构造：Auto-Approve 环节失败（如 implement 蓝队环节失败回退判定点）
if resolved "stage-failure-53" 53 '显式失败'; then
    {
        printf '[headless] :53 环节失败回退（Auto-Approve 环节失败） 确定性处置：显式失败，依据：headless 下交互通道不可用，按显式失败出口处置（gate/systemMessage 可见）\n'
        printf 'POINT stage-failure-53 resolution=deterministic (no-ask) disposition=explicit-failure\n'
        printf 'TIMESTAMP=%s\n' "$TS"
    } > "$A5"
    printf '\n## 变更日志\n- [%s] [headless] :53 环节失败回退 确定性处置：显式失败，依据：headless 交互通道不可用\n' "$TS" >> "$STATE"
else
    printf 'ASK AskUserQuestion at stage-failure-53 (headless 指针/指令缺失)\n' > "$A5"
fi

printf '--- state.dump.begin ---\n%s\n--- state.dump.end ---\n' "$(cat "$STATE")" >> "$A4"
printf 'WALK-COMPLETE\n' >> "$A4"
printf 'WALK-COMPLETE\n' >> "$A5"
exit 0
