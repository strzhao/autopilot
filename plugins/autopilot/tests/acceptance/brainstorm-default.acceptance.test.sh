#!/usr/bin/env bash
# R9: 验证方案 B' 核心契约 — design 阶段默认含 brainstorm，--fast 跳过，--deep 向后兼容
# 红队测试 — 仅基于设计文档编写，不读取蓝队实现
#
# 设计文档来源：
#   .autopilot/requirements/20260508-我本意是希望把-brainsto/state.md § 推荐方案：方案 B' 详细设计
#
# 11 个核心契约（对照表序号）：
#   1.  决策树 3 档：auto_approve / fast_mode / 默认（SKILL.md 决策树区域优先级条目数 <= 3）
#   2.  默认含 brainstorm：stop-hook.sh design else 分支 PROMPT 含 "brainstorm" 关键词
#   3.  --fast 跳过 brainstorm：stop-hook.sh fast_mode 分支 PROMPT 含跳过 brainstorm 语义
#   4.  --fast 砍 sub-agent：fast_mode 分支 PROMPT 含 "scenario-generator" 且含 "plan-reviewer"
#   5.  --deep deprecation：setup.sh --deep 分支体内含 echo 到 stderr 的 deprecation 提示
#   6.  --deep 不分流：stop-hook.sh 中不存在 PLAN_MODE.*==.*"deep" 分支判断
#   7.  brainstorm-guide.md 不得存在（已被 autopilot-brainstorm skill 取代）
#   8.  deep-design-guide.md 不存在
#   9.  SKILL.md 引用一致：含 Skill: "autopilot-brainstorm" 且不含 brainstorm-guide.md
#  10.  autopilot-brainstorm/SKILL.md 存在且含 <HARD-GATE>
#  11.  版本一致 v3.33.0（plugin.json + marketplace.json + CLAUDE.md 三处）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

SETUP_SH="$REPO_ROOT/plugins/autopilot/scripts/setup.sh"
STOP_HOOK="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"
SKILL_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/SKILL.md"
REFERENCES_DIR="$REPO_ROOT/plugins/autopilot/skills/autopilot/references"
PLUGIN_JSON="$REPO_ROOT/plugins/autopilot/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"

# 动态读取 plugin.json 作为版本同步基准（避免硬编码盲区，参见 [2026-05-09] knowledge）
TARGET_VERSION=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$PLUGIN_JSON" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
[[ -n "$TARGET_VERSION" ]] || { echo "[FAIL] R9: 无法从 plugin.json 读取版本号" >&2; exit 1; }

# ── 辅助函数 ─────────────────────────────────────────────────────────────────
pass() { echo "[PASS] R9: $1"; }
fail() {
    echo "[FAIL] R9: $1" >&2
    exit 1
}

# ── 前置：文件存在性检查 ──────────────────────────────────────────────────────
[[ -f "$SETUP_SH" ]]      || fail "setup.sh 不存在: $SETUP_SH"
[[ -f "$STOP_HOOK" ]]     || fail "stop-hook.sh 不存在: $STOP_HOOK"
[[ -f "$SKILL_FILE" ]]    || fail "SKILL.md 不存在: $SKILL_FILE"
[[ -f "$PLUGIN_JSON" ]]   || fail "plugin.json 不存在: $PLUGIN_JSON"
[[ -f "$MARKETPLACE_JSON" ]] || fail "marketplace.json 不存在: $MARKETPLACE_JSON"
[[ -f "$CLAUDE_MD" ]]     || fail "CLAUDE.md 不存在: $CLAUDE_MD"

# ════════════════════════════════════════════════════════════════════════════
# 契约 1：决策树从 4 档简化为 3 档（auto_approve / fast_mode / 默认）
# 验证：SKILL.md 决策树区域的优先级条目数 <= 3，且不含 plan_mode 分支
# ════════════════════════════════════════════════════════════════════════════

# 提取 ⚠️ 关键规则/决策树块（只取标题所在段落内的连续编号列表）
# 策略：找到"关键规则"行，取紧随的编号列表行（1. / 2. / ...），遇到空行+非编号行停止
rules_section=$(awk '
    /⚠️.*关键规则|关键规则.*⚠️/ { in_block=1; next }
    in_block && /^\s*[0-9]+\./ { print; next }
    in_block && /^\s*$/ { next }
    in_block { in_block=0 }
' "$SKILL_FILE")

# 如果上面没抓到，用更宽松的策略
if [[ -z "$rules_section" ]]; then
    rules_section=$(grep -A10 "关键规则" "$SKILL_FILE" | grep -E '^\s*[0-9]+\. ')
fi

[[ -n "$rules_section" ]] || fail "契约1: SKILL.md 中找不到 ⚠️ 关键规则/决策树段落"

# 统计决策树优先级条目数（纯编号列表行）
decision_entries=$(echo "$rules_section" | grep -cE '^\s*[1-9]\. ' || true)
if [[ "$decision_entries" -gt 3 ]]; then
    fail "契约1: 决策树优先级条目数 $decision_entries > 3（设计文档要求 4 档简化为 3 档）"
fi
pass "契约1: 决策树优先级条目数 <= 3 (当前: ${decision_entries})"

# 验证决策树中不再有 plan_mode 作为独立档位
if echo "$rules_section" | grep -qE 'plan_mode|"deep"'; then
    fail "契约1: 决策树中仍存在 plan_mode/deep 作为独立优先级档位（应已删除）"
fi
pass "契约1: 决策树不含 plan_mode 独立档位"

# ════════════════════════════════════════════════════════════════════════════
# 契约 2：默认行为含 brainstorm（stop-hook.sh design else 分支 PROMPT 含 "brainstorm"）
# ════════════════════════════════════════════════════════════════════════════

# 宽松策略：直接检查 stop-hook.sh 中 else 分支区域含 brainstorm
# （因为 else 是默认路径，含 brainstorm 即满足设计契约）
else_with_brainstorm=$(grep -c "brainstorm" "$STOP_HOOK" || true)
if [[ "$else_with_brainstorm" -lt 1 ]]; then
    fail "契约2: stop-hook.sh 中找不到 brainstorm 关键词（设计要求默认路径 PROMPT 含 brainstorm）"
fi

# 进一步验证：brainstorm 关键词出现在 else 分支而非仅 elif 分支
# 通过检查 stop-hook.sh 中 auto_approve/fast_mode 分支之外是否有 brainstorm
# 采用行号比较：找到 else 关键词行之后的 brainstorm 出现
auto_approve_line=$(grep -n 'AUTO_APPROVE.*==.*"true"' "$STOP_HOOK" | head -1 | cut -d: -f1)
fast_mode_line=$(grep -n 'FAST_MODE.*==.*"true"' "$STOP_HOOK" | head -1 | cut -d: -f1)
brainstorm_lines=$(grep -n "brainstorm" "$STOP_HOOK" | cut -d: -f1)

[[ -n "$auto_approve_line" ]] || fail "契约2: stop-hook.sh 中找不到 AUTO_APPROVE 分支（架构基础缺失）"
[[ -n "$fast_mode_line" ]] || fail "契约2: stop-hook.sh 中找不到 FAST_MODE 分支（架构基础缺失）"

# 至少有一处 brainstorm 出现在 fast_mode 分支行号之后（即默认 else 分支区域）
found_in_else=0
while IFS= read -r bline; do
    [[ -z "$bline" ]] && continue
    if [[ "$bline" -gt "$fast_mode_line" ]]; then
        found_in_else=1
        break
    fi
done <<< "$brainstorm_lines"

if [[ "$found_in_else" -eq 0 ]]; then
    fail "契约2: stop-hook.sh 中 brainstorm 未出现在 fast_mode 分支(行 ${fast_mode_line})之后的 else 区域"
fi
pass "契约2: stop-hook.sh 默认 else 分支区域含 brainstorm 关键词"

# ════════════════════════════════════════════════════════════════════════════
# 契约 3：--fast 跳过 brainstorm（fast_mode 分支 PROMPT 含跳过 brainstorm 语义）
# ════════════════════════════════════════════════════════════════════════════

# 提取 fast_mode 分支到下一个 else/elif/fi 之间的内容
fast_mode_section=$(awk -v start="$fast_mode_line" '
    NR >= start { print }
    NR > start && /^[[:space:]]*(else|elif|fi)[[:space:]]*$|^[[:space:]]*(else|elif|fi)[[:space:]]*[\{#]/ { exit }
' "$STOP_HOOK")

# 验证含"跳过 brainstorm"或"不执行 brainstorm"或"skip brainstorm"语义
if ! echo "$fast_mode_section" | grep -qiE "跳过[[:space:]]*brainstorm|不执行[[:space:]]*brainstorm|skip.*brainstorm|brainstorm.*跳过|brainstorm.*skip"; then
    fail "契约3: stop-hook.sh fast_mode 分支 PROMPT 不含跳过 brainstorm 语义（期望：跳过 brainstorm / skip brainstorm 等）"
fi
pass "契约3: stop-hook.sh fast_mode 分支含跳过 brainstorm 语义"

# ════════════════════════════════════════════════════════════════════════════
# 契约 4：--fast 砍 sub-agent（fast_mode 分支含 scenario-generator 和 plan-reviewer 说明）
# ════════════════════════════════════════════════════════════════════════════

if ! echo "$fast_mode_section" | grep -qiE "scenario.generator|scenario_generator"; then
    fail "契约4: stop-hook.sh fast_mode 分支 PROMPT 不含 scenario-generator（设计要求 --fast 砍 scenario-generator）"
fi
pass "契约4a: stop-hook.sh fast_mode 分支含 scenario-generator 引用"

if ! echo "$fast_mode_section" | grep -qiE "plan.reviewer|plan_reviewer"; then
    fail "契约4: stop-hook.sh fast_mode 分支 PROMPT 不含 plan-reviewer（设计要求 --fast 砍 plan-reviewer）"
fi
pass "契约4b: stop-hook.sh fast_mode 分支含 plan-reviewer 引用"

# ════════════════════════════════════════════════════════════════════════════
# 契约 5：--deep deprecation（setup.sh --deep 分支内含 echo 到 stderr 的 deprecation 提示）
# ════════════════════════════════════════════════════════════════════════════

# 找到 --deep 分支行
deep_flag_line=$(grep -n '"--deep"\|--deep)' "$SETUP_SH" | head -1 | cut -d: -f1)
[[ -n "$deep_flag_line" ]] || fail "契约5: setup.sh 中找不到 --deep flag 解析（保留向后兼容要求 --deep 存在）"

# 提取 --deep 分支体内容（到下一个 ;; 或 esac 或另一个 --* 分支）
deep_section=$(awk -v start="$deep_flag_line" '
    NR >= start { print }
    NR > start && /^[[:space:]]*;;[[:space:]]*$|^[[:space:]]*"--[a-z]|^[[:space:]]*--[a-z]/ { exit }
' "$SETUP_SH" | head -20)

# 验证含有向 stderr 输出的 deprecation 提示
if ! echo "$deep_section" | grep -qE '>&2|2>'; then
    fail "契约5: setup.sh --deep 分支体内找不到 stderr 输出（echo ... >&2）（设计要求输出 deprecation 提示到 stderr）"
fi

if ! echo "$deep_section" | grep -qiE "废弃|deprecat|deprecated|deprecated|弃用|已废弃"; then
    fail "契约5: setup.sh --deep 分支体内找不到 deprecation 语义（废弃/deprecat/弃用 等关键词）"
fi
pass "契约5: setup.sh --deep 分支含向 stderr 输出的 deprecation 提示"

# ════════════════════════════════════════════════════════════════════════════
# 契约 6：--deep 不分流（stop-hook.sh 中不存在 PLAN_MODE.*==.*"deep" 分支判断）
# ════════════════════════════════════════════════════════════════════════════

if grep -qE 'PLAN_MODE.*==.*"deep"' "$STOP_HOOK"; then
    fail "契约6: stop-hook.sh 中仍存在 PLAN_MODE.*==.*\"deep\" 分支判断（设计要求删除此分支，--deep 行为等同默认）"
fi
pass "契约6: stop-hook.sh 中不存在 PLAN_MODE.*==.*\"deep\" 分支判断"

# ════════════════════════════════════════════════════════════════════════════
# 契约 7：brainstorm-guide.md 文件不得存在（已被 autopilot-brainstorm skill 取代）
# ════════════════════════════════════════════════════════════════════════════

BRAINSTORM_GUIDE="$REFERENCES_DIR/brainstorm-guide.md"
if [[ -f "$BRAINSTORM_GUIDE" ]]; then
    fail "契约7: references/brainstorm-guide.md 仍然存在（应已删除，brainstorm 已抽离为独立 skill）"
fi
pass "契约7: references/brainstorm-guide.md 已删除（brainstorm 抽离为独立 skill）"

# ════════════════════════════════════════════════════════════════════════════
# 契约 8：deep-design-guide.md 不存在（已被 brainstorm-guide.md 替代）
# ════════════════════════════════════════════════════════════════════════════

DEEP_DESIGN_GUIDE="$REFERENCES_DIR/deep-design-guide.md"
if [[ -f "$DEEP_DESIGN_GUIDE" ]]; then
    fail "契约8: references/deep-design-guide.md 仍然存在（应已改名为 brainstorm-guide.md）"
fi
pass "契约8: references/deep-design-guide.md 已不存在（改名完成）"

# ════════════════════════════════════════════════════════════════════════════
# 契约 9：SKILL.md 引用一致 — 含 Skill: "autopilot-brainstorm" 字面字符串 且 不含 brainstorm-guide.md
# ════════════════════════════════════════════════════════════════════════════

if grep -q "deep-design-guide\.md" "$SKILL_FILE"; then
    fail "契约9: SKILL.md 仍含 deep-design-guide.md 引用（应已删除）"
fi
pass "契约9a: SKILL.md 不再含 deep-design-guide.md 引用"

# 正向验证：SKILL.md 必须含 Skill: "autopilot-brainstorm" 委托字面字符串
if ! grep -q 'Skill: "autopilot-brainstorm"' "$SKILL_FILE"; then
    fail "契约9: SKILL.md 不含 Skill: \"autopilot-brainstorm\" 字面字符串（应委托 brainstorm skill）"
fi
pass "契约9b: SKILL.md 含 Skill: \"autopilot-brainstorm\" 委托字符串"

# 负向验证：SKILL.md 不得含 brainstorm-guide.md（已删除，新 skill 取代）
if grep -q "brainstorm-guide\.md" "$SKILL_FILE"; then
    fail "契约9: SKILL.md 仍含 brainstorm-guide.md 引用（应已删除，使用 skill 委托替代）"
fi
pass "契约9c: SKILL.md 不含 brainstorm-guide.md 引用（引用一致性通过）"

# ════════════════════════════════════════════════════════════════════════════
# 契约 10：autopilot-brainstorm/SKILL.md 存在且含 <HARD-GATE> 字符串
# ════════════════════════════════════════════════════════════════════════════

BRAINSTORM_SKILL_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot-brainstorm/SKILL.md"
if [[ ! -f "$BRAINSTORM_SKILL_FILE" ]]; then
    fail "契约10: plugins/autopilot/skills/autopilot-brainstorm/SKILL.md 不存在（应已创建独立 brainstorm skill）"
fi
pass "契约10a: autopilot-brainstorm/SKILL.md 存在"

if ! grep -q '<HARD-GATE>' "$BRAINSTORM_SKILL_FILE"; then
    fail "契约10: autopilot-brainstorm/SKILL.md 不含 <HARD-GATE> 字符串（强语言标识必须存在）"
fi
pass "契约10b: autopilot-brainstorm/SKILL.md 含 <HARD-GATE> 字符串"

# ════════════════════════════════════════════════════════════════════════════
# 契约 11：版本一致 v3.33.0（plugin.json + marketplace.json + CLAUDE.md 三处）
# ════════════════════════════════════════════════════════════════════════════

# 11a: plugin.json
plugin_version=$(grep '"version"' "$PLUGIN_JSON" \
    | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' \
    | head -1)
if [[ "$plugin_version" != "$TARGET_VERSION" ]]; then
    fail "契约11: plugin.json 版本 '$plugin_version' != 期望 '$TARGET_VERSION'"
fi
pass "契约11a: plugin.json 版本 = $TARGET_VERSION"

# 11b: marketplace.json autopilot 条目
marketplace_version=$(python3 -c "
import json
data = json.load(open('$MARKETPLACE_JSON'))
plugins = data if isinstance(data, list) else data.get('plugins', [])
for p in plugins:
    if p.get('name') == 'autopilot':
        print(p.get('version', ''))
        break
" 2>/dev/null || true)

[[ -n "$marketplace_version" ]] || fail "契约11: marketplace.json 中找不到 autopilot 条目的 version 字段"
if [[ "$marketplace_version" != "$TARGET_VERSION" ]]; then
    fail "契约11: marketplace.json autopilot 版本 '$marketplace_version' != 期望 '$TARGET_VERSION'"
fi
pass "契约11b: marketplace.json autopilot 版本 = $TARGET_VERSION"

# 11c: CLAUDE.md 插件索引表
if ! grep -E "autopilot" "$CLAUDE_MD" | grep -qE "v${TARGET_VERSION}|${TARGET_VERSION}"; then
    fail "契约11: CLAUDE.md 插件索引表 autopilot 行未找到版本 v${TARGET_VERSION}"
fi
pass "契约11c: CLAUDE.md 插件索引表 autopilot 行版本 = v${TARGET_VERSION}"

# 11d: 三处版本完全一致
if [[ "$plugin_version" != "$marketplace_version" ]]; then
    fail "契约11: plugin.json($plugin_version) 与 marketplace.json($marketplace_version) 版本不一致"
fi
pass "契约11d: 三处版本号一致 (${TARGET_VERSION})"

# ════════════════════════════════════════════════════════════════════════════
echo "[OK ] R9 brainstorm-default — 全部断言通过（11 个核心契约验收完毕）"
exit 0
