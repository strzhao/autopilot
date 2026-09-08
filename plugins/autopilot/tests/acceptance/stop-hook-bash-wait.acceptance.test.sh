#!/usr/bin/env bash
# stop-hook-bash-wait: has_pending_subagents 路径 C（后台 Bash 任务）检测契约
# 红队测试 — 仅基于设计文档契约 C9-C13 编写，不读取 stop-hook.sh 的具体实现
#
# 契约来自 state.md ## 契约规约（冻结）：
#   C9 路径 C 检测: transcript 含 toolUseResult.backgroundTaskId 条目且对应 id 无 <task-id> 通知 → exit 0
#       正例: 仅启动条目 → rc=0 | 边界: 启动+通知同在 → rc=1 | 反例: 仅通知无启动 → rc=1
#   C10 通知集共用: bash pending = backgroundTaskId 集合 − queue-operation 通知 task-id 集合
#       （与异步 Agent 共用同一通知集；混合夹具: 1 异步 Agent pending + 1 bash 已完成通知 → rc=0）
#   C11 fail-safe 对称: jq 解析失败时，bash 启动 id 集 − 通知 id 集（文本集合差）> 0 → exit 0；
#       差为空 → 维持既有 C7/C8 行为
#   C12 向后兼容: 既有 has-pending-subagents.acceptance.test.sh（C1-C8）全 PASS
#   C13 无副作用: 路径 C 不产生文件写入/状态修改
#
# 验收场景覆盖映射：
#   S1.P1 → C9a（仅 bash 启动 → rc=0）
#   S1.P2 → C9b（启动+通知 → rc=1）
#   S1.P3 → C10a（混合夹具 → rc=0）
#   S2.P1 → C12（既有测试回归 exit 0）
#   S2.P2 → C11a（jq 必败夹具 + bash 启动未通知 → rc=0）
#   (S3.P1 bash -n 语法检查由 QA 执行，不入本测试)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 兼容两种落点：staging（.autopilot/runtime/...）与正式位置（plugins/autopilot/tests/acceptance）
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
if [[ ! -f "$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh" ]]; then
    REPO_ROOT="/Users/stringzhao/workspace/string-claude-code-plugin"
fi
STOP_HOOK="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"
EXISTING_TEST="$REPO_ROOT/plugins/autopilot/tests/acceptance/has-pending-subagents.acceptance.test.sh"

TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

fail() {
    echo "[FAIL] bash-wait: $1" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

pass() {
    echo "[PASS] bash-wait: $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

# 调用 has_pending_subagents 的 helper（复用既有测试模式）
# 返回 0 = has pending；1 = no pending
call_detect() {
    local transcript="$1"
    # 用 sub-shell source stop-hook.sh 并调用函数，避免主 shell 状态污染
    bash -c "source '$STOP_HOOK' >/dev/null 2>&1; has_pending_subagents '$transcript'"
    return $?
}

# 前置：stop-hook.sh 必须存在
[[ -f "$STOP_HOOK" ]] || { echo "[FATAL] stop-hook.sh 不存在: $STOP_HOOK"; exit 1; }
# 前置：既有测试文件必须存在（C12 依赖）
[[ -f "$EXISTING_TEST" ]] || { echo "[FATAL] 既有测试不存在: $EXISTING_TEST"; exit 1; }
# 前置：jq 必须可用
command -v jq >/dev/null || { echo "[FATAL] 需要 jq 但未安装"; exit 1; }

# ──────────────────────────────────────────────────────────────────────────
# fixture 构造器
# ──────────────────────────────────────────────────────────────────────────

# 后台 Bash 启动痕迹（路径 C 启动条目，schema 来自设计文档）
mk_bash_launched() {
    local task_id="$1"
    jq -nc --arg tid "$task_id" '
        {
            "type": "user",
            "isSidechain": false,
            "toolUseResult": {
                "stdout": "",
                "stderr": "",
                "interrupted": false,
                "isImage": false,
                "noOutputExpected": false,
                "backgroundTaskId": $tid
            }
        }
    '
}

# 后台 Bash / 异步 Agent 完成通知（queue-operation，schema 来自设计文档）
mk_task_notification() {
    local task_id="$1"
    local tool_use_id="${2:-call_MFm1VEqSbKifKmgj}"
    jq -nc --arg tid "$task_id" --arg tuid "$tool_use_id" '
        {
            "type": "queue-operation",
            "operation": "enqueue",
            "timestamp": "2026-09-09T00:00:00.000Z",
            "sessionId": "ea88e080-90b1-47f0-a5a0-565510b46a33",
            "content": ("<task-notification>\n<task-id>" + $tid + "</task-id>\n<tool-use-id>" + $tuid + "</tool-use-id>\n<output-file>/tmp/autopilot-artifacts/x.output</output-file>\n<status>completed</status>\n<summary>Background command completed</summary>\n</task-notification>")
        }
    '
}

# 异步 Agent 启动痕迹（既有路径 B，形状对齐既有测试 fixture）
mk_async_launched() {
    local agent_id="$1"
    local desc="${2:-test agent}"
    jq -nc --arg id "$agent_id" --arg desc "$desc" '
        {
            "type": "user",
            "isSidechain": false,
            "toolUseResult": {
                "isAsync": true,
                "status": "async_launched",
                "agentId": $id,
                "description": $desc
            }
        }
    '
}

# 异步 Agent 完成通知（既有路径 B 通知集）
mk_async_completed() {
    local task_id="$1"
    jq -nc --arg tid "$task_id" '
        {
            "type": "queue-operation",
            "operation": "enqueue",
            "content": ("<task-notification>\n<task-id>" + $tid + "</task-id>\n<status>completed</status>\n</task-notification>")
        }
    '
}

# 生成"半截 JSON 首行"：真实 JSON 的字节中间截断（与既有测试 C3/C7 同构造法）
mk_broken_first_line() {
    echo 'okens":1,"cache_creation_input_tokens":1447,"output_tokens":122}}'
}

# ──────────────────────────────────────────────────────────────────────────
# C9a [S1.P1]: 仅 bash 启动条目（未通知）→ exit=0 (has pending)
# ──────────────────────────────────────────────────────────────────────────
C9A="$TMPDIR_BASE/c9a.jsonl"
mk_bash_launched "b1p3om944" > "$C9A"
call_detect "$C9A"
code=$?
if [[ $code -eq 0 ]]; then
    pass "C9a/S1.P1: 仅 bash 启动未通知 → exit=0 (has pending)"
else
    fail "C9a/S1.P1: 期望 exit=0 (has pending)，实际 exit=$code（蓝队路径 C 未落地则 FAIL 属预期）"
fi

# ──────────────────────────────────────────────────────────────────────────
# C9b [S1.P2] 边界: bash 启动 + 对应 <task-id> 通知同在 → exit=1
# ──────────────────────────────────────────────────────────────────────────
C9B="$TMPDIR_BASE/c9b.jsonl"
mk_bash_launched "b1p3om944" > "$C9B"
mk_task_notification "b1p3om944" >> "$C9B"
call_detect "$C9B"
code=$?
if [[ $code -eq 1 ]]; then
    pass "C9b/S1.P2: bash 启动+通知同在 → exit=1 (no pending)"
else
    fail "C9b/S1.P2: 期望 exit=1，实际 exit=$code"
fi

# ──────────────────────────────────────────────────────────────────────────
# C9c 反例: 仅通知（queue-operation）无启动条目 → exit=1
# ──────────────────────────────────────────────────────────────────────────
C9C="$TMPDIR_BASE/c9c.jsonl"
mk_task_notification "b1p3om944_orphan" > "$C9C"
call_detect "$C9C"
code=$?
if [[ $code -eq 1 ]]; then
    pass "C9c: 仅通知无启动 → exit=1 (孤儿通知不误报)"
else
    fail "C9c: 期望 exit=1，实际 exit=$code"
fi

# ──────────────────────────────────────────────────────────────────────────
# C10a [S1.P3] 混合夹具: 1 个异步 Agent pending + 1 个 bash 已完成通知 → exit=0
#   （Agent pending 命中且 bash 不干扰不误报；通知集共用）
# ──────────────────────────────────────────────────────────────────────────
C10A="$TMPDIR_BASE/c10a.jsonl"
mk_async_launched "agent_mix1" "蓝队" > "$C10A"
mk_bash_launched "b1p3om944" >> "$C10A"
mk_task_notification "b1p3om944" >> "$C10A"
call_detect "$C10A"
code=$?
if [[ $code -eq 0 ]]; then
    pass "C10a/S1.P3: Agent pending + bash 已完成通知 → exit=0 (Agent 命中，bash 不干扰)"
else
    fail "C10a/S1.P3: 期望 exit=0，实际 exit=$code"
fi

# ──────────────────────────────────────────────────────────────────────────
# C10b 通知集共用补强: bash 启动+通知清零 且 Agent 启动+通知清零 → exit=1
#   （bash 与 Agent 走同一 queue-operation 通知集，两路 pending 都被清空）
# ──────────────────────────────────────────────────────────────────────────
C10B="$TMPDIR_BASE/c10b.jsonl"
mk_bash_launched "bash_c10b" > "$C10B"
mk_task_notification "bash_c10b" >> "$C10B"
mk_async_launched "agent_c10b" "红队" >> "$C10B"
mk_async_completed "agent_c10b" >> "$C10B"
call_detect "$C10B"
code=$?
if [[ $code -eq 1 ]]; then
    pass "C10b: bash+Agent 双双启动并通知 → exit=1 (通知集共用，全清零)"
else
    fail "C10b: 期望 exit=1，实际 exit=$code"
fi

# ──────────────────────────────────────────────────────────────────────────
# C11a [S2.P2] fail-safe: jq 必败夹具（首行半截 JSON 污染）+ bash 启动未通知 → exit=0
# ──────────────────────────────────────────────────────────────────────────
C11A="$TMPDIR_BASE/c11a.jsonl"
{
    mk_broken_first_line
    mk_bash_launched "bash_fs1"
} > "$C11A"
call_detect "$C11A"
code=$?
if [[ $code -eq 0 ]]; then
    pass "C11a/S2.P2: jq 失败 + bash 启动未通知 → fail-safe exit=0"
else
    fail "C11a/S2.P2: 期望 fail-safe exit=0，实际 exit=$code（蓝队 fail-safe 对称未落地则 FAIL 属预期）"
fi

# ──────────────────────────────────────────────────────────────────────────
# C11b fail-safe 差集为空: jq 必败夹具 + bash 启动但通知齐全 → exit=1（维持 C7/C8 行为）
# ──────────────────────────────────────────────────────────────────────────
C11B="$TMPDIR_BASE/c11b.jsonl"
{
    mk_broken_first_line
    mk_bash_launched "bash_fs2"
    mk_task_notification "bash_fs2"
} > "$C11B"
call_detect "$C11B"
code=$?
if [[ $code -eq 1 ]]; then
    pass "C11b: jq 失败 + bash 启动+通知（差集为空）→ exit=1"
else
    fail "C11b: 期望 exit=1（差集为空维持既有行为），实际 exit=$code"
fi

# ──────────────────────────────────────────────────────────────────────────
# C11c fail-safe 对称（Agent 侧不受 bash 引入影响）: jq 必败夹具 + async_launched 文本
#   → exit=0（既有 C7 语义在路径 C 引入后不变）
# ──────────────────────────────────────────────────────────────────────────
C11C="$TMPDIR_BASE/c11c.jsonl"
{
    mk_broken_first_line
    mk_async_launched "agent_fs3" "蓝队"
} > "$C11C"
call_detect "$C11C"
code=$?
if [[ $code -eq 0 ]]; then
    pass "C11c: jq 失败 + async_launched（无 bash 条目）→ exit=0（既有 fail-safe 不回归）"
else
    fail "C11c: 期望 exit=0，实际 exit=$code"
fi

# ──────────────────────────────────────────────────────────────────────────
# C12 [S2.P1]: 既有 has-pending-subagents.acceptance.test.sh（C1-C8）全 PASS → exit 0
# ──────────────────────────────────────────────────────────────────────────
bash "$EXISTING_TEST" >/dev/null 2>&1
code=$?
if [[ $code -eq 0 ]]; then
    pass "C12/S2.P1: 既有 C1-C8 测试回归 exit=0"
else
    fail "C12/S2.P1: 既有测试期望 exit=0，实际 exit=$code — 向后兼容被破坏"
fi

# ──────────────────────────────────────────────────────────────────────────
# C13: 无副作用 — 调用前后测试临时目录文件清单不变（轻量断言）
# ──────────────────────────────────────────────────────────────────────────
C13="$TMPDIR_BASE/c13.jsonl"
mk_bash_launched "bash_c13" > "$C13"
before_ls=$(ls -A "$TMPDIR_BASE" | sort)
call_detect "$C13" >/dev/null 2>&1
after_ls=$(ls -A "$TMPDIR_BASE" | sort)
if [[ "$before_ls" == "$after_ls" ]]; then
    pass "C13: 调用前后无新增文件（无副作用）"
else
    fail "C13: 检测到新增文件 — diff: <(echo \"$before_ls\") <(echo \"$after_ls\")"
fi

# ──────────────────────────────────────────────────────────────────────────
# 汇总
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
echo "bash-wait 汇总: PASS=$PASS_COUNT FAIL=$FAIL_COUNT"
echo "─────────────────────────────────────────"

if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 1
fi
exit 0
