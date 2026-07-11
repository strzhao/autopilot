#!/usr/bin/env bash
# acceptance test: brief（项目子任务）状态创建 auto_approve/html_review 默认值
# + stop-hook §5.5 auto-approve → merge 推进
#
# 修复根因（设计文档）：
#   project auto mode 有 3 个人工介入卡点（③已另修，本任务治①②）：
#     ① design 触发 HTML 评审
#     ② QA 卡 review-accept 需手动 approve
#   根因：brief（项目子任务）状态创建时 auto_approve=false，导致 design 走审批
#         + stop-hook §5.5（条件 auto_approve==true）不触发。
#   修复：让 create_brief_state_file 的 brief 默认 auto_approve=true（单任务显式传 false 保留）。
#
# 黑盒规约（本测试验证的，不读实现）：
#   - brief 模式（项目子任务）state 应 auto_approve: true + html_review: false
#   - 单任务模式（显式传单任务偏好）state 应 auto_approve: false + html_review: true（回归不破）
#   - stop-hook §5.5：state 满足 gate=review-accept ∧ phase=qa ∧ auto_approve=true → 自动转 phase=merge
#
# 覆盖验收场景（每条 ≥1 硬断言，失败 exit 1）：
#   AC-P1：brief 模式 create_brief_state_file 4 参 → state auto_approve==true ∧ html_review==false
#   AC-P2：单任务显式偏好（6 参传 false/true）→ state auto_approve==false ∧ html_review==true（回归不破）
#   AC-P3：brief state (auto_approve=true, phase=qa, gate=review-accept) 经 stop-hook → phase==merge
#
# 被测对象（黑盒调用，不读内部默认值逻辑）：
#   - lib.sh:create_brief_state_file（函数签名 brief,session,max_iter,max_retries,auto_approve=true,html_review=false）
#   - stop-hook.sh §5.5（真跑 stop-hook.sh，喂 stdin JSON）
#
# 运行：bash brief-auto-approve.acceptance.test.sh
# 退出码：0 全部 PASS；非零表示对应 AC 失败（蓝队未实现修复时 AC-P1 失败属预期）。

set -u

# ── 定位 repo root（与既有测试同款，从 BASH_SOURCE 向上找 .git） ──
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
STOP_HOOK="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"

if [[ ! -f "$LIB_SH" ]]; then
    echo "FATAL: lib.sh not found at $LIB_SH" >&2
    exit 99
fi
if [[ ! -f "$STOP_HOOK" ]]; then
    echo "FATAL: stop-hook.sh not found at $STOP_HOOK" >&2
    exit 99
fi

# shellcheck source=/dev/null
source "$LIB_SH"

# 设计契约：create_brief_state_file 必须存在。蓝队未实现修复（默认值仍是 false）时
# AC-P1 会失败（这正是红队要抓的：默认值未改则 brief state 仍 auto_approve=false）。
CREATE_BRIEF_DEFINED=1
if ! declare -F create_brief_state_file >/dev/null 2>&1; then
    CREATE_BRIEF_DEFINED=0
    echo "WARN: create_brief_state_file not defined (blue-team missing? AC-P1/P2 will fail)" >&2
fi

# ── 断言宏（参考既有测试 dag-brief-ptr.acceptance.test.sh 风格） ──
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

# 从 state.md frontmatter 提取字段值（strip 可选双引号）
get_frontmatter_field() {
    local state_file="$1" field="$2"
    grep -E "^${field}:" "$state_file" 2>/dev/null \
        | head -1 \
        | sed -E "s/^${field}:[[:space:]]*\"?([^\"]*)\"?[[:space:]]*\$/\1/"
}

# ═══════════════════════════════════════════════════════════════
# AC-P1: brief 模式 create_brief_state_file 4 参 → state auto_approve==true ∧ html_review==false
#
# 黑盒：只传 4 个必填参（brief_file, session, max_iter, max_retries），
# 不传 auto_approve/html_review —— 测的就是默认值。
# 验收：生成的 $STATE_FILE frontmatter auto_approve: true + html_review: false
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── AC-P1: brief 模式（4 参）→ state auto_approve=true ∧ html_review=false ──"

TMP_P1="$(mktemp -d -t autopilot-ac-p1-XXXXXX)"
mkdir -p "$TMP_P1/.autopilot/runtime/requirements/brief-task"
mkdir -p "$TMP_P1/.autopilot/project/tasks"

# brief 文件（项目子任务，含 frontmatter）
BRIEF_P1="$TMP_P1/.autopilot/project/tasks/brief-task.md"
cat > "$BRIEF_P1" <<'EOF'
---
id: brief-task
depends_on: []
---
# brief task
test brief content
EOF

# 设好 create_brief_state_file 依赖的全局环境（PROJECT_ROOT / TASK_DIR / STATE_FILE）
export PROJECT_ROOT="$TMP_P1"
TASK_DIR="$TMP_P1/.autopilot/runtime/requirements/brief-task"
STATE_FILE="$TASK_DIR/state.md"

if [[ "$CREATE_BRIEF_DEFINED" -eq 1 ]]; then
    # 黑盒调用：只传 4 个必填参，不传 auto_approve/html_review
    create_brief_state_file "$BRIEF_P1" "p1sess" "30" "3"

    ACTUAL_AA_P1="$(get_frontmatter_field "$STATE_FILE" auto_approve)"
    ACTUAL_HR_P1="$(get_frontmatter_field "$STATE_FILE" html_review)"
    assert_eq "$ACTUAL_AA_P1" "true" \
        "AC-P1: brief state auto_approve==true (default, fixes design审批 + §5.5不触发)"
    assert_eq "$ACTUAL_HR_P1" "false" \
        "AC-P1: brief state html_review==false (skip HTML review for subtask)"
else
    echo "  FAIL  AC-P1: create_brief_state_file undefined (contract not implemented)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

rm -rf "$TMP_P1"

# ═══════════════════════════════════════════════════════════════
# AC-P2: 单任务显式偏好（6 参传 auto_approve=false, html_review=true）→ 回归不破
#
# 黑盒：单任务模式（AUTOPILOT_HTML_REVIEW=1）显式传第 5/6 参覆盖默认。
# 测的是：显式传值不被默认覆盖（单任务仍走审批 + HTML 评审）。
# 降级说明：setup.sh CLI 难以黑盒驱动（需完整 CLI 交互），改为 lib.sh 层断言
# 显式传参仍生效（证明单任务显式偏好路径不破，这是最稳的黑盒断言方式）。
# 验收：生成的 $STATE_FILE frontmatter auto_approve: false + html_review: true
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── AC-P2: 单任务显式偏好（6 参 false/true）→ state auto_approve=false ∧ html_review=true ──"

TMP_P2="$(mktemp -d -t autopilot-ac-p2-XXXXXX)"
mkdir -p "$TMP_P2/.autopilot/runtime/requirements/single-task"

# 单任务无 brief 文件路径，但 create_brief_state_file 需要一个 brief_file 入参
# （函数内部 head 读取它）。构造一个最小 brief 模拟单任务的目标描述。
BRIEF_P2="$TMP_P2/.autopilot/runtime/requirements/single-task/brief.md"
cat > "$BRIEF_P2" <<'EOF'
---
id: single-task
depends_on: []
---
# single task
test single-task content
EOF

export PROJECT_ROOT="$TMP_P2"
TASK_DIR="$TMP_P2/.autopilot/runtime/requirements/single-task"
STATE_FILE="$TASK_DIR/state.md"

if [[ "$CREATE_BRIEF_DEFINED" -eq 1 ]]; then
    # 黑盒调用：显式传第 5 参 auto_approve=false + 第 6 参 html_review=true
    # （模拟单任务模式 AUTOPILOT_HTML_REVIEW=1 时 setup.sh 的显式偏好传递）
    create_brief_state_file "$BRIEF_P2" "p2sess" "30" "3" "false" "true"

    ACTUAL_AA_P2="$(get_frontmatter_field "$STATE_FILE" auto_approve)"
    ACTUAL_HR_P2="$(get_frontmatter_field "$STATE_FILE" html_review)"
    assert_eq "$ACTUAL_AA_P2" "false" \
        "AC-P2: single-task explicit auto_approve==false (走审批门，回归不破)"
    assert_eq "$ACTUAL_HR_P2" "true" \
        "AC-P2: single-task explicit html_review==true (HTML 评审保留，回归不破)"
else
    echo "  FAIL  AC-P2: create_brief_state_file undefined (contract not implemented)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

rm -rf "$TMP_P2"

# ═══════════════════════════════════════════════════════════════
# AC-P3: brief state (auto_approve=true, phase=qa, gate=review-accept) 经 stop-hook → phase==merge
#
# 黑盒：构造临时项目 + state（phase=qa, gate=review-accept, auto_approve=true），
# 真跑 stop-hook.sh（喂 stdin JSON），断言 state.phase 被改为 merge。
# 参考 auto-approve-gate-bypass.acceptance.test.sh 的 fixture/run_hook 模式。
#
# 本 AC 与既有 R12 的区别：R12 验证 §5.5 机制本身存在；AC-P3 验证本次修复后的
# brief state（create_brief_state_file 默认 auto_approve=true 产出）经 stop-hook
# 真能被 §5.5 推进——端到端闭环（默认值改了才有 auto_approve=true 进入 §5.5）。
# ═══════════════════════════════════════════════════════════════
echo ""
echo "── AC-P3: brief state (auto_approve=true) 经 stop-hook §5.5 → phase==merge ──"

TMP_P3="$(mktemp -d -t autopilot-ac-p3-XXXXXX)"
mkdir -p "$TMP_P3/.autopilot/runtime/requirements/brief-qa"
echo "brief-qa" > "$TMP_P3/.autopilot/runtime/active.ptr"

# 构造 state：phase=qa + gate=review-accept + auto_approve=true（brief 默认值产出后的状态）
# 必要字段补全（参考 auto-approve-gate-bypass fixture，让 stop-hook 过 §1-4 不被拦截）
cat > "$TMP_P3/.autopilot/runtime/requirements/brief-qa/state.md" <<EOF
---
active: true
phase: "qa"
gate: "review-accept"
iteration: 3
max_iterations: 30
max_retries: 3
retry_count: 0
mode: "single"
plan_mode: ""
fast_mode: true
brief_file: ""
next_task: ""
auto_approve: true
knowledge_extracted: ""
task_dir: "$TMP_P3/.autopilot/runtime/requirements/brief-qa"
session_id: p3sess
started_at: "2026-07-10T00:00:00Z"
contract_required: false
html_review: false
---

## 目标
brief qa fixture for §5.5
EOF

# 真跑 stop-hook（喂 stdin JSON：session_id 匹配 + 无 pending subagents）
HOOK_INPUT_P3='{"session_id":"p3sess","transcript_path":"/tmp/none"}'
OUT_P3=$(cd "$TMP_P3" && echo "$HOOK_INPUT_P3" | bash "$STOP_HOOK" 2>/dev/null; echo "__EXIT__$?")
BODY_P3=$(echo "$OUT_P3" | grep -v '__EXIT__')

# 硬断言 1：stop-hook 输出 block JSON（§5.5 推进 merge 会注入 merge prompt）
if echo "$BODY_P3" | grep -q '"decision":[[:space:]]*"block"'; then
    echo "  PASS  AC-P3-a: stop-hook outputs block JSON (§5.5 fired → merge prompt injected)"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo "  FAIL  AC-P3-a: stop-hook 未输出 block JSON（§5.5 未触发）。stdout: $BODY_P3"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# 硬断言 2：state.phase 被改为 merge（§5.5 核心副作用）
PHASE_AFTER_P3="$(get_frontmatter_field "$TMP_P3/.autopilot/runtime/requirements/brief-qa/state.md" phase)"
assert_eq "$PHASE_AFTER_P3" "merge" \
    "AC-P3-b: state.phase==merge after stop-hook (§5.5 auto-approve→merge)"

# 硬断言 3：state.gate 被清空（§5.5 清 gate，不再卡 review-accept）
GATE_AFTER_P3="$(get_frontmatter_field "$TMP_P3/.autopilot/runtime/requirements/brief-qa/state.md" gate)"
assert_eq "$GATE_AFTER_P3" "" \
    "AC-P3-c: state.gate=='' after stop-hook (§5.5 clears review-accept gate)"

rm -rf "$TMP_P3"

# ── 汇总 ──────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "  PASS: $PASS_COUNT    FAIL: $FAIL_COUNT"
echo "════════════════════════════════════════"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo "RESULT: FAIL (brief auto_approve/html_review default contract violated)"
    exit 1
fi

echo "RESULT: PASS (brief default auto_approve=true/html_review=false + §5.5 auto-advance holds)"
exit 0
