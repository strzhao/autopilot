#!/usr/bin/env bash
# R4: 验证 setup.sh --fast flag 解析 + 默认值 + 帮助文本
# 红队测试 — 仅基于设计文档编写，不读取蓝队实现
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
SETUP_SH="$REPO_ROOT/plugins/autopilot/scripts/setup.sh"
LIB_SH="$REPO_ROOT/plugins/autopilot/scripts/lib.sh"

fail() {
    echo "[FAIL] R4: $1" >&2
    exit 1
}

pass() {
    echo "[PASS] R4: $1"
}

# 前置：setup.sh 必须存在
[[ -f "$SETUP_SH" ]] || fail "setup.sh 不存在: $SETUP_SH"
[[ -f "$LIB_SH" ]]   || fail "lib.sh 不存在: $LIB_SH"

# ── 断言 1：setup.sh 中存在 --fast flag 的解析逻辑 ────────────────────────────
# 设计文档: "setup.sh 新增 --fast flag（与 --deep、--project 同 pattern）"
# 只要存在 --fast 相关的条件分支/case 即可（弱断言，不读函数体细节）
if ! grep -qE '"--fast"|--fast\)' "$SETUP_SH"; then
    fail "setup.sh 中找不到 --fast flag 解析（期望存在 \"--fast\" 或 --fast) 分支）"
fi
pass "--fast flag 解析逻辑存在于 setup.sh"

# ── 断言 2：setup.sh 中存在 fast_mode 字段写入逻辑 ──────────────────────────
# 设计文档: "setup.sh 创建 fast_mode: true/false frontmatter 字段"
if ! grep -qE 'fast_mode' "$SETUP_SH"; then
    fail "setup.sh 中找不到 fast_mode 字段写入（设计文档要求在 frontmatter 中创建该字段）"
fi
pass "fast_mode 字段写入逻辑存在于 setup.sh"

# ── 断言 3：帮助文本包含 --fast ──────────────────────────────────────────────
# 设计文档: "帮助文本（/autopilot --help）输出新增 --fast 行"
# 策略：grep --fast 在 setup.sh 的帮助文本相关上下文中出现（不依赖函数名，只检测字符串存在）
# setup.sh 帮助通常含 "Usage" 或 "usage" 或 "--help" 附近有 flag 描述
help_context=$(grep -n "\-\-fast" "$SETUP_SH" || true)
if [[ -z "$help_context" ]]; then
    fail "--fast 未出现在 setup.sh 中，帮助文本行无法满足（应至少出现一次 --fast）"
fi
# 进一步验证 --fast 不只用于解析，还出现在说明文本区域（帮助文字通常含 echo/cat 附近）
# 使用宽松断言：只要 --fast 总出现次数 >= 2（解析1次 + 帮助描述1次）
fast_count=$(grep -c "\-\-fast" "$SETUP_SH" || true)
if [[ "$fast_count" -lt 2 ]]; then
    fail "--fast 在 setup.sh 中只出现 $fast_count 次，帮助文本可能未包含（设计要求帮助行新增 --fast）"
fi
pass "帮助文本包含 --fast（--fast 在 setup.sh 出现 $fast_count 次）"

# ── 断言 4：fast_mode 默认值为 false ────────────────────────────────────────
# 设计文档: "新增 fast_mode: false（默认 false）"
# 检验 setup.sh 中存在 fast_mode: false 或 fast_mode=false 形式的默认初始化
if ! grep -qE 'fast_mode[: =]+false' "$SETUP_SH"; then
    fail "setup.sh 中找不到 fast_mode 的默认值 false（设计文档要求默认 false）"
fi
pass "fast_mode 默认值为 false"

# ── 断言 5：PHASE_FLOW 中存在 fast_mode 特化展示 ────────────────────────────
# 设计文档: "启动时 PHASE_FLOW 显示中，fast_mode 时显示 design (fast) → ... → qa (smoke)"
# 检查存在 "(fast)" 或 "fast" 与 "smoke" 联合展示的逻辑
if ! grep -qE '\(fast\)|fast.*smoke|design.*fast' "$SETUP_SH"; then
    fail "setup.sh 中找不到 PHASE_FLOW fast_mode 特化展示（期望存在 design (fast) 或类似模式）"
fi
pass "PHASE_FLOW 包含 fast_mode 特化展示（含 'fast' 标识）"

# ── 断言 6：/autopilot status 输出应含 fast_mode 字段 ──────────────────────
# 设计文档: "/autopilot status 输出含 fast_mode 字段（非默认值时）"
# 验证 setup.sh 或 stop-hook.sh 中有打印 fast_mode 的逻辑（status 功能通常在 setup.sh 中实现）
STOP_HOOK="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"
status_has_fast=0
if grep -qE 'fast_mode' "$SETUP_SH"; then
    # 已在断言2确认，再检查其是否出现在 status 输出相关代码中
    if grep -A5 -B5 'status' "$SETUP_SH" | grep -qE 'fast_mode'; then
        status_has_fast=1
    fi
fi
# stop-hook.sh 也可能承担 status 输出
if [[ $status_has_fast -eq 0 ]] && [[ -f "$STOP_HOOK" ]]; then
    if grep -qE 'fast_mode' "$STOP_HOOK"; then
        status_has_fast=1
    fi
fi
if [[ $status_has_fast -eq 0 ]]; then
    fail "setup.sh 和 stop-hook.sh 中均未检测到 fast_mode 相关逻辑（/autopilot status 应能显示该字段）"
fi
pass "fast_mode 字段在 setup.sh/stop-hook.sh 中有相关处理（可被 status 输出使用）"

echo "[OK ] R4 setup-fast-flag — 全部断言通过"
exit 0
