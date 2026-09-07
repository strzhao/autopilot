#!/usr/bin/env bash
# R_P3-MECH: p3-mechanism-hygiene 机制卫生三项 + v3.65.0 版本同步
# 红队测试 — 仅基于设计文档契约 C8/C9/C10/C11/C5 与 21 场景 31 谓词 SSOT 编写，
# 不读取蓝队实现文件（lib.sh / stop-hook.sh / setup.sh / doctor SKILL.md / 版本 4 文件）；
# 运行时对被实现文件的 fs-grep 锚点字面全部取自契约/谓词（load_state、RUNTIME-SIZE-WARN、
# cleanup_artifacts_ttl、detect_runtime_size、normalize_enum_value 等）。
#
# 覆盖谓词（场景组 → 谓词）：
#   场景 1: 1.P1 1.P2        load_state 全字段批量输出 + eval 后变量回读
#   场景 2: 2.P1             重复键取第一
#   场景 3: 3.P1             特殊值（空格/分号/单引号/不配对引号）eval 字面回读无执行
#   场景 4: 4.P1             frontmatter 外正文（含伪 --- 块）零混入
#   场景 5: 5.P1             $(touch canary) 注入字面量保存 + 非法键 eval 容错
#   场景 6: 6.P1 6.P2        normalize_enum_value 复用平价 + 无重复定义
#   场景 8: 8.P1 8.P2        stop-hook load_state 接线 + get_field/get_enum_field 定义保留
#   场景 9: 9.P1 9.P2        状态切换重读行为 + load_state 调用点 ≥6
#   场景10: 10.P1-10.P3      TTL 过期删/新鲜留/空目录删非空留
#   场景11: 11.P1            目录不存在 rc==0 静默
#   场景12: 12.P1            幂等二跑目录树 diff 空
#   场景13: 13.P1            目录外哨兵零触碰
#   场景14: 14.P1            setup.sh 接线含容错
#   场景15: 15.P1            已知体积 KB 整数 ≥已知
#   场景16: 16.P1            目录缺失输出 0 rc==0 无警告
#   场景17: 17.P1 17.P2      >500MB 附 RUNTIME-SIZE-WARN / 低于不附
#   场景18: 18.P1 18.P2      doctor 接线 + 报告 runtime 体积行（SKILL.md 为 AI doctor 的
#                            机器可查 SSOT，接线行即契约锚点；"doctor 冒烟"的运行时
#                            报告数字由 AI 产出，机器可查等价锚点为 SKILL 接线行）
#   场景19: 19.P1 19.P2      版本四处动态一致 + 承载字段行无旧版本残留
#   场景20: 20.P1            stop-hook get_field/get_enum_field 直调==0 ∧ load_state>=6
#   场景21: 21.P1            对抗 fixture 上 load_state eval 回读 == get_field 逐字段平价
#   （场景 7.P1 run-all / 7.P2 npm test 归编排器 QA，不在本文件）
#
# 行为真跑全部在 mktemp -d 临时目录构造，不读当前工作区 git 状态；EXIT trap 清理。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
LIB_SH="${REPO_ROOT}/plugins/autopilot/scripts/lib.sh"
STOP_HOOK="${REPO_ROOT}/plugins/autopilot/scripts/stop-hook.sh"
SETUP_SH="${REPO_ROOT}/plugins/autopilot/scripts/setup.sh"
DOCTOR_SKILL="${REPO_ROOT}/plugins/autopilot/skills/autopilot-doctor/SKILL.md"
PLUGIN_JSON="${REPO_ROOT}/plugins/autopilot/.claude-plugin/plugin.json"
MARKETPLACE="${REPO_ROOT}/.claude-plugin/marketplace.json"
REPO_CLAUDE_MD="${REPO_ROOT}/CLAUDE.md"
AUTOPILOT_README="${REPO_ROOT}/plugins/autopilot/README.md"

PASS_COUNT=0
FAIL_COUNT=0

fail() {
    echo "[FAIL] R_P3-MECH: $1" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
}
pass() {
    echo "[PASS] R_P3-MECH: $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

# 观察产物落点（谓词 artifact 字段指定 /tmp/autopilot-artifacts/）
art() {
    mkdir -p /tmp/autopilot-artifacts 2>/dev/null || true
    printf '%s\n' "$1" > "/tmp/autopilot-artifacts/$2" 2>/dev/null || true
}

# ── lib.sh 真跑隔离器 ─────────────────────────────────────────────────────────
# 子进程 bash -c 中 source lib.sh，隔离顶层 trap 'exit 0' ERR 等 source 副作用。
# $1 = snippet；snippet 内通过 $ST / $ST_A / $ST_B / $PAIRS / $CWD_T 等已 export
# 的变量引用 fixture 路径（$1 的插入文本不被外层再次展开）。
lib_run() {
    bash -c "
set -uo pipefail
export AUTOPILOT_TEST_MODE=1
export AUTOPILOT_DISABLE_MAIN=1
source '${LIB_SH}' >/dev/null 2>&1
$1
"
}

# 临时根目录 + 清理
TMP_BASE="$(mktemp -d)"
trap 'rm -rf "${TMP_BASE}"' EXIT

# ── 前置：被测函数定义必须存在（no-op 时以下全部失败）────────────────────────
for fn in load_state cleanup_artifacts_ttl detect_runtime_size normalize_enum_value; do
    if ! grep -qE "^(function[[:space:]]+)?${fn}[[:space:]]*\(\)" "${LIB_SH}" 2>/dev/null; then
        echo "[FATAL] R_P3-MECH: lib.sh 缺少函数定义 ${fn}()（设计文档要求），终止" >&2
        exit 1
    fi
done
for f in "${STOP_HOOK}" "${SETUP_SH}" "${DOCTOR_SKILL}" "${PLUGIN_JSON}" \
         "${MARKETPLACE}" "${REPO_CLAUDE_MD}" "${AUTOPILOT_README}"; do
    [[ -f "$f" ]] || { echo "[FATAL] R_P3-MECH: 契约锚点文件不存在: $f" >&2; exit 1; }
done

# ════════════════════════════════════════════════════════════════════════════
# 场景 1：load_state 全字段批量输出 + eval 后变量可读（1.P1 / 1.P2）
# ════════════════════════════════════════════════════════════════════════════
F1="${TMP_BASE}/s1-state.md"
cat > "${F1}" <<'EOF'
---
phase: review-accept
gate: review-accept
auto_approve: false
iteration: 3
max_iterations: 5
project_name: hello world
---
# body should be ignored
EOF
export ST="${F1}"

# 1.P1：单次输出恰好 N 行 KEY=<值>，逐行合法 KEY= 前缀
out1="$(lib_run 'load_state "$ST"')"
rc1=$?
art "${out1}" "load-state-bulk.out"
if [[ ${rc1} -eq 0 ]]; then
    pass "场景1.P1-pre: load_state <file> rc==0"
else
    fail "场景1.P1-pre: load_state rc 应为 0，实际 rc=${rc1}"
fi
n_total="$(printf '%s\n' "${out1}" | grep -c .)"
n_fmt="$(printf '%s\n' "${out1}" | grep -cE '^[a-z_][a-z0-9_]*=')"
if [[ ${n_total} -eq 6 && ${n_fmt} -eq 6 ]]; then
    pass "场景1.P1: 6 字段 state.md → 恰好 6 行 KEY=<值>（total=${n_total} fmt=${n_fmt}）"
else
    fail "场景1.P1: 期望恰好 6 行合法 KEY= 输出，实际 total=${n_total} fmt=${n_fmt}，输出=[${out1}]"
fi

# 1.P2：eval 后产生与 frontmatter 同名且值正确的变量
res1="$(lib_run 'eval "$(load_state "$ST")" 2>/dev/null; printf "p=%s|g=%s|a=%s|i=%s|m=%s|n=%s" "$phase" "$gate" "$auto_approve" "$iteration" "$max_iterations" "$project_name"')"
art "${res1}" "load-state-vars.out"
exp1='p=review-accept|g=review-accept|a=false|i=3|m=5|n=hello world'
if [[ "${res1}" == "${exp1}" ]]; then
    pass "场景1.P2: eval 后每字段与 frontmatter 一致（含含空格值不 word-split）"
else
    fail "场景1.P2: eval 回读期望[${exp1}]，实际[${res1}]"
fi

# C8 边界（附加，非编号谓词）：文件缺失 → 空输出 rc=0
MISSING1="${TMP_BASE}/no-such-state.md"
res1m="$(lib_run "load_state '${MISSING1}'")"
rc1m=$?
if [[ ${rc1m} -eq 0 && -z "${res1m}" ]]; then
    pass "C8边界: 文件缺失 → 空输出 rc=0"
else
    fail "C8边界: 文件缺失期望空输出 rc=0，实际 rc=${rc1m} 输出=[${res1m}]"
fi

# ════════════════════════════════════════════════════════════════════════════
# 场景 2：重复键取第一（2.P1）
# ════════════════════════════════════════════════════════════════════════════
F2="${TMP_BASE}/s2-state.md"
cat > "${F2}" <<'EOF'
---
dupkey: first-value
dupkey: second-value
phase: keep
---
EOF
export ST="${F2}"
res2="$(lib_run 'eval "$(load_state "$ST")" 2>/dev/null; printf "d=%s" "$dupkey"')"
dl2="$(lib_run 'load_state "$ST" | grep -c "^dupkey="')"
art "${res2}" "load-state-dup-key.out"
if [[ "${res2}" == "d=first-value" ]]; then
    pass "场景2.P1: 重复键取第一处值（first-value ≠ second-value）"
else
    fail "场景2.P1: 重复键期望取第一处 first-value，实际[${res2}]"
fi
if [[ "${dl2}" == "1" ]]; then
    pass "场景2.P1-附: 重复键只输出 1 行（grep -c ^dupkey= =1）"
else
    fail "场景2.P1-附: 重复键输出行数期望 1，实际=${dl2}"
fi

# ════════════════════════════════════════════════════════════════════════════
# 场景 3：特殊值转义 eval 平价（3.P1）— 空格/分号/单引号/不配对引号
# ════════════════════════════════════════════════════════════════════════════
F3="${TMP_BASE}/s3-state.md"
cat > "${F3}" <<'EOF'
---
sp: two words
semi: a;b
sq: it's good
uq: va"lue
q2: "open
---
EOF
CWD_T="${TMP_BASE}/s3-cwd"
mkdir -p "${CWD_T}"
export ST="${F3}" CWD_T
res3="$(lib_run 'cd "$CWD_T" || exit 9
rm -f canary
eval "$(load_state "$ST")" 2>/dev/null
erc=$?
echo "R sp=[$sp] semi=[$semi] sq=[$sq] uq=[$uq] q2=[$q2]"
echo "ERC=$erc"
if [[ -e canary ]]; then echo CANARY_EXISTS; else echo NO_CANARY; fi
')"
art "${res3}" "load-state-dequote.out"
for marker in 'sp=[two words]' 'semi=[a;b]' "sq=[it's good]" 'uq=[va"lue]' 'q2=["open]'; do
    if printf '%s' "${res3}" | grep -qF "${marker}"; then
        pass "场景3.P1: 字面回读 ${marker}"
    else
        fail "场景3.P1: 字面回读缺失 ${marker}，实际输出=[${res3}]"
    fi
done
if printf '%s' "${res3}" | grep -q '^ERC=0$'; then
    pass "场景3.P1: eval rc 干净（ERC=0，转义值全部为合法赋值）"
else
    fail "场景3.P1: eval rc 不干净（含不配对引号/分号值时应仍为合法赋值），输出=[${res3}]"
fi
if printf '%s' "${res3}" | grep -q '^NO_CANARY$'; then
    pass "场景3.P1: 无副作用哨兵（canary 不存在）"
else
    fail "场景3.P1: canary 被创建 = 存在命令执行/word-split 注入，输出=[${res3}]"
fi

# ════════════════════════════════════════════════════════════════════════════
# 场景 4：frontmatter 外正文零混入（4.P1）— 含正文伪 --- 块
# ════════════════════════════════════════════════════════════════════════════
F4="${TMP_BASE}/s4-state.md"
cat > "${F4}" <<'EOF'
---
phase: real-value
---
FAKE_KEY: injected
---
phase: body-fake
more: body-lines
---
EOF
export ST="${F4}"
res4="$(lib_run 'eval "$(load_state "$ST")" 2>/dev/null; printf "phase=%s fake=%s" "${phase:-UNSET}" "${FAKE_KEY:-MISS}"')"
art "${res4}" "load-state-body-excluded.out"
if [[ "${res4}" == "phase=real-value fake=MISS" ]]; then
    pass "场景4.P1: 正文伪字段/伪 --- 块零混入（FAKE_KEY=MISS ∧ phase=real-value）"
else
    fail "场景4.P1: 正文混入或首对 frontmatter 未正确闭合定位，实际[${res4}]"
fi

# ════════════════════════════════════════════════════════════════════════════
# 场景 5：注入安全 + 非法键容错（5.P1）
# ════════════════════════════════════════════════════════════════════════════
F5="${TMP_BASE}/s5-state.md"
cat > "${F5}" <<'EOF'
---
payload: $(touch canary)
bt: `id`
bad-key!: v
---
EOF
CWD_T="${TMP_BASE}/s5-cwd"
mkdir -p "${CWD_T}"
export ST="${F5}" CWD_T
res5="$(lib_run 'cd "$CWD_T" || exit 9
rm -f canary
eval "$(load_state "$ST")" 2>/dev/null || echo TOLERATED
echo "P payload=[${payload:-UNSET}] bt=[${bt:-UNSET}]"
if [[ -e canary ]]; then echo CANARY_EXISTS; else echo NO_CANARY; fi
')"
rc5=$?
art "${res5}" "load-state-injection-safe.out"
if [[ ${rc5} -eq 0 ]]; then
    pass "场景5.P1: eval 容错 rc 不污染（容错接线后整体 rc==0）"
else
    fail "场景5.P1: 容错接线后整体 rc 应为 0，实际 rc=${rc5}，输出=[${res5}]"
fi
if printf '%s' "${res5}" | grep -qF 'payload=[$(touch canary)]'; then
    pass "场景5.P1: \$(touch canary) 字面量保存（不执行）"
else
    fail "场景5.P1: \$(touch canary) 未按字面量保存或变量丢失，输出=[${res5}]"
fi
if printf '%s' "${res5}" | grep -qF 'bt=[`id`]'; then
    pass "场景5.P1-附: 反引号载荷字面量保存"
else
    fail "场景5.P1-附: 反引号载荷被执行或丢失，输出=[${res5}]"
fi
if printf '%s' "${res5}" | grep -q '^NO_CANARY$'; then
    pass "场景5.P1: canary 不存在（零命令执行）"
else
    fail "场景5.P1: canary 被创建 = 注入执行，输出=[${res5}]"
fi
lib_run 'load_state "$ST" >/dev/null' 2>/dev/null
rc5b=$?
if [[ ${rc5b} -eq 0 ]]; then
    pass "场景5.P1: 含非法键文件上 load_state 自身 rc 干净"
else
    fail "场景5.P1: 含非法键文件上 load_state rc 应为 0，实际=${rc5b}"
fi

# ════════════════════════════════════════════════════════════════════════════
# 场景 6：枚举归一复用 normalize_enum_value（6.P1 / 6.P2）
# ════════════════════════════════════════════════════════════════════════════
F6="${TMP_BASE}/s6-state.md"
P6="${TMP_BASE}/s6-pairs.txt"
{
    echo "---"
    i=1
    for v in review-accept REVIEW-ACCEPT Review-Accept true True TRUE skipped SKIPPED fast FAST; do
        printf 'k%02d: %s\n' "${i}" "${v}"
        printf 'k%02d %s\n' "${i}" "${v}" >> "${P6}"
        i=$((i + 1))
    done
    echo "---"
} > "${F6}"
export ST="${F6}" PAIRS="${P6}"
res6="$(lib_run 'STATE_FILE="$ST"
ok=1
while read -r key val; do
    g="$(get_enum_field "$key")"
    n="$(normalize_enum_value "$val")"
    [[ "$g" == "$n" ]] || { echo "MISMATCH $key g=[$g] n=[$n]"; ok=0; }
done < "$PAIRS"
[[ $ok -eq 1 ]] && echo PARITY_OK
')"
art "${res6}" "normalize-enum-parity.out"
if printf '%s' "${res6}" | grep -q '^PARITY_OK$'; then
    pass "场景6.P1: normalize_enum_value 与 get_enum_field 输出逐对一致（10 变体复用非重造）"
else
    fail "场景6.P1: 枚举归一平价失败，输出=[${res6}]"
fi

ncalls="$(grep -c 'normalize_enum_value' "${STOP_HOOK}")"
ndef="$( { grep -cE 'normalize_enum[[:space:]]*\(\)' "${LIB_SH}" || true; grep -cE 'normalize_enum[[:space:]]*\(\)' "${STOP_HOOK}" || true; } | awk '{s+=$1} END{print s}')"
art "calls=${ncalls} dupdefs=${ndef}" "normalize-enum-defined.out"
if [[ ${ncalls} -ge 1 && ${ndef} -eq 0 ]]; then
    pass "场景6.P2: stop-hook 枚举消费点经 normalize_enum_value（calls=${ncalls}）∧ 无 normalize_enum() 重复定义"
else
    fail "场景6.P2: 期望 normalize_enum_value 调用点≥1 且 normalize_enum() 定义==0，实际 calls=${ncalls} dupdefs=${ndef}"
fi

# ════════════════════════════════════════════════════════════════════════════
# 场景 8：接线与兼容（8.P1 / 8.P2）
# ════════════════════════════════════════════════════════════════════════════
wired8="$(grep -c 'load_state' "${STOP_HOOK}")"
art "stop-hook load_state refs=${wired8}" "stop-hook-load-state-wired.out"
if [[ ${wired8} -ge 1 ]]; then
    pass "场景8.P1: stop-hook.sh 含 load_state 接线（refs=${wired8}）"
else
    fail "场景8.P1: stop-hook.sh 未接线 load_state（refs=0）"
fi
if grep -qE '^(function[[:space:]]+)?get_field[[:space:]]*\(\)' "${LIB_SH}" \
   && grep -qE '^(function[[:space:]]+)?get_enum_field[[:space:]]*\(\)' "${LIB_SH}"; then
    pass "场景8.P2: lib.sh 保留 get_field() 与 get_enum_field() 定义（setup.sh 兼容引用）"
else
    fail "场景8.P2: lib.sh 缺少 get_field()/get_enum_field() 定义（兼容函数被误删）"
fi

# ════════════════════════════════════════════════════════════════════════════
# 场景 9：状态切换重载（9.P1 行为 / 9.P2 调用点 ≥6）
# ════════════════════════════════════════════════════════════════════════════
F9A="${TMP_BASE}/s9-a.md"
F9B="${TMP_BASE}/s9-b.md"
printf -- '---\nphase: alpha\ngate: review-accept\n---\n' > "${F9A}"
printf -- '---\nphase: beta\ngate: review-accept\n---\n' > "${F9B}"
export ST_A="${F9A}" ST_B="${F9B}"
res9="$(lib_run 'eval "$(load_state "$ST_A")" 2>/dev/null
old="$phase"
eval "$(load_state "$ST_B")" 2>/dev/null
echo "OLD=$old NEW=$phase"
')"
art "${res9}" "switch-point-reload.out"
if printf '%s' "${res9}" | grep -q '^OLD=alpha NEW=beta$'; then
    pass "场景9.P1: 状态文件切换后重新 load_state，字段反映新文件值（alpha→beta）"
else
    fail "场景9.P1: 切换重读失败，期望 OLD=alpha NEW=beta，实际[${res9}]"
fi

refs9="$(grep -c 'load_state' "${STOP_HOOK}")"
art "load_state call refs=${refs9}" "switch-points-wired.out"
if [[ ${refs9} -ge 6 ]]; then
    pass "场景9.P2: load_state 调用点 ≥6（1 开头批量 + C9 五点位），实际=${refs9}"
else
    fail "场景9.P2: load_state 调用点应 ≥6（3 切换点 + 2 同 run 读回链 + 1 开头），实际=${refs9}"
fi

# ════════════════════════════════════════════════════════════════════════════
# 场景 10：cleanup_artifacts_ttl 三性质（10.P1 / 10.P2 / 10.P3）
# ════════════════════════════════════════════════════════════════════════════
D10="${TMP_BASE}/artifacts-10"
mkdir -p "${D10}/sub_empty" "${D10}/sub_full"
echo x > "${D10}/old.txt";      touch -t 202001010000 "${D10}/old.txt"
echo y > "${D10}/fresh.txt"
echo old > "${D10}/sub_empty/old2.txt"; touch -t 202001010000 "${D10}/sub_empty/old2.txt"
echo z > "${D10}/sub_full/keep.txt"
export ST="${D10}"
lib_run 'cleanup_artifacts_ttl "$ST"' >/dev/null 2>&1
if [[ ! -e "${D10}/old.txt" ]]; then
    pass "场景10.P1: mtime>7 天文件被删除"
else
    fail "场景10.P1: 过期文件 old.txt 未删除"
fi
if [[ -e "${D10}/fresh.txt" ]]; then
    pass "场景10.P2: mtime≤7 天文件保留"
else
    fail "场景10.P2: 新鲜文件 fresh.txt 被误删"
fi
if [[ ! -e "${D10}/sub_empty" && -e "${D10}/sub_full/keep.txt" ]]; then
    pass "场景10.P3: 清后空目录移除 ∧ 非空目录保留"
else
    fail "场景10.P3: 期望 sub_empty 被移除且 sub_full/keep.txt 保留（sub_empty exists=$([[ -e ${D10}/sub_empty ]] && echo yes || echo no) sub_full exists=$([[ -e ${D10}/sub_full ]] && echo yes || echo no))，实际见 find 输出"
fi

# ════════════════════════════════════════════════════════════════════════════
# 场景 11：目录不存在 rc==0 静默（11.P1）
# ════════════════════════════════════════════════════════════════════════════
D11="${TMP_BASE}/no-such-artifacts-dir-xyz"
export ST="${D11}"
ERRF11="${TMP_BASE}/s11-stderr.txt"
lib_run 'cleanup_artifacts_ttl "$ST"' 2>"${ERRF11}" >/dev/null
rc11=$?
if [[ ${rc11} -eq 0 && ! -s "${ERRF11}" ]]; then
    pass "场景11.P1: 目录不存在 → rc==0 静默无 stderr"
else
    fail "场景11.P1: 期望 rc==0 且 stderr 空，实际 rc=${rc11} stderr=[$(cat "${ERRF11}")]"
fi

# ════════════════════════════════════════════════════════════════════════════
# 场景 12：幂等二跑（12.P1）
# ════════════════════════════════════════════════════════════════════════════
D12="${TMP_BASE}/artifacts-12"
mkdir -p "${D12}/sub"
echo a > "${D12}/old.txt";  touch -t 202001010000 "${D12}/old.txt"
echo b > "${D12}/fresh.txt"
echo c > "${D12}/sub/note.txt"
export ST="${D12}"
lib_run 'cleanup_artifacts_ttl "$ST"' >/dev/null 2>&1
snap1="$(find "${D12}" | sort)"
lib_run 'cleanup_artifacts_ttl "$ST"' >/dev/null 2>&1
snap2="$(find "${D12}" | sort)"
if [[ "${snap1}" == "${snap2}" ]]; then
    pass "场景12.P1: 连续执行两次，第二次目录树零变化（幂等）"
else
    fail "场景12.P1: 二跑目录树发生变化（非幂等）: diff=[$(diff <(echo "${snap1}") <(echo "${snap2}") | head -5)]"
fi

# ════════════════════════════════════════════════════════════════════════════
# 场景 13：目录外哨兵零触碰（13.P1）
# ════════════════════════════════════════════════════════════════════════════
OUT13="${TMP_BASE}/outside"
D13="${TMP_BASE}/artifacts-13"
mkdir -p "${OUT13}" "${D13}"
echo SENTINEL_CONTENT > "${OUT13}/old_outside.txt"
touch -t 202001010000 "${OUT13}/old_outside.txt"
echo old > "${D13}/old_inside.txt"; touch -t 202001010000 "${D13}/old_inside.txt"
export ST="${D13}"
lib_run 'cleanup_artifacts_ttl "$ST"' >/dev/null 2>&1
if [[ -e "${OUT13}/old_outside.txt" ]] && [[ "$(cat "${OUT13}/old_outside.txt" 2>/dev/null)" == "SENTINEL_CONTENT" ]]; then
    pass "场景13.P1: 目录外同 mtime 过期哨兵存在且内容未变（零触碰）"
else
    fail "场景13.P1: 目录外哨兵被删除/修改（越界清理）"
fi

# ════════════════════════════════════════════════════════════════════════════
# 场景 14：setup.sh SessionStart 接线含容错（14.P1）
# ════════════════════════════════════════════════════════════════════════════
hits14="$(grep -n 'cleanup_artifacts_ttl' "${SETUP_SH}" | grep -v '^[0-9]*:[[:space:]]*#' || true)"
art "${hits14}" "setup-cleanup-wired.out"
if [[ -z "${hits14}" ]]; then
    fail "场景14.P1: setup.sh 未接线 cleanup_artifacts_ttl"
else
    lnum14="$(printf '%s' "${hits14}" | head -1 | cut -d: -f1)"
    call14="$(sed -n "${lnum14}p" "${SETUP_SH}")"
    next14="$(sed -n "$((lnum14 + 1))p" "${SETUP_SH}")"
    ctx14="${call14}
${next14}"
    if printf '%s' "${ctx14}" | grep -Eq '2>/dev/null|>[[:space:]]*/dev/null|\|\|[[:space:]]*(true|:)|2>&1|if[[:space:]]|&&'; then
        pass "场景14.P1: setup.sh 调用 cleanup_artifacts_ttl 且上下文含容错（不阻断 SessionStart）"
    else
        fail "场景14.P1: 接线行/次行缺容错（2>/dev/null 或 || true 等），行${lnum14}=[${call14}] 次=[${next14}]"
    fi
fi

# ════════════════════════════════════════════════════════════════════════════
# 场景 15：detect_runtime_size 已知体积 KB 整数（15.P1）
# ════════════════════════════════════════════════════════════════════════════
D15="${TMP_BASE}/runtime-15"
mkdir -p "${D15}"
dd if=/dev/zero of="${D15}/blob.bin" bs=1048576 count=2 2>/dev/null
export ST="${D15}"
out15="$(lib_run 'detect_runtime_size "$ST"')"
rc15=$?
art "${out15}" "runtime-size-kb.out"
kb15="$(printf '%s' "${out15}" | head -1)"
if [[ ${rc15} -eq 0 ]] && printf '%s' "${kb15}" | grep -qE '^[0-9]+$'; then
    pass "场景15.P1-pre: 输出首行为 KB 整数（rc=0, kb=${kb15}）"
else
    fail "场景15.P1-pre: 期望首行 KB 整数 rc==0，实际 rc=${rc15} 输出=[${out15}]"
fi
if [[ "${kb15}" =~ ^[0-9]+$ ]] && [[ ${kb15} -ge 2048 ]]; then
    pass "场景15.P1: 输出 KB ≥ 已知体积 2048KB（实际=${kb15}）"
else
    fail "场景15.P1: KB 数应 ≥2048（2MB 文件），实际=${kb15}"
fi

# ════════════════════════════════════════════════════════════════════════════
# 场景 16：目录不存在 → 输出 0 rc==0 无警告（16.P1）
# ════════════════════════════════════════════════════════════════════════════
D16="${TMP_BASE}/no-such-runtime-xyz"
export ST="${D16}"
out16="$(lib_run 'detect_runtime_size "$ST"')"
rc16=$?
art "${out16}" "runtime-size-zero.out"
if [[ ${rc16} -eq 0 && "${out16}" == "0" ]]; then
    pass "场景16.P1: 目录缺失 → stdout==0 rc==0 无 RUNTIME-SIZE-WARN"
else
    fail "场景16.P1: 期望输出 '0' rc==0，实际 rc=${rc16} 输出=[${out16}]"
fi

# ════════════════════════════════════════════════════════════════════════════
# 场景 17：>500MB 附 RUNTIME-SIZE-WARN / 低于不附（17.P1 / 17.P2）
# 注：契约 C11 明确 du -sk 口径（计分配块），稀疏空洞对 du 不可见，
#     故用真实字节文件跨过 500MB（512000KB）阈值，取 502MiB=514048KB 留余量。
# ════════════════════════════════════════════════════════════════════════════
D17="${TMP_BASE}/runtime-17"
mkdir -p "${D17}"
dd if=/dev/zero of="${D17}/big.bin" bs=1048576 count=502 2>/dev/null
export ST="${D17}"
out17="$(lib_run 'detect_runtime_size "$ST"')"
art "${out17}" "runtime-size-warn.out"
kb17="$(printf '%s' "${out17}" | head -1)"
if printf '%s' "${kb17}" | grep -qE '^[0-9]+$'; then
    pass "场景17.P1-pre: 超阈值场景首行仍为 KB 整数（kb=${kb17}）"
else
    fail "场景17.P1-pre: 首行应为 KB 整数，实际=[${out17}]"
fi
if printf '%s' "${out17}" | grep -q 'RUNTIME-SIZE-WARN'; then
    pass "场景17.P1: 超 500MB 附 RUNTIME-SIZE-WARN 信号行"
else
    fail "场景17.P1: >500MB（实际约 ${kb17}KB）未附 RUNTIME-SIZE-WARN，输出=[${out17}]"
fi

D17B="${TMP_BASE}/runtime-17b"
mkdir -p "${D17B}"
dd if=/dev/zero of="${D17B}/small.bin" bs=1024 count=1 2>/dev/null
export ST="${D17B}"
out17b="$(lib_run 'detect_runtime_size "$ST"')"
art "${out17b}" "runtime-size-nowarn.out"
if printf '%s' "${out17b}" | grep -qE '^[0-9]+$' && ! printf '%s' "${out17b}" | grep -q 'RUNTIME-SIZE-WARN'; then
    pass "场景17.P2: 低于阈值仅输出 KB 数无警告"
else
    fail "场景17.P2: 低体积场景不应附 RUNTIME-SIZE-WARN 且首行应为整数，输出=[${out17b}]"
fi

# ════════════════════════════════════════════════════════════════════════════
# 场景 18：doctor 接线（18.P1 / 18.P2）— doctor 为 AI 驱动 skill，
# SKILL.md 的接线行/报告矩阵行是其机器可查 SSOT 锚点
# ════════════════════════════════════════════════════════════════════════════
vol18="$(grep -i 'runtime' "${DOCTOR_SKILL}" | grep '体积' | head -1 || true)"
art "${vol18}" "doctor-runtime-size-line.out"
if [[ -n "${vol18}" ]] && printf '%s' "${vol18}" | grep -Eq 'MB|KB' \
   && printf '%s' "${vol18}" | grep -Eq '[0-9]|X[[:space:]]*MB'; then
    pass "场景18.P1: doctor 报告矩阵含 runtime 体积行（含 MB/KB 单位与数字/占位）"
else
    fail "场景18.P1: doctor SKILL.md 缺 runtime 体积报告行（需含 体积 + MB/KB），锚点行=[${vol18}]"
fi
wire18="$(grep -n 'detect_runtime_size' "${DOCTOR_SKILL}" | head -1 || true)"
art "${wire18}" "doctor-wired-detect-runtime-size.out"
if [[ -n "${wire18}" ]] && ! printf '%s' "${wire18}" | grep -q 'rm '; then
    pass "场景18.P2: doctor SKILL.md 存在 detect_runtime_size 接线引用 ∧ 接线不硬编码清理命令"
else
    fail "场景18.P2: doctor SKILL.md 缺 detect_runtime_size 引用或接线行含清理命令，实际=[${wire18}]"
fi

# ════════════════════════════════════════════════════════════════════════════
# 场景 19：版本 v3.65.0 四处同步（19.P1 动态一致 / 19.P2 承载字段行无旧残留）
# 动态口径：以 plugin.json 为 SSOT，不硬编码版本号（防后续 bump 假红）
# ════════════════════════════════════════════════════════════════════════════
V_PLUGIN="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${PLUGIN_JSON}" | head -1)"
V_MKT="$(awk 'BEGIN{RS="}"} /"name"[[:space:]]*:[[:space:]]*"autopilot"/ { if (match($0, /"version"[[:space:]]*:[[:space:]]*"[0-9][0-9.]*"/)) { s=substr($0,RSTART,RLENGTH); gsub(/[^0-9.]/,"",s); print s; exit } }' "${MARKETPLACE}")"
ROW_CLAUDE="$(grep -F '[autopilot](plugins/autopilot/)' "${REPO_CLAUDE_MD}" | head -1)"
V_CLAUDE="$(printf '%s' "${ROW_CLAUDE}" | grep -oE '[|][[:space:]]*v[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*[|]' | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
README_BEAR_LINE="$(head -25 "${AUTOPILOT_README}" | grep -E 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
V_README="$(printf '%s' "${README_BEAR_LINE}" | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/^v//')"
art "plugin=${V_PLUGIN} mkt=${V_MKT} claude=${V_CLAUDE} readme=${V_README}" "version-quads-synced.out"

if printf '%s' "${V_PLUGIN}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    pass "场景19.P1-pre: plugin.json version 可解析（${V_PLUGIN}）"
else
    fail "场景19.P1-pre: plugin.json version 不可解析=[${V_PLUGIN}]"
fi
quad_ok=1
for pair in "marketplace:${V_MKT}" "claude-md:${V_CLAUDE}" "readme:${V_README}"; do
    src="${pair%%:*}"; val="${pair#*:}"
    if [[ "${val}" != "${V_PLUGIN}" ]]; then
        fail "场景19.P1: ${src} 版本（${val}）≠ plugin.json 动态值（${V_PLUGIN}）"
        quad_ok=0
    fi
done
if [[ ${quad_ok} -eq 1 ]]; then
    pass "场景19.P1: 四处版本相互一致且 == plugin.json 动态值（${V_PLUGIN}）"
fi

# 19.P2：承载字段行内任意版本 token 均须等于动态值（无旧版本残留）
stale=0
pj_line="$(grep -n '"version"' "${PLUGIN_JSON}" | head -1 | cut -d: -f2-)"
for tok in $(printf '%s' "${pj_line}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true); do
    [[ "${tok}" == "${V_PLUGIN}" ]] || { fail "场景19.P2: plugin.json 版本承载行残留旧版本 ${tok}"; stale=1; }
done
mkt_rec="$(awk 'BEGIN{RS="}"} /"name"[[:space:]]*:[[:space:]]*"autopilot"/{print; exit}' "${MARKETPLACE}")"
for tok in $(printf '%s' "${mkt_rec}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true); do
    [[ "${tok}" == "${V_PLUGIN}" ]] || { fail "场景19.P2: marketplace.json autopilot 条目残留旧版本 ${tok}"; stale=1; }
done
for tok in $(printf '%s' "${ROW_CLAUDE}" | grep -oE '[|][[:space:]]*v[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*[|]' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true); do
    [[ "${tok}" == "${V_PLUGIN}" ]] || { fail "场景19.P2: CLAUDE.md autopilot 索引行版本列残留旧版本 ${tok}"; stale=1; }
done
for tok in $(printf '%s' "${README_BEAR_LINE}" | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' || true); do
    tok="${tok#v}"
    [[ "${tok}" == "${V_PLUGIN}" ]] || { fail "场景19.P2: README.md 顶部版本标题行残留旧版本 ${tok}"; stale=1; }
done
if [[ ${stale} -eq 0 ]]; then
    pass "场景19.P2: 四处版本承载字段行零旧版本残留（行锚定闭集）"
fi

# ════════════════════════════════════════════════════════════════════════════
# 场景 20：性能实质 — stop-hook get_field/get_enum_field 直调清零（20.P1）
# ════════════════════════════════════════════════════════════════════════════
direct20="$(grep -v '^[[:space:]]*#' "${STOP_HOOK}" | grep -cE 'get_enum_field|get_field' || true)"
art "direct=${direct20} load_state_refs=${refs9}" "scan-count-reduced.out"
if [[ ${direct20} -eq 0 && ${refs9} -ge 6 ]]; then
    pass "场景20.P1: stop-hook get_field/get_enum_field 直调==0（${direct20}）∧ load_state 调用点=${refs9} ≥6"
else
    fail "场景20.P1: 期望直调==0 ∧ load_state≥6，实际直调=${direct20} load_state=${refs9}"
fi

# ════════════════════════════════════════════════════════════════════════════
# 场景 21：对抗平价 — load_state eval 回读 == get_field 逐字段（21.P1）
# 对抗点：多空格 / 值尾随空格引号 / mode vs plan_mode 锚定 / 重复键
# [2026-09-07] 用户批准适配（铁律例外情形①断言与契约矛盾）：正文伪 --- 块字段
# （FAKE_KEY）从平价比对剔除——get_field 既有 sed 范围对伪块重复开门泄漏正文伪字段
# （历史 quirk），load_state 按 C8「只认首对 ---」更严格语义胜出（正文文本注入正是
# eval 安全契约要防的）；该语义由场景 4.P1 独立锁定，平价只在首对 --- 内字段上要求。
# ════════════════════════════════════════════════════════════════════════════
F21="${TMP_BASE}/s21-state.md"
cat > "${F21}" <<'EOF'
---
phase: review-accept
gate:   has  double
mode: fast
plan_mode: not-mode
note: "trailing  "
dupkey: first
dupkey: second
sq: it's
---
---
FAKE_KEY: fake
mode: bodymode
EOF
export ST="${F21}"
res21="$(lib_run 'STATE_FILE="$ST"
eval "$(load_state "$ST")" 2>/dev/null
ok=1
for k in phase gate mode plan_mode note dupkey sq; do
    lv="${!k-}"
    gv="$(get_field "$k")"
    [[ "$lv" == "$gv" ]] || { echo "MISMATCH k=$k load=[${lv}] get=[${gv}]"; ok=0; }
done
[[ $ok -eq 1 ]] && echo PARITY_OK
')"
art "${res21}" "load-state-parity.out"
if printf '%s' "${res21}" | grep -q '^PARITY_OK$'; then
    pass "场景21.P1: 对抗 fixture（多空格/尾随空格引号/mode 锚定/伪 ---/重复键）上 load_state eval 回读 == get_field 逐字段平价"
else
    fail "场景21.P1: 平价失败，输出=[${res21}]"
fi
mode21="$(lib_run 'STATE_FILE="$ST"; eval "$(load_state "$ST")" 2>/dev/null; printf "%s" "$mode"')"
if [[ "${mode21}" == "fast" ]]; then
    pass "场景21.P1-附: mode 锚定不误匹配 plan_mode（mode=fast）"
else
    fail "场景21.P1-附: mode 锚定失败（期望 fast），实际=[${mode21}]"
fi

# ── 汇总 ─────────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
echo "R_P3-MECH 汇总: PASS=${PASS_COUNT} FAIL=${FAIL_COUNT}"
echo "─────────────────────────────────────────"
if [[ ${FAIL_COUNT} -gt 0 ]]; then
    exit 1
fi
exit 0
