#!/usr/bin/env bash
# R1: 验证 stop-hook.sh 中 compress_qa_report 函数行为
# 红队测试 — 仅基于设计文档编写，不依赖蓝队实现
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
STOP_HOOK="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"

fail() {
    echo "[FAIL] R1: $1" >&2
    exit 1
}

pass() {
    echo "[PASS] R1: $1"
}

# 前置：stop-hook.sh 必须存在
[[ -f "$STOP_HOOK" ]] || fail "stop-hook.sh 不存在: $STOP_HOOK"

# 创建 mock state.md
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
STATE_FILE="$TMP_DIR/state.md"

cat > "$STATE_FILE" <<'EOF'
---
active: true
phase: qa
iteration: 3
goal: 测试目标
worktree: /tmp/test-worktree
created_at: 2026-05-07T00:00:00Z
updated_at: 2026-05-07T03:00:00Z
---

## 设计文档

设计内容占位。

## 实现计划

实现计划占位。

## 红队验收测试

红队测试占位。

## QA 报告

### 轮次 1 (2026-05-07T01:00:00Z) — ❌ 失败

- 问题点 A：缺失参数校验
- 问题点 B：未覆盖错误分支
- 详细日志若干行
- 多行内容确保压缩前体积可观

### 轮次 2 (2026-05-07T02:00:00Z) — ❌ 失败

- 问题点 C：边界条件遗漏
- 问题点 D：与设计稿不一致
- 多行内容
- 更多细节描述

### 轮次 3 (2026-05-07T03:00:00Z) — ✅ 通过

- 所有问题已修复
- ROUND3_UNIQUE_MARKER_KEEP_ME
- 详细审查报告
- 这一轮必须完整保留

## 变更日志

CHANGELOG_UNIQUE_MARKER_DO_NOT_TOUCH

- 2026-05-07: 初始化
EOF

# 备份原文件用于幂等性比较
cp "$STATE_FILE" "$STATE_FILE.before"

# 调用 compress_qa_report — 用 subshell 隔离，避免 stop-hook.sh 顶层 main 污染
# 策略：尝试 source 方式，但通过环境变量阻止 main 执行
# 大多数 hook 脚本会判断 BASH_SOURCE[0] == $0 来决定是否运行 main
# 我们采用 subshell + 函数提取的双重保护

invoke_compress() {
    local target="$1"
    # 尝试 1：直接 source（依赖 stop-hook.sh 防御性写法）
    bash -c "
        # 阻止常见的入口检查
        export AUTOPILOT_DISABLE_MAIN=1
        export AUTOPILOT_TEST_MODE=1
        # 防止 stop-hook 读取 stdin 阻塞
        exec </dev/null
        # source 时若顶层 main 执行了我们也无所谓 — 它会 fail 但函数定义已加载
        source '$STOP_HOOK' 2>/dev/null || true
        if declare -F compress_qa_report >/dev/null; then
            compress_qa_report '$target'
            exit \$?
        fi
        # 回退：用 awk 提取函数体单独执行
        awk '
            /^[[:space:]]*compress_qa_report[[:space:]]*\(\)[[:space:]]*\{/ { in_fn=1; depth=1; print; next }
            in_fn {
                print
                # 简单括号计数（不完美但够用于 bash 函数）
                n=gsub(/\{/, \"&\"); depth+=n
                n=gsub(/\}/, \"&\"); depth-=n
                if (depth<=0) { in_fn=0 }
            }
        ' '$STOP_HOOK' > '$TMP_DIR/fn_only.sh'
        if [[ -s '$TMP_DIR/fn_only.sh' ]]; then
            source '$TMP_DIR/fn_only.sh'
            if declare -F compress_qa_report >/dev/null; then
                compress_qa_report '$target'
                exit \$?
            fi
        fi
        echo 'compress_qa_report 函数未定义' >&2
        exit 99
    "
}

invoke_compress "$STATE_FILE"
rc=$?
if [[ $rc -eq 99 ]]; then
    fail "compress_qa_report 函数不存在于 stop-hook.sh 中（设计文档要求新增此函数）"
elif [[ $rc -ne 0 ]]; then
    fail "compress_qa_report 调用返回非零退出码 ($rc)"
fi

# 断言 1：变更日志 section 完整未变
grep -q "CHANGELOG_UNIQUE_MARKER_DO_NOT_TOUCH" "$STATE_FILE" \
    || fail "## 变更日志 section 被破坏 — CHANGELOG marker 丢失"
pass "变更日志 section 未受影响"

# 断言 2：轮次 3（最新）完整保留
grep -q "ROUND3_UNIQUE_MARKER_KEEP_ME" "$STATE_FILE" \
    || fail "最新一轮（轮次 3）的内容应完整保留，但 ROUND3 marker 不见了"
# 轮次 3 块应包含多行非空内容（避免 awk range pattern 起止重叠的坑，用状态机）
round3_body_lines=$(awk '
    /^### 轮次 3/ { in_block=1; next }
    in_block && /^### / { exit }
    in_block && /^## / { exit }
    in_block && NF>0 { count++ }
    END { print count+0 }
' "$STATE_FILE")
if [[ "$round3_body_lines" -lt 2 ]]; then
    fail "轮次 3 应完整保留多行正文内容，但只有 $round3_body_lines 行非空正文"
fi
pass "轮次 3（最新）完整保留（$round3_body_lines 行正文）"

# 断言 3：轮次 1 已被压缩为单行
# 找出形如 `### 轮次 1 ... — ... ❌` 的行，且该 header 之后到下一个 ### 之间应没有正文
round1_line_count=$(awk '
    /^### 轮次 1/ { in_block=1; count=0; next }
    in_block && /^### / { exit }
    in_block && /^## / { exit }
    in_block && NF>0 { count++ }
    END { print count+0 }
' "$STATE_FILE")
# 压缩后：除了 header 自身那一行外，块内不应再有非空内容行
if [[ "$round1_line_count" -gt 0 ]]; then
    fail "轮次 1 应被压缩为单行 header（无正文），但仍有 $round1_line_count 行内容"
fi
# header 必须保留时间戳与状态标记（❌）
grep -qE "^### 轮次 1.*2026-05-07T01:00:00Z.*❌" "$STATE_FILE" \
    || fail "轮次 1 压缩后的单行应保留时间戳和 ❌ 状态标记"
pass "轮次 1 已压缩为单行"

# 断言 4：轮次 2 已被压缩为单行
round2_line_count=$(awk '
    /^### 轮次 2/ { in_block=1; count=0; next }
    in_block && /^### / { exit }
    in_block && /^## / { exit }
    in_block && NF>0 { count++ }
    END { print count+0 }
' "$STATE_FILE")
if [[ "$round2_line_count" -gt 0 ]]; then
    fail "轮次 2 应被压缩为单行 header，但仍有 $round2_line_count 行内容"
fi
grep -qE "^### 轮次 2.*2026-05-07T02:00:00Z.*❌" "$STATE_FILE" \
    || fail "轮次 2 压缩后的单行应保留时间戳和 ❌ 状态标记"
pass "轮次 2 已压缩为单行"

# 断言 5：旧的失败问题点正文（轮次 1/2 的 bullet）已被清除
if grep -q "问题点 A：缺失参数校验" "$STATE_FILE"; then
    fail "轮次 1 的旧正文（问题点 A）应被压缩掉，但仍存在"
fi
if grep -q "问题点 C：边界条件遗漏" "$STATE_FILE"; then
    fail "轮次 2 的旧正文（问题点 C）应被压缩掉，但仍存在"
fi
pass "历史轮次正文已被压缩"

# 断言 6：幂等性 — 再次调用结果不变
cp "$STATE_FILE" "$STATE_FILE.first_run"
invoke_compress "$STATE_FILE"
rc2=$?
if [[ $rc2 -ne 0 ]]; then
    fail "第二次调用 compress_qa_report 返回非零 ($rc2)"
fi
if ! diff -q "$STATE_FILE" "$STATE_FILE.first_run" >/dev/null; then
    echo "----- diff -----" >&2
    diff "$STATE_FILE.first_run" "$STATE_FILE" >&2 || true
    fail "compress_qa_report 不是幂等的：第二次调用改变了文件内容"
fi
pass "幂等性：第二次调用结果与第一次相同"

echo "[OK ] R1 compress-qa-report — 全部断言通过"
exit 0
