#!/usr/bin/env bash
# acceptance test: autopilot doctor Dim 13 约束守卫（场景 5）
#
# 设计契约（黑盒视角，不读 SKILL.md/lib.sh 实现）：
#   工程约束元验证：
#     - SKILL.md ≤ 664 行（净减或持平）
#     - 零新 skill / 零新 gate / 零新 stop-hook §段
#     - 8 bash 函数纯 bash 无外部运行时（node/python/npx/cargo/go run）
#     - 新增函数遵循三态约定 + DIM 字面量闭集
#
# 覆盖验收场景（场景 5，5 谓词，每条 ≥1 硬断言）：
#   约束守卫.P1：SKILL.md 行数 ≤ 664
#   约束守卫.P2：零新 skill（plugins/autopilot/skills/ 无新目录）
#   约束守卫.P3：零新 gate（stop-hook git diff 无 § 新增）
#   约束守卫.P4：8 bash 函数纯 bash 无外部运行时
#   约束守卫.P5：新增函数三态约定 + DIM 字面量闭集
#
# 运行：bash ai-obs-constraint-guard.acceptance.test.sh

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
LIB_SH="$REPO_ROOT/plugins/autopilot/scripts/lib.sh"
STOP_HOOK="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"
SKILLS_DIR="$REPO_ROOT/plugins/autopilot/skills"

PASS_COUNT=0
FAIL_COUNT=0

# 设计文档锚定的基线行数（变更前）
SKILL_BASELINE=664

# ═══════════════════════════════════════════════════════════════
# P1: SKILL.md 行数 ≤ 664
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P1: SKILL.md 行数 ≤ $SKILL_BASELINE ──"

if [[ -f "$SKILL_MD" ]]; then
    SKILL_WC=$(wc -l < "$SKILL_MD" | tr -d ' ')
    if [[ "$SKILL_WC" -le "$SKILL_BASELINE" ]]; then
        echo "  PASS  P1: SKILL.md 行数=$SKILL_WC ≤ ${SKILL_BASELINE}（净减或持平）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P1: SKILL.md 行数=$SKILL_WC > ${SKILL_BASELINE}（约束守卫违反）"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  P1: SKILL.md 不存在"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# P2: 零新 skill（plugins/autopilot/skills/ 无新目录）
# 用 git diff HEAD 检测新增 skill 目录
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P2: 零新 skill（git diff 新增 skill 目录）──"

if [[ -d "$SKILLS_DIR" ]]; then
    # git diff 检测新增（A）skill 目录
    # 既有 skill 集合：autopilot / autopilot-doctor / autopilot-brainstorm / autopilot-commit / autopilot-project
    NEW_SKILL_DIRS=$(git -C "$REPO_ROOT" diff --diff-filter=A --name-only HEAD 2>/dev/null \
        | grep -E '^plugins/autopilot/skills/[^/]+/$' \
        | awk -F/ '{print $5}' | sort -u || echo "")
    # grep -c 无匹配 rc=1 stdout="0"，避免 || echo 0 拼接陷阱
    NEW_COUNT=$(echo "$NEW_SKILL_DIRS" | grep -c '^.' 2>/dev/null)
    if [[ -z "$NEW_COUNT" ]]; then NEW_COUNT=0; fi
    if [[ "$NEW_COUNT" -eq 0 ]]; then
        echo "  PASS  P2: 零新 skill 目录（约束守卫 holds）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P2: 新增 skill 目录：$NEW_SKILL_DIRS"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    # 期望 doctor skill 存在（已存在，非新增）
    if [[ -d "$SKILLS_DIR/autopilot-doctor" ]]; then
        echo "  PASS  P2-b: autopilot-doctor skill 存在（基线 skill 不破）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P2-b: autopilot-doctor skill 缺失（基线破裂）"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  P2: skills 目录不存在"
    FAIL_COUNT=$((FAIL_COUNT + 2))
fi

# ═══════════════════════════════════════════════════════════════
# P3: 零新 gate（stop-hook git diff 无 § 新增段）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P3: 零新 gate（stop-hook 无 § 新增段）──"

if [[ -f "$STOP_HOOK" ]]; then
    # git diff 检测 stop-hook.sh 新增段（§符号）
    NEW_SECTIONS=$(git -C "$REPO_ROOT" diff HEAD -- plugins/autopilot/scripts/stop-hook.sh 2>/dev/null \
        | grep -E '^\+.*§[0-9]' \
        | grep -v '^+++' || echo "")
    NEW_SEC_COUNT=$(echo "$NEW_SECTIONS" | grep -c '^+' 2>/dev/null)
    if [[ -z "$NEW_SEC_COUNT" ]]; then NEW_SEC_COUNT=0; fi
    if [[ "$NEW_SEC_COUNT" -eq 0 ]]; then
        echo "  PASS  P3: stop-hook 无 § 新增段（零新 gate 约束 holds）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P3: stop-hook 新增 § 段："
        echo "        $NEW_SECTIONS"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  P3: stop-hook.sh 不存在"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# P4: 8 bash 函数纯 bash 无外部运行时
# assert: detect_tech_stack + detect_ai_observability + 6 _ai_*_detect
#         函数体无 node/python/npx/cargo/go run
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P4: 8 bash 函数纯 bash 无外部运行时 ──"

if [[ -f "$LIB_SH" ]]; then
    # 抽取 8 函数体（用 awk 按 `^<funcname>()` 起到 `^}` 止）
    FUNCS_TO_CHECK=(
        detect_tech_stack
        detect_ai_observability
        _ai_struct_log_detect
        _ai_log_rotation_detect
        _ai_cli_diagnostic_detect
        _ai_health_json_detect
        _ai_cache_clean_detect
        _ai_debug_switch_detect
    )

    PURITY_OK=1
    PURITY_VIOLATIONS=""
    for fn in "${FUNCS_TO_CHECK[@]}"; do
        # 提取函数体
        FN_BODY=$(awk -v fn="$fn" '
            $0 ~ "^"fn"[[:space:]]*\\(\\)" {capture=1}
            capture {print}
            capture && /^}/ {capture=0}
        ' "$LIB_SH" 2>/dev/null)

        if [[ -z "$FN_BODY" ]]; then
            # 函数未定义（contract 未实现）— 不算纯度违规，P5 兜底
            continue
        fi

        # 禁词正则（node/python/npx/cargo/go run 调用）
        # 排除注释行（# 开头）
        # 命令调用检测：node/python/npx/cargo 前是分隔符后跟空格+非=参数（排除 node=false 变量赋值/primary="node" 字符串）
        VIOL=$(echo "$FN_BODY" | grep -vE '^\s*#' | grep -E '(^|[[:space:];|])(node|python3?|npx|cargo)[[:space:]]+[^=]|go[[:space:]]+run' || true)
        if [[ -n "$VIOL" ]]; then
            PURITY_OK=0
            PURITY_VIOLATIONS="$PURITY_VIOLATIONS | $fn: $VIOL"
        fi
    done

    if [[ "$PURITY_OK" -eq 1 ]]; then
        echo "  PASS  P4: 8 bash 函数纯 bash 无外部运行时依赖（约束守卫 holds）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P4: 函数含外部运行时调用：$PURITY_VIOLATIONS"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  P4: lib.sh 不存在"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# P5: 新增函数遵循三态约定 + DIM 字面量闭集
# assert: 8 新函数源码 + stdout 信号
#         每函数含 return 0/return 1/return 2 三态
#         ≥1 处 echo "AI-OBS-<DIM>-<STATE>:" 且 <DIM> ∈ 闭集
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P5: 新增函数三态约定 + DIM 字面量闭集 ──"

if [[ -f "$LIB_SH" ]]; then
    # 设计契约 C1 DIM 字面量闭集
    DIM_CLOSURE="STRUCT-LOG|LOG-ROTATION|CLI-DIAGNOSTIC|HEALTH-JSON|CACHE-CLEAN|DEBUG-SWITCH"
    STATE_CLOSURE="PASS|NA|MISSING|PARTIAL"

    # 6 _ai_*_detect 函数（detect_tech_stack / detect_ai_observability 无 DIM 信号）
    TRI_OK=1
    DIM_OK=1
    TRI_VIOLATIONS=""
    DIM_VIOLATIONS=""

    AI_FUNCS=(
        _ai_struct_log_detect
        _ai_log_rotation_detect
        _ai_cli_diagnostic_detect
        _ai_health_json_detect
        _ai_cache_clean_detect
        _ai_debug_switch_detect
    )

    for fn in "${AI_FUNCS[@]}"; do
        FN_BODY=$(awk -v fn="$fn" '
            $0 ~ "^"fn"[[:space:]]*\\(\\)" {capture=1}
            capture {print}
            capture && /^}/ {capture=0}
        ' "$LIB_SH" 2>/dev/null)

        if [[ -z "$FN_BODY" ]]; then
            TRI_VIOLATIONS="$TRI_VIOLATIONS | $fn 未定义"
            TRI_OK=0
            continue
        fi

        # 三态判定：函数体必含 return 1/2 至少一种（自门控/warn）；rc=0 由 P5-b DIM 信号间接覆盖
        # Mutation-Survival：不能只断 rc=0，必须出现 rc=1 或 rc=2 至少一种
        HAS_R1=$(echo "$FN_BODY" | grep -cE 'return[[:space:]]+1' || true)
        HAS_R2=$(echo "$FN_BODY" | grep -cE 'return[[:space:]]+2' || true)
        if [[ "$HAS_R1" -eq 0 && "$HAS_R2" -eq 0 ]]; then
            # 至少存在 rc=1 或 rc=2 之一（自门控/warn）
            TRI_OK=0
            TRI_VIOLATIONS="$TRI_VIOLATIONS | $fn 无 return 1/2（三态契约缺）"
        fi

        # DIM 字面量：函数体必含 echo "AI-OBS-<DIM>-<STATE>:"
        # 提取所有 AI-OBS- 信号
        SIGNAL_HITS=$(echo "$FN_BODY" | grep -oE "AI-OBS-($DIM_CLOSURE)-($STATE_CLOSURE)" || true)
        if [[ -z "$SIGNAL_HITS" ]]; then
            DIM_OK=0
            DIM_VIOLATIONS="$DIM_VIOLATIONS | $fn 无闭集内 AI-OBS-<DIM>-<STATE>: 信号"
        fi
    done

    if [[ "$TRI_OK" -eq 1 ]]; then
        echo "  PASS  P5-a: 6 _ai_*_detect 函数三态约定（return 1/2 至少一种）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P5-a: 三态约定违反：$TRI_VIOLATIONS"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    if [[ "$DIM_OK" -eq 1 ]]; then
        echo "  PASS  P5-b: 6 _ai_*_detect 函数 DIM 字面量闭集（6 客观维各一）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P5-b: DIM 字面量违反：$DIM_VIOLATIONS"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    # Mutation-Survival：闭集外 DIM 字面量必须不存在（如 DIM=HUMAN-OBS、USER-FEEDBACK 等非法）
    # 注：lib.sh 全文检测（不局限函数体内），grep 出的 AI-OBS- 信号必须全部命中闭集
    # DIM 提取：用闭集 STATE 正向匹配（避免抓注释/前缀/含连字符 DIM 误拆）
    INVALID_DIM=$(grep -oE "AI-OBS-[A-Z-]+-($STATE_CLOSURE)" "$LIB_SH" 2>/dev/null \
        | sed -E "s/^AI-OBS-//; s/-($STATE_CLOSURE)\$//" | sort -u \
        | grep -vE "^($DIM_CLOSURE)\$" || true)
    if [[ -z "$INVALID_DIM" ]]; then
        echo "  PASS  P5-c: lib.sh 全文 AI-OBS- DIM 字面量全部在闭集内（无非法 DIM）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P5-c: lib.sh 含闭集外 DIM 字面量：$INVALID_DIM"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    # STATE 字面量闭集（I2 修复）
    # STATE 提取：用闭集 DIM 正向匹配（避免 CACHE-CLEAN 含连字符 DIM 被拆成 STATE=CLEAN）
    INVALID_STATE=$(grep -oE "AI-OBS-($DIM_CLOSURE)-[A-Z]+" "$LIB_SH" 2>/dev/null \
        | sed -E "s/^AI-OBS-($DIM_CLOSURE)-//" | sort -u \
        | grep -vE "^($STATE_CLOSURE)\$" || true)
    if [[ -z "$INVALID_STATE" ]]; then
        echo "  PASS  P5-d: lib.sh 全文 AI-OBS- STATE 字面量全部在闭集内（无非法 STATE）"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  P5-d: lib.sh 含闭集外 STATE 字面量：$INVALID_STATE"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo "  FAIL  P5: lib.sh 不存在"
    FAIL_COUNT=$((FAIL_COUNT + 4))
fi

# ── 汇总 ──────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "  PASS: $PASS_COUNT    FAIL: $FAIL_COUNT"
echo "════════════════════════════════════════"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo "RESULT: FAIL (约束守卫违反：SKILL 行数/新 skill/新 gate/bash 纯度/三态闭集)"
    exit 1
fi

echo "RESULT: PASS (约束守卫 5 谓词 + DIM/STATE 字面量闭集 holds)"
exit 0
