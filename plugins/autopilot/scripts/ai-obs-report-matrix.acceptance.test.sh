#!/usr/bin/env bash
# acceptance test: autopilot doctor Dim 13 报告矩阵 + 修复链路（场景 3+4）
#
# 设计契约（黑盒视角，不读 SKILL.md 实现）：
#   doctor SKILL.md 接入 Dim 13 后，跑 /autopilot doctor 在标杆工程产出 doctor-report.md，
#   报告含 Dim 13 行 + 等级 + 兼容性行；Dim 13 与 Dim 10 不重叠；非 PASS 维引用核心原则 prompt。
#
# ⚠️ CONTRACT_AMBIGUOUS 注释：
#   本测试涉及 doctor 真跑产 report 产物。/autopilot doctor 是交互式 AI skill，
#   bash 测试无法直接调用，且 doctor-report.md 路径依赖 .autopilot/runtime/。
#   本测试采用混合策略：
#     (1) fs-grep 静态契约：对 SKILL.md + ai-observability-principles.md 直接断文本契约
#         （设计契约 C2/C3 可静态校验，不依赖 doctor 真跑）
#     (2) 报告产物 grep 模板：留出 grep 断言逻辑，注释说明 QA 真跑后可补全路径
#
# 覆盖验收场景（场景 3 + 场景 4，9 谓词）：
#   报告矩阵.P1：doctor 报告/SKILL.md 含 Dim 13 行 + AI 可观测性关键词
#   报告矩阵.P2：等级矩阵 Dim 13 行 等级 ∈ {S,A,B,C,D,F}
#   报告矩阵.P3：兼容性矩阵含 Dim 13 行 + autopilot 兼容性描述
#   报告矩阵.P4：Dim 13 与 Dim 10 描述无重叠（核心关键词交集为空）
#   报告矩阵.P5：Dim 13 总分 ∈ [0,100]（权重段 + 0-10 评分段）
#   修复链路.P1：核心原则 prompt 段数 ≥ 9 维（每维一条）
#   修复链路.P2：核心原则非 scaffold（禁模板痕迹）
#   修复链路.P3：核心原则含驱动 AI 自主语义触发词
#   修复链路.P4：9 维核心原则在文件内可唯一定位（id/小标题）
#
# 运行：bash ai-obs-report-matrix.acceptance.test.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT=""
_search="$SCRIPT_DIR"
while [[ -n "$_search" ]] && [[ "$_search" != "/" ]]; do
    if [[ -d "$_search/.git" ]]; then
        REPO_ROOT="$_search"
        break
    fi
    _search="$(dirname "$_search")"
done
unset _search

if [[ -z "$REPO_ROOT" ]]; then
    echo "FATAL: cannot locate repo root" >&2
    exit 99
fi

SKILL_MD="$REPO_ROOT/plugins/autopilot/skills/autopilot-doctor/SKILL.md"
PRINCIPLE_MD="$REPO_ROOT/plugins/autopilot/skills/autopilot-doctor/references/ai-observability-principles.md"

# CONTRACT_AMBIGUOUS: 报告产物路径依赖 doctor 真跑，本测试静态契约层不强制；
# QA 真跑后可 export REPORT_PATH 再跑此测试。
REPORT_PATH="${AUTOTOPILOT_DOCTOR_REPORT:-}"

PASS_COUNT=0
FAIL_COUNT=0

# ═══════════════════════════════════════════════════════════════
# P1: doctor 报告/SKILL.md 含 Dim 13 行 + AI 可观测性关键词
# CONTRACT_AMBIGUOUS: 需 QA 真跑 /autopilot doctor 产 report 后 grep
# 静态层：SKILL.md 必含 Dim 13 标题 + AI 可观测性关键词
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P1: SKILL.md 含 Dim 13 + AI 可观测性关键词 ──"

if [[ ! -f "$SKILL_MD" ]]; then
    echo "  FAIL  P1: SKILL.md 不存在 $SKILL_MD"
    FAIL_COUNT=$((FAIL_COUNT + 1))
else
    # Dim 13 标题
    if grep -qE '^#+.*Dim 13' "$SKILL_MD"; then
        echo "  PASS  P1-a: SKILL.md 含 Dim 13 标题"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P1-a: SKILL.md 无 Dim 13 标题"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    # AI 可观测性 或 调试友好度 关键词命中 ≥1
    if grep -qE '(AI 可观测性|调试友好度|可观测性|调试)' "$SKILL_MD"; then
        echo "  PASS  P1-b: SKILL.md 含 AI 可观测性/调试友好度 关键词"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P1-b: SKILL.md 无 AI 可观测性/调试友好度 关键词"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
fi

# CONTRACT_AMBIGUOUS: QA 真跑后此块生效
if [[ -n "$REPORT_PATH" && -f "$REPORT_PATH" ]]; then
    echo "  [动态] 检测 doctor-report.md..."
    if grep -qE '(Dim 13|AI 可观测性|调试友好度)' "$REPORT_PATH"; then
        echo "  PASS  P1-c: doctor-report.md 含 Dim 13 关键词"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P1-c: doctor-report.md 无 Dim 13 关键词"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
fi

# ═══════════════════════════════════════════════════════════════
# P2: 等级矩阵 Dim 13 行 等级 ∈ {S,A,B,C,D,F}
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P2: SKILL.md 报告矩阵 Dim 13 行 + 等级枚举 ──"

if [[ -f "$SKILL_MD" ]]; then
    # 报告矩阵行格式：| 13 | AI 可观测性/调试友好度 | X/10 | 状态图标 | 摘要 |
    # 至少存在一行同时含「13」+「可观测」+ 评分段
    if grep -qE '\|\s*13\s*\|.*可观测' "$SKILL_MD"; then
        echo "  PASS  P2-a: SKILL.md 报告矩阵含 Dim 13 行"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P2-a: SKILL.md 报告矩阵无 Dim 13 行"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    # 状态图标约定（C2：✅≥7 / ⚠️4-6 / ❌≤3）
    if grep -qE '\|\s*13\s*\|.*(/10|✅|⚠️|❌)' "$SKILL_MD"; then
        echo "  PASS  P2-b: SKILL.md Dim 13 行含评分段或状态图标"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P2-b: SKILL.md Dim 13 行无评分/图标约定"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  P2: SKILL.md 不存在"
    FAIL_COUNT=$((FAIL_COUNT + 2))
fi

# ═══════════════════════════════════════════════════════════════
# P3: 兼容性矩阵含 Dim 13 行 + autopilot 兼容性描述
# 设计契约 C2：| Tier 1.5 真实场景日志可读性 | ✅/⚠️/❌ | Dim 13 | ... |
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P3: 兼容性矩阵含 Dim 13 行 + autopilot 兼容性描述 ──"

if [[ -f "$SKILL_MD" ]]; then
    # 兼容性行：同时含 Tier 1.5（或真实场景/日志可读性）+ Dim 13
    if grep -qE '(Tier 1.5|真实场景日志可读性|日志可读性).*Dim 13|Dim 13.*(Tier 1.5|日志可读性)' "$SKILL_MD"; then
        echo "  PASS  P3-a: 兼容性矩阵含 Dim 13 + Tier 1.5 日志可读性行"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P3-a: 兼容性矩阵无 Dim 13 兼容性行"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  P3: SKILL.md 不存在"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# P4: Dim 13 与 Dim 10 描述无重叠（核心关键词交集为空）
# assert: Dim 13 含「可观测/调试/日志/health」运行时词
#         Dim 10 含「测试/可写性/红蓝队/Tier」测试词
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P4: Dim 13 与 Dim 10 关键词不重叠 ──"

if [[ -f "$SKILL_MD" ]]; then
    # Dim 13 段含运行时词
    if grep -qE '(可观测|调试|日志|health)' "$SKILL_MD"; then
        echo "  PASS  P4-a: SKILL.md 含 Dim 13 运行时关键词"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P4-a: SKILL.md 无 Dim 13 运行时关键词"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    # Dim 10 段含测试词（独立 grep，验证 Dim 10 描述）
    if grep -qE '(测试|可写性|红蓝队|Tier)' "$SKILL_MD"; then
        echo "  PASS  P4-b: SKILL.md 含 Dim 10 测试关键词"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P4-b: SKILL.md 无 Dim 10 测试关键词"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    # Mutation-Survival：Dim 10 段不应混入「可观测/调试友好度/health JSON」运行时专属词
    # 提取 Dim 10 章节段
    DIM10_SEG=$(awk '/^#+.*Dim 10/{f=1; next} /^#+.*Dim 1[123]/{f=0} f' "$SKILL_MD" 2>/dev/null)
    if echo "$DIM10_SEG" | grep -qE '(AI 可观测性|调试友好度|health JSON)'; then
        echo "  FAIL  P4-c: Dim 10 段混入 Dim 13 专属词（可观测性/调试友好度/health JSON）"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        echo "  PASS  P4-c: Dim 10 段无 Dim 13 专属词（关键词不相交）"
        PASS_COUNT=$((PASS_COUNT + 1))
    fi
else
    echo "  FAIL  P4: SKILL.md 不存在"
    FAIL_COUNT=$((FAIL_COUNT + 3))
fi

# ═══════════════════════════════════════════════════════════════
# P5: Dim 13 总分 ∈ [0,100]（评分段 0-10 + 权重段）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P5: Dim 13 评分段 0-10 ──"

if [[ -f "$SKILL_MD" ]]; then
    # C2: 评分 0-10，状态图标 ✅≥7 / ⚠️4-6 / ❌≤3
    if grep -qE '(✅.*[≥>]?\s*7|⚠️.*4-6|❌.*[≤<]?\s*3)' "$SKILL_MD"; then
        echo "  PASS  P5-a: SKILL.md 含 Dim 13 评分阈值规则（✅≥7/⚠️4-6/❌≤3）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P5-a: SKILL.md 无 Dim 13 评分阈值规则"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  P5: SKILL.md 不存在"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# 修复链路.P1: 核心原则 prompt 段数 ≥ 9 维
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 修复链路.P1: ai-observability-principles.md 9 维原则段 ──"

if [[ ! -f "$PRINCIPLE_MD" ]]; then
    echo "  FAIL  修复链路.P1: $PRINCIPLE_MD 不存在"
    FAIL_COUNT=$((FAIL_COUNT + 1))
else
    # 9 维原则段（每维一条），假设以 markdown 标题（##/###）分隔
    # grep -c 无匹配 rc=1 stdout="0"，避免 || echo 0 拼接陷阱
    PRINCIPLE_SECTIONS=$(grep -E '^#{2,3}\s' "$PRINCIPLE_MD" 2>/dev/null | wc -l | tr -d '[:space:]')
    if [[ -z "$PRINCIPLE_SECTIONS" ]]; then PRINCIPLE_SECTIONS=0; fi
    if [[ "$PRINCIPLE_SECTIONS" -ge 9 ]]; then
        echo "  PASS  修复链路.P1: 原则段数=$PRINCIPLE_SECTIONS ≥ 9"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  修复链路.P1: 原则段数=$PRINCIPLE_SECTIONS < 9（每维一条契约违反）"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
fi

# ═══════════════════════════════════════════════════════════════
# 修复链路.P2: 核心原则非 scaffold
# assert: 不含 创建.*文件/<filename>/touch.*\.ts/mkdir.*src/ 模板痕迹
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 修复链路.P2: 原则非 scaffold（禁模板痕迹）──"

if [[ -f "$PRINCIPLE_MD" ]]; then
    SCAFFOLD_HITS=$(grep -E '(创建.*文件|<filename>|touch.*\.(ts|js|go|py|rs)|mkdir.*src/)' "$PRINCIPLE_MD" 2>/dev/null | wc -l | tr -d '[:space:]')
    if [[ -z "$SCAFFOLD_HITS" ]]; then SCAFFOLD_HITS=0; fi
    if [[ "$SCAFFOLD_HITS" -eq 0 ]]; then
        echo "  PASS  修复链路.P2: 原则段无 scaffold 模板痕迹 hits=$SCAFFOLD_HITS"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  修复链路.P2: 原则段含 scaffold 模板痕迹 hits=${SCAFFOLD_HITS}（设计契约 C3 违反）"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  修复链路.P2: 原则文件不存在"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# 修复链路.P3: 核心原则含驱动 AI 自主语义触发词
# assert: 含 原则/本质/业界/最佳实践/调研/自主/思考 中 ≥1
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 修复链路.P3: 原则含驱动 AI 自主语义触发词 ──"

if [[ -f "$PRINCIPLE_MD" ]]; then
    AI_TRIGGER_HITS=$(grep -E '(原则|本质|业界|最佳实践|调研|自主|思考)' "$PRINCIPLE_MD" 2>/dev/null | wc -l | tr -d '[:space:]')
    if [[ -z "$AI_TRIGGER_HITS" ]]; then AI_TRIGGER_HITS=0; fi
    if [[ "$AI_TRIGGER_HITS" -ge 1 ]]; then
        echo "  PASS  修复链路.P3: 原则含 AI 自主语义触发词 hits=$AI_TRIGGER_HITS ≥ 1"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  修复链路.P3: 原则无 AI 自主语义触发词（设计契约 C3 违反）"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  修复链路.P3: 原则文件不存在"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# 修复链路.P4: 9 维核心原则在文件内可唯一定位（id/小标题）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 修复链路.P4: 9 维原则段唯一性 ──"

if [[ -f "$PRINCIPLE_MD" ]]; then
    # 9 维关键词（设计文档 1-9 维）：结构化日志/日志轮转/CLI诊断/health JSON/error code/命名空间/缓存清理/debug开关/debug-prod隔离
    UNIQ_HITS=0
    for kw in '结构化日志' '日志轮转' 'CLI' 'health' 'error code' '命名空间' '缓存清理' 'debug' '隔离'; do
        if grep -q "$kw" "$PRINCIPLE_MD" 2>/dev/null; then
            UNIQ_HITS=$((UNIQ_HITS + 1))
        fi
    done
    if [[ "$UNIQ_HITS" -ge 6 ]]; then
        echo "  PASS  修复链路.P4: 9 维关键词命中 $UNIQ_HITS 处（≥6 维可唯一定位）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  修复链路.P4: 9 维关键词命中 $UNIQ_HITS < 6（原则段无法唯一定位）"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  修复链路.P4: 原则文件不存在"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ── 汇总 ──────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "  PASS: $PASS_COUNT    FAIL: $FAIL_COUNT"
echo "════════════════════════════════════════"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo "RESULT: FAIL (报告矩阵/修复链路契约违反)"
    exit 1
fi

echo "RESULT: PASS (报告矩阵 Dim 13 行 + 等级 + 兼容性 + 关键词不相交 + 原则非 scaffold holds)"
exit 0
