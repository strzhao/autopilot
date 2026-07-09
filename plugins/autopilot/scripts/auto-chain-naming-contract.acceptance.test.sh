#!/usr/bin/env bash
# acceptance test: auto-chain 任务文件命名契约（文件名 = dag.yaml id stem）
#
# 根因修复验证：get_first_ready_task 返回 dag.yaml 的 id（如 T4），全链路用 id 查找任务文件。
# 修复契约：dag.yaml 的 id ≡ 任务文件名 stem
#   - brief 文件名 = <id>.md
#   - handoff 文件名 = <id>.handoff.md
#
# 覆盖验收场景 P1-P5（逐条硬断言，失败 exit 非零）。
#
# 被测系统契约锚点（既存脚本，蓝队未改）：
#   - lib.sh:788  get_first_ready_task  （返回 dag.yaml 的 id，awk 纯解析）
#   - stop-hook.sh:502  TASK_FILE=".../tasks/${NEXT_TASK}.md"  （NEXT_TASK=id）
#   - setup.sh:435      find "$TASKS_DIR" -name "${GOAL}*.md"  （GOAL=id 前缀匹配）
#   - lib.sh:863        handoff="$brief_dir/${dep}.handoff.md" （dep=depends_on id）
#
# 运行：bash auto-chain-naming-contract.acceptance.test.sh
# 退出码：0 全部 PASS；非零表示对应 P<n> 失败。

set -u

# ── source 被测函数 ────────────────────────────────────────────
# lib.sh 顶部仅定义函数与空变量，init_paths 需显式调用（source 本身无副作用）。
# get_first_ready_task 是纯函数（awk 解析入参 dag_file），不依赖 PROJECT_ROOT。
#
# 定位 repo root：从测试文件位置向上找 .git（稳健，不依赖固定深度，
# 因为 staging 目录可能在不同层级；最终落 plugins/autopilot/scripts/test/ 时也成立）。
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

if ! declare -F get_first_ready_task >/dev/null 2>&1; then
    echo "FATAL: get_first_ready_task not defined after sourcing lib.sh" >&2
    exit 99
fi

# ── 测试夹具 ──────────────────────────────────────────────────
TMP_PROJECT=""
cleanup() {
    [[ -n "$TMP_PROJECT" ]] && [[ -d "$TMP_PROJECT" ]] && rm -rf "$TMP_PROJECT"
}
trap cleanup EXIT

TMP_PROJECT="$(mktemp -d)"
TASKS_DIR="$TMP_PROJECT/.autopilot/project/tasks"
mkdir -p "$TASKS_DIR"

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

assert_file_exists() {
    # assert_file_exists <path> <label>
    local path="$1" label="$2"
    if [[ -f "$path" ]]; then
        echo "  PASS  $label (file exists: $(basename "$path"))"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  $label (file NOT found: $path)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

assert_file_not_exists() {
    # assert_file_not_exists <path> <label>
    local path="$1" label="$2"
    if [[ ! -f "$path" ]]; then
        echo "  PASS  $label (correctly NOT found: $(basename "$path"))"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  $label (unexpected file exists: $path)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

assert_find_hits() {
    # assert_find_hits <tasks_dir> <pattern> <expect_basename> <label>
    # 模拟 setup.sh:435 的 find 前缀匹配，断言命中期望文件
    local tasks_dir="$1" pattern="$2" expect="$3" label="$4"
    local match
    match=$(find "$tasks_dir" -maxdepth 1 -name "${pattern}*.md" ! -name "*.handoff.md" 2>/dev/null | head -1)
    local hit_basename=""
    [[ -n "$match" ]] && hit_basename="$(basename "$match")"
    if [[ "$hit_basename" == "$expect" ]]; then
        echo "  PASS  $label (find '$pattern*.md' → $hit_basename)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  $label"
        echo "        find pattern: '${pattern}*.md'"
        echo "        expected hit: '$expect'"
        echo "        actual hit:   '$hit_basename'"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

assert_find_miss() {
    # assert_find_miss <tasks_dir> <pattern> <label>
    # 断言 find 不命中任何文件（回归保护：旧命名不应被 id 前缀匹配命中）
    local tasks_dir="$1" pattern="$2" label="$3"
    local match
    match=$(find "$tasks_dir" -maxdepth 1 -name "${pattern}*.md" ! -name "*.handoff.md" 2>/dev/null | head -1)
    if [[ -z "$match" ]]; then
        echo "  PASS  $label (find '${pattern}*.md' → no hit, as expected for buggy naming)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL  $label"
        echo "        find pattern: '${pattern}*.md'"
        echo "        expected: no hit (id-based lookup must miss NNN-name files)"
        echo "        actual hit:   '$(basename "$match")'"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# ═══════════════════════════════════════════════════════════════
# P1: get_first_ready_task 返回 id（证明链路起点是 id）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P1: get_first_ready_task 返回 id ──"

# 构造 dag.yaml：T4 pending + depends_on:[T2b]，T2b done
cat > "$TMP_PROJECT/dag.yaml" <<'EOF'
tasks:
  - id: T2b
    title: prerequisite done task
    status: done
    depends_on: []
  - id: T4
    title: target ready task
    status: pending
    depends_on: [T2b]
EOF

# 被测：lib.sh:788 get_first_ready_task
NEXT_TASK="$(get_first_ready_task "$TMP_PROJECT/dag.yaml")"
assert_eq "$NEXT_TASK" "T4" "P1: get_first_ready_task returns id 'T4' (chain start = dag id)"

# ═══════════════════════════════════════════════════════════════
# P2: stop-hook 文件查找命中（id=T4 → tasks/T4.md 存在）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P2: stop-hook tasks/<id>.md 查找命中 ──"

# 修复契约：brief 文件名 = <id>.md（而非 005-t4-media.md）
echo "# T4 task brief (id-aligned naming)" > "$TASKS_DIR/T4.md"

# 被测：stop-hook.sh:502  TASK_FILE=".../tasks/${NEXT_TASK}.md"
TASK_FILE="$TMP_PROJECT/.autopilot/project/tasks/${NEXT_TASK}.md"
assert_file_exists "$TASK_FILE" "P2: tasks/T4.md exists when naming follows id contract"

# ═══════════════════════════════════════════════════════════════
# P3: setup.sh next 命中 brief（GOAL=id → find 前缀匹配 T4.md）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P3: setup.sh find -name 'T4*.md' 命中 brief ──"

# 被测：setup.sh:435  find "$TASKS_DIR" -name "${GOAL}*.md"
# GOAL 来自 /autopilot next 的 get_first_ready_task = id
GOAL="$NEXT_TASK"
assert_find_hits "$TASKS_DIR" "$GOAL" "T4.md" "P3: find '${GOAL}*.md' hits T4.md (id-aligned brief)"

# ═══════════════════════════════════════════════════════════════
# P4: handoff 命中（dep=T2b → tasks/T2b.handoff.md 存在）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P4: handoff <dep>.handoff.md 命中 ──"

# 修复契约：handoff 文件名 = <id>.handoff.md
echo "T2b handoff content (id-aligned)" > "$TASKS_DIR/T2b.handoff.md"

# 被测：lib.sh:863  handoff="$brief_dir/${dep}.handoff.md"
# dep 来自 brief 文件的 depends_on（即 dag id T2b）
DEP="T2b"  # 从 P1 dag.yaml 的 depends_on 解析
HANDOFF_FILE="$TASKS_DIR/${DEP}.handoff.md"
assert_file_exists "$HANDOFF_FILE" "P4: tasks/T2b.handoff.md exists (dep id-aligned handoff)"

# ═══════════════════════════════════════════════════════════════
# P5: 反例回归（旧命名 005-t4-media.md + id=T4 → 查找失败）
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── P5: 反例回归（旧命名查找失败，回归保护） ──"

# 独立临时项目模拟旧（buggy）命名：文件名 NNN-<name>.md，id=T4
TMP_BUGGY="$(mktemp -d)"
BUGGY_TASKS="$TMP_BUGGY/.autopilot/project/tasks"
mkdir -p "$BUGGY_TASKS"

cat > "$TMP_BUGGY/dag.yaml" <<'EOF'
tasks:
  - id: T2b
    title: prerequisite done task
    status: done
    depends_on: []
  - id: T4
    title: target ready task
    status: pending
    depends_on: [T2b]
EOF

# 旧命名：文件名带 NNN 前缀和语义后缀，与 id=T4 无 stem 关系
echo "# old buggy naming" > "$BUGGY_TASKS/005-t4-media.md"

BUGGY_NEXT="$(get_first_ready_task "$TMP_BUGGY/dag.yaml")"
assert_eq "$BUGGY_NEXT" "T4" "P5-pre: buggy dag still resolves id 'T4' (chain start unchanged)"

# 反例断言1：stop-hook 直接拼接 tasks/<id>.md → 文件不存在
BUGGY_TASK_FILE="$TMP_BUGGY/.autopilot/project/tasks/${BUGGY_NEXT}.md"
assert_file_not_exists "$BUGGY_TASK_FILE" "P5-a: stop-hook tasks/T4.md NOT exists under buggy naming (chain breaks)"

# 反例断言2：setup.sh find 'T4*.md' → 不命中 005-t4-media.md（前缀不匹配）
assert_find_miss "$BUGGY_TASKS" "$BUGGY_NEXT" "P5-b: setup.sh find 'T4*.md' misses 005-t4-media.md (brief lookup breaks)"

# 反例断言3：handoff T2b.handoff.md → 旧命名下不存在
echo "old buggy handoff" > "$BUGGY_TASKS/002-t2b-prereq.handoff.md"
BUGGY_HANDOFF="$BUGGY_TASKS/${DEP}.handoff.md"
assert_file_not_exists "$BUGGY_HANDOFF" "P5-c: handoff T2b.handoff.md NOT exists under buggy naming (injection lost)"

rm -rf "$TMP_BUGGY"

# ── 汇总 ──────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "  PASS: $PASS_COUNT    FAIL: $FAIL_COUNT"
echo "════════════════════════════════════════"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo "RESULT: FAIL (auto-chain naming contract violated)"
    exit 1
fi

echo "RESULT: PASS (auto-chain naming contract holds: filename = dag id stem)"
exit 0
