
## Context

基于 2026-09-06 三agent并行调研（957 主会话 + 602 sub-agent transcript、11 项目 439 个 state.md、插件源码全量审查），autopilot 质量已获用户认可，但执行效率存在结构性浪费：

- 同一测试套件单轮 QA 被执行 3~5 次（蓝队自检 / Tier 1 全量 / Tier 5 coverage 的 `jest --coverage` / mutation N 遍）
- 契约被 3 个 agent 重复验证（plan-reviewer 维度7/10 → contract-checker 串行点 → qa-reviewer Section A）
- 蓝/红队各自重复扫描项目技术栈；设计文档全文被复制进 5+ 个 prompt（5~20KB/个）
- qa→qa 回炉 12 次共 113h（P50 116min/轮），auto-fix「修一项跑一次」放大
- stop-hook 每次 stop 做 43 次 frontmatter 全文件重扫 state.md + 4MB transcript jq 解析
- 产物零清理：/tmp/autopilot-artifacts 238MB 无 TTL、relight runtime 3.3GB

用户裁决：做 P0（QA 去重合并 ×3）+ P2（QA 回炉治理 ×2）+ P3（机制性能+卫生 ×2），P1（纯 prompt 预算条款）不做。约束：① 改前深读 skill best practice（已完成，document/skill_best_practices.md）② SKILL.md 行数只减不增 ③ AI First（语义留 AI、机械下沉 bash、不加新状态字段/gate）。

## 整体架构设计

三个任务线性 DAG（同改 SKILL.md/版本号必须串行），每任务独立版本号、独立红队验收：

**T1 p0-qa-dedup（v3.63.0）— QA 重复执行合并**
1. **Tier 1 ∪ Tier 5 coverage 合并执行**：有 coverage 工具的项目，Tier 1 单元测试以 coverage 形态跑一次（jest --coverage / c8），摘要落盘；Tier 5 coverage 判定复用该产物（lib.sh `tier5_coverage_check` 输入改为既有产物路径 + freshness_check 验证新鲜度），不再二次执行套件。改动：SKILL.md Tier 1/Tier 5 表述、references/quantitative-metrics.md、lib.sh、stop-hook §8.5.3。
2. **contract-checker 并入 qa-reviewer Section D**：删 SKILL.md 步骤 2.5 整节（省 1 个串行 agent + 1 次全文件重读）；qa-reviewer-prompt.md 加 Section D（契约字面比对，复用其已读的变更文件全文）；contract_required=true 时编排器在 qa-reviewer prompt 附 `## 契约规约` 章节（契约内容 SSOT 不变，contract-protocol.md 写作规约保留）；删 contract-checker-prompt.md，同步 design-modes.md / state-file-guide.md / stop-hook.sh / setup.sh / README.md 引用。
3. **context.md 探针产物化**：design 步骤 1 探针结果（技术栈/测试框架/测试命令/构建命令）写 `$TASK_DIR/context.md`；蓝队/红队/qa-reviewer prompt 模板改为 Read 该文件，替代各自重复扫描项目。改动：SKILL.md 步骤 1 + 三个 prompt 模板。

**T2 p2-qa-loop（v3.64.0）— QA 回炉治理**
4. **auto-fix 批量修复纪律**：从「逐项修→逐项跑检查」改为「全部失败项先完成观察/假设/验证 → 统一修复 → 一轮检查验证全部」。改动：references/auto-fix-phase.md + SKILL.md auto-fix 段（净减）。
5. **蓝队自检证据复用**：蓝队交付摘要附「自检命令+退出码」清单 → 编排器写 state.md `## 蓝队自检` 区域（内容区域非 frontmatter，不加新字段）→ QA Tier 1 对照：同命令且代码未再变（HEAD sha 比对下沉 lib.sh 确定性判）→ 沿用 ✅ 不重跑；命令等价性语义判断留编排器（AI First）。

**T3 p3-mechanism-hygiene（v3.65.0）— 机制性能与卫生**
6. **lib.sh `load_state` 批量化**：一次 awk 吐全部 frontmatter 字段 KEY=VALUE；stop-hook.sh 开头调一次，43 处 get_field/get_enum_field 改读变量。行为不变量：stop-hook 全场景输出逐字节不变（红队跑既有全部 acceptance 测试回归证明）。
7. **产物卫生**：(a) setup.sh 加 /tmp/autopilot-artifacts TTL 清理（>7 天，SessionStart 幂等）；(b) doctor 报告加 runtime/ 体积客观信号（>500MB 警告，体积检测下沉 lib.sh，语义建议留 AI）。acceptance 测试资产生命周期治理涉及质量策略，**不在本 DAG**，另行向用户决策。

## 任务 DAG 概览

| ID | 任务 | 依赖 | 复杂度 |
|----|------|------|--------|
| p0-qa-dedup | QA 重复执行合并（Tier1∪Tier5 coverage / contract-checker 并入 qa-reviewer / context.md 探针产物化）→ v3.63.0 | - | M |
| p2-qa-loop | QA 回炉治理（auto-fix 批量修复 / 蓝队自检证据复用）→ v3.64.0 | p0-qa-dedup | S |
| p3-mechanism-hygiene | 机制性能与卫生（load_state 批量化 / artifacts TTL + doctor runtime 体积）→ v3.65.0 | p2-qa-loop | M |

## 跨任务设计约束

1. **SKILL.md 行数只减不增**：每任务结束 `wc -l` ≤ 前一任务基线（当前 501 行）；红队断言用语义化净非增（[2026-07-19] v3.58.1 模式）
2. **Best practice 5 条筛**：concise（Claude 已聪明，不解释已知）/ degrees-of-freedom 匹配 / progressive disclosure 一层引用 / solve-don't-punt / 术语一致（document/skill_best_practices.md）
3. **AI First**：语义判断留 AI，机械活下沉 bash；不加新 frontmatter 字段/gate/Tier（T2 用 `## 蓝队自检` 内容区域）
4. **质量闸门不动**：谓词 SSOT、红蓝信息隔离、§5.7/§8.5.x 确定性守卫全部保留；本 DAG 只去重、合并、提速
5. **版本同步四处**：plugin.json / marketplace.json / CLAUDE.md 插件索引 /（package.json 如存在）
6. **契约硬要求**：frontmatter contract_required=true，契约规约见下（跨任务接口 SSOT）

## 契约规约

跨任务接口形状权威（各任务红队验收以此为据）：

- **C1 context.md 格式**（T1 产出，T1 三模板消费）：`$TASK_DIR/context.md` 含 `## 技术栈` / `## 测试框架` / `## 测试命令` / `## 构建命令` 四节；节内 bullet，空节写 `N/A`
- **C2 qa-reviewer Section D**（T1 产出）：报告含 `## Section D: 契约符合性`；contract_required=false 或设计文档无 `## 契约规约` 时输出 `N/A`；mismatch 条目含 severity=high/medium/low
- **C3 蓝队自检区域**（T2 产出）：state.md `## 蓝队自检` 区域，每条 `- <命令> ｜ exit=<码> ｜ <一句话范围>`；编排器 QA 沿用判定结果写入 QA 报告（标注「沿用蓝队自检」）
- **C4 load_state 输出**（T3 产出）：`load_state <state.md>` stdout 为逐行 `KEY=value`（frontmatter 全字段，键原样）；stop-hook source 后字段值与改前 get_field 语义逐字节一致（含枚举归一行为——get_enum_field 的归一逻辑保留在变量赋值处）
- **C5 版本号序列**：T1=v3.63.0 → T2=v3.64.0 → T3=v3.65.0，单调递增，四处同步

## Handoff 策略

每任务 handoff 写：版本号 / 改动文件清单 / SKILL.md 新行数基线 / 对下游的影响点（如 T1 删步骤 2.5 后 T2 改 auto-fix 段时的锚点变化；T1 的 context.md 机制 T2 蓝队 prompt 可复用）。下游任务 design 阶段先读上游 handoff 再探针（文件行号已变，不得沿用过期行号）。

> ✅ Plan 审查通过（全部维度通过），3 条重要问题已采纳补入设计：
> 1. **T1 首步全仓清扫**：`grep -rn contract-checker plugins/autopilot/` 结果为准（实证漏点：contract-protocol.md 4 处活引用 / plugin.json description / SKILL.md:63 fast mode 行），不以设计枚举清单为准
> 2. **T1/T2 显式列出受影响既有 acceptance 测试 + 语义化适配**（[2026-07-19] 模式）：tier5-deterministic-sink / tier5-quantitative（T1 改 tier5_coverage_check 输入语义）、qa-reviewer-prompt / predicate-coverage / tier1-deoverfitting（T1 Section D）、skill-references-consistency（references 文件增删）
> 3. **C4 补重读时机约束**：每次状态文件切换点（auto-chain / 全项目 QA 创建后，stop-hook.sh:489-494/531-536/555-560 实证）须重新调用 load_state，重读时机与改前 get_field 调用点一一对应（防 [2026-05-26] stale-variable 同构回归）

