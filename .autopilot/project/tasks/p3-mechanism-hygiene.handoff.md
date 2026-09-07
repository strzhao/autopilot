---
id: p3-mechanism-hygiene
status: done
---

# p3-mechanism-hygiene.handoff — 机制性能与卫生（v3.65.0）

## 实现摘要
三项落地：① lib.sh `load_state`（:191-227，printf %q 转义 + 首对 --- + 重复键取第一 + 缺文件 rc0）+ stop-hook 接线（eval 7 处：开头 + C9 五点位 + detect_smoke_eligible 自足；43 直调清零；枚举复用 normalize_enum_value；local-shadow 4 处合并声明；大写引用零改名）② `cleanup_artifacts_ttl`（lib.sh:231-244 + setup.sh:21 接线）③ `detect_runtime_size`（lib.sh:248-262 + doctor SKILL.md:265/:479 接线，577→576 净减）。性能实测：900 字段 state.md load_state+eval 168ms（改前 43 次×5 子进程）。QA 全绿：红队 46/46、run-all 42/42（编排器+qa-reviewer 双独立复跑）、npm 80/80、C8-C5 全 ✅ 0 Critical。

## 文件变更
修改 10（lib.sh +80 / stop-hook.sh 119 行改动 / setup.sh +3 / doctor SKILL.md 576 / 版本 4 处 / 测试适配 2），无增删文件。详见本任务 commit。

## 下游须知（后续任务/专项必读）
- **stop-hook 字段读取范式已变**：任何后续改 stop-hook 的任务**不得再引入 get_field/get_enum_field 直调**——统一读小写键原样变量（eval load_state 批量加载）；set_field 后需读回处须重 eval load_state（C9 范式）
- **autopilot SKILL.md 最终 478 行**（三任务累计 501→478 净减 23）；doctor SKILL.md 576
- **qa-reviewer 3 个留档建议**（非阻塞）：load_state 非标识符键过滤一行守卫 / TTL 对超长任务谓词 artifact 的边缘场景（QA 产物迁 task_dir 或豁免）/ lib.sh:187 注释措辞（bash 实现非 awk）
- **acceptance 测试资产专项**（本 DAG 明确排除、调研已立项待决策）：测试资产只增不减（42 个 + 时序耦合断言清理只剩 4 条已修，长效治理待专项）；红队铁律例外流程本 DAG 走了 2 次（T1 时序耦合×3 测试、T3 平价 vs 契约×1 断言），模式已沉淀 knowledge
- **谓词 artifact TTL 风险**：/tmp/autopilot-artifacts 7 天清理 vs 超长任务复核——短期可接受，专项时一并处理

## 偏差说明
蓝队 3 项设计偏差（detect_smoke_eligible 自足 eval / doctor Dim 12 实位非 Dim 9 / load_state bash 实现非 awk 内转义）——qa-reviewer Section A 逐项核实语义等价或落位更准，非实质偏差。QA 铁律例外 1 次（21.P1 平价 vs C8 契约矛盾，你批准修断言+重锁），根因与模式已沉淀 knowledge [2026-09-07] 平价谓词条目。
