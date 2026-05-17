#!/usr/bin/env bash
# R11: 验证 autopilot-brainstorm 独立 skill 抽离契约
# 红队测试 — 仅基于设计文档编写，不读取蓝队实现
#
# 设计文档来源：
#   .autopilot/requirements/20260517-你深入了解下-autopilot/state.md § 契约规约
#
# 覆盖契约（14 条全覆盖）：
#   C1:  autopilot-brainstorm/SKILL.md frontmatter 含 name: autopilot-brainstorm
#   C2:  autopilot-brainstorm/SKILL.md 正文含 <HARD-GATE> 标签
#   C3:  autopilot/SKILL.md Standard Design 段落含 Skill: "autopilot-brainstorm" 字面字符串
#   C4:  autopilot/SKILL.md 全文不得出现 brainstorm-guide.md
#   C5:  stop-hook.sh 全文不得出现 brainstorm-guide.md
#   C6:  autopilot/references/brainstorm-guide.md 文件不得存在
#   C7:  autopilot/references/visual-companion-guide.md 文件不得存在
#   C8:  autopilot-brainstorm/references/visual-companion-guide.md 文件必须存在
#   C9:  plugin.json 含 "version": "3.33.0"
#   C10: v3.33.0 一致出现于 marketplace.json / CLAUDE.md / README.md
#   B1:  autopilot-brainstorm/SKILL.md 含 Anti-Pattern 段落
#   B2:  autopilot-brainstorm/SKILL.md 含 Checklist 段落
#   B3:  autopilot-brainstorm/SKILL.md 含 brainstorm.md 模板关键字符串
#   B4:  autopilot-brainstorm/SKILL.md frontmatter description 明确说明使用场景
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

BRAINSTORM_SKILL_MD="$REPO_ROOT/plugins/autopilot/skills/autopilot-brainstorm/SKILL.md"
VISUAL_COMPANION_NEW="$REPO_ROOT/plugins/autopilot/skills/autopilot-brainstorm/references/visual-companion-guide.md"

AUTOPILOT_SKILL_MD="$REPO_ROOT/plugins/autopilot/skills/autopilot/SKILL.md"
OLD_BRAINSTORM_GUIDE="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/brainstorm-guide.md"
OLD_VISUAL_COMPANION="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/visual-companion-guide.md"

STOP_HOOK="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"
PLUGIN_JSON="$REPO_ROOT/plugins/autopilot/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
AUTOPILOT_README="$REPO_ROOT/plugins/autopilot/README.md"

TARGET_VERSION="3.33.0"

# ── 辅助函数 ─────────────────────────────────────────────────────────────────
pass() { echo "[PASS] R11: $1"; }
fail() {
    echo "[FAIL] R11: $1" >&2
    exit 1
}

# ── 前置：关键文件存在性预检 ──────────────────────────────────────────────────
[[ -f "$AUTOPILOT_SKILL_MD" ]] || fail "前置: autopilot/SKILL.md 不存在: $AUTOPILOT_SKILL_MD"
[[ -f "$STOP_HOOK" ]]          || fail "前置: stop-hook.sh 不存在: $STOP_HOOK"
[[ -f "$PLUGIN_JSON" ]]        || fail "前置: plugin.json 不存在: $PLUGIN_JSON"
[[ -f "$MARKETPLACE_JSON" ]]   || fail "前置: marketplace.json 不存在: $MARKETPLACE_JSON"
[[ -f "$CLAUDE_MD" ]]          || fail "前置: CLAUDE.md 不存在: $CLAUDE_MD"
[[ -f "$AUTOPILOT_README" ]]   || fail "前置: autopilot README.md 不存在: $AUTOPILOT_README"

# ════════════════════════════════════════════════════════════════════════════
# C1: autopilot-brainstorm/SKILL.md frontmatter 含 name: autopilot-brainstorm
# ════════════════════════════════════════════════════════════════════════════

[[ -f "$BRAINSTORM_SKILL_MD" ]] || fail "C1: autopilot-brainstorm/SKILL.md 不存在: $BRAINSTORM_SKILL_MD"

# 提取 frontmatter 区域（两个 --- 之间），在其中断言 name 字段
frontmatter=$(awk '/^---$/{if(++c==1){f=1;next}else{f=0}} f{print}' "$BRAINSTORM_SKILL_MD")
[[ -n "$frontmatter" ]] || fail "C1: autopilot-brainstorm/SKILL.md 未找到 frontmatter（--- 包裹区域）"

if ! echo "$frontmatter" | grep -qE '^name:[[:space:]]*autopilot-brainstorm$'; then
    fail "C1: autopilot-brainstorm/SKILL.md frontmatter 不含 'name: autopilot-brainstorm'（精确字段匹配失败）"
fi
pass "C1: autopilot-brainstorm/SKILL.md frontmatter 含 name: autopilot-brainstorm"

# ════════════════════════════════════════════════════════════════════════════
# C2: autopilot-brainstorm/SKILL.md 正文含 <HARD-GATE> 标签
# ════════════════════════════════════════════════════════════════════════════

if ! grep -qF '<HARD-GATE>' "$BRAINSTORM_SKILL_MD"; then
    fail "C2: autopilot-brainstorm/SKILL.md 正文不含 <HARD-GATE> 标签（设计要求强语言标识必须存在）"
fi
pass "C2: autopilot-brainstorm/SKILL.md 正文含 <HARD-GATE> 标签"

# ════════════════════════════════════════════════════════════════════════════
# C3: autopilot/SKILL.md Standard Design 段落含 Skill: "autopilot-brainstorm" 字面字符串
# ════════════════════════════════════════════════════════════════════════════

if ! grep -qF 'Skill: "autopilot-brainstorm"' "$AUTOPILOT_SKILL_MD"; then
    fail "C3: autopilot/SKILL.md 不含字面字符串 Skill: \"autopilot-brainstorm\"（委托调用语句缺失）"
fi
pass "C3: autopilot/SKILL.md 含 Skill: \"autopilot-brainstorm\" 字面字符串"

# ════════════════════════════════════════════════════════════════════════════
# C4: autopilot/SKILL.md 全文不得出现 brainstorm-guide.md
# ════════════════════════════════════════════════════════════════════════════

if grep -qF 'brainstorm-guide.md' "$AUTOPILOT_SKILL_MD"; then
    match_lines=$(grep -n 'brainstorm-guide.md' "$AUTOPILOT_SKILL_MD" | head -5)
    fail "C4: autopilot/SKILL.md 全文不得出现 'brainstorm-guide.md'，但仍存在（行: ${match_lines}）"
fi
pass "C4: autopilot/SKILL.md 全文不含 brainstorm-guide.md（已清理）"

# ════════════════════════════════════════════════════════════════════════════
# C5: stop-hook.sh 全文不得出现 brainstorm-guide.md
# ════════════════════════════════════════════════════════════════════════════

if grep -qF 'brainstorm-guide.md' "$STOP_HOOK"; then
    match_lines=$(grep -n 'brainstorm-guide.md' "$STOP_HOOK" | head -5)
    fail "C5: stop-hook.sh 全文不得出现 'brainstorm-guide.md'，但仍存在（行: ${match_lines}）"
fi
pass "C5: stop-hook.sh 全文不含 brainstorm-guide.md（已清理）"

# ════════════════════════════════════════════════════════════════════════════
# C6: autopilot/references/brainstorm-guide.md 文件不得存在
# ════════════════════════════════════════════════════════════════════════════

if [[ -f "$OLD_BRAINSTORM_GUIDE" ]]; then
    fail "C6: autopilot/references/brainstorm-guide.md 仍然存在（应已删除，被新 skill 取代）"
fi
pass "C6: autopilot/references/brainstorm-guide.md 已不存在（已删除）"

# ════════════════════════════════════════════════════════════════════════════
# C7: autopilot/references/visual-companion-guide.md 文件不得存在
# ════════════════════════════════════════════════════════════════════════════

if [[ -f "$OLD_VISUAL_COMPANION" ]]; then
    fail "C7: autopilot/references/visual-companion-guide.md 仍然存在（应已迁出到 autopilot-brainstorm/references/）"
fi
pass "C7: autopilot/references/visual-companion-guide.md 已不存在（已迁出）"

# ════════════════════════════════════════════════════════════════════════════
# C8: autopilot-brainstorm/references/visual-companion-guide.md 文件必须存在
# ════════════════════════════════════════════════════════════════════════════

if [[ ! -f "$VISUAL_COMPANION_NEW" ]]; then
    fail "C8: autopilot-brainstorm/references/visual-companion-guide.md 不存在（应从主 skill 迁入）"
fi
pass "C8: autopilot-brainstorm/references/visual-companion-guide.md 已存在（迁入成功）"

# ════════════════════════════════════════════════════════════════════════════
# C9: plugin.json 含 "version": "3.33.0"
# ════════════════════════════════════════════════════════════════════════════

plugin_version=$(grep '"version"' "$PLUGIN_JSON" \
    | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' \
    | head -1)
[[ -n "$plugin_version" ]] || fail "C9: plugin.json 无法提取 version 字段"

if [[ "$plugin_version" != "$TARGET_VERSION" ]]; then
    fail "C9: plugin.json 版本 '$plugin_version' != 期望 '$TARGET_VERSION'"
fi
pass "C9: plugin.json 含 \"version\": \"$TARGET_VERSION\""

# ════════════════════════════════════════════════════════════════════════════
# C10: v3.33.0 一致出现于 marketplace.json / CLAUDE.md / README.md 顶部
# ════════════════════════════════════════════════════════════════════════════

# C10a: marketplace.json autopilot 条目
marketplace_version=$(python3 -c "
import json
data = json.load(open('$MARKETPLACE_JSON'))
plugins = data if isinstance(data, list) else data.get('plugins', [])
for p in plugins:
    if p.get('name') == 'autopilot':
        print(p.get('version', ''))
        break
" 2>/dev/null || true)

if [[ -z "$marketplace_version" ]]; then
    # 回退方案：awk 提取（兼容 python3 不可用场景）
    marketplace_version=$(awk '
        /"name"[[:space:]]*:[[:space:]]*"autopilot"/ { found=1 }
        found && /"version"/ {
            match($0, /"version"[[:space:]]*:[[:space:]]*"([^"]+)"/, arr)
            if (arr[1] != "") { print arr[1]; found=0 }
        }
    ' "$MARKETPLACE_JSON")
fi

[[ -n "$marketplace_version" ]] || fail "C10: marketplace.json 中找不到 autopilot 条目的 version 字段"
if [[ "$marketplace_version" != "$TARGET_VERSION" ]]; then
    fail "C10a: marketplace.json autopilot 版本 '$marketplace_version' != 期望 '$TARGET_VERSION'"
fi
pass "C10a: marketplace.json autopilot 版本 = $TARGET_VERSION"

# C10b: CLAUDE.md 插件索引表
if ! grep -E "autopilot" "$CLAUDE_MD" | grep -qE "v${TARGET_VERSION}|${TARGET_VERSION}"; then
    fail "C10b: CLAUDE.md 插件索引表 autopilot 行未找到版本 v${TARGET_VERSION}"
fi
pass "C10b: CLAUDE.md 插件索引表 autopilot 行含 v${TARGET_VERSION}"

# C10c: autopilot README.md 顶部（前 30 行）
readme_head=$(head -30 "$AUTOPILOT_README")
if ! echo "$readme_head" | grep -qE "v${TARGET_VERSION}|${TARGET_VERSION}"; then
    fail "C10c: autopilot README.md 顶部（前 30 行）未找到 v${TARGET_VERSION} 变更说明"
fi
pass "C10c: autopilot README.md 顶部含 v${TARGET_VERSION} 变更说明"

# C10d: 版本号内部一致性（plugin.json 与 marketplace.json 一致）
if [[ "$plugin_version" != "$marketplace_version" ]]; then
    fail "C10d: plugin.json($plugin_version) 与 marketplace.json($marketplace_version) 版本不一致"
fi
pass "C10d: plugin.json 与 marketplace.json 版本一致 (${TARGET_VERSION})"

# ════════════════════════════════════════════════════════════════════════════
# B1: autopilot-brainstorm/SKILL.md 含 Anti-Pattern 段落
# ════════════════════════════════════════════════════════════════════════════

if ! grep -qiE 'Anti-Pattern|anti pattern|反模式' "$BRAINSTORM_SKILL_MD"; then
    fail "B1: autopilot-brainstorm/SKILL.md 不含 Anti-Pattern 段落（设计要求强语言标识 'Anti-Pattern' 或 '反模式'）"
fi
pass "B1: autopilot-brainstorm/SKILL.md 含 Anti-Pattern 段落"

# ════════════════════════════════════════════════════════════════════════════
# B2: autopilot-brainstorm/SKILL.md 含 Checklist 段落
# ════════════════════════════════════════════════════════════════════════════

if ! grep -qiE 'Checklist|检查清单|checklist' "$BRAINSTORM_SKILL_MD"; then
    fail "B2: autopilot-brainstorm/SKILL.md 不含 Checklist 段落（设计要求必须包含强制执行 Checklist）"
fi
pass "B2: autopilot-brainstorm/SKILL.md 含 Checklist 段落"

# ════════════════════════════════════════════════════════════════════════════
# B3: autopilot-brainstorm/SKILL.md 含 brainstorm.md 模板关键字符串
#     验证：探索的目的与约束 / 候选方案与权衡（或近义命名）
# ════════════════════════════════════════════════════════════════════════════

has_purpose=0
has_candidates=0

# 探索的目的与约束（或近义）
if grep -qE '探索的目的与约束|目的与约束|探索目的' "$BRAINSTORM_SKILL_MD"; then
    has_purpose=1
fi

# 候选方案与权衡（或近义）
if grep -qE '候选方案与权衡|候选方案|方案与权衡' "$BRAINSTORM_SKILL_MD"; then
    has_candidates=1
fi

if [[ $has_purpose -eq 0 ]]; then
    fail "B3: autopilot-brainstorm/SKILL.md 不含 brainstorm.md 模板关键字符串：'探索的目的与约束'（或近义），模板章节缺失"
fi
if [[ $has_candidates -eq 0 ]]; then
    fail "B3: autopilot-brainstorm/SKILL.md 不含 brainstorm.md 模板关键字符串：'候选方案与权衡'（或近义），模板章节缺失"
fi
pass "B3: autopilot-brainstorm/SKILL.md 含 brainstorm.md 模板关键字符串（探索的目的与约束 / 候选方案与权衡）"

# ════════════════════════════════════════════════════════════════════════════
# B4: autopilot-brainstorm/SKILL.md frontmatter description 字段明确说明使用场景
#     必须包含 "design 阶段" / "需求探索" 等关键词
# ════════════════════════════════════════════════════════════════════════════

description_value=$(echo "$frontmatter" | grep -E '^description:' | sed 's/^description:[[:space:]]*//')
[[ -n "$description_value" ]] || fail "B4: autopilot-brainstorm/SKILL.md frontmatter 不含 description 字段"

has_design_stage=0
has_exploration=0

# design 阶段 / design phase
if echo "$description_value" | grep -qiE 'design[[:space:]]*阶段|design phase'; then
    has_design_stage=1
fi

# 需求探索 / 需求分析 / requirement exploration
if echo "$description_value" | grep -qiE '需求探索|需求分析|requirement.*explor'; then
    has_exploration=1
fi

if [[ $has_design_stage -eq 0 ]] && [[ $has_exploration -eq 0 ]]; then
    fail "B4: autopilot-brainstorm/SKILL.md frontmatter description 不含使用场景关键词（需包含 'design 阶段' 或 '需求探索' 等）；当前 description: '$description_value'"
fi
pass "B4: autopilot-brainstorm/SKILL.md frontmatter description 明确说明使用场景（含 design 阶段 / 需求探索 等关键词）"

# ════════════════════════════════════════════════════════════════════════════
echo "[OK ] R11 brainstorm-skill-extract — 全部断言通过（C1-C10 + B1-B4，共 14 条契约验收完毕）"
exit 0
