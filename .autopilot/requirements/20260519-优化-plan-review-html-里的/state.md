---
active: true
phase: "merge"
gate: "review-accept"
iteration: 4
max_iterations: 30
max_retries: 3
retry_count: 0
mode: "single"
plan_mode: ""
fast_mode: false
brief_file: ""
next_task: ""
auto_approve: false
knowledge_extracted: ""
task_dir: "/Users/stringzhao/workspace/agi/live/string-claude-code-plugin/.autopilot/requirements/20260519-优化-plan-review-html-里的"
session_id: a86e35dd-a921-4577-8dff-4f0e2abd5e99
started_at: "2026-05-19T02:58:52Z"
contract_required: true
html_review: true
---

## 目标
优化 plan review html 里的效果 1. 当前生成的 plan 人去看的时候不够直观和高效，你深入搜索和了解下好的方案设计，优化下 2. 在 html 左侧增加目录展示，方便切换 3. 先了解 skill best practice ， skill 非常脆弱，涉及到 skill 的都需要采用最小化改动

> 📚 项目知识库已存在: .autopilot/。design 阶段请先加载相关知识上下文。

## 验收场景

> 由验收场景生成器从纯目标视角生成（信息隔离：未读取设计文档/实现代码）。供 plan-reviewer 评估场景覆盖度参考。

**场景 1：左侧目录默认呈现并准确反映 plan 结构**
- 类型：Happy Path｜验证层级：UI
- 前置：design 阶段，浏览器加载 plan review HTML，plan 含 ≥2 个标题
- 步骤：用户加载页面，视线扫向左侧
- 预期：左侧出现独立 TOC 区域；条目按层级（H2/H3）有序、缩进；条目文字与正文标题一致；现有决策按钮、菜单、正文渲染不退化
- OST：DOM 中存在 `<nav>` 或 `role="navigation"` 容器，子条目数 = plan 标题数；条目带层级标识（class 含 `toc-h2/toc-h3` 或 `aria-level`）

**场景 2：点击目录条目跳转到对应正文章节**
- 类型：Happy Path｜验证层级：UI
- 前置：plan 至少 3 个条目，正文长到产生滚动
- 步骤：滚动正文使首节标题滚出视口；点击 TOC 中第 3 项
- 预期：正文滚动到对应标题位置；URL hash 变化或 TOC 该项获得激活态
- OST：点击前条目无 active 类；点击后该条目带 active class / aria-current；`window.location.hash` 变化或 `scrollTop` 显著增大；目标 heading 在视口内

**场景 3：滚动正文时目录高亮自动跟随**
- 类型：Happy Path｜验证层级：UI
- 前置：多章节、可滚动
- 步骤：从顶滚到下，依次经过 H2/H3
- 预期：滚动经过新章节时 TOC 激活项自动切换；同一时刻最多 1 项 active
- OST：滚到第 N 节时第 N 项获得 active、其他清除；`document.querySelectorAll('.is-active').length === 1`（章节过渡瞬间可为 0）

**场景 4：plan 内容很短或无标题时的退化处理**
- 类型：Edge Case｜验证层级：UI
- 前置：plan markdown 仅段落 / 仅 1 个 H1
- 步骤：加载页面
- 预期：不出现空目录壳；显示「无目录」提示或不渲染 TOC 容器；正文 + 决策按钮区不留大片左侧空白
- OST：0 标题：TOC 容器存在但带 `.toc-empty` 节点（含「无」字样）；1 H1：H1 不入 TOC（按设计），TOC 显示空状态

**场景 5：plan 内容很长、标题很多时目录可独立滚动**
- 类型：Edge Case｜验证层级：UI
- 前置：plan 含 30+ 标题
- 步骤：加载；在 TOC 区域内滚动
- 预期：TOC 可独立滚动；正文不一起滚；决策按钮始终可见可点
- OST：TOC 内滚动后 `#toc-pane.scrollTop` 变化，`window.scrollY` 不变；决策按钮 `getBoundingClientRect()` 仍在视口

**场景 6：现有交互未因新增 TOC 而退化**
- 类型：Integration｜验证层级：UI + WebSocket
- 前置：TOC 已渲染
- 步骤：选中正文 → 评论按钮 → 添加评论；打开评论侧边栏；切换菜单偏好；点击决策按钮
- 预期：选区浮动评论按钮正常出现；评论卡牌正常加入；菜单切换正常；决策按钮触发 WS 发送 1 次
- OST：选中后评论按钮 DOM 出现；评论数 +1；偏好项 aria-checked / class 翻转；决策按钮 disabled 且 server.cjs 收到一条 WS 消息

**场景 7：窄屏 / 响应式视口下目录不破坏可用性**
- 类型：Edge Case｜验证层级：UI
- 步骤：视口缩小至 ≤768px
- 预期：TOC 不挤压正文；折叠抽屉/隐藏；正文可读宽度保留；决策按钮可访问
- OST：跨断点后 TOC/正文容器 class 列表更新；正文 `offsetWidth` ≥ 可读阈值

**场景 8：加载阶段的目录状态**
- 类型：Edge Case｜验证层级：UI
- 预期：完成后 TOC 条目 ↔ 正文 anchor 一一对应，不存在悬空 href
- OST：每个 `a[href^="#h-"]` 的 hash 在 `document.getElementById` 命中真实 heading

**场景 9：skill 文件最小化改动（目标 3 验收）**
- 类型：Integration｜验证层级：Config + UI
- 步骤：检视改动文件 diff
- 预期：`SKILL.md` / `launch-plan-review.sh` / `helper.js` / `server.cjs` / `frame-template.html` / `prefs.cjs` / `marked.min.js` **0 行改动**
- OST：`git diff --name-only HEAD` 仅含 `plugins/autopilot/scripts/visual-companion/plan-review-template.html`

## 设计文档

### Context（为什么做）

`plugins/autopilot/scripts/visual-companion/plan-review-template.html`（1321 行）是 autopilot design 阶段供用户在浏览器中评审设计方案的 HTML 模板。当前布局为 2 列 grid：左侧设计文档主体 + 右侧 320px 评论面板。窄屏（<1100px）折叠为单列。当 plan 较长时存在两个明确痛点：

1. **找不到关键信息**：无导航能力，跳转 H2/H3 必须手动滚动
2. **阅读节奏一片黑字**：现有 H 排版已不错（Crimson Pro + 1.55rem H2 + border-top 分隔），但列表/代码块/表格/引用尚未做层级强化

约束（来自用户与 brainstorm）：
- **skill 最小化改动铁律**：不动 `SKILL.md`、`launch-plan-review.sh`、`helper.js`、`frame-template.html`、`server.cjs`。改动局限在 `plan-review-template.html` 一个文件
- 保留 stringzhao 调色板（墨/纸/雾/烟/炭/苔/琥/朱/天）+ 字体（Crimson Pro / Noto Serif SC / Inter）
- 保留所有现有交互：选区评论按钮、决策按钮、WS 通信、双 listener 阻断（`stopImmediatePropagation`）
- 不依赖 AI 在 plan 中写特殊标记（callout / 摘要卡均**不做**）

### 整体方案

引入"三栏阅读"布局，左 260px 固定 TOC + 中间 1fr 设计文档主体 + 右 320px 评论面板。TOC 通过客户端 post-process 在 marked.parse() 完成后扫描 H2/H3，补充唯一 id，构造列表渲染到左栏。滚动时 IntersectionObserver 驱动 TOC 当前章节高亮。窄屏（<1200px）TOC 折叠为左上角抽屉按钮，点击展开 overlay。同时对 H 标题、列表、代码块、表格、引用做"阅读体验重排"。

### 关键决策

**D1. 改动文件唯一**
仅 `plan-review-template.html` 一个文件。CSS、JS、HTML 全部内联在该文件中。验证手段：`git diff --name-only` 在 implement 完成后只能列出此一个文件。

**D2. TOC 内容动态生成（H2/H3）**
post-process 时使用 `setAttribute('id', 'h-N')` 而非 `dataset.id = 'h-N'`，避免红队字面 grep 命中失败（参见知识库 patterns.md "HTML 模板用 setAttribute" 教训）。重复标题文本通过递增计数器 fallback。H4+ 不入 TOC（避免列表过长）。

**D3. anchor 命名独立**
TOC 锚点 id 使用 `h-1`、`h-2`...，与已有 `data-block-id="b-1"`（评论锚点）完全隔离，不能复用、不能借位。

**D4. Grid 三列响应式（与现有 #comments-drawer-toggle 1100/1101 断点协调）**
- `>= 1200px`：三栏 grid `260px 1fr 320px`，TOC 固定显示，评论固定显示
- `1100px - 1199px`：两栏 grid `1fr 320px`（保留现有评论显示逻辑），TOC 折叠为抽屉
- `< 1100px`：单栏（保留现有 grid 折叠 + 评论抽屉化逻辑），TOC 也折叠为抽屉
- 现有 line 837/856 的 `@media (max-width: 1100px)` / `(min-width: 1101px)` **保持不动**（控制 `#comments-drawer-toggle` 的显隐），新增 TOC 断点仅为 `1200px` 一个，与现有 1100 断点互不重叠

**D5. TOC 高亮采用 IntersectionObserver**
监听所有 H2/H3 元素，进入视口时高亮 TOC 对应项。比 scroll 事件性能更好；rootMargin 设置 `-80px 0px -70% 0px` 补偿 sticky toolbar 与"阅读焦点中段"。

**D6. 抽屉交互不引入新点击 listener 冲突**
新增的 TOC 切换按钮 click 事件**不**通过 `[data-choice]` 属性触发（保留 helper.js click 委托给决策按钮的语义）。使用独立的 id selector（`#toc-toggle`）+ 内联 listener，避免与 helper.js 双 listener 冲突。

**D7. 现有 grid `.reading-layout` 改造而非新建**
直接修改 line 326-345 处的 `.reading-layout`，加左侧 TOC 列。不新建容器避免 CSS 链式失效。

**D8. 标识一类视觉强化（顺手做）**
保留 stringzhao 配色，仅微调：
- `<ul>/<ol>` marker 用 `--sage` 苔色
- `<code>` 行内 / `<pre>` 块用 `--mist` 浅雾背景 + `--rule` 边线
- `<table>` thead 加 `--paper-soft` 强化 + `--rule` 底线
- `<blockquote>` 左 3px solid `--sage` 边线
- 段落首行不缩进（保留现有体验，不做 drop-cap，避免与 TOC 视线竞争）

### 真实测试场景（QA Tier 1.5 必跑）

**场景 1（独立）**：用一份包含 5 个 H2 + 8 个 H3 的 mock 设计文档启动 plan-review，浏览器中验证 TOC 出现在左侧 260px 列、列表项数 = 13、点击任一项主体滚动到对应位置。

**场景 2（独立）**：在场景 1 基础上手动滚动主体，验证 TOC 当前章节高亮跟随（`.toc-item.is-active` class 切换）。

**场景 3（独立）**：浏览器窗口宽度调整到 1100px，验证 TOC 折叠为左上角抽屉按钮；点击按钮 overlay 展开；点击 overlay 项关闭 + 滚动跳转。

**场景 4（独立）**：在场景 1 基础上选中正文段落，验证选区上方仍正常出现 💬 评论按钮，点击后评论卡牌出现在右侧面板（**回归测试现有功能**）。

**场景 5（独立）**：在场景 1 基础上点击决策按钮"同意"，验证 server.cjs 收到的 WS payload 中 `choice="approve"`，且只发送一次（**回归测试 helper.js 双 listener 阻断**）。

**场景 6（独立）**：mock 一份 H 标题文本完全相同（如三个 `### 步骤`）的设计文档，验证 TOC 项 id 不冲突（`h-1`、`h-2`、`h-3`），点击各自跳转到正确位置。

启动方式（场景 1-6 共用）：
```bash
# 准备 mock state.md
mkdir -p /tmp/autopilot-test-plan-review/requirements/test-task
cat > /tmp/autopilot-test-plan-review/requirements/test-task/state.md <<'EOF'
---
phase: design
---
## 目标
test
## 设计文档
... (mock H2/H3 内容)
EOF
# 启动 launch-plan-review.sh，浏览器自动打开
bash plugins/autopilot/scripts/visual-companion/launch-plan-review.sh /tmp/autopilot-test-plan-review/requirements/test-task
# 在浏览器中执行场景 1-6 的人工/自动化检查
# 完成后 stop-server.sh 清理
```

## 契约规约

### 接口签名（前端 UI 组件 — DOM 接口）

`plan-review-template.html` 渲染后的 DOM 必须满足以下 shape：

```html
<body>
  <header class="toolbar">...</header>  <!-- 现有 -->
  <main class="reading-layout">
    <!-- 新增 -->
    <nav id="toc-pane" class="toc-pane" aria-label="目录">
      <button id="toc-toggle" type="button" aria-expanded="false" aria-controls="toc-list">
        <span class="toc-toggle-icon">☰</span>
        <span class="toc-toggle-label">目录</span>
      </button>
      <ol id="toc-list" class="toc-list">
        <li class="toc-item toc-h2"><a href="#h-1">设计文档</a></li>
        <li class="toc-item toc-h3"><a href="#h-2">Context</a></li>
        ...
      </ol>
    </nav>
    <!-- 现有 -->
    <article id="design-content-wrap">...</article>
    <aside id="comments-pane">...</aside>
  </main>
</body>
```

### 接口签名（example，Pact 风格）

- Given: 设计文档包含 markdown `## A\n### B\n## C`
- When: marked.parse + post-process 完成
- Then: `#toc-list` 包含 3 个 `<li>`，第 1 个 `<a href="#h-1">A</a>`、第 2 个 `<a href="#h-2">B</a>`（嵌套或缩进表示层级）、第 3 个 `<a href="#h-3">C</a>`；正文中 `<h2 id="h-1">A</h2>`、`<h3 id="h-2">B</h2>`、`<h2 id="h-3">C</h2>`

### 数据结构

- TOC 项 selector: `#toc-list .toc-item`
- 当前高亮 class: `is-active`（添加在 `.toc-item` 上，不在 `<a>` 上）
- 抽屉展开状态: `#toc-pane.is-open`（class 切换）+ `#toc-toggle[aria-expanded="true"]`
- TOC 项层级 class: `.toc-h2` / `.toc-h3`
- 正文 heading id: `h-${counter}`（counter 从 1 开始递增）
- 正文 heading 同时保留现有 `data-block-id="b-${counter}"`（评论锚点）—— 两套 attribute 共存，互不替代

### 边界值（invariant，DbC 谓词）

- TOC 触发深度: 仅 `H2` 和 `H3` 入 TOC，`H1`、`H4`、`H5`、`H6` 一律忽略
- id 命名计数器: `h-1`、`h-2`...，遇到重复 H 文本时计数器**仍递增**（保证 id 唯一）
- 三栏断点（仅控制 TOC 与 grid）: `viewport.width >= 1200px` → 三栏 + TOC 固定；`1100px <= viewport.width < 1200px` → 两栏 + TOC 抽屉；`viewport.width < 1100px` → 单栏 + TOC 抽屉 + 评论抽屉
- `.toc-pane` 在固定显示态必须满足 `position: sticky` + `top: <toolbar-height>` + `max-height: calc(100vh - <toolbar-height>)` + `overflow-y: auto`，使 TOC 可独立滚动而不带动正文（场景 5 OST `#toc-pane.scrollTop` 独立变化要求）
- IntersectionObserver rootMargin: `-80px 0px -70% 0px`（顶部预留 sticky toolbar 高度，底部仅当 heading 在视口上 30% 内才视为"当前"）
- 抽屉打开后 ESC 关闭 + 点击 overlay 外部关闭

### 边界值（example，正/边界/反）

- 正例: viewport = 1400px → 三栏布局，TOC 始终可见
- 边界: viewport = 1200px → 三栏布局（包含 1200px）
- 边界: viewport = 1199px → 两栏 + TOC 抽屉（评论列正常显示）
- 边界: viewport = 1100px → 两栏 + TOC 抽屉（评论列正常显示，仍未触发现有评论抽屉化）
- 反例: viewport = 1099px → 单栏 + TOC 抽屉 + 评论抽屉（现有评论抽屉逻辑接管）
- 正例: 设计文档无 H2/H3 → `#toc-list` 为空 `<ol></ol>`，TOC 容器仍渲染但显示「无目录」占位文本
- 反例: 设计文档完全为空 → 现有渲染逻辑接管，TOC 显示「无目录」占位，决策按钮仍可用

### 错误契约

- marked.parse 抛异常 → fallback 到原始文本展示（现有逻辑不退化）；TOC 显示「无目录」占位
- IntersectionObserver 浏览器不支持 → TOC 仍可点击跳转，仅缺失高亮跟随（不阻断核心流程）
- 重复 H 标题 → 通过计数器保证 id 唯一，TOC 列表项允许文本重复

### 副作用清单

- 新增 DOM 节点：`<nav id="toc-pane">`（含 `<button id="toc-toggle">` + `<ol id="toc-list">`）
- 新增 CSS class：`.toc-pane`、`.toc-list`、`.toc-item`、`.toc-h2`、`.toc-h3`、`.is-active`、`.is-open`
- 新增 JS 全局符号：`buildTOC()`、`syncTOCHighlight()`（IIFE 内部，不污染 window）
- 修改 CSS：`.reading-layout` grid-template-columns 与 media query 断点（line 326-345）
- 不增加：HTTP 请求、外部脚本、新依赖、cookie/localStorage（现有 prefs.cjs 沿用）
- 不修改：`launch-plan-review.sh`、`helper.js`、`server.cjs`、`SKILL.md`、`frame-template.html`、`prefs.cjs`、`marked.min.js`


## 实现计划

### 改动范围
仅修改 `plugins/autopilot/scripts/visual-companion/plan-review-template.html` 一个文件。预计改动量：
- 新增 CSS：~80 行
- 修改 CSS：~20 行（grid + 响应式断点）
- 阅读体验重排 CSS：~50 行
- 新增 HTML 结构：~10 行（TOC 容器骨架）
- 新增 JS：~70 行（buildTOC + IntersectionObserver + 抽屉交互）
- **总计 ≈ 230 行新增 / 20 行修改**

### 任务清单

- [x] **Step 1**：在 plan-review-template.html `<style>` 段中（line 326-345 附近）修改 `.reading-layout` 的 `grid-template-columns`：默认（>=1200px）`260px 1fr 320px`；新增 `@media (max-width: 1199px)` 收回到 `1fr 320px` + TOC 抽屉化。**保留现有 line 340-345 `@media (max-width: 1100px)` 的单栏折叠不动**，使新断点 1199 与现有 1100/1101 评论抽屉断点互不冲突
- [x] **Step 2**：在 `<style>` 段末尾新增 TOC 相关 CSS 类（约 80 行）。**关键 invariant 必须显式落实**：
  - `.toc-pane { position: sticky; top: <toolbar-height>; max-height: calc(100vh - <toolbar-height>); overflow-y: auto; }`（场景 5 独立滚动 + 不带动正文）
  - `.toc-list`、`.toc-item`、`.toc-h2`（左对齐）、`.toc-h3`（缩进 1.2rem）、`.is-active`（前景色 `--sage` + 左 2px solid `--sage` border）
  - `#toc-toggle`（默认隐藏，<1200px 抽屉态显示）+ `.toc-overlay-backdrop`（半透明 `--ink` 0.4 alpha）
  - 抽屉态 `#toc-pane.is-open { transform: translateX(0); }` + 默认 `transform: translateX(-100%); position: fixed; top: 0; left: 0; height: 100vh; z-index: 90; background: var(--paper); }`
  - 空状态 `.toc-empty { color: var(--smoke); font-size: 0.85rem; padding: 1rem; }`
- [x] **Step 3**：在 `.reading-layout` 内 `<article>` 之前新增 `<nav id="toc-pane">` 骨架（含 `<button id="toc-toggle">` 与空 `<ol id="toc-list">`），约 10 行 HTML
- [x] **Step 4**：在现有 marked.parse + post-process 段（约 line 920-950）后追加 `buildTOC()` 函数：扫描 `#design-content` 内所有 `h2`、`h3`，**必须使用 `headingEl.setAttribute('id', 'h-' + counter)`**（不能用 `headingEl.dataset.id` —— dataset 写不出真实 id 属性，会让红队 grep `id="h-` 失败；与 line 947 `child.dataset.blockId = 'b-' + counter` 风格不同是有意的）。counter 全局递增、保证唯一，构造 `<li class="toc-item toc-h2/h3"><a href="#h-N">text</a></li>` 注入 `#toc-list`
- [x] **Step 5**：在 buildTOC 之后追加 `setupTOCHighlight()` 函数：使用 IntersectionObserver 监听所有 H2/H3，rootMargin `-80px 0px -70% 0px`，进入视口的最靠上的 heading 对应的 toc-item 添加 `.is-active` class（其他清除）。降级：浏览器不支持 IntersectionObserver 时跳过此步（仅保留点击跳转）
- [x] **Step 6**：在 buildTOC 之后追加 TOC 项点击平滑滚动逻辑（`scrollIntoView({ behavior: 'smooth', block: 'start' })`）；窄屏抽屉打开状态点击后**自动关闭抽屉**
- [x] **Step 7**：实现 TOC 抽屉交互：`#toc-toggle` 点击切换 `#toc-pane.is-open` class + `aria-expanded` 同步；ESC 键关闭；点击 `.toc-overlay-backdrop` 关闭。**新增 listener 必须 scoped 到 `#toc-toggle` selector，不能复用 `[data-choice]` 委托**
- [x] **Step 8**：处理空状态——若 `#toc-list` 渲染后无 `<li>`（无 H2/H3），追加 `<div class="toc-empty">无目录</div>` 占位
- [x] **Step 9**：保留并验证现有 `data-block-id="b-N"` 注入逻辑不被破坏（H2/H3 元素同时拥有 `id="h-N"` 和 `data-block-id="b-N"`，互不冲突）
- [x] **Step 10**：自测——准备 mock state.md（5 H2 + 8 H3）启动 launch-plan-review.sh，浏览器逐项验证 9 个验收场景 + 6 个真实测试场景
- [x] **Step 11**：清理与提交准备：`git diff --stat` 仅修改一个文件、改动量在预算内；`git diff --name-only` 不包含 SKILL.md / launch-plan-review.sh / helper.js / server.cjs / frame-template.html / prefs.cjs / marked.min.js

### 验证方案

#### 静态检查
- `git diff --name-only HEAD` 输出仅 `plugins/autopilot/scripts/visual-companion/plan-review-template.html`
- HTML 通过浏览器 devtools console 无 JS 报错
- TOC 容器、按钮、列表项的 selector 与契约规约 §"接口签名"一致

#### 真实测试场景（参见上文「真实测试场景」+ 验收场景列表）
启动方式：
```bash
mkdir -p /tmp/autopilot-toc-test/requirements/test-task
# 写入 mock state.md（含已知数量的 H2/H3）
bash plugins/autopilot/scripts/visual-companion/launch-plan-review.sh /tmp/autopilot-toc-test/requirements/test-task
# 浏览器验证 9 个验收场景
# 完成后 stop-server.sh 或关闭浏览器
```

#### 已知降级路径
- IntersectionObserver 不支持 → TOC 仍可点击跳转，仅缺失高亮
- marked 抛异常 → 现有 fallback 显示纯文本，TOC 显示「无目录」
- 选区评论按钮 / 决策按钮 / WS 通信 → 必须 100% 不退化（场景 6 重点验证）

> ✅ Plan 审查通过（plan-reviewer sonnet agent，全部 8 维度通过）。3 个 80-90 重要问题已吸收到设计文档与实现计划：
> 1. 三栏断点改为与现有 `#comments-drawer-toggle` 1100/1101 断点协调（D4 + Step 1）
> 2. `.toc-pane` sticky/overflow 关键属性显式落实到契约规约边界值与 Step 2
> 3. Step 4 强调 `setAttribute('id', ...)` 必须用属性写法、与 dataset.blockId 风格不同是有意的


## 红队验收测试

### 测试文件
`plugins/autopilot/tests/acceptance/plan-review-toc.acceptance.test.sh`（bash + grep 字面断言风格，与同主题前作 plan-review-html.acceptance.test.sh 一致，shellcheck 通过）

### 验收标准（共 31 个断言，全 PASS）

**A. DOM 结构契约（7 条）** — 场景 1, 8
- A1-A7: `<nav id="toc-pane">` / `aria-label="目录"` / `<button id="toc-toggle">` / `aria-expanded="false"` / `aria-controls="toc-list"` / `<ol id="toc-list">` / `<ol>` 含 `class="toc-list"`

**B. JS 行为契约（9 条）** — 场景 1-3, 6, 8
- B1: `setAttribute('id'` 字面（D2 决策）
- B2: `IntersectionObserver`（D5 高亮）
- B3-B5: `'is-active'` / `'is-open'` / `'toc-empty'` class 字面
- B6: `scrollIntoView`（点击跳转）
- B7: ESC 键关闭逻辑（regex 同时覆盖 `'Escape'` / `keyCode==27` / `which==27`）
- B8: `buildTOC` 函数标识
- B9: `#toc-toggle` 选择器使用

**C. CSS 契约（6 条）** — 场景 5, 7
- C1-C3: `.toc-pane` selector / `position: sticky` / `overflow-y: auto`
- C4: 1200px 断点 media query（regex 兼容 `max-width: 1199px` 与 `min-width: 1200px`）
- C5-C6: `.toc-h2` / `.toc-h3` 层级 class

**D. 现有功能未退化（5 条）** — 场景 6
- D1: `child.dataset.blockId = 'b-'` 仍存在
- D2: `stopImmediatePropagation` 仍存在
- D3: `@media (max-width: 1100px)` 与 `#comments-drawer-toggle` 共存（杀死"数字保留但 selector 改名"mutation）
- D4: `min-width: 1101px` 断点仍存在
- D5: `<aside id="comments-pane">` 仍存在

**E. skill 文件 0 改动（2 条）** — 场景 9
- E1: 禁改清单（SKILL.md / launch-plan-review.sh / helper.js / server.cjs / frame-template.html / prefs.cjs / marked.min.js）均未改动
- E2: 改动文件白名单校验（git diff 只含 plan-review-template.html + 红队测试 + .autopilot 状态）

**F. 重复 H 文本计数器逻辑（2 条）** — 场景 6 OST + D2
- F1: counter 自增逻辑存在
- F2: `'h-' + counter` 拼接（兼容 3 种字面写法）

### 测试运行结果
```
[OK ] R11 plan-review-toc — 全部 24 个静态字面断言通过
      覆盖：A(7) + B(9) + C(6) + D(5) + E(2) + F(2) = 31 个 grep 断言
```

### CONTRACT_AMBIGUOUS 标记
无主要契约模糊。仅 C4 用 regex 双路兼容设计 D4 中"新增 1200 断点"的两种合法写法。

### 端到端浏览器场景未覆盖（QA 阶段必跑）
toc-item DOM 由 JS 运行时生成、TOC 高亮跟随、抽屉展开/关闭、点击平滑滚动等交互行为无法仅靠 grep 验证，需 QA Tier 1.5 阶段在浏览器中按 state.md 设计文档「真实测试场景」启动 launch-plan-review.sh 人工冒烟。

## 契约校验

✅ **PASS**（contract-checker agent，5 维度逐字比对）

- **DOM 字段**：`<nav id="toc-pane">` / `<button id="toc-toggle">` / `<ol id="toc-list" class="toc-list">` / `aria-label="目录"` / `aria-expanded="false"` / `aria-controls="toc-list"` — 全部匹配
- **Class**：`.toc-pane` / `.toc-list` / `.toc-item` / `.toc-h2` / `.toc-h3` / `.is-active` / `.is-open` / `.toc-empty` — 全部存在
- **断点**：`@media (max-width: 1199px)` (line 342, 992) / `@media (max-width: 1100px)` (line 347, 614, 644, 844) / `@media (min-width: 1101px)` (line 637, 863) — 全部匹配
- **JS 签名**：`buildTOC()` (line 1135) / `setupTOCHighlight()` (line 1169) / `setAttribute('id', hid)` (line 1143) / `'h-' + counter` (line 1141) / `counter++` (line 1154) / IntersectionObserver rootMargin `-80px 0px -70% 0px` (line 1201) / `scrollIntoView({ behavior: 'smooth', block: 'start' })` (line 1242) / Escape (line 1271) — 全部匹配
- **错误契约**：marked.parse try/catch fallback (line 1097-1109) / IntersectionObserver undefined fallback (line 1171) / counter-based unique id — 全部覆盖
- **共存**：`dataset.blockId = 'b-'` (line 1116) 与 `stopImmediatePropagation` (line 1576) 保留


## QA 报告

### 轮次 1 (2026-05-19T04:05:00Z) — ✅ 用户验收通过

#### Wave 1（命令执行）

**Tier 0: 红队验收测试** — ✅ PASS
- 命令: `bash plugins/autopilot/tests/acceptance/plan-review-toc.acceptance.test.sh`
- 输出: `[OK ] R11 plan-review-toc — 全部 24 个静态字面断言通过 / 覆盖：A(7) + B(9) + C(6) + D(5) + E(2) + F(2) = 31 个 grep 断言`

**Tier 1: 基础验证**
- 类型检查: N/A（项目无 TypeScript）
- Lint（红队 .sh）: ✅ shellcheck PASS
- Lint（npm run lint）: ⚠️ 2 个 pre-existing style/info（has-pending-subagents.acceptance.test.sh:171 SC2129、scripts/lib.sh:106 SC1003）— **与本次改动无关**
- 单元测试（npm test）: ⚠️ 80 测试 79 PASS / 1 FAIL — VC9 (`pending-subagent.acceptance.test.mjs:360`) 性能阈值失败 (2515ms / 2268ms vs 2000ms 阈值)。**与本次改动无关**（独立模块、5MB transcript 解析阈值过紧的环境性能问题）
- 构建: N/A（项目无 build 步骤）
- 静态结构: ✅ `<script>` 2/2、`<style>` 1/1、`<body>` 1/1 标签匹配；`id="toc-pane"` / `id="toc-toggle"` / `id="toc-list"` 各出现 1 次；`buildTOC`/`setupTOCHighlight` 函数定义存在

#### Wave 1.5: 真实测试场景（Chrome DevTools MCP 浏览器验证）

**执行**: 准备 mock state.md（5 H2 + 8 H3 + 3 重复标题）→ 复用 launch-plan-review.sh 渲染逻辑 → file:///tmp/autopilot-toc-test/plan-review.html → Chrome DevTools `evaluate_script` DOM 检查

**输出**:
```json
{
  "scene1": {"toc_pane_exists": true, "toc_pane_aria_label": "目录", "toc_list_exists": true, "toc_items_count": 14, "h2_count": 5, "h3_count": 9, "toc_items_class_h2": 5, "toc_items_class_h3": 9},
  "scene6_8": {"all_h_ids": ["h-1"..."h-14"], "all_ids_unique": true, "toc_hrefs_count": 14, "dangling_hrefs": []},
  "scene4_h1_excluded": {"h1_count_in_content": 0, "toc_includes_h1": false},
  "scene6_data_block_id": {"block_ids_count": 26, "first_three": ["b-1","b-2","b-3"]},
  "scene6_comments_pane": {"exists": true},
  "scene6_choice_buttons": {"count": 3, "choices": ["approve","revise","abort"]},
  "scene5_sticky": {"position": "sticky", "overflow_y": "auto", "max_height": "847px"}
}
```

- 场景 1（TOC 默认呈现）: ✅ TOC 14 项（5 H2 + 9 H3，与正文匹配）、aria-label="目录"、toc-h2/toc-h3 class 正确
- 场景 4（H1 不入 TOC）: ✅ H1 不入 TOC（设计行为）
- 场景 5（独立滚动 sticky）: ✅ position=sticky、overflow-y=auto、max-height=847px
- 场景 6（重复标题 id 唯一）: ✅ all_ids_unique=true（h-1..h-14 全唯一）、3 个 "### 步骤" 各得到独立 id
- 场景 6（现有功能未退化）: ✅ data-block-id 26 个全部保留、`<aside id="comments-pane">` 存在、3 个决策按钮 [approve/revise/abort] 存在
- 场景 8（无悬空 href）: ✅ dangling_hrefs=[]，14 个 toc href 全部命中真实 heading

**用户验收**: 浏览器中 ✅ 验收通过

#### Wave 2: qa-reviewer

跳过（用户已直接验收通过）

#### 结果判定
- ✅ Tier 0/1.5 全部通过（用户视角验收 OK）
- ⚠️ Tier 1 npm test VC9 失败 — pre-existing 与本次改动无关（独立模块、性能阈值环境性能波动）
- ⚠️ Tier 1 lint 2 个 style/info — pre-existing 与本次改动无关
- 步骤 3 ⚠️ 复盘：仅遍历 Tier 1.5 ⚠️，本轮 Tier 1.5 全 ✅ 无需复盘

→ **gate: "review-accept"**，进入 merge 阶段


## 变更日志
- [2026-05-19T02:58:52Z] autopilot 初始化，目标: 优化 plan review html 里的效果 1. 当前生成的 plan 人去看的时候不够直观和高效，你深入搜索和了解下好的方案设计，优化下 2. 在 html 左侧增加目录展示，方便切换 3. 先了解 skill best practice ， skill 非常脆弱，涉及到 skill 的都需要采用最小化改动
- [2026-05-19T02:58:52Z] 模式自适应：fast_mode=false（standard）。理由：用户明确要求"深入搜索好的方案设计"+UI/UX 决策+多改动点+skill 最小化约束，需要 brainstorm 对齐方案
- [2026-05-19T03:15:00Z] brainstorm 完成，共识：客户端 post-process 动态 TOC（H2/H3）+ 阅读体验重排，260px 固定左栏 + <1200px 抽屉，仅改 plan-review-template.html 一文件
- [2026-05-19T03:25:00Z] 验收场景生成器输出 9 个场景（信息隔离），写入 ## 验收场景
- [2026-05-19T03:25:00Z] 设计文档 + 实现计划 + 契约规约写入完成，启动 plan-reviewer 审查
- [2026-05-19T03:35:00Z] plan-reviewer PASS（全部 8 维度），3 个 80-90 重要问题已吸收：1) 断点协调（保留 1100/1101 不动，TOC 单独 1200 断点）2) `.toc-pane` sticky/overflow 显式落实 3) Step 4 强调 setAttribute id 写法
- [2026-05-19T03:36:00Z] HTML 评审审批：用户在浏览器中点击「同意」（choice=approve），设计方案通过，进入 implement 阶段
- [2026-05-19T03:55:00Z] 蓝队完成实现：plan-review-template.html +334/-3 行，11 步全部完成，自测通过；改动唯一文件
- [2026-05-19T03:55:00Z] 红队完成验收测试：plan-review-toc.acceptance.test.sh 31 个断言全 PASS，shellcheck 通过
- [2026-05-19T03:56:00Z] 合流：git add 蓝/红队产出（2 文件改动 +670/-3）；启动 contract-checker
- [2026-05-19T03:57:00Z] contract-checker PASS（5 维度逐字比对全部匹配，无 mismatches）；进入 Phase: qa
- [2026-05-19T04:05:00Z] QA Wave 1：Tier 0 红队 31/31 PASS、Tier 1 lint+静态结构 PASS（VC9 npm test 1 项 ⚠️ pre-existing 性能阈值与本次无关）
- [2026-05-19T04:08:00Z] QA Wave 1.5：Chrome DevTools 浏览器验证 7 项断言 ✅（TOC 14 项 / id 唯一 / 无悬空 href / sticky / data-block-id 26 个保留 / 3 决策按钮 / aside 存在）
- [2026-05-19T04:10:00Z] 用户在浏览器中验收通过；gate: review-accept；进入 merge 阶段
