# Plan 审批 HTML 评审路径指南

详细描述 design 阶段步骤 4 的两条审批路径（4b 默认 / 4c 可选 HTML）。SKILL.md 步骤 4 仅放决策树，详细工作流走本文。

## 路径选择（4a）

唯一开关：state.md frontmatter `html_review: true` → 走 4c HTML 评审，否则走 4b 默认 AskUserQuestion。

环境变量 `AUTOPILOT_HTML_REVIEW=1` 由 setup.sh 在创建任务时一次性同步到 frontmatter；用户视角仍是「export 完启动 autopilot 即可开 HTML 评审」。已存在的任务想中途切换：直接编辑 state.md 的 `html_review` 字段。

## 4b. 默认 AskUserQuestion + preview 路径

使用 `AskUserQuestion` 请求审批，3 个选项：
- **通过，开始实现** — preview 字段填入设计摘要（≤40 行），结构：目标 / 范围 / 关键决策 / 取舍
- **有修改意见** — 用户在 free-text 框输入反馈
- **放弃本次任务**

「通过」选项的 preview 末尾**必须**追加固定提示文案：
```
─────────────────────────────
💡 启用 HTML 评审：
   设置 AUTOPILOT_HTML_REVIEW=1
   或 state.md frontmatter 加 html_review: true
```

用户选「修改」→ 收集 feedback，根据反馈修改设计文档后重新走步骤 3-4。

## 4c. HTML 浏览器评审路径

### 调用方式

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/visual-companion/launch-plan-review.sh "$task_dir"
```

⚠️ **Claude 调用规范（关键）**：
- **必须前台同步调用**：Bash 工具直接执行，**禁用 `run_in_background: true`**
- Bash 工具 `timeout` 参数显式设为 `600000`（10 分钟，工具最大值）
- 用户在浏览器点击后，wait-decision.sh 立即捕获事件 → 脚本退出 → stdout 返回 Claude 主对话**自动继续**，用户**无需回到终端二次操作**
- 后台调用（`nohup … &` 或 `run_in_background: true`）会破坏自动续上的体验，造成"用户点完后还得回终端发消息触发 Claude 读结果"的二次操作问题

`launch-plan-review.sh` 编排：
1. 调 `start-server.sh --project-dir "$task_dir"` 启动 visual-companion
2. 读取 state.md 的 `## 设计文档` + `## 实现计划` 段落，HTML 转义后写入 `$CONTENT_DIR/plan-review.html`
3. 跨平台打开浏览器：`open` (macOS) / `xdg-open` (Linux) / `cmd.exe /c start` (Windows)；失败时 stderr 打印 URL 让用户手动
4. 调 `wait-decision.sh "$state_dir"` 阻塞等待用户操作（默认 30 分钟超时）
5. `stop-server.sh` 关闭服务
6. stdout 输出最终决策 JSON

### stdout 解析（成功判据：stdout 非空且为合法 JSON）

不依赖退出码（macOS 上 `tail -F | grep -m1` 与 timeout 组合的退出码语义不可靠）。

| `choice` 字段 | 处理 |
|---------------|------|
| `approve` | 进步骤 5，feedback（如有）写入变更日志参考 |
| `revise` | feedback 写入变更日志，回到步骤 3 重新设计；下次设计参考 feedback 不丢失 |
| `abort` | 取消任务，frontmatter `phase: cancelled` |

### 降级路径

| 场景 | 行为 |
|------|------|
| stdout 为空 / 解析失败 / 超时 | fallback 到 4b 默认路径 |
| 浏览器打不开（headless / SSH） | launch-plan-review.sh stderr 打印 URL，wait-decision 仍工作；用户手动打开即可 |
| visual-companion server 启动失败 | stderr 报错 → fallback 到 4b |

## 实现细节参考

- `plugins/autopilot/scripts/visual-companion/plan-review-template.html` — HTML 模板（textarea#feedback + 3 个 data-choice 按钮 + `<pre id="design-content">` 占位区）
- `plugins/autopilot/scripts/visual-companion/wait-decision.sh` — FIFO + tail + read 循环，匹配 `"choice":"(approve|revise|abort)"` 行后 stdout 输出原始 JSON
- `plugins/autopilot/scripts/visual-companion/launch-plan-review.sh` — 编排脚本
- `plugins/autopilot/scripts/visual-companion/helper.js` — click 事件 handler 已扩展为附带 `feedback` 字段（读取 `#feedback` textarea）

## 验收测试

- 自动化：`plugins/autopilot/tests/acceptance/plan-review-html.acceptance.test.sh`（22 项断言，shellcheck 0 警告）
- 端到端人工：参见对应任务的 `acceptance-checklist.md`（场景 3 approve / 场景 4 revise+feedback / 场景 5 默认关闭回归）
