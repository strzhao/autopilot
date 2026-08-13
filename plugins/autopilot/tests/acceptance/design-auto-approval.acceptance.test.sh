#!/usr/bin/env bash
# acceptance test: design 步骤 4 AI 判定低风险设 auto_approve=true + phase=implement 后，
# stop-hook 正确路由 §9 implement 分支（不重注入 design / 不触发 §5.5）。
#
# 背景：v3.62.0 让 AI 在 standard 单任务 design 步骤 4 据低风险判断设 auto_approve=true
# （跳过 design 审批 + QA gate）。本测试锁定 design 步骤 4 后态（phase=implement ∧ auto_approve=true）
# 的 stop-hook 路由契约：
#   AC-1：phase=implement + auto_approve=true（design 步骤4 后态）→ §9 implement 分支 block JSON，
#         prompt 含 implement 指引，不含"写设计文档"（不重注入 design auto_approve 分支）
#   AC-2：phase 保持 implement（§5.5 不触发，因 phase≠qa；不被误转 merge）
#   AC-3：回归守护——phase=design + auto_approve=true + design_doc_written → §9 design auto_approve
#         分支 block（auto-chain 既有路径不被 AI 设 auto_approve 破坏）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
STOP_HOOK="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"

fail() { echo "[FAIL] $1" >&2; exit 1; }
pass() { echo "[PASS] $1"; }

[[ -f "$STOP_HOOK" ]] || fail "stop-hook.sh 不存在: $STOP_HOOK"

# fixture helper: phase auto_approve [with_design_doc]
# with_design=1 时写 ## 设计文档 段（触发 design_doc_written）
build_fixture() {
    local phase="$1" auto_approve="$2" with_design="${3:-0}"
    local dir
    dir="$(mktemp -d -t autopilot-design-auto-XXXXXX)"
    mkdir -p "$dir/.autopilot/runtime/requirements/test-task"
    echo "test-task" > "$dir/.autopilot/runtime/active.ptr"
    cat > "$dir/.autopilot/runtime/requirements/test-task/state.md" <<EOF
---
active: true
phase: "$phase"
gate: ""
iteration: 3
max_iterations: 30
max_retries: 3
retry_count: 0
mode: "single"
plan_mode: ""
fast_mode: ""
brief_file: ""
next_task: ""
auto_approve: $auto_approve
knowledge_extracted: ""
task_dir: "$dir/.autopilot/runtime/requirements/test-task"
session_id: dasess
started_at: "2026-08-14T00:00:00Z"
contract_required: false
html_review: false
---

## 目标
test fixture
EOF
    if [[ "$with_design" == "1" ]]; then
        printf '\n## 设计文档\ndesign content for design_doc_written\n' \
            >> "$dir/.autopilot/runtime/requirements/test-task/state.md"
    fi
    echo "$dir"
}

run_hook() {
    local dir="$1"
    local hook_input='{"session_id":"dasess","transcript_path":"/tmp/none"}'
    (cd "$dir" && echo "$hook_input" | bash "$STOP_HOOK" 2>/dev/null; echo "__EXIT__$?")
}

get_state_field() {
    local dir="$1" field="$2"
    grep -E "^${field}:" "$dir/.autopilot/runtime/requirements/test-task/state.md" \
        | head -1 | sed -E "s/^${field}:[[:space:]]*\"?([^\"]*)\"?$/\1/"
}

# ─────────────────────────────────────────────────────────────────────
# AC-1: phase=implement + auto_approve=true → §9 implement 分支
# ─────────────────────────────────────────────────────────────────────
dir1="$(build_fixture implement true)"
out1="$(run_hook "$dir1")"
body1=$(echo "$out1" | grep -v '__EXIT__')

if ! echo "$body1" | grep -q '"decision":[[:space:]]*"block"'; then
    fail "AC-1: phase=implement+auto_approve=true 未输出 block JSON。stdout: $body1"
fi
if ! echo "$body1" | grep -q "implement"; then
    fail "AC-1: prompt 不含 implement 指引（应走 §9 implement 分支）。stdout: $body1"
fi
if echo "$body1" | grep -q "写设计文档"; then
    fail "AC-1: prompt 含'写设计文档'（误走 design auto_approve 分支，应走 implement）。stdout: $body1"
fi
pass "AC-1: phase=implement+auto_approve=true → §9 implement 分支（不重注入 design）"

# ─────────────────────────────────────────────────────────────────────
# AC-2: phase 保持 implement（§5.5 不触发，因 phase≠qa）
# ─────────────────────────────────────────────────────────────────────
phase_after1=$(get_state_field "$dir1" phase)
if [[ "$phase_after1" != "implement" ]]; then
    fail "AC-2: phase 被改动（应保持 implement，§5.5 因 phase≠qa 不触发），实际: $phase_after1"
fi
pass "AC-2: phase=implement 保持不变（§5.5 不触发，不被误转 merge）"
rm -rf "$dir1"

# ─────────────────────────────────────────────────────────────────────
# AC-3: 回归守护——phase=design + auto_approve=true + design_doc_written → §9 design 分支
# ─────────────────────────────────────────────────────────────────────
dir3="$(build_fixture design true 1)"
out3="$(run_hook "$dir3")"
body3=$(echo "$out3" | grep -v '__EXIT__')

if ! echo "$body3" | grep -q '"decision":[[:space:]]*"block"'; then
    fail "AC-3: phase=design+auto_approve=true+design_doc 未输出 block JSON（§9 design 分支应推进）。stdout: $body3"
fi
# §7.6 不拦截（auto_approve=true），§9 design auto_approve 分支 prompt 含"直接写设计文档"
if ! echo "$body3" | grep -q "写设计文档"; then
    fail "AC-3: phase=design+auto_approve=true 应走 design auto_approve 分支（含'写设计文档'）。stdout: $body3"
fi
pass "AC-3: phase=design+auto_approve=true+design_doc → §9 design auto_approve 分支（auto-chain 既有路径不破坏）"
rm -rf "$dir3"

echo "[OK ] design-auto-approval — 3 条断言全部通过"
exit 0
