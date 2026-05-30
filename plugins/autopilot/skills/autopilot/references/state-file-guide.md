# 状态文件格式指南

## 状态文件字段说明

状态文件（`.autopilot/runtime/active.ptr` 指针指向的 `.autopilot/runtime/requirements/<slug>/state.md`，worktree 中位于 `.autopilot/runtime/sessions/<name>/requirements/<slug>/state.md`）的 frontmatter 包含以下字段：

**AI 可写字段**：
- `phase`: 当前阶段（design → implement → qa → auto-fix → merge → done），AI 更新
- `gate`: 审批门标记，AI 更新
- `retry_count`: auto-fix 重试计数，AI 在 auto-fix 阶段递增
- `mode`: 任务模式（""/"single"/"project"），AI 在 design 阶段 1.5 步骤检测后写入
- `qa_scope`: 选择性重跑标记，AI 更新；可选值：`"smoke"`（diff 小或 fast_mode 触发，跳过 Wave 2 qa-reviewer）/ `"selective"`（auto-fix 后只重跑失败 Tier）/ `""`（默认全量 QA）
- `next_task`: 下一个就绪任务 ID（项目模式 merge 阶段写入，触发 auto-chain）
- `knowledge_extracted`: 知识提取完成标记，AI 在 merge 阶段设为 `"true"`（有新增）或 `"skipped"`（无新增）。stop-hook 的 phase=done 守卫检查此字段，缺失或空值会回滚到 merge
- `fast_mode`: 三态字段。`""`（默认/未定）/`"true"`（fast）/`"false"`（standard）。setup.sh 的 `--fast` / `--standard` flag 时直接写入；为空时 AI 在启动流程步骤 2 中按自适应规则写回（bug 修复/小改动/单一概念跨文件 search-replace→true，架构权衡/新抽象/探索未知模块→false，不确定→true），写入后整个生命周期不再修改

- `html_review`: 布尔值（默认 false）。设为 `true` 时，design 阶段步骤 4 启用 HTML 浏览器评审路径（自动打开浏览器渲染设计文档 + 反馈输入 + 通过/修改/放弃按钮）。setup.sh 创建任务时若环境变量 `AUTOPILOT_HTML_REVIEW=1` 则自动写入 `true`，否则写 `false`；用户可手动编辑该字段覆盖（编辑生效需在下一次步骤 4 判定时读到）。

**stop-hook 管理（AI 只读）**：
- `iteration`: 当前迭代次数，stop-hook 自动递增
- `auto_approve`: auto-chain 时为 true，失败回退为 false

**setup.sh 创建（AI 不修改）**：
- `max_iterations`: 最大迭代次数（默认 30）
- `max_retries`: auto-fix 最大重试次数（默认 3）
- `plan_mode`: **已弃用**，新代码不读。旧值 `"deep"` 兼容期保留（行为同默认 `""`，均触发 brainstorm 探索流程）。真正的开关是 `fast_mode`
- `brief_file`: 项目子任务简报文件路径（项目模式自动设置）
- `task_dir`: 需求管理文件夹路径
- `session_id`: 会话 ID
- `started_at`: 启动时间戳（ISO 8601）
- `contract_required`: 是否启用契约规约校验（plan-reviewer 维度 7 + contract-checker Agent）。setup.sh 新建时写入 `true`，旧 state.md 无此字段视为 `false`，自动豁免。

## 项目模式设计模板

项目模式（`--project` flag 或 step 1 检测）时，将以下内容写入状态文件 `## 设计文档` 区域：

```markdown
## Context
(为什么需要这个项目，解决什么问题)

## 整体架构设计
- 系统概览（组件、数据流、集成点）
- 关键技术决策和权衡

## 任务 DAG 概览
| ID | 任务 | 依赖 | 复杂度 |
|----|------|------|--------|
| 001-xxx | ... | - | S/M/L |
| 002-xxx | ... | 001-xxx | S/M/L |

## 跨任务设计约束
(命名规范、共享接口、错误处理模式等)

## Handoff 策略
(任务间信息传递的关键内容)
```

## 更新原则

使用 Edit 工具精确修改字段值，不要用 Write 重写整个文件。

## 契约规约 章节

设计文档应在 `## 设计文档` 之后增加 `## 契约规约` 章节，作为红蓝队 + plan-reviewer + contract-checker 共同的接口形状权威。

详见 [references/contract-protocol.md](contract-protocol.md)

N/A 整体跳过：frontmatter `contract_required` 缺失或 false 时，本章节可省略。

## 验收场景 区域（谓词 SSOT）

design 步骤 2 编排器把验收场景生成器的输出冻结写入 `## 验收场景`，内容为预注册验收谓词（EARS-OST + 观测绑定，格式见 references/scenario-generator-prompt.md）。**这是全链路谓词的唯一权威源（SSOT）**：plan-reviewer 据此做覆盖分析、红队据 det-machine/real-process 谓词写 Tier-0 硬断言、QA Tier 1.5 据此驱动真实产物求值产三元组、谓词闸门据三元组放行。生成器失败时该区域填 `N/A`，下游各环节按各自降级处理。

<!-- deprecated: ## 红队验收测试 / ## QA 报告 / ## 变更日志 区块已废弃（v3.37+），AI 在对话中产出，不持久化到 state.md -->
