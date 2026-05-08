#!/usr/bin/env bash
# R10: autopilot design 步骤 4「HTML 评审路径」验收测试
# 红队测试 — 仅基于设计文档编写，不读取蓝队实现代码
#
# 设计文档来源：
#   .autopilot/requirements/20260508-可以，按照-AskUserQuestio/state.md § 设计文档
#
# 覆盖范围（5 个核心契约）：
#   C1.  wait-decision.sh 脚本级单测：mock events → stdout 输出匹配 JSON；超时退出非 0
#   C2.  HTML 模板静态结构：plan-review-template.html 存在 textarea#feedback + 三按钮
#   C3.  SKILL.md 步骤 4 分支逻辑：html_review 开关描述 + 默认路径 hint 文案
#   C4.  state-file-guide.md：html_review frontmatter 字段说明存在
#   C5.  版本号同步至 v3.22.0（plugin.json + marketplace.json + CLAUDE.md 三处）
#
# 注意：场景 3/4（端到端浏览器）需人工操作，不在本脚本内；见 acceptance-checklist.md
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

VISUAL_DIR="$REPO_ROOT/plugins/autopilot/scripts/visual-companion"
WAIT_DECISION_SH="$VISUAL_DIR/wait-decision.sh"
PLAN_REVIEW_HTML="$VISUAL_DIR/plan-review-template.html"
SKILL_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/SKILL.md"
STATE_GUIDE="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/state-file-guide.md"
PLUGIN_JSON="$REPO_ROOT/plugins/autopilot/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"

TARGET_VERSION="3.22.0"

# ── 辅助函数 ─────────────────────────────────────────────────────────────────
pass() { echo "[PASS] R10: $1"; }
fail() {
    echo "[FAIL] R10: $1" >&2
    exit 1
}

# ── 前置：关键文件存在性检查 ──────────────────────────────────────────────────
echo "---- 前置检查：文件存在性 ----"
[[ -f "$WAIT_DECISION_SH" ]]   || fail "wait-decision.sh 不存在: $WAIT_DECISION_SH"
[[ -f "$PLAN_REVIEW_HTML" ]]   || fail "plan-review-template.html 不存在: $PLAN_REVIEW_HTML"
[[ -f "$SKILL_FILE" ]]         || fail "SKILL.md 不存在: $SKILL_FILE"
[[ -f "$STATE_GUIDE" ]]        || fail "state-file-guide.md 不存在: $STATE_GUIDE"
[[ -f "$PLUGIN_JSON" ]]        || fail "plugin.json 不存在: $PLUGIN_JSON"
[[ -f "$MARKETPLACE_JSON" ]]   || fail "marketplace.json 不存在: $MARKETPLACE_JSON"
[[ -f "$CLAUDE_MD" ]]          || fail "CLAUDE.md 不存在: $CLAUDE_MD"
pass "前置：所有必需文件存在"

# ════════════════════════════════════════════════════════════════════════════
# 契约 C1：wait-decision.sh 脚本级单测
#   设计文档：tail -F events | grep -m1，匹配 choice 行直接 echo 给 stdout
#   改进建议：stdout 非空且为合法 JSON 作为成功判据，不依赖退出码
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "---- C1: wait-decision.sh 脚本级单测 ----"

# C1a: 脚本本身有执行权限
if [[ ! -x "$WAIT_DECISION_SH" ]]; then
    fail "C1: wait-decision.sh 无执行权限（期望 chmod +x）"
fi
pass "C1a: wait-decision.sh 有执行权限"

# C1b: 接受 state_dir 参数（help/usage 或能正常启动）
# 策略：用超时 2s 快速超时，检查退出码 != 2（参数错误）
test_dir_c1="$(mktemp -d /tmp/td-c1-XXXXXX)"
test_state_dir="$test_dir_c1/state"
mkdir -p "$test_state_dir"
touch "$test_state_dir/events"

# C1c: 注入 approve 事件 → stdout 出现该 JSON 行
# 启动 wait-decision.sh（超时 5s），在后台注入事件后检查 stdout
actual_output=""
actual_output="$(
    # 后台等 1s 再注入事件，让 wait-decision 先启动 tail
    (sleep 1 && printf '{"type":"click","choice":"approve","feedback":"LGTM"}\n' >> "$test_state_dir/events") &
    INJECT_PID=$!
    # 运行 wait-decision.sh，超时 5s（可参数覆盖）
    result="$(bash "$WAIT_DECISION_SH" "$test_state_dir" 5 2>/dev/null)"
    wait "$INJECT_PID" 2>/dev/null || true
    echo "$result"
)"

if [[ -z "$actual_output" ]]; then
    fail "C1c: wait-decision.sh stdout 为空（期望：输出注入的 approve JSON 行）"
fi
pass "C1c: wait-decision.sh stdout 非空（收到事件行）"

# C1d: stdout 输出的内容包含 choice=approve（合法 JSON 或至少含 approve 子串）
if ! echo "$actual_output" | grep -q '"approve"'; then
    fail "C1d: wait-decision.sh stdout '${actual_output}' 不含 choice:approve（期望：输出原始 approve JSON 行）"
fi
pass "C1d: wait-decision.sh stdout 含 \"approve\"（choice 字段正确）"

# C1e: stdout 包含 feedback 值（end-to-end feedback 传递验证）
if ! echo "$actual_output" | grep -q '"feedback"'; then
    fail "C1e: wait-decision.sh stdout 不含 feedback 字段（期望：helper.js 注入 feedback 到事件 payload）"
fi
pass "C1e: stdout 含 feedback 字段"

# C1f: stdout 是合法 JSON（能被解析）
if ! echo "$actual_output" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    fail "C1f: wait-decision.sh stdout '${actual_output}' 不是合法 JSON（期望：整行为 JSON）"
fi
pass "C1f: stdout 是合法 JSON"

# C1g: 超时场景 → 退出码非 0（设计文档：超时返回非 0 退出码）
# 注意设计改进建议：成功时 exit code 也可能非 0（管道 timeout 行为）
# 但超时场景必须是「stdout 为空 AND 非 0 exit」，以此区分超时
timeout_dir="$(mktemp -d /tmp/td-c1-timeout-XXXXXX)"
mkdir -p "$timeout_dir"
touch "$timeout_dir/events"
timeout_exit=0
timeout_output="$(bash "$WAIT_DECISION_SH" "$timeout_dir" 2 2>/dev/null)" || timeout_exit=$?

if [[ -n "$timeout_output" ]]; then
    fail "C1g: 超时场景下 wait-decision.sh stdout 非空（期望：超时时 stdout 为空）"
fi
if [[ "$timeout_exit" -eq 0 ]]; then
    fail "C1g: 超时场景下 wait-decision.sh 退出码为 0（期望：超时返回非 0）"
fi
pass "C1g: 超时场景 stdout 为空 且 退出码 $timeout_exit != 0"

# C1h: revise choice 同样被正确输出（验证不只支持 approve）
test_dir_revise="$(mktemp -d /tmp/td-c1-revise-XXXXXX)"
mkdir -p "$test_dir_revise"
touch "$test_dir_revise/events"
revise_output="$(
    (sleep 1 && printf '{"type":"click","choice":"revise","feedback":"请用 ESM"}\n' >> "$test_dir_revise/events") &
    bash "$WAIT_DECISION_SH" "$test_dir_revise" 5 2>/dev/null
    wait 2>/dev/null || true
)"
if ! echo "$revise_output" | grep -q '"revise"'; then
    fail "C1h: revise 事件未被 wait-decision.sh 输出（期望：支持 approve/revise/abort 三种 choice）"
fi
pass "C1h: revise choice 正确输出"

# C1i: abort choice 同样被正确输出
test_dir_abort="$(mktemp -d /tmp/td-c1-abort-XXXXXX)"
mkdir -p "$test_dir_abort"
touch "$test_dir_abort/events"
abort_output="$(
    (sleep 1 && printf '{"type":"click","choice":"abort","feedback":""}\n' >> "$test_dir_abort/events") &
    bash "$WAIT_DECISION_SH" "$test_dir_abort" 5 2>/dev/null
    wait 2>/dev/null || true
)"
if ! echo "$abort_output" | grep -q '"abort"'; then
    fail "C1i: abort 事件未被 wait-decision.sh 输出（期望：支持 approve/revise/abort 三种 choice）"
fi
pass "C1i: abort choice 正确输出"

# 清理
rm -rf "$test_dir_c1" "$timeout_dir" "$test_dir_revise" "$test_dir_abort"

# ════════════════════════════════════════════════════════════════════════════
# 契约 C2：plan-review-template.html 静态结构
#   设计文档：textarea#feedback + 三个 data-choice 按钮 (approve/revise/abort)
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "---- C2: plan-review-template.html 静态结构 ----"

# C2a: textarea#feedback 存在
if ! grep -qi 'id="feedback"\|id=.feedback.' "$PLAN_REVIEW_HTML"; then
    fail "C2a: plan-review-template.html 不含 textarea#feedback（设计要求: id=\"feedback\"）"
fi
pass "C2a: 含 id=\"feedback\" 元素"

# C2b: data-choice="approve" 按钮存在
if ! grep -qi 'data-choice="approve"\|data-choice=.approve.' "$PLAN_REVIEW_HTML"; then
    fail "C2b: plan-review-template.html 不含 data-choice=\"approve\" 按钮"
fi
pass "C2b: 含 data-choice=\"approve\" 按钮"

# C2c: data-choice="revise" 按钮存在
if ! grep -qi 'data-choice="revise"\|data-choice=.revise.' "$PLAN_REVIEW_HTML"; then
    fail "C2c: plan-review-template.html 不含 data-choice=\"revise\" 按钮"
fi
pass "C2c: 含 data-choice=\"revise\" 按钮"

# C2d: data-choice="abort" 按钮存在
if ! grep -qi 'data-choice="abort"\|data-choice=.abort.' "$PLAN_REVIEW_HTML"; then
    fail "C2d: plan-review-template.html 不含 data-choice=\"abort\" 按钮"
fi
pass "C2d: 含 data-choice=\"abort\" 按钮"

# C2e: 设计文档主体渲染区域（v3.22 用 <pre>，v3.22 用 <div id="design-content"> + marked.js）
if ! grep -qiE '<pre|id="design-content"' "$PLAN_REVIEW_HTML"; then
    fail "C2e: plan-review-template.html 不含设计文档主体渲染区域（应有 <pre> 或 <div id=\"design-content\">）"
fi
pass "C2e: 含设计文档主体渲染区域"

# C2h: marked.js 渲染机制（v3.22）— marked.min.js 文件存在 + 模板含 marked.parse 调用
MARKED_LIB="$VISUAL_DIR/marked.min.js"
if [[ ! -f "$MARKED_LIB" ]]; then
    fail "C2h: marked.min.js 不存在（v3.22 设计要求：内嵌 markdown 渲染库到 visual-companion）"
fi
if ! grep -q "marked.parse" "$PLAN_REVIEW_HTML"; then
    fail "C2h: plan-review-template.html 不含 marked.parse 调用（v3.22 设计要求：用 marked 渲染 markdown）"
fi
if ! grep -q "{{MARKED_LIB}}" "$PLAN_REVIEW_HTML"; then
    fail "C2h: plan-review-template.html 不含 {{MARKED_LIB}} 占位符（运行时由 launch-plan-review.sh 注入）"
fi
pass "C2h: marked.js 渲染机制就位（marked.min.js 存在 + 模板含 marked.parse + {{MARKED_LIB}} 占位）"

# C2f: HTML 模板含 helper.js 注入或 WebSocket 接入点
# 设计文档：复用 server.cjs 的 helperInjection 机制（server 自动在 </body> 前注入 helper.js）
# 模板本身不需要手动引用 helper.js，但需要是合法 HTML 结构（含 </body> 以便 server 注入）
if ! grep -qi '</body>' "$PLAN_REVIEW_HTML"; then
    fail "C2f: plan-review-template.html 不含 </body>（server.cjs 需要此标签自动注入 helper.js）"
fi
pass "C2f: 含 </body> 标签（server.cjs 可自动注入 helper.js）"

# C2g: 模板含任务标题占位（设计文档：顶部任务标题）
if ! grep -qiE 'title|task|任务|标题|TASK_TITLE|PLAN_TITLE' "$PLAN_REVIEW_HTML"; then
    fail "C2g: plan-review-template.html 不含任务标题占位（设计要求：顶部任务标题）"
fi
pass "C2g: 含任务标题占位区域"

# ════════════════════════════════════════════════════════════════════════════
# 契约 C3：SKILL.md 步骤 4 分支逻辑 + 默认路径 preview hint
#   设计文档：
#   - 步骤 4 检查 html_review 开关 (frontmatter > env > default false)
#   - 默认路径 preview 末尾追加 AUTOPILOT_HTML_REVIEW=1 提示
#   - 开启路径调用 launch-plan-review.sh
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "---- C3: SKILL.md 步骤 4 分支逻辑 ----"

# C3a: SKILL.md 含 html_review 开关检查
if ! grep -q "html_review" "$SKILL_FILE"; then
    fail "C3a: SKILL.md 不含 html_review 开关描述（设计要求：步骤 4 检查 html_review 开关）"
fi
pass "C3a: SKILL.md 含 html_review 关键词"

# C3b: SKILL.md 含 AUTOPILOT_HTML_REVIEW 环境变量引用
if ! grep -q "AUTOPILOT_HTML_REVIEW" "$SKILL_FILE"; then
    fail "C3b: SKILL.md 不含 AUTOPILOT_HTML_REVIEW 环境变量（设计要求：env AUTOPILOT_HTML_REVIEW=1 开启）"
fi
pass "C3b: SKILL.md 含 AUTOPILOT_HTML_REVIEW 环境变量引用"

# C3c: SKILL.md 含 launch-plan-review.sh 调用说明
if ! grep -q "launch-plan-review" "$SKILL_FILE"; then
    fail "C3c: SKILL.md 不含 launch-plan-review 脚本引用（设计要求：HTML 开启时调用 launch-plan-review.sh）"
fi
pass "C3c: SKILL.md 含 launch-plan-review 脚本引用"

# C3d: SKILL.md 默认路径 preview 末尾含开启 HTML 评审的 hint 文案
# 设计文档：preview 末尾追加「💡 启用 HTML 评审：设置 AUTOPILOT_HTML_REVIEW=1 或 frontmatter html_review: true」
if ! grep -q "AUTOPILOT_HTML_REVIEW" "$SKILL_FILE"; then
    fail "C3d: SKILL.md preview hint 区域缺少 AUTOPILOT_HTML_REVIEW hint 文案"
fi

# C3e: 具体检查 hint 包含 =1 的示例（明确告知用户如何开启）
if ! grep -qE "AUTOPILOT_HTML_REVIEW.*=.*1|AUTOPILOT_HTML_REVIEW=1" "$SKILL_FILE"; then
    fail "C3e: SKILL.md 不含 AUTOPILOT_HTML_REVIEW=1 的具体示例（设计要求：hint 说明具体设置值）"
fi
pass "C3e: SKILL.md 含 AUTOPILOT_HTML_REVIEW=1 开启示例"

# C3f: frontmatter html_review 优先级描述（设计：frontmatter > env > false）
if ! grep -qE "html_review.*true|frontmatter.*html_review|html_review.*frontmatter" "$SKILL_FILE"; then
    fail "C3f: SKILL.md 不含 frontmatter html_review: true 覆盖说明（设计要求：frontmatter > env 优先级）"
fi
pass "C3f: SKILL.md 含 frontmatter html_review 优先级说明"

# C3g: 超时降级逻辑说明（设计文档：wait-decision 超时 → fallback AskUserQuestion + preview）
if ! grep -qiE "timeout|超时|fallback|降级" "$SKILL_FILE"; then
    fail "C3g: SKILL.md 不含超时降级逻辑描述（设计要求：wait-decision 超时 → fallback AskUserQuestion）"
fi
pass "C3g: SKILL.md 含超时降级逻辑描述"

# C3h: 前台同步调用 + bash timeout=600000 调用规范（避免后台调用导致用户二次操作）
HTML_REVIEW_GUIDE="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/html-review-guide.md"
if ! grep -qE "前台同步|run_in_background|600000" "$SKILL_FILE"; then
    fail "C3h: SKILL.md 不含「前台同步 / 禁用 run_in_background / timeout=600000」调用规范"
fi
pass "C3h: SKILL.md 含前台同步调用规范"

if [[ ! -f "$HTML_REVIEW_GUIDE" ]] || ! grep -qE "前台同步|run_in_background|600000" "$HTML_REVIEW_GUIDE"; then
    fail "C3i: html-review-guide.md 不存在或不含「前台同步 / 禁用 run_in_background / timeout=600000」调用规范"
fi
pass "C3i: html-review-guide.md 含前台同步调用规范"

# ════════════════════════════════════════════════════════════════════════════
# 契约 C4：state-file-guide.md 含 html_review frontmatter 字段说明
#   设计文档：frontmatter 增加 html_review: false 字段说明
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "---- C4: state-file-guide.md frontmatter 字段 ----"

# C4a: html_review 字段名存在于 state-file-guide.md
if ! grep -q "html_review" "$STATE_GUIDE"; then
    fail "C4a: state-file-guide.md 不含 html_review 字段说明（设计要求：frontmatter 新增 html_review: false 字段）"
fi
pass "C4a: state-file-guide.md 含 html_review 字段"

# C4b: 默认值为 false（设计文档：默认关闭）
if ! grep -E "html_review" "$STATE_GUIDE" | grep -q "false"; then
    fail "C4b: state-file-guide.md html_review 字段说明不含默认值 false（设计要求：默认关闭）"
fi
pass "C4b: html_review 字段说明含默认值 false"

# ════════════════════════════════════════════════════════════════════════════
# 契约 C5：版本号同步至 v3.22.0
#   设计文档：plugin.json + marketplace.json + CLAUDE.md（package.json 不存在，跳过）
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "---- C5: 版本号同步至 v3.22.0 ----"

# C5a: plugin.json 版本
plugin_version=$(grep '"version"' "$PLUGIN_JSON" \
    | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' \
    | head -1)
if [[ "$plugin_version" != "$TARGET_VERSION" ]]; then
    fail "C5a: plugin.json 版本 '$plugin_version' != 期望 '$TARGET_VERSION'"
fi
pass "C5a: plugin.json 版本 = $TARGET_VERSION"

# C5b: marketplace.json autopilot 条目版本
marketplace_version=$(python3 -c "
import json
data = json.load(open('$MARKETPLACE_JSON'))
plugins = data if isinstance(data, list) else data.get('plugins', [])
for p in plugins:
    if p.get('name') == 'autopilot':
        print(p.get('version', ''))
        break
" 2>/dev/null || true)

[[ -n "$marketplace_version" ]] || fail "C5b: marketplace.json 中找不到 autopilot 条目的 version 字段"
if [[ "$marketplace_version" != "$TARGET_VERSION" ]]; then
    fail "C5b: marketplace.json autopilot 版本 '$marketplace_version' != 期望 '$TARGET_VERSION'"
fi
pass "C5b: marketplace.json autopilot 版本 = $TARGET_VERSION"

# C5c: CLAUDE.md 插件索引表 autopilot 行版本
if ! grep -E "autopilot" "$CLAUDE_MD" | grep -qE "v${TARGET_VERSION}|${TARGET_VERSION}"; then
    fail "C5c: CLAUDE.md 插件索引表 autopilot 行未找到版本 v${TARGET_VERSION}"
fi
pass "C5c: CLAUDE.md 插件索引表 autopilot 行版本 = v${TARGET_VERSION}"

# C5d: 三处版本一致
if [[ "$plugin_version" != "$marketplace_version" ]]; then
    fail "C5d: plugin.json($plugin_version) 与 marketplace.json($marketplace_version) 版本不一致"
fi
pass "C5d: 三处版本号一致（${TARGET_VERSION}）"

# C5e: 版本确实比上一版（v3.21.0）更高
prev_version="3.21.0"
prev_minor=$(echo "$prev_version" | cut -d. -f2)
curr_minor=$(echo "$plugin_version" | cut -d. -f2)
prev_major=$(echo "$prev_version" | cut -d. -f1)
curr_major=$(echo "$plugin_version" | cut -d. -f1)
prev_patch=$(echo "$prev_version" | cut -d. -f3)
curr_patch=$(echo "$plugin_version" | cut -d. -f3)

is_greater=0
if [[ "$curr_major" -gt "$prev_major" ]]; then
    is_greater=1
elif [[ "$curr_major" -eq "$prev_major" ]] && [[ "$curr_minor" -gt "$prev_minor" ]]; then
    is_greater=1
elif [[ "$curr_major" -eq "$prev_major" ]] && [[ "$curr_minor" -eq "$prev_minor" ]] && [[ "$curr_patch" -gt "$prev_patch" ]]; then
    is_greater=1
fi

if [[ $is_greater -eq 0 ]]; then
    fail "C5e: 版本 $plugin_version 不高于上一版 ${prev_version}（期望：从 3.21.0 升级到 3.22.0）"
fi
pass "C5e: 版本 $plugin_version > $prev_version — 升级方向正确"

# ════════════════════════════════════════════════════════════════════════════
# 附加：helper.js 含 feedback textarea 读取逻辑
#   设计文档：helper.js click 事件捕获时附加读取 #feedback textarea 内容
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "---- 附加 C6: helper.js feedback 读取逻辑 ----"

HELPER_JS="$VISUAL_DIR/helper.js"
[[ -f "$HELPER_JS" ]] || fail "C6: helper.js 不存在: $HELPER_JS"

# C6a: helper.js 含 feedback 读取逻辑（getElementById 或 querySelector 读取 #feedback）
if ! grep -qE 'feedback|getElementById.*feedback|querySelector.*feedback' "$HELPER_JS"; then
    fail "C6a: helper.js 不含 #feedback 读取逻辑（设计要求：click 事件时附加 feedback 内容到 payload，约 6 行）"
fi
pass "C6a: helper.js 含 feedback 读取逻辑"

# C6b: feedback 值通过 sendEvent 发出（包含在事件 payload 中）
# 验证：sendEvent 调用时包含 feedback 字段
if ! grep -B5 -A5 "sendEvent" "$HELPER_JS" | grep -qiE "feedback"; then
    fail "C6b: helper.js sendEvent 调用不含 feedback 字段（设计要求：附加 feedback 到 event payload）"
fi
pass "C6b: helper.js sendEvent 调用包含 feedback 字段"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "[OK ] R10 plan-review-html — 全部自动化断言通过"
echo "      注：端到端浏览器测试（场景 3/4）见 acceptance-checklist.md，需人工/QA 执行"
exit 0
