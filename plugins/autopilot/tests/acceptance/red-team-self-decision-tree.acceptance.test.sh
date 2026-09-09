#!/usr/bin/env bash
# R_SELFDEC: 红队验收测试例外修改流程改造——双层决策树（证据门槛自决 + 证据不足才 AskUserQuestion）
# 红队测试 — 黑盒视角，仅基于设计契约（state.md 契约规约 C1-C9 + 验收场景 1-8 共 13 谓词 SSOT）编写，
#            绝不读取蓝队改后的 SKILL.md / auto-fix-phase.md / stop-hook.sh / contract-protocol.md /
#            anti-rationalization.md 工作区内容来凑断言（TDD 红灯；断言期望值全部来自设计文档契约字面）。
#
# 谓词映射（逐条 det-machine 谓词 → ≥1 硬断言，期望值字面量取自谓词 assert）：
#   场景1.P1 → 断言 1.1（自决锚点族 count >= 1）
#   场景1.P2 → 断言 1.2（留痕锚点族 count >= 1）
#   场景2.P1 → 断言 2.1（AskUserQuestion count >= 1）
#   场景2.P2 → 断言 2.2（升级条件锚点族 count >= 1）
#   场景3.P1 → 断言 3.1（旧「无条件必须先问用户」措辞族 count == 0）
#   场景4.P1 → 断言 4.1（自决族 ∧ AskUserQuestion 两值同时 >= 1）
#   场景5.P1 → 断言 5.1（四文件 git diff --numstat sum(deleted) >= sum(added)）
#   场景5.P2 → 断言 5.2（主 SKILL.md 单文件 deleted >= added）
#   场景6.P1 → 断言 6.1（acceptance_tests_tampered|TAMPER 于 stop-hook.sh count >= 1）
#   场景6.P2 → 断言 6.2（lock_acceptance_tests 于 stop-hook.sh count >= 1）
#   场景7.P1 → 断言 7.1（三类问题枚举 每词 file-count >= 1）
#   场景8.P2 → 断言 8.2（npm run lint / ShellCheck exit == 0）
#   场景8.P1 → 占位声明（run-all 全量回归由编排器 QA Tier 1 执行，本文件不覆盖——
#              本测试合流后即为 run-all 成员，若在测试内再跑 run-all 将无限递归；
#              对齐 p2-qa-loop 场景7.P1 既有先例，留 QA 真机判定）
#
# 契约映射（契约元素 ↔ 断言）：
#   C1  → 断言 C1.1/C1.2（SKILL.md 铁律段：红队铁律 / AI 自决 / 重锁 / references/auto-fix-phase.md /
#         证据链闭合 + AskUserQuestion 双层表述 + 默认禁改，段内行数 +0 由 5.2 单文件 numstat 兜底）
#   C2  → 断言 C2.1/C2.2（SKILL.md auto-fix 段同一行含新字面「证据链闭合」+ 保留字面，改写可证 kill no-op；
#         C7③ 旧表述「经用户确认」区域内清零）
#   C3  → 断言 C3.1/C3.2（stop-hook.sh §8.5.1 _tamper_reason 窗口含 三情形/AI 自决/AskUserQuestion/重锁/git checkout
#         + 结构不变量：acceptance_tests_tampered 调用、rc==2 双信号、decision:block、exit 0）
#   C4  → 断言 C4.1-C4.7（auto-fix-phase.md 铁律头段条件式 + §6 三情形/决策树/E1-E3/U1-U4/逐字锚点/
#         留痕格式/QA 报告区块转记 + 闭集语义 + §3 批量修复段关键词零改动 + 旧表述清零）
#   C5  → 断言 C5.1/C5.2（anti-rationalization.md 新反向条目含「证据」字面 + 无证据/证据不足条件）
#   C6  → 断言 C6.1-C6.3（lib.sh 两函数定义 + rc 语义注释 0/2/1 + 锁文件格式注释零改动）
#   C6 一致性 → 断言 C6.4（三情形定义字面在 auto-fix-phase.md 与 SKILL.md 引用行间一致）
#   C7  → 断言 C2.2 + C4.5 + C4.6（三处反向断言闭集：§6 旧单层表述 / 铁律头段 L4 同表述 / SKILL.md 经用户确认）
#   C8  → 断言 5.1/5.2（numstat 减行硬约束，从场景5 谓词口径独立实现）
#   C9  → 断言 C9.1（contract-protocol.md 逐字一致成文行：逐字推导 + 禁止推测 + 契约规约/验收场景）
#   C6b 行为断言（真跑 stop-hook 双向）→ 独立文件 red-team-trace-backstop.acceptance.test.sh
#
# Mutation-Survival 自检：每条断言均已过心智 No-op 检验——若蓝队改动未发生（旧文案/旧结构原样保留），
# 对应断言必 FAIL（新字面缺失 / 旧字面残留 / 计数不满足 / 行数净增 / lint 非 0）。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 优先 git 顶层（对暂存区位置和 target 位置都健壮）；回退到 target 推算路径。
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
    REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
fi

SKILL_MD="${REPO_ROOT}/plugins/autopilot/skills/autopilot/SKILL.md"
REF_DIR="${REPO_ROOT}/plugins/autopilot/skills/autopilot/references"
AUTO_FIX_REF="${REF_DIR}/auto-fix-phase.md"
CONTRACT_REF="${REF_DIR}/contract-protocol.md"
ANTI_RAT_REF="${REF_DIR}/anti-rationalization.md"
STOP_HOOK="${REPO_ROOT}/plugins/autopilot/scripts/stop-hook.sh"
LIB_SH="${REPO_ROOT}/plugins/autopilot/scripts/lib.sh"

RED_TEAM_FILE="plugins/autopilot/skills/autopilot/references/red-team-prompt.md"
BLUE_TEAM_FILE="plugins/autopilot/skills/autopilot/references/blue-team-prompt.md"
IMPLEMENT_PHASE_FILE="plugins/autopilot/skills/autopilot/references/implement-phase.md"

fail() {
    echo "[FAIL] R_SELFDEC: $1" >&2
    exit 1
}

pass() {
    echo "[PASS] R_SELFDEC: $1"
}

# gcount <grep-args...> → grep 输出行数（多文件/目录递归；空输出记 0）
gcount() {
    local out
    out=$(grep "$@" 2>/dev/null) || true
    if [[ -n "${out}" ]]; then
        printf '%s\n' "${out}" | grep -c . || true
    else
        printf '0'
    fi
}

# 前置：锚点文件必须存在（缺失 = 测试环境错误，非 no-op 判定）
for f in "${SKILL_MD}" "${AUTO_FIX_REF}" "${CONTRACT_REF}" "${ANTI_RAT_REF}" "${STOP_HOOK}" "${LIB_SH}"; do
    [[ -f "${f}" ]] || fail "锚点文件不存在: ${f}"
done
[[ -d "${REF_DIR}" ]] || fail "references 目录不存在: ${REF_DIR}"

# ============================================================================
# 断言 1.1（场景1.P1）：自决路径强对立锚点族 count >= 1
#   driver 逐字：grep -rnE '无需(询问|打断)用户|直接决策|自主决策|自行决策' SKILL.md references/ | wc -l
# ============================================================================
SELF_DECISION_N=$(gcount -rnE '无需(询问|打断)用户|直接决策|自主决策|自行决策' "${SKILL_MD}" "${REF_DIR}")
if [[ "${SELF_DECISION_N}" -lt 1 ]]; then
    fail "场景1.P1: 自决路径锚点族命中 ${SELF_DECISION_N} < 1——SKILL.md 与 references/ 全域没有「AI 可自决、无需打断用户」的强对立表述，双层决策树自决分支未成文"
fi
pass "场景1.P1: 自决锚点族命中 ${SELF_DECISION_N} >= 1"

# ============================================================================
# 断言 1.2（场景1.P2）：留痕锚点族 count >= 1
#   driver 逐字：grep -rnE '留痕|决策记录|决策.{0,4}记录|记录.{0,6}(决策|修改)' SKILL.md references/ | wc -l
# ============================================================================
TRACE_N=$(gcount -rnE '留痕|决策记录|决策.{0,4}记录|记录.{0,6}(决策|修改)' "${SKILL_MD}" "${REF_DIR}")
if [[ "${TRACE_N}" -lt 1 ]]; then
    fail "场景1.P2: 留痕锚点族命中 ${TRACE_N} < 1——自决修改红队测试须留痕的要求未成文，事后审计无锚点"
fi
pass "场景1.P2: 留痕锚点族命中 ${TRACE_N} >= 1"

# ============================================================================
# 断言 2.1（场景2.P1）：AskUserQuestion 于 SKILL.md + references/*.md count >= 1
# ============================================================================
ASK_N=$(gcount -rc 'AskUserQuestion' "${SKILL_MD}" "${REF_DIR}")
if [[ "${ASK_N}" -lt 1 ]]; then
    fail "场景2.P1: AskUserQuestion 命中 ${ASK_N} < 1——升级路径（人类仲裁）被整体删除，决策树只剩自决单分支"
fi
pass "场景2.P1: AskUserQuestion 命中 ${ASK_N} >= 1"

# ============================================================================
# 断言 2.2（场景2.P2）：升级触发条件为条件化表述（证据不足/边缘情形）count >= 1
#   driver 逐字：grep -rnE '证据.{0,8}(不足|不充分)|边缘情形|无法.{0,6}(判定|决策)' SKILL.md references/ | wc -l
# ============================================================================
UPGRADE_COND_N=$(gcount -rnE '证据.{0,8}(不足|不充分)|边缘情形|无法.{0,6}(判定|决策)' "${SKILL_MD}" "${REF_DIR}")
if [[ "${UPGRADE_COND_N}" -lt 1 ]]; then
    fail "场景2.P2: 升级条件锚点族命中 ${UPGRADE_COND_N} < 1——AskUserQuestion 升级路径未写成条件式（证据不足/边缘情形才升级），退回无条件打断"
fi
pass "场景2.P2: 升级条件锚点族命中 ${UPGRADE_COND_N} >= 1"

# ============================================================================
# 断言 3.1（场景3.P1，反向）：旧「无条件必须先问用户」措辞族 count == 0
#   driver 逐字：grep -rnE '必须.{0,12}(询问|AskUserQuestion)|是否允许修改|未经用户(同意|确认|允许).{0,10}修改'
#               SKILL.md references/ stop-hook.sh | wc -l
#   消歧（生成器原注）：新升级路径须写成条件式；若升级话术与本族字面冲突，是文案需调整，不是谓词需放宽。
# ============================================================================
OLD_HITS=$(grep -rnE '必须.{0,12}(询问|AskUserQuestion)|是否允许修改|未经用户(同意|确认|允许).{0,10}修改' "${SKILL_MD}" "${REF_DIR}" "${STOP_HOOK}" 2>/dev/null) || true
OLD_N=0
if [[ -n "${OLD_HITS}" ]]; then
    OLD_N=$(printf '%s\n' "${OLD_HITS}" | grep -c . || true)
fi
if [[ "${OLD_N}" -ne 0 ]]; then
    fail "场景3.P1: 旧机制措辞族残留 ${OLD_N} 处（应 == 0）——无条件前置用户询问的旧单层机制未清除，命中如下：
${OLD_HITS}"
fi
pass "场景3.P1: 旧「无条件必须先问用户」措辞族全域 == 0"

# ============================================================================
# 断言 4.1（场景4.P1）：决策树双分支完备共存——自决族 >= 1 ∧ AskUserQuestion >= 1（任一为 0 即 FAIL）
#   自决族计数复用 1.1 的 SELF_DECISION_N，AskUserQuestion 计数复用 2.1 的 ASK_N。
# ============================================================================
if [[ "${SELF_DECISION_N}" -lt 1 || "${ASK_N}" -lt 1 ]]; then
    fail "场景4.P1: 双分支不完备（自决族=${SELF_DECISION_N}, AskUserQuestion=${ASK_N}，两值须同时 >= 1）——决策树缺自决分支或缺升级分支"
fi
pass "场景4.P1: 双分支共存（自决族=${SELF_DECISION_N} >= 1 ∧ AskUserQuestion=${ASK_N} >= 1）"

# ============================================================================
# 断言 7.1（场景7.P1）：三类问题枚举完整保留——每词 file-count >= 1（三者同时满足）
#   driver 逐字：grep -rlE '契约.{0,4}矛盾' ... | wc -l；grep -rliE '私有.{0,2}seam' ... | wc -l；
#               grep -rl '断言机制' ... | wc -l
# ============================================================================
N1=$(gcount -rlE '契约.{0,4}矛盾' "${SKILL_MD}" "${REF_DIR}")
N2=$(gcount -rliE '私有.{0,2}seam' "${SKILL_MD}" "${REF_DIR}")
N3=$(gcount -rl '断言机制' "${SKILL_MD}" "${REF_DIR}")
if [[ "${N1}" -lt 1 ]]; then
    fail "场景7.P1: 「契约.{0,4}矛盾」file-count=${N1} < 1——情形①枚举丢失，决策维度不完整"
fi
if [[ "${N2}" -lt 1 ]]; then
    fail "场景7.P1: 「私有.{0,2}seam」(-i) file-count=${N2} < 1——情形②枚举丢失，决策维度不完整"
fi
if [[ "${N3}" -lt 1 ]]; then
    fail "场景7.P1: 「断言机制」file-count=${N3} < 1——情形③枚举丢失，决策维度不完整"
fi
pass "场景7.P1: 三类问题枚举齐备（契约矛盾=${N1} / 私有seam=${N2} / 断言机制=${N3}，每项 >= 1）"

# ============================================================================
# 断言 C1.1 + C1.2（契约 C1）：SKILL.md 铁律段字面 + 双层表述
#   必须含字面：红队铁律 / AI 自决 / 重锁 / references/auto-fix-phase.md；
#   行为语义（机械锚点）：证据链闭合（自决）+ AskUserQuestion（升级）同段共存 + 默认禁改表述。
#   「红队铁律」为 L348 行内补入的新契约词——改写前不存在，no-op 必 FAIL。
# ============================================================================
HIT_N=$(gcount -c '红队铁律' "${SKILL_MD}")
if [[ "${HIT_N}" -lt 1 ]]; then
    fail "C1.1: SKILL.md 不含「红队铁律」字面（C1 要求 L348 行内补入；shrinkage-invariants 契约词 after>=1 同步失守）"
fi

C1_PARA_OK=0
C1_LNS=$(grep -n '红队铁律' "${SKILL_MD}" 2>/dev/null) || true
if [[ -z "${C1_LNS}" ]]; then
    fail "C1.1: SKILL.md 不含「红队铁律」字面（C1 要求 L348 行内补入，no-op 必 FAIL）"
fi
while IFS= read -r matched; do
    ln="${matched%%:*}"
    para=$(awk -v s="${ln}" 'NR==s {f=1; print; next} f && /^[[:space:]]*$/ {exit} f {print}' "${SKILL_MD}")
    if printf '%s' "${para}" | grep -qF 'AI 自决' \
        && printf '%s' "${para}" | grep -qF '重锁' \
        && printf '%s' "${para}" | grep -qF 'references/auto-fix-phase.md' \
        && printf '%s' "${para}" | grep -qF '证据链闭合' \
        && printf '%s' "${para}" | grep -qF 'AskUserQuestion' \
        && printf '%s' "${para}" | grep -qE '默认(不允许|禁止|不得)'; then
        C1_PARA_OK=1
        break
    fi
done < <(printf '%s\n' "${C1_LNS}")
if [[ "${C1_PARA_OK}" -ne 1 ]]; then
    fail "C1.2: SKILL.md 铁律段缺双层表述要件——段内须同时含「AI 自决」∧「重锁」∧「references/auto-fix-phase.md」∧「证据链闭合」∧「AskUserQuestion」∧ 默认禁改表述（C1 行为语义：默认禁改 + 三情形例外 + 证据链闭合自决 / 不闭合 AskUserQuestion）"
fi
pass "C1: SKILL.md 铁律段含红队铁律 + AI 自决 + 重锁 + 指针 + 证据链闭合/AskUserQuestion 双层 + 默认禁改"

# ============================================================================
# 断言 C2.1 + C2.2（契约 C2 + C7③）：SKILL.md auto-fix 段行改写可证
#   新字面「证据链闭合」须与保留字面（.acceptance.test / 重锁 / references/auto-fix-phase.md）
#   同一行出现——改写前该行不含「证据链闭合」，no-op 必 FAIL；
#   旧表述「经用户确认」在 auto-fix Phase 区域内清零（C7③）。
# ============================================================================
REGION=$(awk '/^## Phase: auto-fix/ && !started {started=1; print; next} started && /^## / {exit} started {print}' "${SKILL_MD}")
if [[ -z "${REGION}" ]]; then
    fail "C2 setup: SKILL.md 未找到「## Phase: auto-fix」区域（结构漂移或区域被删）"
fi

C2_LINE_OK=0
while IFS= read -r line; do
    if printf '%s' "${line}" | grep -qF '.acceptance.test' \
        && printf '%s' "${line}" | grep -qF '证据链闭合' \
        && printf '%s' "${line}" | grep -qF '重锁' \
        && printf '%s' "${line}" | grep -qF 'references/auto-fix-phase.md'; then
        C2_LINE_OK=1
        break
    fi
done <<< "${REGION}"
if [[ "${C2_LINE_OK}" -ne 1 ]]; then
    fail "C2.1: SKILL.md auto-fix 段无一行同时含「.acceptance.test」∧「证据链闭合」∧「重锁」∧「references/auto-fix-phase.md」——C2 要求单行内改写且新字面「证据链闭合」在本行内出现（治 no-op 恒过），改写未发生或未按单行落位"
fi
CONFIRM_N=$(printf '%s\n' "${REGION}" | grep -cF '经用户确认' || true)
if [[ "${CONFIRM_N}" -ne 0 ]]; then
    fail "C2.2: SKILL.md auto-fix 段残留「经用户确认」x${CONFIRM_N}（C7③：旧单层表述须清零）"
fi
pass "C2: auto-fix 段行内含新字面证据链闭合（改写可证）+ 保留字面齐备 + 旧表述「经用户确认」区域清零"

# ============================================================================
# 断言 C3.1 + C3.2（契约 C3）：stop-hook.sh §8.5.1 _tamper_reason 字面 + 结构不变量
#   窗口锚点：_tamper_reason 赋值行（契约命名锚点），回看 8 行须覆盖 acceptance_tests_tampered
#   调用与 rc==2 双信号，前看 10 行须覆盖 decision:block 与 exit 0。
# ============================================================================
TR_LN=$(grep -n '_tamper_reason' "${STOP_HOOK}" 2>/dev/null | head -1 | cut -d: -f1)
if [[ -z "${TR_LN}" ]]; then
    fail "C3 setup: stop-hook.sh 未找到 _tamper_reason（C3 命名锚点缺失——§8.5.1 注入文案结构被移走）"
fi
start_ln=$((TR_LN - 8))
[[ ${start_ln} -lt 1 ]] && start_ln=1
end_ln=$((TR_LN + 10))
WINDOW=$(sed -n "${start_ln},${end_ln}p" "${STOP_HOOK}")

for lit in '三情形' 'AI 自决' 'AskUserQuestion' '重锁' 'git checkout'; do
    if ! printf '%s' "${WINDOW}" | grep -qF "${lit}"; then
        fail "C3.1: stop-hook.sh §8.5.1 _tamper_reason 窗口缺字面「${lit}」（C3 五字面闭集：三情形/AI 自决/AskUserQuestion/重锁/git checkout）——注入文案未同步双层决策树"
    fi
done
for structural in 'acceptance_tests_tampered' '\-eq 2' 'TAMPER' '"decision"' '"block"' 'exit 0'; do
    if ! printf '%s' "${WINDOW}" | grep -qE "${structural}"; then
        fail "C3.2: stop-hook.sh §8.5.1 结构不变量缺失「${structural}」——C3 行为零改动约束被破坏（acceptance_tests_tampered 调用 / rc==2 双信号判定 / decision:block 结构 / exit 0 均须保留）"
    fi
done
pass "C3: §8.5.1 窗口含五字面（三情形/AI 自决/AskUserQuestion/重锁/git checkout）+ 结构不变量（调用/rc==2/TAMPER/decision:block/exit 0）齐备"

# ============================================================================
# 断言 6.1 / 6.2（场景6.P1 / 6.P2）：既有守卫不变量未被破坏
# ============================================================================
TAMPER_N=$(grep -cE 'acceptance_tests_tampered|TAMPER' "${STOP_HOOK}" 2>/dev/null) || TAMPER_N=0
if [[ "${TAMPER_N}" -lt 1 ]]; then
    fail "场景6.P1: acceptance_tests_tampered|TAMPER 于 stop-hook.sh 命中 ${TAMPER_N} < 1——tamper 守卫检测信号丢失"
fi
pass "场景6.P1: acceptance_tests_tampered|TAMPER 命中 ${TAMPER_N} >= 1"

LOCK_N=$(grep -c 'lock_acceptance_tests' "${STOP_HOOK}" 2>/dev/null) || LOCK_N=0
if [[ "${LOCK_N}" -lt 1 ]]; then
    fail "场景6.P2: lock_acceptance_tests 于 stop-hook.sh 命中 ${LOCK_N} < 1——重锁机制关键词丢失"
fi
pass "场景6.P2: lock_acceptance_tests 命中 ${LOCK_N} >= 1"

# ============================================================================
# 断言 C4.1-C4.7（契约 C4 + C7①②）：auto-fix-phase.md 铁律头段 + §6 重写
# ============================================================================

# C4.1 铁律头段（L4）条件式双层表述：头段（## 1. 之前）含 证据链闭合 ∧ AI 自决 ∧ AskUserQuestion ∧ 重锁
HEAD_REGION=$(awk '/^## 1\./ {exit} {print}' "${AUTO_FIX_REF}")
for lit in '证据链闭合' 'AI 自决' 'AskUserQuestion' '重锁'; do
    if ! printf '%s' "${HEAD_REGION}" | grep -qF "${lit}"; then
        fail "C4.1: auto-fix-phase.md 铁律头段（L4）缺字面「${lit}」——头段未同步为条件式双层表述，与新 §6 同文件自相矛盾"
    fi
done
pass "C4.1: 铁律头段条件式双层表述齐备（证据链闭合/AI 自决/AskUserQuestion/重锁）"

# C4.2 §6 区域提取
SEC6=$(awk '/^## 6\./ && !started {started=1; print; next} started && /^## / {exit} started {print}' "${AUTO_FIX_REF}")
if [[ -z "${SEC6}" ]]; then
    fail "C4 setup: auto-fix-phase.md 未找到「## 6.」区域（§6 被删除或重编号，与设计改动面不符）"
fi

# C4.2 三情形枚举 + 闭集语义（之外一律不改）
for lit in '断言与契约矛盾' '断言机制错'; do
    if ! printf '%s' "${SEC6}" | grep -qF "${lit}"; then
        fail "C4.2: auto-fix-phase.md §6 缺三情形字面「${lit}」（闭集枚举 ①③）"
    fi
done
if ! printf '%s' "${SEC6}" | grep -qE '私有[[:space:]]?[Ss]eam'; then
    fail "C4.2: auto-fix-phase.md §6 缺三情形字面「私有 seam」（情形②，闭集枚举）"
fi
if ! printf '%s' "${SEC6}" | grep -qE '一律不改|之外.{0,6}不改|闭集外'; then
    fail "C4.2: auto-fix-phase.md §6 缺闭集语义「之外一律不改」——三情形闭集外的修实现默认路径须保留（防所有失败都能改测试的放水口子）"
fi
pass "C4.2: §6 三情形枚举（断言与契约矛盾/私有 seam/断言机制错）+ 闭集语义齐备"

# C4.3 双层决策树 + 证据判据/升级判据 + 重锁函数 + 变更日志留痕 + 逐字锚点
for lit in '证据链闭合' 'AI 自决' 'AskUserQuestion' 'lock_acceptance_tests' '留痕' '变更日志' '逐字' \
           'E1' 'E2' 'E3' 'U1' 'U2' 'U3' 'U4'; do
    if ! printf '%s' "${SEC6}" | grep -qF "${lit}"; then
        fail "C4.3: auto-fix-phase.md §6 缺字面「${lit}」（双层决策树 / E1-E3 证据判据 / U1-U4 升级判据 / 重锁 / 变更日志留痕 / 逐字一致锚点）"
    fi
done
pass "C4.3: §6 双层决策树 + E1-E3/U1-U4 + lock_acceptance_tests 重锁 + 变更日志留痕 + 逐字锚点齐备"

# C4.4 留痕格式示例：存在一行同时含「AI 自决改红队测试」∧「已重锁」（新格式替换旧「经用户确认改红队测试」）
#      且 §6 含「证据」字面（C6b 留痕行须同现证据字面的成文来源）
TRACE_LINE_OK=0
while IFS= read -r line; do
    if printf '%s' "${line}" | grep -qF 'AI 自决改红队测试' && printf '%s' "${line}" | grep -qF '已重锁'; then
        TRACE_LINE_OK=1
        break
    fi
done <<< "${SEC6}"
if [[ ${TRACE_LINE_OK} -ne 1 ]]; then
    fail "C4.4: auto-fix-phase.md §6 缺留痕格式示例行（须同行含「AI 自决改红队测试」∧「已重锁」）——变更日志留痕格式未成文，事后审计无格式锚点"
fi
if ! printf '%s' "${SEC6}" | grep -qF '证据'; then
    fail "C4.4: auto-fix-phase.md §6 缺「证据」字面——留痕行须同现证据字面的要求未成文（C6b 守卫 grep 口径的成文来源）"
fi
pass "C4.4: 留痕格式示例行（AI 自决改红队测试 + 已重锁）+ 证据字面齐备"

# C4.5 QA 报告区块转记指令（载体明确，非悬空承诺）
if ! printf '%s' "${SEC6}" | grep -qF '红队测试修改清单'; then
    fail "C4.5: auto-fix-phase.md §6 缺「红队测试修改清单」字面——QA 报告显著区块转记指令未成文，用户 merge 前不可审计"
fi
if ! printf '%s' "${SEC6}" | grep -qF '转记'; then
    fail "C4.5: auto-fix-phase.md §6 缺「转记」字面——编排器从变更日志转记的指令未成文"
fi
pass "C4.5: QA 报告「红队测试修改清单」区块 + 编排器转记指令齐备"

# C4.6 + C7①②（反向断言）：旧单层表述清零
OLD_CONFIRM_LOG=$(grep -cF '经用户确认改红队测试' "${AUTO_FIX_REF}" 2>/dev/null) || OLD_CONFIRM_LOG=0
if [[ "${OLD_CONFIRM_LOG}" -ne 0 ]]; then
    fail "C4.6/C7: auto-fix-phase.md 残留旧留痕标记「经用户确认改红队测试」x${OLD_CONFIRM_LOG}（应 == 0）——旧留痕格式与 AI 自决新格式并存漂移"
fi
OLD_ASK_RELOCK=$(grep -cE 'AskUserQuestion`?[[:space:]]*确认[[:space:]]*\+[[:space:]]*重锁' "${AUTO_FIX_REF}" 2>/dev/null) || OLD_ASK_RELOCK=0
if [[ "${OLD_ASK_RELOCK}" -ne 0 ]]; then
    fail "C4.6/C7①②: auto-fix-phase.md 残留旧单层表述「AskUserQuestion 确认 + 重锁」x${OLD_ASK_RELOCK}（应 == 0；覆盖 §6 与铁律头段 L4 两处闭集）——须 AskUserQuestion 确认 + 重锁放行的旧措辞未清零"
fi
pass "C4.6/C7①②: 旧留痕标记「经用户确认改红队测试」== 0 + 旧单层表述「AskUserQuestion 确认 + 重锁」== 0"

# C4.7 §3 批量修复段零改动（保护 p2-qa-loop 断言的关键词）
for lit in '统一修复' '一轮'; do
    if ! grep -qF "${lit}" "${AUTO_FIX_REF}"; then
        fail "C4.7: auto-fix-phase.md 缺 §3 批量修复段关键词「${lit}」——§3 须零改动（p2-qa-loop 契约）"
    fi
done
if ! grep -qE '共同(上游)?根因' "${AUTO_FIX_REF}"; then
    fail "C4.7: auto-fix-phase.md 缺「共同根因」语义——§3 批量修复纪律阶段一须零改动"
fi
pass "C4.7: §3 批量修复段关键词（统一修复/一轮/共同根因）未被破坏"

# ============================================================================
# 断言 C5.1 + C5.2（契约 C5）：anti-rationalization.md 新反向条目
# ============================================================================
AR_HAS_EVIDENCE_SELF=0
while IFS= read -r line; do
    if printf '%s' "${line}" | grep -qF '证据' && printf '%s' "${line}" | grep -qF '自决'; then
        AR_HAS_EVIDENCE_SELF=1
        break
    fi
done < "${ANTI_RAT_REF}"
if [[ ${AR_HAS_EVIDENCE_SELF} -ne 1 ]]; then
    fail "C5.1: anti-rationalization.md 无「证据」∧「自决」同行条目——「证据不足/无证据就自决改测试 = 放水」反向条目缺失，防放水教育层有缺口"
fi
if ! grep -qE '无证据|证据不足|证据链不闭合' "${ANTI_RAT_REF}"; then
    fail "C5.2: anti-rationalization.md 缺「无证据/证据不足/证据链不闭合」条件表述——反向条目未写明触发条件"
fi
pass "C5: 新反向条目（证据 ∧ 自决同行 + 无证据/证据不足条件）齐备"

# ============================================================================
# 断言 C6.1-C6.3（契约 C6 行为不变量，零改动区）+ C6.4 三情形一致性
# ============================================================================
if ! grep -qE '^lock_acceptance_tests\(\)|^function lock_acceptance_tests' "${LIB_SH}"; then
    fail "C6.1: lock_acceptance_tests() 函数未定义于 lib.sh（签名零改动区被破坏）"
fi
if ! grep -qE '^acceptance_tests_tampered\(\)|^function acceptance_tests_tampered' "${LIB_SH}"; then
    fail "C6.1: acceptance_tests_tampered() 函数未定义于 lib.sh（签名零改动区被破坏）"
fi
pass "C6.1: lock_acceptance_tests() + acceptance_tests_tampered() 函数定义在位"

for rc_doc in '0 = clean' '2 = tampered' '1 = no-lock'; do
    if ! grep -qF "${rc_doc}" "${LIB_SH}"; then
        fail "C6.2: lib.sh 缺 rc 语义注释「${rc_doc}」——三态退出码文档（0/2/1）被破坏"
    fi
done
pass "C6.2: rc 语义注释（0 = clean / 2 = tampered / 1 = no-lock）在位"

if ! grep -qF '<sha256>' "${LIB_SH}" || ! grep -qF '<abs-path>' "${LIB_SH}"; then
    fail "C6.3: lib.sh 锁文件格式注释（<sha256>  <abs-path>）缺失——锁文件格式契约文档被破坏"
fi
pass "C6.3: 锁文件格式注释（<sha256>  <abs-path>）在位"

for lit in '断言与契约矛盾' '断言机制'; do
    if ! grep -qF "${lit}" "${SKILL_MD}" || ! grep -qF "${lit}" "${AUTO_FIX_REF}"; then
        fail "C6.4: 三情形字面「${lit}」未在 SKILL.md 与 auto-fix-phase.md 间保持一致（C6：定义字面跨文件一致）"
    fi
done
if ! grep -qE '私有[[:space:]]?[Ss]eam' "${SKILL_MD}" || ! grep -qE '私有[[:space:]]?[Ss]eam' "${AUTO_FIX_REF}"; then
    fail "C6.4: 三情形字面「私有 seam」未在 SKILL.md 与 auto-fix-phase.md 间保持一致"
fi
pass "C6.4: 三情形定义字面跨文件（SKILL.md ↔ auto-fix-phase.md）一致"

# ============================================================================
# 断言 5.1（场景5.P1，C8）：四文件 git diff --numstat sum(deleted) >= sum(added)
#   优先工作区 vs HEAD；若全空（已提交）回退 HEAD~1；仍全空 = no-op，直接 FAIL。
# ============================================================================
FOUR_FILES=(
    "${RED_TEAM_FILE}"
    "${BLUE_TEAM_FILE}"
    "${IMPLEMENT_PHASE_FILE}"
    "plugins/autopilot/skills/autopilot/SKILL.md"
)

compute_numstat() {
    local diff_ref="${1}"
    local ta=0
    local td=0
    local out
    # diff_ref 可能是区间（"A B"，含空格）或单 ref——故意不加引号按词分割
    out=$(git -C "${REPO_ROOT}" diff --numstat ${diff_ref} -- "${FOUR_FILES[@]}" 2>/dev/null) || true
    if [[ -n "${out}" ]]; then
        while IFS=$'\t' read -r added deleted _path; do
            [[ "${added}" == "-" || "${deleted}" == "-" ]] && continue
            if [[ "${added}" =~ ^[0-9]+$ ]]; then
                ta=$((ta + added))
            fi
            if [[ "${deleted}" =~ ^[0-9]+$ ]]; then
                td=$((td + deleted))
            fi
        done <<< "${out}"
    fi
    printf '%s %s' "${ta}" "${td}"
}

NUM_HEAD=$(compute_numstat "HEAD")
TOTAL_ADDED=${NUM_HEAD%% *}
TOTAL_DELETED=${NUM_HEAD##* }
DIFF_REF_DESC="HEAD (working tree, uncommitted)"

# [2026-09-09 适配] 工作区 clean（改动已提交）时，动态定位最近触碰四文件的 commit
# 并取其自身 diff（区间形式）——固定层数回退（HEAD~1/HEAD~2）会被中间不相关 commit
# 击穿（rebase/多 commit 合流后必现）；对齐 skill-shrinkage-invariants 场景 1.P2
# 的 commit-aware 适配先例。
if [[ "${TOTAL_ADDED}" -eq 0 && "${TOTAL_DELETED}" -eq 0 ]]; then
    LAST_TOUCH=$(git -C "${REPO_ROOT}" log -1 --format=%H -- "${FOUR_FILES[@]}" 2>/dev/null) || true
    if [[ -n "${LAST_TOUCH}" ]]; then
        NUM_LAST=$(compute_numstat "${LAST_TOUCH}~1 ${LAST_TOUCH}")
        TOTAL_ADDED=${NUM_LAST%% *}
        TOTAL_DELETED=${NUM_LAST##* }
        DIFF_REF_DESC="$(git -C "${REPO_ROOT}" log -1 --format=%h "${LAST_TOUCH}" 2>/dev/null) (last commit touching the four files)"
    fi
fi

if [[ "${TOTAL_ADDED}" -eq 0 && "${TOTAL_DELETED}" -eq 0 ]]; then
    fail "场景5.P1: 四文件 git diff --numstat 无可见变更（added=0 deleted=0）——改动未发生（no-op）或已提交超过一层回溯范围，减行硬约束不可判 PASS"
fi
if [[ "${TOTAL_DELETED}" -lt "${TOTAL_ADDED}" ]]; then
    fail "场景5.P1: 四文件净增行（added=${TOTAL_ADDED} > deleted=${TOTAL_DELETED}，[${DIFF_REF_DESC}]）——违反「主 SKILL.md 只能减少不能增加」硬约束"
fi
pass "场景5.P1: 四文件 sum(deleted)=${TOTAL_DELETED} >= sum(added)=${TOTAL_ADDED}（[${DIFF_REF_DESC}]）"

# ============================================================================
# 断言 5.2（场景5.P2）：主 SKILL.md 单文件 added <= deleted（行数只减不增）
#   同上 no-op 守卫：单文件 numstat 全空 = 改动未发生，FAIL。
# ============================================================================
SKILL_OUT=$(git -C "${REPO_ROOT}" diff --numstat HEAD -- "plugins/autopilot/skills/autopilot/SKILL.md" 2>/dev/null) || true
S_ADDED=0
S_DELETED=0
if [[ -n "${SKILL_OUT}" ]]; then
    while IFS=$'\t' read -r added deleted _path; do
        [[ "${added}" == "-" || "${deleted}" == "-" ]] && continue
        [[ "${added}" =~ ^[0-9]+$ ]] && S_ADDED=${added}
        [[ "${deleted}" =~ ^[0-9]+$ ]] && S_DELETED=${deleted}
    done <<< "${SKILL_OUT}"
fi
if [[ "${S_ADDED}" -eq 0 && "${S_DELETED}" -eq 0 ]]; then
    # [2026-09-09 适配] 工作区 clean 时动态定位最近触碰 SKILL.md 的 commit 取其自身
    # diff——固定 HEAD~1 单 ref 回退会被中间不相关 commit 击穿（区间形式 + 去引号）；
    # 对齐场景 5.1 同款 last-touch 适配。
    SKILL_LAST=$(git -C "${REPO_ROOT}" log -1 --format=%H -- "plugins/autopilot/skills/autopilot/SKILL.md" 2>/dev/null) || true
    if [[ -n "${SKILL_LAST}" ]]; then
        SKILL_OUT=$(git -C "${REPO_ROOT}" diff --numstat "${SKILL_LAST}~1" "${SKILL_LAST}" -- "plugins/autopilot/skills/autopilot/SKILL.md" 2>/dev/null) || true
    fi
    if [[ -n "${SKILL_OUT}" ]]; then
        while IFS=$'\t' read -r added deleted _path; do
            [[ "${added}" == "-" || "${deleted}" == "-" ]] && continue
            [[ "${added}" =~ ^[0-9]+$ ]] && S_ADDED=${added}
            [[ "${deleted}" =~ ^[0-9]+$ ]] && S_DELETED=${deleted}
        done <<< "${SKILL_OUT}"
    fi
fi
if [[ "${S_ADDED}" -eq 0 && "${S_DELETED}" -eq 0 ]]; then
    fail "场景5.P2: 主 SKILL.md 单文件 numstat 无可见变更（no-op 或已提交超过一层），行数约束不可判 PASS"
fi
if [[ "${S_DELETED}" -lt "${S_ADDED}" ]]; then
    fail "场景5.P2: 主 SKILL.md 单文件净增行（added=${S_ADDED} > deleted=${S_DELETED}）——硬约束 3「行数只减不增」被违反（C1/C2 单行内替换 +0 的载体证据）"
fi
pass "场景5.P2: 主 SKILL.md 单文件 deleted=${S_DELETED} >= added=${S_ADDED}"

# ============================================================================
# 断言 C9.1（契约 C9）：contract-protocol.md 逐字一致原则成文
#   存在一行同时含「逐字推导」∧「禁止推测」，且该行提及契约规约或验收场景（红队写测试与
#   AI 自决改测试共用同一锚点）。
# ============================================================================
C9_LINE_OK=0
while IFS= read -r line; do
    if printf '%s' "${line}" | grep -qF '逐字推导' \
        && printf '%s' "${line}" | grep -qF '禁止推测' \
        && { printf '%s' "${line}" | grep -qF '契约规约' || printf '%s' "${line}" | grep -qF '验收场景'; }; then
        C9_LINE_OK=1
        break
    fi
done < "${CONTRACT_REF}"
if [[ ${C9_LINE_OK} -ne 1 ]]; then
    fail "C9.1: contract-protocol.md 缺逐字一致成文行（须同行含「逐字推导」∧「禁止推测」∧ 提及「契约规约」或「验收场景」）——红队写测试与 AI 自决改测试的共用锚点未成文"
fi
pass "C9: contract-protocol.md 逐字一致成文行在位（逐字推导 + 禁止推测 + 契约锚点）"

# ============================================================================
# 断言 8.2（场景8.P2）：npm run lint / ShellCheck 零 error（exit == 0）
#   场景8.P1（run-all 全量回归）由编排器 QA Tier 1 执行：本测试合流后即为 run-all 成员，
#   测试内再跑 run-all 会无限递归——对齐 p2-qa-loop 场景7.P1 既有先例，此处不覆盖。
# ============================================================================
LINT_OUT_FILE=$(mktemp)
LINT_RC=0
npm run lint --silent > "${LINT_OUT_FILE}" 2>&1 || LINT_RC=$?
if [[ "${LINT_RC}" -ne 0 ]]; then
    echo "----- ShellCheck 输出（前 30 行）-----" >&2
    head -30 "${LINT_OUT_FILE}" >&2 || true
    rm -f "${LINT_OUT_FILE}"
    fail "场景8.P2: npm run lint 退出码 ${LINT_RC} != 0——ShellCheck 存在告警/错误（交付门禁）"
fi
rm -f "${LINT_OUT_FILE}"
pass "场景8.P2: npm run lint exit == 0（ShellCheck 零告警）"

pass "场景8.P1（run-all 全量回归）— // 留 QA Tier 1 真机判定（本测试为其成员，内跑将无限递归）"

echo "[OK ] R_SELFDEC red-team-self-decision-tree — 全部断言通过（场景1.P1/1.P2/2.P1/2.P2/3.P1/4.P1/5.P1/5.P2/6.P1/6.P2/7.P1/8.P2 + C1-C9 契约字面；C6b 行为断言见 red-team-trace-backstop）"
exit 0
