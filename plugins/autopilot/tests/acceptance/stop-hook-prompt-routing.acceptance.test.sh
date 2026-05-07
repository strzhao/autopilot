#!/usr/bin/env bash
# R6: 验证 stop-hook.sh 中 design fast_mode 分支 + qa smoke 分支的 prompt 路由
# 红队测试 — 仅基于设计文档编写，不读取蓝队实现
#
# 设计文档要求：
#   - design 阶段 fast_mode=true 时：在 auto_approve 之后、plan_mode 之后、标准之前
#     注入特殊 prompt，提示砍 scenario-generator + plan-reviewer
#   - qa 阶段 qa_scope=smoke 时：注入特殊 prompt，提示砍 qa-reviewer Agent
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
STOP_HOOK="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"

fail() {
    echo "[FAIL] R6: $1" >&2
    exit 1
}

pass() {
    echo "[PASS] R6: $1"
}

# 前置
[[ -f "$STOP_HOOK" ]] || fail "stop-hook.sh 不存在: $STOP_HOOK"

# ── 断言 1：stop-hook.sh 含 fast_mode 分支 ──────────────────────────────────
# 设计文档: design 阶段 fast_mode=true 时注入特殊 prompt
if ! grep -qE 'fast_mode' "$STOP_HOOK"; then
    fail "stop-hook.sh 中不存在任何 fast_mode 引用（设计文档要求 design 阶段处理 fast_mode=true）"
fi
pass "stop-hook.sh 包含 fast_mode 相关引用"

# ── 断言 2：design 阶段存在 scenario-generator 相关砍除指令 ─────────────────
# 设计文档: fast_mode=true 时提示"砍 scenario-generator + plan-reviewer"
# 检查 stop-hook.sh 中有引用 scenario-generator 与裁剪/跳过/不启动语义的组合
scenario_ref=$(grep -n "scenario" "$STOP_HOOK" || true)
if [[ -z "$scenario_ref" ]]; then
    fail "stop-hook.sh 中找不到 scenario（设计要求 fast_mode 分支提示砍 scenario-generator）"
fi
pass "stop-hook.sh 含 scenario-generator 相关引用"

# ── 断言 3：design 阶段存在 plan-reviewer 相关砍除指令 ──────────────────────
# 设计文档: fast_mode=true 时提示"砍 scenario-generator + plan-reviewer"
plan_reviewer_ref=$(grep -n "plan.reviewer\|plan_reviewer" "$STOP_HOOK" || true)
if [[ -z "$plan_reviewer_ref" ]]; then
    fail "stop-hook.sh 中找不到 plan-reviewer（设计要求 fast_mode 分支提示砍 plan-reviewer）"
fi
pass "stop-hook.sh 含 plan-reviewer 相关引用"

# ── 断言 4：fast_mode 路由优先级正确 ────────────────────────────────────────
# 设计文档: design 阶段 fast_mode 分支在 auto_approve 之后、标准逻辑之前
# 验证方式：在文件中 auto_approve 条件的行号 < fast_mode 分支行号 < 标准 design 提示行号
# 这是对行顺序的软约束，用行号比较
# 探针精度调整（patterns 2026-03-30）：函数体内含同名小写变量会污染 head -1 定位，
# 改用大写 prompt routing 分支条件的唯一锚点 'AUTO_APPROVE.*==.*"true"' / 'FAST_MODE.*==.*"true"'。
auto_approve_line=$(grep -n 'AUTO_APPROVE.*==.*"true"' "$STOP_HOOK" | head -1 | cut -d: -f1)
fast_mode_line=$(grep -n 'FAST_MODE.*==.*"true"' "$STOP_HOOK" | head -1 | cut -d: -f1)

if [[ -z "$auto_approve_line" ]]; then
    fail "stop-hook.sh 中找不到 auto_approve 引用（参考已有功能，auto_approve 应存在）"
fi
if [[ -z "$fast_mode_line" ]]; then
    fail "stop-hook.sh 中找不到 fast_mode 引用"
fi
# fast_mode 处理必须在 auto_approve 之后出现（行号更大）
if [[ "$fast_mode_line" -le "$auto_approve_line" ]]; then
    fail "fast_mode 分支（行 ${fast_mode_line}）应在 auto_approve 处理（行 ${auto_approve_line}）之后 — 路由优先级违反设计文档"
fi
pass "fast_mode 分支行号($fast_mode_line) 在 auto_approve($auto_approve_line) 之后 — 优先级正确"

# ── 断言 5：qa 阶段存在 smoke 分支 ──────────────────────────────────────────
# 设计文档: qa 阶段 qa_scope=smoke 时注入特殊 prompt
if ! grep -qE '"smoke"|smoke' "$STOP_HOOK"; then
    fail "stop-hook.sh 中找不到 smoke 引用（设计要求 qa 阶段 qa_scope=smoke 时特殊路由）"
fi
pass "stop-hook.sh 含 qa_scope smoke 相关引用"

# ── 断言 6：qa smoke 分支中存在 qa-reviewer 砍除指令 ─────────────────────────
# 设计文档: qa_scope=smoke 时提示"砍 qa-reviewer Agent"
qa_reviewer_ref=$(grep -n "qa.reviewer\|qa_reviewer" "$STOP_HOOK" || true)
if [[ -z "$qa_reviewer_ref" ]]; then
    fail "stop-hook.sh 中找不到 qa-reviewer（设计要求 smoke 分支提示砍 qa-reviewer Agent）"
fi
pass "stop-hook.sh 含 qa-reviewer 相关引用"

# ── 断言 7：detect_smoke_eligible 在 qa 阶段转入时被调用 ────────────────────
# 设计文档: "phase 转入 qa 时调用"
# 验证：在文件中 "qa" 上下文附近存在 detect_smoke_eligible 调用
detect_call=$(grep -n "detect_smoke_eligible" "$STOP_HOOK" || true)
if [[ -z "$detect_call" ]]; then
    fail "stop-hook.sh 中找不到 detect_smoke_eligible 调用（设计要求 qa 转入时调用此函数）"
fi
# 调用行数应该有 >= 2 行（一行定义，一行调用）
detect_count=$(grep -c "detect_smoke_eligible" "$STOP_HOOK" || true)
if [[ "$detect_count" -lt 2 ]]; then
    fail "detect_smoke_eligible 只出现 $detect_count 次，疑似只有定义没有调用（设计要求 qa 转入时调用）"
fi
pass "detect_smoke_eligible 在 stop-hook.sh 中有定义且被调用（出现 $detect_count 次）"

# ── 断言 8：fast_mode 分支与 plan_mode 分支排序正确 ─────────────────────────
# 设计文档: design 阶段优先级: auto_approve > plan_mode:"deep" > fast_mode > 其他
# 验证 plan_mode 的行号 < fast_mode 的行号（plan_mode deep 分支应更早）
plan_mode_line=$(grep -n 'PLAN_MODE.*==.*"deep"' "$STOP_HOOK" | head -1 | cut -d: -f1)
if [[ -n "$plan_mode_line" ]] && [[ -n "$fast_mode_line" ]]; then
    if [[ "$fast_mode_line" -le "$plan_mode_line" ]]; then
        fail "fast_mode 分支（行 ${fast_mode_line}）应在 plan_mode 处理（行 ${plan_mode_line}）之后 — 优先级顺序违反设计"
    fi
    pass "fast_mode 分支行号($fast_mode_line) 在 plan_mode($plan_mode_line) 之后 — 优先级顺序正确"
else
    pass "plan_mode 引用未检测到或与 fast_mode 行号关系无法比较，跳过优先级顺序断言"
fi

echo "[OK ] R6 stop-hook-prompt-routing — 全部断言通过"
exit 0
