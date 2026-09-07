---
id: p0-qa-dedup
depends_on: []
status: pending
---

# p0-qa-dedup · QA 重复执行合并 → v3.63.0

## 目标
消除单轮 QA 中同一测试套件的重复执行与契约的三重验证：① Tier 1 与 Tier 5 coverage 合并为一次 coverage 形态执行 ② contract-checker agent 并入 qa-reviewer Section D（删 implement 后串行点）③ 项目上下文探针产物化（context.md），蓝/红/qa-reviewer 不再各自重复扫描。

## 架构上下文
- 完整设计见 `.autopilot/project/design.md`（T1 节 + 跨任务设计约束 + 契约规约 C1/C2/C5）
- 基线行数：SKILL.md 501 / quantitative-metrics.md 181 / qa-reviewer-prompt.md 182 / contract-checker-prompt.md 93 / blue-team-prompt.md 41 / red-team-prompt.md 72 / design-modes.md 69 / lib.sh 1597 / stop-hook.sh 1059
- 现状证据：SKILL.md 步骤 2.5（contract-checker 串行点）；lib.sh:282-470（detect_quantitative_tools / tier5_coverage_check / tier5_mutation_check）；stop-hook §8.5.3（tier5_status 自动判）；stop-hook.sh 与 setup.sh 含 contract-checker 引用
- **首步必须全仓清扫**：`grep -rn contract-checker plugins/autopilot/`，引用清单以 grep 结果为准（已知漏点：contract-protocol.md 4 处活引用 / plugin.json description / SKILL.md:63 fast mode 行），不以下面枚举为准

## 输出契约
- C1 `$TASK_DIR/context.md`：`## 技术栈` / `## 测试框架` / `## 测试命令` / `## 构建命令` 四节，空节写 `N/A`；design 步骤 1 探针时写入，蓝队/红队/qa-reviewer prompt 模板改为 Read 该文件
- C2 qa-reviewer 报告含 `## Section D: 契约符合性`；contract_required=false 或无 `## 契约规约` 时输出 `N/A`；mismatch 条目含 severity=high/medium/low
- C5 版本号 v3.63.0，四处同步（plugin.json / marketplace.json / CLAUDE.md 插件索引 / package.json 如存在）

## 跨任务约束（全文见 design.md）
- SKILL.md 行数只减不增（≤501，删步骤 2.5 应净减）
- AI First：语义留 AI（命令等价性、契约比对判断），机械下沉 bash（coverage 产物新鲜度）
- 质量闸门不动：谓词 SSOT、红蓝隔离、§5.7/§8.5.x 守卫保留；contract-protocol.md 写作规约保留只去 checker 执行引用
- 降级路径：无 coverage 工具的项目 Tier 1 维持原形态、Tier 5 维持 na/skipped 现状

## 受影响既有 acceptance 测试（须语义化适配，[2026-07-19] 模式）
- tier5-deterministic-sink / tier5-quantitative（tier5_coverage_check 输入语义变化）
- qa-reviewer-prompt / predicate-coverage / tier1-deoverfitting（qa-reviewer-prompt 加 Section D）
- skill-references-consistency（contract-checker-prompt.md 删除，references 文件清单变化）
- skill-md-net-shrinkage / skill-shrinkage-invariants（行数约束锁）

## 验收标准
- 红队新验收测试锁 C1/C2/C5 + 降级路径；上述既有测试全绿
- stop-hook §8.5.3 的 tier5_status 三态判定行为不变
- 无 coverage 工具项目：Tier 1 / Tier 5 行为逐字节不变
