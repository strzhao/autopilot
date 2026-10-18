# Visual Companion 使用指南

在 brainstorm 需求探索阶段，浏览器端视觉伴侣用于展示 mockup、图表和视觉选项。

## 启动

```bash
# 使用 task_dir 作为项目目录，mockup 文件持久化
${CLAUDE_PLUGIN_ROOT}/scripts/visual-companion/start-server.sh --project-dir $TASK_DIR
```

返回 JSON：`{"type":"server-started","port":52341,"url":"http://localhost:52341","screen_dir":"...","state_dir":"..."}`

保存 `screen_dir` 和 `state_dir`，告知用户打开 URL。

## 每次写入流程

1. **检查服务器存活**：`$STATE_DIR/server-info` 存在？`$STATE_DIR/server-stopped` 不存在？
2. **写 HTML 到 screen_dir**：用 Write 工具创建新文件（语义命名：`layout.html`、`approach.html`）
3. **通知用户**：提醒 URL + 简述屏幕内容 + 请求终端反馈
4. **下次轮次**：读 `$STATE_DIR/events`（如存在）获取用户浏览器交互，合并终端反馈
5. **迭代或推进**：反馈修改当前屏幕则写新版本（`layout-v2.html`），验证通过再推进
6. **回到终端**：下一步不需要浏览器时，推送 waiting 页面清除旧内容

## 写入内容片段（推荐）

只写页面内容，服务器自动包装框架模板。无需 `<html>`、CSS、`<script>`。

### 可用 CSS 类

**选项卡** `div.options > div.option[data-choice]`：A/B/C 选择
**卡片** `div.cards > div.card[data-choice]`：视觉设计对比
**Mockup** `div.mockup > div.mockup-header + div.mockup-body`：预览容器
**分栏** `div.split`：左右并排对比
**多选** `div.options[data-multiselect]`：允许选择多项

### 示例

```html
<h2>哪种布局更好？</h2>
<div class="options">
  <div class="option" data-choice="a" onclick="toggleSelect(this)">
    <div class="letter">A</div>
    <div class="content"><h3>单列</h3><p>干净的阅读体验</p></div>
  </div>
  <div class="option" data-choice="b" onclick="toggleSelect(this)">
    <div class="letter">B</div>
    <div class="content"><h3>双列</h3><p>侧栏导航 + 主内容</p></div>
  </div>
</div>
```

## 文件命名

- 语义名称：`platform.html`、`visual-style.html`
- 不重用文件名，每个屏幕用新文件
- 迭代版本加后缀：`layout-v2.html`

## 关闭

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/visual-companion/stop-server.sh $SESSION_DIR
```

使用 `--project-dir` 时，mockup 文件持久化在 `$TASK_DIR/visual/` 中。

## Mockup 全保真规范（四锚定）

mockup 是「视觉精确源」——AI 手写 HTML 若掺占位内容，会被下游当真实设计双层失真。生成时四项全部锚定真实源：

1. **真实 tokens**：读项目 theme/tokens 文件（`colors.json` / `tokens.scss` / tailwind config 等），色彩、圆角、间距逐字引用，禁止目测近似值。
2. **真实数据**：用仓库 seed 数据、接口样例、README 示例；禁止编造数字与 lorem ipsum。
3. **真实设备框**：按目标平台画状态栏/导航栏/手势条（iOS 灵动岛 / Android 打孔屏 / 桌面浏览器窗口框）。
4. **真实字体栈**：引用项目实际 font-family 与字阶，不假设系统默认。

禁占位卡片（灰矩形 +「内容区」占位文字）、禁拍脑袋主观评分表（无锚依据的打分）。

## VLM 自检环（写入后 Feedback Loop）

每屏写入后执行，通过才推进下一屏：

1. 读回渲染结果，自评单一问题：「能否以假乱真当产品截图？」
2. 不达标 → 按 VLM 反馈修正重写（`<name>-v2.html`），再自评。
3. 上限 2 轮——防无限循环（与编排器 max_retries 同构）；2 轮后仍不达标，如实向用户说明差距点后推进。

## Design Anchor 冻结协议

**用户确认选定方案是冻结前置**——未经用户确认不得冻结。确认后：

1. 把选定 mockup 拷贝到 `$TASK_DIR/design-anchor/`（HTML 源 + `README.md` 渲染说明：如何打开、目标平台、字体依赖）。
2. 写 `$TASK_DIR/design-anchor/manifest.md`，含**冻结声明**：本目录为冻结后唯一视觉锚，design/implement/qa 各阶段禁止修改锚；后续还原对照与 anchor-compare 谓词均以本锚为唯一基准。
3. 条件短路：纯后端任务不启用视觉伴侣——无锚则下游 anchor-compare 自然不生成。
