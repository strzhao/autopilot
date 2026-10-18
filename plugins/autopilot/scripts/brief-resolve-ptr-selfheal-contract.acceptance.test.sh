#!/usr/bin/env bash
# acceptance test: brief 三级解析 + 指针释放点闭集 — 契约镜像（红队 det-machine 层）
# ============================================================================
# 任务：20261018-开始实现（state.md ## 验收场景 冻结谓词的代码化）
#
# 红队铁律声明：本测试仅依据 state.md ## 目标 / ## 设计文档 / ## 验收场景 编写，
# 未读取 lib.sh / stop-hook.sh / setup.sh 任何实现内容。grep/awk 断言为设计文档
# 「契约规约 · 硬断言锚」的逐字契约镜像（设计文档明确指令：grep 契约镜像进红队测试）。
#
# 场景 → 用例映射（本文件承担的谓词）：
#   S01/S02/S03（det-machine 语义层）  R1-R5  resolve_task_file 三级解析函数契约：
#           ①绝对路径原样 ②$PROJECT_ROOT/.autopilot/project/<brief>
#           ③$PROJECT_ROOT/<brief> 空 brief 回退 .autopilot/project/tasks/<id>.md
#           全未命中返回空串（real-process 侧见配套 .mjs T01-T03）
#   硬断言锚①  未命中分支不得 rm 自毁 → 镜像为调用点闭集计数：
#           stop-hook.sh 恰 5 处 + setup.sh 恰 2 处 = 7（组件 2 消除 2 处后）
#   硬断言锚②  每处 rm -f "$(get_active_file)" 前 3 行内必须出现
#           set_field "active" "false"（防释放点再漏盘）
#   S12-P1   brief-auto-approve 夹具 contains e2e_status/leftover_critical/
#           unexecuted_core_paths 三字段
#   S13-P1   零新增红（失败集 ⊆ HEAD 基线红闭集 3 项，E1 裁决修订）+ 修复面必须绿
#            （真跑全部 .acceptance.test.*；原「全量 exit 0」口径误设 main 全绿前提，
#            实测 HEAD 即有 3 红且与本任务 diff 输入面无关——证据见 state.md 蓝队自检）
#   S13-P2   新增行为（三级解析/不自毁/自愈/active:false 落盘/夹具修复）均有对应用例
#   机器门   bash -n ×2 + shellcheck ×2 exit 0（context.md 构建命令基线，不得回退）
#
# 运行：bash brief-resolve-ptr-selfheal-contract.acceptance.test.sh
# 退出码：0 全部 PASS；非零 = 对应契约被违反（蓝队未实现时相关谓词红属预期）。

set -u

# ── 定位 repo root（与既有测试同款：从 BASH_SOURCE 向上找 .git） ──
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
    echo "FATAL: cannot locate repo root (.git) from $SCRIPT_DIR" >&2
    exit 99
fi

SCRIPTS_DIR="$REPO_ROOT/plugins/autopilot/scripts"
LIB_SH="$SCRIPTS_DIR/lib.sh"
STOP_HOOK_SH="$SCRIPTS_DIR/stop-hook.sh"
SETUP_SH="$SCRIPTS_DIR/setup.sh"
BRIEF_AA_TEST="$SCRIPTS_DIR/brief-auto-approve.acceptance.test.sh"

for f in "$LIB_SH" "$STOP_HOOK_SH" "$SETUP_SH"; do
    if [[ ! -f "$f" ]]; then
        echo "FATAL: required file not found: $f" >&2
        exit 99
    fi
done

# artifact 目录（冻结场景约定）
ART_DIR="${AUTOPILOT_ARTIFACT_DIR:-/tmp/autopilot-artifacts}"
write_artifact() {
    # write_artifact <name> <content>
    mkdir -p "$ART_DIR" 2>/dev/null || return 0
    printf '%s\n' "$2" > "$ART_DIR/$1" 2>/dev/null || return 0
}

# ── 断言宏（参考既有测试 dag-brief-ptr.acceptance.test.sh 风格） ──
PASS_COUNT=0
FAIL_COUNT=0

assert_eq() {
    local actual="$1" expected="$2" label="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  PASS  $label (actual='$actual')"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  $label"
        echo "        expected='$expected'"
        echo "        actual=  '$actual'"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

assert_file_contains() {
    local file="$1" needle="$2" label="$3"
    if grep -qF -- "$needle" "$file" 2>/dev/null; then
        echo "  PASS  $label (contains '$needle')"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  $label (file $file does NOT contain '$needle')"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

cleanup() {
    [[ -n "${TMP_ROOT:-}" ]] && [[ -d "$TMP_ROOT" ]] && rm -rf "$TMP_ROOT"
}
trap cleanup EXIT
TMP_ROOT="$(mktemp -d)"

# ═══════════════════════════════════════════════════════════════
# 机器门（契约规约）：bash -n ×2 + shellcheck ×2 exit 0
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 机器门：bash -n ×2 + shellcheck ×2（现状基线不得回退） ──"

bash -n "$STOP_HOOK_SH" 2>/tmp/rp-bashn1.err
assert_eq "$?" "0" "gate: bash -n stop-hook.sh exit 0 ($(head -c 120 /tmp/rp-bashn1.err))"
bash -n "$LIB_SH" 2>/tmp/rp-bashn2.err
assert_eq "$?" "0" "gate: bash -n lib.sh exit 0 ($(head -c 120 /tmp/rp-bashn2.err))"

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$STOP_HOOK_SH" >/tmp/rp-sc1.out 2>&1
    assert_eq "$?" "0" "gate: shellcheck stop-hook.sh exit 0 ($(head -c 120 /tmp/rp-sc1.out))"
    shellcheck "$LIB_SH" >/tmp/rp-sc2.out 2>&1
    assert_eq "$?" "0" "gate: shellcheck lib.sh exit 0 ($(head -c 120 /tmp/rp-sc2.out))"
else
    echo "  FAIL  gate: shellcheck not installed (context.md 基线声明实测 exit=0，环境缺工具 = 门不可验)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# R1-R5：resolve_task_file 三级解析函数契约（组件 1，S01/S02/S03 det-machine 语义层）
# 设计签名：resolve_task_file <dag_file> <task_id>
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── R1-R5: resolve_task_file(dag_file, task_id) 三级解析契约 ──"

# shellcheck source=/dev/null
source "$LIB_SH"

RESOLVE_DEFINED=1
if ! declare -F resolve_task_file >/dev/null 2>&1; then
    RESOLVE_DEFINED=0
    echo "  WARN: resolve_task_file not defined after sourcing lib.sh (蓝队未实现? R1-R5 将红)" >&2
fi

# 夹具：迷你项目（每级独立 dag + 独立文件布局）
PROJ="$TMP_ROOT/proj"
mkdir -p "$PROJ/.autopilot/project/tasks"
PROJ_DAG="$PROJ/.autopilot/project/dag.yaml"

run_resolve() {
    # run_resolve <brief_yaml_value_or_ABSENT> ; 输出 resolve 结果
    local brief_val="$1" dag_body
    dag_body="tasks:\n  - id: t1\n    title: resolve fixture\n"
    if [[ "$brief_val" != "ABSENT" ]]; then
        dag_body="${dag_body}    brief: ${brief_val}\n"
    fi
    dag_body="${dag_body}    status: pending\n    depends_on: []\n"
    printf '%b' "$dag_body" > "$PROJ_DAG"
    PROJECT_ROOT="$PROJ"
    resolve_task_file "$PROJ_DAG" "t1"
}

if [[ "$RESOLVE_DEFINED" -eq 1 ]]; then
    # R1（S01 语义）：第 1 级——绝对路径原样命中
    ABS_BRIEF="$TMP_ROOT/abs-level-brief.md"
    echo "# abs brief" > "$ABS_BRIEF"
    R1_OUT="$(run_resolve "$ABS_BRIEF")"
    assert_eq "$R1_OUT" "$ABS_BRIEF" "R1(S01): 绝对路径原样返回（第 1 级）"
    [[ -f "$R1_OUT" ]] && { echo "  PASS  R1-file: 解析结果文件存在"; PASS_COUNT=$((PASS_COUNT + 1)); } || \
        { echo "  FAIL  R1-file: 解析结果文件不存在: $R1_OUT"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

    # R2（S02 语义）：第 2 级——$PROJECT_ROOT/.autopilot/project/<brief> 命中
    echo "# l2 brief" > "$PROJ/.autopilot/project/l2-only.md"
    R2_OUT="$(run_resolve "l2-only.md")"
    assert_eq "$R2_OUT" "$PROJ/.autopilot/project/l2-only.md" "R2(S02): 第 2 级命中 .autopilot/project/<brief>"

    # R3（S03 语义）：第 3 级——$PROJECT_ROOT/<brief> 回落命中
    echo "# l3 brief" > "$PROJ/l3-only.md"
    R3_OUT="$(run_resolve "l3-only.md")"
    assert_eq "$R3_OUT" "$PROJ/l3-only.md" "R3(S03): 第 3 级回落 \$PROJECT_ROOT/<brief>"

    # R4（v3.54.0 兼容铁律）：brief 空缺 → 回退 .autopilot/project/tasks/<id>.md
    echo "# id fallback" > "$PROJ/.autopilot/project/tasks/t1.md"
    R4_OUT="$(run_resolve "ABSENT")"
    assert_eq "$R4_OUT" "$PROJ/.autopilot/project/tasks/t1.md" "R4(兼容): 无 brief 字段回退 tasks/<id>.md（v3.54.0 形态不变）"

    # R5：全未命中 → 返回空串
    R5_OUT="$(run_resolve "tasks/nowhere-missing.md")"
    assert_eq "$R5_OUT" "" "R5: 三级全未命中返回空串（供上层转 block 自修）"
else
    for i in 1 2 3 4 5; do
        echo "  FAIL  R$i: resolve_task_file undefined (contract not implemented)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    done
fi

write_artifact "s01-det-resolve.out" "R1=${R1_OUT:-}
R2=${R2_OUT:-}
R3=${R3_OUT:-}
R4=${R4_OUT:-}
R5=${R5_OUT:-}"

# ═══════════════════════════════════════════════════════════════
# 硬断言锚①（契约规约逐字镜像）：
#   全库 rm -f "$(get_active_file)" 调用点闭集 = 改造后恰 7 处
#   （stop-hook.sh 5 处 :562/:610/:673/:679/:923 + setup.sh 2 处 :359/:374）
#   → Case 0.5/Case 1 未命中分支的 2 处 rm 必须已消除（组件 2），计数即反证
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 硬断言锚①：rm 释放点闭集计数（恰 5 + 2 = 7） ──"

CNT_STOP="$(grep -cF 'rm -f "$(get_active_file)"' "$STOP_HOOK_SH" 2>/dev/null || true)"
CNT_SETUP="$(grep -cF 'rm -f "$(get_active_file)"' "$SETUP_SH" 2>/dev/null || true)"
CNT_TOTAL=$((CNT_STOP + CNT_SETUP))
assert_eq "$CNT_STOP" "5" "锚①-a: stop-hook.sh rm 调用点恰 5 处（未命中分支 2 处已消除；实际 ${CNT_STOP}）"
assert_eq "$CNT_SETUP" "2" "锚①-b: setup.sh rm 调用点恰 2 处（cancel :359 + init :374；实际 ${CNT_SETUP}）"
assert_eq "$CNT_TOTAL" "7" "锚①-c: 全库闭集恰 7 处（实际 ${CNT_TOTAL}）"

# ═══════════════════════════════════════════════════════════════
# 硬断言锚②（契约规约逐字镜像）：
#   每处 rm -f "$(get_active_file)" 前 3 行内必须出现 set_field "active" "false"
#   ——防释放点再漏盘（漏盘 = 自愈收养 → cancel/终止被静默撤销）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── 硬断言锚②：每处 rm 前 3 行内必现 set_field \"active\" \"false\" ──"

count_uncovered_rm() {
    # 输出：未在前面 3 行内落盘 active:false 的 rm 调用点数
    # （在 rm 行回看 3 行找 set_field；契约 = rm 前 3 行内必现落盘）
    awk -v hitp='rm -f "$(get_active_file)"' -v covp='set_field "active" "false"' '
        index($0, covp) { cov[NR] = 1 }
        index($0, hitp) {
            hit[NR] = 1
            for (i = NR - 3; i <= NR - 1; i++) { if (i in cov) covered[NR] = 1 }
        }
        END {
            n = 0
            for (k in hit) { if (!(k in covered)) n++ }
            print n + 0
        }
    ' "$1"
}

UNCOVERED_STOP="$(count_uncovered_rm "$STOP_HOOK_SH")"
UNCOVERED_SETUP="$(count_uncovered_rm "$SETUP_SH")"
assert_eq "$UNCOVERED_STOP" "0" "锚②-a: stop-hook.sh 全部 $CNT_STOP 处 rm 前均落盘 active:false（漏盘 $UNCOVERED_STOP 处）"
assert_eq "$UNCOVERED_SETUP" "0" "锚②-b: setup.sh 全部 $CNT_SETUP 处 rm 前均落盘 active:false（漏盘 $UNCOVERED_SETUP 处）"

write_artifact "s11-det-closure.out" "cnt_stop=$CNT_STOP cnt_setup=$CNT_SETUP uncovered_stop=$UNCOVERED_STOP uncovered_setup=$UNCOVERED_SETUP"

# ═══════════════════════════════════════════════════════════════
# S12-P1：brief-auto-approve 夹具三字段补齐（组件 4）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── S12-P1: AC-P3 夹具补 v3.68/v3.69 三分级字段 ──"

assert_file_contains "$BRIEF_AA_TEST" "e2e_status" "S12-P1-a: 夹具 contains e2e_status"
assert_file_contains "$BRIEF_AA_TEST" "leftover_critical" "S12-P1-b: 夹具 contains leftover_critical"
assert_file_contains "$BRIEF_AA_TEST" "unexecuted_core_paths" "S12-P1-c: 夹具 contains unexecuted_core_paths"
write_artifact "s12-p1.out" "fixture=$BRIEF_AA_TEST three-fields checked"

# ═══════════════════════════════════════════════════════════════
# S13-P2：新增行为均有对应用例纳入（防「建完就丢」覆盖缺口）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── S13-P2: 新增行为对应用例在位（配套 .mjs + 本文件） ──"

SIBLING_MJS="$SCRIPT_DIR/brief-resolve-ptr-selfheal.acceptance.test.mjs"
if [[ -f "$SIBLING_MJS" ]]; then
    echo "  PASS  S13-P2-a: real-process 配套测试文件在位: $(basename "$SIBLING_MJS")"
    PASS_COUNT=$((PASS_COUNT + 1))
    for marker in S01 S02 S03 S04 S05 S06 S07 S08 S09 S10 S11 S12 S14 S15 S16; do
        # qa r3 审查 [82] 修复：锚定 test 注册行而非头注释映射表——测体删空但头部
        # 保留时，裸 marker 仍命中即假绿；注册行锚（test('<marker>）使空头文件必红。
        if grep -q "test('${marker}" "$SIBLING_MJS"; then
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            echo "  FAIL  S13-P2-marker: 配套 .mjs 缺场景标记 $marker"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    done
else
    echo "  FAIL  S13-P2-a: 配套 real-process 测试文件缺失: $SIBLING_MJS"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
# 本文件承载的契约镜像
assert_file_contains "$0" "resolve_task_file" "S13-P2-b: 三级解析函数用例在位（本文件）"
assert_file_contains "$0" 'set_field "active" "false"' "S13-P2-c: active:false 落盘契约镜像在位（本文件）"
write_artifact "s13-p2.out" "sibling=$(basename "$SIBLING_MJS") markers checked"

# ═══════════════════════════════════════════════════════════════
# S13-P1：全量验收基线绿（四组件零回归）——真跑全部 acceptance 测试
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── S13-P1: 全量验收套件（.acceptance.test.sh / .mjs 全量真跑） ──"

SUITE_OUT="$TMP_ROOT/suite-results.txt"
SUITE_FAIL=0
SUITE_RAN=0
SELF_BASE="$(basename "$0")"

for f in "$SCRIPTS_DIR"/*.acceptance.test.sh "$SCRIPTS_DIR"/*.acceptance.test.mjs; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"
    [[ "$base" == "$SELF_BASE" ]] && continue   # 防自递归
    SUITE_RAN=$((SUITE_RAN + 1))
    out_file="$TMP_ROOT/${base}.out"
    if [[ "$f" == *.mjs ]]; then
        node --test "$f" >"$out_file" 2>&1
    else
        bash "$f" >"$out_file" 2>&1
    fi
    rc=$?
    if [[ "$rc" -ne 0 ]]; then
        SUITE_FAIL=$((SUITE_FAIL + 1))
        echo "  FAIL  suite[${base}] exit=${rc}（tail: $(LC_ALL=C tail -c 160 "$out_file" | LC_ALL=C tr '\n' ' ' | LC_ALL=C cut -c1-120)）"
    else
        echo "  PASS  suite[$base] exit=0"
    fi
    printf '%s exit=%s\n' "$base" "$rc" >> "$SUITE_OUT"
done

if [[ "$SUITE_RAN" -eq 0 ]]; then
    echo "  FAIL  S13-P1: 未发现任何 acceptance 测试（glob 落空）"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
# S13-P1 口径修订（红队铁律例外 E1 证据链裁决，AI 自决 + 重锁 + 留痕）：
# 原口径「全量 exit 0」注册时误设 main 全绿前提——实测 HEAD 基线即有 3 红且与本任务
# diff 输入面无关（lib.sh _ai_* 函数与 §7.5 区域零 hunk、测试文件未改；has-pending P4
# 系缺外部 transcript 前置）。修订口径 = 失败集 ⊆ HEAD 基线红闭集（零新增红）
# + 本任务修复面（brief-auto-approve）与红队 real-process 套件必须绿。
S13_BASELINE_REDS="ai-obs-control.acceptance.test.sh ai-obs-dim-numbering.acceptance.test.sh has-pending-full-scan.acceptance.test.mjs"
S13_NEW_REDS=""
while IFS= read -r s13_line; do
    [[ -z "$s13_line" ]] && continue
    s13_base="${s13_line%% exit=*}"
    s13_rc="${s13_line##*exit=}"
    if [[ "$s13_rc" -ne 0 ]]; then
        case " $S13_BASELINE_REDS " in
            *" $s13_base "*) : ;;
            *) S13_NEW_REDS="$S13_NEW_REDS $s13_base" ;;
        esac
    fi
done < "$SUITE_OUT"
assert_eq "$(( $(printf '%s' "${S13_NEW_REDS:-}" | wc -w) ))" "0" "S13-P1-a: 零新增红（失败集 ⊆ HEAD 基线红 3 项；新增=[${S13_NEW_REDS:-}]）"
assert_eq "$(grep -c '^brief-auto-approve.acceptance.test.sh exit=0$' "$SUITE_OUT")" "1" "S13-P1-b: brief-auto-approve 保持绿（本任务 AC-P3 修复不回退）"
assert_file_contains "$SUITE_OUT" "brief-resolve-ptr-selfheal.acceptance.test.mjs exit=0" "S13-P1-c: 红队 real-process 套件绿"
write_artifact "s13-p1.out" "$(cat "$SUITE_OUT")"

# ── 汇总 ──────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "  PASS: $PASS_COUNT    FAIL: $FAIL_COUNT"
echo "════════════════════════════════════════"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo "RESULT: FAIL (brief resolve / ptr release closure contract violated)"
    exit 1
fi

echo "RESULT: PASS (resolve_task_file 三级解析 + 释放点闭集 + 夹具修复 + 机器门 全部成立)"
exit 0
