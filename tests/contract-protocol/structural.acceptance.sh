#!/usr/bin/env bash
# contract-protocol v3.24.0 — Tier 1.5 结构性验收测试（11 项）
# 红队测试 — 仅基于设计文档，不读蓝队实现代码
# 可独立执行：bash tests/contract-protocol/structural.acceptance.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SKILL_DIR="$REPO_ROOT/plugins/autopilot/skills/autopilot"
REFS_DIR="$SKILL_DIR/references"
SCRIPTS_DIR="$REPO_ROOT/plugins/autopilot/scripts"

pass_count=0
fail_count=0

pass() {
    echo "[PASS] C${1}: ${2}"
    pass_count=$((pass_count + 1))
}

fail() {
    echo "[FAIL] C${1}: ${2}" >&2
    fail_count=$((fail_count + 1))
    # 不立即 exit — 收集全部结果后统一报告
}

fail_hard() {
    echo "[FAIL] C${1}: ${2}" >&2
    echo ""
    echo "=========================================="
    echo " 结构性验收测试终止（前置条件不满足）"
    echo "=========================================="
    exit 1
}

echo "=========================================="
echo " contract-protocol v3.24.0 结构性验收测试"
echo " 共 11 项，全部必须 PASS"
echo "=========================================="
echo ""

# ── C1: contract-protocol.md 存在 + 至少 6 个 ## 章节 ──────────────────────────
# 设计：Annex A 有 6 个 ## 章节（1-6），加 # 顶级标题合计 ≥6 个 ## 行
PROTOCOL_FILE="$REFS_DIR/contract-protocol.md"
[[ -f "$PROTOCOL_FILE" ]] \
    || fail_hard "1" "contract-protocol.md 不存在: $PROTOCOL_FILE（前置条件失败，终止测试）"

section_count=$(grep -cE "^##? " "$PROTOCOL_FILE" || true)
if [[ "$section_count" -ge 6 ]]; then
    pass "1" "contract-protocol.md 存在 + 章节数 $section_count ≥ 6"
else
    echo "  实际章节数: $section_count"
    echo "  --- grep -E '^##? ' 输出 ---"
    grep -nE "^##? " "$PROTOCOL_FILE" || true
    echo "  ---"
    fail "1" "contract-protocol.md 章节数 $section_count < 6（期望 ≥ 6 个 ## 章节）"
fi

# ── C2: contract-checker-prompt.md 存在 + 含 JSON schema "pass": boolean ───────
# 设计：contract-checker-prompt.md 约 60 行，含 `"pass": boolean` 输出 schema
CHECKER_PROMPT="$REFS_DIR/contract-checker-prompt.md"
[[ -f "$CHECKER_PROMPT" ]] \
    || fail_hard "2" "contract-checker-prompt.md 不存在: $CHECKER_PROMPT（前置条件失败，终止测试）"

if grep -qE '"pass":\s*boolean' "$CHECKER_PROMPT"; then
    pass "2" "contract-checker-prompt.md 存在 + 含 '\"pass\": boolean' JSON schema"
else
    echo "  --- 文件前 30 行 ---"
    head -30 "$CHECKER_PROMPT" || true
    echo "  ---"
    fail "2" "contract-checker-prompt.md 缺少 '\"pass\": boolean' JSON 输出 schema（contract-checker 必须有结构化输出）"
fi

# ── C3: SKILL.md 含「步骤 2.5」和「contract-checker」字样 ─────────────────────
# 设计：SKILL.md Phase: implement 末尾新增「步骤 2.5: 契约自动校验」约 15 行
SKILL_MD="$SKILL_DIR/SKILL.md"
[[ -f "$SKILL_MD" ]] \
    || fail_hard "3" "SKILL.md 不存在: $SKILL_MD（前置条件失败，终止测试）"

c3_hit=0
if grep -qE "步骤 2\.5|步骤2\.5" "$SKILL_MD"; then
    c3_hit=$((c3_hit + 1))
fi
if grep -q "contract-checker" "$SKILL_MD"; then
    c3_hit=$((c3_hit + 1))
fi

if [[ "$c3_hit" -ge 2 ]]; then
    pass "3" "SKILL.md 含「步骤 2.5」和「contract-checker」（两个关键 token 均命中）"
elif [[ "$c3_hit" -eq 1 ]]; then
    echo "  命中数: $c3_hit / 2"
    echo "  --- grep '步骤 2.5|contract-checker' ---"
    grep -nE "步骤 2\.5|步骤2\.5|contract-checker" "$SKILL_MD" || echo "  (无命中)"
    echo "  ---"
    fail "3" "SKILL.md 仅命中 $c3_hit / 2 个关键 token（步骤 2.5 + contract-checker 必须同时存在）"
else
    echo "  --- grep '步骤 2.5|contract-checker' ---"
    grep -nE "步骤 2\.5|步骤2\.5|contract-checker" "$SKILL_MD" || echo "  (无命中)"
    echo "  ---"
    fail "3" "SKILL.md 缺少「步骤 2.5」和「contract-checker」（两者均未找到）"
fi

# ── C4: SKILL.md 不含维度数字硬编码 ──────────────────────────────────────────
# 设计：「6 维度」「7 维度」「{N}/6」「/6 维度」全部去除，改为「全部维度」
# 验证：grep 必须 0 命中
bad_dimension_count=$(grep -cE "[0-9]+\s*维度|N/[0-9]+|/[0-9]+\s*维度|\{N\}/[0-9]+|[0-9]+/[0-9]+\s*维度" "$SKILL_MD" || true)
if [[ "$bad_dimension_count" -eq 0 ]]; then
    pass "4" "SKILL.md 不含维度数字硬编码（grep -cE '[0-9]+\s*维度|...' = 0）"
else
    echo "  命中行数: $bad_dimension_count"
    echo "  --- 具体命中行 ---"
    grep -nE "[0-9]+\s*维度|N/[0-9]+|/[0-9]+\s*维度|\{N\}/[0-9]+|[0-9]+/[0-9]+\s*维度" "$SKILL_MD" || true
    echo "  ---"
    fail "4" "SKILL.md 仍含维度数字硬编码 $bad_dimension_count 处（期望 = 0，设计要求全改为'全部维度'）"
fi

# ── C5: state-file-guide.md 含 contract_required 字段说明 ─────────────────────
# 设计：state-file-guide.md 在「setup.sh 创建（AI 不修改）」块追加 contract_required 字段说明
STATE_GUIDE="$REFS_DIR/state-file-guide.md"
[[ -f "$STATE_GUIDE" ]] \
    || fail_hard "5" "state-file-guide.md 不存在: $STATE_GUIDE（前置条件失败，终止测试）"

if grep -q "contract_required" "$STATE_GUIDE"; then
    hit_count=$(grep -c "contract_required" "$STATE_GUIDE" || true)
    pass "5" "state-file-guide.md 含 contract_required 字段说明（共 $hit_count 处命中）"
else
    echo "  --- 文件末尾 30 行（字段说明通常在末尾附近）---"
    tail -30 "$STATE_GUIDE" || true
    echo "  ---"
    fail "5" "state-file-guide.md 缺少 contract_required 字段说明（设计要求追加到 setup.sh 创建字段列表）"
fi

# ── C6: setup.sh + lib.sh 共计至少 2 处 contract_required: true 写入 ──────────
# 设计文档：T3「跳过 lib.sh L313+ 的 create_project_qa_state_file」→ 实际 2 处写入
# （1 处 setup.sh 正常流程，1 处 lib.sh 正常 design→implement 流程）
LIB_SH="$SCRIPTS_DIR/lib.sh"
SETUP_SH="$SCRIPTS_DIR/setup.sh"
[[ -f "$LIB_SH" ]] || fail_hard "6" "lib.sh 不存在: $LIB_SH（前置条件失败，终止测试）"
[[ -f "$SETUP_SH" ]] || fail_hard "6" "setup.sh 不存在: $SETUP_SH（前置条件失败，终止测试）"

lib_count=$(grep -c "contract_required: true" "$LIB_SH" || true)
setup_count=$(grep -c "contract_required: true" "$SETUP_SH" || true)
total_writes=$((lib_count + setup_count))

if [[ "$total_writes" -ge 2 ]]; then
    pass "6" "setup.sh($setup_count) + lib.sh($lib_count) 共 $total_writes 处 contract_required: true 写入（≥ 2）"
else
    echo "  lib.sh  命中: $lib_count 处"
    echo "  setup.sh 命中: $setup_count 处"
    echo "  --- lib.sh grep contract_required ---"
    grep -n "contract_required" "$LIB_SH" || echo "  (无命中)"
    echo "  --- setup.sh grep contract_required ---"
    grep -n "contract_required" "$SETUP_SH" || echo "  (无命中)"
    echo "  ---"
    fail "6" "setup.sh + lib.sh contract_required: true 写入共 $total_writes 处，期望 ≥ 2（设计：lib.sh 至少 1 处 design→implement 流程 + setup.sh 至少 1 处）"
fi

# ── C7: plan-reviewer-prompt.md 维度 7 简洁（grep -A 5 后 ≤ 6 行）──────────────
# 设计：维度 7 仅 3 行，不含细分阈值，使用「≥91」二档
PLAN_REVIEWER="$REFS_DIR/plan-reviewer-prompt.md"
[[ -f "$PLAN_REVIEWER" ]] || fail_hard "7" "plan-reviewer-prompt.md 不存在（前置条件失败，终止测试）"

dim7_exists=$(grep -cE "7\..*契约完整性|7\.\s*\*\*契约" "$PLAN_REVIEWER" || true)
if [[ "$dim7_exists" -eq 0 ]]; then
    echo "  --- grep '7.*契约完整性' ---"
    grep -n "契约" "$PLAN_REVIEWER" || echo "  (无命中)"
    echo "  ---"
    fail "7" "plan-reviewer-prompt.md 缺少维度 7 契约完整性（期望含 '7. 契约完整性' 或类似标题）"
else
    dim7_line_count=$(grep -A 5 -E "7\..*契约完整性|7\.\s*\*\*契约" "$PLAN_REVIEWER" | wc -l | tr -d ' ')
    if [[ "$dim7_line_count" -le 6 ]]; then
        pass "7" "plan-reviewer-prompt.md 维度 7 存在且简洁（grep -A 5 共 $dim7_line_count 行 ≤ 6）"
    else
        echo "  实际行数: $dim7_line_count（期望 ≤ 6）"
        echo "  --- grep -A 5 维度 7 ---"
        grep -A 5 -E "7\..*契约完整性|7\.\s*\*\*契约" "$PLAN_REVIEWER" || true
        echo "  ---"
        fail "7" "plan-reviewer-prompt.md 维度 7 行数 $dim7_line_count > 6（设计要求仅 3 行，不含细分阈值）"
    fi
fi

# ── C8: red-team-prompt.md ^## ⚠️ 章节数 = 2（保持不变）─────────────────────
# 设计：红队加 1 条 bullet 到现有 ⚠️ 铁律章节，不新增 ⚠️ 章节，保持 ⚠️ 章节数 = 2
RED_TEAM="$REFS_DIR/red-team-prompt.md"
[[ -f "$RED_TEAM" ]] || fail_hard "8" "red-team-prompt.md 不存在（前置条件失败，终止测试）"

red_warning_count=$(grep -cE "^## ⚠️" "$RED_TEAM" || true)
if [[ "$red_warning_count" -eq 2 ]]; then
    pass "8" "red-team-prompt.md ## ⚠️ 章节数 = 2（保持原有，未新增章节）"
else
    echo "  实际 ## ⚠️ 章节数: $red_warning_count（期望 = 2）"
    echo "  --- grep '^## ⚠️' ---"
    grep -n "^## ⚠️" "$RED_TEAM" || echo "  (无命中)"
    echo "  ---"
    fail "8" "red-team-prompt.md ## ⚠️ 章节数 = $red_warning_count，期望 = 2（保持原有，禁止新增 ⚠️ 章节）"
fi

# ── C9: blue-team-prompt.md ^## ⚠️ 章节数 = 0（保持不变）─────────────────────
# 设计：蓝队加 1 条 rule 到 ## 工作规则 末尾，不新增 ⚠️ 章节，保持 ⚠️ 章节数 = 0
BLUE_TEAM="$REFS_DIR/blue-team-prompt.md"
[[ -f "$BLUE_TEAM" ]] || fail_hard "9" "blue-team-prompt.md 不存在（前置条件失败，终止测试）"

blue_warning_count=$(grep -cE "^## ⚠️" "$BLUE_TEAM" || true)
if [[ "$blue_warning_count" -eq 0 ]]; then
    pass "9" "blue-team-prompt.md ## ⚠️ 章节数 = 0（保持原有，未新增章节）"
else
    echo "  实际 ## ⚠️ 章节数: $blue_warning_count（期望 = 0）"
    echo "  --- grep '^## ⚠️' ---"
    grep -n "^## ⚠️" "$BLUE_TEAM" || echo "  (无命中)"
    echo "  ---"
    fail "9" "blue-team-prompt.md ## ⚠️ 章节数 = $blue_warning_count，期望 = 0（禁止在蓝队 prompt 新增 ⚠️ 章节）"
fi

# ── C10: red-team-prompt.md 含 CONTRACT_AMBIGUOUS + 不含 EXPECTED_FIELD_NAME_FROM_CONTRACT ─
# 设计：红队 prompt 加「CONTRACT_AMBIGUOUS: <歧义点>」机制；明确禁止 EXPECTED_FIELD_NAME_FROM_CONTRACT 占位符
# 两项必须同时满足，任意一项失败即 FAIL

c10_pass=true

if grep -q "CONTRACT_AMBIGUOUS" "$RED_TEAM"; then
    echo "  [INFO] red-team-prompt.md 含 CONTRACT_AMBIGUOUS ✓"
else
    echo "  [INFO] red-team-prompt.md 缺少 CONTRACT_AMBIGUOUS"
    c10_pass=false
fi

if grep -q "EXPECTED_FIELD_NAME_FROM_CONTRACT" "$RED_TEAM"; then
    echo "  --- grep EXPECTED_FIELD_NAME_FROM_CONTRACT (必须为 0 命中) ---"
    grep -n "EXPECTED_FIELD_NAME_FROM_CONTRACT" "$RED_TEAM" || true
    echo "  ---"
    c10_pass=false
    echo "  [INFO] red-team-prompt.md 含 EXPECTED_FIELD_NAME_FROM_CONTRACT（v1 占位符复发！）"
fi

if [[ "$c10_pass" == "true" ]]; then
    pass "10" "red-team-prompt.md 含 CONTRACT_AMBIGUOUS + 不含 EXPECTED_FIELD_NAME_FROM_CONTRACT（v1 占位符干净）"
else
    echo "  --- grep CONTRACT_AMBIGUOUS ---"
    grep -n "CONTRACT_AMBIGUOUS" "$RED_TEAM" || echo "  (无命中)"
    echo "  ---"
    fail "10" "red-team-prompt.md C10 双检失败：必须含 CONTRACT_AMBIGUOUS 且不含 EXPECTED_FIELD_NAME_FROM_CONTRACT"
fi

# ── C11: 4 处版本号字符串全部 = 3.24.0 ────────────────────────────────────────
# 设计：plugin.json / marketplace.json / 根 CLAUDE.md / plugins/autopilot/README.md 四处同步
TARGET_VERSION="3.24.0"

PLUGIN_JSON="$REPO_ROOT/plugins/autopilot/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"
ROOT_CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
AUTOPILOT_README="$REPO_ROOT/plugins/autopilot/README.md"

c11_pass=true
c11_details=()

# plugin.json
if [[ ! -f "$PLUGIN_JSON" ]]; then
    c11_pass=false
    c11_details+=("plugin.json 不存在: $PLUGIN_JSON")
elif grep -q "\"version\".*\"$TARGET_VERSION\"" "$PLUGIN_JSON" || grep -q "\"$TARGET_VERSION\"" "$PLUGIN_JSON"; then
    c11_details+=("plugin.json ✓ 含 $TARGET_VERSION")
else
    actual=$(grep -oE '"version":\s*"[^"]+"' "$PLUGIN_JSON" | head -1 || echo "未找到 version 字段")
    c11_pass=false
    c11_details+=("plugin.json ✗ 实际: $actual（期望: $TARGET_VERSION）")
fi

# marketplace.json — autopilot 条目
if [[ ! -f "$MARKETPLACE_JSON" ]]; then
    c11_pass=false
    c11_details+=("marketplace.json 不存在: $MARKETPLACE_JSON")
elif grep -q "$TARGET_VERSION" "$MARKETPLACE_JSON"; then
    # 额外检查 autopilot 条目确实含目标版本（防止其他插件版本误命中）
    if python3 -c "
import json, sys
data = json.load(open('$MARKETPLACE_JSON'))
plugins = data if isinstance(data, list) else data.get('plugins', [data])
found = [p for p in plugins if p.get('name') == 'autopilot' and p.get('version') == '$TARGET_VERSION']
sys.exit(0 if found else 1)
" 2>/dev/null; then
        c11_details+=("marketplace.json autopilot 条目 ✓ $TARGET_VERSION")
    else
        # fallback: 宽松检查（如 JSON 结构不同）
        if grep -A5 '"autopilot"' "$MARKETPLACE_JSON" | grep -q "$TARGET_VERSION"; then
            c11_details+=("marketplace.json autopilot 附近含 $TARGET_VERSION ✓（宽松检查）")
        else
            actual_ver=$(grep -oE '"version":\s*"[^"]+"' "$MARKETPLACE_JSON" | head -1 || echo "未找到")
            c11_pass=false
            c11_details+=("marketplace.json autopilot 条目 ✗ 实际: $actual_ver（期望: $TARGET_VERSION）")
        fi
    fi
else
    actual_ver=$(grep -oE '"version":\s*"[^"]+"' "$MARKETPLACE_JSON" | head -1 || echo "未找到")
    c11_pass=false
    c11_details+=("marketplace.json ✗ 不含 $TARGET_VERSION，实际: $actual_ver")
fi

# 根 CLAUDE.md — 插件索引表
if [[ ! -f "$ROOT_CLAUDE_MD" ]]; then
    c11_pass=false
    c11_details+=("根 CLAUDE.md 不存在")
elif grep -q "v$TARGET_VERSION" "$ROOT_CLAUDE_MD" || grep -q "$TARGET_VERSION" "$ROOT_CLAUDE_MD"; then
    c11_details+=("根 CLAUDE.md ✓ 含 v$TARGET_VERSION")
else
    actual_ver=$(grep -oE "v[0-9]+\.[0-9]+\.[0-9]+" "$ROOT_CLAUDE_MD" | grep "autopilot" -A1 | head -1 || grep -oE "v3\.[0-9]+\.[0-9]+" "$ROOT_CLAUDE_MD" | head -1 || echo "未找到")
    c11_pass=false
    c11_details+=("根 CLAUDE.md ✗ 实际: $actual_ver（期望: v$TARGET_VERSION）")
fi

# plugins/autopilot/README.md
if [[ ! -f "$AUTOPILOT_README" ]]; then
    c11_pass=false
    c11_details+=("plugins/autopilot/README.md 不存在")
elif grep -q "v$TARGET_VERSION" "$AUTOPILOT_README" || grep -q "$TARGET_VERSION" "$AUTOPILOT_README"; then
    c11_details+=("plugins/autopilot/README.md ✓ 含 v$TARGET_VERSION")
else
    actual_ver=$(grep -oE "v3\.[0-9]+\.[0-9]+" "$AUTOPILOT_README" | head -1 || echo "未找到")
    c11_pass=false
    c11_details+=("plugins/autopilot/README.md ✗ 实际: $actual_ver（期望: v$TARGET_VERSION）")
fi

echo "  C11 版本号检查明细："
for detail in "${c11_details[@]}"; do
    echo "    $detail"
done

if [[ "$c11_pass" == "true" ]]; then
    pass "11" "4 处版本号字符串全部 = $TARGET_VERSION（plugin.json / marketplace.json / 根 CLAUDE.md / autopilot README.md）"
else
    fail "11" "版本号 4 处未全部对齐到 $TARGET_VERSION（见上方明细）"
fi

# ── 最终汇总 ─────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo " 结构性验收测试汇总"
echo " 通过: $pass_count / $((pass_count + fail_count))"
echo " 失败: $fail_count"
echo "=========================================="

if [[ "$fail_count" -gt 0 ]]; then
    echo ""
    echo "存在 $fail_count 项失败，蓝队实现尚未完成或存在偏差。"
    exit 1
fi

echo ""
echo "全部 11 项结构性验收通过。可进行 functional-meta 元验证。"
exit 0
