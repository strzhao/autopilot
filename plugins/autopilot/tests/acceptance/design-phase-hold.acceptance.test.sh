#!/usr/bin/env bash
# R-design-hold: standard design 模式放行契约（§7.6 修复验收）
#
# 红队测试 — 仅基于设计文档与验收场景编写，不读取 §7.6 实现代码。
#
# 修复目标（2026-05-31 bug）：
#   standard design 模式（fast_mode≠true ∧ auto_approve≠true）下 AI 结束回合等用户后，
#   stop-hook 不应重新注入"继续 design"的 block decision 把流程带跑，
#   而应放行（输出 systemMessage、不带 decision:block）把控制权交回用户。
#
# 验收契约 C1（§7.6）：
#   phase=design ∧ auto_approve≠true ∧ fast_mode≠true ∧ gate="" ∧ 无 pending
#   → exit 0 ∧ stdout 不含 "decision":"block" ∧ stdout 含 "systemMessage"
#     ∧ iteration 不递增 ∧ phase 保持 design
#
# fast_mode/auto_approve 路径及 implement/qa 等阶段的自动推进行为保持不变。
#
# 测试场景（对应预注册谓词）：
#   场景1: phase=design, fast_mode=false, auto_approve=false, gate="", 无 pending
#          P1: exit_code==0  P2: not contains "decision":"block"
#          P3: iteration 不递增  P4: phase 仍==design  P5: contains "systemMessage"
#
#   场景2: phase=design, fast_mode=true → contains "decision":"block"（回归）
#   场景3: phase=design, auto_approve=true → contains "decision":"block"（回归）
#   场景4: phase=implement, fast_mode=false, auto_approve=false, 无 pending
#          → contains block；iteration_after == iteration_before+1；phase 仍==implement
#
#   场景5: phase=qa → contains block；phase=auto-fix → contains block（回归）
#   场景6: phase=design + pending sub-agent → not-contains block ∧ exit 0（§7.5 优先）
#   场景7: fast_mode 字段缺失 → not-contains block；auto_approve 字段缺失 → 同理
#
# no-op mutation 保护：若 §7.6 被删，场景1 P2/P5 必须 FAIL（输出 block、不输出 systemMessage）。
#
# 运行方式：bash plugins/autopilot/tests/acceptance/design-phase-hold.acceptance.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
STOP_HOOK="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"

# ── 计数器 ──────────────────────────────────────────────────────────────────
PASS_COUNT=0
FAIL_COUNT=0

fail() {
    echo "[FAIL] R-design-hold: $1" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

pass() {
    echo "[PASS] R-design-hold: $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

# 前置：stop-hook.sh 必须存在
[[ -f "$STOP_HOOK" ]] || { echo "[FATAL] R-design-hold: stop-hook.sh 不存在: $STOP_HOOK" >&2; exit 1; }
# 前置：jq 必须可用（transcript 构造需要）
command -v jq >/dev/null || { echo "[FATAL] R-design-hold: 需要 jq 但未安装" >&2; exit 1; }

# ── 全局临时目录（EXIT trap 清理） ──────────────────────────────────────────
TMPDIR_BASE=$(mktemp -d -t autopilot-design-hold-XXXXXX)
trap 'rm -rf "$TMPDIR_BASE"' EXIT

# ── 辅助函数 ────────────────────────────────────────────────────────────────

# build_fixture <phase> <gate> <fast_mode_val> <auto_approve_val> [iteration]
#   构造含 git repo 的临时 fixture 目录，返回目录绝对路径（stdout）。
#   fast_mode_val / auto_approve_val 为 YAML 值（"true" / "false" / "" 表示字段缺失）
#   iteration 默认 5
build_fixture() {
    local phase="$1"
    local gate="$2"
    local fast_mode_val="$3"     # "true" / "false" / "MISSING"
    local auto_approve_val="$4"  # "true" / "false" / "MISSING"
    local iteration="${5:-5}"
    local design_doc="${6:-written}"   # "written"(审批点，实质设计文档) / "empty"(接力点，仅占位符)

    local dir
    dir="$(mktemp -d -t autopilot-design-hold-fix-XXXXXX)"

    # 初始化 git repo（stop-hook.sh 依赖 git rev-parse --show-toplevel）
    git -C "$dir" init -q
    git -C "$dir" config user.email "test@test.com"
    git -C "$dir" config user.name "Test"

    mkdir -p "$dir/.autopilot/runtime/requirements/test-task"
    echo "test-task" > "$dir/.autopilot/runtime/active.ptr"

    # 动态构造 YAML frontmatter，支持字段缺失
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
        # fast_mode 字段
        if [[ "$fast_mode_val" != "MISSING" ]]; then
            echo "fast_mode: ${fast_mode_val}"
        fi
        # auto_approve 字段
        if [[ "$auto_approve_val" != "MISSING" ]]; then
            echo "auto_approve: ${auto_approve_val}"
        fi
        echo "knowledge_extracted: \"\""
        echo "task_dir: \"${dir}/.autopilot/runtime/requirements/test-task\""
        echo "session_id: design-hold-sess"
        echo "started_at: \"2026-05-31T00:00:00Z\""
        echo "contract_required: false"
        echo "html_review: false"
        echo "---"
        echo ""
        echo "## 目标"
        echo "design-phase-hold 测试 fixture"
        echo ""
        echo "## 设计文档"
        if [[ "$design_doc" == "written" ]]; then
            # 实质设计文档（审批点）：主 SKILL 接力写入后形态，design_doc_written → true
            echo "## Context"
            echo "实现用户登录功能，解决无认证安全问题。"
            echo ""
            echo "## 整体架构设计"
            echo "- 前端：登录表单 + token 存储"
            echo "- 后端：/api/login 端点 + JWT 签发"
            echo ""
            echo "## 任务分解"
            echo "1. 后端登录端点  2. 前端表单  3. token 拦截器"
        else
            # 仅占位符（接力点）：brainstorm 刚完成、主 SKILL 未接力，design_doc_written → false
            echo "(待 design 阶段填充)"
        fi
        echo ""
        echo "## 实现计划"
        echo "(待 design 阶段填充)"
    } > "$dir/.autopilot/runtime/requirements/test-task/state.md"

    echo "$dir"
}

# make_empty_transcript <dir>
#   写一个最小合法 JSONL transcript（无任何 Agent tool_use → 无 pending sub-agent）。
#   返回文件绝对路径（stdout）。
make_empty_transcript() {
    local dir="$1"
    local f="$dir/transcript.jsonl"
    # 一条普通用户消息，不含 Agent tool_use / async_launched
    jq -nc '{"type":"user","isSidechain":false,"message":{"role":"user","content":[{"type":"text","text":"start"}]}}' > "$f"
    echo "$f"
}

# make_pending_transcript <dir>
#   写含一个未完成同步 Agent tool_use 的 transcript（§7.5 会检测到 pending → 静默等待）。
make_pending_transcript() {
    local dir="$1"
    local f="$dir/transcript_pending.jsonl"
    # 主线程 Agent tool_use（isSidechain=false），无对应 tool_result → sync pending
    jq -nc '{"isSidechain":false,"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_design_001","name":"Agent","input":{"prompt":"explore","options":{}}}]}}' > "$f"
    echo "$f"
}

# run_hook <dir> <transcript_path>
#   以 dir 为 cwd 驱动 stop-hook.sh，stdin 传入 session_id=design-hold-sess。
#   输出：hook 的 stdout 行 + 最后一行 __EXIT__<code>
run_hook() {
    local dir="$1"
    local transcript_path="$2"
    local hook_input
    hook_input=$(jq -nc \
        --arg cwd "$dir" \
        --arg sid "design-hold-sess" \
        --arg tp "$transcript_path" \
        '{"cwd":$cwd,"session_id":$sid,"transcript_path":$tp}')
    (cd "$dir" && echo "$hook_input" | bash "$STOP_HOOK" 2>/dev/null; echo "__EXIT__$?")
}

# get_state_field <dir> <field>
#   从 fixture 的 state.md 提取 frontmatter 字段值。
get_state_field() {
    local dir="$1" field="$2"
    grep -E "^${field}:" \
        "$dir/.autopilot/runtime/requirements/test-task/state.md" \
        | head -1 \
        | sed -E "s/^${field}:[[:space:]]*\"?([^\"]*)\"?[[:space:]]*$/\1/"
}

# ──────────────────────────────────────────────────────────────────────────────
# 场景1（核心修复）：phase=design, fast_mode=false, auto_approve=false, gate="", 无 pending
# 谓词: P1 exit_code==0  P2 not-contains "decision":"block"
#       P3 iteration 不递增  P4 phase==design  P5 contains "systemMessage"
# ──────────────────────────────────────────────────────────────────────────────
dir_s1="$(build_fixture design "" false false 5)"
ts_s1="$(make_empty_transcript "$dir_s1")"
out_s1="$(run_hook "$dir_s1" "$ts_s1")"
body_s1=$(echo "$out_s1" | grep -v '^__EXIT__')
exit_s1=$(echo "$out_s1" | grep '^__EXIT__' | sed 's/__EXIT__//')

# P1: exit_code == 0
if [[ "$exit_s1" -eq 0 ]]; then
    pass "场景1 P1: exit_code==0（放行）"
else
    fail "场景1 P1: 期望 exit_code==0，实际 exit=$exit_s1 — §7.6 应 exit 0"
fi

# P2: stdout 不含 "decision":"block"
if ! echo "$body_s1" | grep -q '"decision"'; then
    pass "场景1 P2: stdout 不含 decision（放行，不重注入 block）"
elif ! echo "$body_s1" | grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    pass "场景1 P2: stdout 含 decision 但不是 block（放行）"
else
    fail "场景1 P2: stdout 含 \"decision\":\"block\" — §7.6 修复应消除此 block 注入。stdout: $body_s1"
fi

# P3: iteration 不递增（iteration_after == 5）
iter_after_s1=$(get_state_field "$dir_s1" iteration)
if [[ "$iter_after_s1" == "5" ]]; then
    pass "场景1 P3: iteration 未递增（仍为 5）"
else
    fail "场景1 P3: iteration 应保持 5，实际: $iter_after_s1 — 放行路径不应递增 iteration"
fi

# P4: phase 执行后仍 == design
phase_after_s1=$(get_state_field "$dir_s1" phase)
if [[ "$phase_after_s1" == "design" ]]; then
    pass "场景1 P4: phase 仍为 design"
else
    fail "场景1 P4: phase 应保持 design，实际: $phase_after_s1"
fi

# P5: stdout 含 §7.6 专属的 systemMessage 暂停说明
#   ⚠️ 不能只 grep '"systemMessage"' —— §9 的 block JSON 本身也含 systemMessage 键
#   （值 "autopilot iteration N | phase: design"）。删 §7.6 后 standard design 落到 §9
#   仍会输出含 systemMessage 的 block JSON → 弱断言无法 kill mutation。
#   故断言 §7.6 专属标志 "用户尚未确认"（§9 systemMessage 绝不含），双条件 AND，确保 kill no-op。
if echo "$body_s1" | grep -q '"systemMessage"' && echo "$body_s1" | grep -q '用户尚未确认'; then
    pass "场景1 P5: stdout 含 §7.6 专属 systemMessage 暂停说明（含「用户尚未确认」）"
else
    fail "场景1 P5: stdout 未含 §7.6 专属暂停说明（应含 systemMessage 键 + 「用户尚未确认」标志，§9 block 的 systemMessage 不含此标志）。stdout: $body_s1"
fi
rm -rf "$dir_s1"

# ──────────────────────────────────────────────────────────────────────────────
# 场景2（回归）：phase=design, fast_mode=true → contains "decision":"block"
# fast_mode 路径保持自动推进（§9 design fast_mode 分支）
# ──────────────────────────────────────────────────────────────────────────────
dir_s2="$(build_fixture design "" true false 5)"
ts_s2="$(make_empty_transcript "$dir_s2")"
out_s2="$(run_hook "$dir_s2" "$ts_s2")"
body_s2=$(echo "$out_s2" | grep -v '^__EXIT__')

if echo "$body_s2" | grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    pass "场景2: phase=design + fast_mode=true → 仍输出 block（自动推进保持）"
else
    fail "场景2: phase=design + fast_mode=true 应输出 block，实际 stdout: $body_s2"
fi
rm -rf "$dir_s2"

# ──────────────────────────────────────────────────────────────────────────────
# 场景3（回归）：phase=design, auto_approve=true → contains "decision":"block"
# auto_approve 路径保持自动推进（§9 design auto_approve 分支）
# ──────────────────────────────────────────────────────────────────────────────
dir_s3="$(build_fixture design "" false true 5)"
ts_s3="$(make_empty_transcript "$dir_s3")"
out_s3="$(run_hook "$dir_s3" "$ts_s3")"
body_s3=$(echo "$out_s3" | grep -v '^__EXIT__')

if echo "$body_s3" | grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    pass "场景3: phase=design + auto_approve=true → 仍输出 block（auto-chain 保持）"
else
    fail "场景3: phase=design + auto_approve=true 应输出 block，实际 stdout: $body_s3"
fi
rm -rf "$dir_s3"

# ──────────────────────────────────────────────────────────────────────────────
# 场景4（回归）：phase=implement, fast_mode=false, auto_approve=false, 无 pending
# → contains block；iteration_after == iteration_before+1；phase 仍==implement
# ──────────────────────────────────────────────────────────────────────────────
dir_s4="$(build_fixture implement "" false false 7)"
ts_s4="$(make_empty_transcript "$dir_s4")"
out_s4="$(run_hook "$dir_s4" "$ts_s4")"
body_s4=$(echo "$out_s4" | grep -v '^__EXIT__')

if echo "$body_s4" | grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    pass "场景4: phase=implement + standard → 输出 block（自动推进保持）"
else
    fail "场景4: phase=implement + standard 应输出 block，实际 stdout: $body_s4"
fi

iter_after_s4=$(get_state_field "$dir_s4" iteration)
if [[ "$iter_after_s4" == "8" ]]; then
    pass "场景4: iteration 递增 7 → 8"
else
    fail "场景4: iteration 应由 7 递增为 8，实际: $iter_after_s4"
fi

phase_after_s4=$(get_state_field "$dir_s4" phase)
if [[ "$phase_after_s4" == "implement" ]]; then
    pass "场景4: phase 仍为 implement"
else
    fail "场景4: phase 应保持 implement，实际: $phase_after_s4"
fi
rm -rf "$dir_s4"

# ──────────────────────────────────────────────────────────────────────────────
# 场景5（回归）：phase=qa → contains block；phase=auto-fix → contains block
# ──────────────────────────────────────────────────────────────────────────────
dir_s5a="$(build_fixture qa "" false false 3)"
ts_s5a="$(make_empty_transcript "$dir_s5a")"
out_s5a="$(run_hook "$dir_s5a" "$ts_s5a")"
body_s5a=$(echo "$out_s5a" | grep -v '^__EXIT__')

if echo "$body_s5a" | grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    pass "场景5a: phase=qa + standard → 输出 block（qa 自动推进保持）"
else
    fail "场景5a: phase=qa + standard 应输出 block，实际 stdout: $body_s5a"
fi
rm -rf "$dir_s5a"

dir_s5b="$(build_fixture auto-fix "" false false 3)"
ts_s5b="$(make_empty_transcript "$dir_s5b")"
out_s5b="$(run_hook "$dir_s5b" "$ts_s5b")"
body_s5b=$(echo "$out_s5b" | grep -v '^__EXIT__')

if echo "$body_s5b" | grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    pass "场景5b: phase=auto-fix + standard → 输出 block（auto-fix 自动推进保持）"
else
    fail "场景5b: phase=auto-fix + standard 应输出 block，实际 stdout: $body_s5b"
fi
rm -rf "$dir_s5b"

# ──────────────────────────────────────────────────────────────────────────────
# 场景6（边界）：phase=design + transcript 含 pending sync sub-agent
# → §7.5 静默等待优先，not-contains block ∧ exit 0
# 注：§7.5 在 §7.6 之前检查，pending 时直接 exit 0（无 decision 也无 systemMessage）
# ──────────────────────────────────────────────────────────────────────────────
dir_s6="$(build_fixture design "" false false 5)"
ts_s6="$(make_pending_transcript "$dir_s6")"
out_s6="$(run_hook "$dir_s6" "$ts_s6")"
body_s6=$(echo "$out_s6" | grep -v '^__EXIT__')
exit_s6=$(echo "$out_s6" | grep '^__EXIT__' | sed 's/__EXIT__//')

# §7.5 静默等待：exit 0 且不输出 block
if [[ "$exit_s6" -eq 0 ]]; then
    pass "场景6: design + pending sub-agent → exit 0（§7.5 静默等待）"
else
    fail "场景6: design + pending sub-agent 期望 exit 0，实际 exit=$exit_s6"
fi

if ! echo "$body_s6" | grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    pass "场景6: stdout 不含 block（§7.5 优先于 §7.6，pending 时静默）"
else
    fail "场景6: stdout 含 block，§7.5 应在 §7.6 前拦截 pending 场景。stdout: $body_s6"
fi
rm -rf "$dir_s6"

# ──────────────────────────────────────────────────────────────────────────────
# 场景7（异常防御）：fast_mode 字段缺失 → 视为 false → 放行（not-contains block）
#                    auto_approve 字段缺失 → 同理 not-contains block
# §7.6 注释：缺失字段 get_field 返回空串，"" != "true" 恒真 → 缺失即按 false（fail-safe 朝放行）
# ──────────────────────────────────────────────────────────────────────────────

# 7a: fast_mode 字段缺失，auto_approve=false → 应放行
dir_s7a="$(build_fixture design "" MISSING false 5)"
ts_s7a="$(make_empty_transcript "$dir_s7a")"
out_s7a="$(run_hook "$dir_s7a" "$ts_s7a")"
body_s7a=$(echo "$out_s7a" | grep -v '^__EXIT__')
exit_s7a=$(echo "$out_s7a" | grep '^__EXIT__' | sed 's/__EXIT__//')

if [[ "$exit_s7a" -eq 0 ]]; then
    pass "场景7a: fast_mode 字段缺失 → exit 0（缺失即 false，放行）"
else
    fail "场景7a: fast_mode 缺失时期望 exit 0，实际 exit=$exit_s7a"
fi

if ! echo "$body_s7a" | grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    pass "场景7a: fast_mode 字段缺失 → 不含 block（fail-safe 朝放行）"
else
    fail "场景7a: fast_mode 缺失时不应输出 block，实际 stdout: $body_s7a"
fi
rm -rf "$dir_s7a"

# 7b: auto_approve 字段缺失，fast_mode=false → 应放行
dir_s7b="$(build_fixture design "" false MISSING 5)"
ts_s7b="$(make_empty_transcript "$dir_s7b")"
out_s7b="$(run_hook "$dir_s7b" "$ts_s7b")"
body_s7b=$(echo "$out_s7b" | grep -v '^__EXIT__')
exit_s7b=$(echo "$out_s7b" | grep '^__EXIT__' | sed 's/__EXIT__//')

if [[ "$exit_s7b" -eq 0 ]]; then
    pass "场景7b: auto_approve 字段缺失 → exit 0（缺失即 false，放行）"
else
    fail "场景7b: auto_approve 缺失时期望 exit 0，实际 exit=$exit_s7b"
fi

if ! echo "$body_s7b" | grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    pass "场景7b: auto_approve 字段缺失 → 不含 block（fail-safe 朝放行）"
else
    fail "场景7b: auto_approve 缺失时不应输出 block，实际 stdout: $body_s7b"
fi
rm -rf "$dir_s7b"

# 7c: 两个字段都缺失 → 视为双 false → 应放行
dir_s7c="$(build_fixture design "" MISSING MISSING 5)"
ts_s7c="$(make_empty_transcript "$dir_s7c")"
out_s7c="$(run_hook "$dir_s7c" "$ts_s7c")"
body_s7c=$(echo "$out_s7c" | grep -v '^__EXIT__')
exit_s7c=$(echo "$out_s7c" | grep '^__EXIT__' | sed 's/__EXIT__//')

if [[ "$exit_s7c" -eq 0 ]]; then
    pass "场景7c: fast_mode+auto_approve 均缺失 → exit 0（双 false 放行）"
else
    fail "场景7c: 两字段均缺失期望 exit 0，实际 exit=$exit_s7c"
fi

if ! echo "$body_s7c" | grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    pass "场景7c: 两字段均缺失 → 不含 block"
else
    fail "场景7c: 两字段均缺失时不应输出 block，实际 stdout: $body_s7c"
fi
rm -rf "$dir_s7c"

# ──────────────────────────────────────────────────────────────────────────────
# 场景8（v3.43.1 新增·接力点）：phase=design, standard, 设计文档仅占位符（empty）
# → §7.6 design_doc_written=false 不命中 → fall through §9 输出 block（自动唤醒接力）
# 验证 brainstorm 完成后不被误停、自动接力写设计文档（v3.43.0 回归 bug 的修复契约）。
# 与场景1（审批点，设计文档已落盘 → 放行）互为反例，共同锁定 design_doc_written 边界。
# 谓词: P1 contains "decision":"block"  P2 iteration 递增 5→6  P3 phase==design
# ──────────────────────────────────────────────────────────────────────────────
dir_s8="$(build_fixture design "" false false 5 empty)"
ts_s8="$(make_empty_transcript "$dir_s8")"
out_s8="$(run_hook "$dir_s8" "$ts_s8")"
body_s8=$(echo "$out_s8" | grep -v '^__EXIT__')

# P1: 输出 block（§9 接力，非放行）。kill-mutation：若 §7.6 退化为一刀切放行（删 design_doc_written
# 前置），接力点也会被放行 → 此处不含 block → FAIL，守住"接力点必须自动推进"契约。
if echo "$body_s8" | grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    pass "场景8: design + 设计文档空（接力点）→ 输出 block（§9 自动唤醒接力）"
else
    fail "场景8: 接力点应 fall through §9 输出 block（brainstorm 后自动接力）。stdout: $body_s8"
fi

# P2: iteration 递增（§9 路径递增，与放行路径的"冻结"区分）
iter_after_s8=$(get_state_field "$dir_s8" iteration)
if [[ "$iter_after_s8" == "6" ]]; then
    pass "场景8: iteration 递增 5 → 6（接力点走 §9，非放行冻结）"
else
    fail "场景8: 接力点 iteration 应递增为 6，实际: $iter_after_s8"
fi

# P3: phase 仍 design
phase_after_s8=$(get_state_field "$dir_s8" phase)
if [[ "$phase_after_s8" == "design" ]]; then
    pass "场景8: phase 仍为 design（接力仍在 design 阶段）"
else
    fail "场景8: phase 应保持 design，实际: $phase_after_s8"
fi
rm -rf "$dir_s8"

# ──────────────────────────────────────────────────────────────────────────────
# 汇总
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────────────────────────"
echo "R-design-hold 汇总: PASS=${PASS_COUNT}  FAIL=${FAIL_COUNT}"
echo "─────────────────────────────────────────────────────────────"

if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 1
fi
exit 0
