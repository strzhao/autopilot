# Brainstorm — 飞书飞阅评论改造

## 用户原目标

> 优化 plan review html 的评审效果，当前只有简单的修改建议，不方便，也不准确，我希望优化成类似飞书文档一样的飞阅评论效果，可以任意选择某一段评论，然后同意和反馈 2 个按钮放到最顶部，设置也改到最顶部

## Q1 提交模型

**选定：评论累积 + 决策一次提交**

最终 payload：
```json
{
  "choice": "revise",
  "comments": [
    {"anchor":"h2-2","quote":"红队铁律","text":"这里太严苛"},
    {"anchor":"p-7","text":"建议加一个降级"}
  ],
  "feedback": ""
}
```

理由：
- 协议向后兼容（wait-decision.sh 的检测正则 `"choice":"(approve|revise|abort)"` 不变）
- comments 数组作为 revise 的结构化反馈传给下一轮 design
- approve 时 comments 也能保留（autopilot 知识沉淀阶段可参考）
- 无需新增 state-dir/comments.jsonl 状态文件（避免 server 端额外存储路径）

## Q2 按钮组合

**选定：顶部 2 大按钮 + abort 收进右侧 ⋯ 菜单**

布局：
- 顶部 sticky 工具栏左侧：标题
- 中间：「同意」「反馈」2 个主按钮
- 右侧：⋯ 下拉菜单（含 "放弃任务" + "决策后自动关闭" toggle）

## Q3 评论触发

**选定：选中文本 → 浮动「+ 评论」气泡（飞书飞阅经典）**

实现要点：
- 监听 `selectionchange`，光标附近显示浮动按钮
- 按钮位置：选区底部下方 8px
- 点击 → 在右侧 marginalia 栏对应位置打开新评论卡片（自动 focus textarea）
- anchor 策略：取选区起点所在的最近 block（h2/h3/p/li/blockquote/pre）的 data-block-id；选中文本记为 quote 字段

## Q4 评论展示

**选定：右侧 marginalia 栏**

布局：
- 阅读栏：max-width 从 1400px 收窄到 ~960px
- 右侧 marginalia 栏：~320px
- 评论卡片纵向对齐锚点 top 位置（同一锚点多卡片纵向堆叠）
- 卡片样式延续 stringzhao.life/colors（纸色背景 + 苔色强调）
- 点击卡片 → 高亮原文锚点 + scroll into view
- 评论卡片支持：编辑、删除（不支持回复，飞阅简化版）

## 我的细节判断（不再追问，在最终审批让用户调整）

- **跨 block 选区**：取 selection 起点所在 block 作为 anchor（飞书同样策略）
- **多评论锚点**：同一 block 可多条评论，纵向堆叠
- **空评论提交拦截**：textarea 为空时禁用「保存」按钮
- **放弃确认**：菜单中点「放弃任务」弹 confirm 二次确认（destructive）
- **小屏降级**：宽度 < 1100px 时 marginalia 改为底部抽屉（autopilot 主要是桌面，降级简单即可）
- **空评论流程**：用户全程没加评论也没填 feedback，仍可直接点「同意」或「反馈」；点「反馈」时 comments=[] && feedback="" 时给 toast 提示「请添加评论或写反馈」拦截一次（避免空 revise）

## 不做的（YAGNI）

- 评论回复 / 多人协作（autopilot 单用户）
- 评论持久化跨会话（评审是一次性的）
- @ 提及 / emoji reaction
- 评论 markdown 渲染（纯文本足够）
- 评论时间戳显示（同一会话内无意义）
