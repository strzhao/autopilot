#!/usr/bin/env bash
# acceptance test: auto-chain dag brief 显式指针根治（brief 优先 + tasks/<id>.md 回退）
#
# 根因修复验证（v3.54.1 设计契约）：4 处查找点推断「文件名=id」AI 偏离即断。
# 根治契约：dag.yaml 的 `brief` 字段作为显式文件指针，全链路优先用 brief 定位任务文件，
# brief 字段缺失时回退 `tasks/<id>.md`（向后兼容 v3.54.0）。
#
# 修复契约（本测试验证的）：
#   1. lib.sh 新增 get_task_brief(dag_file, task_id) 纯函数：
#      - 返回 dag 该 id 的 `brief` 字段值（相对路径如 .autopilot/project/tasks/002-foo.md）
#      - 无 brief 字段返回空字符串
#      - 多 task 时精确匹配 id（不窜位）
#   2. stop-hook Case 0.5/1：TASK_FILE 优先用 brief 字段（$PROJECT_ROOT/$brief 或绝对），
#      空则回退 tasks/${id}.md
#   3. lib.sh create_brief_state_file handoff：dep 的 handoff 优先用 dep 的 brief 推导
#      （${dep_brief%.md}.handoff.md），空则回退 ${dep}.handoff.md
#
# 向后兼容铁律：无 brief 字段时行为 = v3.54.0（回退命中）。
#
# 覆盖验收场景 P1-P5（逐条硬断言，失败 exit 非零）：
#   P1 dag 有 brief → get_task_brief 返回 brief 值（det-machine）
#   P2 dag 无 brief → get_task_brief 返回空（det-machine）
#   P3 dag 多 task → get_task_brief 精确匹配 id（det-machine，v3.54.1 awk 字段顺序 bug 回归保护）
#   P4 stop-hook TASK_FILE 查找契约镜像（det-machine，brief 优先 + 回退两路径）
#   P5 handoff dep_brief 推导契约镜像（det-machine，brief 推导 + 回退两路径）
#
# 运行：bash dag-brief-ptr.acceptance.test.sh
# 退出码：0 全部 PASS；非零表示对应 P<n> 失败（蓝队未实现 get_task_brief 时 P1-P3 失败属预期）。

set -u

# ── source 被测函数 ────────────────────────────────────────────
# lib.sh 顶部仅定义函数与空变量，init_paths 需显式调用（source 本身无副作用）。
# get_task_brief 设计为纯函数（解析入参 dag_file + task_id），不依赖 PROJECT_ROOT。
#
# 定位 repo root：从测试文件位置向上找 .git（staging 目录层级不固定时稳健，
# 与 auto-chain-naming-contract.acceptance.test.sh 同款）。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT=""
_search="$SCRIPT_DIR"
while [[ -n "$_search" ]] && [[ "$_search" != "/" ]]; do
    if [[ -d "$_search/.git" ]]; then
        REPO_ROOT="$_search"
        break
    fi
    _search="$(dirname "$_search")"
done
unset _search

if [[ -z "$REPO_ROOT" ]]; then
    echo "FATAL: cannot locate repo root (.git) from $SCRIPT_DIR" >&2
    exit 99
fi

LIB_SH="$REPO_ROOT/plugins/autopilot/scripts/lib.sh"

if [[ ! -f "$LIB_SH" ]]; then
    echo "FATAL: lib.sh not found at $LIB_SH" >&2
    exit 99
fi

# shellcheck source=/dev/null
source "$LIB_SH"

# 设计契约：get_task_brief 必须存在。蓝队未实现时此分支失败（预期「未实现」状态）。
GET_TASK_BRIEF_DEFINED=1
if ! declare -F get_task_brief >/dev/null 2>&1; then
    GET_TASK_BRIEF_DEFINED=0
    echo "WARN: get_task_brief not defined after sourcing lib.sh (blue-team not yet implemented? P1-P3 will fail)" >&2
fi

# ── 测试夹具 ──────────────────────────────────────────────────
TMP_DAG_DIR=""
cleanup() {
    [[ -n "$TMP_DAG_DIR" ]] && [[ -d "$TMP_DAG_DIR" ]] && rm -rf "$TMP_DAG_DIR"
}
trap cleanup EXIT

TMP_DAG_DIR="$(mktemp -d)"

PASS_COUNT=0
FAIL_COUNT=0

assert_eq() {
    # assert_eq <actual> <expected> <label>
    local actual="$1" expected="$2" label="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  PASS  $label (actual='$actual')"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  $label"
        echo "        expected='$expected'"
        echo "        actual=  '$actual'"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

assert_neq() {
    # assert_neq <actual> <not_expected> <label>
    local actual="$1" not_expected="$2" label="$3"
    if [[ "$actual" != "$not_expected" ]]; then
        echo "  PASS  $label (actual='$actual' != '$not_expected')"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  $label"
        echo "        expected != '$not_expected'"
        echo "        actual=    '$actual'"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# ═══════════════════════════════════════════════════════════════
# P1: dag 有 brief → get_task_brief 返回 brief 值
# 验收标准：get_task_brief(dag, foo) 输出 .autopilot/project/tasks/002-foo.md
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P1: dag 有 brief → get_task_brief 返回 brief 值 ──"

# 构造 dag.yaml：id=foo + brief 显式指针（文件名 ≠ id）
cat > "$TMP_DAG_DIR/p1-dag.yaml" <<'EOF'
tasks:
  - id: foo
    title: foo task with brief pointer
    brief: .autopilot/project/tasks/002-foo.md
    status: pending
    depends_on: []
EOF

if [[ "$GET_TASK_BRIEF_DEFINED" -eq 1 ]]; then
    ACTUAL_P1="$(get_task_brief "$TMP_DAG_DIR/p1-dag.yaml" "foo")"
    assert_eq "$ACTUAL_P1" ".autopilot/project/tasks/002-foo.md" \
        "P1: get_task_brief returns brief value '.autopilot/project/tasks/002-foo.md'"
else
    echo "  FAIL  P1: get_task_brief undefined (contract not implemented)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# P2: dag 无 brief → get_task_brief 返回空（回退路径依赖此）
# 验收标准：无 brief 字段 → 返回空字符串
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P2: dag 无 brief → get_task_brief 返回空 ──"

# 构造 dag.yaml：id=foo 但无 brief 字段（v3.54.0 旧格式）
cat > "$TMP_DAG_DIR/p2-dag.yaml" <<'EOF'
tasks:
  - id: foo
    title: foo task without brief
    status: pending
    depends_on: []
EOF

if [[ "$GET_TASK_BRIEF_DEFINED" -eq 1 ]]; then
    ACTUAL_P2="$(get_task_brief "$TMP_DAG_DIR/p2-dag.yaml" "foo")"
    assert_eq "$ACTUAL_P2" "" \
        "P2: get_task_brief returns empty when brief field absent (fallback path depends on this)"
else
    echo "  FAIL  P2: get_task_brief undefined (contract not implemented)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# P3: dag 多 task → get_task_brief 精确匹配 id（不窜位）
# 验收标准：task A（有 brief）+ task B（无 brief），分别查询返回各自正确值
# 关键回归保护：v3.54.1 awk 字段顺序 bug——多 task 时 brief 窜位（A 的 brief 错配给 B）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P3: dag 多 task → get_task_brief 精确匹配 id（v3.54.1 窜位回归保护） ──"

# 构造 dag.yaml：task A（有 brief）+ task B（无 brief），故意让 B 紧跟 A
# 若 awk 按「遇 brief 字段即记录」而非「按 id 分组」，会把 A 的 brief 错配给 B
cat > "$TMP_DAG_DIR/p3-dag.yaml" <<'EOF'
tasks:
  - id: A
    title: task A with brief
    brief: .autopilot/project/tasks/001-a.md
    status: pending
    depends_on: []
  - id: B
    title: task B without brief (must NOT inherit A's brief)
    status: pending
    depends_on: []
EOF

if [[ "$GET_TASK_BRIEF_DEFINED" -eq 1 ]]; then
    ACTUAL_P3_A="$(get_task_brief "$TMP_DAG_DIR/p3-dag.yaml" "A")"
    ACTUAL_P3_B="$(get_task_brief "$TMP_DAG_DIR/p3-dag.yaml" "B")"
    assert_eq "$ACTUAL_P3_A" ".autopilot/project/tasks/001-a.md" \
        "P3-a: get_task_brief(A) returns A's brief (not leaked)"
    assert_eq "$ACTUAL_P3_B" "" \
        "P3-b: get_task_brief(B) returns empty (NOT inheriting A's brief = no field-order bug)"
else
    echo "  FAIL  P3: get_task_brief undefined (contract not implemented)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ═══════════════════════════════════════════════════════════════
# P4: stop-hook TASK_FILE 查找契约镜像（brief 优先 + tasks/<id>.md 回退）
# 验收标准：
#   - brief 非空 → TASK_FILE=$PROJECT_ROOT/$brief 命中 002-foo.md（非 foo.md）
#   - brief 空  → TASK_FILE=tasks/foo.md（回退命中）
# 契约镜像：stop-hook.sh:472/503 Case 0.5/1 的「brief 优先 + id.md 回退」逻辑
# （stop-hook 是 Stop hook 不能直接跑，按设计文档查找逻辑镜像）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P4: stop-hook TASK_FILE 查找契约镜像（brief 优先 + 回退） ──"

# P4-a：brief 非空路径
# 构造 project root，brief 指向 002-foo.md（文件名 ≠ id=foo）
TMP_PROJ_P4A="$(mktemp -d)"
mkdir -p "$TMP_PROJ_P4A/.autopilot/project/tasks"
cat > "$TMP_PROJ_P4A/.autopilot/project/dag.yaml" <<'EOF'
tasks:
  - id: foo
    brief: .autopilot/project/tasks/002-foo.md
    status: pending
    depends_on: []
EOF
# 故意只放 002-foo.md（不放 foo.md），证明走的是 brief 路径而非回退
echo "# foo brief content (id != filename)" > "$TMP_PROJ_P4A/.autopilot/project/tasks/002-foo.md"

PROJECT_ROOT="$TMP_PROJ_P4A"
TASK_ID="foo"
TASK_BRIEF=""
if [[ "$GET_TASK_BRIEF_DEFINED" -eq 1 ]]; then
    TASK_BRIEF="$(get_task_brief "$PROJECT_ROOT/.autopilot/project/dag.yaml" "$TASK_ID")"
fi

# 契约镜像：stop-hook TASK_FILE 查找逻辑
#   if [[ -n "$brief" ]]; then TASK_FILE="$PROJECT_ROOT/$brief"; else TASK_FILE="$PROJECT_ROOT/.autopilot/project/tasks/${id}.md"; fi
if [[ -n "$TASK_BRIEF" ]]; then
    TASK_FILE_P4A="$PROJECT_ROOT/$TASK_BRIEF"
else
    TASK_FILE_P4A="$PROJECT_ROOT/.autopilot/project/tasks/${TASK_ID}.md"
fi

if [[ "$GET_TASK_BRIEF_DEFINED" -eq 1 ]]; then
    assert_eq "$(basename "$TASK_FILE_P4A")" "002-foo.md" \
        "P4-a: TASK_FILE via brief → 002-foo.md (filename != id, brief path taken)"
    [[ -f "$TASK_FILE_P4A" ]] && { echo "  PASS  P4-a-exists (brief-derived file exists)"; PASS_COUNT=$((PASS_COUNT + 1)); } || \
        { echo "  FAIL  P4-a-exists (brief-derived file missing: $TASK_FILE_P4A)"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
else
    # 蓝队未实现时，验证回退路径（无 brief 解析 → 必须走 tasks/<id>.md）
    assert_eq "$(basename "$TASK_FILE_P4A")" "foo.md" \
        "P4-a (fallback-only, no brief): TASK_FILE → foo.md (regression baseline = v3.54.0)"
fi

rm -rf "$TMP_PROJ_P4A"

# P4-b：brief 空路径（回退）
# 构造 dag 无 brief，只放 tasks/foo.md，证明回退命中
TMP_PROJ_P4B="$(mktemp -d)"
mkdir -p "$TMP_PROJ_P4B/.autopilot/project/tasks"
cat > "$TMP_PROJ_P4B/.autopilot/project/dag.yaml" <<'EOF'
tasks:
  - id: foo
    title: foo without brief (v3.54.0 format)
    status: pending
    depends_on: []
EOF
echo "# foo brief (id-aligned, no brief field)" > "$TMP_PROJ_P4B/.autopilot/project/tasks/foo.md"

PROJECT_ROOT="$TMP_PROJ_P4B"
TASK_ID="foo"
TASK_BRIEF=""
if [[ "$GET_TASK_BRIEF_DEFINED" -eq 1 ]]; then
    TASK_BRIEF="$(get_task_brief "$PROJECT_ROOT/.autopilot/project/dag.yaml" "$TASK_ID")"
fi

# 契约镜像：同 P4-a
if [[ -n "$TASK_BRIEF" ]]; then
    TASK_FILE_P4B="$PROJECT_ROOT/$TASK_BRIEF"
else
    TASK_FILE_P4B="$PROJECT_ROOT/.autopilot/project/tasks/${TASK_ID}.md"
fi

assert_eq "$(basename "$TASK_FILE_P4B")" "foo.md" \
    "P4-b: TASK_FILE fallback (brief empty) → foo.md (backward compat = v3.54.0)"
[[ -f "$TASK_FILE_P4B" ]] && { echo "  PASS  P4-b-exists (fallback file exists)"; PASS_COUNT=$((PASS_COUNT + 1)); } || \
    { echo "  FAIL  P4-b-exists (fallback file missing: $TASK_FILE_P4B)"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

rm -rf "$TMP_PROJ_P4B"

# ═══════════════════════════════════════════════════════════════
# P5: handoff dep_brief 推导契约镜像（brief 推导 + ${dep}.handoff.md 回退）
# 验收标准：
#   - dep 的 brief 非空 → handoff = ${brief%.md}.handoff.md = 002-foo.handoff.md（非 foo.handoff.md）
#   - dep 的 brief 空  → handoff = ${dep}.handoff.md（回退）
# 契约镜像：lib.sh create_brief_state_file handoff 推导逻辑（lib.sh:863 既有 + brief 推导增强）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P5: handoff dep_brief 推导契约镜像（brief 推导 + 回退） ──"

# P5-a：dep 的 brief 非空（推导路径）
# 构造 dag：dep=foo 的 brief 指向 002-foo.md → handoff 应为 002-foo.handoff.md
TMP_PROJ_P5A="$(mktemp -d)"
mkdir -p "$TMP_PROJ_P5A/.autopilot/project/tasks"
cat > "$TMP_PROJ_P5A/.autopilot/project/dag.yaml" <<'EOF'
tasks:
  - id: foo
    brief: .autopilot/project/tasks/002-foo.md
    status: done
    depends_on: []
EOF
# 故意只放 002-foo.handoff.md（不放 foo.handoff.md），证明走的是 brief 推导路径
echo "foo handoff content (brief-derived)" > "$TMP_PROJ_P5A/.autopilot/project/tasks/002-foo.handoff.md"

PROJECT_ROOT="$TMP_PROJ_P5A"
DEP="foo"
DEP_BRIEF=""
if [[ "$GET_TASK_BRIEF_DEFINED" -eq 1 ]]; then
    DEP_BRIEF="$(get_task_brief "$PROJECT_ROOT/.autopilot/project/dag.yaml" "$DEP")"
fi
BRIEF_DIR="$PROJECT_ROOT/.autopilot/project/tasks"

# 契约镜像：lib.sh create_brief_state_file handoff 推导逻辑
#   if [[ -n "$dep_brief" ]]; then handoff="${dep_brief%.md}.handoff.md"; else handoff="${dep}.handoff.md"; fi
# 注意：dep_brief 可能是相对路径（.autopilot/project/tasks/002-foo.md），需取 basename 再推导
if [[ -n "$DEP_BRIEF" ]]; then
    DEP_BRIEF_BASE="$(basename "$DEP_BRIEF")"
    HANDOFF_FILE_P5A="$BRIEF_DIR/${DEP_BRIEF_BASE%.md}.handoff.md"
else
    HANDOFF_FILE_P5A="$BRIEF_DIR/${DEP}.handoff.md"
fi

if [[ "$GET_TASK_BRIEF_DEFINED" -eq 1 ]]; then
    assert_eq "$(basename "$HANDOFF_FILE_P5A")" "002-foo.handoff.md" \
        "P5-a: handoff via dep_brief → 002-foo.handoff.md (NOT foo.handoff.md)"
    [[ -f "$HANDOFF_FILE_P5A" ]] && { echo "  PASS  P5-a-exists (brief-derived handoff exists)"; PASS_COUNT=$((PASS_COUNT + 1)); } || \
        { echo "  FAIL  P5-a-exists (brief-derived handoff missing: $HANDOFF_FILE_P5A)"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
else
    assert_eq "$(basename "$HANDOFF_FILE_P5A")" "foo.handoff.md" \
        "P5-a (fallback-only, no brief): handoff → foo.handoff.md (regression baseline = v3.54.0)"
fi

rm -rf "$TMP_PROJ_P5A"

# P5-b：dep 的 brief 空（回退路径）
TMP_PROJ_P5B="$(mktemp -d)"
mkdir -p "$TMP_PROJ_P5B/.autopilot/project/tasks"
cat > "$TMP_PROJ_P5B/.autopilot/project/dag.yaml" <<'EOF'
tasks:
  - id: foo
    title: foo without brief
    status: done
    depends_on: []
EOF
echo "foo handoff (id-aligned, no brief field)" > "$TMP_PROJ_P5B/.autopilot/project/tasks/foo.handoff.md"

PROJECT_ROOT="$TMP_PROJ_P5B"
DEP="foo"
DEP_BRIEF=""
if [[ "$GET_TASK_BRIEF_DEFINED" -eq 1 ]]; then
    DEP_BRIEF="$(get_task_brief "$PROJECT_ROOT/.autopilot/project/dag.yaml" "$DEP")"
fi
BRIEF_DIR="$PROJECT_ROOT/.autopilot/project/tasks"

# 契约镜像：同 P5-a
if [[ -n "$DEP_BRIEF" ]]; then
    DEP_BRIEF_BASE="$(basename "$DEP_BRIEF")"
    HANDOFF_FILE_P5B="$BRIEF_DIR/${DEP_BRIEF_BASE%.md}.handoff.md"
else
    HANDOFF_FILE_P5B="$BRIEF_DIR/${DEP}.handoff.md"
fi

assert_eq "$(basename "$HANDOFF_FILE_P5B")" "foo.handoff.md" \
    "P5-b: handoff fallback (dep_brief empty) → foo.handoff.md (backward compat = v3.54.0)"
[[ -f "$HANDOFF_FILE_P5B" ]] && { echo "  PASS  P5-b-exists (fallback handoff exists)"; PASS_COUNT=$((PASS_COUNT + 1)); } || \
    { echo "  FAIL  P5-b-exists (fallback handoff missing: $HANDOFF_FILE_P5B)"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

rm -rf "$TMP_PROJ_P5B"

# ── 汇总 ──────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "  PASS: $PASS_COUNT    FAIL: $FAIL_COUNT"
echo "════════════════════════════════════════"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo "RESULT: FAIL (dag brief pointer contract violated)"
    exit 1
fi

echo "RESULT: PASS (dag brief pointer contract holds: brief-first + id.md fallback)"
exit 0
