#!/usr/bin/env bash
# KCTX_FAN: 知识库消费链路 context.md 四节→五节（相关历史知识）+ 红队读侧义务 + 版本 3.69.0 同步
# 红队测试 — 黑盒视角，基于设计契约（state.md ## 验收场景 SSOT + ## 契约规约）编写，
#            绝不读取蓝队改后的 SKILL.md / prompt 实际内容凑断言（TDD 红灯 + 信息隔离）。
#
# 变更背景：优化 autopilot 知识库消费链路——
#   ① context.md 契约从四节扩为五节（新增 `## 相关历史知识`，节名字面禁变体；无相关条目写字面 N/A），
#      写侧 = autopilot SKILL.md design 步骤 1
#   ② red-team-prompt.md 增加读侧消费义务（非 N/A 时用例设计必须显式避开所列历史模式），
#      「相关历史知识」与「避开」必须同一条款行
#   ③ blue-team-prompt.md 术语四节→五节
#   ④ 版本 3.67.0 → 3.69.0 四处同步（plugin.json / marketplace.json / 根 CLAUDE.md / plugins/autopilot/README.md 顶部 30 行）
#
# 谓词映射（状态文件 ## 验收场景 SSOT）：
#   场景1.P1  [det-machine]: SKILL.md 含「相关历史知识」>=1
#   场景1.P2  [det-machine]: SKILL.md 含「相关历史知识」且同行含「构建命令」的行数 >=1（五节契约行绑定）
#   场景1.P3  [det-machine]: blue-team-prompt.md 含「五节」>=1
#   场景2.P1  [det-machine]: red-team-prompt.md 含「相关历史知识」>=1
#   场景2.P2  [det-machine]: red-team-prompt.md 含「避开」>=1
#   场景2.P3  [det-machine]: red-team-prompt.md 同行含「相关历史知识」+「避开」的行数 >=1（条件与动作共行）
#   场景3.P1  [det-machine]: SKILL.md 同行含「相关历史知识」+「N/A」的行数 >=1（N/A 语义）
#   场景4.P1  [det-machine]: autopilot/SKILL.md git diff --numstat deleted >= added
#   场景4.P2  [det-machine]: autopilot-doctor/SKILL.md git diff --numstat deleted >= added（未触碰时 0>=0 成立）
#   场景5.P4  [det-machine]: 四文件各含「3.69.0」每处 >=1（README.md 限顶部 30 行，契约规约）
#
# QA 豁免说明（场景5.P1/P2/P3 不由本测试覆盖）：
#   场景5.P1（本测试文件存在于 run-all 收集）、P2（run-all.sh rc==0）、P3（stdout 含本测试 PASS）
#   属自包含递归断言——本测试文件断言「自己被 run-all 收集且全量通过」会引入
#   ① 自我引用（测试存在性依赖测试自身运行）② run-all 嵌套递归（run-all 内跑 run-all）。
#   故按预注册谓词约定由 QA 阶段对真实产物（tests/acceptance/ 落位文件 + run-all 实跑）求值，
#   本测试只覆盖场景 1-4 与场景 5.P4。
#
# 实现说明：
#   - after = 当前工作区文件；净非增（场景4）用 git diff --numstat HEAD，空则回退 HEAD~1
#     （蓝队先 commit 再进 QA 的时序兼容，与 skill-shrinkage-invariants 同构）
#   - 双重 grep 纪律：字面锚点（grep -F/-E 计数）+ 共行绑定（同一行双锚点）双层，
#     治单弱锚点（如只 grep「节」）假绿
#   - 共行绑定用 grep -E 双向（A.*B | B.*A），防条款行语序变化漏检

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# REPO_ROOT 自适应：从脚本目录向上找 plugins/autopilot/.claude-plugin/plugin.json
# （兼容暂存区 acceptance-staging/ 深层路径与目标位 tests/acceptance/ 两种落位）
REPO_ROOT=""
_probe_dir="$SCRIPT_DIR"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if [[ -f "$_probe_dir/plugins/autopilot/.claude-plugin/plugin.json" ]]; then
        REPO_ROOT="$_probe_dir"
        break
    fi
    _probe_dir="$(dirname "$_probe_dir")"
done
[[ -n "$REPO_ROOT" ]] || {
    echo "[FAIL] KCTX_FAN: 无法定位仓库根（向上 12 层未找到 plugins/autopilot/.claude-plugin/plugin.json）" >&2
    exit 1
}

# 目标文件（相对 REPO_ROOT）
AUTOPILOT_SKILL="plugins/autopilot/skills/autopilot/SKILL.md"
DOCTOR_SKILL="plugins/autopilot/skills/autopilot-doctor/SKILL.md"
RED_TEAM_PROMPT="plugins/autopilot/skills/autopilot/references/red-team-prompt.md"
BLUE_TEAM_PROMPT="plugins/autopilot/skills/autopilot/references/blue-team-prompt.md"
PLUGIN_JSON="plugins/autopilot/.claude-plugin/plugin.json"
MARKETPLACE_JSON=".claude-plugin/marketplace.json"
ROOT_CLAUDE_MD="CLAUDE.md"
AUTOPILOT_README="plugins/autopilot/README.md"

ARTIFACT_DIR="/tmp/autopilot-artifacts"
mkdir -p "$ARTIFACT_DIR"

fail() {
    echo "[FAIL] KCTX_FAN: $1" >&2
    exit 1
}

pass() {
    echo "[PASS] KCTX_FAN: $1"
}

# 前置：目标文件存在
for f in "$AUTOPILOT_SKILL" "$DOCTOR_SKILL" "$RED_TEAM_PROMPT" "$BLUE_TEAM_PROMPT" \
         "$PLUGIN_JSON" "$MARKETPLACE_JSON" "$ROOT_CLAUDE_MD" "$AUTOPILOT_README"; do
    [[ -f "$REPO_ROOT/$f" ]] || fail "目标文件不存在: $REPO_ROOT/$f（蓝队可能尚未改动/文件路径漂移）"
done

# 辅助：grep -cE 计数（grep 无匹配 stdout="0"+rc=1，n 已捕获 "0" 再 || n=0 单值归一）
count_lines() {
    local file="$1" pattern="$2" n
    n=$(grep -cE "$pattern" "$file" 2>/dev/null) || n=0
    echo "$n"
}

# 辅助：numstat 取某文件 added/deleted（diff HEAD 空→回退 HEAD~1；二进制 "-" 当 0）
numstat_stat() {
    local rel="$1" content line added deleted
    content=$(git -C "$REPO_ROOT" diff --numstat HEAD -- "$rel" 2>/dev/null || true)
    if [[ -z "$content" ]]; then
        content=$(git -C "$REPO_ROOT" diff --numstat HEAD~1 -- "$rel" 2>/dev/null || true)
    fi
    if [[ -z "$content" ]]; then
        echo "0 0"   # 未改动（HEAD 与 HEAD~1 均无 diff）= added=0/deleted=0，0>=0 成立
        return
    fi
    line=$(echo "$content" | grep -E "[[:space:]]${rel}$" | head -1)
    if [[ -z "$line" ]]; then
        echo "0 0"
        return
    fi
    added=$(echo "$line" | awk '{print $1}')
    deleted=$(echo "$line" | awk '{print $2}')
    [[ "$added" == "-" ]] && added=0
    [[ "$deleted" == "-" ]] && deleted=0
    echo "$added $deleted"
}

SKILL_PATH="$REPO_ROOT/$AUTOPILOT_SKILL"
RED_PATH="$REPO_ROOT/$RED_TEAM_PROMPT"
BLUE_PATH="$REPO_ROOT/$BLUE_TEAM_PROMPT"

# ===========================================================================
# 断言 1（场景1.P1）：autopilot SKILL.md 含「相关历史知识」字面锚点 >=1
#   节名字面禁变体（禁「历史教训」「相关知识」等变体），grep -F 语义由 -E 转义等价锁定
# ===========================================================================
SKILL_HIST=$(count_lines "$SKILL_PATH" '相关历史知识')
echo "  [scene1.P1] SKILL.md '相关历史知识' count=$SKILL_HIST" >> "$ARTIFACT_DIR/kctx-fan-anchors.out"
[[ "$SKILL_HIST" -ge 1 ]] || \
    fail "scene 1.P1: SKILL.md 缺「相关历史知识」字面锚点（count=$SKILL_HIST，节名字面禁变体）"
pass "scene 1.P1: SKILL.md 含「相关历史知识」(count=$SKILL_HIST >= 1)"

# ===========================================================================
# 断言 2（场景1.P2）：五节契约行绑定——「相关历史知识」与「构建命令」同行 >=1
#   双层：字面锚点（断言1）+ 共行绑定（本断言），治契约行拆行/散落多处
# ===========================================================================
SKILL_COLINE=$(count_lines "$SKILL_PATH" '相关历史知识.*构建命令|构建命令.*相关历史知识')
echo "  [scene1.P2] SKILL.md 共行(相关历史知识+构建命令) count=$SKILL_COLINE" >> "$ARTIFACT_DIR/kctx-fan-anchors.out"
[[ "$SKILL_COLINE" -ge 1 ]] || \
    fail "scene 1.P2: SKILL.md 无同行含「相关历史知识」+「构建命令」的契约行（count=$SKILL_COLINE，该节须绑定在 context.md 五节契约行内）"
pass "scene 1.P2: SKILL.md 五节契约行绑定（共行 count=$SKILL_COLINE >= 1）"

# ===========================================================================
# 断言 3（场景1.P3）：blue-team-prompt.md 术语四节→五节，「五节」>=1
# ===========================================================================
BLUE_FIVE=$(count_lines "$BLUE_PATH" '五节')
echo "  [scene1.P3] blue-team-prompt.md '五节' count=$BLUE_FIVE" >> "$ARTIFACT_DIR/kctx-fan-anchors.out"
[[ "$BLUE_FIVE" -ge 1 ]] || \
    fail "scene 1.P3: blue-team-prompt.md 缺「五节」措辞（count=$BLUE_FIVE，术语四节→五节未同步）"
pass "scene 1.P3: blue-team-prompt.md 含「五节」(count=$BLUE_FIVE >= 1)"

# ===========================================================================
# 断言 4（场景2.P1）：red-team-prompt.md 含「相关历史知识」>=1（读侧消费对象锚点）
# ===========================================================================
RED_HIST=$(count_lines "$RED_PATH" '相关历史知识')
echo "  [scene2.P1] red-team-prompt.md '相关历史知识' count=$RED_HIST" >> "$ARTIFACT_DIR/kctx-fan-anchors.out"
[[ "$RED_HIST" -ge 1 ]] || \
    fail "scene 2.P1: red-team-prompt.md 缺「相关历史知识」（count=$RED_HIST，读侧消费义务未接线）"
pass "scene 2.P1: red-team-prompt.md 含「相关历史知识」(count=$RED_HIST >= 1)"

# ===========================================================================
# 断言 5（场景2.P2）：red-team-prompt.md 含「避开」>=1（动作动词锚点）
# ===========================================================================
RED_AVOID=$(count_lines "$RED_PATH" '避开')
echo "  [scene2.P2] red-team-prompt.md '避开' count=$RED_AVOID" >> "$ARTIFACT_DIR/kctx-fan-anchors.out"
[[ "$RED_AVOID" -ge 1 ]] || \
    fail "scene 2.P2: red-team-prompt.md 缺「避开」（count=$RED_AVOID，用例设计规避动作缺失）"
pass "scene 2.P2: red-team-prompt.md 含「避开」(count=$RED_AVOID >= 1)"

# ===========================================================================
# 断言 6（场景2.P3）：条件与动作共行绑定——「相关历史知识」+「避开」同一条款行 >=1
#   契约要点：两者必须在同一条款行（拆两行 = 条件与动作脱钩，读侧义务失效）
# ===========================================================================
RED_COLINE=$(count_lines "$RED_PATH" '相关历史知识.*避开|避开.*相关历史知识')
echo "  [scene2.P3] red-team-prompt.md 共行(相关历史知识+避开) count=$RED_COLINE" >> "$ARTIFACT_DIR/kctx-fan-anchors.out"
[[ "$RED_COLINE" -ge 1 ]] || \
    fail "scene 2.P3: red-team-prompt.md 无同一条款行同时含「相关历史知识」+「避开」（count=$RED_COLINE，条件与动作必须共行）"
pass "scene 2.P3: red-team-prompt.md 条款行共行绑定（共行 count=$RED_COLINE >= 1）"

# ===========================================================================
# 断言 7（场景3.P1）：N/A 语义——SKILL.md 同行含「相关历史知识」+「N/A」>=1
#   无相关条目时写字面 N/A 的规约须与节名绑定出现（防只写节名不写 N/A 规约）
# ===========================================================================
SKILL_NA=$(count_lines "$SKILL_PATH" '相关历史知识.*N/A|N/A.*相关历史知识')
echo "  [scene3.P1] SKILL.md 共行(相关历史知识+N/A) count=$SKILL_NA" >> "$ARTIFACT_DIR/kctx-fan-anchors.out"
[[ "$SKILL_NA" -ge 1 ]] || \
    fail "scene 3.P1: SKILL.md 无同行含「相关历史知识」+「N/A」（count=$SKILL_NA，缺『无相关条目写 N/A』规约）"
pass "scene 3.P1: SKILL.md N/A 语义共行绑定（共行 count=$SKILL_NA >= 1）"

# ===========================================================================
# 断言 8（场景4.P1）：autopilot SKILL.md 净非增（numstat deleted >= added）
# ===========================================================================
SKILL_STATS=$(numstat_stat "$AUTOPILOT_SKILL")
SKILL_ADDED=${SKILL_STATS% *}
SKILL_DELETED=${SKILL_STATS#* }
echo "  [scene4.P1] autopilot/SKILL.md numstat added=$SKILL_ADDED deleted=$SKILL_DELETED" >> "$ARTIFACT_DIR/kctx-fan-numstat.out"
[[ "$SKILL_DELETED" -ge "$SKILL_ADDED" ]] || \
    fail "scene 4.P1: autopilot/SKILL.md 净增 (deleted=$SKILL_DELETED < added=$SKILL_ADDED，契约硬约束 deleted >= added)"
pass "scene 4.P1: autopilot/SKILL.md 净非增 (deleted=$SKILL_DELETED >= added=$SKILL_ADDED)"

# ===========================================================================
# 断言 9（场景4.P2）：doctor SKILL.md 净非增（未触碰时 added=deleted=0，0>=0 成立）
# ===========================================================================
DOCTOR_STATS=$(numstat_stat "$DOCTOR_SKILL")
DOCTOR_ADDED=${DOCTOR_STATS% *}
DOCTOR_DELETED=${DOCTOR_STATS#* }
echo "  [scene4.P2] doctor/SKILL.md numstat added=$DOCTOR_ADDED deleted=$DOCTOR_DELETED" >> "$ARTIFACT_DIR/kctx-fan-numstat.out"
[[ "$DOCTOR_DELETED" -ge "$DOCTOR_ADDED" ]] || \
    fail "scene 4.P2: doctor/SKILL.md 净增 (deleted=$DOCTOR_DELETED < added=$DOCTOR_ADDED，本任务不触 doctor，出现净增即越界)"
pass "scene 4.P2: doctor/SKILL.md 净非增 (deleted=$DOCTOR_DELETED >= added=$DOCTOR_ADDED)"

# ===========================================================================
# 断言 10（场景5.P4）：版本四处各含「3.69.0」每处 >=1
#   plugin.json / marketplace.json / 根 CLAUDE.md / README.md（顶部 30 行，契约规约）
# ===========================================================================
VER_PATTERN='3\.69\.0'
declare -a VER_FILES=("$PLUGIN_JSON" "$MARKETPLACE_JSON" "$ROOT_CLAUDE_MD" "$AUTOPILOT_README")
declare -a VER_LABELS=("plugin.json" "marketplace.json" "根 CLAUDE.md" "README.md(顶部30行)")

{
    echo "=== 版本 3.69.0 四处同步 grep ==="
} > "$ARTIFACT_DIR/kctx-fan-version.out"

for i in 0 1 2 3; do
    rel="${VER_FILES[$i]}"
    label="${VER_LABELS[$i]}"
    if [[ "$rel" == "$AUTOPILOT_README" ]]; then
        # README 限顶部 30 行（契约：README 顶部 30 行内版本号）
        n=$(head -30 "$REPO_ROOT/$rel" | grep -cE "$VER_PATTERN" 2>/dev/null) || n=0
    else
        n=$(grep -cE "$VER_PATTERN" "$REPO_ROOT/$rel" 2>/dev/null) || n=0
    fi
    echo "  [$label] count=$n" >> "$ARTIFACT_DIR/kctx-fan-version.out"
    [[ "$n" -ge 1 ]] || \
        fail "scene 5.P4: $label 缺「3.69.0」（count=$n，版本四处同步缺失）"
done
pass "scene 5.P4: 版本四处均含 3.69.0 (plugin.json / marketplace.json / CLAUDE.md / README.md 顶部30行)"

echo "[OK ] KCTX_FAN knowledge-context-fanout — 全部断言通过"
exit 0
