#!/usr/bin/env bash
# R_TAMPER: 验证 lib.sh acceptance_tests_tampered 函数四路径决策
# 红队测试 — 仅基于设计文档契约 C2 和 19 条谓词 SSOT 编写，不读取蓝队实现
#
# 覆盖谓词：
#   场景4.P1 [real-process]: acceptance.test.* 被改 → rc!=0 + stdout contains "TAMPER"
#   场景4.P2 [det-machine]:  tamper 检出时 stdout not-contains "PASS"/"通过证据"
#   场景5.P1 [real-process]: 仅源码改，验收测试未改 → rc==0 + not-contains "TAMPER"
#   场景6.P1 [real-process]: 先 lock 既有文件集 → 新增未锁文件 → 既有维度判非违规(rc 0)
#
# 契约 C2（逐字）：
#   锁文件格式：每行 <sha256><空格><空格><abs-path>
#   退出码: 0=clean, 2=tampered, 1=no-lock（自门控 no-op）
#   tampered 时 stdout 含 TAMPER(modified): 或 TAMPER(missing): + 路径
#   调用方双信号判定：rc==2 OR stdout contains "TAMPER" → 违规
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
LIB_SH="${REPO_ROOT}/plugins/autopilot/scripts/lib.sh"

fail() {
    echo "[FAIL] R_TAMPER: ${1}" >&2
    exit 1
}

pass() {
    echo "[PASS] R_TAMPER: ${1}"
}

# 前置
[[ -f "${LIB_SH}" ]] || fail "lib.sh 不存在: ${LIB_SH}"

# 断言0：两个函数定义存在性
if ! grep -qE '^lock_acceptance_tests\(\)|^function lock_acceptance_tests' "${LIB_SH}"; then
    fail "lock_acceptance_tests() 函数未定义于 lib.sh（设计文档要求新增此函数）"
fi
if ! grep -qE '^acceptance_tests_tampered\(\)|^function acceptance_tests_tampered' "${LIB_SH}"; then
    fail "acceptance_tests_tampered() 函数未定义于 lib.sh（设计文档要求新增此函数）"
fi
pass "lock_acceptance_tests() + acceptance_tests_tampered() 函数定义均存在"

# ── helper：subshell 中 source lib.sh 后调用函数 ────────────────────────────────
invoke_lock() {
    local lock_file="${1}"
    shift
    local files_args=""
    for f in "$@"; do
        files_args="${files_args} '${f}'"
    done
    bash -c "
        set -uo pipefail
        export AUTOPILOT_TEST_MODE=1
        export AUTOPILOT_DISABLE_MAIN=1
        source '${LIB_SH}' 2>/dev/null || true
        lock_acceptance_tests '${lock_file}' ${files_args}
    "
}

invoke_tampered() {
    local lock_file="${1}"
    bash -c "
        set -uo pipefail
        export AUTOPILOT_TEST_MODE=1
        export AUTOPILOT_DISABLE_MAIN=1
        source '${LIB_SH}' 2>/dev/null || true
        acceptance_tests_tampered '${lock_file}'
    "
}

# 临时 git 仓库（符合真实场景；部分实现可能依赖 git 上下文）
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# 真 git 仓库初始化
git -C "${TMP_DIR}" init -q
git -C "${TMP_DIR}" config user.email "test@test.com"
git -C "${TMP_DIR}" config user.name "Test"

LOCK_FILE="${TMP_DIR}/.acceptance-lock"

# ── 场景4.P1 + 场景4.P2：验收测试文件被改 → tamper + rc!=0 + not-PASS ──────────

TEST_FILE="${TMP_DIR}/foo.acceptance.test.sh"
echo '#!/usr/bin/env bash' > "${TEST_FILE}"
echo 'echo original' >> "${TEST_FILE}"

# 建锁
invoke_lock "${LOCK_FILE}" "${TEST_FILE}" || fail "场景4 setup: lock_acceptance_tests 调用失败"
[[ -f "${LOCK_FILE}" ]] || fail "场景4 setup: 锁文件未生成"

# 篡改测试文件
echo 'echo tampered_content' >> "${TEST_FILE}"

# 检测
out4=$(invoke_tampered "${LOCK_FILE}") ; rc4=$?

# 场景4.P1：双信号：rc==2 OR stdout contains "TAMPER"
if [[ ${rc4} -eq 0 ]] && ! echo "${out4}" | grep -q "TAMPER"; then
    fail "场景4.P1: 测试文件被改后，rc=${rc4} 且 stdout 未含 'TAMPER'，实际='${out4}'"
fi
# 场景4.P1：强断言 rc!=0（契约 C2: tampered=2）
if [[ ${rc4} -eq 0 ]]; then
    fail "场景4.P1: tamper 场景退出码应 !=0（期望 2），实际 rc=${rc4}"
fi
# 场景4.P1：stdout 须含 TAMPER（双信号之一）
if ! echo "${out4}" | grep -q "TAMPER"; then
    fail "场景4.P1: stdout 应含 'TAMPER'，实际='${out4}'"
fi
pass "场景4.P1: 验收测试文件被篡改 → rc!=0 + stdout contains TAMPER"

# 场景4.P2：tamper 时 stdout not-contains PASS / 通过证据
if echo "${out4}" | grep -qi "PASS"; then
    fail "场景4.P2: tamper 输出中不应含 'PASS'，实际='${out4}'"
fi
if echo "${out4}" | grep -q "通过证据"; then
    fail "场景4.P2: tamper 输出中不应含 '通过证据'，实际='${out4}'"
fi
pass "场景4.P2: tamper 时 stdout not-contains PASS/通过证据"

# ── 场景5.P1：仅源码改（非验收测试），验收测试未改 → rc==0 + not-TAMPER ─────────

TEST_FILE5="${TMP_DIR}/bar.acceptance.test.sh"
echo '#!/usr/bin/env bash' > "${TEST_FILE5}"
echo 'echo clean_test' >> "${TEST_FILE5}"
SRC_FILE5="${TMP_DIR}/lib.sh"
echo 'some_function() { echo hello; }' > "${SRC_FILE5}"

LOCK_FILE5="${TMP_DIR}/.acceptance-lock5"
invoke_lock "${LOCK_FILE5}" "${TEST_FILE5}" || fail "场景5 setup: lock 调用失败"

# 仅修改源码文件（不在锁内）
echo 'some_function() { echo world; }' > "${SRC_FILE5}"
# 验收测试文件不改

out5=$(invoke_tampered "${LOCK_FILE5}") ; rc5=$?

# 场景5.P1：rc==0（clean）
if [[ ${rc5} -ne 0 ]]; then
    fail "场景5.P1: 仅源码改时 rc 应 ==0（clean），实际 rc=${rc5}，stdout='${out5}'"
fi
# 场景5.P1：stdout not-contains TAMPER
if echo "${out5}" | grep -q "TAMPER"; then
    fail "场景5.P1: 仅源码改时 stdout 不应含 'TAMPER'，实际='${out5}'"
fi
pass "场景5.P1: 仅源码改、验收测试未改 → rc==0 + not-contains TAMPER"

# ── 场景6.P1：先 lock 既有文件集 → 新增未锁文件 → 既有维度判非违规(rc 0) ─────
# 显式 setup：
#   step1: 创建 A.acceptance.test.sh，lock 它
#   step2: 新增 B.acceptance.test.sh（未锁），且 A 不变
#   step3: 断言 acceptance_tests_tampered 对 lock 判 rc==0（只锁 A，B 新增不违规）

TEST_A="${TMP_DIR}/A.acceptance.test.sh"
TEST_B="${TMP_DIR}/B.acceptance.test.sh"
LOCK_FILE6="${TMP_DIR}/.acceptance-lock6"

echo '#!/usr/bin/env bash' > "${TEST_A}"
echo 'echo A_test_content' >> "${TEST_A}"

# lock 仅包含 A
invoke_lock "${LOCK_FILE6}" "${TEST_A}" || fail "场景6 setup: lock A 调用失败"

# 新增未锁的 B（A 保持不变）
echo '#!/usr/bin/env bash' > "${TEST_B}"
echo 'echo B_test_content' >> "${TEST_B}"

# 验证 A 未变
out6=$(invoke_tampered "${LOCK_FILE6}") ; rc6=$?

# 场景6.P1：既有锁定文件(A)未改 → rc==0（不报 modified）
if [[ ${rc6} -ne 0 ]]; then
    fail "场景6.P1: 既有锁定文件未改、仅新增未锁文件 B → rc 应 ==0（对既有维度非违规），实际 rc=${rc6}，stdout='${out6}'"
fi
# 场景6.P1：stdout not-contains TAMPER（A 未被标 modified）
if echo "${out6}" | grep -q "TAMPER"; then
    fail "场景6.P1: 既有锁定文件 A 未改时不应报 TAMPER，实际='${out6}'"
fi
pass "场景6.P1: 先 lock A → 新增未锁 B，A 未改 → 既有维度 rc==0 非违规"

# ── 场景 bonus：无锁文件 → rc==1 自门控 no-op ──────────────────────────────────
NO_LOCK="${TMP_DIR}/.no-such-lock"
out_nolock=$(invoke_tampered "${NO_LOCK}") ; rc_nolock=$?

if [[ ${rc_nolock} -ne 1 ]]; then
    fail "自门控(no-lock): 无锁文件时 rc 应 ==1，实际 rc=${rc_nolock}，stdout='${out_nolock}'"
fi
# 无锁不得误报 TAMPER
if echo "${out_nolock}" | grep -q "TAMPER"; then
    fail "自门控(no-lock): 无锁文件时 stdout 不应含 'TAMPER'，实际='${out_nolock}'"
fi
pass "自门控(no-lock): 无锁文件 → rc==1，不误报 TAMPER"

# ── 场景③ na 可见化成文规则 grep（场景7.P3）────────────────────────────────────
# 断言 SKILL.md 中存在"na 必须可见不得静默放行"相关成文规则
SKILL_MD="${REPO_ROOT}/plugins/autopilot/skills/autopilot/SKILL.md"
QUANTITATIVE_MD="${REPO_ROOT}/plugins/autopilot/skills/autopilot/references/quantitative-metrics.md"

[[ -f "${SKILL_MD}" ]] || fail "场景7.P3 setup: SKILL.md 不存在: ${SKILL_MD}"
[[ -f "${QUANTITATIVE_MD}" ]] || fail "场景7.P3 setup: quantitative-metrics.md 不存在: ${QUANTITATIVE_MD}"

# 场景7.P3：SKILL.md 或 references 中存在"na 必须可见"或"不得静默放行"成文规则
# 契约 C4：grep 可命中 "na" 邻近 "可见"/"显式"/"未验证"
na_rule_found=0
if grep -qE 'na.*(可见|显式|未验证|静默放行)|(可见|显式|不得静默放行).*na' "${SKILL_MD}" 2>/dev/null; then
    na_rule_found=1
fi
if grep -qE 'na.*(可见|显式|未验证|静默放行)|(可见|显式|不得静默放行).*na' "${QUANTITATIVE_MD}" 2>/dev/null; then
    na_rule_found=1
fi
if [[ ${na_rule_found} -eq 0 ]]; then
    fail "场景7.P3: SKILL.md 和 quantitative-metrics.md 中均未找到 'na 必须可见不得静默放行' 成文规则（契约 C4 grep 应命中）"
fi
pass "场景7.P3: na 可见化成文规则 grep 命中"

# ── 场景④ coverage 反向否决成文规则 grep（场景8.P3）─────────────────────────────
# 契约 C5：成文规则 grep 可命中 "反向否决" 或 "不作通过"（coverage 语义处）
coverage_rule_found=0
if grep -qE '反向否决|不作通过' "${QUANTITATIVE_MD}" 2>/dev/null; then
    coverage_rule_found=1
fi
if grep -qE '反向否决|不作通过' "${SKILL_MD}" 2>/dev/null; then
    coverage_rule_found=1
fi
if [[ ${coverage_rule_found} -eq 0 ]]; then
    fail "场景8.P3: SKILL.md 和 quantitative-metrics.md 中均未找到 'coverage 反向否决/不作通过' 成文规则（契约 C5 grep 应命中）"
fi
pass "场景8.P3: coverage 反向否决成文规则 grep 命中"

echo "[OK ] R_TAMPER acceptance-tamper-guard — 全部断言通过（场景4.P1/4.P2/5.P1/6.P1/7.P3/8.P3 + 自门控）"
exit 0
