#!/usr/bin/env bash
# launch-plan-review.sh — 编排 HTML 浏览器设计方案评审
#
# Usage: launch-plan-review.sh <task-dir>
#
# 流程：
#   1. 启动 visual-companion server（复用 start-server.sh）
#   2. 从 <task-dir>/state.md 提取 ## 设计文档 + ## 实现计划 内容
#   3. 渲染 plan-review-template.html，写入 $CONTENT_DIR/plan-review.html
#   4. 跨平台打开浏览器（失败则打印 URL 供手动访问）
#   5. 调 wait-decision.sh 阻塞等待用户决策
#   6. 关闭 server（stop-server.sh）
#   7. stdout 输出决策 JSON（来自 wait-decision.sh）
#
# 成功判据（Claude 解析时使用）：stdout 包含合法 JSON 且含 choice 字段。
# 超时 / 解析失败 → stdout 为空，由调用方 fallback 到 AskUserQuestion。

set -euo pipefail

TASK_DIR="${1:?Usage: launch-plan-review.sh <task-dir>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/plan-review-template.html"
STATE_MD="${TASK_DIR}/state.md"

if [[ ! -f "$STATE_MD" ]]; then
  echo "launch-plan-review: state.md not found: ${STATE_MD}" >&2
  exit 1
fi

# ── 步骤 1：启动 server ──────────────────────────────────────────────────────
SERVER_JSON="$("${SCRIPT_DIR}/start-server.sh" --project-dir "$TASK_DIR" 2>/dev/null)"

if [[ -z "$SERVER_JSON" ]] || echo "$SERVER_JSON" | grep -q '"error"'; then
  echo "launch-plan-review: failed to start server: ${SERVER_JSON}" >&2
  exit 1
fi

# 解析 server JSON（使用 node 保证可靠，避免 sed/awk 在特殊字符时出错）
SERVER_URL="$(node -e "console.log(JSON.parse(process.argv[1]).url)" -- "$SERVER_JSON" 2>/dev/null)"
CONTENT_DIR="$(node -e "console.log(JSON.parse(process.argv[1]).screen_dir)" -- "$SERVER_JSON" 2>/dev/null)"
STATE_DIR="$(node -e "console.log(JSON.parse(process.argv[1]).state_dir)" -- "$SERVER_JSON" 2>/dev/null)"
SESSION_DIR="$(dirname "$STATE_DIR")"

if [[ -z "$SERVER_URL" || -z "$CONTENT_DIR" || -z "$STATE_DIR" ]]; then
  echo "launch-plan-review: failed to parse server JSON: ${SERVER_JSON}" >&2
  exit 1
fi

# ── 步骤 2：提取 state.md 内容（## 设计文档 + ## 实现计划）──────────────────
# 用 python3（macOS/Linux 均有）做 HTML 转义，避免 <>&" 破坏 <pre> 标签
# 提取规则：从 "## 设计文档" 标题直到文件末尾的 "## 变更日志" 或 "## 红队" 之前
DESIGN_CONTENT="$(python3 - "$STATE_MD" <<'PYEOF'
import sys, html, re

state_file = sys.argv[1]
with open(state_file, 'r', encoding='utf-8') as f:
    content = f.read()

# 提取 frontmatter 之后的 body
body = re.sub(r'^---.*?---\s*', '', content, flags=re.DOTALL)

# 只保留 ## 设计文档 到 ## 变更日志（或 ## 红队 或 ## QA）之前
m = re.search(r'(## 设计文档.*?)(?=\n## (?:变更日志|红队|QA)|$)', body, flags=re.DOTALL)
if m:
    text = m.group(1)
else:
    # 降级：输出全部 body（去 frontmatter 后）
    text = body.strip()

# 同时追加 ## 实现计划（若 ## 设计文档 区域未包含）
if '## 实现计划' not in text:
    m2 = re.search(r'(## 实现计划.*?)(?=\n## (?:验证方案|变更日志|红队|QA)|$)', body, flags=re.DOTALL)
    if m2:
        text = text.rstrip() + '\n\n' + m2.group(1)

print(html.escape(text.strip()))
PYEOF
)"

if [[ -z "$DESIGN_CONTENT" ]]; then
  DESIGN_CONTENT="（无法提取设计文档内容，请查阅 state.md）"
fi

# ── 步骤 3：渲染 HTML 到 CONTENT_DIR ─────────────────────────────────────────
if [[ ! -f "$TEMPLATE" ]]; then
  echo "launch-plan-review: template not found: ${TEMPLATE}" >&2
  exit 1
fi

RENDERED_HTML="${CONTENT_DIR}/plan-review.html"
MARKED_LIB="${SCRIPT_DIR}/marked.min.js"
PREFS_CJS="${SCRIPT_DIR}/prefs.cjs"

# 读取 auto_close_after_decision 偏好（默认 true）
AUTO_CLOSE_PREF="true"
if [[ -f "$PREFS_CJS" ]]; then
  AUTO_CLOSE_PREF="$(node -e "try { var p=require('${PREFS_CJS}'); console.log(String(p.getPref('auto_close_after_decision', true))); } catch(e) { console.log('true'); }" 2>/dev/null || echo "true")"
fi
# 确保只输出 true 或 false
if [[ "$AUTO_CLOSE_PREF" != "true" && "$AUTO_CLOSE_PREF" != "false" ]]; then
  AUTO_CLOSE_PREF="true"
fi

# 用 python3 做可靠的占位符替换（避免 sed 在多行内容时出错）
python3 - "$TEMPLATE" "$DESIGN_CONTENT" "$RENDERED_HTML" "$MARKED_LIB" "$AUTO_CLOSE_PREF" <<'PYEOF'
import sys, os

template_path = sys.argv[1]
design_content = sys.argv[2]
output_path = sys.argv[3]
marked_lib_path = sys.argv[4]
auto_close_pref = sys.argv[5]

with open(template_path, 'r', encoding='utf-8') as f:
    tmpl = f.read()

# 读 marked.min.js（运行时内嵌注入，与 helper.js 同模式）
marked_lib = ''
if os.path.isfile(marked_lib_path):
    with open(marked_lib_path, 'r', encoding='utf-8') as f:
        marked_lib = f.read()

result = tmpl.replace('{{DESIGN_CONTENT}}', design_content)
result = result.replace('{{MARKED_LIB}}', marked_lib)
result = result.replace('{{AUTO_CLOSE_PREF}}', auto_close_pref)

with open(output_path, 'w', encoding='utf-8') as f:
    f.write(result)
PYEOF

# ── 步骤 4：打开浏览器（跨平台）─────────────────────────────────────────────
open_browser() {
  local url="$1"
  if command -v open >/dev/null 2>&1; then
    # macOS
    open "$url" 2>/dev/null && return 0
  fi
  if command -v xdg-open >/dev/null 2>&1; then
    # Linux (X11/Wayland)
    xdg-open "$url" 2>/dev/null && return 0
  fi
  if command -v cmd.exe >/dev/null 2>&1; then
    # Windows / Git Bash / WSL
    cmd.exe /c start "" "$url" 2>/dev/null && return 0
  fi
  return 1
}

if open_browser "$SERVER_URL"; then
  echo "launch-plan-review: browser opened: ${SERVER_URL}" >&2
else
  echo "launch-plan-review: 无法自动打开浏览器，请手动访问：${SERVER_URL}" >&2
  echo "launch-plan-review: 打开后点击通过/修改/放弃按钮即可继续" >&2
fi

# ── 步骤 5：阻塞等待用户决策 ─────────────────────────────────────────────────
DECISION="$("${SCRIPT_DIR}/wait-decision.sh" "$STATE_DIR" 1800 2>/dev/null || true)"

# ── 步骤 6：关闭 server ──────────────────────────────────────────────────────
"${SCRIPT_DIR}/stop-server.sh" "$SESSION_DIR" >/dev/null 2>&1 || true

# ── 步骤 7：输出决策 JSON ─────────────────────────────────────────────────────
if [[ -n "$DECISION" ]]; then
  echo "$DECISION"
  exit 0
else
  # 超时或无决策：stdout 为空，调用方应 fallback 到 AskUserQuestion
  exit 1
fi
