---
name: autopilot-brainstorm
description: autopilot design 阶段需求探索专用。在写设计文档前通过逐个澄清问题理解用户意图，提出 2-3 方案让用户选择，输出共识总结到 brainstorm.md 后交回主 skill。当 autopilot skill 在 design 阶段委托调用时使用。
---

# autopilot-brainstorm — design 阶段需求探索代理

在写任何设计文档之前，通过自然的协作对话将用户意图转化为清晰共识。逐个澄清问题，提出 2-3 种方案，输出 brainstorm.md 后交回主 skill 接力。

<HARD-GATE>
在输出 brainstorm.md 之前，禁止写设计文档、禁止更新 state.md 的 ## 设计文档 / ## 实现计划区域、禁止调用任何实现 skill。无论任务看起来多简单，都必须完整走完探索流程。
</HARD-GATE>

## Anti-Pattern: "这太简单不需要 brainstorm"

**每个任务都必须走这个流程**——一个配置改动、一个工具函数、一个"明显"的需求。"简单"是返工的根源：未经检验的假设在小任务里造成最多浪费。探索可以很短（真正简单的任务 2-3 个问题即可），但必须走完。

## Checklist（必须 TaskCreate 每项，按顺序完成）

你**必须**为以下每项创建 Task 并依序完成：

1. **探索项目上下文**：使用 1-2 个 Explore agent 分析代码库，检查文件、文档、近期 commit；识别当前实现模式和相关约束
2. **视觉伴侣征求**（可选独立消息）：评估后续问题是否涉及视觉内容（UI mockup、架构图、布局对比），如果是，单独发一条消息征求同意（参见 `references/visual-companion-guide.md`）
3. **逐个澄清问题**：一次一个问题（AskUserQuestion），聚焦目的、约束、成功标准；优先多选题
4. **提出 2-3 种方案**：每种含权衡分析，先展示推荐方案，使用 AskUserQuestion 让用户选择
5. **写 brainstorm.md 后交回主 SKILL**：将共识总结写入 `$TASK_DIR/brainstorm.md`，然后退出，由主 skill 接力写设计文档

## The Process

**理解用户意图**：

- 先探索项目现状（文件、文档、近期 commit），再提问——避免问已有答案的问题
- 评估范围：如果目标描述多个独立子系统，立即标记可能需要项目模式拆分，不要深入细节
- 对于合适范围的任务，一次一个问题逐步澄清
- 优先多选题（AskUserQuestion options），开放式也可以；每条消息只有一个问题
- 聚焦：目的、约束、成功标准

**探索方案**：

- 提出 2-3 种不同方案，每种含权衡分析
- 先展示推荐方案并解释推荐理由
- 方案对比用 AskUserQuestion 让用户选择

**视觉伴侣（可选）**：

评估后续问题是否涉及视觉内容时，单独一条消息征求同意：
> "后续可能涉及视觉内容（mockup、布局对比等），可以在浏览器中展示。需要启用视觉伴侣吗？"

用户同意后参见 `references/visual-companion-guide.md` 操作。**判断标准**：
- **用浏览器**：UI mockup、架构图、布局对比、设计风格对比
- **用终端**：需求问题、概念选择、权衡列表、技术决策

## Key Principles

- **一次一个问题**：不要一条消息塞多个问题，用户容易遗漏
- **多选优先**：AskUserQuestion options 比开放式更易回答
- **YAGNI 无情移除**：从所有设计中清除不必要的功能，"以后可能用到"不是理由
- **递进验证**：展示方案、获得认可后再推进，不要单方面决定
- **灵活回溯**：发现理解偏差时立刻返回澄清，不要在错误假设上继续

## brainstorm.md 模板

写入 `$TASK_DIR/brainstorm.md`（`task_dir` 从 frontmatter 读取）：

```markdown
## 探索的目的与约束

（用户目标一句话 + 项目上下文探索关键发现 + 明确约束）

## 候选方案与权衡

### 方案 A：...
- 优势：...
- 劣势：...

### 方案 B：...
- 优势：...
- 劣势：...

### 方案 C（如有）：...

## 选择与理由

选定方案：X
选择理由：...
被排除方案及原因：...

## 待主 SKILL 接力的设计决策

（列出用户已确认的决策、关键约束、需要在设计文档中深化的点）
```

## 交接协议

**必须遵守**：

- 从 state.md frontmatter 读取 `task_dir`，将 brainstorm.md 写入 `$TASK_DIR/brainstorm.md`
- **独立调用（无 state.md，如 `/autopilot:autopilot-brainstorm` 直接调用）时**：`task_dir` 必须落项目根下 `.autopilot/runtime/requirements/<slug>`——slug 用 `YYYYMMDD-<任务关键词>`（参考 `runtime/requirements/` 下已有目录命名）。**严禁**写到顶层 `.autopilot/requirements/`：那是 v3.35 前旧路径，已被 `.gitignore` 拦截，落那里等于丢失产物（不入库、主流程读不到）。
- **禁止**修改 state.md 的 frontmatter（`phase`、`gate` 等字段由主 skill 控制）
- **禁止**写入 state.md 的 `## 设计文档` 或 `## 实现计划` 区域
- brainstorm.md 写入完成后，本 skill 职责结束，主 SKILL 接力：读取 brainstorm.md → 写设计文档 → plan-reviewer → AskUserQuestion 审批
