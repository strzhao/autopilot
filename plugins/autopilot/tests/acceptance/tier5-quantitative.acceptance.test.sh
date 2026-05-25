#!/usr/bin/env bash
# R-Tier5: 验证 autopilot v3.36.0 Tier 5 量化指标门禁 — OC-1..7 契约硬断言
# 红队测试 — 仅基于设计文档 + 契约规约编写，不读取任何蓝队实现
#
# 设计要点（来自 state.md「设计文档 / 契约规约 OC-1..7」）：
#   - Tier 5 入口锚定字符串「Tier 5: 量化指标门禁」(OC-1)
#   - 阈值常量 mutation=60 / coverage_line=80 / coverage_branch=70 (OC-2)
#   - autopilot-doctor 检测函数 detect_quantitative_tools (OC-3)
#   - tier5-report.json schema 含 survived_mutants / uncovered_critical / tier5_status (OC-4)
#   - 降级矩阵：smoke skipped / 双子项 null ⟹ na (OC-5)
#   - 不变量护栏：red-team-prompt.md 精简后仍保留极简引用，但 "Mental Mutation 5 问" ≤1 (OC-6)
#   - 命名一致性：使用业界术语 (OC-7)
#   - 版本同步 v3.36.0 + CI 行数守护上调到 615
#
# 测试质量铁律：不允许"宽容跳过"，每个断言失败必须 exit 1
# 注：不用 -e（grep -c 无匹配返回 1 会误触发退出，断言失败由 _log_fail + 末尾 exit 1 统一兜底）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# ── 关键路径 ─────────────────────────────────────────────────────────────────
SKILL_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/SKILL.md"
QM_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/quantitative-metrics.md"
DOCTOR_SKILL="$REPO_ROOT/plugins/autopilot/skills/autopilot-doctor/SKILL.md"
DOCTOR_DIR="$REPO_ROOT/plugins/autopilot/skills/autopilot-doctor"
RED_PROMPT="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/red-team-prompt.md"
MUTATION_DOC="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/test-mutation-survival.md"
PLUGIN_JSON="$REPO_ROOT/plugins/autopilot/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
AUTOPILOT_README="$REPO_ROOT/plugins/autopilot/README.md"
CI_GUARD_TEST="$REPO_ROOT/plugins/autopilot/tests/acceptance/skill-references-consistency.acceptance.test.sh"

# ── 计数器 ───────────────────────────────────────────────────────────────────
PASSED=0
FAILED=0
FAILURES=()

# ── 辅助函数（本测试内部定义；不允许 warn 模式）─────────────────────────────
_log_pass() {
    local id="$1"; shift
    local desc="$*"
    echo "✓ $id $desc"
    PASSED=$((PASSED + 1))
}

_log_fail() {
    local id="$1"; shift
    local desc="$*"
    echo "✗ $id $desc" >&2
    FAILED=$((FAILED + 1))
    FAILURES+=("$id $desc")
}

# 断言：文件存在（前置条件）；失败直接 exit 1（不再进行后续断言无意义）
assert_file_exists() {
    local id="$1"
    local f="$2"
    if [[ -f "$f" ]]; then
        _log_pass "$id" "file exists: $f"
    else
        _log_fail "$id" "file MISSING: $f"
    fi
}

# 断言：grep -c 命中数 >= 阈值
# 用法：assert_grep_ge <id> <pattern> <file> <min_count> <desc>
assert_grep_ge() {
    local id="$1"
    local pattern="$2"
    local file="$3"
    local min="$4"
    local desc="$5"
    if [[ ! -f "$file" ]]; then
        _log_fail "$id" "$desc — 文件不存在: $file"
        return
    fi
    local count
    count=$(grep -c -- "$pattern" "$file" 2>/dev/null) || count=0
    # 防御：grep -c 单文件应输出单行；若多行则取第一行
    count=$(echo "$count" | head -1 | tr -d ' ')
    [[ -z "$count" ]] && count=0
    if [[ "$count" -ge "$min" ]]; then
        _log_pass "$id" "$desc (grep -c '$pattern' = $count >= $min)"
    else
        _log_fail "$id" "$desc (grep -c '$pattern' = $count < $min, file=$file)"
    fi
}

# 断言：grep -cE 命中数 >= 阈值
assert_grepE_ge() {
    local id="$1"
    local pattern="$2"
    local file="$3"
    local min="$4"
    local desc="$5"
    if [[ ! -f "$file" ]]; then
        _log_fail "$id" "$desc — 文件不存在: $file"
        return
    fi
    local count
    count=$(grep -cE -- "$pattern" "$file" 2>/dev/null) || count=0
    count=$(echo "$count" | head -1 | tr -d ' ')
    [[ -z "$count" ]] && count=0
    if [[ "$count" -ge "$min" ]]; then
        _log_pass "$id" "$desc (grep -cE '$pattern' = $count >= $min)"
    else
        _log_fail "$id" "$desc (grep -cE '$pattern' = $count < $min, file=$file)"
    fi
}

# 断言：grep -cE 命中数 <= 阈值
assert_grepE_le() {
    local id="$1"
    local pattern="$2"
    local file="$3"
    local max="$4"
    local desc="$5"
    if [[ ! -f "$file" ]]; then
        _log_fail "$id" "$desc — 文件不存在: $file"
        return
    fi
    local count
    count=$(grep -cE -- "$pattern" "$file" 2>/dev/null) || count=0
    count=$(echo "$count" | head -1 | tr -d ' ')
    [[ -z "$count" ]] && count=0
    if [[ "$count" -le "$max" ]]; then
        _log_pass "$id" "$desc (grep -cE '$pattern' = $count <= $max)"
    else
        _log_fail "$id" "$desc (grep -cE '$pattern' = $count > $max, file=$file)"
    fi
}

# 断言：wc -l 行数 <= 阈值
assert_wc_le() {
    local id="$1"
    local file="$2"
    local max="$3"
    local desc="$4"
    if [[ ! -f "$file" ]]; then
        _log_fail "$id" "$desc — 文件不存在: $file"
        return
    fi
    local lines
    lines=$(wc -l < "$file" | tr -d ' ')
    if [[ "$lines" -le "$max" ]]; then
        _log_pass "$id" "$desc (wc -l = $lines <= $max)"
    else
        _log_fail "$id" "$desc (wc -l = $lines > $max, file=$file)"
    fi
}

# 断言：wc -l 行数 < 阈值
assert_wc_lt() {
    local id="$1"
    local file="$2"
    local max="$3"
    local desc="$4"
    if [[ ! -f "$file" ]]; then
        _log_fail "$id" "$desc — 文件不存在: $file"
        return
    fi
    local lines
    lines=$(wc -l < "$file" | tr -d ' ')
    if [[ "$lines" -lt "$max" ]]; then
        _log_pass "$id" "$desc (wc -l = $lines < $max)"
    else
        _log_fail "$id" "$desc (wc -l = $lines >= $max, file=$file)"
    fi
}

# 断言：grep 在文件或目录（含子文件）中至少有一处命中
# 用于 OC-3 stryker.conf 可能在 SKILL.md 或 references/ 子目录
assert_grep_in_tree_ge() {
    local id="$1"
    local pattern="$2"
    local dir_or_file="$3"
    local min="$4"
    local desc="$5"
    local count
    if [[ -d "$dir_or_file" ]]; then
        count=$(grep -rc -- "$pattern" "$dir_or_file" 2>/dev/null | awk -F: '{s+=$NF} END{print s+0}')
    elif [[ -f "$dir_or_file" ]]; then
        count=$(grep -c -- "$pattern" "$dir_or_file" 2>/dev/null) || count=0
        count=$(echo "$count" | head -1 | tr -d ' ')
    else
        _log_fail "$id" "$desc — 路径不存在: $dir_or_file"
        return
    fi
    [[ -z "$count" ]] && count=0
    if [[ "$count" -ge "$min" ]]; then
        _log_pass "$id" "$desc (tree grep -c '$pattern' = $count >= $min)"
    else
        _log_fail "$id" "$desc (tree grep -c '$pattern' = $count < $min, path=$dir_or_file)"
    fi
}

echo "=========================================="
echo " R-Tier5 autopilot v3.36.0 Tier 5 量化门禁验收"
echo "=========================================="

# ─────────────────────────────────────────────────────────────────────────────
# 前置：所有关键文件存在
# ─────────────────────────────────────────────────────────────────────────────
assert_file_exists "T5pre.1" "$SKILL_FILE"
assert_file_exists "T5pre.2" "$QM_FILE"
assert_file_exists "T5pre.3" "$DOCTOR_SKILL"
assert_file_exists "T5pre.4" "$RED_PROMPT"
assert_file_exists "T5pre.5" "$MUTATION_DOC"
assert_file_exists "T5pre.6" "$PLUGIN_JSON"
assert_file_exists "T5pre.7" "$MARKETPLACE_JSON"
assert_file_exists "T5pre.8" "$CLAUDE_MD"
assert_file_exists "T5pre.9" "$CI_GUARD_TEST"

# ─────────────────────────────────────────────────────────────────────────────
# T5a: 入口锚定字符串（OC-1）
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- T5a: 入口锚定字符串（OC-1）---"

# T5a.1 SKILL.md 含字面 "Tier 5: 量化指标门禁"
assert_grep_ge "T5a.1" "Tier 5: 量化指标门禁" "$SKILL_FILE" 1 \
    "OC-1: SKILL.md 包含 'Tier 5: 量化指标门禁' 入口字符串"

# T5a.2 SKILL.md 中 Tier 0 / Tier 1 / Tier 3 / Tier 5 各自至少出现一次
assert_grep_ge "T5a.2a" "Tier 0" "$SKILL_FILE" 1 \
    "OC-1: SKILL.md 含 'Tier 0'（与 Tier 5 并列）"
assert_grep_ge "T5a.2b" "Tier 1" "$SKILL_FILE" 1 \
    "OC-1: SKILL.md 含 'Tier 1'（与 Tier 5 并列）"
assert_grep_ge "T5a.2c" "Tier 3" "$SKILL_FILE" 1 \
    "OC-1: SKILL.md 含 'Tier 3'（与 Tier 5 并列）"
assert_grep_ge "T5a.2d" "Tier 5" "$SKILL_FILE" 1 \
    "OC-1: SKILL.md 含 'Tier 5'"

# ─────────────────────────────────────────────────────────────────────────────
# T5b: 阈值常量声明（OC-2）— 必须三条独立行正则锚定
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- T5b: 阈值常量声明（OC-2）---"

assert_grepE_ge "T5b.1" '^mutation_threshold:[[:space:]]*60$' "$QM_FILE" 1 \
    "OC-2: quantitative-metrics.md 行首声明 'mutation_threshold: 60'"

assert_grepE_ge "T5b.2" '^coverage_line_threshold:[[:space:]]*80$' "$QM_FILE" 1 \
    "OC-2: quantitative-metrics.md 行首声明 'coverage_line_threshold: 80'"

assert_grepE_ge "T5b.3" '^coverage_branch_threshold:[[:space:]]*70$' "$QM_FILE" 1 \
    "OC-2: quantitative-metrics.md 行首声明 'coverage_branch_threshold: 70'"

# ─────────────────────────────────────────────────────────────────────────────
# T5c: 工具检测路径（OC-3）— autopilot-doctor 扩展
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- T5c: 工具检测路径（OC-3）---"

# T5c.1 doctor SKILL 含 detect_quantitative_tools 函数名
assert_grep_ge "T5c.1" "detect_quantitative_tools" "$DOCTOR_SKILL" 1 \
    "OC-3: autopilot-doctor SKILL.md 含 detect_quantitative_tools 函数标识"

# T5c.2 doctor SKILL.md 或 references/ 含 stryker.conf 字面（任一处即可）
assert_grep_in_tree_ge "T5c.2" "stryker.conf" "$DOCTOR_DIR" 1 \
    "OC-3: autopilot-doctor 区域含 stryker.conf 检测路径（SKILL.md 或 references/）"

# T5c.3 doctor SKILL 提及 npm install --save-dev @stryker-mutator/core 安装建议
assert_grep_in_tree_ge "T5c.3" "@stryker-mutator/core" "$DOCTOR_DIR" 1 \
    "OC-3: autopilot-doctor 含 '@stryker-mutator/core' 安装建议"

assert_grep_in_tree_ge "T5c.3b" "npm install --save-dev" "$DOCTOR_DIR" 1 \
    "OC-3: autopilot-doctor 含 'npm install --save-dev' 字面安装命令"

# ─────────────────────────────────────────────────────────────────────────────
# T5d: 不变量护栏（OC-6）— 防伪优化复活
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- T5d: 不变量护栏（OC-6）防伪优化复活 ---"

# T5d.1 red-team-prompt.md 中 "Mutation-Survival 自检铁律" 至少保留 1 处极简引用
#   设计 OC-6 + 知识库 [SKILL 优化极易劣化]：精简不能把整个铁律名删光
assert_grep_ge "T5d.1" "Mutation-Survival 自检铁律" "$RED_PROMPT" 1 \
    "OC-6: red-team-prompt.md 保留 'Mutation-Survival 自检铁律' 极简引用（不被精简误删）"

# T5d.2 "Mental Mutation 5 问" 或 "过 5 问" 命中 ≤ 1（铁律内容已被工具替代，禁止复活）
assert_grepE_le "T5d.2" "Mental Mutation 5 问|过 5 问" "$RED_PROMPT" 1 \
    "OC-6: red-team-prompt.md 'Mental Mutation 5 问' / '过 5 问' 字面命中 <= 1（防铁律复活）"

# T5d.3 SKILL.md 仍含 "复盘升级" 兜底字面（Tier 1.5 步骤 3 不变）
assert_grep_ge "T5d.3" "复盘升级" "$SKILL_FILE" 1 \
    "OC-6: SKILL.md 含 '复盘升级' 兜底（Tier 1.5 步骤 3）"

# ─────────────────────────────────────────────────────────────────────────────
# T5e: 版本同步（CLAUDE.md / plugin.json / marketplace.json / README.md）
# v3.36.2 改为动态读 plugin.json 作为基准，断言其他 3 处与之一致
# （避免硬编码盲区，参见 [2026-05-09] knowledge）
# ─────────────────────────────────────────────────────────────────────────────
echo ""
PLUGIN_VERSION=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$PLUGIN_JSON" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
echo "--- T5e: 版本同步 v${PLUGIN_VERSION:-UNKNOWN} ---"

if [[ -z "$PLUGIN_VERSION" ]]; then
    _log_fail "T5e.0" "无法从 plugin.json 读取版本号"
else
    # T5e.1 plugin.json 自身（恒成立，作为基准锚点）
    assert_grep_ge "T5e.1" "\"version\": \"$PLUGIN_VERSION\"" "$PLUGIN_JSON" 1 \
        "OC-T5e: plugin.json 含 \"version\": \"$PLUGIN_VERSION\""

    # T5e.2 marketplace.json 与 plugin.json 版本一致
    assert_grepE_ge "T5e.2" "\"version\"[[:space:]]*:[[:space:]]*\"${PLUGIN_VERSION//./\\.}\"" "$MARKETPLACE_JSON" 1 \
        "OC-T5e: marketplace.json 版本与 plugin.json 一致 ($PLUGIN_VERSION)"
    assert_grep_ge "T5e.2b" "autopilot" "$MARKETPLACE_JSON" 1 \
        "OC-T5e: marketplace.json 含 autopilot 条目"

    # T5e.3 CLAUDE.md 插件索引行含 v$PLUGIN_VERSION
    assert_grep_ge "T5e.3" "v$PLUGIN_VERSION" "$CLAUDE_MD" 1 \
        "OC-T5e: CLAUDE.md 插件索引含 v$PLUGIN_VERSION"

    # T5e.4 autopilot README.md 含 v$PLUGIN_VERSION
    if [[ -f "$AUTOPILOT_README" ]]; then
        assert_grep_ge "T5e.4" "v$PLUGIN_VERSION\|$PLUGIN_VERSION" "$AUTOPILOT_README" 1 \
            "OC-T5e: autopilot README.md 含 v$PLUGIN_VERSION"
    else
        _log_fail "T5e.4" "autopilot README.md 不存在: $AUTOPILOT_README"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# T5f: SKILL.md 行数 CI 守护上调到 615
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- T5f: CI 行数守护上调 615 ---"

# T5f.1 skill-references-consistency.acceptance.test.sh 含 615 阈值
assert_grep_ge "T5f.1" "615" "$CI_GUARD_TEST" 1 \
    "OC-T5f: CI 守护测试含阈值 615"

# T5f.2 SKILL.md 行数 < 615
assert_wc_lt "T5f.2" "$SKILL_FILE" 615 \
    "OC-T5f: SKILL.md 总行数 < 615 (CI 守护下限)"

# T5f.3 同时 CI 守护测试不应再硬编码旧阈值 600
#   防回退：旧 >=600 fail 文案应已上调
#   策略：grep "600" 命中 = 0（不应再有旧阈值字面）
# 注意：可能在注释/文案中保留历史信息，所以宽容到 <= 2 处历史引用，但 615 必须出现
#   优先用强约束：615 至少 1 次
assert_grep_ge "T5f.3" "615" "$CI_GUARD_TEST" 1 \
    "OC-T5f: CI 守护测试包含 615 阈值（v3.36 Tier 5 上调）"

# ─────────────────────────────────────────────────────────────────────────────
# T5g: 精简验证（S1）— test-mutation-survival.md ≤ 60 行 + 顶部仍引用降级清单
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- T5g: 精简验证（S1）---"

# T5g.1 test-mutation-survival.md 行数 ≤ 60（设计 ~50，留 10 行余量）
assert_wc_le "T5g.1" "$MUTATION_DOC" 60 \
    "OC-S1: test-mutation-survival.md 精简后 wc -l <= 60"

# T5g.2 顶部仍保留"工具不可用时降级清单"字面或类似引用
#   设计：保留为"工具不可用时降级清单"的核心
#   宽容匹配：降级 / fallback / 工具不可用 任一存在
assert_grepE_ge "T5g.2" "降级|fallback|工具不可用|tool.*unavail" "$MUTATION_DOC" 1 \
    "OC-S1: test-mutation-survival.md 保留'降级清单'语义引用（降级/fallback/工具不可用）"

# ─────────────────────────────────────────────────────────────────────────────
# T5h: tier5-report.json schema 双向语义（OC-4）
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- T5h: tier5-report.json schema（OC-4）双向语义 ---"

# T5h.1 schema 含 tier5_status 字段
assert_grep_ge "T5h.1" "tier5_status" "$QM_FILE" 1 \
    "OC-4: quantitative-metrics.md 含 tier5_status 字段"

# T5h.2 schema 含 survived_mutants 字段
assert_grep_ge "T5h.2" "survived_mutants" "$QM_FILE" 1 \
    "OC-4: quantitative-metrics.md 含 survived_mutants 字段"

# T5h.3 schema 含 uncovered_critical 字段
assert_grep_ge "T5h.3" "uncovered_critical" "$QM_FILE" 1 \
    "OC-4: quantitative-metrics.md 含 uncovered_critical 字段"

# T5h.4 含 auto-fix 字面（消费端契约）
assert_grep_ge "T5h.4" "auto-fix" "$QM_FILE" 1 \
    "OC-4: quantitative-metrics.md 含 'auto-fix' 字面（消费端契约）"

# T5h.5 含 "消费端" 字面（防设计文档单方向语义反模式）
assert_grep_ge "T5h.5" "消费端" "$QM_FILE" 1 \
    "OC-4: quantitative-metrics.md 含 '消费端' 字面（双向语义对偶）"

# ─────────────────────────────────────────────────────────────────────────────
# T5i: 降级矩阵（OC-5）
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- T5i: 降级矩阵（OC-5）---"

# T5i.1 含 smoke 跳过路径 — "smoke ... skipped" 或 "skipped ... smoke"
assert_grepE_ge "T5i.1" "smoke.*skipped|skipped.*smoke" "$QM_FILE" 1 \
    "OC-5: quantitative-metrics.md 含 smoke 模式 skipped 路径"

# T5i.2 含 tier5_status: "na" 字面（双子项均 null → na）
assert_grep_ge "T5i.2" "\"na\"" "$QM_FILE" 1 \
    "OC-5: quantitative-metrics.md 含 'na' 字面（降级状态）"
assert_grep_ge "T5i.2b" "tier5_status" "$QM_FILE" 1 \
    "OC-5: quantitative-metrics.md 含 tier5_status 字段（降级矩阵关键）"

# T5i.3 含双子项 null 不变量描述（多种语义表达任一即可）
assert_grepE_ge "T5i.3" "(mutation\.tool == null && coverage\.tool == null)|双子项均.*null|两子项.*N/A|两子项.*null|双子项.*null" "$QM_FILE" 1 \
    "OC-5: quantitative-metrics.md 含'双子项均 null ⟹ na'不变量描述"

# ─────────────────────────────────────────────────────────────────────────────
# T5j: 工作流真实跑（如果时间允许）
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "--- T5j: 工作流真实跑 ---"

# T5j.1 跑 skill-references-consistency.acceptance.test.sh —
#   蓝队完成 T4.7 (阈值 600 → 615) 后应 PASS
if bash "$CI_GUARD_TEST" >/dev/null 2>&1; then
    _log_pass "T5j.1" "skill-references-consistency.acceptance.test.sh 在阈值 615 下 PASS"
else
    _log_fail "T5j.1" "skill-references-consistency.acceptance.test.sh FAIL（阈值未上调 / SKILL.md 超 615 / 其他）"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 汇总
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo " R-Tier5 汇总: PASSED=$PASSED  FAILED=$FAILED"
echo "=========================================="

if [[ $FAILED -gt 0 ]]; then
    echo ""
    echo "失败明细："
    for f in "${FAILURES[@]}"; do
        echo "   - $f"
    done
    echo ""
    echo "FAIL"
    exit 1
fi

echo "PASS"
exit 0
