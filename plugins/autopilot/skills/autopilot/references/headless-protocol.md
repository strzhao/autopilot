# Headless 协议（无人值守确定性运行档位）

`--headless`（setup.sh flag）开启的档位：编排器在无人值守环境（如 zcode `--prompt` / CI）下运行时，
全部 AskUserQuestion 交互点确定性化——不问、不挂起、必留痕。**本文件是 headless 行为的唯一权威源（SSOT）**：
SKILL.md 六处点位指针（优先级表 / :53 环节失败回退 / brainstorm 委托 / 复杂度分流 / guardrail 必问 / U1-U4，共 7 行替换）皆指向此处。

## 字段五元组（frontmatter `headless`）

| 项 | 值 |
|----|----|
| 字段名 | `headless`（state.md frontmatter） |
| 语义 | 无人值守确定性运行档位：交互点全部确定性化，不挂起、必留痕 |
| 合法值 | canonical `true`；空 = 交互模式（**不设 false**——非 headless 模板零字面量，防默认值发射掩盖漏传） |
| 写入者=setup.sh（唯一） | 仅 `--headless` 显式传入时发射 `headless: true` 行；幂等（重复传入等价一次）；同时将 `session_id` 写空 |
| 读者 | 编排器 AI（交互点判定）；**stop-hook 不读此字段**——hook 侧完全复用既有 §5.5 auto_approve / §6 停等 / §7.6 分支，零新增 |

## 行为矩阵（flag-asymmetry 全边枚举）

| # | 交互点 | 交互模式（headless 空） | headless=true |
|---|--------|------------------------|---------------|
| 1 | design 步骤 1 复杂度分流问（SKILL.md :85） | AskUserQuestion 项目/单任务 | 不问：按单任务继续，分流假设记入设计文档 |
| 2 | brainstorm 委托（SKILL.md :57-59） | 复用命中即用；未命中→委托 Q&A | 复用命中即用；未命中→编排器自答（推演关键问题与假设写入 brainstorm.md 留痕） |
| 3 | design 步骤 4 guardrail 必问（SKILL.md :127-128） | AskUserQuestion 三选 | 不问：预授权放行 + 变更日志留痕（guardrail 类别+理由）；auto_approve=true 照设 |
| 4 | SKILL.md :53 环节失败回退（Auto-Approve/Fast 环节失败） | AskUserQuestion 回退人工审批 | 不问：按显式失败出口处置（交互通道不可用），gate/systemMessage 可见 |
| 5 | 红队 U1-U4 升级（SKILL.md :348/:362） | AskUserQuestion 升级 | 不问：留痕 + 保守处置（不改红队测试，实现修复优先），记入 QA 报告遗留 |
| 6 | qa 收口点名问（SKILL.md :331） | auto_approve=false 时问 | 不触发：点位 3 已设 auto_approve=true → 既有「预授权不问」豁免，零新增 |
| 7 | §5.5 自动 merge（分级达标） | 机械自动 | 不变 |
| 8 | §6 gate 停等（分级未达标） | 停等 | **不变 = headless 显式失败出口**（绝不自动合入未验证代码；gate 保留、不 merge） |
| 9 | §7.6 design 停等 | 放行交用户 | 不触发（headless 下点位 3 同轮 auto_approve + phase=implement，与既有 auto_approve 路径同） |

## 留痕契约

每个确定性处置必须在 state.md `## 变更日志` 写一行，锚点词 `[headless]` 机械可 grep（对齐 §8.5.1b 留痕守卫惯例）：

```
[headless] <点位> 确定性处置：<放行/保守处置/显式失败>，依据：<guardrail 类别 / E 编号 / 假设要点>
```

- 点位 1/2/3/5/6 → 处置 = 放行（3）或保守处置（1/2/5）；点位 4/8 → 处置 = **显式失败**
- qa gate 显式失败出口（点位 8）同属确定性处置，同样落 `[headless]` 留痕（gate 保留，不自动 merge）
- 交互模式（headless 空）不得出现 `[headless]` 留痕（反向契约）

## 组合语义

- headless **正交于 fast/standard**：只改交互点处置方式，不改变质量档位、链路完整性或红蓝对抗结构
- 与 `--fast` / `--standard` 可组合，两者同时生效（如 fast 链路 + headless 确定性化）
- 幂等：重复 `--headless` 等价传入一次
- 交互模式行为完全不变（反向契约）：SKILL.md / references 的全部提问指令保留原样
- 显式 flag 仅在目标文本**之前**生效（shell 惯例）：目标文本首个 token 恰为档位字面量（如 `setup.sh "--fast 模式调研"`）时按显式 flag 处理并被吞入 flag（与历史行为一致）；文本内/后的字面量永不识别（C2）

## session 归属（机制层）

- `--headless` 时 setup.sh 将 `session_id` 写空 → stop-hook Guard 1 首轮 Stop 认领真实 runtime session id（claude/zcode 双 runtime 通吃），非 headless 行为不变
- stop-hook Guard 2 泄漏告警：state session 非 `sess_` 前缀 ∧ 运行时 session 是 `sess_` 前缀 → 输出含 `CLAUDE_CODE_SESSION_ID` 的 systemMessage 告警后**照旧放行**（行为不变、可观测性+）；signature 不命中零输出（防误报）

## 残余风险（显式声明）

点位 1-6 的确定性化依赖编排器读 `headless` 字段执行，stop-hook 不读该字段（机械层无法指认语义活），
存在「编排器漏执行」的自适用盲区。接受为已知取舍：这些点位本质是语义活；缓解 = 本 SSOT + SKILL 六处点位指针
（非后置章节，不跳读）+ 红队引用存在性断言。若未来要求机制级兜底，再评估 stop-hook 侧状态信号扩展。
