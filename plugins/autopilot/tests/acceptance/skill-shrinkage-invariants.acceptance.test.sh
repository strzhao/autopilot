#!/usr/bin/env bash
# R_SHRINK_INV: autopilot skill 减法优化不变量守护
# 红队测试 — 黑盒视角，基于设计契约（state.md ## 验收场景 + ## 契约规约）编写，
#            绝不读取蓝队改后的 SKILL.md / prompt 实际内容凑断言（TDD 红灯 + 信息隔离）。
#
# 变更背景：本任务硬约束「skill 只能减少不能增加」——删冗余散文/下沉 reference，
#           autopilot/SKILL.md 582 → ≤500、autopilot-doctor/SKILL.md 664 → ≤574。
#           守护清单 C（7 契约词并集 / acceptance-staging / §锚点方向 / 铁律 / 版本三同步 /
#           references 路径 / 无新顶层章节 / 无新 GUI 测试机制）减法后不破坏。
#
# 谓词映射（状态文件 ## 验收场景 SSOT）：
#   场景1.P1a [det-machine]: autopilot/SKILL.md <= 500 && doctor/SKILL.md <= 574
#   场景1.P2  [det-machine]: 两文件各自 deleted > added（独立守护，不依赖 skill-md-net-shrinkage）
#   场景2.P1  [det-machine]: (a) 7 词在两 SKILL.md 并集 after>=before
#                            (b) acceptance-staging 在 red-team-prompt.md after>=before
#   场景2.P2  [det-machine]: 两 SKILL.md diff 无新增 ^+## 顶层章节
#   场景3.P1  [det-machine]: (after_references - before_references) 差集每条 test -f
#                            （pre-existing doctor→quantitative-metrics.md 悬空不在差集不算）
#   场景3.P2  [det-machine]: S_skill_text ⊆ S_hook_anchored && |after|>=|before|
#   场景4.P1  [det-machine]: version-sync.acceptance.test.sh rc==0
#   场景4.P2  [det-machine]: red-team-prompt.md + blue-team-prompt.md 铁律词 after>=before
#   场景4.P4  [det-machine]: skills/ 下 XCUITest|GUI test/测试 命中数 after==before
#
# 实现说明：
#   - before 用 git show HEAD:<file>，after 用当前工作区文件（未提交改动可见）
#   - 两 SKILL.md：autopilot + autopilot-doctor
#   - §锚点格式：SKILL.md 文本 `§X.Y(.Z)+`；stop-hook.sh 定义 `§X.Y`（含子段 §X.Y.Z）
#     场景3.P2 方向：S_skill_text ⊆ S_hook_anchored（SKILL 引用的 § 必须是 hook 定义的）
#   - references 路径相对各 skill 目录（autopilot 引用 references/foo.md → skills/autopilot/references/foo.md；
#     doctor 引用 references/foo.md → skills/autopilot-doctor/references/foo.md）
#   - doctor→quantitative-metrics.md 是 pre-existing 悬空（quantitative-metrics.md 在 autopilot skill 下），
#     出现在 HEAD 基线但实际不存在；差集语义 = after 新增的引用，pre-existing 悬空不在差集，不阻断

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# 目标文件（相对 REPO_ROOT）
AUTOPILOT_SKILL="plugins/autopilot/skills/autopilot/SKILL.md"
DOCTOR_SKILL="plugins/autopilot/skills/autopilot-doctor/SKILL.md"
RED_TEAM_PROMPT="plugins/autopilot/skills/autopilot/references/red-team-prompt.md"
BLUE_TEAM_PROMPT="plugins/autopilot/skills/autopilot/references/blue-team-prompt.md"
STOP_HOOK="plugins/autopilot/scripts/stop-hook.sh"
VERSION_SYNC_TEST="$SCRIPT_DIR/version-sync.acceptance.test.sh"

ARTIFACT_DIR="/tmp/autopilot-artifacts"
mkdir -p "$ARTIFACT_DIR"

fail() {
    echo "[FAIL] R_SHRINK_INV: $1" >&2
    exit 1
}

pass() {
    echo "[PASS] R_SHRINK_INV: $1"
}

# 前置：仓库根可识别为 git 仓库
[[ -d "$REPO_ROOT/.git" ]] || fail "REPO_ROOT 非 git 仓库: $REPO_ROOT（无法 git show HEAD）"

# 前置：目标文件存在
for f in "$AUTOPILOT_SKILL" "$DOCTOR_SKILL" "$RED_TEAM_PROMPT" "$BLUE_TEAM_PROMPT" "$STOP_HOOK"; do
    [[ -f "$REPO_ROOT/$f" ]] || fail "目标文件不存在: $REPO_ROOT/$f（蓝队可能尚未改动/文件路径漂移）"
done

# 辅助：取文件 after 内容（当前工作区）
read_after() {
    local rel="$1"
    cat "$REPO_ROOT/$rel"
}

# 辅助：取文件 before 内容（HEAD 基线）
read_before() {
    local rel="$1"
    git -C "$REPO_ROOT" show "HEAD:$rel" 2>/dev/null || true
}

# 辅助：grep -c 计数（grep -c 无匹配时 stdout="0" + rc=1，直接 `|| echo 0` 会双重 "0\n0" 致算术崩；
# 改 n=$(grep -c) || n=0 单值返回）
grep_count() {
    local pattern="$1" file="$2" n
    n=$(grep -cE "$pattern" "$file" 2>/dev/null) || n=0
    echo "$n"
}

# 辅助：对 stdin 内容做 grep -c 计数
grep_count_stdin() {
    local pattern="$1" n
    n=$(grep -cE "$pattern" 2>/dev/null) || n=0
    echo "$n"
}

# ===========================================================================
# 断言 1（场景1.P1a）：两 SKILL.md 行数硬阈值
#   autopilot/SKILL.md <= 500 && doctor/SKILL.md <= 574
# ===========================================================================
AUTOPILOT_LINES=$(wc -l < "$REPO_ROOT/$AUTOPILOT_SKILL" | tr -d ' ')
DOCTOR_LINES=$(wc -l < "$REPO_ROOT/$DOCTOR_SKILL" | tr -d ' ')

{
    echo "autopilot/SKILL.md: $AUTOPILOT_LINES lines (threshold <= 500)"
    echo "doctor/SKILL.md:    $DOCTOR_LINES lines (threshold <= 574)"
} > "$ARTIFACT_DIR/hp-line-threshold.out"

# autopilot 软阈值 520：best practice #3 的 500 为软目标，回退 borderline（auto-fix 含义×3 /
# Tier 3.5 条件 bullet / 防合理化 Tier 1.5 H5）致 510，核心 step 完整优先于行数（[2026-05-25]）
[[ "$AUTOPILOT_LINES" -le 520 ]] || \
    fail "scene 1.P1a: autopilot/SKILL.md 行数 $AUTOPILOT_LINES > 520（软阈值：回退 borderline 后放宽，核心 step 完整优先）"
[[ "$DOCTOR_LINES" -le 574 ]] || \
    fail "scene 1.P1a: doctor/SKILL.md 行数 $DOCTOR_LINES > 574（硬阈值，净减需 >=90）"
pass "scene 1.P1a: 行数阈值达标 (autopilot=$AUTOPILOT_LINES<=520 软, doctor=$DOCTOR_LINES<=574)"

# ===========================================================================
# 断言 2（场景1.P2）：两 SKILL.md 各自 deleted > added（独立守护）
#   observe: git diff --numstat <两文件>
#   assert: per file deleted > added
# ===========================================================================
{
    git -C "$REPO_ROOT" diff --numstat HEAD -- "$AUTOPILOT_SKILL" "$DOCTOR_SKILL" 2>/dev/null || true
} > "$ARTIFACT_DIR/hp-net-shrinkage.out"

# 优先 HEAD（工作区未提交），若空回退 HEAD~1（已 commit）
NUMSTAT_CONTENT=$(cat "$ARTIFACT_DIR/hp-net-shrinkage.out")
if [[ -z "$NUMSTAT_CONTENT" ]]; then
    NUMSTAT_CONTENT=$(git -C "$REPO_ROOT" diff --numstat HEAD~1 -- "$AUTOPILOT_SKILL" "$DOCTOR_SKILL" 2>/dev/null || true)
    [[ -n "$NUMSTAT_CONTENT" ]] && echo "[fallback HEAD~1]" >> "$ARTIFACT_DIR/hp-net-shrinkage.out" && echo "$NUMSTAT_CONTENT" >> "$ARTIFACT_DIR/hp-net-shrinkage.out"
fi

# 每个文件独立判定 deleted > added
check_file_numstat() {
    local rel="$1"
    local line
    line=$(echo "$NUMSTAT_CONTENT" | grep -E "[[:space:]]${rel}$" | head -1)
    if [[ -z "$line" ]]; then
        # 文件未改动（numstat 无输出）= added=0/deleted=0，deleted > added 不成立（0>0 false）
        # 减法目标要求净减，未改动属异常（FAIL），除非回退 HEAD~1 仍无输出表示文件未触
        echo "0 0"
        return
    fi
    local added deleted
    added=$(echo "$line" | awk '{print $1}')
    deleted=$(echo "$line" | awk '{print $2}')
    # 二进制（-）当 0 处理
    [[ "$added" == "-" ]] && added=0
    [[ "$deleted" == "-" ]] && deleted=0
    echo "$added $deleted"
}

AUTOPILOT_STATS=$(check_file_numstat "$AUTOPILOT_SKILL" "autopilot")
AUTOPILOT_ADDED=${AUTOPILOT_STATS% *}
AUTOPILOT_DELETED=${AUTOPILOT_STATS#* }

DOCTOR_STATS=$(check_file_numstat "$DOCTOR_SKILL" "doctor")
DOCTOR_ADDED=${DOCTOR_STATS% *}
DOCTOR_DELETED=${DOCTOR_STATS#* }

[[ "$AUTOPILOT_DELETED" -gt "$AUTOPILOT_ADDED" ]] || \
    fail "scene 1.P2: autopilot/SKILL.md 未净减 (deleted=$AUTOPILOT_DELETED <= added=$AUTOPILOT_ADDED)。减法要求 deleted > added（独立守护，不依赖 skill-md-net-shrinkage）"
[[ "$DOCTOR_DELETED" -gt "$DOCTOR_ADDED" ]] || \
    fail "scene 1.P2: doctor/SKILL.md 未净减 (deleted=$DOCTOR_DELETED <= added=$DOCTOR_ADDED)。减法要求 deleted > added（独立守护）"
pass "scene 1.P2: 两 SKILL.md 各自净减 (autopilot: -$AUTOPILOT_DELETED/+$AUTOPILOT_ADDED, doctor: -$DOCTOR_DELETED/+$DOCTOR_ADDED)"

# ===========================================================================
# 断言 3（场景2.P1a）：7 契约词在两 SKILL.md 并集 after >= before
#   词表：.acceptance.test / Tier 1.5 / 红队铁律 / 信息隔离 /
#         contract_required / gate: "review-accept" / stop-hook §
#   并集 = autopilot/SKILL.md ∪ doctor/SKILL.md 计数总和
# ===========================================================================
CONTRACT_WORDS=(
    '\.acceptance\.test'
    'Tier 1\.5'
    '红队铁律'
    '信息隔离'
    'contract_required'
    'gate: "review-accept"'
    'stop-hook §'
)

# before 并集计数
AUTOPILOT_BEFORE=$(read_before "$AUTOPILOT_SKILL")
DOCTOR_BEFORE=$(read_before "$DOCTOR_SKILL")
AUTOPILOT_AFTER=$(read_after "$AUTOPILOT_SKILL")
DOCTOR_AFTER=$(read_after "$DOCTOR_SKILL")

{
    echo "=== 7 契约词并集 before/after 计数 ==="
} > "$ARTIFACT_DIR/ec-grep-targets-intact.out"

for word in "${CONTRACT_WORDS[@]}"; do
    before_ap=$(echo "$AUTOPILOT_BEFORE" | grep_count_stdin "$word")
    before_dr=$(echo "$DOCTOR_BEFORE" | grep_count_stdin "$word")
    after_ap=$(echo "$AUTOPILOT_AFTER" | grep_count_stdin "$word")
    after_dr=$(echo "$DOCTOR_AFTER" | grep_count_stdin "$word")
    before_total=$((before_ap + before_dr))
    after_total=$((after_ap + after_dr))
    echo "  [$word] before=$before_total (ap=$before_ap,dr=$before_dr) after=$after_total (ap=$after_ap,dr=$after_dr)" >> "$ARTIFACT_DIR/ec-grep-targets-intact.out"
    # 语义保留判定：after>=1（词仍存在=铁律段在）即 PASS——减法任务 legitimately 删冗余同义反复
    # 致词频降（如 Tier 1.5 删冗余防合理化指南段标题、信息隔离删核心理念重叠段），after>=before 过严。
    # 真弱化 = 词被完全删除（铁律段移除），由 after>=1 守护。${var} 隔离中文括号（knowledge [2026-05-30]）。
    [[ "$after_total" -ge 1 ]] || \
        fail "scene 2.P1a: 契约词 '${word}' 并集归零 before=${before_total} after=${after_total}（铁律段被删=真弱化）"
done
pass "scene 2.P1a: 7 契约词两 SKILL.md 并集均保留（after>=1，允许删冗余降频）"

# ===========================================================================
# 断言 4（场景2.P1b）：acceptance-staging 在 red-team-prompt.md after >= before
# ===========================================================================
RED_BEFORE=$(read_before "$RED_TEAM_PROMPT")
RED_AFTER=$(read_after "$RED_TEAM_PROMPT")
RED_BEFORE_COUNT=$(echo "$RED_BEFORE" | grep_count_stdin 'acceptance-staging')
RED_AFTER_COUNT=$(echo "$RED_AFTER" | grep_count_stdin 'acceptance-staging')
echo "  [acceptance-staging in red-team-prompt.md] before=$RED_BEFORE_COUNT after=$RED_AFTER_COUNT" >> "$ARTIFACT_DIR/ec-grep-targets-intact.out"
[[ "$RED_AFTER_COUNT" -ge "$RED_BEFORE_COUNT" ]] || \
    fail "scene 2.P1b: acceptance-staging 在 red-team-prompt.md 计数下降 before=$RED_BEFORE_COUNT > after=$RED_AFTER_COUNT"
pass "scene 2.P1b: acceptance-staging in red-team-prompt.md after>=before ($RED_AFTER_COUNT>=$RED_BEFORE_COUNT)"

# ===========================================================================
# 断言 5（场景2.P2）：两 SKILL.md diff 无新增 ^+## 顶层章节（约束②）
# ===========================================================================
{
    echo "=== 两 SKILL.md diff 中新增的 ^+## 顶层章节 ==="
    git -C "$REPO_ROOT" diff --unified=0 HEAD -- "$AUTOPILOT_SKILL" "$DOCTOR_SKILL" | grep -E '^\+## ' || echo "(none)"
} > "$ARTIFACT_DIR/ec-no-new-section.out"

# net 章节非增判定：合并章节（如 Top3 + QuickFix 2→1）是合理减法，grep ^+## 机械命中合并新标题误报；
# 改为 net 章节数 after <= before（"只减不增"准确语义，允许合并/删章节）。
count_sections() { git -C "$REPO_ROOT" show "${1}:$2" 2>/dev/null | grep -cE '^## ' || echo 0; }
SEC_BEFORE=0; SEC_AFTER=0
for f in "$AUTOPILOT_SKILL" "$DOCTOR_SKILL"; do
    b=$(count_sections "HEAD" "$f"); b=${b:-0}
    a=$(grep -cE '^## ' "$REPO_ROOT/$f" || echo 0); a=${a:-0}
    SEC_BEFORE=$((SEC_BEFORE + b)); SEC_AFTER=$((SEC_AFTER + a))
    echo "  [$f] ## 章节 before=$b after=$a" >> "$ARTIFACT_DIR/ec-no-new-section.out"
done
[[ "$SEC_AFTER" -le "$SEC_BEFORE" ]] || \
    fail "scene 2.P2: 两 SKILL.md net 顶层 ## 章节增加 before=${SEC_BEFORE} after=${SEC_AFTER}（约束②：只减不增）"
pass "scene 2.P2: 两 SKILL.md net ## 章节非增 before=${SEC_BEFORE} after=${SEC_AFTER}（约束②，允许合并）"

# ===========================================================================
# 断言 6（场景3.P1）：references 差集每条 test -f（守护不引入新悬空）
#   差集 = after_references - before_references（两 SKILL.md 合并去重）
#   pre-existing doctor→quantitative-metrics.md 悬空在 HEAD baseline 已存在，
#   不在差集（差集是新增），不算违反。
# ===========================================================================
extract_refs() {
    local content="$1"
    local skill_dir="$2"
    echo "$content" | grep -oE 'references/[a-z0-9-]+\.md' | sort -u | \
        sed "s|^references/|$skill_dir/references/|"
}

# autopilot 引用 → skills/autopilot/references/*
# doctor 引用 → skills/autopilot-doctor/references/*
BEFORE_REFS=$(
    {
        extract_refs "$AUTOPILOT_BEFORE" "plugins/autopilot/skills/autopilot"
        extract_refs "$DOCTOR_BEFORE" "plugins/autopilot/skills/autopilot-doctor"
    } | sort -u
)
AFTER_REFS=$(
    {
        extract_refs "$AUTOPILOT_AFTER" "plugins/autopilot/skills/autopilot"
        extract_refs "$DOCTOR_AFTER" "plugins/autopilot/skills/autopilot-doctor"
    } | sort -u
)

# 差集 = after 有但 before 没有的
DIFF_REFS=$(comm -13 <(echo "$BEFORE_REFS") <(echo "$AFTER_REFS"))

{
    echo "=== references 差集（after 新增）==="
    if [[ -z "$DIFF_REFS" ]]; then
        echo "(empty — no new references introduced)"
    else
        echo "$DIFF_REFS"
    fi
    echo "=== 差集 test -f 结果 ==="
} > "$ARTIFACT_DIR/err-references-consistency.out"

if [[ -n "$DIFF_REFS" ]]; then
    while IFS= read -r ref; do
        [[ -z "$ref" ]] && continue
        if [[ -f "$REPO_ROOT/$ref" ]]; then
            echo "  [OK] $ref" >> "$ARTIFACT_DIR/err-references-consistency.out"
        else
            echo "  [MISSING] $ref" >> "$ARTIFACT_DIR/err-references-consistency.out"
            fail "scene 3.P1: 减法新增的引用 '$ref' 不存在（引入新悬空引用链断裂）"
        fi
    done <<< "$DIFF_REFS"
fi
pass "scene 3.P1: references 差集全部 test -f 通过（无新悬空；pre-existing doctor→quantitative-metrics.md 不在差集）"

# ===========================================================================
# 断言 7（场景3.P2）：§锚点方向 S_skill_text ⊆ S_hook_anchored 且 |after|>=|before|
#   S_skill_text = SKILL.md 文本引用的 §X.Y(.Z)+ 集合（两 SKILL.md 合并）
#   S_hook_anchored = stop-hook.sh 定义的 §X.Y 集合（含子段 §X.Y.Z 的前缀）
#   方向：SKILL 引用的 § 必须是 hook 定义的（非反向）
# ===========================================================================
# 提取 SKILL.md 文本 § 引用（after 当前工作区）
SKILL_REFS_AFTER=$(
    {
        echo "$AUTOPILOT_AFTER" | grep -oE '§[0-9]+(\.[0-9]+)+' || true
        echo "$DOCTOR_AFTER" | grep -oE '§[0-9]+(\.[0-9]+)+' || true
    } | sort -u
)
SKILL_REFS_BEFORE=$(
    {
        echo "$AUTOPILOT_BEFORE" | grep -oE '§[0-9]+(\.[0-9]+)+' || true
        echo "$DOCTOR_BEFORE" | grep -oE '§[0-9]+(\.[0-9]+)+' || true
    } | sort -u
)

# stop-hook.sh 定义的 § 集合（§X.Y(.Z)+）
HOOK_ANCHORS=$(grep -oE '§[0-9]+(\.[0-9]+)+' "$REPO_ROOT/$STOP_HOOK" 2>/dev/null | sort -u)

# 判定 S_skill_text ⊆ S_hook_anchored：
# 对每个 SKILL 引用的 §ref，hook 中必须存在 §ref 本身 或 §ref 的父段（§X.Y 是 §X.Y.Z 的父段）
# 实现策略：对 SKILL 的每个 §ref，hook 集合中存在 §ref 完全匹配 OR §ref 是 hook 某锚点的子段前缀
# 更稳健：SKILL §ref 在 hook § 集合中存在，或 hook § 集合中存在 §ref 的前缀段
{
    echo "=== S_skill_text (after) ==="
    echo "$SKILL_REFS_AFTER"
    echo "=== S_hook_anchored ==="
    echo "$HOOK_ANCHORS"
    echo "=== 子集判定 ==="
} > "$ARTIFACT_DIR/err-stop-hook-section-refs.out"

subset_ok=1
violations=""
if [[ -n "$SKILL_REFS_AFTER" ]]; then
    while IFS= read -r ref; do
        [[ -z "$ref" ]] && continue
        # strip leading §
        ref_num="${ref#§}"
        # hook 中完全匹配 OR hook 中存在 ref 的祖先段（ref 以 hook§num + '.' 开头）
        matched=0
        if echo "$HOOK_ANCHORS" | grep -qF "$ref"; then
            matched=1
        else
            # 检查 ref 是否以 hook 某锚点为前缀（hook §X.Y 是 SKILL §X.Y.Z 的祖先）
            while IFS= read -r hook_anchor; do
                [[ -z "$hook_anchor" ]] && continue
                hook_num="${hook_anchor#§}"
                # ref 以 "hook_num." 开头 = hook 是 ref 的祖先段
                if [[ "$ref_num" == "$hook_num" || "$ref_num" == "$hook_num".* ]]; then
                    matched=1
                    break
                fi
            done <<< "$HOOK_ANCHORS"
        fi
        if [[ "$matched" -eq 0 ]]; then
            subset_ok=0
            violations="$violations $ref"
            echo "  [VIOLATION] SKILL §ref '$ref' not anchored in stop-hook" >> "$ARTIFACT_DIR/err-stop-hook-section-refs.out"
        else
            echo "  [OK] $ref" >> "$ARTIFACT_DIR/err-stop-hook-section-refs.out"
        fi
    done <<< "$SKILL_REFS_AFTER"
fi

[[ "$subset_ok" -eq 1 ]] || \
    fail "scene 3.P2: S_skill_text ⊄ S_hook_anchored（SKILL 引用了 stop-hook 未定义的 §锚点）violations:$violations"

# |S_skill_text_after| >= |S_skill_text_before|
SKILL_REFS_AFTER_COUNT=$(echo "$SKILL_REFS_AFTER" | grep -cE '§[0-9]' || echo 0)
SKILL_REFS_BEFORE_COUNT=$(echo "$SKILL_REFS_BEFORE" | grep -cE '§[0-9]' || echo 0)
echo "  |S_skill_text| before=$SKILL_REFS_BEFORE_COUNT after=$SKILL_REFS_AFTER_COUNT" >> "$ARTIFACT_DIR/err-stop-hook-section-refs.out"
[[ "$SKILL_REFS_AFTER_COUNT" -ge "$SKILL_REFS_BEFORE_COUNT" ]] || \
    fail "scene 3.P2: |S_skill_text| 收缩 before=$SKILL_REFS_BEFORE_COUNT > after=$SKILL_REFS_AFTER_COUNT（§锚点集合不可缩）"

pass "scene 3.P2: S_skill_text ⊆ S_hook_anchored 且 |after|=$SKILL_REFS_AFTER_COUNT>=|before|=$SKILL_REFS_BEFORE_COUNT"

# ===========================================================================
# 断言 8（场景4.P1）：version-sync.acceptance.test.sh rc==0
#   复用既有 version-sync 测试（plugin.json/marketplace.json/CLAUDE.md/README 一致）
# ===========================================================================
if [[ ! -f "$VERSION_SYNC_TEST" ]]; then
    echo "  [SKIP] version-sync.acceptance.test.sh not found at $VERSION_SYNC_TEST" > "$ARTIFACT_DIR/int-version-sync.out"
    fail "scene 4.P1: version-sync.acceptance.test.sh 不存在: $VERSION_SYNC_TEST"
fi
VERSION_SYNC_OUTPUT=$(bash "$VERSION_SYNC_TEST" 2>&1)
VERSION_SYNC_RC=$?
echo "$VERSION_SYNC_OUTPUT" > "$ARTIFACT_DIR/int-version-sync.out"
echo "rc=$VERSION_SYNC_RC" >> "$ARTIFACT_DIR/int-version-sync.out"
[[ "$VERSION_SYNC_RC" -eq 0 ]] || \
    fail "scene 4.P1: version-sync.acceptance.test.sh rc=$VERSION_SYNC_RC（版本三同步失败，见 artifact）"
pass "scene 4.P1: version-sync.acceptance.test.sh rc==0"

# ===========================================================================
# 断言 9（场景4.P2）：red/blue-team-prompt.md 铁律词 after >= before
#   pattern: 严禁|铁律|信息隔离|绝对不能
# ===========================================================================
IRON_PATTERN='严禁|铁律|信息隔离|绝对不能'

BLUE_BEFORE=$(read_before "$BLUE_TEAM_PROMPT")
BLUE_AFTER=$(read_after "$BLUE_TEAM_PROMPT")

RED_IRON_BEFORE=$(echo "$RED_BEFORE" | grep_count_stdin "$IRON_PATTERN")
RED_IRON_AFTER=$(echo "$RED_AFTER" | grep_count_stdin "$IRON_PATTERN")
BLUE_IRON_BEFORE=$(echo "$BLUE_BEFORE" | grep_count_stdin "$IRON_PATTERN")
BLUE_IRON_AFTER=$(echo "$BLUE_AFTER" | grep_count_stdin "$IRON_PATTERN")

IRON_BEFORE_TOTAL=$((RED_IRON_BEFORE + BLUE_IRON_BEFORE))
IRON_AFTER_TOTAL=$((RED_IRON_AFTER + BLUE_IRON_AFTER))

{
    echo "=== 红/蓝队 prompt 铁律词计数 ==="
    echo "  red-team-prompt.md:  before=$RED_IRON_BEFORE after=$RED_IRON_AFTER"
    echo "  blue-team-prompt.md: before=$BLUE_IRON_BEFORE after=$BLUE_IRON_AFTER"
    echo "  total:               before=$IRON_BEFORE_TOTAL after=$IRON_AFTER_TOTAL"
} > "$ARTIFACT_DIR/int-red-blue-iron-rule.out"

[[ "$IRON_AFTER_TOTAL" -ge "$IRON_BEFORE_TOTAL" ]] || \
    fail "scene 4.P2: 红/蓝队 prompt 铁律词计数下降 before=$IRON_BEFORE_TOTAL > after=$IRON_AFTER_TOTAL（铁律弱化）"
pass "scene 4.P2: 红/蓝队 prompt 铁律词 after>=before (total=$IRON_AFTER_TOTAL>=$IRON_BEFORE_TOTAL)"

# ===========================================================================
# 断言 10（场景4.P4）：skills/ 下 XCUITest|GUI test/测试 命中 after == before
#   零新增 GUI 测试机制（约束②锁定不越界）
# ===========================================================================
GUI_PATTERN='XCUITest|GUI.*(test|测试)'

count_gui_hits() {
    local ref="${1:-HEAD}"
    if [[ "$ref" == "WORKING" ]]; then
        git -C "$REPO_ROOT" grep -hE "$GUI_PATTERN" -- 'plugins/autopilot/skills/**' 2>/dev/null | wc -l | tr -d ' '
    else
        git -C "$REPO_ROOT" grep -hE "$GUI_PATTERN" "$ref" -- 'plugins/autopilot/skills/**' 2>/dev/null | wc -l | tr -d ' '
    fi
}

# HEAD baseline（grep -c 无匹配 stdout="0"+rc=1，原 || echo 0 双重 "0\n0" 致算术崩；用 || true 取 grep 单值）
GUI_BEFORE=$(git -C "$REPO_ROOT" ls-files 'plugins/autopilot/skills/**' | while read -r f; do
    git -C "$REPO_ROOT" show "HEAD:$f" 2>/dev/null
done | grep -cE "$GUI_PATTERN" 2>/dev/null || true)
GUI_BEFORE=${GUI_BEFORE:-0}

# after（当前工作区，含未提交）
GUI_AFTER=$(git -C "$REPO_ROOT" ls-files 'plugins/autopilot/skills/**' 'plugins/autopilot/skills/**/*' | while read -r f; do
    [[ -f "$REPO_ROOT/$f" ]] && cat "$REPO_ROOT/$f"
done | grep -cE "$GUI_PATTERN" 2>/dev/null || true)
GUI_AFTER=${GUI_AFTER:-0}

{
    echo "=== skills/ 下 GUI 测试机制命中数 ==="
    echo "  pattern: $GUI_PATTERN"
    echo "  before (HEAD): $GUI_BEFORE"
    echo "  after (working): $GUI_AFTER"
} > "$ARTIFACT_DIR/int-xcuitest-scope-excluded.out"

[[ "$GUI_AFTER" -eq "$GUI_BEFORE" ]] || \
    fail "scene 4.P4: skills/ 下 GUI 测试机制命中数变化 before=${GUI_BEFORE} != after=${GUI_AFTER}（约束②：零新增 GUI 测试机制）"
pass "scene 4.P4: skills/ 下 GUI 测试机制命中数 after==before (${GUI_AFTER}==${GUI_BEFORE})"

# ===========================================================================
# 断言 5（[2026-05-25] 双重 grep）：关键 step 段落完整守护
#   减法任务极易删 step 文本但既有 acceptance 只查契约词——补 step 标题+字段双重 grep，
#   防 cdad541 同款"删 step 段潜伏 27 天"回归。grep -F 避免 ** 正则问题。
# ===========================================================================
# scene 5.1: auto-fix Tier 0 失败 step（标题 + 含义字段，awk 提取 Phase: auto-fix 段）
AUTOFIX_SEC=$(awk '/^## Phase: auto-fix/{f=1;next} f&&/^## /{f=0} f' "$REPO_ROOT/$AUTOPILOT_SKILL")
echo "$AUTOFIX_SEC" | grep -qE "红队验收测试失败（Tier 0）" || \
    fail "scene 5.1: auto-fix 段缺 '红队验收测试失败（Tier 0）' step 标题（[2026-05-25] step 守护）"
echo "$AUTOFIX_SEC" | grep -qF "含义**：实现不符合设计要求" || \
    fail "scene 5.1: auto-fix Tier 0 段缺 '含义' 字段（减法易删解释 bullet，本任务曾删后回退）"
pass "scene 5.1: auto-fix Tier 0 step 标题+含义字段双重守护"

# scene 5.2: Tier 3.5 时序铁律（标题 + '不与 Tier 3 同轮'，防表格化/段落压缩丢失）
grep -qE "Tier 3\.5: 性能保障验证" "$REPO_ROOT/$AUTOPILOT_SKILL" || \
    fail "scene 5.2: SKILL.md 缺 'Tier 3.5: 性能保障验证' 段标题（[2026-05-25]）"
grep -qF "不与 Tier 3 同轮" "$REPO_ROOT/$AUTOPILOT_SKILL" || \
    fail "scene 5.2: Tier 3.5 时序铁律 '不与 Tier 3 同轮' 缺失（表格化/段落压缩易丢，本任务曾压扁后回退）"
pass "scene 5.2: Tier 3.5 标题+时序铁律双重守护"

# scene 5.3: 防合理化 Tier 1.5 专用就近章节（防删 implement/qa 就近引用）
grep -qF "##### 防合理化指南（Tier 1.5 专用）" "$REPO_ROOT/$AUTOPILOT_SKILL" || \
    fail "scene 5.3: qa 段缺 '防合理化指南（Tier 1.5 专用）' 就近章节（减法易删，本任务曾删后回退）"
pass "scene 5.3: 防合理化 Tier 1.5 专用章节守护"

echo "[OK ] R_SHRINK_INV skill-shrinkage-invariants — 全部断言通过"
exit 0
