#!/usr/bin/env bash
# R-ke-normalize: knowledge_extracted 守卫三态化 + frontmatter 重复键健壮性
#
# 背景：审计 19 个真实 session 发现 merge 收尾时 AI 反复把 knowledge_extracted 写成
# 非法 token（yes/done/中文摘要），旧 stop-hook 一律回滚 merge 重跑全部知识提取——
# 即使活已经做完、只是 token 写错（tautological-key 陷阱），白烧 iteration。
#
# 设计契约（state-file-guide.md + 本次三态化）：
#   phase=done 时 knowledge_extracted：
#     T1 合法 true/skipped           → 放行 done（不回滚）
#     T2 空值（这一步根本没做，非豁免）→ 回滚 merge + block JSON（真守卫保留）
#     T3 非空乱值（yes/done/摘要）     → 自动归一为 true、不回滚、不输出 block JSON，
#                                       stderr 给出规范化告知
#   重复键（AI Edit 失误产生的两行同键）：
#     T4 get_field 取第一行；set_field 写后只剩一行；正文同名行不受影响
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
STOP_HOOK="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"
LIB="$REPO_ROOT/plugins/autopilot/scripts/lib.sh"

PASS_COUNT=0
FAIL_COUNT=0
fail() { echo "[FAIL] R-ke-normalize: $1" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }
pass() { echo "[PASS] R-ke-normalize: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }

[[ -f "$STOP_HOOK" ]] || { echo "[FATAL] stop-hook.sh 不存在: $STOP_HOOK"; exit 1; }
[[ -f "$LIB" ]] || { echo "[FATAL] lib.sh 不存在: $LIB"; exit 1; }
command -v jq >/dev/null || { echo "[FATAL] 需要 jq 但未安装"; exit 1; }

# ── fixture：单任务 done 场景（brief_file 空 + mode single → done-handler Case 3 清理退出）──
# 参数: knowledge_extracted 值（原样写入，含引号）
build_fixture() {
    local ke="$1"
    local dir
    dir="$(mktemp -d -t autopilot-ke-XXXXXX)"
    mkdir -p "$dir/.autopilot/runtime/requirements/test-task"
    echo "test-task" > "$dir/.autopilot/runtime/active.ptr"
    cat > "$dir/.autopilot/runtime/requirements/test-task/state.md" <<EOF
---
active: true
phase: "done"
gate: ""
iteration: 5
max_iterations: 30
max_retries: 3
retry_count: 0
mode: "single"
plan_mode: ""
fast_mode: true
brief_file: ""
next_task: ""
auto_approve: false
knowledge_extracted: $ke
task_dir: "$dir/.autopilot/runtime/requirements/test-task"
session_id: kesess
started_at: "2026-05-31T00:00:00Z"
contract_required: false
html_review: false
---

## 目标
ke fixture
EOF
    echo "$dir"
}

# 运行 stop-hook，stdout→变量、stderr→文件，附 exit code 行
run_hook() {
    local dir="$1" errfile="$2"
    local hook_input='{"session_id":"kesess","transcript_path":"/tmp/none"}'
    (cd "$dir" && echo "$hook_input" | bash "$STOP_HOOK" 2>"$errfile"; echo "__EXIT__$?")
}

get_state_field() {
    local dir="$1" field="$2"
    grep -m1 -E "^${field}:" "$dir/.autopilot/runtime/requirements/test-task/state.md" \
        | sed -E "s/^${field}:[[:space:]]*\"?([^\"]*)\"?$/\1/"
}

# ─────────────────────────────────────────────────────────────────────
# T1：合法 skipped → 放行 done，不回滚
# ─────────────────────────────────────────────────────────────────────
dir1="$(build_fixture '"skipped"')"; err1="$dir1/err.txt"
out1="$(run_hook "$dir1" "$err1")"
if echo "$out1" | grep -q '"decision":[[:space:]]*"block"'; then
    fail "T1 合法 skipped 不应输出 block JSON。stdout: $(echo "$out1" | grep -v __EXIT__)"
elif [[ "$(get_state_field "$dir1" phase)" != "done" ]]; then
    fail "T1 phase 应保持 done，实际: $(get_state_field "$dir1" phase)"
elif [[ "$(get_state_field "$dir1" knowledge_extracted)" != "skipped" ]]; then
    fail "T1 knowledge_extracted 应保持 skipped，实际: $(get_state_field "$dir1" knowledge_extracted)"
else
    pass "T1 合法 skipped → 放行 done、不回滚、不归一"
fi
rm -rf "$dir1"

# ─────────────────────────────────────────────────────────────────────
# T2：空值（非豁免单任务）→ 回滚 merge + block JSON（真守卫）
# ─────────────────────────────────────────────────────────────────────
dir2="$(build_fixture '""')"; err2="$dir2/err.txt"
out2="$(run_hook "$dir2" "$err2")"
if ! echo "$out2" | grep -q '"decision":[[:space:]]*"block"'; then
    fail "T2 空值应输出 block JSON 回滚。stdout: $(echo "$out2" | grep -v __EXIT__)"
elif [[ "$(get_state_field "$dir2" phase)" != "merge" ]]; then
    fail "T2 phase 应回滚 merge，实际: $(get_state_field "$dir2" phase)"
else
    pass "T2 空值非豁免 → 回滚 merge + block（真守卫保留）"
fi
rm -rf "$dir2"

# ─────────────────────────────────────────────────────────────────────
# T3：非空乱值 yes → 自动归一 true、不回滚、不 block、stderr 告知
# ─────────────────────────────────────────────────────────────────────
dir3="$(build_fixture '"yes"')"; err3="$dir3/err.txt"
out3="$(run_hook "$dir3" "$err3")"
ke3="$(get_state_field "$dir3" knowledge_extracted)"
ph3="$(get_state_field "$dir3" phase)"
if echo "$out3" | grep -q '"decision":[[:space:]]*"block"'; then
    fail "T3 乱值不应回滚/输出 block JSON。stdout: $(echo "$out3" | grep -v __EXIT__)"
elif [[ "$ke3" != "true" ]]; then
    fail "T3 knowledge_extracted 应被归一为 true，实际: $ke3"
elif [[ "$ph3" != "done" ]]; then
    fail "T3 phase 应保持 done（未回滚），实际: $ph3"
elif ! grep -q '规范化为 true' "$err3"; then
    fail "T3 stderr 应有规范化告知。stderr: $(cat "$err3")"
else
    pass "T3 乱值 yes → 归一 true + 不回滚 + stderr 告知（tautological-key 容错）"
fi
rm -rf "$dir3"

# ─────────────────────────────────────────────────────────────────────
# T4：frontmatter 重复键 — get_field 取第一行、set_field 写后去重、正文不动
# ─────────────────────────────────────────────────────────────────────
( # 子 shell 隔离 source 副作用
    # shellcheck source=/dev/null
    source "$LIB" >/dev/null 2>&1
    TMP="$(mktemp)"
    cat > "$TMP" <<'EOF'
---
active: true
phase: "done"
gate: "review-accept"
gate: ""
knowledge_extracted: "yes"
knowledge_extracted: ""
iteration: 3
---

# body
phase: not-a-field
EOF
    # shellcheck disable=SC2034  # STATE_FILE 被 sourced lib.sh 的 get_field/set_field 经全局读取
    STATE_FILE="$TMP"
    g_read="$(get_field gate)"
    k_read="$(get_field knowledge_extracted)"
    set_field "gate" '""'
    set_field "knowledge_extracted" '"true"'
    g_lines="$(grep -c '^gate:' "$TMP")"
    k_lines="$(grep -c '^knowledge_extracted:' "$TMP")"
    body_ok="$(grep -c 'phase: not-a-field' "$TMP")"
    fm_phase="$(get_field phase)"
    rm -f "$TMP"
    [[ "$g_read" == "review-accept" ]] || { echo "T4a get_field 重复 gate 应取第一行 review-accept，实际: $g_read"; exit 11; }
    [[ "$k_read" == "yes" ]]            || { echo "T4b get_field 重复 knowledge 应取第一行 yes，实际: $k_read"; exit 12; }
    [[ "$g_lines" == "1" ]]            || { echo "T4c set_field 后 gate 应只剩 1 行，实际: $g_lines"; exit 13; }
    [[ "$k_lines" == "1" ]]            || { echo "T4d set_field 后 knowledge 应只剩 1 行，实际: $k_lines"; exit 14; }
    [[ "$body_ok" == "1" ]]           || { echo "T4e 正文 'phase: not-a-field' 应保留，实际计数: $body_ok"; exit 15; }
    [[ "$fm_phase" == "done" ]]       || { echo "T4f frontmatter phase 不应被波及，实际: $fm_phase"; exit 16; }
)
t4_rc=$?
if [[ $t4_rc -eq 0 ]]; then
    pass "T4 重复键：get_field 取第一行 + set_field 写后去重 + 正文/他字段不受影响"
else
    fail "T4 重复键健壮性子断言失败（rc=$t4_rc，详见上方输出）"
fi

# ── 汇总 ──
echo ""
echo "─────────────────────────────────────────"
echo "R-ke-normalize 汇总: PASS=$PASS_COUNT FAIL=$FAIL_COUNT"
echo "─────────────────────────────────────────"
[[ $FAIL_COUNT -gt 0 ]] && exit 1
exit 0
