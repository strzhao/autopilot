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
#   C5.  版本号同步至当前 TARGET_VERSION（plugin.json + marketplace.json + CLAUDE.md 三处）
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

TARGET_VERSION="3.28.0"

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
# 契约 C5：版本号同步至 $TARGET_VERSION
#   设计文档：plugin.json + marketplace.json + CLAUDE.md（package.json 不存在，跳过）
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "---- C5: 版本号同步至 v${TARGET_VERSION} ----"

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
prev_version="3.27.1"
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
    fail "C5e: 版本 $plugin_version 不高于上一版 ${prev_version}（期望：从 3.26.1 升级到 3.27.0）"
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
# 契约 C7：prefs.cjs 模块契约（依据 C-prefs）
#   设计文档：新建 scripts/visual-companion/prefs.cjs，导出 load/save/getPref/setPref/PREFS_FILE
#   持久化路径：~/.autopilot/prefs.json（os.homedir() 拼接）
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "---- C7: prefs.cjs 模块契约 ----"

PREFS_CJS="$VISUAL_DIR/prefs.cjs"

# C7a: prefs.cjs 文件存在
if [[ ! -f "$PREFS_CJS" ]]; then
    fail "C7a: scripts/visual-companion/prefs.cjs 不存在（设计要求：新建偏好读写模块）"
fi
pass "C7a: prefs.cjs 文件存在"

# C7b: module.exports 导出五个 API：getPref / setPref / load / save / PREFS_FILE
for api_name in getPref setPref load save PREFS_FILE; do
    if ! grep -q "module\.exports" "$PREFS_CJS"; then
        fail "C7b: prefs.cjs 不含 module.exports（设计要求：CommonJS 导出）"
    fi
    if ! grep -E "module\.exports|exports\." "$PREFS_CJS" | grep -qF "$api_name"; then
        fail "C7b: prefs.cjs module.exports 未导出 '$api_name'（设计要求：导出 getPref/setPref/load/save/PREFS_FILE 五个 API）"
    fi
done
pass "C7b: prefs.cjs module.exports 导出 getPref/setPref/load/save/PREFS_FILE 全部五个 API"

# C7c: 单测 — mock HOME 到临时目录，文件不存在时 getPref 返回 defaultValue=true
tmp_home_c7c="$(mktemp -d /tmp/prefs-XXXXXX)"
c7c_result="$(HOME="$tmp_home_c7c" node -e "
const p = require('$PREFS_CJS');
const val = p.getPref('auto_close_after_decision', true);
if (val !== true) {
  process.stderr.write('FAIL: expected true, got ' + JSON.stringify(val) + '\n');
  process.exit(1);
}
console.log('OK:' + val);
" 2>&1)" || {
    rm -rf "$tmp_home_c7c"
    fail "C7c: 文件不存在时 getPref('auto_close_after_decision', true) 未返回 true（实际：$c7c_result）"
}
rm -rf "$tmp_home_c7c"
pass "C7c: 文件不存在时 getPref 返回 defaultValue=true（不抛异常）"

# C7d: 单测 — setPref 后 getPref 返回值与 set 的值严格相等（boolean）
tmp_home_c7d="$(mktemp -d /tmp/prefs-XXXXXX)"
c7d_result="$(HOME="$tmp_home_c7d" node -e "
const p = require('$PREFS_CJS');
p.setPref('auto_close_after_decision', false);
const val = p.getPref('auto_close_after_decision', true);
if (val !== false) {
  process.stderr.write('FAIL: expected false, got ' + JSON.stringify(val) + '\n');
  process.exit(1);
}
console.log('OK:' + val);
" 2>&1)" || {
    rm -rf "$tmp_home_c7d"
    fail "C7d: setPref(false) 后 getPref 返回值不是严格的 false（实际：$c7d_result）"
}
rm -rf "$tmp_home_c7d"
pass "C7d: setPref(false) 后 getPref 返回严格 false（boolean 严格相等）"

# C7e: 损坏 JSON 降级 — 写 {broken 到 prefs 文件，调 getPref 返回 defaultValue 且不抛异常
tmp_home_c7e="$(mktemp -d /tmp/prefs-XXXXXX)"
mkdir -p "$tmp_home_c7e/.autopilot"
printf '{broken' > "$tmp_home_c7e/.autopilot/prefs.json"
c7e_result="$(HOME="$tmp_home_c7e" node -e "
const p = require('$PREFS_CJS');
let val;
try {
  val = p.getPref('auto_close_after_decision', 'FALLBACK');
} catch(e) {
  process.stderr.write('FAIL: threw exception: ' + e.message + '\n');
  process.exit(1);
}
if (val !== 'FALLBACK') {
  process.stderr.write('FAIL: expected FALLBACK, got ' + JSON.stringify(val) + '\n');
  process.exit(1);
}
console.log('OK:' + val);
" 2>&1)" || {
    rm -rf "$tmp_home_c7e"
    fail "C7e: 损坏 JSON 时 getPref 未静默降级为 defaultValue（实际：$c7e_result）"
}
rm -rf "$tmp_home_c7e"
pass "C7e: 损坏 JSON 时 getPref 静默降级为 defaultValue，不抛异常"

# C7f: 字段名 auto_close_after_decision 在 prefs.cjs 中有引用（DEFAULTS 或文档注释）
if ! grep -q "auto_close_after_decision" "$PREFS_CJS"; then
    fail "C7f: prefs.cjs 不含字段名 auto_close_after_decision（设计要求：DEFAULTS 或注释中引用）"
fi
pass "C7f: prefs.cjs 含字段名 auto_close_after_decision"

# ════════════════════════════════════════════════════════════════════════════
# 契约 C8：HTML 模板新元素契约（依据 C-template-placeholders + C-dom-contract）
#   设计文档：新增 {{AUTO_CLOSE_PREF}} 占位符 + data-auto-close + data-pref 标记
#             + overlay 元素 + pref-update 事件 + window.brainstorm.send + window.close
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "---- C8: plan-review-template.html 新元素契约 ----"

# C8a: 模板含 {{AUTO_CLOSE_PREF}} 占位符（唯一新占位符）
if ! grep -qF '{{AUTO_CLOSE_PREF}}' "$PLAN_REVIEW_HTML"; then
    fail "C8a: plan-review-template.html 不含 {{AUTO_CLOSE_PREF}} 占位符（设计要求：新增唯一偏好注入占位）"
fi
pass "C8a: 含 {{AUTO_CLOSE_PREF}} 占位符"

# C8b: 模板含 data-auto-close="{{AUTO_CLOSE_PREF}}" 注入位置契约
if ! grep -qF 'data-auto-close="{{AUTO_CLOSE_PREF}}"' "$PLAN_REVIEW_HTML"; then
    fail "C8b: plan-review-template.html 不含 data-auto-close=\"{{AUTO_CLOSE_PREF}}\"（设计要求：body 上注入 data-auto-close 属性）"
fi
pass "C8b: 含 data-auto-close=\"{{AUTO_CLOSE_PREF}}\" 注入位置"

# C8c: 模板含 data-pref="auto_close_after_decision" 标记的元素
if ! grep -qF 'data-pref="auto_close_after_decision"' "$PLAN_REVIEW_HTML"; then
    fail "C8c: plan-review-template.html 不含 data-pref=\"auto_close_after_decision\" 元素（设计要求：开关元素需含此标记）"
fi
pass "C8c: 含 data-pref=\"auto_close_after_decision\" 标记的开关元素"

# C8d: 模板不含 {{AUTO_CLOSE_PREF_CHECKED}} 等变体占位符（防止占位符二义性回归）
if grep -qF '{{AUTO_CLOSE_PREF_CHECKED}}' "$PLAN_REVIEW_HTML"; then
    fail "C8d: plan-review-template.html 含禁止使用的占位符 {{AUTO_CLOSE_PREF_CHECKED}}（设计要求：只允许 {{AUTO_CLOSE_PREF}} 一个新占位）"
fi
pass "C8d: 不含 {{AUTO_CLOSE_PREF_CHECKED}} 等禁止变体占位符"

# C8e: 模板含 overlay 元素（submit-overlay 或含 overlay 关键字）
if ! grep -qiE 'submit-overlay|id="[^"]*overlay[^"]*"|class="[^"]*overlay[^"]*"' "$PLAN_REVIEW_HTML"; then
    fail "C8e: plan-review-template.html 不含 overlay 元素（设计要求：决策后显示全屏反馈 overlay）"
fi
pass "C8e: 含 overlay 元素（提交反馈用）"

# C8f: 模板含 window.brainstorm.send 调用（pref-update 通过它发送）
if ! grep -q "window\.brainstorm\.send" "$PLAN_REVIEW_HTML"; then
    fail "C8f: plan-review-template.html 不含 window.brainstorm.send 调用（设计要求：pref-update 通过 brainstorm.send 发送）"
fi
pass "C8f: 含 window.brainstorm.send 调用"

# C8g: 模板含 pref-update 字符串（事件类型字面量）
if ! grep -q "pref-update" "$PLAN_REVIEW_HTML"; then
    fail "C8g: plan-review-template.html 不含 pref-update 字符串（设计要求：WS 消息 type 字面量）"
fi
pass "C8g: 含 pref-update 事件类型字面量"

# C8h: 模板含 window.close 调用（auto-close 实现）
if ! grep -q "window\.close" "$PLAN_REVIEW_HTML"; then
    fail "C8h: plan-review-template.html 不含 window.close 调用（设计要求：auto-close 内嵌脚本）"
fi
pass "C8h: 含 window.close 调用（auto-close 实现）"

# ════════════════════════════════════════════════════════════════════════════
# 契约 C9：launch-plan-review.sh 渲染注入契约
#   设计文档：渲染前 node -e 读偏好，python 脚本替换 {{AUTO_CLOSE_PREF}} 占位
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "---- C9: launch-plan-review.sh 渲染注入契约 ----"

LAUNCH_SH="$VISUAL_DIR/launch-plan-review.sh"

# C9a: 脚本含 prefs.cjs 引用
if ! grep -qE "prefs\.cjs|require.*prefs" "$LAUNCH_SH"; then
    fail "C9a: launch-plan-review.sh 不含 prefs.cjs 引用（设计要求：渲染前调用 prefs.cjs 读偏好）"
fi
pass "C9a: launch-plan-review.sh 含 prefs.cjs 引用"

# C9b: 脚本含 AUTO_CLOSE_PREF 字面量（变量名或占位符替换）
if ! grep -q "AUTO_CLOSE_PREF" "$LAUNCH_SH"; then
    fail "C9b: launch-plan-review.sh 不含 AUTO_CLOSE_PREF 字面量（设计要求：渲染时替换 {{AUTO_CLOSE_PREF}} 占位）"
fi
pass "C9b: launch-plan-review.sh 含 AUTO_CLOSE_PREF 字面量"

# C9c: 单测 — mock HOME + mock state.md，跑 launch-plan-review.sh，验证渲染后 HTML 中
#      {{AUTO_CLOSE_PREF}} 已被替换为 true 或 false（不再是字面占位符）
#      注意：脚本会启动 server 并阻塞，用 timeout 5 包装；测试结束后 kill server
echo ""
echo "  C9c: 渲染注入单测（timeout 包装）..."

tmp_home_c9c="$(mktemp -d /tmp/c9c-home-XXXXXX)"
tmp_state_c9c="$(mktemp -d /tmp/c9c-state-XXXXXX)"
tmp_content_c9c="$(mktemp -d /tmp/c9c-content-XXXXXX)"

# 构造最小 mock state.md（frontmatter + 内容）
cat > "$tmp_state_c9c/state.md" << 'EOF'
---
active: true
phase: "implement"
gate: ""
---

## 目标
mock test plan review

## 设计文档
mock design content for C9c test
EOF

# 清理函数：kill server 进程
_c9c_cleanup() {
    pkill -f "visual-companion/server.cjs" 2>/dev/null || true
    lsof -ti:7654 2>/dev/null | xargs kill -9 2>/dev/null || true
    rm -rf "$tmp_home_c9c" "$tmp_state_c9c" "$tmp_content_c9c"
}
trap '_c9c_cleanup' EXIT

# 用 timeout 5 跑 launch-plan-review.sh；脚本会在等待决策时阻塞，timeout 会中断它
# 我们只关心 CONTENT_DIR 中渲染后的 plan-review.html 是否正确替换了占位符
# 先导出 CONTENT_DIR 让 launch-plan-review.sh 用（若其支持环境变量覆盖），否则读默认路径
export HOME="$tmp_home_c9c"
LAUNCH_SCRIPT="$LAUNCH_SH"

# 以 timeout 5 跑脚本，收集到 plan-review.html 路径
# launch-plan-review.sh 通常把 html 写到 $CONTENT_DIR 或脚本同目录临时目录
# 我们用子 shell 并捕获，超时后检查生成文件
c9c_rendered_html=""

# 尝试找脚本实际写入 HTML 的目录
# 从脚本自身 grep CONTENT_DIR 赋值行（不读实现，但可 grep 变量名确认存在）
if grep -q "CONTENT_DIR" "$LAUNCH_SH"; then
    # CONTENT_DIR 存在，尝试从脚本中找默认值模式（非强制，仅辅助）
    :
fi

# 用 timeout 5 运行脚本（阻塞部分会被 timeout 中断）
# 捕获 stdout/stderr；脚本超时时 exit=124，launch-plan-review.sh 期待 TASK_DIR 参数（不是 state.md 文件路径）
c9c_exit=0
c9c_output="$(HOME="$tmp_home_c9c" timeout 5 bash "$LAUNCH_SH" "$tmp_state_c9c" 2>&1)" || c9c_exit=$?

# 搜索渲染后的 plan-review.html：优先在 tmp_state_c9c 下（--project-dir 模式），再搜 /tmp
c9c_rendered_html="$(find "$tmp_state_c9c" -name "plan-review.html" 2>/dev/null | head -1)"

if [[ -z "$c9c_rendered_html" ]]; then
    c9c_rendered_html="$(find /tmp -name "plan-review.html" -newer "$tmp_state_c9c/state.md" -maxdepth 6 2>/dev/null | head -1)"
fi

if [[ -z "$c9c_rendered_html" ]]; then
    # 也尝试从 output 里提取路径提示
    c9c_rendered_html="$(echo "$c9c_output" | grep -oE '/[^ ]*/plan-review\.html' | head -1)"
fi

if [[ -z "$c9c_rendered_html" ]] || [[ ! -f "$c9c_rendered_html" ]]; then
    fail "C9c: launch-plan-review.sh 运行后未找到渲染后的 plan-review.html（output: $c9c_output）"
fi

# 验证 {{AUTO_CLOSE_PREF}} 已被替换（不再是字面量）
if grep -qF '{{AUTO_CLOSE_PREF}}' "$c9c_rendered_html"; then
    fail "C9c: 渲染后的 plan-review.html 仍含字面 {{AUTO_CLOSE_PREF}}，占位符未被替换（设计要求：渲染时替换为 true 或 false）"
fi

# 验证替换值是 true 或 false（data-auto-close 属性值）
if ! grep -qE 'data-auto-close="(true|false)"' "$c9c_rendered_html"; then
    fail "C9c: 渲染后的 plan-review.html data-auto-close 属性值不是 true/false（期望：data-auto-close=\"true\" 或 data-auto-close=\"false\"）"
fi

pass "C9c: launch-plan-review.sh 渲染后 {{AUTO_CLOSE_PREF}} 已替换为 true/false，占位符不再存在"

# 重置 EXIT trap（清理已在此完成）
trap - EXIT
_c9c_cleanup

# ════════════════════════════════════════════════════════════════════════════
# 契约 C10：server.cjs pref-update 处理契约
#   设计文档：server.cjs handleMessage 新增 pref-update 分支，require ./prefs.cjs，调 setPref
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "---- C10: server.cjs pref-update 处理契约 ----"

SERVER_CJS="$VISUAL_DIR/server.cjs"
[[ -f "$SERVER_CJS" ]] || fail "C10: server.cjs 不存在: $SERVER_CJS"

# C10a: server.cjs 含 require ./prefs.cjs 或 require ./prefs 引用
if ! grep -qE "require.*['\"].*prefs(\.cjs)?['\"]" "$SERVER_CJS"; then
    fail "C10a: server.cjs 不含 require('./prefs.cjs') 或 require('./prefs')（设计要求：server 引入偏好模块）"
fi
pass "C10a: server.cjs 含 require prefs.cjs 引用"

# C10b: server.cjs 含字面量 pref-update（消息类型分支）
if ! grep -q "pref-update" "$SERVER_CJS"; then
    fail "C10b: server.cjs 不含字面量 pref-update（设计要求：handleMessage 新增 pref-update 分支）"
fi
pass "C10b: server.cjs 含 pref-update 消息类型字面量"

# C10c: server.cjs 含 setPref 调用
if ! grep -q "setPref" "$SERVER_CJS"; then
    fail "C10c: server.cjs 不含 setPref 调用（设计要求：pref-update 分支调 prefs.setPref 落盘）"
fi
pass "C10c: server.cjs 含 setPref 调用"

# ════════════════════════════════════════════════════════════════════════════
# 契约 C11：渲染顺序污染防御（v3.27.1 hotfix 引入的回归防御）
#   背景：launch-plan-review.sh 用 python str.replace 全局替换占位符。
#   若 `{{DESIGN_CONTENT}}` 先注入，且 design 文档中字面引用了 `{{MARKED_LIB}}` /
#   `{{AUTO_CLOSE_PREF}}` 等占位符名（如契约规约章节），后续 replace 会把这些字面
#   也一起替换 → marked.min.js 被重复注入到 design content 内 → marked.parse 把
#   其内嵌的 `'<a href="'+(e=s)+'"'` JS 片段当 markdown 自动链接渲染 → 生成畸形
#   <a href> → 用户点击决策按钮时浏览器误触发 navigate 到非法 URL。
#   修复：调换 replace 顺序，先 MARKED_LIB / AUTO_CLOSE_PREF，最后才 DESIGN_CONTENT。
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "---- C11: 渲染顺序防污染（design 内占位符字面量保留） ----"

# C11a: 构造含 {{MARKED_LIB}} 字面量的 mock state.md，渲染后断言
#        - marked.js 特征字符串 `(e=s)` 在 HTML 中只出现 1 次（仅 <script>{{MARKED_LIB}}</script> 注入位置）
#        - design-content-raw 区内保留 `{{MARKED_LIB}}` 字面量（用 html.escape 后是 `{{MARKED_LIB}}`，{ 不被转义）

c11_tmp_dir="$(mktemp -d /tmp/c11-XXXXXX)"
c11_tmp_home="$(mktemp -d /tmp/c11-home-XXXXXX)"
cat > "$c11_tmp_dir/state.md" <<'STATEEOF'
---
active: true
phase: "design"
---
## 设计文档
### 占位符污染回归测试
本节文档故意包含 `{{MARKED_LIB}}` 字面量，模拟契约规约引用占位符的场景。
新增 `{{AUTO_CLOSE_PREF}}` 占位符也要在 design content 内出现。
再来一次 `{{MARKED_LIB}}` 字面量，验证多次出现都保留。

## 实现计划
- [ ] mock
STATEEOF

_c11_cleanup() {
    pkill -f "visual-companion/server.cjs" 2>/dev/null || true
    rm -rf "$c11_tmp_dir" "$c11_tmp_home"
}
trap _c11_cleanup EXIT

# 后台启动 launch-plan-review，等渲染完成（5s 足够）
HOME="$c11_tmp_home" timeout 5 bash "$LAUNCH_SH" "$c11_tmp_dir" >/dev/null 2>&1 || true

c11_html="$(find "$c11_tmp_dir" -name "plan-review.html" 2>/dev/null | head -1)"
if [[ -z "$c11_html" || ! -f "$c11_html" ]]; then
    fail "C11a: 未找到渲染后的 plan-review.html（c11_tmp_dir=$c11_tmp_dir）"
fi

# C11a: marked.js 特征字符串 `(e=s)` 在渲染后 HTML 中只出现 1 次
c11_es_count="$(grep -c "(e=s)" "$c11_html" 2>/dev/null || echo 0)"
if [[ "$c11_es_count" -ne 1 ]]; then
    fail "C11a: marked.min.js 特征 '(e=s)' 在渲染 HTML 中出现 $c11_es_count 次（期望 1 次）— marked.js 被污染注入到 design content（v3.27.1 修复前的 bug）"
fi
pass "C11a: marked.min.js 特征 '(e=s)' 仅出现 1 次（无污染注入）"

# C11b: design content 内的 {{MARKED_LIB}} 字面量保留原样（不被后续 replace 污染）
#       design-content-raw 是 hidden div，内容已 html.escape，但 { } 不被转义
if ! grep -qF "{{MARKED_LIB}}" "$c11_html"; then
    fail "C11b: design content 内的 {{MARKED_LIB}} 字面量未保留（应该保留作为文档字面量展示给用户，不应被 replace 污染）"
fi
pass "C11b: design content 内 {{MARKED_LIB}} 字面量保留原样"

# C11c: launch-plan-review.sh 渲染顺序契约 — DESIGN_CONTENT 必须在 MARKED_LIB 之后替换
if ! awk '
    /tmpl\.replace.*MARKED_LIB/ { ml_line=NR }
    /tmpl\.replace.*DESIGN_CONTENT/ || /result\.replace.*DESIGN_CONTENT/ { dc_line=NR }
    END { exit !(dc_line > ml_line) }
' "$LAUNCH_SH"; then
    fail "C11c: launch-plan-review.sh 中 {{DESIGN_CONTENT}} 必须在 {{MARKED_LIB}} 之后替换（v3.27.1 修复的渲染顺序契约）"
fi
pass "C11c: launch-plan-review.sh 渲染顺序契约（DESIGN_CONTENT 最后替换）"

trap - EXIT
_c11_cleanup

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "[OK ] R10 plan-review-html — 全部自动化断言通过"
echo "      注：端到端浏览器测试（场景 3/4）见 acceptance-checklist.md，需人工/QA 执行"
exit 0
