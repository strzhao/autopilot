#!/usr/bin/env bash
# R_QALOOP: p2-qa-loop 验收测试（QA 回炉治理 → v3.64.0）
# 红队测试 — 仅基于设计文档契约 C3/C6/C7/C5 与验收场景谓词编写，不读取蓝队实现。
#
# 覆盖谓词：
#   场景1.P1 [det-machine]: blue-team-prompt.md 返回格式含机器可读清单（exit= + ｜）
#                           ∧ SKILL.md 含 "蓝队自检" 区域 ∧ 含 "tree_sig:"
#   场景1.P2 [det-machine]: SKILL.md 含 "沿用蓝队自检" 标注语义
#   场景1.P3 [det-machine]: tree_sig 行为真跑（64-hex + 确定性 + 测试文件不进签名）
#   场景1.P4 [det-machine]: 不新增 frontmatter 字段（tree_sig 不得以字段形式登记/写入）
#   场景2.P1 [det-machine]: 改源码 → 签名变 ∧ SKILL.md 含重跑语义
#   场景2.P2 [det-machine]: 仅改测试文件 → 签名不变（复用依然生效）
#   场景3.P1 [det-machine]: SKILL.md 含区域缺失 → 照常执行降级分支语义
#   场景4.P1 [det-machine]: 三条件字面齐备（同语义命令 ∧ exit=0 ∧ tree_sig 匹配）∧ 缺一重跑
#   场景4.P2 [det-machine]: exit=0 条件存在（失败结果不可复用）
#   场景5.P1 [det-machine]: 批量修复语义（统一修复 ∧ 一轮验证；auto-fix-phase.md 另含共同根因）
#   场景5.P2 [det-machine]: 四阶段方法论（观察/假设/验证/修复）保留
#   场景5.P3 [det-machine, negate]: "立即运行对应检查命令" 在 skills/autopilot/ 全目录计数 == 0
#   场景6.P1 [det-machine]: 四处版本动态一致（== plugin.json 值）∧ >= 3.64.0（no-op 防护）
#
# C7 行为真跑说明：在 mktemp -d 临时目录自建 git repo（init + commit + 源码/测试文件），
# 子 shell 中 source lib.sh 调 tree_sig 验证四性质，不读当前工作区 git 状态（无时序耦合），
# 结束清理临时目录。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

SKILL_MD="${REPO_ROOT}/plugins/autopilot/skills/autopilot/SKILL.md"
AUTO_FIX_REF="${REPO_ROOT}/plugins/autopilot/skills/autopilot/references/auto-fix-phase.md"
BLUE_TEAM_REF="${REPO_ROOT}/plugins/autopilot/skills/autopilot/references/blue-team-prompt.md"
STATE_GUIDE="${REPO_ROOT}/plugins/autopilot/skills/autopilot/references/state-file-guide.md"
SKILL_DIR="${REPO_ROOT}/plugins/autopilot/skills/autopilot"
LIB_SH="${REPO_ROOT}/plugins/autopilot/scripts/lib.sh"
STOP_HOOK="${REPO_ROOT}/plugins/autopilot/scripts/stop-hook.sh"
PLUGIN_JSON="${REPO_ROOT}/plugins/autopilot/.claude-plugin/plugin.json"
MARKETPLACE_JSON="${REPO_ROOT}/.claude-plugin/marketplace.json"
ROOT_CLAUDE_MD="${REPO_ROOT}/CLAUDE.md"
README_MD="${REPO_ROOT}/plugins/autopilot/README.md"

fail() {
    echo "[FAIL] R_QALOOP: ${1}" >&2
    exit 1
}

pass() {
    echo "[PASS] R_QALOOP: ${1}"
}

# 前置：锚点文件必须存在（不存在 = 测试环境错误，非 no-op 判定）
for f in "${SKILL_MD}" "${AUTO_FIX_REF}" "${BLUE_TEAM_REF}" "${STATE_GUIDE}" \
         "${LIB_SH}" "${STOP_HOOK}" "${PLUGIN_JSON}" "${MARKETPLACE_JSON}" \
         "${ROOT_CLAUDE_MD}" "${README_MD}"; do
    [[ -f "${f}" ]] || fail "锚点文件不存在: ${f}"
done

# =========================================================================
# 场景 5：auto-fix 批量修复纪律（先写文档断言，行为真跑放最后）
# =========================================================================

# ── 场景5.P1：批量修复语义——统一修复 ∧ 一轮验证 ─────────────────────────────
# C6：SKILL.md 与 auto-fix-phase.md 均含「统一修复」∧「一轮」验证语义文本。
# 共同根因语义：设计文档明确落在 auto-fix-phase.md（阶段一末尾共同根因分析），
# SKILL.md 只保留两段式骨架 + 指针（progressive disclosure），故不强制 SKILL.md 含此词。
for f in "${SKILL_MD}" "${AUTO_FIX_REF}"; do
    grep -qF '统一修复' "${f}" \
        || fail "场景5.P1: $(basename "${f}") 不含「统一修复」语义（C6 契约）"
    grep -qF '一轮' "${f}" \
        || fail "场景5.P1: $(basename "${f}") 不含「一轮」验证语义（C6 契约）"
done
grep -qE '共同(上游)?根因' "${AUTO_FIX_REF}" \
    || fail "场景5.P1: auto-fix-phase.md 不含共同根因语义（批量纪律阶段一）"
pass "场景5.P1: 统一修复 ∧ 一轮验证语义双文件齐备 + auto-fix-phase.md 共同根因"

# ── 场景5.P2：四阶段方法论保留（观察/假设/验证/修复）────────────────────────
for kw in '观察' '假设' '验证' '修复'; do
    grep -qF "${kw}" "${AUTO_FIX_REF}" \
        || fail "场景5.P2: auto-fix-phase.md 四阶段关键词「${kw}」缺失（不得删除）"
done
pass "场景5.P2: 四阶段方法论（观察/假设/验证/修复）保留"

# ── 场景5.P3（negate）：旧逐项验证表述清零 ──────────────────────────────────
# no-op 时 SKILL.md/auto-fix-phase.md 残留「立即运行对应检查命令」→ 计数 > 0 → FAIL
OLD_CNT_SKILL=$(grep -cF '立即运行对应检查命令' "${SKILL_MD}" || true)
OLD_CNT_REF=$(grep -cF '立即运行对应检查命令' "${AUTO_FIX_REF}" || true)
if [[ "${OLD_CNT_SKILL}" -ne 0 || "${OLD_CNT_REF}" -ne 0 ]]; then
    fail "场景5.P3: 旧表述「立即运行对应检查命令」残留（SKILL.md=${OLD_CNT_SKILL} 处, auto-fix-phase.md=${OLD_CNT_REF} 处），逐项验证节奏未清除"
fi
# 谓词 driver 口径：skills/autopilot/ 全目录计数 == 0
OLD_CNT_DIR=$(grep -rcF '立即运行对应检查命令' "${SKILL_DIR}" 2>/dev/null | awk -F: '{s+=$NF} END {print s+0}')
if [[ "${OLD_CNT_DIR}" -ne 0 ]]; then
    fail "场景5.P3: skills/autopilot/ 全目录残留「立即运行对应检查命令」共 ${OLD_CNT_DIR} 处"
fi
pass "场景5.P3: 旧表述「立即运行对应检查命令」全目录计数 == 0"

# =========================================================================
# 场景 1 / 2 / 3 / 4：蓝队自检证据复用（文档契约断言）
# =========================================================================

# ── 场景1.P1：生产端 + 编排端双断言（防漏生产端致静默 no-op）────────────────
# 生产端：blue-team-prompt.md 返回格式要求机器可读清单条目 `- <命令> ｜ exit=<码> ｜ <范围>`
grep -qE 'exit= ?' "${BLUE_TEAM_REF}" \
    || fail "场景1.P1: blue-team-prompt.md 返回格式不含 exit= 机器可读清单条目（C3 生产端缺失）"
grep -qF '｜' "${BLUE_TEAM_REF}" \
    || fail "场景1.P1: blue-team-prompt.md 返回格式不含全角 ｜ 分隔符（C3 清单格式）"
# 编排端：SKILL.md 合流段规定写入 ## 蓝队自检 区域且首行 tree_sig: <64-hex>
grep -qF '蓝队自检' "${SKILL_MD}" \
    || fail "场景1.P1: SKILL.md 不含「蓝队自检」区域语义（C3 编排端缺失）"
grep -qF 'tree_sig:' "${SKILL_MD}" \
    || fail "场景1.P1: SKILL.md 合流段不含 tree_sig: 首行规约（C3 编排端缺失）"
pass "场景1.P1: blue-team-prompt.md 清单格式（exit= + ｜）∧ SKILL.md 蓝队自检 + tree_sig: 双端齐备"

# ── 场景1.P2：沿用标注语义 ──────────────────────────────────────────────────
grep -qF '沿用蓝队自检' "${SKILL_MD}" \
    || fail "场景1.P2: SKILL.md 不含「沿用蓝队自检」标注语义（QA 报告沿用须可观测）"
pass "场景1.P2: SKILL.md 含「沿用蓝队自检」"

# ── 场景3.P1：区域缺失降级分支（照常执行，行为与改动前一致）─────────────────
# 局部性启发：在「蓝队自检」出现行附近 ±N 行内须有「缺失/不存在/为空」与「照常/重跑」语义
FALLBACK_FOUND=0
for ln in $(grep -nF '蓝队自检' "${SKILL_MD}" | cut -d: -f1); do
    start=$((ln - 10)); [[ ${start} -lt 1 ]] && start=1
    end=$((ln + 14))
    seg=$(sed -n "${start},${end}p" "${SKILL_MD}")
    if echo "${seg}" | grep -qE '缺失|不存在|为空|无该区域|没有该区域' \
       && echo "${seg}" | grep -qE '照常|重跑'; then
        FALLBACK_FOUND=1
        break
    fi
done
[[ ${FALLBACK_FOUND} -eq 1 ]] \
    || fail "场景3.P1: SKILL.md 未在蓝队自检语境附近找到「区域缺失→照常执行/重跑」降级分支语义"
pass "场景3.P1: 区域缺失 → 照常执行降级分支语义存在"

# ── 场景4.P1：三条件字面齐备 + 缺一重跑 ─────────────────────────────────────
grep -qE '同语义命令|同一命令|命令等价|同命令' "${SKILL_MD}" \
    || fail "场景4.P1: SKILL.md 不含「同语义命令」条件语义"
grep -qE 'exit= ?0' "${SKILL_MD}" \
    || fail "场景4.P1: SKILL.md 不含 exit=0 条件语义"
grep -E 'tree_sig.*(匹配|一致|相同|未变)|(匹配|一致|相同|未变).*tree_sig' "${SKILL_MD}" >/dev/null \
    || fail "场景4.P1: SKILL.md 不含 tree_sig 匹配/一致条件语义"
grep -qE '缺一|任一不满足|任一缺失|缺一不可' "${SKILL_MD}" \
    || fail "场景4.P1: SKILL.md 不含「三条件缺一重跑」语义"
pass "场景4.P1: 三条件字面（同语义命令 ∧ exit=0 ∧ tree_sig 匹配）+ 缺一重跑齐备"

# ── 场景4.P2：exit=0 条件（失败结果不可复用为通过证据）──────────────────────
grep -qE 'exit= ?0' "${SKILL_MD}" \
    || fail "场景4.P2: SKILL.md 沿用条件不含 exit=0（非零退出码结果将被错误复用）"
pass "场景4.P2: 沿用条件含 exit=0"

# ── 场景2.P1（文档半边）：签名不一致 → 重跑语义文本存在 ─────────────────────
grep -qE '重跑' "${SKILL_MD}" \
    || fail "场景2.P1: SKILL.md 不含重跑语义（签名不一致时须重跑）"
pass "场景2.P1(文档): SKILL.md 含重跑语义（行为半边见下方 tree_sig 真跑）"

# ── 场景1.P4：不新增 frontmatter 字段（清单只存在于 ## 蓝队自检 内容区域）───
# 反向守卫（对过度实现）：tree_sig / 蓝队自检不得被登记为 frontmatter 字段或经
# set_field 机制写入 state.md frontmatter——只能是内容区域。
if grep -nE '(^|\|)\s*`?tree_sig`?\s*\|' "${STATE_GUIDE}" >/dev/null 2>&1; then
    fail "场景1.P4: state-file-guide.md 以字段表行形式登记了 tree_sig（应为内容区域，非 frontmatter 字段）"
fi
if grep -nE 'set_field[^#]*tree_sig|tree_sig[^#]*set_field' "${LIB_SH}" "${STOP_HOOK}" >/dev/null 2>&1; then
    fail "场景1.P4: lib.sh/stop-hook.sh 通过 set_field 机制写 tree_sig（frontmatter 化，违反内容区域契约）"
fi
if grep -nE 'set_field[^#]*蓝队自检|蓝队自检[^#]*set_field' "${LIB_SH}" "${STOP_HOOK}" >/dev/null 2>&1; then
    fail "场景1.P4: lib.sh/stop-hook.sh 通过 set_field 机制写「蓝队自检」（frontmatter 化，违反内容区域契约）"
fi
pass "场景1.P4: 无 frontmatter 新字段（tree_sig / 蓝队自检均未字段化）"

# =========================================================================
# 场景 6：版本四处同步（动态比对，不硬编码固定版本）
# =========================================================================

VER=$(grep -E '"version"' "${PLUGIN_JSON}" | head -1 | sed 's/[^0-9.]*\([0-9][0-9.]*\).*/\1/')
[[ "${VER}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "场景6.P1: plugin.json 版本号无法解析: '${VER}'"
VER_ESC=$(printf '%s' "${VER}" | sed 's/\./\\./g')

# no-op 防护：版本必须 >= 3.64.0（动态一致性比对对「四处都没动」恒真，此处兜底）
IFS='.' read -r V_MAJ V_MIN V_PAT <<< "${VER}"
if [[ ${V_MAJ} -lt 3 ]] \
   || { [[ ${V_MAJ} -eq 3 ]] && [[ ${V_MIN} -lt 64 ]]; } \
   || { [[ ${V_MAJ} -eq 3 ]] && [[ ${V_MIN} -eq 64 ]] && [[ ${V_PAT} -lt 0 ]]; }; then
    fail "场景6.P1: plugin.json 版本 ${VER} < 3.64.0（版本未升级，no-op）"
fi

# marketplace.json：以 name=autopilot 定位条目取 version
MKT_VER=$(grep -A4 '"name": "autopilot"' "${MARKETPLACE_JSON}" | grep -m1 '"version"' | sed 's/[^0-9.]*\([0-9][0-9.]*\).*/\1/')
[[ "${MKT_VER}" == "${VER}" ]] \
    || fail "场景6.P1: marketplace.json 版本 '${MKT_VER}' != plugin.json '${VER}'"

# CLAUDE.md 插件索引行
grep -qE "v?${VER_ESC}" "${ROOT_CLAUDE_MD}" \
    || fail "场景6.P1: CLAUDE.md 插件索引未含版本 ${VER}（!= plugin.json 动态值）"

# README.md
grep -qE "v?${VER_ESC}" "${README_MD}" \
    || fail "场景6.P1: README.md 未含版本 ${VER}（!= plugin.json 动态值）"

pass "场景6.P1: 四处版本一致 == plugin.json 动态值 ${VER}（且 >= 3.64.0）"

# =========================================================================
# 场景 1.P3 / 2.P1 / 2.P2：tree_sig 行为真跑（临时 git repo，无时序耦合）
# =========================================================================

# 前置：tree_sig 函数定义存在于 lib.sh（no-op → FAIL）
if ! grep -qE '^tree_sig\(\)|^function tree_sig' "${LIB_SH}"; then
    fail "tree_sig() 函数未定义于 lib.sh（设计文档要求新增此函数，no-op）"
fi
pass "tree_sig() 函数定义存在"

TMP_REPO="$(mktemp -d)"
trap 'rm -rf "${TMP_REPO}"' EXIT

REPO="${TMP_REPO}/repo"
mkdir -p "${REPO}/src" "${REPO}/tests"
git -C "${REPO}" init -q
git -C "${REPO}" config user.email "redteam@test.local"
git -C "${REPO}" config user.name "redteam"
printf 'export const a = 1;\nexport const b = 2;\n' > "${REPO}/src/app.ts"
printf 'export const util = () => 42;\n' > "${REPO}/src/util.ts"
printf 'import { a } from "../src/app";\ntest("a is 1", () => { expect(a).toBe(1); });\n' > "${REPO}/tests/app.test.ts"
git -C "${REPO}" add -A
git -C "${REPO}" commit -qm "init baseline"

# 子 shell 中 source lib.sh 调 tree_sig（隔离 lib.sh 顶层可能存在的 trap 'exit 0' ERR）。
# 先尝试 tree_sig "$repo"（路径参数口径），失败/空输出再回退 cd 后无参调用（cwd 口径）。
invoke_tree_sig() {
    (
        cd "${REPO}" || exit 9
        export AUTOPILOT_TEST_MODE=1
        export AUTOPILOT_DISABLE_MAIN=1
        # shellcheck disable=SC1090
        source "${LIB_SH}" 2>/dev/null || true
        out="$(tree_sig "${REPO}" 2>/dev/null)"
        if ! printf '%s' "${out}" | grep -qE '[0-9a-f]{64}'; then
            out="$(tree_sig 2>/dev/null)"
        fi
        printf '%s\n' "${out}" | grep -Eo '[0-9a-f]{64}' | head -1
    )
}

# ── 场景1.P3-a：输出为 64-hex（sha256 口径，非 MD5 32-hex）──────────────────
SIG_A="$(invoke_tree_sig)"
[[ "${SIG_A}" =~ ^[0-9a-f]{64}$ ]] \
    || fail "场景1.P3: tree_sig 输出不是 64-hex，实际='${SIG_A}'（C7: sha256 64-hex）"
pass "场景1.P3-a: tree_sig 输出 64-hex"

# ── 场景1.P3-b：同一 tree 两次调用值相同（确定性）───────────────────────────
SIG_B="$(invoke_tree_sig)"
[[ "${SIG_A}" == "${SIG_B}" ]] \
    || fail "场景1.P3: 同一 tree 两次 tree_sig 调用值不同（${SIG_A} != ${SIG_B}），签名非确定性"
pass "场景1.P3-b: 同一 tree 两次调用值相同"

# ── 场景2.P2 / 1.P3-c：仅改测试文件 → 签名不变（复用依然生效）───────────────
printf '// test-only edit: add case\n' >> "${REPO}/tests/app.test.ts"
SIG_C="$(invoke_tree_sig)"
[[ "${SIG_C}" == "${SIG_A}" ]] \
    || fail "场景2.P2: 仅改测试文件后签名变化（${SIG_A} -> ${SIG_C}），测试文件未从签名中排除，蓝队自检复用将被误失效"
pass "场景2.P2: 仅改测试文件 → 签名不变"

# ── 场景1.P3-d（补充，设计排除模式收紧）：untracked 测试文件 → 签名不变 ─────
printf 'test("extra", () => {});\n' > "${REPO}/tests/new.extra.test.ts"
SIG_D="$(invoke_tree_sig)"
[[ "${SIG_D}" == "${SIG_A}" ]] \
    || fail "场景1.P3: 新增 untracked 测试文件后签名变化（${SIG_A} -> ${SIG_D}），untracked 扫描未排除测试文件"
pass "场景1.P3-d: untracked 测试文件 → 签名不变"

# ── 场景2.P1：改源码 → 签名变（不复用任何蓝队结果）──────────────────────────
printf 'export const c = 3;\n' >> "${REPO}/src/app.ts"
SIG_E="$(invoke_tree_sig)"
[[ "${SIG_E}" != "${SIG_A}" ]] \
    || fail "场景2.P1: 修改源码后签名不变（${SIG_A} == ${SIG_E}），auto-fix 改代码后蓝队自检会被错误沿用"
pass "场景2.P1: 修改源码 → 签名变化"

# ── 场景1.P3-e（补充）：恢复源码 → 回到基线签名（内容驱动，非 mtime）────────
git -C "${REPO}" checkout -q -- src/app.ts
SIG_F="$(invoke_tree_sig)"
[[ "${SIG_F}" == "${SIG_A}" ]] \
    || fail "场景1.P3: 恢复源码内容后签名未回到基线（${SIG_A} != ${SIG_F}），签名疑似混入 mtime 等非内容因素"
pass "场景1.P3-e: 恢复源码内容 → 回到基线签名"

# ── 场景2.P1 补充 / C7：untracked 非测试文件 → 签名变（闭合 untracked 盲区）─
printf 'export const hidden = "leak";\n' > "${REPO}/src/untracked_feature.ts"
SIG_G="$(invoke_tree_sig)"
[[ "${SIG_G}" != "${SIG_F}" ]] \
    || fail "场景2.P1: 新增 untracked 非测试源码文件后签名不变（${SIG_F} == ${SIG_G}），untracked 盲区未闭合"
pass "场景2.P1-补: untracked 非测试文件 → 签名变化"

# 场景7.P1（run-all 全量回归）由编排器 QA 执行，本文件不覆盖（任务规则 1）。

echo "[OK ] R_QALOOP p2-qa-loop — 全部断言通过（场景1.P1/1.P2/1.P3/1.P4/2.P1/2.P2/3.P1/4.P1/4.P2/5.P1/5.P2/5.P3/6.P1）"
exit 0
