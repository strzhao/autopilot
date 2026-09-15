#!/usr/bin/env bash
# R_STEP4_REGION: design 步骤 4 自治默认 + 留痕 + 反向通道 + 例外 + 旧口径清零（场景1.P1/P2、2.P1、4.P1-P5、5.P1/P2）
# 红队验收测试 — 仅基于设计文档（state.md 的 ## 设计文档 契约规约 C1-C10 + ## 验收场景 SSOT）编写。
#            铁律：本文件断言「文本内容」，全部期望值字面量逐字取自谓词 assert/negate 与契约规约；
#            绝不读取蓝队改后的 SKILL.md / references/** / scripts/** 内容来凑断言（TDD 红灯）。
#
# 谓词映射（逐条 det-machine 谓词 → ≥1 硬断言，期望值字面量取自该谓词 assert/negate）：
#   场景1.P1 → A1.1 步骤 4 区间含 `auto_approve: true` ≥1 ∧ A1.2 含 `phase: "implement"` ≥1
#              ∧ A1.3 含 `同轮` ≥1；A1.4 negate `命任一即必须问` == 0 ∧ A1.5 negate `闭合 guardrail` == 0
#   场景1.P2 → A2.1 区间含 `[design-auto]` ≥1 ∧ A2.2 区间含 `## 变更日志` ≥1
#              ∧ A2.3 design-modes.md 含 `[design-auto]` ≥1 ∧ A2.4 design-modes.md 留痕格式块 ≥1
#   场景2.P1 → A3.1 同一行共现 `先看方案` ∧ `AskUserQuestion` 计数 ≥1 ∧ A3.2 含 `先给我审` 行 ≥1
#   场景4.P1 → A4.1 区间 negate 八元组（`不可逆操作`/`大半径`/`跨模块或>5文件`/`新抽象`/`外部副作用`/
#              `API契约`/`安全敏感`/`auth/权限/支付/密钥`）命中计数 == 0
#   场景4.P2 → A5.1 区间 negate 三字面（`命任一即必须问`/`闭合 guardrail`/`非开放提示`）命中计数 == 0
#   场景4.P3 → A6.1 四 references 文件 `据低风险判断` 计数 == 0 ∧ A6.2 `自治|例外征询` 计数 ≥ 4（每文件 ≥1）
#   场景4.P4 → A7.1 全仓六字面 negate 命中计数 == 0（作用域 plugins/ + CLAUDE.md + marketplace.json）
#   场景4.P5 → A8.1 html-review-guide.md 前 20 行含 `用户要求审阅`/`例外` ≥1
#              ∧ A8.2 前 20 行 negate `4b 默认`/`否则走 4b 默认` == 0
#   场景5.P1 → A9.1 同一行共现 `不可逆` ∧ `AskUserQuestion` ∧（`无证据门禁可兜底`|`必须由用户裁决的取舍`）计数 ≥1
#   场景5.P2 → A10.1 例外规则行切片 negate 八字面（`>5文件`/`跨模块`/`新抽象`/`API契约`/`auth`/`权限`/`支付`/`密钥`）== 0
#
# CONTRACT_AMBIGUOUS: ① 场景1.P2「留痕格式块」未冻结机械形态——本测试按「代码围栏内含 `[design-auto]`
#   或 `[design-auto]` 所在行含箭头/占位符（`→`/`<`）」判定，并提请补声明。
#   ② 场景4.P4「排除 README.md changelog 区」未冻结行级边界——本测试按「排除 README.md 全文」实现
#   （超集排除，宁弱不假红）：六字面在基线 d45e899 下于 plugins/ 内 README.md 零命中，故该排除不掩盖真实残留；
#   若需覆盖 README 非 changelog 区，请补声明。
#   ③ 场景5.P2「例外规则行切片」未冻结切片边界——本测试取步骤 4 区间内含 `不可逆`/`例外`/`AskUserQuestion`
#   的行之并集（≥ 场景5.P1 定位行，属超集强化）。
#
# artifact: /tmp/autopilot-artifacts/场景{1.P1,1.P2,2.P1,4.P1,4.P2,4.P3,4.P4,4.P5,5.P1,5.P2}.out

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
    echo "[FAIL] R_STEP4_REGION: 无法定位 REPO_ROOT（缺 .claude-plugin/marketplace.json）" >&2
    exit 1
}

SKILL_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/SKILL.md"
REF_DIR="$REPO_ROOT/plugins/autopilot/skills/autopilot/references"
DESIGN_MODES="$REF_DIR/design-modes.md"
STATE_GUIDE="$REF_DIR/state-file-guide.md"
AUTO_CHAIN="$REF_DIR/auto-chain-guide.md"
PROJECT_SKILL="$REPO_ROOT/plugins/autopilot/skills/autopilot-project/SKILL.md"
HTML_GUIDE="$REF_DIR/html-review-guide.md"

ART_DIR="${AUTOPILOT_ARTIFACT_DIR:-/tmp/autopilot-artifacts}"
ART_NESTED="$ART_DIR/design-step4"
mkdir -p "$ART_NESTED"

PASS_N=0
FAIL_N=0
FAIL_MSGS=()

pass() {
    echo "[PASS] R_STEP4_REGION: $1"
    PASS_N=$((PASS_N + 1))
}

fails() { # 记录失败但继续跑完其余谓词（保证每个谓词都产出 artifact）
    echo "[FAIL] R_STEP4_REGION: $1" >&2
    FAIL_N=$((FAIL_N + 1))
    FAIL_MSGS+=("$1")
}

# 写 artifact（保证非空：首行 header；并留命名空间副本，防与 headless 测试同名 artifact 互覆）
write_art() { # <文件名> <内容>
    local f="$ART_DIR/$1"
    {
        echo "# $1 — design-step4 autonomy evidence"
        printf '%s\n' "$2"
    } > "$f"
    cp "$f" "$ART_NESTED/$1" 2>/dev/null || true
}

count_in() { # <字面> <文本>  → 命中行数（grep -F，无匹配输出 0）
    local literal="$1" text="$2"
    printf '%s\n' "$text" | grep -cF -- "$literal" || true
}

[[ -f "$SKILL_FILE" ]] || {
    echo "[FAIL] R_STEP4_REGION: SKILL.md 不存在: $SKILL_FILE" >&2
    exit 1
}

extract_phase_design() {
    awk '
        /^## Phase: *design/ { in_p = 1 }
        in_p && /^## / && !/^## Phase: *design/ { in_p = 0 }
        in_p { print }
    ' "$1"
}

extract_step4_region() {
    awk '
        /^#### 步骤 4\./ { in_r = 1 }
        in_r && /^#### / && !/^#### 步骤 4\./ { in_r = 0 }
        in_r { print }
    '
}

PHASE_DESIGN="$(extract_phase_design "$SKILL_FILE")"
STEP4="$(printf '%s\n' "$PHASE_DESIGN" | extract_step4_region)"

if [[ -z "$PHASE_DESIGN" ]]; then
    echo "[FAIL] R_STEP4_REGION: 无法定位 '## Phase: design' 段（提取为空）" >&2
    exit 1
fi
if [[ -z "$STEP4" ]]; then
    echo "[FAIL] R_STEP4_REGION: 无法定位 '#### 步骤 4.' 区间（提取为空）" >&2
    exit 1
fi

echo "=========================================="
echo " R_STEP4_REGION 步骤 4 自治默认/留痕/例外 + 旧口径清零（场景1/2/4/5）"
echo "=========================================="

# ═══════════════════════════════════════════════════════════════════════════
# 场景1.P1：默认路径三要素齐备 + 闭合必问声明清零
# ═══════════════════════════════════════════════════════════════════════════
C_AUTO=$(count_in 'auto_approve: true' "$STEP4")
C_PHASE=$(count_in 'phase: "implement"' "$STEP4")
C_TONGLUN=$(count_in '同轮' "$STEP4")
N_MINGREN=$(count_in '命任一即必须问' "$STEP4")
N_CLOSED=$(count_in '闭合 guardrail' "$STEP4")

write_art "场景1.P1.out" "region_lines=$(printf '%s\n' "$STEP4" | grep -c . || true)
auto_approve: true = ${C_AUTO}
phase: \"implement\" = ${C_PHASE}
同轮 = ${C_TONGLUN}
命任一即必须问 = ${N_MINGREN} (negate 期望 0)
闭合 guardrail = ${N_CLOSED} (negate 期望 0)"

[[ "$C_AUTO" -ge 1 ]] || fails "场景1.P1: 步骤 4 区间不含 'auto_approve: true'（命中 ${C_AUTO} < 1）"
[[ "$C_PHASE" -ge 1 ]] || fails "场景1.P1: 步骤 4 区间不含 'phase: \"implement\"'（命中 ${C_PHASE} < 1）"
[[ "$C_TONGLUN" -ge 1 ]] || fails "场景1.P1: 步骤 4 区间不含 '同轮'（命中 ${C_TONGLUN} < 1）"
[[ "$N_MINGREN" -eq 0 ]] || fails "场景1.P1(negate): 步骤 4 区间仍含 '命任一即必须问' x${N_MINGREN}（应 == 0，闭合必问声明未清除）"
[[ "$N_CLOSED" -eq 0 ]] || fails "场景1.P1(negate): 步骤 4 区间仍含 '闭合 guardrail' x${N_CLOSED}（应 == 0）"
[[ $((C_AUTO + C_PHASE + C_TONGLUN)) -ge 3 && "$N_MINGREN" -eq 0 && "$N_CLOSED" -eq 0 ]] &&
    pass "场景1.P1: 自治默认三要素齐备（auto_approve: true x${C_AUTO} / phase: \"implement\" x${C_PHASE} / 同轮 x${C_TONGLUN}）+ 闭合必问声明清零"

# ═══════════════════════════════════════════════════════════════════════════
# 场景1.P2：留痕锚点与落点齐备
# ═══════════════════════════════════════════════════════════════════════════
C_DESIGN_AUTO=$(count_in '[design-auto]' "$STEP4")
C_CHANGELOG=$(count_in '## 变更日志' "$STEP4")
DM_DESIGN_AUTO=0
DM_FORMAT_BLOCK=0
if [[ -f "$DESIGN_MODES" ]]; then
    DM_DESIGN_AUTO=$(count_in '[design-auto]' "$(cat "$DESIGN_MODES")")
    # 留痕格式块：代码围栏内含 `[design-auto]` 或 `[design-auto]` 行含箭头/占位符
    FENCE_HIT=$(awk '/^```/{f=!f; next} f && /\[design-auto\]/{print}' "$DESIGN_MODES" | grep -c . || true)
    ARROW_HIT=$(grep -F '[design-auto]' "$DESIGN_MODES" | grep -cE '→|<|…' || true)
    [[ "$FENCE_HIT" -ge 1 || "$ARROW_HIT" -ge 1 ]] && DM_FORMAT_BLOCK=1
fi

write_art "场景1.P2.out" "SKILL 步骤 4 区间 [design-auto] = ${C_DESIGN_AUTO}
SKILL 步骤 4 区间 ## 变更日志 = ${C_CHANGELOG}
design-modes.md [design-auto] = ${DM_DESIGN_AUTO}
design-modes.md 留痕格式块 = ${DM_FORMAT_BLOCK}"

[[ "$C_DESIGN_AUTO" -ge 1 ]] || fails "场景1.P2: 步骤 4 区间不含 '[design-auto]'（命中 ${C_DESIGN_AUTO} < 1）"
[[ "$C_CHANGELOG" -ge 1 ]] || fails "场景1.P2: 步骤 4 区间不含 '## 变更日志'（命中 ${C_CHANGELOG} < 1）"
[[ -f "$DESIGN_MODES" ]] || fails "场景1.P2: design-modes.md 不存在: $DESIGN_MODES"
[[ "$DM_DESIGN_AUTO" -ge 1 ]] || fails "场景1.P2: design-modes.md 不含 '[design-auto]'（命中 ${DM_DESIGN_AUTO} < 1）"
[[ "$DM_FORMAT_BLOCK" -eq 1 ]] || fails "场景1.P2: design-modes.md 无「留痕格式块」（代码围栏含 [design-auto] 或该行含 →/</… 均未命中）"
[[ "$C_DESIGN_AUTO" -ge 1 && "$C_CHANGELOG" -ge 1 && "$DM_DESIGN_AUTO" -ge 1 && "$DM_FORMAT_BLOCK" -eq 1 ]] &&
    pass "场景1.P2: 留痕锚点齐备（区间 [design-auto] x${C_DESIGN_AUTO} / ## 变更日志 x${C_CHANGELOG} / design-modes.md 锚点 x${DM_DESIGN_AUTO} + 格式块）"

# ═══════════════════════════════════════════════════════════════════════════
# 场景2.P1：用户反向通道（先看方案/先给我审）仍走 AskUserQuestion
# ═══════════════════════════════════════════════════════════════════════════
CO_SAME_LINE=$(printf '%s\n' "$STEP4" | grep -F '先看方案' | grep -cF 'AskUserQuestion' || true)
C_MY_AUDIT=$(count_in '先给我审' "$STEP4")

write_art "场景2.P1.out" "同行共现 先看方案 ∧ AskUserQuestion = ${CO_SAME_LINE}
含 先给我审 的行 = ${C_MY_AUDIT}"

[[ "$CO_SAME_LINE" -ge 1 ]] || fails "场景2.P1: 步骤 4 区间无同行共现 '先看方案' ∧ 'AskUserQuestion' 的规则行（计数 ${CO_SAME_LINE} < 1）"
[[ "$C_MY_AUDIT" -ge 1 ]] || fails "场景2.P1: 步骤 4 区间不含 '先给我审'（命中 ${C_MY_AUDIT} < 1）"
[[ "$CO_SAME_LINE" -ge 1 && "$C_MY_AUDIT" -ge 1 ]] &&
    pass "场景2.P1: 反向通道齐备（同行共现 x${CO_SAME_LINE} + 先给我审 x${C_MY_AUDIT}）"

# ═══════════════════════════════════════════════════════════════════════════
# 场景4.P1：五类高风险类别条目清零（区间 negate 八元组）
# ═══════════════════════════════════════════════════════════════════════════
N_CAT=$(printf '%s\n' "$STEP4" | grep -cF -e '不可逆操作' -e '大半径' -e '跨模块或>5文件' -e '新抽象' -e '外部副作用' -e 'API契约' -e '安全敏感' -e 'auth/权限/支付/密钥' || true)

write_art "场景4.P1.out" "步骤 4 区间 negate 八元组命中 = ${N_CAT} (期望 0)
negate: 不可逆操作 / 大半径 / 跨模块或>5文件 / 新抽象 / 外部副作用 / API契约 / 安全敏感 / auth/权限/支付/密钥"

[[ "$N_CAT" -eq 0 ]] || fails "场景4.P1(negate): 步骤 4 区间仍命中五类高风险类别 x${N_CAT}（应 == 0；防「只删部分类别」的 no-op 减法）"
[[ "$N_CAT" -eq 0 ]] && pass "场景4.P1: 五类高风险类别条目清零（negate 八元组命中 0）"

# ═══════════════════════════════════════════════════════════════════════════
# 场景4.P2：闭合必问声明清零（区间 negate 三字面）
# ═══════════════════════════════════════════════════════════════════════════
N_CLOSED3=$(printf '%s\n' "$STEP4" | grep -cF -e '命任一即必须问' -e '闭合 guardrail' -e '非开放提示' || true)

write_art "场景4.P2.out" "步骤 4 区间 negate 三字面命中 = ${N_CLOSED3} (期望 0)
negate: 命任一即必须问 / 闭合 guardrail / 非开放提示"

[[ "$N_CLOSED3" -eq 0 ]] || fails "场景4.P2(negate): 步骤 4 区间仍命中闭合必问声明 x${N_CLOSED3}（应 == 0）"
[[ "$N_CLOSED3" -eq 0 ]] && pass "场景4.P2: 闭合必问声明清零（negate 三字面命中 0）"

# ═══════════════════════════════════════════════════════════════════════════
# 场景4.P3：4 处 references 复述同步为自治口径
# ═══════════════════════════════════════════════════════════════════════════
REF4=("$DESIGN_MODES" "$STATE_GUIDE" "$AUTO_CHAIN" "$PROJECT_SKILL")
OLD_LOW_RISK=0
NEW_AUTONOMY=0
PER_FILE_REPORT=""
for f in "${REF4[@]}"; do
    if [[ ! -f "$f" ]]; then
        PER_FILE_REPORT="${PER_FILE_REPORT}$(basename "$f"): MISSING\n"
        continue
    fi
    o=$(count_in '据低风险判断' "$(cat "$f")")
    n=$(grep -cE '自治|例外征询' "$f" || true)
    OLD_LOW_RISK=$((OLD_LOW_RISK + o))
    NEW_AUTONOMY=$((NEW_AUTONOMY + n))
    PER_FILE_REPORT="${PER_FILE_REPORT}$(basename "$f"): 据低风险判断=${o} 自治|例外征询=${n}\n"
done

write_art "场景4.P3.out" "四 references 复述同步（design-modes.md / state-file-guide.md / auto-chain-guide.md / autopilot-project/SKILL.md）
据低风险判断 合计 = ${OLD_LOW_RISK} (期望 0)
自治|例外征询 合计 = ${NEW_AUTONOMY} (期望 >= 4)
--- 逐文件 ---
$(printf '%b' "$PER_FILE_REPORT")"

[[ "$OLD_LOW_RISK" -eq 0 ]] || fails "场景4.P3(negate): 四 references 仍含 '据低风险判断' x${OLD_LOW_RISK}（应 == 0，旧口径未同步）"
[[ "$NEW_AUTONOMY" -ge 4 ]] || fails "场景4.P3: 四 references '自治|例外征询' 计数 ${NEW_AUTONOMY} < 4（4 处复述未同步为自治口径）"
[[ "$OLD_LOW_RISK" -eq 0 && "$NEW_AUTONOMY" -ge 4 ]] &&
    pass "场景4.P3: 4 处 references 复述同步（据低风险判断 0 / 自治|例外征询 x${NEW_AUTONOMY}）"

# ═══════════════════════════════════════════════════════════════════════════
# 场景4.P4：全仓陈旧表述清零（覆盖 A7/A18/A19/A20/A21/B1/B5）
# ═══════════════════════════════════════════════════════════════════════════
SCOPE_LIST=("$REPO_ROOT/plugins" "$REPO_ROOT/CLAUDE.md" "$REPO_ROOT/.claude-plugin/marketplace.json")
REPO_WIDE_HITS=0
REPO_WIDE_DETAIL=""
for target in "${SCOPE_LIST[@]}"; do
    [[ -e "$target" ]] || continue
    h=$(grep -rnF \
        --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=tests \
        --exclude-dir=.autopilot --exclude-dir=codex --exclude=README.md \
        -e '步骤 4: AskUserQuestion 请求用户审批' \
        -e 'plan-reviewer Agent 审查 → AskUserQuestion 审批' \
        -e 'plan-reviewer → AskUserQuestion 审批' \
        -e 'design → 审批 → implement' \
        -e 'Q&A + AskUserQuestion 审批' \
        -e '| design | AskUserQuestion 审批 |' \
        "$target" 2>/dev/null | wc -l | tr -d ' ')
    REPO_WIDE_HITS=$((REPO_WIDE_HITS + h))
    if [[ "$h" -gt 0 ]]; then
        REPO_WIDE_DETAIL="${REPO_WIDE_DETAIL}$(grep -rnF \
            --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=tests \
            --exclude-dir=.autopilot --exclude-dir=codex --exclude=README.md \
            -e '步骤 4: AskUserQuestion 请求用户审批' \
            -e 'plan-reviewer Agent 审查 → AskUserQuestion 审批' \
            -e 'plan-reviewer → AskUserQuestion 审批' \
            -e 'design → 审批 → implement' \
            -e 'Q&A + AskUserQuestion 审批' \
            -e '| design | AskUserQuestion 审批 |' \
            "$target" 2>/dev/null | sed "s#${REPO_ROOT}/##")\n"
    fi
done

write_art "场景4.P4.out" "全仓六字面 negate 命中 = ${REPO_WIDE_HITS} (期望 0)
作用域: plugins/ + CLAUDE.md + .claude-plugin/marketplace.json
排除: tests/ · .autopilot/ · codex/ · .git · node_modules · README.md（见文件头 CONTRACT_AMBIGUOUS ②）
negate: 步骤 4: AskUserQuestion 请求用户审批 / plan-reviewer Agent 审查 → AskUserQuestion 审批 / plan-reviewer → AskUserQuestion 审批 / design → 审批 → implement / Q&A + AskUserQuestion 审批 / | design | AskUserQuestion 审批 |
--- 命中明细 ---
$(printf '%b' "$REPO_WIDE_DETAIL")"

[[ "$REPO_WIDE_HITS" -eq 0 ]] || fails "场景4.P4(negate): 全仓仍命中陈旧表述 x${REPO_WIDE_HITS}（应 == 0；明细见 artifact 场景4.P4.out）"
[[ "$REPO_WIDE_HITS" -eq 0 ]] && pass "场景4.P4: 全仓陈旧表述清零（六字面 negate 命中 0）"

# ═══════════════════════════════════════════════════════════════════════════
# 场景4.P5：html-review-guide.md 不再把 4b 声明为唯一默认路径（A18）
# ═══════════════════════════════════════════════════════════════════════════
HEAD20=""
if [[ -f "$HTML_GUIDE" ]]; then
    HEAD20="$(head -20 "$HTML_GUIDE")"
fi
H20_USER_REVIEW=$(printf '%s\n' "$HEAD20" | grep -cE '用户要求审阅|例外' || true)
H20_DEFAULT_4B=$(printf '%s\n' "$HEAD20" | grep -cF -e '4b 默认' -e '否则走 4b 默认' || true)

write_art "场景4.P5.out" "html-review-guide.md 前 20 行
用户要求审阅|例外 = ${H20_USER_REVIEW} (期望 >= 1)
4b 默认|否则走 4b 默认 = ${H20_DEFAULT_4B} (期望 0)"

[[ -f "$HTML_GUIDE" ]] || fails "场景4.P5: html-review-guide.md 不存在: $HTML_GUIDE"
[[ "$H20_USER_REVIEW" -ge 1 ]] || fails "场景4.P5: 前 20 行不含「用户要求审阅」或「例外」语义（命中 ${H20_USER_REVIEW} < 1）"
[[ "$H20_DEFAULT_4B" -eq 0 ]] || fails "场景4.P5(negate): 前 20 行仍含 4b 唯一默认表述 x${H20_DEFAULT_4B}（应 == 0）"
[[ "$H20_USER_REVIEW" -ge 1 && "$H20_DEFAULT_4B" -eq 0 ]] &&
    pass "场景4.P5: 4b 不再是唯一默认路径（用户要求审阅|例外 x${H20_USER_REVIEW}；4b 默认表述 0）"

# ═══════════════════════════════════════════════════════════════════════════
# 场景5.P1：例外判据为结论级且可触达（同一行共现）
# ═══════════════════════════════════════════════════════════════════════════
EXC_SAME_LINE=$(printf '%s\n' "$STEP4" | grep -F '不可逆' | grep -F 'AskUserQuestion' | grep -cE '无证据门禁可兜底|必须由用户裁决的取舍' || true)

write_art "场景5.P1.out" "同行共现 不可逆 ∧ AskUserQuestion ∧ (无证据门禁可兜底|必须由用户裁决的取舍) = ${EXC_SAME_LINE} (期望 >= 1)"

[[ "$EXC_SAME_LINE" -ge 1 ]] || fails "场景5.P1: 步骤 4 区间无同行共现「不可逆 ∧ AskUserQuestion ∧（无证据门禁可兜底|必须由用户裁决的取舍）」的例外规则行（计数 ${EXC_SAME_LINE} < 1）"
[[ "$EXC_SAME_LINE" -ge 1 ]] && pass "场景5.P1: 例外规则行可触达（同行三要素共现 x${EXC_SAME_LINE}）"

# ═══════════════════════════════════════════════════════════════════════════
# 场景5.P2：例外分支以结论级判据定义，非类别枚举（例外规则行切片 negate）
# ═══════════════════════════════════════════════════════════════════════════
EXC_SLICE="$(printf '%s\n' "$STEP4" | grep -E '不可逆|例外|AskUserQuestion' || true)"
N_ENUM=$(printf '%s\n' "$EXC_SLICE" | grep -cF -e '>5文件' -e '跨模块' -e '新抽象' -e 'API契约' -e 'auth' -e '权限' -e '支付' -e '密钥' || true)

write_art "场景5.P2.out" "例外规则行切片（含 不可逆|例外|AskUserQuestion 的行并集）行数 = $(printf '%s\n' "$EXC_SLICE" | grep -c . || true)
切片内 negate 八字面命中 = ${N_ENUM} (期望 0)
negate: >5文件 / 跨模块 / 新抽象 / API契约 / auth / 权限 / 支付 / 密钥"

[[ "$N_ENUM" -eq 0 ]] || fails "场景5.P2(negate): 例外规则行切片仍命中类别枚举字面 x${N_ENUM}（应 == 0；例外须为结论级判据）"
[[ "$N_ENUM" -eq 0 ]] && pass "场景5.P2: 例外分支为结论级判据（切片 negate 八字面命中 0）"

# ═══════════════════════════════════════════════════════════════════════════
# 汇总
# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo "=========================================="
echo " R_STEP4_REGION 汇总: PASS=${PASS_N}  FAIL=${FAIL_N}"
echo "=========================================="
echo "覆盖谓词: 场景1.P1/1.P2/2.P1/4.P1/4.P2/4.P3/4.P4/4.P5/5.P1/5.P2"

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
