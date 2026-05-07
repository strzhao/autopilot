#!/usr/bin/env bash
# R5: 验证 stop-hook.sh detect_smoke_eligible 函数三路径决策
# 红队测试 — 仅基于设计文档编写，不读取蓝队实现
#
# 设计文档决策表：
#   fast_mode=true  + ≤100行/≤8文件 + 无依赖  → qa_scope=smoke, fast_mode 保持 true
#   fast_mode=true  + >100行 或 含依赖         → qa_scope 不变（空）, fast_mode 降级为 false
#   fast_mode=false + ≤30行/≤3文件  + 无依赖  → qa_scope=smoke, fast_mode 保持 false
#   fast_mode=false + >30行  或 含依赖         → qa_scope 不变（空）, fast_mode 保持 false
#   qa_scope 已被设为非空（如 "selective"）    → 不覆盖，直接返回
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
STOP_HOOK="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"
LIB_SH="$REPO_ROOT/plugins/autopilot/scripts/lib.sh"

fail() {
    echo "[FAIL] R5: $1" >&2
    exit 1
}

pass() {
    echo "[PASS] R5: $1"
}

# 前置
[[ -f "$STOP_HOOK" ]] || fail "stop-hook.sh 不存在: $STOP_HOOK"
[[ -f "$LIB_SH" ]]   || fail "lib.sh 不存在: $LIB_SH"

# ── 断言 0：函数定义存在性 ───────────────────────────────────────────────────
if ! grep -qE '^detect_smoke_eligible\(\)|^function detect_smoke_eligible' "$STOP_HOOK"; then
    fail "detect_smoke_eligible() 函数未定义于 stop-hook.sh（设计文档要求新增此函数）"
fi
pass "detect_smoke_eligible() 函数定义存在"

# 临时目录 & state 文件准备
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# 创建伪 git 仓库（lib.sh 的 init_paths 需要）
mkdir -p "$TMP_DIR/.git"
STATE_FILE="$TMP_DIR/state.md"

# Helper：创建 state.md 并设置 frontmatter 字段
make_state() {
    local fast_mode="$1"
    local qa_scope="${2:-}"
    cat > "$STATE_FILE" <<EOF
---
active: true
phase: qa
fast_mode: $fast_mode
qa_scope: $qa_scope
iteration: 1
goal: test
worktree: /tmp/test
created_at: 2026-05-07T00:00:00Z
updated_at: 2026-05-07T00:00:00Z
---

## 目标
测试占位

## 设计文档
(占位)

## 变更日志
- [2026-05-07] 初始化
EOF
}

# Helper：通过 subshell source stop-hook.sh 并调用函数
# 传入：state 文件路径、diff 内容
# 输出：执行后 qa_scope 和 fast_mode 字段值（从 state 文件读取）
invoke_detect() {
    local state_f="$1"
    local diff_content="$2"

    bash -c "
        export AUTOPILOT_TEST_MODE=1
        export AUTOPILOT_DISABLE_MAIN=1
        exec </dev/null
        source '$LIB_SH' 2>/dev/null || true
        source '$STOP_HOOK' 2>/dev/null || true
        if ! declare -F detect_smoke_eligible >/dev/null 2>&1; then
            echo 'FUNCTION_NOT_FOUND' >&2
            exit 99
        fi
        # 设置 STATE_FILE 全局变量（lib.sh 使用）
        STATE_FILE='$state_f'
        # 传递 diff 内容通过临时文件
        DIFF_TMP=\$(mktemp)
        printf '%s' '$diff_content' > \"\$DIFF_TMP\"
        detect_smoke_eligible \"\$DIFF_TMP\" 2>/dev/null || true
        rm -f \"\$DIFF_TMP\"
    "
}

# 读取 state.md 中某字段
read_field() {
    local field="$1"
    local file="$2"
    grep "^${field}:" "$file" | sed "s/${field}: *//" | tr -d '"' | tr -d "'"
}

# ── 路径 A：fast_mode=true + 小 diff（≤100行，≤8文件）+ 无依赖 → smoke ──────
make_state "true" ""
# 构造 ≤100 行、≤8 文件的 diff（无依赖文件）
small_diff=""
for i in $(seq 1 5); do
    small_diff="${small_diff}diff --git a/src/file${i}.ts b/src/file${i}.ts
index abc..def 100644
--- a/src/file${i}.ts
+++ b/src/file${i}.ts
@@ -1,3 +1,4 @@
+// added line
 const x = 1;
 const y = 2;
"
done

invoke_detect "$STATE_FILE" "$small_diff"
qa_scope_a=$(read_field "qa_scope" "$STATE_FILE")
fast_mode_a=$(read_field "fast_mode" "$STATE_FILE")

if [[ "$qa_scope_a" != "smoke" ]]; then
    fail "路径A(fast+小diff): qa_scope 期望 'smoke'，实际 '$qa_scope_a'"
fi
if [[ "$fast_mode_a" != "true" ]]; then
    fail "路径A(fast+小diff): fast_mode 应保持 true，实际 '$fast_mode_a'"
fi
pass "路径A: fast_mode=true + 小diff → qa_scope=smoke, fast_mode=true"

# ── 路径 B：fast_mode=true + 大 diff（>100行）→ qa_scope 不变，fast_mode 降级 ──
make_state "true" ""
# 构造 >100 行的 diff
large_diff=""
for i in $(seq 1 110); do
    large_diff="${large_diff}+line ${i} of changes
"
done
large_diff="diff --git a/src/big.ts b/src/big.ts
index abc..def 100644
--- a/src/big.ts
+++ b/src/big.ts
@@ -1,5 +1,115 @@
${large_diff}"

invoke_detect "$STATE_FILE" "$large_diff"
qa_scope_b=$(read_field "qa_scope" "$STATE_FILE")
fast_mode_b=$(read_field "fast_mode" "$STATE_FILE")

if [[ "$qa_scope_b" == "smoke" ]]; then
    fail "路径B(fast+大diff): qa_scope 不应被设为 smoke（diff 超过阈值，应保持空或不变）"
fi
if [[ "$fast_mode_b" == "true" ]]; then
    fail "路径B(fast+大diff): fast_mode 应降级为 false，实际仍为 true"
fi
pass "路径B: fast_mode=true + 大diff → fast_mode 降级为 false，qa_scope 不设 smoke"

# ── 路径 C：fast_mode=false + 小 diff（≤30行，≤3文件）+ 无依赖 → smoke ────────
make_state "false" ""
# 构造 ≤30 行、2 文件的 diff
small_diff_std=""
for i in 1 2; do
    small_diff_std="${small_diff_std}diff --git a/src/f${i}.ts b/src/f${i}.ts
index aaa..bbb 100644
--- a/src/f${i}.ts
+++ b/src/f${i}.ts
@@ -1,2 +1,3 @@
+// new line
 const a = 1;
"
done

invoke_detect "$STATE_FILE" "$small_diff_std"
qa_scope_c=$(read_field "qa_scope" "$STATE_FILE")
fast_mode_c=$(read_field "fast_mode" "$STATE_FILE")

if [[ "$qa_scope_c" != "smoke" ]]; then
    fail "路径C(standard+小diff): qa_scope 期望 'smoke'，实际 '$qa_scope_c'"
fi
if [[ "$fast_mode_c" != "false" ]]; then
    fail "路径C(standard+小diff): fast_mode 应保持 false，实际 '$fast_mode_c'"
fi
pass "路径C: fast_mode=false + 小diff(≤30行≤3文件) → qa_scope=smoke"

# ── 路径 D：fast_mode=false + 大 diff（>30行）→ qa_scope 保持空 ──────────────
make_state "false" ""
# 构造 >30 行的 diff
big_diff_std="diff --git a/src/large.ts b/src/large.ts
index aaa..bbb 100644
--- a/src/large.ts
+++ b/src/large.ts
@@ -1,5 +1,40 @@
"
for i in $(seq 1 35); do
    big_diff_std="${big_diff_std}+line ${i}
"
done

invoke_detect "$STATE_FILE" "$big_diff_std"
qa_scope_d=$(read_field "qa_scope" "$STATE_FILE")

if [[ "$qa_scope_d" == "smoke" ]]; then
    fail "路径D(standard+大diff): qa_scope 不应被设为 smoke（>30行）"
fi
pass "路径D: fast_mode=false + 大diff(>30行) → qa_scope 不变（不设 smoke）"

# ── 路径 E：fast_mode=true + 含依赖文件 → 不触发 smoke，fast_mode 降级 ─────────
make_state "true" ""
dep_diff="diff --git a/package.json b/package.json
index aaa..bbb 100644
--- a/package.json
+++ b/package.json
@@ -1,3 +1,4 @@
+  \"newdep\": \"^1.0.0\",
 {
   \"name\": \"test\"
"

invoke_detect "$STATE_FILE" "$dep_diff"
qa_scope_e=$(read_field "qa_scope" "$STATE_FILE")
fast_mode_e=$(read_field "fast_mode" "$STATE_FILE")

if [[ "$qa_scope_e" == "smoke" ]]; then
    fail "路径E(fast+含依赖): 含 package.json 变更不应触发 smoke"
fi
if [[ "$fast_mode_e" == "true" ]]; then
    fail "路径E(fast+含依赖): fast_mode 应降级为 false（含依赖文件修改）"
fi
pass "路径E: fast_mode=true + 含 package.json 依赖文件 → fast_mode 降级，不触发 smoke"

# ── 路径 F：fast_mode=false + 含依赖文件（pnpm-lock/yarn.lock 等）→ 不触发 smoke ──
for dep_file in "pnpm-lock.yaml" "yarn.lock" "requirements.txt" "Cargo.lock"; do
    make_state "false" ""
    dep_diff2="diff --git a/${dep_file} b/${dep_file}
index aaa..bbb 100644
--- a/${dep_file}
+++ b/${dep_file}
@@ -1,2 +1,3 @@
+changed: true
 existing: content
"
    invoke_detect "$STATE_FILE" "$dep_diff2"
    qa_scope_f=$(read_field "qa_scope" "$STATE_FILE")
    if [[ "$qa_scope_f" == "smoke" ]]; then
        fail "路径F: 含 ${dep_file} 变更不应触发 smoke（standard 模式下含依赖文件）"
    fi
done
pass "路径F: standard 模式下含各类依赖文件（pnpm-lock/yarn.lock/requirements.txt/Cargo.lock）均不触发 smoke"

# ── 路径 G：qa_scope 已为非空（如 "selective"）→ 不被覆盖 ───────────────────
make_state "true" "selective"
invoke_detect "$STATE_FILE" "$small_diff"
qa_scope_g=$(read_field "qa_scope" "$STATE_FILE")

if [[ "$qa_scope_g" != "selective" ]]; then
    fail "路径G: qa_scope 已为 'selective'，detect_smoke_eligible 不应覆盖，实际变为 '$qa_scope_g'"
fi
pass "路径G: qa_scope 已为 'selective' → detect_smoke_eligible 不覆盖（保持 selective）"

# ── 路径 H：fast_mode=true + 文件数 > 8 → 即使行数 ≤100 也不触发 smoke ────────
make_state "true" ""
many_files_diff=""
for i in $(seq 1 9); do
    many_files_diff="${many_files_diff}diff --git a/src/f${i}.ts b/src/f${i}.ts
index abc..def 100644
--- a/src/f${i}.ts
+++ b/src/f${i}.ts
@@ -1,1 +1,2 @@
+// change
 const x = ${i};
"
done

invoke_detect "$STATE_FILE" "$many_files_diff"
qa_scope_h=$(read_field "qa_scope" "$STATE_FILE")
fast_mode_h=$(read_field "fast_mode" "$STATE_FILE")

if [[ "$qa_scope_h" == "smoke" ]]; then
    fail "路径H(fast+9文件): 文件数超过 8 不应触发 smoke（fast 模式阈值 ≤8 文件）"
fi
if [[ "$fast_mode_h" == "true" ]]; then
    fail "路径H(fast+9文件): fast_mode 应降级为 false（文件数超过阈值）"
fi
pass "路径H: fast_mode=true + 9文件(>8) → 不触发 smoke，fast_mode 降级"

echo "[OK ] R5 detect-smoke-eligible — 全部断言通过"
exit 0
