#!/usr/bin/env bash
# R_TRACE: C6b 留痕确定性 backstop 行为断言（真跑 stop-hook 双向）+ C3 注入文案行为断言
# 红队测试 — 黑盒视角，仅基于设计契约（state.md 契约规约 C6b / C3）编写，不读取蓝队改后的
#            stop-hook.sh / lib.sh 实现来推断断言值。stop-hook.sh 当黑盒可执行文件：
#            构造临时 git 仓库 + 临时 lock + state.md 后以 stdin JSON 驱动，断言输出 JSON。
#
# 契约 C6b（逐字）：
#   行为契约：已锁验收测试文件（.acceptance-lock 列表内文件）工作区相对 index 存在差异
#     （git diff -- <lock文件> 非空，即合流 git add 之后被改过）∧ 变更日志无
#     「[auto-fix] AI 自决改红队测试」留痕（留痕行须同现「证据」字面）→ decision:block
#   基线：index（非 HEAD）——HEAD 基线对已 add 新文件恒非空，会误伤每次首次合流
#   自门控：无相关 diff / 无锁文件 → 不触发（零副作用）
#
# 谓词映射（对齐 v3.48.1 N2 真跑先例，双向缺一不可）：
#   场景① no-op 放行  → 断言 S1（lock 内文件 add 后未再改 + 无留痕 → 不触发 C6b，
#                        stop-hook 走 §9 常规路由输出「当前阶段: qa」prompt）
#                        ——该场景同时守护 index 基线选择：HEAD 基线实现会误 block 首次合流。
#   场景② block       → 断言 S2（lock 内文件 add 后工作区再改 + 静默重锁 + 变更日志无留痕
#                        → decision:block，且输出含留痕要求语义；§8.5.1 因 sha 已重锁匹配须保持静默）
#   场景③ 合规留痕    → 断言 S3（同场景但变更日志有合规留痕：含 [auto-fix] AI 自决改红队测试
#                        ∧ 证据 ∧ 已重锁 → 不触发 C6b，§9 常规路由照常）
#   自门控 no-lock    → 断言 S4（无锁文件 + 测试文件有 diff → 不触发，§9 常规路由照常）
#   契约 C3 行为半边  → 断言 S5（lock 内文件 add 后再改且未重锁 → §8.5.1 tamper 守卫真触发
#                        decision:block，注入文案含 三情形/AI 自决/AskUserQuestion/重锁/git checkout
#                        ——v3.53.0 旧文案缺「三情形」「AI 自决」，no-op 必 FAIL）
#
# 断言判别器说明：
#   phase=qa 时 stop-hook 未命中任何守卫也会在 §9 输出 decision:block（常规路由 prompt 含
#   「当前阶段: qa」）。因此「守卫触发」与「常规放行」的判别器是 reason 内容：
#   - C6b 触发 = early-exit block（§8.5 区守卫先例：§3.5/§5/§8.5.1/§8.5.2 均 early-exit），
#     输出不含 §9 常规路由的「当前阶段: qa」字样，且须携带留痕要求语义（AI 自决改红队测试，
#     或至少 留痕 ∧ 自决——守卫消息必须告知 AI 补何种留痕才可自愈）。
#   - 常规放行 = §9 路由输出，含「当前阶段: qa」。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
    REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
fi
LIB_SH="${REPO_ROOT}/plugins/autopilot/scripts/lib.sh"
STOP_HOOK="${REPO_ROOT}/plugins/autopilot/scripts/stop-hook.sh"

fail() {
    echo "[FAIL] R_TRACE: $1" >&2
    exit 1
}

pass() {
    echo "[PASS] R_TRACE: $1"
}

# 前置
[[ -f "${LIB_SH}" ]] || fail "lib.sh 不存在: ${LIB_SH}"
[[ -f "${STOP_HOOK}" ]] || fail "stop-hook.sh 不存在: ${STOP_HOOK}"
command -v jq >/dev/null 2>&1 || fail "jq 不可用（stop-hook 输出 JSON 构造依赖 jq）"
command -v git >/dev/null 2>&1 || fail "git 不可用"

# 断言0：C6 行为前置——lock 函数定义存在（C6b 守卫的依赖面）
if ! grep -qE '^lock_acceptance_tests\(\)|^function lock_acceptance_tests' "${LIB_SH}"; then
    fail "lock_acceptance_tests() 未定义于 lib.sh（C6 零改动区被破坏，C6b 行为断言失去依赖面）"
fi
if ! grep -qE '^acceptance_tests_tampered\(\)|^function acceptance_tests_tampered' "${LIB_SH}"; then
    fail "acceptance_tests_tampered() 未定义于 lib.sh（C6 零改动区被破坏）"
fi
pass "lock_acceptance_tests() + acceptance_tests_tampered() 定义在位"

TMPROOT=$(mktemp -d)
trap 'rm -rf "${TMPROOT}"' EXIT

SLUG="20260908-c6b-trace-behavior"
SESSION="c6b-trace-session"

# mk_repo <changelog_extra>：临时 git 仓库 + baseline commit（不含验收测试文件，镜像真实
# 合流时序：验收测试为 staged 新文件）+ active.ptr + state.md（phase=qa）。
# $1 = 附加变更日志行（空串 = 只有中性行）
mk_repo() {
    local extra="${1:-}"
    local d
    d=$(mktemp -d "${TMPROOT}/repo.XXXXXX") || fail "mktemp 失败"
    git -C "${d}" init -q
    git -C "${d}" config user.email "redteam@test.local"
    git -C "${d}" config user.name "redteam"
    mkdir -p "${d}/plugins/autopilot/tests/acceptance"
    printf 'placeholder baseline\n' > "${d}/README.md"
    git -C "${d}" add README.md
    git -C "${d}" commit -qm "baseline (no acceptance test)"
    local task_dir="${d}/.autopilot/runtime/requirements/${SLUG}"
    mkdir -p "${task_dir}"
    printf '%s\n' "${SLUG}" > "${d}/.autopilot/runtime/active.ptr"
    {
        cat <<EOF_STATE
---
active: true
phase: "qa"
gate: ""
iteration: 1
max_iterations: 30
max_retries: 3
retry_count: 0
mode: ""
plan_mode: ""
fast_mode:
brief_file: ""
next_task: ""
auto_approve: false
knowledge_extracted: ""
task_dir: "${task_dir}"
session_id: "${SESSION}"
started_at: "2026-09-08T00:00:00Z"
contract_required: false
html_review: false
---

## 目标
C6b 留痕守卫行为断言临时任务

## 变更日志
- [2026-09-08T00:00:00Z] init
EOF_STATE
        if [[ -n "${extra}" ]]; then
            printf '%s\n' "${extra}"
        fi
    } > "${task_dir}/state.md"
    printf '%s' "${d}"
}

# lock_via_lib <lock_file> <test_file>：subshell source lib.sh 调 lock_acceptance_tests
# （镜像 §8.5.0.5 合流时序：mv → git add → lock_acceptance_tests）
lock_via_lib() {
    local lock_file="${1}"
    local test_file="${2}"
    bash -c "
        set -uo pipefail
        export AUTOPILOT_TEST_MODE=1
        export AUTOPILOT_DISABLE_MAIN=1
        source '${LIB_SH}' 2>/dev/null || true
        lock_acceptance_tests '${lock_file}' '${test_file}'
    " || fail "lock_acceptance_tests 调用失败（lock=${lock_file}）"
    [[ -f "${lock_file}" ]] || fail "锁文件未生成: ${lock_file}"
}

# run_hook <repo>：以 stdin JSON 驱动 stop-hook（黑盒），返回 stdout（block JSON 走 stdout）
run_hook() {
    local repo="${1}"
    printf '{"cwd":"%s","session_id":"%s","transcript_path":""}' "${repo}" "${SESSION}" \
        | bash "${STOP_HOOK}" 2>/dev/null
}

assert_block() {  # assert_block <out> <label>
    if ! printf '%s' "${1}" | grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"'; then
        fail "${2}: 期望 decision:block，实际输出='${1}'"
    fi
}

assert_routine_qa_reached() {  # §9 常规路由到达 = 无守卫 early-exit 拦截
    if ! printf '%s' "${1}" | grep -qF '当前阶段: qa'; then
        fail "${2}: 期望到达 §9 常规路由（输出含「当前阶段: qa」），实际被守卫 early-exit 拦截，输出='${1}'"
    fi
}

# ============================================================================
# 断言 S1（C6b 场景①，no-op 放行 / index 基线回归守卫）：
#   lock 内文件 add 后未再改 + 无留痕 → C6b 不触发，§9 常规路由照常。
#   反例检验：若守卫误用 HEAD 基线（staged 新文件对 HEAD 恒非空 diff），此处会误 block
#   → 「当前阶段: qa」缺失 → FAIL（设计文档明示的 HEAD 基线回归）。
# ============================================================================
R1=$(mk_repo "")
TEST1="${R1}/plugins/autopilot/tests/acceptance/foo.acceptance.test.sh"
printf '#!/usr/bin/env bash\necho "acceptance baseline"\n' > "${TEST1}"
git -C "${R1}" add -- "${TEST1}"
lock_via_lib "${R1}/.autopilot/runtime/requirements/${SLUG}/.acceptance-lock" "${TEST1}"

out1=$(run_hook "${R1}")
assert_block "${out1}" "S1"
assert_routine_qa_reached "${out1}" "S1（C6b 场景①：已 add 未再改 + 无留痕，须自门控放行）"
pass "S1: 已 add 未再改 + 无留痕 → C6b 自门控不触发，§9 常规路由照常（index 基线回归守卫通过）"

# ============================================================================
# 断言 S2（C6b 场景②，核心 block 方向——「AI 修改 + 静默重锁」主放水面）：
#   lock 内文件 add 后工作区再改 + 重锁（sha 匹配使 §8.5.1 静默）+ 变更日志无留痕
#   → decision:block，early-exit（无 §9 常规路由字样），输出携带留痕要求语义。
# ============================================================================
R2=$(mk_repo "")
TEST2="${R2}/plugins/autopilot/tests/acceptance/foo.acceptance.test.sh"
printf '#!/usr/bin/env bash\necho "acceptance baseline"\n' > "${TEST2}"
git -C "${R2}" add -- "${TEST2}"
LOCK2="${R2}/.autopilot/runtime/requirements/${SLUG}/.acceptance-lock"
lock_via_lib "${LOCK2}" "${TEST2}"
# 模拟 AI 静默修改红队测试 + 重锁（v3.53.0 dogfood 实证主放水面：改后重锁使 §8.5.1 失明）
printf '# AI silently modified the red-team test\n' >> "${TEST2}"
lock_via_lib "${LOCK2}" "${TEST2}"

out2=$(run_hook "${R2}")
assert_block "${out2}" "S2（C6b 场景②：diff ∧ 无留痕 → 须 block）"
if printf '%s' "${out2}" | grep -qF '当前阶段: qa'; then
    fail "S2: 输出含 §9 常规路由「当前阶段: qa」——C6b 守卫未 early-exit 拦截（diff ∧ 无留痕场景放水），输出='${out2}'"
fi
if printf '%s' "${out2}" | grep -qF 'TAMPER'; then
    fail "S2: 输出含 TAMPER——§8.5.1 tamper 守卫不应触发（测试已重锁 sha 匹配）；若非本测试 setup 问题，则 §8.5.1 触发条件被本改动破坏（C6 零改动区）"
fi
if printf '%s' "${out2}" | grep -qF 'AI 自决改红队测试'; then
    :
elif printf '%s' "${out2}" | grep -qF '留痕' && printf '%s' "${out2}" | grep -qF '自决'; then
    :
else
    fail "S2: block 输出未携带留痕要求语义（须含「AI 自决改红队测试」留痕标记，或至少「留痕」∧「自决」）——守卫 block 后 AI 无从得知须补何种留痕，确定性执法不可自愈，输出='${out2}'"
fi
pass "S2: diff ∧ 无留痕（静默重锁）→ C6b decision:block + early-exit + 留痕要求语义（§8.5.1 静默）"

# ============================================================================
# 断言 S3（C6b 场景③，合规留痕放行）：
#   同场景但变更日志有合规留痕（含 [auto-fix] AI 自决改红队测试 ∧ 证据 ∧ 已重锁）
#   → C6b 不触发，§9 常规路由照常（AI 自决合规路径零打断）。
# ============================================================================
COMPLIANT_TRACE="- [auto-fix] AI 自决改红队测试 plugins/autopilot/tests/acceptance/foo.acceptance.test.sh，情形①，证据 E1: 设计文档 ## 契约规约 C2 字段级 diff 对照（grep -n 输出已留 QA 报告），已重锁"
R3=$(mk_repo "${COMPLIANT_TRACE}")
TEST3="${R3}/plugins/autopilot/tests/acceptance/foo.acceptance.test.sh"
printf '#!/usr/bin/env bash\necho "acceptance baseline"\n' > "${TEST3}"
git -C "${R3}" add -- "${TEST3}"
LOCK3="${R3}/.autopilot/runtime/requirements/${SLUG}/.acceptance-lock"
lock_via_lib "${LOCK3}" "${TEST3}"
printf '# AI modified with evidence and trace\n' >> "${TEST3}"
lock_via_lib "${LOCK3}" "${TEST3}"

out3=$(run_hook "${R3}")
assert_block "${out3}" "S3（§9 常规路由本身为 block）"
assert_routine_qa_reached "${out3}" "S3（C6b 场景③：diff ∧ 合规留痕 → 守卫不得触发）"
pass "S3: diff ∧ 合规留痕（AI 自决改红队测试 + 证据 + 已重锁）→ C6b 不触发，§9 常规路由照常（合规自决路径零打断）"

# ============================================================================
# 断言 S4（C6b 自门控 no-lock）：
#   无锁文件 + 测试文件 add 后再改 → C6b 不触发（无锁=未进入受保护期），§9 常规路由照常。
#   同时覆盖 C6：§8.5.1 的 no-lock 自门控（acceptance_tests_tampered rc==1 → 不触发）。
# ============================================================================
R4=$(mk_repo "")
TEST4="${R4}/plugins/autopilot/tests/acceptance/foo.acceptance.test.sh"
printf '#!/usr/bin/env bash\necho "acceptance baseline"\n' > "${TEST4}"
git -C "${R4}" add -- "${TEST4}"
printf '# modified but never locked\n' >> "${TEST4}"

out4=$(run_hook "${R4}")
assert_block "${out4}" "S4（§9 常规路由本身为 block）"
assert_routine_qa_reached "${out4}" "S4（C6b 自门控：无锁文件 → 不得触发）"
pass "S4: 无锁文件 → C6b/§8.5.1 自门控不触发，§9 常规路由照常"

# ============================================================================
# 断言 S5（契约 C3 行为半边 + C6 触发不变量）：
#   lock 内文件 add 后工作区再改且未重锁 → §8.5.1 tamper 守卫真触发 decision:block，
#   注入文案须含 五字面：三情形 / AI 自决 / AskUserQuestion / 重锁 / git checkout。
#   v3.53.0 旧文案缺「三情形」「AI 自决」→ no-op 必 FAIL；同时验证 §8.5.1 仍在
#   implement→qa 窗口触发（C6 触发条件零改动）。
# ============================================================================
R5=$(mk_repo "")
TEST5="${R5}/plugins/autopilot/tests/acceptance/foo.acceptance.test.sh"
printf '#!/usr/bin/env bash\necho "acceptance baseline"\n' > "${TEST5}"
git -C "${R5}" add -- "${TEST5}"
LOCK5="${R5}/.autopilot/runtime/requirements/${SLUG}/.acceptance-lock"
lock_via_lib "${LOCK5}" "${TEST5}"
printf '# modified WITHOUT re-lock: sha mismatch\n' >> "${TEST5}"

out5=$(run_hook "${R5}")
assert_block "${out5}" "S5（§8.5.1 篡改触发）"
if ! printf '%s' "${out5}" | grep -qF 'TAMPER'; then
    fail "S5: §8.5.1 应触发（sha 不匹配）但输出未含 TAMPER 双信号，输出='${out5}'——tamper 守卫检测链路失效（C6 零改动区被破坏）"
fi
for lit in '三情形' 'AI 自决' 'AskUserQuestion' '重锁' 'git checkout'; do
    if ! printf '%s' "${out5}" | grep -qF "${lit}"; then
        fail "S5/C3: §8.5.1 block 注入文案缺字面「${lit}」（C3 五字面闭集）——文案未同步双层决策树，实际='${out5}'"
    fi
done
pass "S5: 未重锁篡改 → §8.5.1 真触发 block + 文案含三情形/AI 自决/AskUserQuestion/重锁/git checkout（C3 行为半边 + C6 触发不变量）"

echo "[OK ] R_TRACE red-team-trace-backstop — 全部断言通过（S1/S2/S3/S4/S5：C6b 双向真跑 + no-lock 自门控 + C3 注入文案行为断言）"
exit 0
