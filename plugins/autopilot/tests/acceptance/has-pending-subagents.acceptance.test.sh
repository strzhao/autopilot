#!/usr/bin/env bash
# R-bg-detect: has_pending_subagents 后台 sub-agent 检测契约
# 红队测试 — 仅基于设计文档契约 C1-C8 编写，不读取 stop-hook.sh 的具体实现
#
# 契约来自 .autopilot/requirements/20260511-.../state.md ## 契约规约：
#   C1: transcript 文件不存在 → exit=1
#   C2: transcript 空 → exit=1
#   C3: 末尾 4MB 第一行半截 JSON + 后面有 async_launched + 无 completion → exit=0  (核心修复目标)
#   C4: 末尾 4MB 第一行半截 JSON + 后面有 async_launched + 有对应 completion → exit=1
#   C5: 完整 JSON 行 + async_launched 未完成 → exit=0
#   C6: 完整 JSON 行 + sync Agent 调用未返回 tool_result → exit=0
#   C7: jq 解析仍然失败 + raw tail 含 "status":"async_launched" → exit=0 (fail-safe)
#   C8: jq 解析失败且 raw tail 无 async_launched 文本 → exit=1

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
STOP_HOOK="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"

TMPDIR_BASE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

fail() {
    echo "[FAIL] R-bg-detect: $1" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

pass() {
    echo "[PASS] R-bg-detect: $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

# 调用 has_pending_subagents 的 helper
# 返回 0 = has pending；1 = no pending
call_detect() {
    local transcript="$1"
    # 用 sub-shell source stop-hook.sh 并调用函数，避免主 shell 状态污染
    bash -c "source '$STOP_HOOK' >/dev/null 2>&1; has_pending_subagents '$transcript'"
    return $?
}

# 前置：stop-hook.sh 必须存在
[[ -f "$STOP_HOOK" ]] || { echo "[FATAL] stop-hook.sh 不存在: $STOP_HOOK"; exit 1; }

# 前置：jq 必须可用
command -v jq >/dev/null || { echo "[FATAL] 需要 jq 但未安装"; exit 1; }

# ──────────────────────────────────────────────────────────────────────────
# C1: transcript 文件不存在 → exit=1
# ──────────────────────────────────────────────────────────────────────────
NONEXIST="$TMPDIR_BASE/nonexist.jsonl"
call_detect "$NONEXIST"
code=$?
if [[ $code -eq 1 ]]; then
    pass "C1: 不存在 transcript → exit=1"
else
    fail "C1: 不存在 transcript 期望 exit=1，实际 exit=$code"
fi

# ──────────────────────────────────────────────────────────────────────────
# C2: 空 transcript → exit=1
# ──────────────────────────────────────────────────────────────────────────
EMPTY="$TMPDIR_BASE/empty.jsonl"
: > "$EMPTY"
call_detect "$EMPTY"
code=$?
if [[ $code -eq 1 ]]; then
    pass "C2: 空 transcript → exit=1"
else
    fail "C2: 空 transcript 期望 exit=1，实际 exit=$code"
fi

# ──────────────────────────────────────────────────────────────────────────
# helper: 构造一个 async_launched JSON 行
# ──────────────────────────────────────────────────────────────────────────
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

mk_sync_agent_use() {
    local tool_use_id="$1"
    jq -nc --arg id "$tool_use_id" '
        {
            "type": "assistant",
            "isSidechain": false,
            "message": {
                "role": "assistant",
                "content": [{
                    "type": "tool_use",
                    "id": $id,
                    "name": "Agent",
                    "input": {"description": "test", "prompt": "test"}
                }]
            }
        }
    '
}

mk_sync_agent_result() {
    local tool_use_id="$1"
    jq -nc --arg id "$tool_use_id" '
        {
            "type": "user",
            "message": {
                "role": "user",
                "content": [{
                    "type": "tool_result",
                    "tool_use_id": $id,
                    "content": "done"
                }]
            }
        }
    '
}

# 生成"半截 JSON 首行"：取一个真实 JSON 的字节中间截断
# 模拟 tail -c 在字节边界中切产生的破损行
mk_broken_first_line() {
    # 一个完整 JSON 的中段（注意：故意不以 { 开头）
    echo 'okens":1,"cache_creation_input_tokens":1447,"output_tokens":122}}'
}

# ──────────────────────────────────────────────────────────────────────────
# C3: 半截首行 + async_launched + 无 completion → exit=0 (核心修复目标)
# ──────────────────────────────────────────────────────────────────────────
C3="$TMPDIR_BASE/c3.jsonl"
mk_broken_first_line > "$C3"
mk_async_launched "agent_c3" "蓝队" >> "$C3"
mk_async_launched "agent_c3b" "红队" >> "$C3"
call_detect "$C3"
code=$?
if [[ $code -eq 0 ]]; then
    pass "C3: 半截首行 + 2 个 async_launched 未完成 → exit=0 (has pending)"
else
    fail "C3: 期望 exit=0 (has pending)，实际 exit=$code — 这就是 error.txt 的根因场景"
fi

# ──────────────────────────────────────────────────────────────────────────
# C4: 半截首行 + async_launched + 对应 completion → exit=1
# ──────────────────────────────────────────────────────────────────────────
C4="$TMPDIR_BASE/c4.jsonl"
mk_broken_first_line > "$C4"
mk_async_launched "agent_c4a" "蓝队" >> "$C4"
mk_async_launched "agent_c4b" "红队" >> "$C4"
mk_async_completed "agent_c4a" >> "$C4"
mk_async_completed "agent_c4b" >> "$C4"
call_detect "$C4"
code=$?
if [[ $code -eq 1 ]]; then
    pass "C4: 半截首行 + 2 launched + 2 completed → exit=1 (no pending)"
else
    fail "C4: 期望 exit=1，实际 exit=$code"
fi

# ──────────────────────────────────────────────────────────────────────────
# C5: 完整 JSON 行 + async_launched 未完成 → exit=0
# ──────────────────────────────────────────────────────────────────────────
C5="$TMPDIR_BASE/c5.jsonl"
mk_async_launched "agent_c5" "蓝队" > "$C5"
call_detect "$C5"
code=$?
if [[ $code -eq 0 ]]; then
    pass "C5: 完整行 + launched 无 completion → exit=0"
else
    fail "C5: 期望 exit=0，实际 exit=$code"
fi

# ──────────────────────────────────────────────────────────────────────────
# C6: sync Agent 启动未完成 → exit=0
# ──────────────────────────────────────────────────────────────────────────
C6="$TMPDIR_BASE/c6.jsonl"
mk_sync_agent_use "toolu_c6_001" > "$C6"
call_detect "$C6"
code=$?
if [[ $code -eq 0 ]]; then
    pass "C6: sync Agent 未完成 → exit=0"
else
    fail "C6: 期望 exit=0，实际 exit=$code"
fi

# 反向验证 C6: sync Agent 启动后完成 → exit=1
C6B="$TMPDIR_BASE/c6b.jsonl"
mk_sync_agent_use "toolu_c6b_001" > "$C6B"
mk_sync_agent_result "toolu_c6b_001" >> "$C6B"
call_detect "$C6B"
code=$?
if [[ $code -eq 1 ]]; then
    pass "C6b: sync Agent launched+result → exit=1"
else
    fail "C6b: 期望 exit=1，实际 exit=$code"
fi

# ──────────────────────────────────────────────────────────────────────────
# C7: jq 解析失败（全文件都是垃圾）+ raw tail 含 async_launched 文本 → exit=0 fail-safe
# ──────────────────────────────────────────────────────────────────────────
C7="$TMPDIR_BASE/c7.jsonl"
# 多行连续垃圾，丢首行也救不了，但 tail 中保留了 async_launched 文本字面量
printf 'garbage line one not json\nmore garbage with "status":"async_launched" text inside but invalid json\nthird garbage line\n' > "$C7"
call_detect "$C7"
code=$?
if [[ $code -eq 0 ]]; then
    pass "C7: jq 失败 + 含 async_launched 文本 → fail-safe exit=0"
else
    fail "C7: 期望 fail-safe exit=0，实际 exit=$code — fail-unsafe 是这次灾难根因"
fi

# ──────────────────────────────────────────────────────────────────────────
# C8: jq 解析失败 + 无 async_launched 文本 → exit=1
# ──────────────────────────────────────────────────────────────────────────
C8="$TMPDIR_BASE/c8.jsonl"
printf 'pure garbage line\nmore broken stuff\nno async marker here\n' > "$C8"
call_detect "$C8"
code=$?
if [[ $code -eq 1 ]]; then
    pass "C8: jq 失败 + 无 async_launched 文本 → exit=1"
else
    fail "C8: 期望 exit=1，实际 exit=$code"
fi

# ──────────────────────────────────────────────────────────────────────────
# C9 [bonus, S3]: 大半截行（无换行符）— 边界 case
# 用一行超长 JSON 的中间段（不含 \n）作为整个 transcript 的首行
# ──────────────────────────────────────────────────────────────────────────
C9="$TMPDIR_BASE/c9.jsonl"
# 单行半截 + 后面跟合法 async_launched
{
    # 第一行：故意制造很长但没换行的半截
    printf '%s\n' 'okens":1,"junk":"aaaa","x":"y"}'
    mk_async_launched "agent_c9" "蓝队"
} > "$C9"
call_detect "$C9"
code=$?
if [[ $code -eq 0 ]]; then
    pass "C9: 半截单行 + launched → exit=0"
else
    fail "C9: 期望 exit=0，实际 exit=$code"
fi

# ──────────────────────────────────────────────────────────────────────────
# C10 [bonus]: 真实 transcript 文件回归（如果存在则跑）
# ──────────────────────────────────────────────────────────────────────────
REAL_TS="/Users/stringzhao/.claude/projects/-Users-stringzhao-workspace-relight--claude-worktrees-pick/1bf7db8b-dfbc-461e-a0a1-437f07e38aec.jsonl"
if [[ -f "$REAL_TS" ]]; then
    call_detect "$REAL_TS"
    code=$?
    # 在这个 transcript 里两个 agent 都已经 completed，预期 exit=1
    # 关键是不能崩、不能因 jq parse error 走错误降级
    if [[ $code -eq 1 ]]; then
        pass "C10: 真实 error.txt transcript（agent 已完成）→ exit=1"
    else
        fail "C10: 真实 error.txt transcript 期望 exit=1（agent 已完成），实际 exit=$code"
    fi

    # C10b: 复现 error.txt 当时的状态 — 截取 transcript 至 launched 之后、completion 之前
    # 关键：用行边界截断（模拟真实 transcript 在 stop-hook 触发瞬间，最后一行完整写出）
    # 这正好覆盖 launched (4.4M)，但不包含 completion (4.7M)
    C10B="$TMPDIR_BASE/real-mid.jsonl"
    # head -c 切到 4.5M 后用 sed 去掉最后一行（可能半截），剩下都是完整 JSON 行
    head -c 4500000 "$REAL_TS" | sed '$d' > "$C10B"
    call_detect "$C10B"
    code=$?
    if [[ $code -eq 0 ]]; then
        pass "C10b: 真实 transcript 截至 launched 后（error.txt 瞬态）→ exit=0 (has pending)"
    else
        fail "C10b: 真实 transcript 截至 launched 后期望 exit=0，实际 exit=$code — 这是 error.txt 根因场景"
    fi
else
    echo "[SKIP] R-bg-detect: C10 真实 transcript 不存在 ($REAL_TS)"
fi

# ──────────────────────────────────────────────────────────────────────────
# 汇总
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────"
echo "R-bg-detect 汇总: PASS=$PASS_COUNT FAIL=$FAIL_COUNT"
echo "─────────────────────────────────────────"

if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 1
fi
exit 0
