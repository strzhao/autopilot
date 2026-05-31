#!/usr/bin/env bash
# R-silent-wait-visibility: §7.5 后台 sub-agent 静默等待可见性契约
#
# 红队测试 — 仅基于设计文档验收谓词（state.md ## 验收场景 P1-P5 + ## 契约规约 C1-C3）
# 编写，不读取 stop-hook.sh §7.5 新增实现代码。
#
# 被测行为（设计意图）：
#   stop-hook 在检测到后台 sub-agent 仍在运行（has_pending=true）时，
#   应当放行（不重新唤醒 AI）但让用户可见：
#     - 输出一条含 "systemMessage" 键的 JSON（stdout）
#     - 文案含专属标志字符串 "等待后台 sub-agent"
#     - 绝不输出 "decision":"block"（精确串，防止重唤醒/merge 死循环）
#     - iteration 不递增（exit 仍在 §8 之前）
#   当无 pending 时此机制完全不介入（落入正常的 §9 block 注入）。
#
# 验收谓词来源（P1-P5）：
#   P1: has_pending=true → stdout 含 "等待后台 sub-agent"（§7.5 专属标志）
#   P2: has_pending=true → stdout 不含 "decision":"block"（精确串，放行不唤醒）
#   P3: has_pending=true → stdout 含 "systemMessage" 键
#   P4: has_pending=true → state.md iteration 仍为 5（不递增）
#   P5: 回归 — has_pending=false → stdout 含 "decision":"block" 且不含 "等待后台 sub-agent"
#
# Mutation 自检（反 tautological）：
#   若把 §7.5 新增的 jq systemMessage 行删掉（回退裸 exit 0），
#   P1/P3 必须转红 — "等待后台 sub-agent" 是 §7.5 新增专属标志，
#   §9 的 systemMessage 文案是 "autopilot iteration N | phase: X"，
#   §7.6 的是 "用户尚未确认"，均不含此串。
#
# 运行方式：bash plugins/autopilot/tests/acceptance/silent-wait-visibility.acceptance.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
STOP_HOOK="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"

# ── 计数器 ──────────────────────────────────────────────────────────────────
PASS_COUNT=0
FAIL_COUNT=0

fail() {
    echo "[FAIL] R-silent-wait: $1" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

pass() {
    echo "[PASS] R-silent-wait: $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

# 前置：stop-hook.sh 必须存在
[[ -f "$STOP_HOOK" ]] || { echo "[FATAL] R-silent-wait: stop-hook.sh 不存在: $STOP_HOOK" >&2; exit 1; }
# 前置：jq 必须可用（transcript 构造需要）
command -v jq >/dev/null || { echo "[FATAL] R-silent-wait: 需要 jq 但未安装" >&2; exit 1; }

# ── 全局临时目录（EXIT trap 清理） ───────────────────────────────────────────
TMPDIR_BASE=$(mktemp -d -t autopilot-silent-wait-XXXXXX)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# SESSION_ID 固定，供 fixture 与 stdin 一致
SESSION_ID="silent-wait-sess-001"

# ── 辅助：构造临时 git repo + state.md fixture ──────────────────────────────
# build_fixture <phase> <gate> <iteration>
#   构造含 git repo 的临时 fixture 目录，返回目录绝对路径（stdout）。
#   iteration 默认 5（P4 用前值 5 来断言不变性）
build_fixture() {
    local phase="$1"
    local gate="$2"
    local iteration="${3:-5}"

    local dir
    dir="$(mktemp -d -t autopilot-sw-fix-XXXXXX)"

    # 初始化 git repo（stop-hook.sh 依赖 git rev-parse --show-toplevel）
    git -C "$dir" init -q
    git -C "$dir" config user.email "test@test.com"
    git -C "$dir" config user.name "Test"

    mkdir -p "$dir/.autopilot/runtime/requirements/test-task"
    echo "test-task" > "$dir/.autopilot/runtime/active.ptr"

    # 构造 YAML frontmatter：session_id 与 stdin 一致
    {
        echo "---"
        echo "active: true"
        echo "phase: \"${phase}\""
        echo "gate: \"${gate}\""
        echo "iteration: ${iteration}"
        echo "max_iterations: 30"
        echo "max_retries: 3"
        echo "retry_count: 0"
        echo "mode: \"single\""
        echo "plan_mode: \"\""
        echo "fast_mode: false"
        echo "auto_approve: false"
        echo "knowledge_extracted: \"\""
        echo "task_dir: \"${dir}/.autopilot/runtime/requirements/test-task\""
        echo "session_id: ${SESSION_ID}"
        echo "started_at: \"2026-05-31T00:00:00Z\""
        echo "contract_required: false"
        echo "html_review: false"
        echo "---"
        echo ""
        echo "## 目标"
        echo "silent-wait-visibility 测试 fixture"
    } > "$dir/.autopilot/runtime/requirements/test-task/state.md"

    echo "$dir"
}

# ── 辅助：构造含未完成 Agent tool_use 的 transcript（has_pending=true）────────
# make_pending_transcript <dir>
#   主线程（isSidechain=false）Assistant 消息含 Agent tool_use，无对应 tool_result
#   → has_pending_subagents 返回 0（has pending）→ §7.5 触发
make_pending_transcript() {
    local dir="$1"
    local f="$dir/transcript_pending.jsonl"
    # 一条普通 user 消息（前景，无 agent 调用）
    jq -nc '{"isSidechain":false,"type":"user","message":{"role":"user","content":[{"type":"text","text":"start"}]}}' > "$f"
    # 主线程 assistant 消息：含 Agent tool_use，无对应 tool_result → sync pending
    jq -nc '{"isSidechain":false,"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_sw_001","name":"Agent","input":{"prompt":"long running task","options":{}}}]}}' >> "$f"
    echo "$f"
}

# ── 辅助：构造无 pending 的 transcript（has_pending=false）──────────────────
# make_clean_transcript <dir>
#   所有 Agent tool_use 都有对应 tool_result → has_pending_subagents 返回 1（no pending）
make_clean_transcript() {
    local dir="$1"
    local f="$dir/transcript_clean.jsonl"
    # 用户消息
    jq -nc '{"isSidechain":false,"type":"user","message":{"role":"user","content":[{"type":"text","text":"start"}]}}' > "$f"
    # Agent tool_use
    jq -nc '{"isSidechain":false,"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_sw_002","name":"Agent","input":{"prompt":"completed task","options":{}}}]}}' >> "$f"
    # 对应 tool_result（已完成）
    jq -nc '{"isSidechain":false,"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_sw_002","content":"done"}]}}' >> "$f"
    echo "$f"
}

# ── 辅助：驱动 stop-hook，透传 stdin JSON ────────────────────────────────────
# run_hook <dir> <transcript_path>
#   以 dir 为 cwd 驱动 stop-hook.sh，stdin 传 {cwd, session_id, transcript_path}。
#   输出：hook 的 stdout 行 + 最后一行 __EXIT__<code>
run_hook() {
    local dir="$1"
    local transcript_path="$2"
    local hook_input
    hook_input=$(jq -nc \
        --arg cwd "$dir" \
        --arg sid "$SESSION_ID" \
        --arg tp "$transcript_path" \
        '{"cwd":$cwd,"session_id":$sid,"transcript_path":$tp}')
    (cd "$dir" && echo "$hook_input" | bash "$STOP_HOOK" 2>/dev/null; echo "__EXIT__$?")
}

# ── 辅助：从 state.md 提取 frontmatter 字段值 ────────────────────────────────
get_state_field() {
    local dir="$1" field="$2"
    grep -E "^${field}:" \
        "$dir/.autopilot/runtime/requirements/test-task/state.md" \
        | head -1 \
        | sed -E "s/^${field}:[[:space:]]*\"?([^\"]*)\"?[[:space:]]*$/\1/"
}

# ════════════════════════════════════════════════════════════════════════════
# 场景 A（P1 + P2 + P3 + P4）：
#   phase=implement, gate="", iteration=5, max_iterations=30
#   transcript 含主线程未完成 Agent tool_use（has_pending=true）
#   → §7.5 触发 → 输出 systemMessage + 不含 decision:block + iteration 不变
# ════════════════════════════════════════════════════════════════════════════
dir_A="$(build_fixture implement "" 5)"
ts_A="$(make_pending_transcript "$dir_A")"
out_A="$(run_hook "$dir_A" "$ts_A")"
body_A=$(echo "$out_A" | grep -v '^__EXIT__')
exit_A=$(echo "$out_A" | grep '^__EXIT__' | sed 's/__EXIT__//')

# P0-放行码：§7.5 必须 exit 0（systemMessage 放行 = 允许 stop / 交回控制，非 block 唤醒）
if [ "$exit_A" = "0" ]; then
    pass "P0: has_pending=true → stop-hook exit 0（放行，不唤醒）"
else
    fail "P0: has_pending=true 时 stop-hook 应 exit 0（systemMessage 放行），实际 exit=${exit_A}"
fi

# P1：stdout 含 "等待后台 sub-agent"（§7.5 专属标志）
if echo "$body_A" | grep -q '等待后台 sub-agent'; then
    pass "P1: has_pending=true → stdout 含「等待后台 sub-agent」（§7.5 专属标志）"
else
    fail "P1: has_pending=true 时 stdout 应含「等待后台 sub-agent」，实际 stdout: ${body_A}"
fi

# P2：stdout 不含 "decision":"block"（防止重唤醒）
# ⚠️ §9 的 jq -n（无 -c）输出 pretty JSON：冒号后有空格 "decision": "block"。
# 故用 [[:space:]]* 容错正则（与 P5a 一致）——无空格精确串 '"decision":"block"' 永远匹配
# 不到带空格的真实输出，会让"不含 block"断言恒真（tautological），无法捕捉 C1 违反。
# [[:space:]]* 仍要求 "decision" 紧邻冒号紧邻 "block"，不跨字段误匹配。
if ! echo "$body_A" | grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    pass "P2: has_pending=true → stdout 不含精确串 \"decision\":\"block\"（放行不唤醒）"
else
    fail "P2: has_pending=true 时 stdout 不应含 \"decision\":\"block\"，违反放行契约（会重蹈 merge 死循环）。stdout: ${body_A}"
fi

# P3：stdout 含 "systemMessage" 键（确为 systemMessage 通道放行）
if echo "$body_A" | grep -q '"systemMessage"'; then
    pass "P3: has_pending=true → stdout 含 \"systemMessage\" 键（systemMessage 通道放行）"
else
    fail "P3: has_pending=true 时 stdout 应含 \"systemMessage\" 键，实际 stdout: ${body_A}"
fi

# P4：iteration 不递增（等待期间不消耗迭代预算）
iter_before=5
iter_after_A="$(get_state_field "$dir_A" iteration)"
if [[ "$iter_after_A" == "$iter_before" ]]; then
    pass "P4: has_pending=true → iteration 仍为 ${iter_before}（未递增，不消耗预算）"
else
    fail "P4: iteration 应保持 ${iter_before}，实际执行后为: ${iter_after_A} — §7.5 exit 0 在 §8 递增之前，不应改变 iteration"
fi

rm -rf "$dir_A"

# ════════════════════════════════════════════════════════════════════════════
# 场景 B（P5 回归）：
#   phase=implement, gate="", iteration=5, max_iterations=30
#   transcript 无 pending（所有 Agent tool_use 都有 tool_result）
#   → §7.5 不介入 → 落入 §9 正常注入 → 含 "decision":"block" 且不含 "等待后台 sub-agent"
# ════════════════════════════════════════════════════════════════════════════
dir_B="$(build_fixture implement "" 5)"
ts_B="$(make_clean_transcript "$dir_B")"
out_B="$(run_hook "$dir_B" "$ts_B")"
body_B=$(echo "$out_B" | grep -v '^__EXIT__')

# P5a：stdout 含 "decision":"block"（落入 §9 正常注入）
# 注意：设计谓词的"精确串 "decision":"block""的意图是避免 "decision".*"block" 正则跨字段误匹配，
# 并非要求 JSON 无空格格式；实际 jq 输出为格式化 JSON，用带空格容错的 grep 匹配。
if echo "$body_B" | grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    pass "P5a: has_pending=false → stdout 含 \"decision\":\"block\"（§9 正常注入，自动推进保持）"
else
    fail "P5a: has_pending=false 时 stdout 应含 \"decision\":\"block\"（§9 正常推进），实际 stdout: ${body_B}"
fi

# P5b：stdout 不含 "等待后台 sub-agent"（§7.5 未误触发）
if ! echo "$body_B" | grep -q '等待后台 sub-agent'; then
    pass "P5b: has_pending=false → stdout 不含「等待后台 sub-agent」（§7.5 未误触发）"
else
    fail "P5b: has_pending=false 时 §7.5 不应触发，stdout 不应含「等待后台 sub-agent」。stdout: ${body_B}"
fi

rm -rf "$dir_B"

# ════════════════════════════════════════════════════════════════════════════
# 场景 C（C2 契约 - 自救提示可见性）：
#   同 P1 条件，stdout 还须含 /autopilot cancel（自救出路提示）
#   来源：契约规约 C2："文案含...自救出路提示（/autopilot cancel）"
# ════════════════════════════════════════════════════════════════════════════
dir_C="$(build_fixture implement "" 5)"
ts_C="$(make_pending_transcript "$dir_C")"
out_C="$(run_hook "$dir_C" "$ts_C")"
body_C=$(echo "$out_C" | grep -v '^__EXIT__')

if echo "$body_C" | grep -q '/autopilot cancel'; then
    pass "C2-自救提示: has_pending=true → stdout 含 /autopilot cancel（自救出路可见）"
else
    fail "C2-自救提示: has_pending=true 时 stdout 应含 /autopilot cancel，契约 C2 要求自救出路可见。stdout: ${body_C}"
fi

rm -rf "$dir_C"

# ════════════════════════════════════════════════════════════════════════════
# 场景 D（全阶段泛化回归）：
#   §7.5 注释说明全阶段（implement/merge/qa/auto-fix）均受保护。
#   用 merge 阶段 + pending transcript 再验一次，确认非 phase-specific。
# ════════════════════════════════════════════════════════════════════════════
dir_D="$(build_fixture merge "" 3)"
ts_D="$(make_pending_transcript "$dir_D")"
out_D="$(run_hook "$dir_D" "$ts_D")"
body_D=$(echo "$out_D" | grep -v '^__EXIT__')

if echo "$body_D" | grep -q '等待后台 sub-agent'; then
    pass "全阶段泛化: phase=merge + has_pending=true → stdout 含「等待后台 sub-agent」"
else
    fail "全阶段泛化: phase=merge + has_pending=true 时应触发 §7.5，实际 stdout: ${body_D}"
fi

if ! echo "$body_D" | grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    pass "全阶段泛化: phase=merge + has_pending=true → stdout 不含 block（不重蹈 merge 死循环）"
else
    fail "全阶段泛化: phase=merge + has_pending=true 时不应含 block，历史 bug 是 merge 死循环根因。stdout: ${body_D}"
fi

rm -rf "$dir_D"

# ════════════════════════════════════════════════════════════════════════════
# 汇总
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "─────────────────────────────────────────────────────────────"
echo "R-silent-wait 汇总: PASS=${PASS_COUNT}  FAIL=${FAIL_COUNT}"
echo "─────────────────────────────────────────────────────────────"

if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 1
fi
exit 0
