#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# headless-mode 验收测试（红队）——仅基于设计文档 / 契约规约 C1-C8 / 冻结验收谓词编写。
# 铁律：绝不读取蓝队本次工作区未提交的实现改动（setup.sh / stop-hook.sh / SKILL.md /
#       references/headless-protocol.md 的工作区版本一律不读；脚本机制事实仅取 git HEAD 基线）。
#
# SSOT：state.md `## 验收场景`（场景生成器冻结 2026-09-10，9 组 32 条谓词逐条覆盖，
#       其中场景 9 为第 2 轮修订新增；每条谓词 ≥1 硬断言，断言字面量取自谓词 assert: 字段）。
#
# 谓词 → 测试函数映射：
#   场景1.P1 → test_s1_p1_headless_init            （C1：exit 0 + 字段级锚 ^headless: true）
#   场景1.P2 → test_s1_p2_full_loop_terminal       （120s 内 exit 0 且 phase 到终态 done）
#   场景1.P3 → test_s1_p3_no_hang_markers          （negate：AskUserQuestion/pending-user 0 匹配）
#   场景1.P4 → test_s1_p4_hook_json_protocol       （stop-hook 合成 payload → jq 合法 JSON object）
#   场景2.P1 → test_s2_p1_design_approval_deterministic
#   场景2.P2 → test_s2_p2_guardrail_deterministic
#   场景2.P3 → test_s2_p3_trace_freshness          （mtime < 60s + 内嵌时间戳字段）
#   场景2.P4 → test_s2_p4_complexity_split_no_ask  （negate：AskUserQuestion == 0 + 留痕含 单任务）
#   场景2.P5 → test_s2_p5_stage_failure_no_ask     （SKILL.md:53 回退点 negate + [headless] 留痕）
#   场景3.P1 → test_s3_p1_prose_flag_no_effect     （C2：字面量档位 == 对照基线）
#   场景3.P2 → test_s3_p2_goal_text_verbatim       （文本逐字保留 + 长度相等）
#   场景3.P3 → test_s3_p3_explicit_flag_and_prose  （显式 --fast 生效且文本保留）
#   场景3.P4 → test_s3_p4_word_split_tokens        （多 argv token 分词形态，活标本复现）
#   场景9.P1 → test_s9_p1_redteam_no_hang          （60s 内 exit 0 且 != 124）
#   场景9.P2 → test_s9_p2_conservative_trace       （[headless] + U[1-4] + 保守处置）
#   场景9.P3 → test_s9_p3_qa_report_leftover       （遗留区含具体 U 编号条目，样板词不算）
#   场景4.P1 → test_s4_p1_brainstorm_no_hang
#   场景4.P2 → test_s4_p2_brainstorm_trace
#   场景5.P1 → test_s5_p1_qa_gate_no_hold
#   场景5.P2 → test_s5_p2_gate_disposition_trace
#   场景5.P3 → test_s5_p3_state_no_wait            （negate：等待应答标记 0 匹配）
#   场景5.P4 → test_s5_p4_gate_kept_no_merge       （C7：gate 保留 + 不进 merge）
#   场景6.P1 → test_s6_p1_leak_warning             （C6：告警含 CLAUDE_CODE_SESSION_ID）
#   场景6.P2 → test_s6_p2_leak_trace
#   场景6.P3 → test_s6_p3_no_silent_release        （negate：无告警伴随的静默放行 == 0）
#   场景6.P4 → test_s6_p4_control_no_warning       （对照防误报：signature 不存在 → 0 告警）
#   场景7.P1 → test_s7_p1_no_headless_marker       （C5/C8 反向：非 headless 模板零发射）
#   场景7.P2 → test_s7_p2_interactive_ask_preserved（C5：提问指令保留，匹配数 >= 1）
#   场景7.P3 → test_s7_p3_interactive_no_headless_trace（negate：headless 留痕标记 0）
#   场景8.P1 → test_s8_p1_headless_fast_combo      （--headless --fast 两档同效）
#   场景8.P2 → test_s8_p2_headless_idempotent      （--headless 重复幂等，C8）
#   场景8.P3 → test_s8_p3_unknown_flag_to_text     （未定义 flag 逐字归入目标文本）
#   C3(指针) → test_C3_skill_pointers                 （6 处 AskUserQuestion 点位 headless 指针）
#   C8(文件) → test_C8_headless_protocol_ssot / test_C8_state_guide_field / test_C8_writer_and_net0
#
# 驱动隔离契约（场景生成器冻结条款）：凡真实执行 setup.sh / stop-hook 的 driver 与本套件
# 一律在 mktemp -d 沙盒内运行（PROJECT_ROOT 解析为沙盒目录），绝不触碰仓库真实
# .autopilot/runtime/active.ptr。套件自身不快照/恢复 active.ptr——因为根本不在仓库内执行。
#
# 契约模糊点（CONTRACT_AMBIGUOUS）逐处标注，见各断言旁注释。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# REPO_ROOT 稳健探测（兼容暂存区 acceptance-staging/ 与合流后 tests/acceptance/ 两种部署位置）
_find_repo_root() {
    local d="$SCRIPT_DIR"
    while [[ -n "$d" && "$d" != "/" ]]; do
        if [[ -f "$d/.claude-plugin/marketplace.json" ]]; then
            echo "$d"; return 0
        fi
        d=$(dirname "$d")
    done
    return 1
}
REPO_ROOT="$(_find_repo_root)" || {
    echo "[FAIL] headless-mode: 无法定位 REPO_ROOT（缺 .claude-plugin/marketplace.json）" >&2
    exit 1
}

SETUP_SH="$REPO_ROOT/plugins/autopilot/scripts/setup.sh"
STOP_HOOK="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"
SKILL_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/SKILL.md"
REFERENCES_DIR="$REPO_ROOT/plugins/autopilot/skills/autopilot/references"
PROTOCOL_MD="$REFERENCES_DIR/headless-protocol.md"
STATE_GUIDE="$REFERENCES_DIR/state-file-guide.md"
ART_DIR="/tmp/autopilot-artifacts"

fail() { echo "[FAIL] headless-mode: $1" >&2; exit 1; }
pass() { echo "[PASS] headless-mode: $1"; }

[[ -f "$SETUP_SH" ]]   || fail "setup.sh 不存在: $SETUP_SH"
[[ -f "$STOP_HOOK" ]]  || fail "stop-hook.sh 不存在: $STOP_HOOK"
[[ -f "$SKILL_FILE" ]] || fail "SKILL.md 不存在: $SKILL_FILE"
command -v jq >/dev/null 2>&1 || fail "jq 不可用（本套件 1.P4/6.P1 需要 jq 解析 hook JSON）"
mkdir -p "$ART_DIR" || fail "无法创建产物目录 $ART_DIR"

# 泄漏模拟用宿主 session 形态：uuid 形态（非 sess_ 前缀），与设计文档记录的
# 宿主 CLAUDE_CODE_SESSION_ID 泄漏形态一致（stop-hook Guard 2 signature 前提）
HOST_LEAK_SESSION_ID="a07d6b51-ecc8-4c7f-9f3a-3f62526527ca"

SANDBOXES=()
new_sandbox() {
    local d
    d="$(mktemp -d -t autopilot-hl-XXXXXX)" || fail "mktemp 失败"
    SANDBOXES+=("$d")
    printf '%s' "$d"
}
trap '[[ ${#SANDBOXES[@]} -gt 0 ]] && rm -rf "${SANDBOXES[@]}" 2>/dev/null' EXIT

# ── 可移植 timeout 包装（macOS 无 GNU timeout 时用 bash 看门狗，语义一致：挂起 → 124） ──
run_with_timeout() { # <secs> <outfile> <cmd...>
    local secs="$1" outfile="$2"; shift 2
    local rc
    if command -v timeout >/dev/null 2>&1; then
        timeout "$secs" "$@" >"$outfile" 2>&1
        rc=$?
    else
        "$@" >"$outfile" 2>&1 &
        local pid=$! wpid=$?
        ( sleep "$secs"; kill -9 "$pid" 2>/dev/null ) &
        wpid=$!
        wait "$pid"; rc=$?
        kill -9 "$wpid" 2>/dev/null
        wait "$wpid" 2>/dev/null
        if [[ "$rc" -gt 128 ]]; then rc=124; fi
    fi
    return "$rc"
}

# ── setup.sh 调用（沙盒内真实执行）；leak 模式注入宿主泄漏 env ──
# 输出回显；RUN_RC 全局返回 exit code
RUN_RC=0
run_setup() {
    local sbx="$1" mode="$2"; shift 2
    local out
    if [[ "$mode" == "leak" ]]; then
        out="$(cd "$sbx" && export CLAUDE_CODE_SESSION_ID="$HOST_LEAK_SESSION_ID" && bash "$SETUP_SH" "$@" 2>&1)"
    else
        out="$(cd "$sbx" && unset CLAUDE_CODE_SESSION_ID && bash "$SETUP_SH" "$@" 2>&1)"
    fi
    RUN_RC=$?
    printf '%s' "$out"
}

# ── stop-hook 调用（沙盒内真实执行，stdout/stderr 分离捕获） ──
OUT_STDOUT=""; OUT_STDERR=""; HOOK_RC=0
run_hook() { # <sbx> <hook_session> <clean|leak>
    local sbx="$1" sess="$2" mode="$3"
    local tmpo tmpe payload
    tmpo="$(mktemp -t hlout.XXXXXX)"; tmpe="$(mktemp -t hlerr.XXXXXX)"
    payload="$(printf '{"session_id":"%s","transcript_path":"/tmp/none"}' "$sess")"
    # 有意在子 shell 内隔离泄漏 env，供泄漏 signature 复现（rationale）
    # shellcheck disable=SC2030,SC2031
    if [[ "$mode" == "leak" ]]; then
        ( cd "$sbx" && export CLAUDE_CODE_SESSION_ID="$HOST_LEAK_SESSION_ID" \
          && printf '%s' "$payload" | bash "$STOP_HOOK" ) >"$tmpo" 2>"$tmpe"
    else
        ( cd "$sbx" && unset CLAUDE_CODE_SESSION_ID \
          && printf '%s' "$payload" | bash "$STOP_HOOK" ) >"$tmpo" 2>"$tmpe"
    fi
    # 函数内赋值、测试函数内读取的全局状态（rationale：跨函数传递设计）
    # shellcheck disable=SC2034
    HOOK_RC=$?
    OUT_STDOUT="$(cat "$tmpo")"
    OUT_STDERR="$(cat "$tmpe")"
    rm -f "$tmpo" "$tmpe"
}

# ── state 定位与字段读取 ──
state_path() { # <sbx> → state.md 绝对路径（经 active.ptr，失败时 find 兜底）
    local sbx="$1" slug f
    slug="$(cat "$sbx/.autopilot/runtime/active.ptr" 2>/dev/null | head -1 | tr -d '[:space:]')"
    if [[ -n "$slug" && -f "$sbx/.autopilot/runtime/requirements/$slug/state.md" ]]; then
        printf '%s' "$sbx/.autopilot/runtime/requirements/$slug/state.md"
        return 0
    fi
    f="$(find "$sbx/.autopilot/runtime/requirements" -name 'state.md' 2>/dev/null | head -1)"
    [[ -n "$f" ]] && { printf '%s' "$f"; return 0; }
    return 1
}

field_value() { # <state> <field> → 去引号原值
    grep -E "^${2}:" "$1" 2>/dev/null | head -1 | sed -E "s/^${2}:[[:space:]]*\"?([^\"]*)\"?$/\1/"
}

goal_text() { # <state> → `## 目标` 段首个非空行（即 $GOAL 逐字落盘行）
    awk '/^## 目标/{f=1;next} f&&NF{print;exit}' "$1"
}

# frontmatter 内 upsert 字段（键已存在→原位替换；不存在→闭合 --- 前插入；POSIX awk 可移植）
state_set_fm() { # <state> <key> <raw_value>
    local f="$1" key="$2" val="$3"
    awk -v key="$key" -v val="$val" '
        n == 0 && /^---[[:space:]]*$/ { n = 1; print; next }
        n == 1 {
            if ($0 ~ "^" key ":") { print key ": " val; done = 1; next }
            if ($0 ~ "^---[[:space:]]*$") {
                if (!done) print key ": " val
                print; n = 2; next
            }
            print; next
        }
        { print }
    ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

now_epoch() { date +%s; }
file_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }

# 挂起/等待应答标记（冻结谓词原文：AskUserQuestion / pending-user / 等待态）
wait_marker_count() { # <file> → 匹配行数
    grep -c -E 'AskUserQuestion|pending-user|等待用户应答|等待用户' "$1" 2>/dev/null || true
}

skill_win_has() { # <line> <ERE> → SKILL.md 该行 ±3 窗口内是否命中（净 0 行单行内替换 → 行号稳定）
    local line="$1" pat="$2" from to
    from=$((line - 3)); [[ $from -lt 1 ]] && from=1
    to=$((line + 3))
    sed -n "${from},${to}p" "$SKILL_FILE" | grep -qiE "$pat"
}

# ═══════════════════════════════════════════════════════════════════════════
# 场景 1：headless 档位开启下全流程确定性闭环
# ═══════════════════════════════════════════════════════════════════════════

test_s1_p1_headless_init() {
    # 场景1.P1 [real-process] C1：setup.sh --headless → exit 0 且 frontmatter 字段级行锚
    # `headless: true` 计数 >= 1（field 级锚——goal 文本含 headless 字样不得满足）
    local sbx state count
    sbx="$(new_sandbox)"
    local out
    out="$(run_setup "$sbx" clean --headless "为工程补齐 README 的安装一节")"
    [[ "$RUN_RC" -eq 0 ]] || fail "场景1.P1: setup.sh --headless exit=${RUN_RC}（契约 C1 要求 exit 0）。输出: $out"
    state="$(state_path "$sbx")" || fail "场景1.P1: 沙盒内未找到 state.md"
    count="$(grep -c -E '^headless: true' "$state" 2>/dev/null || true)"
    [[ "$count" -ge 1 ]] || fail "场景1.P1: state frontmatter 未发射字段行 headless: true（字段级锚 ^headless: true 计数=${count}，>=1 要求）。state: $(cat "$state")"
    {
        echo "SETUP_RC=$RUN_RC"
        echo "HEADLESS_LINE_COUNT=$count"
        echo "--- state.frontmatter ---"
        sed -n '/^---$/,/^---$/p' "$state"
    } > "$ART_DIR/场景1.P1.out"
    pass "场景1.P1: setup.sh --headless → exit 0 + 字段级锚 headless: true 发射（计数=${count}）"
}

test_s1_p2_full_loop_terminal() {
    # 场景1.P2 [real-process]：闭环冒烟驱动器 120s 超时内 exit 0（124=挂起）且 state 到终态
    local rc outfile
    outfile="$(mktemp -t hlloop.XXXXXX)"
    run_with_timeout 120 "$outfile" bash "$SCRIPT_DIR/headless-full-loop.driver.sh"
    rc=$?
    [[ "$rc" -eq 0 ]] || fail "场景1.P2: headless-full-loop.driver.sh exit=${rc}（要求 0，124=挂起）。driver 输出: $(tail -20 "$outfile" 2>/dev/null)"
    [[ -f "$ART_DIR/场景1.P2.out" ]] || fail "场景1.P2: 驱动器未产出 /tmp/autopilot-artifacts/场景1.P2.out"
    grep -q '^DRIVER-WALK-COMPLETE$' "$ART_DIR/场景1.P2.out" || fail "场景1.P2: 驱动器日志缺 DRIVER-WALK-COMPLETE 完结标记（走查未完成）"
    grep -q '^FINAL_PHASE=done$' "$ART_DIR/场景1.P2.out" || fail "场景1.P2: state 未到达终态（FINAL_PHASE != done）。日志尾部: $(tail -10 "$ART_DIR/场景1.P2.out")"
    grep -q '^ACTIVE_PTR_PRESENT=no$' "$ART_DIR/场景1.P2.out" || fail "场景1.P2: 终态后 active.ptr 仍在（单任务终态应移除指针）"
    rm -f "$outfile"
    pass "场景1.P2: 闭环驱动器 120s 内 exit 0 且 state 到终态 phase=done + active.ptr 移除"
    # 终态口径注：phase 枚举终态为 done；done 时单任务路径机械移除 active.ptr（stop-hook §5 Case 3）
}

test_s1_p3_no_hang_markers() {
    # 场景1.P3 [det-machine] negate：闭环全程日志与 state 不含等待用户应答的挂起标记，计数 == 0
    local art="$ART_DIR/场景1.P2.out" count
    [[ -f "$art" ]] || fail "场景1.P3: 前置产物 场景1.P2.out 缺失（P2 未运行？）"
    grep -q '^DRIVER-WALK-COMPLETE$' "$art" || fail "场景1.P3: 驱动器走查未完成（防半程日志假 0）"
    count="$(wait_marker_count "$art")"
    [[ "$count" -eq 0 ]] || fail "场景1.P3: 挂起标记计数=${count}（要求 == 0；AskUserQuestion/pending-user/等待态出现在闭环日志或 state 中）"
    {
        echo "HANG_MARKER_COUNT=$count"
        echo "SCOPE=$art"
    } > "$ART_DIR/场景1.P3.out"
    pass "场景1.P3: 闭环产物挂起标记计数 == 0（negate 断言通过）"
}

test_s1_p4_hook_json_protocol() {
    # 场景1.P4 [real-process]：headless 任务下合成 payload 调 stop-hook → jq 可解析 JSON object
    # 且含协议关键字段（decision 或 systemMessage）
    local sbx state sess
    sbx="$(new_sandbox)"
    run_setup "$sbx" leak --headless "为工程补齐 README 的安装一节" >/dev/null
    [[ "$RUN_RC" -eq 0 ]] || fail "场景1.P4: headless 初始化失败 rc=$RUN_RC"
    state="$(state_path "$sbx")" || fail "场景1.P4: state.md 缺失"
    # 模拟 headless design 步骤 4 同轮确定性处置（行为矩阵 §7.6 行：不触发停等）
    state_set_fm "$state" auto_approve "true"
    state_set_fm "$state" phase '"implement"'
    sess="sess-hl-json-$$_$RANDOM"
    run_hook "$sbx" "$sess" clean
    printf '%s' "$OUT_STDOUT" | jq -e . >/dev/null 2>&1 \
        || fail "场景1.P4: stop-hook stdout 非合法 JSON（jq -e . 失败）。stdout: $OUT_STDOUT"
    printf '%s' "$OUT_STDOUT" | jq -e 'type == "object"' >/dev/null 2>&1 \
        || fail "场景1.P4: 输出不是 JSON object。stdout: $OUT_STDOUT"
    printf '%s' "$OUT_STDOUT" | jq -e '(has("decision") or has("systemMessage"))' >/dev/null 2>&1 \
        || fail "场景1.P4: JSON 缺协议关键字段（需 has decision 或 has systemMessage）。stdout: $OUT_STDOUT"
    {
        echo "HOOK_RC=$HOOK_RC"
        echo "--- stdout ---"
        printf '%s\n' "$OUT_STDOUT"
    } > "$ART_DIR/场景1.P4.out"
    pass "场景1.P4: stop-hook 输出合法 JSON object 且含 decision/systemMessage 协议字段"
}

# ═══════════════════════════════════════════════════════════════════════════
# 场景 2：交互点确定性放行并留痕（design 审批点 + 高风险 guardrail + 分流 + :53 回退）
# ═══════════════════════════════════════════════════════════════════════════

run_approval_points_driver() {
    local outfile rc
    outfile="$(mktemp -t hlap.XXXXXX)"
    run_with_timeout 60 "$outfile" bash "$SCRIPT_DIR/headless-approval-points.driver.sh"
    rc=$?
    rm -f "$outfile"
    return "$rc"
}

test_s2_p1_design_approval_deterministic() {
    # 场景2.P1：design 审批点 headless 下不发起询问 → 留痕含点位(design) + [headless] + 确定性处置
    local art="$ART_DIR/场景2.P1.out"
    run_approval_points_driver || fail "场景2.P1: headless-approval-points.driver.sh 执行失败（rc=$?）"
    [[ -f "$art" ]] || fail "场景2.P1: 留痕产物 $art 不存在"
    grep -qF 'design' "$art"   || fail "场景2.P1: 留痕不含点位标识 design"
    grep -qF '[headless]' "$art" || fail "场景2.P1: 留痕不含 [headless] 锚点词（C4 固定格式）"
    grep -qF '确定性处置' "$art" || fail "场景2.P1: 留痕不含 确定性处置（C4 固定格式）"
    pass "场景2.P1: design 审批点确定性放行留痕完整（design + [headless] + 确定性处置）"
}

test_s2_p2_guardrail_deterministic() {
    # 场景2.P2：高风险 guardrail（5 类闭合标准任一）触发 → 确定性放行 + guardrail 留痕
    local art="$ART_DIR/场景2.P2.out"
    [[ -f "$art" ]] || fail "场景2.P2: guardrail 留痕产物 $art 不存在"
    grep -qF 'guardrail' "$art"   || fail "场景2.P2: 留痕不含 guardrail 标识"
    grep -qF '[headless]' "$art"  || fail "场景2.P2: 留痕不含 [headless] 锚点词"
    pass "场景2.P2: guardrail 命中确定性放行留痕完整（guardrail + [headless]）"
}

test_s2_p4_complexity_split_no_ask() {
    # 场景2.P4 [det-machine]：design 步骤 1 且 mode 空 → AskUserQuestion 计数 == 0（negate）
    # 且分流留痕含「单任务」
    local art="$ART_DIR/场景2.P4.out" count
    [[ -f "$art" ]] || fail "场景2.P4: 产物 $art 不存在"
    grep -q '^WALK-COMPLETE$' "$art" || fail "场景2.P4: 驱动走查未完成（防半程日志假 0）"
    count="$(wait_marker_count "$art")"
    [[ "$count" -eq 0 ]] || fail "场景2.P4: AskUserQuestion/等待标记计数=${count}（要求 == 0，headless 复杂度分流不得询问）"
    grep -qF '单任务' "$art" || fail "场景2.P4: 分流留痕不含「单任务」（按单任务模式继续的假设未记录）"
    pass "场景2.P4: 复杂度分流零询问（计数=0）且按单任务继续留痕"
}

test_s2_p5_stage_failure_no_ask() {
    # 场景2.P5 [det-machine]：Auto-Approve/Fast 环节失败触发 SKILL.md:53 回退点 → 不问 + [headless] 留痕
    local art="$ART_DIR/场景2.P5.out" count
    [[ -f "$art" ]] || fail "场景2.P5: 产物 $art 不存在"
    grep -q '^WALK-COMPLETE$' "$art" || fail "场景2.P5: 驱动走查未完成（防半程日志假 0）"
    count="$(wait_marker_count "$art")"
    [[ "$count" -eq 0 ]] || fail "场景2.P5: AskUserQuestion/等待标记计数=${count}（要求 == 0，headless 下 :53 回退点不问）"
    grep -qF '[headless]' "$art" || fail "场景2.P5: 处置留痕不含 [headless]（C4：显式失败出口同属确定性处置）"
    pass "场景2.P5: :53 环节失败回退零询问且显式失败出口留痕"
}

test_s2_p3_trace_freshness() {
    # 场景2.P3 [freshness]：留痕产物本次运行新鲜（mtime 距驱动结束 < 60s）且含时间戳字段
    local art="$ART_DIR/场景2.P1.out" now mtime age
    [[ -f "$art" ]] || fail "场景2.P3: 留痕产物 $art 不存在"
    now="$(now_epoch)"
    mtime="$(file_mtime "$art")"
    [[ -n "$mtime" ]] || fail "场景2.P3: 无法读取产物 mtime"
    age=$(( now - mtime ))
    [[ "$age" -ge 0 && "$age" -lt 60 ]] || fail "场景2.P3: 产物 mtime 距驱动结束 ${age}s（要求 < 60s，非本次新鲜写入）"
    grep -Eq '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' "$art" \
        || fail "场景2.P3: 留痕不含可追溯时间戳字段（ISO-8601 UTC）"
    {
        echo "MTIME_AGE_SECONDS=$age"
        echo "HAS_TIMESTAMP_FIELD=yes"
    } > "$ART_DIR/场景2.P3.out"
    pass "场景2.P3: 留痕新鲜（mtime 差=${age}s < 60）且含时间戳字段"
}

# ═══════════════════════════════════════════════════════════════════════════
# 场景 3：flag 解析防误报
# ═══════════════════════════════════════════════════════════════════════════

PROSE_GOAL="策略：先按 --fast 跑一轮，再用 --standard 复核"

test_s3_p1_prose_flag_no_effect() {
    # 场景3.P1 [real-process] C2：目标文本含 --fast/--standard 字面量且未显式传档位 flag
    # → 档位字段与对照基线一致 且 != "fast" 且 != "standard"
    local sbx_ctl sbx_lit ctl_state lit_state ctl_val lit_val
    sbx_ctl="$(new_sandbox)"; sbx_lit="$(new_sandbox)"
    run_setup "$sbx_ctl" clean "为工程补齐 README 的安装一节" >/dev/null
    [[ "$RUN_RC" -eq 0 ]] || fail "场景3.P1: 对照基线运行失败 rc=$RUN_RC"
    run_setup "$sbx_lit" clean "$PROSE_GOAL" >/dev/null
    [[ "$RUN_RC" -eq 0 ]] || fail "场景3.P1: 含字面量运行失败 rc=$RUN_RC"
    ctl_state="$(state_path "$sbx_ctl")" || fail "场景3.P1: 对照 state 缺失"
    lit_state="$(state_path "$sbx_lit")" || fail "场景3.P1: 字面量 state 缺失"
    ctl_val="$(field_value "$ctl_state" fast_mode)"
    lit_val="$(field_value "$lit_state" fast_mode)"
    [[ "$lit_val" == "$ctl_val" ]] || fail "场景3.P1: 含字面量运行档位('$lit_val') != 对照基线('$ctl_val')——prose 中的档位字面量被误识别（C2 违约）"
    [[ "$lit_val" != "fast" ]] || fail "场景3.P1: 档位字段值 == fast（谓词明确禁止）"
    [[ "$lit_val" != "standard" ]] || fail "场景3.P1: 档位字段值 == standard（谓词明确禁止）"
    [[ "$lit_val" != "true" ]] || fail "场景3.P1: fast_mode 被字面量 --fast 激活（误识别为 flag，C2 违约）"
    [[ "$lit_val" != "false" ]] || fail "场景3.P1: fast_mode 被字面量 --standard 激活（误识别为 flag，C2 违约）"
    {
        echo "CONTROL_FAST_MODE=[$ctl_val]"
        echo "LITERAL_FAST_MODE=[$lit_val]"
        echo "PROSE_GOAL=$PROSE_GOAL"
    } > "$ART_DIR/场景3.P1.out"
    pass "场景3.P1: 字面量档位与基线一致（[$lit_val] == [$ctl_val]），prose token 未被识别为 flag"
}

test_s3_p2_goal_text_verbatim() {
    # 场景3.P2：目标文本含字面量 token → 逐字完整写入 state（不截断不改写，长度 == 输入长度）
    local sbx state text in_bytes got_bytes
    sbx="$(new_sandbox)"
    run_setup "$sbx" clean "$PROSE_GOAL" >/dev/null
    [[ "$RUN_RC" -eq 0 ]] || fail "场景3.P2: 运行失败 rc=$RUN_RC"
    state="$(state_path "$sbx")" || fail "场景3.P2: state 缺失"
    text="$(goal_text "$state")"
    grep -qF -- '--fast' <<< "$text"     || fail "场景3.P2: state 目标文本缺 --fast 字面量，实际: [$text]"
    grep -qF -- '--standard' <<< "$text" || fail "场景3.P2: state 目标文本缺 --standard 字面量，实际: [$text]"
    in_bytes="$(printf '%s' "$PROSE_GOAL" | wc -c | tr -d ' ')"
    got_bytes="$(printf '%s' "$text" | wc -c | tr -d ' ')"
    [[ "$got_bytes" -eq "$in_bytes" ]] || fail "场景3.P2: 目标文本字段长度($got_bytes) != 输入长度($in_bytes)——文本被截断/改写。实际: [$text]"
    [[ "$text" == "$PROSE_GOAL" ]] || fail "场景3.P2: 目标文本非逐字保留。期望: [$PROSE_GOAL] 实际: [$text]"
    {
        echo "INPUT_BYTES=$in_bytes"
        echo "STATE_GOAL_BYTES=$got_bytes"
        echo "STATE_GOAL=$text"
    } > "$ART_DIR/场景3.P2.out"
    pass "场景3.P2: 目标文本逐字完整写入（长度 $got_bytes == ${in_bytes}，含 --fast/--standard）"
}

test_s3_p3_explicit_flag_and_prose() {
    # 场景3.P3：显式 --fast + 文本含两字面量 → 档位生效 fast 且文本仍逐字保留
    local sbx state val text
    sbx="$(new_sandbox)"
    run_setup "$sbx" clean --fast "$PROSE_GOAL" >/dev/null
    [[ "$RUN_RC" -eq 0 ]] || fail "场景3.P3: 运行失败 rc=$RUN_RC"
    state="$(state_path "$sbx")" || fail "场景3.P3: state 缺失"
    val="$(field_value "$state" fast_mode)"
    [[ "$val" == "true" ]] || fail "场景3.P3: 显式 --fast 未生效（fast_mode=[$val]，要求 true）"
    text="$(goal_text "$state")"
    grep -qF -- '--standard' <<< "$text" || fail "场景3.P3: 显式 flag 生效后文本丢字面量 --standard。实际: [$text]"
    grep -qF -- '--fast' <<< "$text"     || fail "场景3.P3: 显式 flag 生效后文本丢字面量 --fast。实际: [$text]"
    {
        echo "FAST_MODE=[$val]"
        echo "STATE_GOAL=$text"
    } > "$ART_DIR/场景3.P3.out"
    pass "场景3.P3: 显式 --fast 生效（fast_mode=true）且目标文本逐字保留"
}

test_s3_p4_word_split_tokens() {
    # 场景3.P4 [real-process]：多 argv token 分词形式（目标未加引号，复现 live specimen 形态）
    # → 档位字段 == "" 且文本逐字保留（--fast/--standard 都在文本里）
    local outfile rc art
    art="$ART_DIR/场景3.P4.out"
    outfile="$(mktemp -t hlws.XXXXXX)"
    run_with_timeout 60 "$outfile" bash "$SCRIPT_DIR/headless-flag-word-split.driver.sh"
    rc=$?
    rm -f "$outfile"
    [[ "$rc" -eq 0 ]] || fail "场景3.P4: headless-flag-word-split.driver.sh exit=$rc"
    [[ -f "$art" ]] || fail "场景3.P4: 产物 $art 缺失"
    grep -q '^FAST_MODE_VALUE=$' "$art" || fail "场景3.P4: 档位字段非空（分词后的 --fast/--standard 被识别为 flag，C2 根治失败）。$(grep -E '^FAST_MODE_VALUE=' "$art")"
    grep -q '^GOAL_HAS_FAST=yes$'  "$art" || fail "场景3.P4: 目标文本丢失 --fast（被 flag 分支吞掉）"
    grep -q '^GOAL_HAS_STANDARD=yes$' "$art" || fail "场景3.P4: 目标文本丢失 --standard（被 flag 分支吞掉）"
    grep -q '^GOAL_BYTES_MATCH=yes$' "$art" || fail "场景3.P4: 分词重组后的目标文本与输入长度不一致"
    pass "场景3.P4: 多 argv token 分词形态下档位字段为空 + 文本逐字保留（活标本形态已根治）"
}

# ═══════════════════════════════════════════════════════════════════════════
# 场景 9：红队铁律 U1-U4 升级在 headless 下不问且保守处置留痕
# ═══════════════════════════════════════════════════════════════════════════

test_s9_p1_redteam_no_hang() {
    # 场景9.P1 [real-process]：U 类升级判定 headless 下不 AskUserQuestion 且 60s 内返回
    local outfile rc
    outfile="$(mktemp -t hlrt.XXXXXX)"
    run_with_timeout 60 "$outfile" bash "$SCRIPT_DIR/headless-redteam-escalation.driver.sh"
    rc=$?
    rm -f "$outfile"
    [[ "$rc" -ne 124 ]] || fail "场景9.P1: 红队 U 类升级驱动器超时挂起（rc=124）"
    [[ "$rc" -eq 0 ]] || fail "场景9.P1: 驱动器 exit=${rc}（要求 0）"
    [[ -f "$ART_DIR/场景9.P1.out" ]] || fail "场景9.P1: 产物 场景9.P1.out 缺失"
    pass "场景9.P1: U 类升级判定 60s 内返回（rc=0，未挂起）"
}

test_s9_p2_conservative_trace() {
    # 场景9.P2 [det-machine]：处置留痕含 [headless] + grep -E 'U[1-4]' >= 1 + 保守处置
    local art="$ART_DIR/场景9.P1.out" ucount
    [[ -f "$art" ]] || fail "场景9.P2: 前置产物缺失"
    grep -qF '[headless]' "$art" || fail "场景9.P2: 留痕不含 [headless]（C4）"
    ucount="$(grep -c -E 'U[1-4]' "$art" 2>/dev/null || true)"
    [[ "$ucount" -ge 1 ]] || fail "场景9.P2: U 编号命中数=${ucount}（要求 >= 1，弱锚单字母不认）"
    grep -qF '保守处置' "$art" || fail "场景9.P2: 留痕不含 保守处置"
    { echo "U_HIT_COUNT=$ucount"; } > "$ART_DIR/场景9.P2.out"
    pass "场景9.P2: U 类升级留痕完整（[headless] + U[1-4] 命中 $ucount + 保守处置）"
}

test_s9_p3_qa_report_leftover() {
    # 场景9.P3 [det-machine]：QA 报告遗留区含对应 U 编号条目（样板词「遗留」不满足——必须落具体条目）
    local art="$ART_DIR/场景9.P1.out" tmp count
    [[ -f "$art" ]] || fail "场景9.P3: 前置产物缺失"
    tmp="$(mktemp -t hllo.XXXXXX)"
    sed -n '/--- qa-report.begin ---/,/--- qa-report.end ---/p' "$art" > "$tmp"
    [[ -s "$tmp" ]] || fail "场景9.P3: 产物中无 QA 报告 dump（qa-report.begin/end 标记缺失）"
    # 提取遗留区：首个含「遗留」的标题行起，到下一个标题行为止
    awk '/遗留/{f=1; print; next} f && /^#/{f=0} f {print}' "$tmp" > "$tmp.sec"
    count="$(grep -c -E 'U[1-4]' "$tmp.sec" 2>/dev/null || true)"
    rm -f "$tmp" "$tmp.sec"
    [[ "$count" -ge 1 ]] || fail "场景9.P3: QA 报告遗留区 U[1-4] 条目命中数=${count}（要求 >= 1；「遗留」样板词不算，必须落具体 U 编号条目）"
    { echo "LEFTOVER_U_HIT=$count"; } > "$ART_DIR/场景9.P3.out"
    pass "场景9.P3: QA 报告遗留区含 U 编号具体条目（命中 ${count}）"
}

# ═══════════════════════════════════════════════════════════════════════════
# 场景 4：brainstorm Q&A 委托在 headless 下不挂起且处置显式留痕
# ═══════════════════════════════════════════════════════════════════════════

test_s4_p1_brainstorm_no_hang() {
    # 场景4.P1 [real-process]：委托链路 60s 超时内返回不挂起
    local outfile rc
    outfile="$(mktemp -t hlbd.XXXXXX)"
    run_with_timeout 60 "$outfile" bash "$SCRIPT_DIR/headless-brainstorm-delegation.driver.sh"
    rc=$?
    rm -f "$outfile"
    [[ "$rc" -ne 124 ]] || fail "场景4.P1: brainstorm 委托驱动器超时挂起（rc=124）"
    [[ "$rc" -eq 0 ]] || fail "场景4.P1: 驱动器 exit=${rc}（要求 0）"
    [[ -f "$ART_DIR/场景4.P1.out" ]] || fail "场景4.P1: 产物 场景4.P1.out 缺失"
    pass "场景4.P1: brainstorm 委托链路 60s 内返回（rc=0，未挂起）"
}

test_s4_p2_brainstorm_trace() {
    # 场景4.P2 [det-machine]：留痕非空且含 brainstorm 与 [headless]
    local art="$ART_DIR/场景4.P1.out" size
    [[ -f "$art" ]] || fail "场景4.P2: 前置产物缺失"
    size="$(wc -c < "$art" | tr -d ' ')"
    [[ "$size" -gt 0 ]] || fail "场景4.P2: 留痕产物为空（size=0）"
    grep -qF 'brainstorm' "$art"  || fail "场景4.P2: 留痕不含 brainstorm 标识"
    grep -qF '[headless]' "$art"  || fail "场景4.P2: 留痕不含 [headless] 锚点词（C4）"
    { echo "TRACE_SIZE=$size"; } > "$ART_DIR/场景4.P2.out"
    pass "场景4.P2: brainstorm 委托处置留痕非空（size=${size}）且含 brainstorm + [headless]"
}

# ═══════════════════════════════════════════════════════════════════════════
# 场景 5：qa 收口/gate 分级未达标时 headless 显式处置不停等（C7）
# ═══════════════════════════════════════════════════════════════════════════

test_s5_p1_qa_gate_no_hold() {
    # 场景5.P1 [real-process]：分级未达标 + headless → gate 不进入停等（驱动器 60s 内返回）且留痕存在
    local outfile rc
    outfile="$(mktemp -t hlqg.XXXXXX)"
    run_with_timeout 60 "$outfile" bash "$SCRIPT_DIR/headless-qa-gate.driver.sh"
    rc=$?
    rm -f "$outfile"
    [[ "$rc" -ne 124 ]] || fail "场景5.P1: qa gate 驱动器超时停等（rc=124）"
    [[ "$rc" -eq 0 ]] || fail "场景5.P1: 驱动器 exit=${rc}（要求 0）"
    [[ -f "$ART_DIR/场景5.P1.out" ]] || fail "场景5.P1: gate 留痕产物 场景5.P1.out 缺失"
    pass "场景5.P1: qa gate 未达标在 headless 下不停等（60s 内 rc=0）且留痕存在"
}

state_dump_wait_count() { # <artifact> → state dump 段内等待应答标记计数
    local art="$1" tmp
    tmp="$(mktemp -t hlsd.XXXXXX)"
    sed -n '/--- state.dump.begin ---/,/--- state.dump.end ---/p' "$art" > "$tmp"
    wait_marker_count "$tmp"
    local rc=$?
    rm -f "$tmp"
    return "$rc"
}

test_s5_p2_gate_disposition_trace() {
    # 场景5.P2 [det-machine]：显式记录收口——size>0 + [headless] + (gate|verified|partial|unverified)
    local art="$ART_DIR/场景5.P1.out" size
    [[ -f "$art" ]] || fail "场景5.P2: 前置产物缺失"
    size="$(wc -c < "$art" | tr -d ' ')"
    [[ "$size" -gt 0 ]] || fail "场景5.P2: gate 留痕为空"
    grep -qF '[headless]' "$art" || fail "场景5.P2: gate 处置留痕不含 [headless]（C4：qa gate 显式失败出口同属确定性处置）"
    grep -q -E 'gate|verified|partial|unverified' "$art" || fail "场景5.P2: 留痕无分级/gate 字段可见（gate|verified|partial|unverified 均 0 命中）"
    { echo "TRACE_SIZE=$size"; } > "$ART_DIR/场景5.P2.out"
    pass "场景5.P2: gate 处置以显式记录收口（[headless] + 分级字段可见）"
}

test_s5_p3_state_no_wait() {
    # 场景5.P3 [det-machine] negate：处置后 state 不停留在等待用户应答态（计数 == 0）
    local art="$ART_DIR/场景5.P1.out" count
    [[ -f "$art" ]] || fail "场景5.P3: 前置产物缺失"
    grep -q '^WALK-COMPLETE$' "$art" || fail "场景5.P3: 驱动走查未完成（防半程 state 假 0）"
    count="$(state_dump_wait_count "$art")"
    [[ "$count" -eq 0 ]] || fail "场景5.P3: 处置后 state 含等待应答标记，计数=${count}（要求 == 0）"
    { echo "STATE_WAIT_MARKER_COUNT=$count"; } > "$ART_DIR/场景5.P3.out"
    pass "场景5.P3: 处置后 state 零等待应答标记（计数=0）"
}

test_s5_p4_gate_kept_no_merge() {
    # 场景5.P4 [det-machine] C7：gate 保留停等且不进入 merge（显式失败出口）
    # assert: gate == "review-accept" AND phase == "qa" AND 无 merge commit 产物
    local art="$ART_DIR/场景5.P1.out" tmp gate_line phase_line commits
    [[ -f "$art" ]] || fail "场景5.P4: 前置产物缺失"
    tmp="$(mktemp -t hlq4.XXXXXX)"
    sed -n '/--- state.dump.begin ---/,/--- state.dump.end ---/p' "$art" > "$tmp"
    gate_line="$(grep -E '^gate:' "$tmp" | head -1)"
    phase_line="$(grep -E '^phase:' "$tmp" | head -1)"
    rm -f "$tmp"
    [[ "$gate_line" == 'gate: "review-accept"' ]] || fail "场景5.P4: gate 未保留（实际 [$gate_line]，要求 \"review-accept\"——分级未达标绝不清 gate）"
    [[ "$phase_line" == 'phase: "qa"' ]] || fail "场景5.P4: phase 未停在 qa（实际 [$phase_line]，要求 \"qa\"——未达标不得进 merge）"
    commits="$(grep -E '^MERGE_COMMIT_COUNT=' "$art" | head -1 | cut -d= -f2)"
    [[ "$commits" == "1" ]] || fail "场景5.P4: 沙盒仓库 commit 数=${commits}（要求仍为初始 1——出现 merge commit 产物，C7 违约）"
    grep -qF 'merge 阶段必须使用 Agent' "$art" && fail "场景5.P4: hook 输出了 merge 推进 prompt（分级未达标被误判达标并自动推进）"
    pass "场景5.P4: gate 保留 \"review-accept\" + phase 停在 \"qa\" + 零 merge commit（C7 显式失败出口）"
}

# ═══════════════════════════════════════════════════════════════════════════
# 场景 6：CLAUDE_CODE_SESSION_ID 泄漏检测告警与反静默放行
# ═══════════════════════════════════════════════════════════════════════════

test_s6_p1_leak_warning() {
    # 场景6.P1 [real-process] C6：泄漏组 → 显式告警（stderr 非空 OR stdout 警示字段非空）
    # 且文本含 CLAUDE_CODE_SESSION_ID
    # 复现路径 = 设计文档记录的真实陷阱：setup.sh 继承宿主泄漏 env（uuid 形态）写入 state，
    # 随后 sess_ 前缀的 runtime session 调 stop-hook → 归属不符 + signature 命中。
    local sbx state hook_sess combined
    sbx="$(new_sandbox)"
    run_setup "$sbx" leak "为工程补齐 README 的安装一节" >/dev/null
    [[ "$RUN_RC" -eq 0 ]] || fail "场景6.P1: 任务初始化失败 rc=$RUN_RC"
    state="$(state_path "$sbx")" || fail "场景6.P1: state 缺失"
    local landed
    landed="$(field_value "$state" session_id)"
    [[ "$landed" == "$HOST_LEAK_SESSION_ID" ]] || fail "场景6.P1: 前置失效——泄漏 env 未落进 state（state session_id=[$landed]，无法复现泄漏陷阱）"
    hook_sess="sess_redteam_leak_6p1"
    run_hook "$sbx" "$hook_sess" leak
    combined="$(printf '%s\n%s' "$OUT_STDOUT" "$OUT_STDERR")"
    # 先落证据产物（失败也留审计痕迹），再做断言
    {
        echo "HOOK_RC=$HOOK_RC"
        echo "STATE_SESSION=$landed"
        echo "HOOK_SESSION=$hook_sess"
        echo "--- stdout ---"
        printf '%s\n' "$OUT_STDOUT"
        echo "--- stderr ---"
        printf '%s\n' "$OUT_STDERR"
    } > "$ART_DIR/场景6.P1.out"
    printf '%s' "$combined" | grep -qF 'CLAUDE_CODE_SESSION_ID' \
        || fail "场景6.P1: 泄漏告警未含变量名 CLAUDE_CODE_SESSION_ID。stdout: [$OUT_STDOUT] stderr: [$OUT_STDERR]"
    # CONTRACT_AMBIGUOUS: 警示字段名未冻结（设计文档说 systemMessage；谓词允许 stderr 非空或
    # stdout 警示字段非空——此处对 systemMessage/warning/reason 三者取宽容并集）
    local stderr_hit=0 field_hit=0
    [[ -n "${OUT_STDERR//[[:space:]]/}" ]] && stderr_hit=1
    printf '%s' "$OUT_STDOUT" | jq -e '[.systemMessage, .warning, .reason] | map(select(. != null and . != "")) | length > 0' >/dev/null 2>&1 && field_hit=1
    [[ "$stderr_hit" -eq 1 || "$field_hit" -eq 1 ]] || fail "场景6.P1: 无显式告警通道（stderr 空 且 stdout 无非空警示字段）。stdout: [$OUT_STDOUT]"
    pass "场景6.P1: 泄漏组显式告警且含 CLAUDE_CODE_SESSION_ID（stderr_hit=$stderr_hit field_hit=${field_hit}）"
}

test_s6_p2_leak_trace() {
    # 场景6.P2 [det-machine]：泄漏告警产生 → 留痕记录含泄漏变量名
    local art="$ART_DIR/场景6.P1.out" count
    [[ -f "$art" ]] || fail "场景6.P2: 前置产物缺失"
    count="$(grep -cF 'CLAUDE_CODE_SESSION_ID' "$art" 2>/dev/null || true)"
    [[ "$count" -ge 1 ]] || fail "场景6.P2: 泄漏留痕 CLAUDE_CODE_SESSION_ID 命中=${count}（要求 >= 1）"
    { echo "LEAK_TRACE_COUNT=$count"; } > "$ART_DIR/场景6.P2.out"
    pass "场景6.P2: 泄漏留痕记录含变量名（命中 ${count}）"
}

test_s6_p3_no_silent_release() {
    # 场景6.P3 [det-machine] negate：泄漏存在时不得产生「无告警伴随的静默放行」记录
    # 组合 = (放行标记 AND 不含告警标记)，计数必须 == 0
    local art="$ART_DIR/场景6.P1.out" released warned combo
    [[ -f "$art" ]] || fail "场景6.P3: 前置产物缺失"
    released=0; warned=0
    grep -q '^HOOK_RC=0$' "$art" && released=1
    grep -qF 'CLAUDE_CODE_SESSION_ID' "$art" && warned=1
    combo=0
    if [[ "$released" -eq 1 && "$warned" -eq 0 ]]; then combo=1; fi
    [[ "$combo" -eq 0 ]] || fail "场景6.P3: 检出无告警伴随的静默放行（hook rc=0 放行但全程无 CLAUDE_CODE_SESSION_ID 告警标记）——Guard 2 反静默放行缺失"
    { echo "SILENT_RELEASE_COMBO=$combo (released=$released warned=$warned)"; } > "$ART_DIR/场景6.P3.out"
    pass "场景6.P3: 泄漏下无「静默放行」组合（released=$released warned=${warned}）"
}

test_s6_p4_control_no_warning() {
    # 场景6.P4 [real-process] 对照防误报：泄漏 signature 不存在（session 归属匹配）→ 零告警
    # 关键构造：泄漏 env 仍在（证明告警按 signature 门控而非 env 出现即告），
    # 但 state session 与 payload session 一致（signature 不成立）。
    local sbx state sess count combined
    sbx="$(new_sandbox)"
    run_setup "$sbx" leak --headless "为工程补齐 README 的安装一节" >/dev/null
    [[ "$RUN_RC" -eq 0 ]] || fail "场景6.P4: headless 初始化失败 rc=$RUN_RC"
    state="$(state_path "$sbx")" || fail "场景6.P4: state 缺失"
    sess="sess-control-match-6p4"
    state_set_fm "$state" session_id "$sess"   # 强制归属匹配，隔离 setup 侧行为
    run_hook "$sbx" "$sess" leak
    combined="$(printf '%s\n%s' "$OUT_STDOUT" "$OUT_STDERR")"
    count="$(printf '%s' "$combined" | grep -cF 'CLAUDE_CODE_SESSION_ID' 2>/dev/null || true)"
    [[ "$count" -eq 0 ]] || fail "场景6.P4: 对照组出现泄漏告警（计数=${count}，要求 0）——signature 不存在却告警 = 误报。stdout: [$OUT_STDOUT] stderr: [$OUT_STDERR]"
    {
        echo "CONTROL_SESSION=$sess"
        echo "LEAK_ENV=exported"
        echo "WARNING_COUNT=$count"
        echo "--- stdout ---"
        printf '%s\n' "$OUT_STDOUT"
    } > "$ART_DIR/场景6.P4.out"
    pass "场景6.P4: 对照组零告警（signature 不存在，计数=0，防误报成立）"
}

# ═══════════════════════════════════════════════════════════════════════════
# 场景 7：交互模式行为完全不变（反向谓词，回归防线）
# ═══════════════════════════════════════════════════════════════════════════

test_s7_p1_no_headless_marker() {
    # 场景7.P1 [real-process] negate：未传 headless flag → state 不写 headless 档位标记（计数 == 0）
    # 断言取最严口径：state 全文（含 frontmatter/目标/变更日志）零 headless 字样；
    # P1 driver 的 goal 文本不含 headless 字样，故全文计数合法可达 0。
    local sbx state count
    sbx="$(new_sandbox)"
    run_setup "$sbx" clean "为工程补齐 README 的安装一节" >/dev/null
    [[ "$RUN_RC" -eq 0 ]] || fail "场景7.P1: 交互模式初始化失败 rc=$RUN_RC"
    state="$(state_path "$sbx")" || fail "场景7.P1: state 缺失"
    count="$(grep -ci 'headless' "$state" 2>/dev/null || true)"
    [[ "$count" -eq 0 ]] || fail "场景7.P1: state 全文 headless 标记计数=${count}（要求 == 0——非 headless 模板不得发射档位标记，C8）。state: $(cat "$state")"
    local field_count
    field_count="$(grep -c -E '^headless:' "$state" 2>/dev/null || true)"
    [[ "$field_count" -eq 0 ]] || fail "场景7.P1: frontmatter 出现 headless 字段行（字段级锚计数=${field_count}）"
    {
        echo "FULL_TEXT_COUNT=$count"
        echo "--- state.dump ---"
        cat "$state"
    } > "$ART_DIR/场景7.P1.out"
    pass "场景7.P1: 交互模式 state 零 headless 标记（全文计数=0）"
}

test_s7_p2_interactive_ask_preserved() {
    # 场景7.P2 [det-machine] C5：SKILL.md 与 references/*.md 保留交互点提问行为定义（匹配数 >= 1）
    local total skill_only
    total="$(cat "$SKILL_FILE" "$REFERENCES_DIR"/*.md 2>/dev/null | grep -c 'AskUserQuestion' || true)"
    skill_only="$(grep -c 'AskUserQuestion' "$SKILL_FILE" 2>/dev/null || true)"
    [[ "$total" -ge 1 ]] || fail "场景7.P2: SKILL.md + references 提问类指令匹配数=${total}（要求 >= 1——交互提问定义被删光，C5 违约）"
    [[ "$skill_only" -ge 1 ]] || fail "场景7.P2: SKILL.md 自身提问指令匹配数=${skill_only}（要求 >= 1）"
    {
        echo "TOTAL_ASK_MATCHES=$total"
        echo "SKILL_ASK_MATCHES=$skill_only"
    } > "$ART_DIR/场景7.P2.out"
    pass "场景7.P2: 交互提问行为定义保留（SKILL=$skill_only 处，总计=$total 处）"
}

test_s7_p3_interactive_no_headless_trace() {
    # 场景7.P3 [real-process] negate：交互模式闭环冒烟不产生 headless 专用自动放行留痕（计数 == 0）
    local outfile rc art
    art="$ART_DIR/场景7.P3.out"
    outfile="$(mktemp -t hlip.XXXXXX)"
    run_with_timeout 60 "$outfile" bash "$SCRIPT_DIR/interactive-parity.driver.sh"
    rc=$?
    rm -f "$outfile"
    [[ "$rc" -eq 0 ]] || fail "场景7.P3: interactive-parity.driver.sh exit=$rc"
    [[ -f "$art" ]] || fail "场景7.P3: 产物 $art 缺失"
    grep -q '^WALK-COMPLETE$' "$art" || fail "场景7.P3: 驱动走查未完成（防假 0）"
    grep -q '^HEADLESS_TRACE_COUNT=0$' "$art" || fail "场景7.P3: 交互模式运行产生了 headless 自动放行留痕（计数非 0）。$(grep -E '^HEADLESS_TRACE' "$art")"
    pass "场景7.P3: 交互模式冒烟零 headless 留痕（negate 断言通过）"
}

# ═══════════════════════════════════════════════════════════════════════════
# 场景 8：headless 档位与既有档位组合及 CLI 契约保持
# ═══════════════════════════════════════════════════════════════════════════

test_s8_p1_headless_fast_combo() {
    # 场景8.P1：--headless --fast 同传 → 两档同时生效且 exit 0
    # 字段级无引号锚（与既有发射格式一致）：^headless: true 与 ^fast_mode: true
    local sbx state hc fc
    sbx="$(new_sandbox)"
    run_setup "$sbx" clean --headless --fast "为工程补齐 README 的安装一节" >/dev/null
    [[ "$RUN_RC" -eq 0 ]] || fail "场景8.P1: 组合调用 exit=${RUN_RC}（要求 0）"
    state="$(state_path "$sbx")" || fail "场景8.P1: state 缺失"
    hc="$(grep -c -E '^headless: true' "$state" 2>/dev/null || true)"
    fc="$(grep -c -E '^fast_mode: true' "$state" 2>/dev/null || true)"
    [[ "$hc" -ge 1 ]] || fail "场景8.P1: ^headless: true 计数=${hc}（要求 >= 1——headless 档位未生效）"
    [[ "$fc" -ge 1 ]] || fail "场景8.P1: ^fast_mode: true 计数=${fc}（要求 >= 1——fast 档位未生效）"
    { echo "HEADLESS_COUNT=$hc"; echo "FAST_COUNT=$fc"; } > "$ART_DIR/场景8.P1.out"
    pass "场景8.P1: --headless --fast 两档同效（headless=$hc fast=${fc}，exit 0）"
}

test_s8_p2_headless_idempotent() {
    # 场景8.P2 C8 幂等：--headless --headless 重复传入 → exit 0 且字段级发射
    # 幂等口径：恰好发射一次（重复 flag 不应产生重复 frontmatter 键行）
    local sbx state hc
    sbx="$(new_sandbox)"
    run_setup "$sbx" clean --headless --headless "为工程补齐 README 的安装一节" >/dev/null
    [[ "$RUN_RC" -eq 0 ]] || fail "场景8.P2: 重复 flag exit=${RUN_RC}（要求 0，幂等接受）"
    state="$(state_path "$sbx")" || fail "场景8.P2: state 缺失"
    hc="$(grep -c -E '^headless: true' "$state" 2>/dev/null || true)"
    [[ "$hc" -ge 1 ]] || fail "场景8.P2: ^headless: true 计数=${hc}（要求 >= 1）"
    [[ "$hc" -eq 1 ]] || fail "场景8.P2: headless 字段发射 $hc 次（幂等要求恰好一次，重复键行会破坏 frontmatter 唯一性）"
    { echo "HEADLESS_COUNT=$hc"; } > "$ART_DIR/场景8.P2.out"
    pass "场景8.P2: --headless 重复传入幂等（exit 0 + 恰好一次字段级发射）"
}

test_s8_p3_unknown_flag_to_text() {
    # 场景8.P3：前导未定义 flag → 沿用既有契约 exit 0 且逐字归入目标文本
    # （脚本设计不变量：所有错误经 stdout、非零退出会阻断 skill 加载 → 永远 exit 0）
    local sbx state text
    sbx="$(new_sandbox)"
    run_setup "$sbx" clean --not-a-real-flag "为工程补齐 README 的安装一节" >/dev/null
    [[ "$RUN_RC" -eq 0 ]] || fail "场景8.P3: 未定义 flag exit=${RUN_RC}（既有契约为 exit 0，非零退出会阻断 skill 加载）"
    state="$(state_path "$sbx")" || fail "场景8.P3: state 缺失"
    text="$(goal_text "$state")"
    grep -qF -- '--not-a-real-flag' <<< "$text" || fail "场景8.P3: 未定义 flag 未逐字归入目标文本。实际: [$text]"
    { echo "STATE_GOAL=$text"; } > "$ART_DIR/场景8.P3.out"
    pass "场景8.P3: 未定义 flag exit 0 且逐字归入目标文本"
}

# ═══════════════════════════════════════════════════════════════════════════
# C3 指针 / C8 文件内容断言
# ═══════════════════════════════════════════════════════════════════════════

test_C3_skill_pointers() {
    # C3 证据：行为矩阵 6 处 AskUserQuestion 点位的 headless 指针存在于 SKILL.md
    # （设计 §5：五处单行内替换 + 优先级表；净 0 行 → 设计引用行号稳定，±3 窗口容漂移）
    # CONTRACT_AMBIGUOUS: SKILL 替换行的具体措辞未冻结，此处只断言 headless 指针存在。
    local missing=""
    skill_win_has 48  'headless' || missing="${missing} 优先级表(:46-50)"
    skill_win_has 53  'headless' || missing="${missing} 环节失败回退(:53)"
    skill_win_has 58  'headless' || missing="${missing} brainstorm委托(:57-59)"
    skill_win_has 85  'headless' || missing="${missing} 复杂度分流(:85)"
    skill_win_has 127 'headless' || missing="${missing} guardrail必问(:127-128)"
    if ! skill_win_has 348 'headless' && ! skill_win_has 362 'headless'; then
        missing="${missing} U1-U4指针(:348,:362)"
    fi
    [[ -z "$missing" ]] || fail "C3: SKILL.md headless 指针缺失：$missing"
    pass "C3: SKILL.md 六处交互点位 headless 指针齐备（优先级表/:53/:57-59/:85/:127-128/:348|362）"
}

test_C8_headless_protocol_ssot() {
    # C8：references/headless-protocol.md 为 SSOT——存在 + 行为矩阵锚点 + 留痕契约 + 写入者唯一
    [[ -f "$PROTOCOL_MD" ]] || fail "C8: references/headless-protocol.md 不存在（设计 §5 新 SSOT）"
    grep -qF '写入者=setup.sh' "$PROTOCOL_MD" || fail "C8: headless-protocol.md 缺「写入者=setup.sh」字段定义锚（写入者唯一断言）"
    grep -qF '[headless]' "$PROTOCOL_MD" || fail "C8: headless-protocol.md 缺 [headless] 留痕契约锚（C4）"
    grep -qF '确定性处置' "$PROTOCOL_MD" || fail "C8: headless-protocol.md 缺「确定性处置」留痕契约锚（C4）"
    local miss=""
    grep -qF '单任务'   "$PROTOCOL_MD" || miss="${miss} 复杂度分流"
    grep -qE '自答|自行回答|推演关键问题' "$PROTOCOL_MD" || miss="${miss} brainstorm自答"
    grep -qF '预授权'   "$PROTOCOL_MD" || miss="${miss} guardrail预授权"
    grep -qF '保守处置' "$PROTOCOL_MD" || miss="${miss} U1-U4保守处置"
    grep -qF '显式失败' "$PROTOCOL_MD" || miss="${miss} 显式失败出口"
    [[ -z "$miss" ]] || fail "C8: headless-protocol.md 行为矩阵缺点位行：$miss"
    # CONTRACT_AMBIGUOUS: 泄漏机制文档落点未冻结（headless-protocol.md 或 state-file-guide.md）
    grep -qF 'CLAUDE_CODE_SESSION_ID' "$PROTOCOL_MD" \
        || grep -qF 'CLAUDE_CODE_SESSION_ID' "$STATE_GUIDE" \
        || fail "C8: 泄漏检测机制（CLAUDE_CODE_SESSION_ID）未在 headless-protocol.md / state-file-guide.md 任一文档化"
    pass "C8: headless-protocol.md SSOT 完整（写入者唯一 + 行为矩阵 5 点位 + C4 留痕契约 + 泄漏机制文档）"
}

test_C8_state_guide_field() {
    # C8：state-file-guide.md 含 headless 字段五元组（字段名/语义/合法值/写入者/读者）
    # CONTRACT_AMBIGUOUS: 五元组标签字面未冻结；此处锚合法值(true)/写入者/读者三个强字段。
    local entry
    entry="$(grep -n -A2 -E '^-.?`?headless`?' "$STATE_GUIDE" 2>/dev/null | head -6)"
    [[ -n "$entry" ]] || fail "C8: state-file-guide.md 缺 headless 字段条目"
    grep -q 'true' <<< "$entry"   || fail "C8: headless 字段条目缺合法值锚（canonical true）"
    grep -q '写入者' <<< "$entry"  || fail "C8: headless 字段条目缺「写入者」元组项"
    grep -q '读者' <<< "$entry"    || fail "C8: headless 字段条目缺「读者」元组项"
    pass "C8: state-file-guide.md headless 字段五元组在档（合法值/写入者/读者锚齐备）"
}

test_C8_writer_and_net0() {
    # C8：写入机制唯一（stop-hook 不读 headless 字段）+ SKILL.md 行数净 0（478 基线，不增）
    # 净 0 的精确执法由既有 skill-shrinkage-invariants 1.P2（per-file deleted >= added）承载，
    # 此处锁绝对口径：行数不得高于 478 基线（净缩减合法，净增长违约）。
    local quoted_reads lines
    quoted_reads="$(grep -c -E "[\"']headless[\"']" "$STOP_HOOK" 2>/dev/null || true)"
    [[ "$quoted_reads" -eq 0 ]] || fail "C8: stop-hook.sh 出现 headless 字段读取（$quoted_reads 处）——设计规定 stop-hook 不读该字段（读者=编排器 AI）"
    lines="$(wc -l < "$SKILL_FILE" | tr -d ' ')"
    [[ "$lines" -le 478 ]] || fail "C8: SKILL.md 行数=${lines}（478 基线，净 0 行约束违约）"
    { echo "SKILL_LINES=$lines"; echo "STOPHOOK_FIELD_READS=$quoted_reads"; } > "$ART_DIR/C8.writer-net0.out"
    pass "C8: stop-hook 零 headless 字段读取 + SKILL.md 行数 $lines <= 478 基线（净 0）"
}

# ═══════════════════════════════════════════════════════════════════════════
# 执行（依赖顺序：先驱动器后 fs-grep 断言；freshness 紧随其产物产生）
# ═══════════════════════════════════════════════════════════════════════════
test_s1_p1_headless_init
test_s1_p2_full_loop_terminal
test_s1_p3_no_hang_markers
test_s1_p4_hook_json_protocol
test_s2_p1_design_approval_deterministic
test_s2_p2_guardrail_deterministic
test_s2_p4_complexity_split_no_ask
test_s2_p5_stage_failure_no_ask
test_s2_p3_trace_freshness
test_s3_p1_prose_flag_no_effect
test_s3_p2_goal_text_verbatim
test_s3_p3_explicit_flag_and_prose
test_s3_p4_word_split_tokens
test_s9_p1_redteam_no_hang
test_s9_p2_conservative_trace
test_s9_p3_qa_report_leftover
test_s4_p1_brainstorm_no_hang
test_s4_p2_brainstorm_trace
test_s5_p1_qa_gate_no_hold
test_s5_p2_gate_disposition_trace
test_s5_p3_state_no_wait
test_s5_p4_gate_kept_no_merge
test_s6_p1_leak_warning
test_s6_p2_leak_trace
test_s6_p3_no_silent_release
test_s6_p4_control_no_warning
test_s7_p1_no_headless_marker
test_s7_p2_interactive_ask_preserved
test_s7_p3_interactive_no_headless_trace
test_s8_p1_headless_fast_combo
test_s8_p2_headless_idempotent
test_s8_p3_unknown_flag_to_text
test_C3_skill_pointers
test_C8_headless_protocol_ssot
test_C8_state_guide_field
test_C8_writer_and_net0

echo "[OK ] headless-mode — 全部谓词断言通过（9 组 32 条冻结谓词 + C3/C8 文件断言）"
exit 0
