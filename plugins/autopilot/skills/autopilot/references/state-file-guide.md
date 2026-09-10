# 状态文件格式指南

## 状态文件字段说明

状态文件（`.autopilot/runtime/active.ptr` 指针指向的 `.autopilot/runtime/requirements/<slug>/state.md`，worktree 中位于 `.autopilot/runtime/sessions/<name>/requirements/<slug>/state.md`）的 frontmatter 包含以下字段：

**AI 可写字段**：
- `phase`: 当前阶段（design → implement → qa → auto-fix → merge → done），AI 更新。**合法值（闭合枚举）：design / implement / qa / auto-fix / merge / done**
- `gate`: 审批门标记，AI 更新。**合法值（闭合枚举）：""（空，无门）/ review-accept**
- `retry_count`: auto-fix 重试计数，AI 在 auto-fix 阶段递增
- `mode`: 任务模式，AI 在 design 阶段 1.5 步骤检测后写入。**合法值（闭合枚举）：""（空）/ single / project / project-qa**
- `qa_scope`: 选择性重跑标记，AI 更新。**合法值（闭合枚举）：""（空，默认全量 QA）/ smoke（diff 小或 fast_mode 触发，跳过 Wave 2 qa-reviewer）/ selective（auto-fix 后只重跑失败 Tier）**
- `tier5_status`: Tier 5 量化指标门禁判定。**合法值（闭合枚举）：""（空，未判）/ na（无 mutation/coverage 工具）/ skipped（smoke 路径主动跳过）/ pass / fail**。**写入者**：stop-hook §8.5.3（na/skipped 自动判，幂等：仅 tier5_status 空时写）/ 编排器（pass/fail，跑工具后调 lib.sh `tier5_coverage_check` / `tier5_mutation_check` 据结果写）。**读者**：stop-hook（gate=review-accept 时校验合规，缺失/越界 → block 回 qa 补判）。详见 references/quantitative-metrics.md
- `e2e_status`: 端到端真实验证分级（QA 结果判定轮与验收决策卡同轮写入，**AI 不写其他时机**）。**合法值（闭合枚举，canonical 小写）：verified（核心变更层级真实产物已被真实驱动并观测——Tier 1.5 谓词全 PASS 且无真实驱动跳过格，**硬判据：执行面清单存在未执行核心链路时 e2e_status 最多 partial，不得标 verified**）/ partial（部分链路实证、部分未实证）/ unverified（关键链路未实证——首跑推迟/全量 mock）**。**读者**：stop-hook §5.5（auto_approve=true 时分级自动推进的唯一判定依据）+ §5.7b（`gate=review-accept ∧ phase=qa ∧ auto_approve=true` 时缺失/越界 → block 回 qa 补判，不耗 retry_count；auto_approve=false 不强制，向后兼容）
- `leftover_critical`: 遗留问题分级计数（与 e2e_status 同轮写入）。**格式：非负整数十进制字符串**（如 `"0"` / `"2"`，无上限）。语义 = 遗留问题中用户可感知/影响核心链路的条数（AI 语义判断，普通遗留不计入）。校验与消费方同 e2e_status（§5.5 达标条件 = `e2e_status=verified ∧ leftover_critical=0 ∧ unexecuted_core_paths=0`；§5.7b fail-safe 校验）。**同轮产物**：验收决策卡持久化到 `$TASK_DIR/acceptance-card.md`（结构契约见 references/qa-report-template.md，红队 TA-7 场景锁定）
- `unexecuted_core_paths`: 执行面清单未执行核心链路计数（与 e2e_status / leftover_critical 同轮写入——QA 结果判定轮与验收决策卡同轮，**AI 不写其他时机**）。**格式：非负整数十进制字符串**（与 leftover_critical 完全同构，如 `"0"` / `"3"`，无上限）。语义 = 验收决策卡「### 端到端真实验证结论」执行面清单中未执行核心链路的条数（清单结构契约见 references/qa-report-template.md；非核心降级链路行内留理由、不计入；纯文档任务写「无可执行链路」豁免行 → `"0"`）。**读者**：stop-hook §5.5（分级达标第三计数条件）+ §5.7b（校验与 e2e_status 同款 fail-safe，缺失/越界 → block 回 qa 补判，不耗 retry_count；auto_approve=false 不强制，向后兼容）
- `next_task`: 下一个就绪任务 ID（项目模式 merge 阶段写入，触发 auto-chain）
- `knowledge_extracted`: 知识提取完成标记，AI 在 merge 阶段设为 `"true"`（有新增）或 `"skipped"`（无新增）。**合法值（闭合枚举）：""（空）/ true / skipped**。stop-hook 的 phase=done 守卫检查此字段，缺失或空值会回滚到 merge
- `fast_mode`: 三态字段。`""`（默认/未定）/`"true"`（fast）/`"false"`（standard）。setup.sh 的 `--fast` / `--standard` flag 时直接写入；为空时 AI 在 design 步骤 1 探针后按自适应规则写回（bug 修复/小改动/单一概念跨文件 search-replace→true，架构权衡/新抽象/探索未知模块→false，不确定→true），写入后整个生命周期不再修改

- `html_review`: 布尔值（默认 false）。设为 `true` 时，design 阶段步骤 4 启用 HTML 浏览器评审路径（自动打开浏览器渲染设计文档 + 反馈输入 + 通过/修改/放弃按钮）。setup.sh 创建任务时若环境变量 `AUTOPILOT_HTML_REVIEW=1` 则自动写入 `true`，否则写 `false`；用户可手动编辑该字段覆盖（编辑生效需在下一次步骤 4 判定时读到）。
- `auto_approve`: 全程自动驾驶开关。来源：(1) stop-hook auto-chain（项目子任务）；(2) AI design 步骤 4 据低风险判断设 `true`（跳过审批 + QA gate）；(3) revise 回 design 重置 `false`。`true` 时 §5.5 自动跳过 review-accept gate 直接 merge。

**stop-hook 管理（AI 只读）**：
- `iteration`: 当前迭代次数，stop-hook 自动递增（stop-hook 段仅此一项；auto_approve 已移至 AI 可写字段）

**setup.sh 创建（AI 不修改）**：
- `max_iterations`: 最大迭代次数（默认 30）
- `max_retries`: auto-fix 最大重试次数（默认 3）
- `plan_mode`: **已弃用**，新代码不读。旧值 `"deep"` 兼容期保留（行为同默认 `""`，均触发 brainstorm 探索流程）。真正的开关是 `fast_mode`
- `brief_file`: 项目子任务简报文件路径（项目模式自动设置）
- `task_dir`: 需求管理文件夹路径
- `session_id`: 会话 ID（`--headless` 时 setup.sh 写空，由 stop-hook Guard 1 首轮认领真实 runtime session）
- `headless`: 无人值守确定性运行档位。**合法值：canonical `true`；空 = 交互模式（不设 false，非 headless 模板零字面量）**。写入者=setup.sh（唯一）：仅 `--headless` 传入时发射 `headless: true` 行，幂等、与 `--fast`/`--standard` 可组合；读者=编排器 AI（交互点确定性化判定），stop-hook 不读此字段。行为矩阵 / 留痕契约 / 组合语义见 [references/headless-protocol.md](headless-protocol.md)
- `started_at`: 启动时间戳（ISO 8601）
- `contract_required`: 是否启用契约规约校验（plan-reviewer 维度 7 + qa-reviewer Section D）。setup.sh 新建时写入 `true`，旧 state.md 无此字段视为 `false`，自动豁免。

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

> **枚举归一说明**：shell 会对上述枚举字段（phase/gate/mode/qa_scope/knowledge_extracted/tier5_status）的值机械归一大小写、下划线↔连字符；越界值（不在闭合枚举内）会触发 stop-hook 纠正并退回 AI 提示。**不要依赖近义词或大小写变体**，请严格使用上述列出的 canonical 值。

## 更新原则

使用 Edit 工具精确修改字段值，不要用 Write 重写整个文件。

## 契约规约 章节

设计文档应在 `## 设计文档` 之后增加此章节（红蓝队 + plan-reviewer + qa-reviewer 共同的接口形状权威），详见 [references/contract-protocol.md](contract-protocol.md)。frontmatter `contract_required` 缺失或 false 时可省略。

## 验收场景 区域（谓词 SSOT）

design 步骤 2 编排器把验收场景生成器的输出冻结写入 `## 验收场景`，内容为预注册验收谓词（EARS-OST + 观测绑定，格式见 references/scenario-generator-prompt.md）。**这是全链路谓词的唯一权威源（SSOT）**：plan-reviewer 据此做覆盖分析、红队据 det-machine/real-process 谓词写 Tier-0 硬断言、QA Tier 1.5 据此驱动真实产物求值产三元组、谓词闸门据三元组放行。生成器失败时该区域填 `N/A`，下游各环节按各自降级处理。

**谓词格式规约**（stop-hook §5.7 机械解析，必须遵守）：
- 用 bullet-list + fullwidth `｜` 分隔各字段，禁 halfwidth `|`（避 jq 管道符 hazard）。
- 每条谓词一行：`- **<id> [channel]** <描述> ｜ observe: <观测> ｜ assert: <DbC> ｜ driver: <type>:<target> ｜ artifact: <path>`。
- `driver` type 枚举：`curl` / `playwright` / `node-script`（禁网络/外部依赖）/ `fs-grep` / `freshness`。`node-script` 不得用于 `curl|fetch|playwright|overmind|pylon|mysql` 类观测。
- `artifact` 路径约定：`/tmp/autopilot-artifacts/<pred-id>.out`。QA 求值时编排器写入真实驱动输出，stop-hook §5.7 校验文件存在且非空，不依赖 ## QA 报告。PASS 谓词须将真实驱动输出写入预注册 artifact 路径，缺失即 block 回 qa（非 auto-fix，不耗 retry_count）。

## 蓝队自检 区域（自检证据复用）

implement 合流时编排器写入：**首行 `tree_sig: <64-hex>`**（lib.sh `tree_sig` 输出），随后每条 `- <命令> ｜ exit=<码> ｜ <一句话范围>`。QA Tier 1 满足「同语义命令 + exit=0 + tree_sig 匹配」三条件才沿用（缺一重跑，QA 报告标注「沿用蓝队自检」）；auto-fix 触及任何测试文件 → 作废本区域；区域缺失 → QA 照常执行。

<!-- deprecated: ## 红队验收测试 / ## QA 报告 / ## 变更日志 区块已废弃（v3.37+），AI 在对话中产出，不持久化到 state.md -->
