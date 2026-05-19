## 探索的目的与约束

**用户目标**：优化 autopilot 的 plan-review HTML 评审界面阅读体验。痛点为「找不到关键信息」，长文档时缺少导航与节奏感。

**项目上下文关键发现**：
- `plan-review-template.html` 当前 1321 行，是单文件资产（含 CSS + JS + HTML 结构），客户端调 `marked.parse()` 渲染设计文档
- 布局现状：2 列 grid（中间内容 1fr + 右侧 320px 评论），<1100px 折叠为单列；**无左侧 TOC**
- `launch-plan-review.sh` 通过 Python 脚本提取 state.md 的 `## 设计文档` 区块，注入 `{{DESIGN_CONTENT}}` 占位符
- **极松耦合**：SKILL.md 仅在 design 阶段步骤 4c 一次性 Bash 调用 `launch-plan-review.sh`，HTML/CSS 改动完全不需要碰 SKILL.md
- marked 产物中 H1-H6 已被注入 `data-block-id`，但**没有 id 属性**——不能直接做 hash 锚点跳转
- `data-block-id` 已被评论锚点系统占用，新增 TOC 必须使用独立的 id 命名（如 `h-1`、`h-2`）
- helper.js 与模板 JS 存在双 click listener 冲突，模板已用 `stopImmediatePropagation` 隔离

**明确约束**：
1. **skill 最小化改动铁律**：不改 SKILL.md、launch-plan-review.sh、helper.js、frame-template.html、server.cjs。改动集中在 `plan-review-template.html` 一个文件
2. **保留现有视觉资产**：stringzhao 调色板（墨/纸/雾/烟/炭/苔/琥/朱/天）+ Crimson Pro/Noto Serif SC/Inter 字体保留不动
3. **不破坏现有交互**：评论选区按钮、决策按钮、WS 通信、双 listener 阻断逻辑必须 100% 保留
4. **不依赖 AI 在 plan 中写特殊标记**：所有改进必须对任意 markdown 输入都生效

---

## 候选方案与权衡

### 方案 A（选定）：客户端 post-process 动态 TOC + 阅读体验重排

**核心思路**：在 plan-review-template.html 的 JS 渲染段内，marked.parse() 完成后扫描所有 H2/H3 元素，为其补充唯一 id（`h-1`、`h-2`...），同时构造左侧 TOC 容器。CSS 引入第三栏 grid 列（左 260px / 中间 1fr / 右 320px）。窄屏（<1200px）将 TOC 折叠为左上角抽屉按钮，点击展开。Scroll/IntersectionObserver 驱动 TOC 高亮当前可视的章节。

**改动范围**：
- 单文件：`plugins/autopilot/scripts/visual-companion/plan-review-template.html`
- 新增 CSS：~80 行（TOC 容器、列表、抽屉、高亮样式）
- 新增 JS：~60 行（TOC 生成、滚动同步、抽屉交互）
- 修改 CSS：~20 行（grid-template-columns 由 2 列改 3 列、断点调整）
- 阅读体验调优 CSS：~50 行（H2/H3 重量、列表节奏、代码块、表格、引用）
- 估算总增量：≈ 200 行（在现有 1321 行基础上 +15%）

**优势**：
- ✅ 完全不动 SKILL.md / launch-plan-review.sh / helper.js / server.cjs，符合"最小化改动"约束
- ✅ TOC 动态适配任意 plan 内容
- ✅ 与现有 marked 渲染流程在同一时序里收尾，无新增异步步骤
- ✅ 阅读体验重排保留 stringzhao 调色板，仅在排版细节升级

**劣势**：
- ⚠️ AI 写嵌套过深 H4/H5 或重复小标题时，需要 fallback（限制 TOC 深度到 H3 + id 用递增计数器避免冲突）
- ⚠️ data-block-id 系统已存在，新增 id 属性需保证不冲突（采用不同前缀 `h-` vs `b-`）
- ⚠️ 评论卡牌 positionCards() 算法当前已经在做绝对定位，新增三栏布局不能影响其 cascade 计算

### 方案 B（已排除）：TOC 仅锁定顶层固定章节

**核心思路**：TOC 只列出 state.md 约定的 `## 设计文档` / `## 实现计划` / `## 验证方案` / `## QA 报告` 等顶层节点，下方 H3 不入 TOC。

**优势**：实现最简、TOC 跨 plan 一致。

**排除原因**：用户选择「H2/H3 动态全部入 TOC」，希望 TOC 跟随 markdown 实际节奏。

### 方案 C（已排除）：服务端预生成 TOC 注入

**核心思路**：launch-plan-review.sh 的 Python 提取段同时生成 TOC HTML，新增 `{{TOC_CONTENT}}` 占位符注入。

**排除原因**：会改动 launch-plan-review.sh，违反"skill 最小化改动"约束（launch-plan-review.sh 是 SKILL 调用入口的一部分），同时 Python 端做 markdown 解析需引入新依赖（或写正则）。

---

## 选择与理由

**选定方案：方案 A — 客户端 post-process 动态 TOC + 阅读体验重排**

**选择理由**：
1. **改动半径最小**：单文件 plan-review-template.html，与 SKILL.md 完全解耦，符合用户最强约束
2. **历史经验背书**：知识库 patterns.md 记录"HTML 模板用 setAttribute 设置 id"、"事件委托用 stopImmediatePropagation 阻断 helper.js 双重触发"，方案 A 完整继承这些防御
3. **响应式天然适配**：现有模板已有 <1100px 折叠机制，扩展到 <1200px 触发左侧抽屉是同源思路
4. **YAGNI 原则贯彻**：不做 callout、不做摘要卡、不做 mermaid/highlight 扩展。只做 TOC + 排版重排两件事

**被排除方案**：
- 方案 B：TOC 表达力受限，未达用户期望的「跟随 markdown 节奏」体验
- 方案 C：触动 SKILL 调用入口脚本，违反最小化原则

---

## 待主 SKILL 接力的设计决策

主 SKILL 在写 ## 设计文档 / ## 实现计划 时需要在以下决策点深化：

### 已经确认（无需再问用户）
1. **TOC 形态**：260px 固定左侧脱列 + 阅读高亮，宽屏（>=1200px）固定显示，窄屏（<1200px）折叠为左上角抽屉按钮
2. **TOC 内容**：H2/H3 全部入 TOC，H4+ 不进入；通过客户端 post-process marked 渲染产物生成
3. **anchor 命名**：使用 `h-1`、`h-2`...（避免与已有 `data-block-id="b-N"` 冲突）；text 重复时用计数器 fallback
4. **改动边界**：仅 `plan-review-template.html`；不改 SKILL.md / launch-plan-review.sh / helper.js / frame-template.html / server.cjs
5. **样式调优范围**：阅读体验重排（H 标题层级、列表节奏、代码块、表格、引用、间距）；保留 stringzhao 调色板与字体
6. **不做事项**：不做 callout 块、不做顶部摘要卡片、不做 markdown 扩展（mermaid / highlight.js）

### 主 SKILL 需要在设计文档中深化的细节
1. **TOC 高亮算法**：使用 IntersectionObserver 还是 scroll + getBoundingClientRect？前者性能更好，但需注意 sticky toolbar 偏移补偿
2. **Grid 三栏断点**：>=1200px 三栏 / 800-1200px 两栏（中 + 右，TOC 抽屉化） / <800px 单列（保留现有逻辑）。具体断点和过渡需在设计文档落实
3. **阅读体验重排具体清单**：H1/H2/H3 字号与重量、列表 marker 样式、代码块 padding/边框、表格 header 强调、blockquote 边线
4. **id 冲突防御**：post-process 时既要补 `id="h-N"`（TOC 锚点），又要保留已注入的 `data-block-id="b-N"`（评论锚点）。**必须使用 setAttribute('id', ...) 而非 dataset.id**（patterns.md 记录的红队 grep 经验）
5. **抽屉交互**：使用 `<details>` 还是手写 toggle？要避免与现有 click listener 冲突（若新增 button 必须考虑 stopImmediatePropagation 是否需要扩展）
6. **打印样式**：`@media print` 是否隐藏 TOC？（现有模板未声明，可顺手补充）
7. **契约规约**：state.md frontmatter `contract_required: true`，设计文档需包含 `## 契约规约` 章节，定义 TOC DOM 接口（容器 id、TOC 项 selector、anchor id 命名规则）以便红队测试

### 验收场景候选（供主 SKILL 在 plan-reviewer 阶段细化）
1. 任意 plan 渲染后，左侧出现 TOC，列出所有 H2 + H3
2. 点击 TOC 项，正文滚动到对应标题
3. 滚动正文，TOC 当前章节高亮跟随
4. 评论按钮在选区上方仍正常浮现，决策按钮（同意/反馈）依然只发送一次 WS 事件
5. 窗口宽度 800-1199px 时，TOC 折叠为左上角按钮
6. 窗口宽度 <800px 时，行为不退化（保留现有单列体验）
7. 现有 stringzhao 调色板与字体未被替换
