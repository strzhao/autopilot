# 验收清单：autopilot design 步骤 4「HTML 评审路径」

红队产出 — 仅基于设计文档编写（不读取蓝队实现代码）  
设计文档：`state.md § 设计文档`  
版本目标：v3.22.0  
生成日期：2026-05-09

---

## 自动化测试执行入口

```bash
# 运行本功能专项自动化测试（覆盖 C1/C2/C3/C4/C5/C6 可自动化断言）
bash plugins/autopilot/tests/acceptance/plan-review-html.acceptance.test.sh

# 运行全部红队验收测试
bash plugins/autopilot/tests/acceptance/run-all.sh
```

---

## 5 大场景验收标准

---

### 场景 1：wait-decision.sh 脚本级单测

**类型**：可完全自动化（已包含在 bash 测试脚本中）  
**前提条件**：wait-decision.sh 已创建于 `plugins/autopilot/scripts/visual-companion/wait-decision.sh`

#### 验证步骤

```bash
# 步骤 1：创建 mock events 文件
mkdir -p /tmp/td-test/state
touch /tmp/td-test/state/events

# 步骤 2：后台启动 wait-decision.sh（5s 超时）
bash plugins/autopilot/scripts/visual-companion/wait-decision.sh /tmp/td-test/state 5 &
WAIT_PID=$!

# 步骤 3：注入 approve 事件
sleep 0.5
echo '{"type":"click","choice":"approve","feedback":"LGTM"}' >> /tmp/td-test/state/events

# 步骤 4：等待输出
wait "$WAIT_PID"
WAIT_EXIT=$?

# 步骤 5：超时场景（另起测试，不注入事件）
mkdir -p /tmp/td-timeout/state
touch /tmp/td-timeout/state/events
bash plugins/autopilot/scripts/visual-companion/wait-decision.sh /tmp/td-timeout/state 2
TIMEOUT_EXIT=$?
```

#### 期望证据

| 验证点 | 期望输出 | 判断依据 |
|--------|----------|----------|
| approve 路径 stdout 非空 | 含 `"choice":"approve"` 的 JSON 行 | 设计文档：匹配行直接 echo 给 stdout |
| stdout 为合法 JSON | `python3 -c "import sys,json; json.load(sys.stdin)"` 返回 0 | 设计文档：整行 JSON 给 Claude 解析 |
| feedback 字段存在 | stdout 含 `"feedback"` | 设计文档：helper.js 附加 feedback 到 payload |
| revise choice 正确输出 | 注入 revise 事件 → stdout 含 `"revise"` | 设计文档：支持 approve/revise/abort 三种 choice |
| abort choice 正确输出 | 注入 abort 事件 → stdout 含 `"abort"` | 同上 |
| 超时场景 stdout 为空 | 无输出 | 设计文档：无事件注入时超时 |
| 超时场景退出码非 0 | `$?` != 0 | 设计文档：超时返回非 0 退出码 |

**注意**：设计改进建议（state.md §Plan 审查改进建议 1）指出 macOS `timeout + tail -F | grep -m1` 组合下，**成功路径的退出码也可能为非 0**。Claude 解析时应以「stdout 非空且为合法 JSON」作为成功判据，不依赖退出码。

---

### 场景 2：HTML 模板静态浏览器打开

**类型**：部分自动化（结构 grep 自动化；视觉验证需人工）  
**前提条件**：plan-review-template.html 已创建于 `plugins/autopilot/scripts/visual-companion/plan-review-template.html`

#### 验证步骤

```bash
# 步骤 1：结构检查（自动化，已在 bash 脚本 C2 契约中）
grep -i 'id="feedback"' plugins/autopilot/scripts/visual-companion/plan-review-template.html
grep -i 'data-choice="approve"' plugins/autopilot/scripts/visual-companion/plan-review-template.html
grep -i 'data-choice="revise"' plugins/autopilot/scripts/visual-companion/plan-review-template.html
grep -i 'data-choice="abort"' plugins/autopilot/scripts/visual-companion/plan-review-template.html
grep -i '<pre' plugins/autopilot/scripts/visual-companion/plan-review-template.html
grep -i '</body>' plugins/autopilot/scripts/visual-companion/plan-review-template.html

# 步骤 2：视觉验证（人工，macOS）
open plugins/autopilot/scripts/visual-companion/plan-review-template.html
```

#### 期望证据

| 验证点 | 期望输出 | 判断依据 |
|--------|----------|----------|
| textarea#feedback 存在 | `grep` 返回非空行 | 设计文档：textarea#feedback 收集用户反馈 |
| data-choice="approve" 存在 | `grep` 返回非空行 | 设计文档：通过/修改/放弃三按钮 |
| data-choice="revise" 存在 | 同上 | 同上 |
| data-choice="abort" 存在 | 同上 | 同上 |
| `<pre>` 内容区域存在 | `grep` 返回非空行 | 设计文档：v1 使用 `<pre>` 渲染设计文档全文 |
| `</body>` 存在 | `grep` 返回非空行 | server.cjs 需要此标签自动注入 helper.js |
| 视觉：页面可正常渲染 | 浏览器显示页面无 JS 错误 | 人工确认 |
| 视觉：页面包含 3 个操作按钮 | 可视化确认 3 个按钮文案可读 | 人工确认 |
| 视觉：textarea 可输入文本 | 点击 textarea 可输入 | 人工确认 |

---

### 场景 3：端到端 approve 路径

**类型**：串行，需人工操作浏览器  
**前提条件**：已完成场景 1/2 验证；server.cjs + launch-plan-review.sh 均已就绪；macOS 环境

#### 验证步骤

```bash
# 步骤 1：以 HTML 评审模式启动 autopilot（工作目录为任意 git 仓库）
cd /tmp && git init html-review-test && cd html-review-test
AUTOPILOT_HTML_REVIEW=1 claude
```

在 Claude Code 交互中：
```
/autopilot 添加 hello world 注释到 README.md
```

等待 design 阶段步骤 4 执行，观察：

1. 终端出现「服务器启动」或「浏览器打开」日志
2. 浏览器自动打开 `http://localhost:<port>/`
3. 页面显示设计文档内容（`<pre>` 区域）和 3 个按钮
4. 在 textarea 不填内容，直接点击「通过」按钮

```bash
# 步骤 2（人工点击后）：验证 state.md phase 切换
grep '^phase:' .autopilot/requirements/*/state.md
```

#### 期望证据

| 验证点 | 期望输出 | 判断依据 |
|--------|----------|----------|
| 浏览器自动打开 | 系统默认浏览器自动打开 plan-review 页 | 设计文档：跨平台 open/xdg-open/cmd start |
| 浏览器打不开时 fallback | 终端打印 URL，让用户手动访问 | 设计文档：命令行打印 URL 继续 wait |
| 点「通过」后终端响应 | 终端 Claude 输出含 `decision: approve` 或进入 implement 阶段 | 设计文档：choice 回流 Claude 解析 |
| state.md phase 切换 | `grep '^phase:' state.md` 返回 `phase: "implement"` | 设计文档：approve → 进步骤 5 |
| events 文件含 approve 行 | `cat state/events` 包含含 `"choice":"approve"` 的 JSON 行 | 设计文档：helper.js 写 events 文件 |

---

### 场景 4：端到端 revise + feedback 路径

**类型**：串行，需人工操作浏览器，依赖场景 3 环境搭建  
**前提条件**：与场景 3 相同

#### 验证步骤

```bash
# 步骤 1：以 HTML 评审模式启动 autopilot（同场景 3）
AUTOPILOT_HTML_REVIEW=1 claude
```

在 Claude Code 交互中：
```
/autopilot 添加 hello world 注释到 README.md
```

等待 design 阶段步骤 4，浏览器自动打开后：

1. 在 textarea#feedback 中输入：`请使用 ESM 不要 CJS`
2. 点击「修改」按钮

```bash
# 步骤 2（人工点击后）：验证 feedback 回流
# 检查 events 文件中 feedback 字段
cat .autopilot/requirements/*/state/events | python3 -c "import sys,json; [print(json.loads(l)) for l in sys.stdin if l.strip()]"

# 检查 state.md 是否记录了 feedback（变更日志或目标区域）
grep -i "ESM\|请使用\|feedback" .autopilot/requirements/*/state.md
```

#### 期望证据

| 验证点 | 期望输出 | 判断依据 |
|--------|----------|----------|
| events 文件含 revise + feedback | `cat events` 含 `"choice":"revise"` 且 `"feedback":"请使用 ESM 不要 CJS"` | 设计文档：helper.js JSON.stringify feedback |
| feedback 字段为合法 JSON 字符串 | `python3 json.loads` 不报错 | 设计文档：helper.js 端 JSON.stringify 处理转义 |
| state.md 含 feedback 文本 | `grep` 找到「请使用 ESM」或 feedback 内容 | 设计文档：feedback 文本回流 state.md 变更日志/目标 |
| state.md phase 仍为 design | `grep '^phase:' state.md` 返回 `phase: "design"` | 设计文档：revise → 回步骤 3，不进 implement |
| Claude 进入修改设计循环 | Claude 输出含「修改」「重新设计」等语义 | 设计文档：revise → 回步骤 3 |

---

### 场景 5：默认关闭路径回归

**类型**：部分自动化（SKILL.md 文本检查自动化；完整路径需人工）  
**前提条件**：未设 AUTOPILOT_HTML_REVIEW 环境变量；`html_review` frontmatter 未设置或为 false

#### 自动化验证步骤（bash 脚本 C3 契约已覆盖）

```bash
# 验证 SKILL.md 默认路径含 hint 文案（自动化）
grep -A5 -B5 "AskUserQuestion" plugins/autopilot/skills/autopilot/SKILL.md | grep "AUTOPILOT_HTML_REVIEW"

# 验证 hint 含具体设置示例
grep "AUTOPILOT_HTML_REVIEW=1" plugins/autopilot/skills/autopilot/SKILL.md
```

#### 人工验证步骤

```bash
# 步骤 1：不设环境变量，启动 autopilot
cd /tmp/html-review-test
unset AUTOPILOT_HTML_REVIEW
claude
```

在 Claude Code 交互中：
```
/autopilot 添加 hello world 注释到 README.md
```

等待 design 阶段步骤 4，观察：

1. 终端输出 AskUserQuestion 格式的问题（而非浏览器打开）
2. Claude 展示 preview 内容（设计文档的文本预览）
3. preview 内容末尾包含「启用 HTML 评审」的 hint

#### 期望证据

| 验证点 | 期望输出 | 判断依据 |
|--------|----------|----------|
| 不打开浏览器 | 无浏览器窗口弹出，无 `open` 命令执行 | 设计文档：默认关闭 |
| 走 AskUserQuestion | Claude 以提问形式展示 plan，等待用户文字回复 | 设计文档：AskUserQuestion 为基础路径 |
| preview 末尾含 hint 文案 | preview 末尾包含 `AUTOPILOT_HTML_REVIEW=1` 字样 | 设计文档：「💡 启用 HTML 评审：设置 AUTOPILOT_HTML_REVIEW=1」 |
| hint 同时提及 frontmatter | hint 含 `html_review: true` 或同义文案 | 设计文档：提示 frontmatter html_review: true 同样可开启 |
| 用户回复「通过」后继续 | state.md phase 切换到 implement | 基础路径不变 |
| 用户回复「修改」后继续 | state.md phase 仍为 design，循环重做 | 基础路径不变 |

---

## 交叉验证：helper.js feedback 读取

**对应**：设计文档改动清单「修改 helper.js：click 事件捕获时附加读取 #feedback textarea 内容到 event payload（约 6 行）」

```bash
# 自动化验证（bash 脚本 C6 契约已覆盖）
grep -n "feedback" plugins/autopilot/scripts/visual-companion/helper.js
```

#### 期望证据

| 验证点 | 期望输出 | 判断依据 |
|--------|----------|----------|
| helper.js 含 feedback 读取 | `grep` 返回含 `feedback` 的代码行 | 设计文档：附加读取 #feedback textarea 内容 |
| sendEvent 调用含 feedback 字段 | `grep -A5 sendEvent` 含 feedback 键名 | 设计文档：附加到 event payload |
| 无 feedback 时正确降级 | textarea 为空时 feedback 字段为空字符串或 null（不报错） | 健壮性要求 |

---

## 降级路径专项

**对应**：设计文档「降级：浏览器打不开 → 命令行打印 URL 继续 wait | wait-decision 超时 → fallback AskUserQuestion + preview」

| # | 降级场景 | 触发条件 | 期望行为 | 验证方式 |
|---|----------|----------|----------|----------|
| D1 | 浏览器打不开 | `open` 命令失败（headless 环境）| 终端打印 URL，用户可手动访问；wait-decision.sh 仍继续等待 | 人工：在 headless SSH 环境执行，观察终端输出 |
| D2 | wait-decision 超时 | 30 分钟内无用户操作（或测试用 2s 超时） | 自动切换为 AskUserQuestion + preview，Claude 继续询问用户 | bash 测试：C1g 契约（超时 stdout 为空且退出码非 0）+ 人工观察 Claude fallback |
| D3 | events 文件不存在 | launch-plan-review.sh 未初始化 events 文件 | wait-decision.sh 应优雅报错或等待文件出现 | 人工：手动运行 wait-decision.sh 指向不存在路径 |
| D4 | WebSocket 断连 | 用户关闭浏览器 Tab | helper.js 1 秒后自动重连（已有逻辑） | 不涉及新改动，参考 helper.js 现有 `ws.onclose` 逻辑 |

---

## 文件存在性汇总检查

QA 阶段执行前，可用以下命令快速核查所有必需文件：

```bash
REPO_ROOT="/Users/stringzhao/workspace/string-claude-code-plugin"
VISUAL="$REPO_ROOT/plugins/autopilot/scripts/visual-companion"
SKILL="$REPO_ROOT/plugins/autopilot/skills/autopilot"

echo "=== 新增文件 ==="
ls -la "$VISUAL/plan-review-template.html"
ls -la "$VISUAL/wait-decision.sh"
ls -la "$VISUAL/launch-plan-review.sh"

echo "=== 修改文件 ==="
ls -la "$VISUAL/helper.js"
ls -la "$SKILL/SKILL.md"
ls -la "$SKILL/references/state-file-guide.md"
ls -la "$REPO_ROOT/plugins/autopilot/.claude-plugin/plugin.json"
ls -la "$REPO_ROOT/.claude-plugin/marketplace.json"
ls -la "$REPO_ROOT/CLAUDE.md"
```

---

## 场景独立性说明

| 场景 | 类型 | 自动化程度 | 是否可独立执行 |
|------|------|------------|----------------|
| 场景 1：wait-decision 单测 | 脚本级 | 完全自动化（bash 脚本 C1 契约） | 是，独立 |
| 场景 2：HTML 静态检查 | 文件结构 | 结构检查自动化，视觉需人工 | 是，独立 |
| 场景 3：端到端 approve | 集成 | 需人工操作浏览器 | 串行，依赖环境 |
| 场景 4：端到端 revise+feedback | 集成 | 需人工操作浏览器 | 串行，依赖场景 3 环境 |
| 场景 5：默认关闭回归 | 集成 | 文本检查自动化，完整路径需人工 | 可独立执行 |
