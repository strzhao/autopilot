#!/usr/bin/env bash
# R_FRESH: 验证 lib.sh freshness_check 函数五路径决策
# 红队测试 — 仅基于设计文档契约 C1 和 19 条谓词 SSOT 编写，不读取蓝队实现
#
# 覆盖谓词：
#   场景1.P1 [real-process]: 源码 mtime > 产物 mtime → STALE + rc!=0
#   场景1.P2 [det-machine]:  STALE 时 stdout not-contains "PASS"
#   场景2.P1 [real-process]: 产物 mtime >= 源码 mtime → FRESH + rc==0
#   场景3.P1 [real-process]: 解释型目录产物(dist/)，src mtime > dist mtime → STALE + rc!=0
#   场景3.P2 [det-machine]:  无可识别产物 → stdout != "FRESH"（输出 UNKNOWN）
#
# 契约 C1（逐字）：
#   stdout: STALE | FRESH | UNKNOWN（三选一，单 token）
#   退出码: FRESH=0, STALE=1, UNKNOWN=1
#   算法:   find -newer（禁用 stat -f/-c）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
LIB_SH="${REPO_ROOT}/plugins/autopilot/scripts/lib.sh"

fail() {
    echo "[FAIL] R_FRESH: ${1}" >&2
    exit 1
}

pass() {
    echo "[PASS] R_FRESH: ${1}"
}

# 前置：lib.sh 必须存在
[[ -f "${LIB_SH}" ]] || fail "lib.sh 不存在: ${LIB_SH}"

# 断言0：函数定义存在性（契约 C1 前置）
if ! grep -qE '^freshness_check\(\)|^function freshness_check' "${LIB_SH}"; then
    fail "freshness_check() 函数未定义于 lib.sh（设计文档要求新增此函数）"
fi
pass "freshness_check() 函数定义存在"

# ── helper：在子 shell 中 source lib.sh 后调用 freshness_check ─────────────────
# 返回：stdout 写入变量、退出码通过 $? 保留
# 用法：invoke_freshness <product> <src_dir> → stdout
invoke_freshness() {
    local product="${1}"
    local src_dir="${2}"
    bash -c "
        set -uo pipefail
        export AUTOPILOT_TEST_MODE=1
        export AUTOPILOT_DISABLE_MAIN=1
        source '${LIB_SH}' 2>/dev/null || true
        freshness_check '${product}' '${src_dir}'
    "
}

# 临时工作目录
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# ── 场景1.P1 + 场景1.P2：源码 mtime > 产物 mtime → STALE + rc!=0 + not-PASS ──

PROD_FILE="${TMP_DIR}/bundle.js"
SRC_DIR="${TMP_DIR}/src1"
mkdir -p "${SRC_DIR}"

# 先创建产物（旧）
touch "${PROD_FILE}"
# 等 1 秒确保 mtime 差（用 sleep 1 确保 find -newer 能区分）
sleep 1
# 再创建比产物更新的源码文件
touch "${SRC_DIR}/app.ts"

out1=$(invoke_freshness "${PROD_FILE}" "${SRC_DIR}") ; rc1=$?

# 场景1.P1：rc!=0
if [[ ${rc1} -eq 0 ]]; then
    fail "场景1.P1: 源码更新时 freshness_check 退出码应 !=0，实际 rc=${rc1}"
fi
# 场景1.P1：stdout contains "STALE"
if ! echo "${out1}" | grep -q "STALE"; then
    fail "场景1.P1: stdout 应含 'STALE'，实际='${out1}'"
fi
pass "场景1.P1: 源码 mtime > 产物 mtime → STALE + rc!=0"

# 场景1.P2：STALE 时 stdout not-contains "PASS"（大小写不敏感）
if echo "${out1}" | grep -qi "PASS"; then
    fail "场景1.P2: STALE 输出中不应含 'PASS'，实际='${out1}'"
fi
pass "场景1.P2: STALE 时 stdout not-contains PASS"

# ── 场景2.P1：产物 mtime >= 源码 mtime → FRESH + rc==0 ─────────────────────────

PROD_FILE2="${TMP_DIR}/bundle2.js"
SRC_DIR2="${TMP_DIR}/src2"
mkdir -p "${SRC_DIR2}"

# 先创建源码
touch "${SRC_DIR2}/app.ts"
sleep 1
# 再创建产物（更新）
touch "${PROD_FILE2}"

out2=$(invoke_freshness "${PROD_FILE2}" "${SRC_DIR2}") ; rc2=$?

# 场景2.P1：rc==0
if [[ ${rc2} -ne 0 ]]; then
    fail "场景2.P1: 产物更新时 freshness_check 退出码应 ==0，实际 rc=${rc2}，stdout='${out2}'"
fi
# 场景2.P1：stdout contains "FRESH"
if ! echo "${out2}" | grep -q "FRESH"; then
    fail "场景2.P1: stdout 应含 'FRESH'，实际='${out2}'"
fi
pass "场景2.P1: 产物 mtime >= 源码 mtime → FRESH + rc==0"

# ── 场景3.P1：解释型目录产物(dist/)，src mtime > dist mtime → STALE ────────────

DIST_DIR="${TMP_DIR}/dist"
SRC_DIR3="${TMP_DIR}/src3"
mkdir -p "${DIST_DIR}" "${SRC_DIR3}"

# 先创建 dist 目录中的文件（旧产物）
touch "${DIST_DIR}/main.js"
sleep 1
# 再创建更新的源码
touch "${SRC_DIR3}/index.ts"

out3=$(invoke_freshness "${DIST_DIR}" "${SRC_DIR3}") ; rc3=$?

# 场景3.P1：rc!=0
if [[ ${rc3} -eq 0 ]]; then
    fail "场景3.P1: 解释型 dist/ 场景，源码更新时 rc 应 !=0，实际 rc=${rc3}"
fi
# 场景3.P1：stdout contains "STALE"
if ! echo "${out3}" | grep -q "STALE"; then
    fail "场景3.P1: 解释型 dist/ 场景，stdout 应含 'STALE'，实际='${out3}'"
fi
pass "场景3.P1: 解释型 dist/ 目录产物，src mtime > dist mtime → STALE + rc!=0"

# ── 场景3.P2：无可识别产物 → stdout != "FRESH"（应为 UNKNOWN）────────────────

NONEXIST_PROD="${TMP_DIR}/no_such_product_xyz"
SRC_DIR4="${TMP_DIR}/src4"
mkdir -p "${SRC_DIR4}"
touch "${SRC_DIR4}/code.ts"

out4=$(invoke_freshness "${NONEXIST_PROD}" "${SRC_DIR4}") ; rc4=$?

# 场景3.P2：stdout 不得为 FRESH
if echo "${out4}" | grep -q "^FRESH$"; then
    fail "场景3.P2: 无产物时 stdout 不应为 'FRESH'，实际='${out4}'"
fi
# 额外验证：应为 UNKNOWN（契约 C1 逐字）
if ! echo "${out4}" | grep -q "UNKNOWN"; then
    fail "场景3.P2: 无产物时 stdout 应含 'UNKNOWN'，实际='${out4}'"
fi
# 无产物时 rc 应 !=0（契约 C1: UNKNOWN=rc1）
if [[ ${rc4} -eq 0 ]]; then
    fail "场景3.P2: 无产物时 rc 应 !=0（UNKNOWN 不放行），实际 rc=${rc4}"
fi
pass "场景3.P2: 无可识别产物 → UNKNOWN（not-FRESH） + rc!=0"

echo "[OK ] R_FRESH freshness-check — 全部断言通过（场景1.P1/1.P2/2.P1/3.P1/3.P2）"
exit 0
