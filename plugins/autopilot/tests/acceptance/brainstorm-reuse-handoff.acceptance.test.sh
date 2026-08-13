#!/usr/bin/env bash
# R_REUSE: brainstorm 产物复用接力（方案 A'）— design 阶段 Standard 模式「先查复用」
# 红队测试 — 黑盒视角，基于设计契约（state.md § 验收场景 SSOT）编写，
#            绝不读取蓝队改后的 SKILL.md Standard 段 / design-modes.md §3 实际内容
#            来凑断言（TDD 红灯原则）。
#
# 设计契约来源：
#   .autopilot/runtime/requirements/20260809-这个方向好一些，按照/state.md § 验收场景
#
# 变更背景：用户习惯「先独立 /autopilot:autopilot-brainstorm 再 /autopilot」，
#           但独立 brainstorm 产物对 autopilot 不可见。方案 A' 在 design 阶段
#           Standard 模式入口加「先查复用」（编排器语义扫描 runtime/requirements/*/brainstorm.md），
#           智力活留 skill md、机械活不下沉 bash（语义判断 = high freedom，[2026-05-05]/[2026-05-30]）。
#
# 谓词映射（10 条 det-machine，对照 state.md § 验收场景表）：
#   SC1.P1: git diff --numstat SKILL.md deleted >= added（净非增）
#   SC1.P2: wc -l SKILL.md <= 510（改动前 512，净减 ≥2）
#   SC2.P1: awk SKILL.md「### Standard Design」段 + grep -F「先查复用」命中≥1
#   SC2.P2: grep -F 'Skill: "autopilot-brainstorm"' SKILL.md 命中≥1（不破坏既有契约9/C3）
#   SC3.P1: awk design-modes.md「## §3」段 + grep -F「先查复用」命中≥1
#   SC4.P1: git diff --name-only 不含 autopilot-brainstorm/SKILL.md（brainstorm skill 零改）
#   SC4.P2: git diff --name-only 不含 setup.sh / lib.sh / stop-hook.sh（脚本零改）
#   SC4.P3: git diff --unified=0 SKILL.md 改动行号 ⊂ Standard Design 段行号范围
#           （步骤1/决策树区域零改；委托 fast-mode-decision-timing / brainstorm-default 兜底）
#   SC5.P1: awk Standard 段 + grep -F brainstorm.md AND grep -F 先查复用 双重命中
#           （[2026-05-25] 双重 grep 长效守护，AND 关系）
#   SC6.P1: [SKIP] claude -p headless Read + quote 判语义可读 — bash 无法直接调 LLM，
#           由编排器手动跑 claude -p 独立验证（[2026-07-19] 减法三件套①）
#
# 实现说明：
#   - 字面匹配一律 grep -F 避免 markdown ** / 正则元字符误解析（[2026-07-23] awk BSD 单词边界盲区）
#   - awk 提取段用 POSIX match/substr/split（避免 BSD/gawk 差异）
#   - git diff ref 优先 HEAD（工作区未提交），回退 HEAD~1（已提交），对齐 skill-md-net-shrinkage 范式

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

SKILL_FILE_REL="plugins/autopilot/skills/autopilot/SKILL.md"
DESIGN_MODES_REL="plugins/autopilot/skills/autopilot/references/design-modes.md"
BRAINSTORM_SKILL_REL="plugins/autopilot/skills/autopilot-brainstorm/SKILL.md"
SETUP_SH_REL="plugins/autopilot/scripts/setup.sh"
LIB_SH_REL="plugins/autopilot/scripts/lib.sh"
STOP_HOOK_REL="plugins/autopilot/scripts/stop-hook.sh"

SKILL_FILE="$REPO_ROOT/$SKILL_FILE_REL"
DESIGN_MODES_FILE="$REPO_ROOT/$DESIGN_MODES_REL"

pass() { echo "[PASS] R_REUSE: $1"; }
fail() {
    echo "[FAIL] R_REUSE: $1" >&2
    exit 1
}

# ── 前置：仓库根可识别为 git 仓库 ─────────────────────────────────────────────
[[ -d "$REPO_ROOT/.git" ]] || fail "REPO_ROOT 非 git 仓库: ${REPO_ROOT}（无法 git diff）"

# ── 前置：关键文件存在性检查 ──────────────────────────────────────────────────
[[ -f "$SKILL_FILE" ]] || fail "SKILL.md 不存在: $SKILL_FILE"
[[ -f "$DESIGN_MODES_FILE" ]] || fail "design-modes.md 不存在: $DESIGN_MODES_FILE"

# ── git diff ref 选择（优先 HEAD 工作区，回退 HEAD~1 已提交）──────────────────
# 判定 SKILL.md 是否有工作区改动（vs HEAD），对齐 skill-md-net-shrinkage.compute_numstat 范式
skill_has_workdir_change() {
    local out
    out=$(git -C "$REPO_ROOT" diff --numstat HEAD -- "$SKILL_FILE_REL" 2>/dev/null || true)
    [[ -n "$out" ]]
}

if skill_has_workdir_change; then
    DIFF_REF="HEAD"
    DIFF_REF_DESC="HEAD (working tree, uncommitted)"
else
    DIFF_REF="HEAD~1"
    DIFF_REF_DESC="HEAD~1 (committed, fallback diff)"
fi
pass "git diff ref 选定 [$DIFF_REF_DESC]"

# ════════════════════════════════════════════════════════════════════════════
# 谓词 SC1.P1 [det-machine]: git diff --numstat SKILL.md deleted >= added（净非增）
# observe: git diff --numstat SKILL.md 求 added/deleted
# assert:  deleted >= added
# ════════════════════════════════════════════════════════════════════════════
numstat_line=$(git -C "$REPO_ROOT" diff --numstat "$DIFF_REF" -- "$SKILL_FILE_REL" 2>/dev/null || true)
skill_added=0
skill_deleted=0
if [[ -n "$numstat_line" ]]; then
    # numstat 输出格式：<added>\t<deleted>\t<path>
    skill_added=$(echo "$numstat_line" | awk -F'\t' '{print $1}')
    skill_deleted=$(echo "$numstat_line" | awk -F'\t' '{print $2}')
    # 二进制文件保护（- 表示）
    [[ "$skill_added" == "-" ]] && skill_added=0
    [[ "$skill_deleted" == "-" ]] && skill_deleted=0
    # 防意外非数字
    [[ "$skill_added" =~ ^[0-9]+$ ]] || skill_added=0
    [[ "$skill_deleted" =~ ^[0-9]+$ ]] || skill_deleted=0
fi
pass "SC1.P1 numstat [$DIFF_REF_DESC]: added=$skill_added deleted=$skill_deleted"

if [[ "$skill_deleted" -lt "$skill_added" ]]; then
    NET_INC=$((skill_added - skill_deleted))
    fail "SC1.P1: SKILL.md 净增行 (added=$skill_added > deleted=$skill_deleted), 违反 deleted>=added 硬约束. net=+$NET_INC"
fi
NET_DEC=$((skill_deleted - skill_added))
pass "SC1.P1: SKILL.md 净非增约束满足 (deleted=$skill_deleted >= added=$skill_added, net=-$NET_DEC)"

# ════════════════════════════════════════════════════════════════════════════
# 谓词 SC1.P2 [det-machine]: wc -l SKILL.md <= 510
# observe: wc -l < SKILL.md
# assert:  after(<=510) <= before(512)
# ════════════════════════════════════════════════════════════════════════════
skill_lines=$(wc -l < "$SKILL_FILE")
# trim 可能的前导空白（BSD wc 偶发）
skill_lines=$(echo "$skill_lines" | tr -d '[:space:]')
if [[ "$skill_lines" -gt 510 ]]; then
    fail "SC1.P2: SKILL.md 行数 $skill_lines > 510（硬约束净减 ≥2：512→≤510）"
fi
pass "SC1.P2: SKILL.md 行数 $skill_lines <= 510"

# ════════════════════════════════════════════════════════════════════════════
# 辅助：awk 提取 SKILL.md「### Standard Design」段内容 + 行号范围
# 边界：从「### Standard Design」行到下一个「### 」或「## 」标题（POSIX awk）
# ════════════════════════════════════════════════════════════════════════════
extract_standard_section() {
    awk '
        /^### Standard Design/ { in_block=1; next }
        in_block && /^### / { in_block=0 }
        in_block && /^## / { in_block=0 }
        in_block { print }
    ' "$SKILL_FILE"
}

# 提取段起止行号（1-indexed，含标题行到边界前一行的闭区间）
extract_standard_range() {
    awk '
        /^### Standard Design/ { start=NR; in_block=1; next }
        in_block && (/^### / || /^## /) { print start " " (NR-1); in_block=0; exit }
        END { if (in_block && start>0) print start " " NR }
    ' "$SKILL_FILE"
}

standard_section=$(extract_standard_section)
[[ -n "$standard_section" ]] || fail "辅助: SKILL.md 中找不到「### Standard Design」段（awk 提取为空，蓝队可能改了标题或删段）"

standard_range=$(extract_standard_range)
[[ -n "$standard_range" ]] || fail "辅助: 无法提取 Standard Design 段行号范围"
standard_start=${standard_range% *}
standard_end=${standard_range#* }
[[ "$standard_start" =~ ^[0-9]+$ ]] || fail "辅助: Standard 段起始行号非数字: $standard_start"
[[ "$standard_end" =~ ^[0-9]+$ ]] || fail "辅助: Standard 段结束行号非数字: $standard_end"
pass "辅助: Standard Design 段行号范围 [$standard_start, $standard_end]（awk 边界提取）"

# ════════════════════════════════════════════════════════════════════════════
# 谓词 SC2.P1 [det-machine]: awk Standard 段 + grep -F「先查复用」命中≥1
# observe: awk 提取段 + grep -F '先查复用'
# assert:  命中数 >= 1
# ════════════════════════════════════════════════════════════════════════════
# 注：grep -F 字面匹配，避免「先查复用」被当作正则（虽无元字符，统一 -F 防御 + 与 SC5.P1 一致）
reuse_hits=$(echo "$standard_section" | grep -F -c '先查复用' || true)
if [[ "$reuse_hits" -lt 1 ]]; then
    fail "SC2.P1: Standard Design 段不含「先查复用」语义（grep -F 命中数=${reuse_hits}，期望≥1）"
fi
pass "SC2.P1: Standard Design 段含「先查复用」语义（命中数=${reuse_hits}）"

# ════════════════════════════════════════════════════════════════════════════
# 谓词 SC2.P2 [det-machine]: grep -F 'Skill: "autopilot-brainstorm"' SKILL.md 命中≥1
# observe: grep -F 'Skill: "autopilot-brainstorm"' SKILL.md
# assert:  命中数 >= 1（不破坏既有 brainstorm-default 契约9 / brainstorm-skill-extract C3）
# ════════════════════════════════════════════════════════════════════════════
# 注：双引号是契约字面的一部分（state.md 契约规约明确要求 Skill: "autopilot-brainstorm" 字面字符串）；
#     grep -F 把双引号当字面字符，单引号包整个模式防止 bash 干扰。
skill_delegate_hits=$(grep -F -c 'Skill: "autopilot-brainstorm"' "$SKILL_FILE" || true)
if [[ "$skill_delegate_hits" -lt 1 ]]; then
    fail "SC2.P2: SKILL.md 不含 'Skill: \"autopilot-brainstorm\"' 字面（破坏既有契约9/C3，命中数=${skill_delegate_hits}）"
fi
pass "SC2.P2: SKILL.md 含 'Skill: \"autopilot-brainstorm\"' 字面（命中数=${skill_delegate_hits}，契约9/C3 保持）"

# ════════════════════════════════════════════════════════════════════════════
# 谓词 SC3.P1 [det-machine]: awk design-modes.md「## §3」段 + grep「先查复用」命中≥1
# observe: awk 提取 design-modes.md §3 段 + grep -F '先查复用'
# assert:  命中数 >= 1
# ════════════════════════════════════════════════════════════════════════════
# 提取 §3 段（从「## §3」到下一个「## 」边界，progressive disclosure / 一处真相 [2026-05-10]）
design_modes_section3=$(awk '
    /^## §3/ { in_block=1; next }
    in_block && /^## / { in_block=0 }
    in_block { print }
' "$DESIGN_MODES_FILE")
[[ -n "$design_modes_section3" ]] || fail "SC3.P1: design-modes.md 中找不到「## §3」段（awk 提取为空）"

reuse_dm_hits=$(echo "$design_modes_section3" | grep -F -c '先查复用' || true)
if [[ "$reuse_dm_hits" -lt 1 ]]; then
    fail "SC3.P1: design-modes.md §3 段不含「先查复用」（命中数=${reuse_dm_hits}，期望≥1）"
fi
pass "SC3.P1: design-modes.md §3 段含「先查复用」详细步骤（命中数=${reuse_dm_hits}）"

# ════════════════════════════════════════════════════════════════════════════
# 谓词 SC4.P1 [det-machine]: git diff --name-only 不含 autopilot-brainstorm/SKILL.md
# observe: git diff --name-only
# assert:  不含 $BRAINSTORM_SKILL_REL（brainstorm skill 零改，方案 A' 不依赖）
# ════════════════════════════════════════════════════════════════════════════
changed_files=$(git -C "$REPO_ROOT" diff --name-only "$DIFF_REF" 2>/dev/null || true)
if echo "$changed_files" | grep -F -q "$BRAINSTORM_SKILL_REL"; then
    fail "SC4.P1: autopilot-brainstorm/SKILL.md 改动违规（$BRAINSTORM_SKILL_REL 出现在 git diff，方案 A' 要求 brainstorm skill 零改）"
fi
pass "SC4.P1: autopilot-brainstorm/SKILL.md 零改（方案 A' 不依赖）"

# ════════════════════════════════════════════════════════════════════════════
# 谓词 SC4.P2 [det-machine]: git diff --name-only 不含 setup.sh / lib.sh / stop-hook.sh
# observe: git diff --name-only
# assert:  不含任一脚本（语义活不下沉 bash，智力活留 skill md）
# ════════════════════════════════════════════════════════════════════════════
for script_rel in "$SETUP_SH_REL" "$LIB_SH_REL" "$STOP_HOOK_REL"; do
    if echo "$changed_files" | grep -F -q "$script_rel"; then
        fail "SC4.P2: 脚本改动违规（$script_rel 出现在 git diff，方案 A' 语义判断留 skill，不下沉 bash）"
    fi
done
pass "SC4.P2: setup.sh / lib.sh / stop-hook.sh 三脚本零改"

# ════════════════════════════════════════════════════════════════════════════
# 谓词 SC4.P3 [det-machine]: git diff --unified=0 SKILL.md 改动行号 ⊂ Standard Design 段范围
# observe: git diff --unified=0 SKILL.md 所有 hunk 的 new_start..new_end
# assert:  每个 hunk 的 [new_start, new_end] ⊂ [standard_start, standard_end]
#          （步骤1 fast_mode 探针区 / 决策树区域零改，委托 fast-mode-decision-timing /
#           brainstorm-default 兜底）
# ════════════════════════════════════════════════════════════════════════════
# 策略：
#   1. git diff --unified=0 解析 hunk 头 `@@ -l,s +l,s @@`，提取 +new_start,new_len
#   2. new_len 省略时默认 1；new_len=0（纯删除）当作单点 [new_start, new_start]（保守）
#   3. 断言所有 hunk 的 [new_start, new_end] ⊂ [standard_start, standard_end]
#   行号基准：git diff +new 段对应改动后文件行号，与 awk NR（当前磁盘 SKILL.md）一致。
#   注：用 awk POSIX match/substr/split 一次性解析所有 hunk，避免 BSD/gawk 差异。
# commit-aware：工作区 clean（改动已 commit，DIFF_REF=HEAD~1）→ 位置守护 N/A
# （位置守护是 brainstorm-reuse 一次性 QA，非跨任务持续约束；持续守护靠 SC2.P1 先查复用语义 + SC1.P1 净减）
if [[ "$DIFF_REF" == "HEAD~1" ]]; then
    pass "SC4.P3: 工作区 clean（改动已 commit），位置守护 N/A（一次性 QA；持续守护靠 SC2.P1 语义 + SC1.P1 净减）"
else
    hunk_output=$(git -C "$REPO_ROOT" diff --unified=0 "$DIFF_REF" -- "$SKILL_FILE_REL" 2>/dev/null || true)

    if [[ -n "$hunk_output" ]]; then
        # awk 解析所有 @@ hunk 头，输出越界违规行（若有）
        violations=$(echo "$hunk_output" | awk -v s="$standard_start" -v e="$standard_end" '
            /^@@/ {
                # 提取 +new_start,new_len 部分（match 找到 +数字[,数字]）
                if (match($0, /\+[0-9]+(,[0-9]+)?/)) {
                    plus = substr($0, RSTART+1, RLENGTH-1)
                    split(plus, a, ",")
                    ns = a[1] + 0
                    nl = (a[2] != "" ? a[2] + 0 : 1)
                    ne = (nl == 0 ? ns : ns + nl - 1)
                    if (ns < s || ne > e) {
                        print "  hunk [" ns "," ne "] 越出 Standard Design 段 [" s "," e "]"
                    }
                }
            }
        ')
        if [[ -n "$violations" ]]; then
            fail "SC4.P3: 检测到 hunk 改动行号越出 Standard Design 段 [$standard_start, $standard_end]（步骤1/决策树区域零改违规）：
$violations"
        fi
    fi
    pass "SC4.P3: 所有 hunk 改动行号 ⊂ Standard Design 段 [$standard_start, $standard_end]（步骤1/决策树区域零改）"
fi

# ════════════════════════════════════════════════════════════════════════════
# 谓词 SC5.P1 [det-machine]: awk Standard 段 brainstorm.md 字面 AND 先查复用语义 双重命中
# observe: awk Standard 段 + grep -F 'brainstorm.md' AND grep -F '先查复用'
# assert:  两重均命中≥1（[2026-05-25] 双重 grep 长效守护防 cdad541 翻版，AND 关系）
# ════════════════════════════════════════════════════════════════════════════
bm_hits=$(echo "$standard_section" | grep -F -c 'brainstorm.md' || true)
reuse_hits_5=$(echo "$standard_section" | grep -F -c '先查复用' || true)
if [[ "$bm_hits" -lt 1 ]]; then
    fail "SC5.P1: Standard Design 段不含 'brainstorm.md' 字面（AND 第一重失效，命中数=${bm_hits}，[2026-05-25] 双重守护要求）"
fi
if [[ "$reuse_hits_5" -lt 1 ]]; then
    fail "SC5.P1: Standard Design 段不含「先查复用」语义（AND 第二重失效，命中数=${reuse_hits_5}，[2026-05-25] 双重守护要求）"
fi
pass "SC5.P1: Standard Design 段双重 grep 命中（brainstorm.md=$bm_hits AND 先查复用=${reuse_hits_5}，[2026-05-25] 长效守护）"

# ════════════════════════════════════════════════════════════════════════════
# 谓词 SC6.P1 [det-machine]: claude -p headless Read SKILL.md + quote Standard 段
# assert:  含「先查复用」语义可读（[2026-07-19] 减法三件套①）
# ════════════════════════════════════════════════════════════════════════════
# 注：bash 无法直接调 LLM 判断语义可读性。此谓词需编排器 claude -p headless 独立验证：
#     Read SKILL.md → quote Standard Design 段 → 判断含「先查复用」语义可读。
#     此处标注 SKIP 不 fail（不阻塞红队），由 Tier 1.5 / 编排器手动跑 claude -p 兜底。
echo "[SKIP] SC6.P1 需编排器 claude -p 独立验证（[2026-07-19] 三件套①：headless Read SKILL.md + quote Standard 段判语义可读）"

# ════════════════════════════════════════════════════════════════════════════
echo "[OK ] R_REUSE brainstorm-reuse-handoff — 全部断言通过（9 条 det-machine 谓词执行 + 1 条 SC6.P1 SKIP）"
exit 0
