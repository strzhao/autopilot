# Brainstorm Q&A

任务：基于 ~/Downloads/tdd.txt 优化 autopilot skill 的 TDD 质量。

## 背景
relight 项目的 c3648c2 commit 引入回归（删除 composedImageUrl 字段映射 + /:pickDate/wallpaper 路由），但 autopilot 全流程通过：
- 红队验收测试用 `if (status === 200) { strict } else { console.warn }` 模式宽容跳过 → 22 PASS / 1 FAIL，PASS 大半是假阳性
- CI 在 Lint 阶段就挂（ELIFECYCLE exit 1），autopilot 仍宣告 phase: done
- mac App 是 Swift 跨语言契约消费方，红队/qa-reviewer 都没看 → 字段被删后无人发现

tdd.txt 列了 P0/P1/P2/P3 共 7 条改进。

## Q1：本次范围
**用户选择**：P0 + P3 最小集（4 处改动）
- P0a: red-team-prompt 加禁用宽容跳过铁律
- P0b: merge 阶段加 CI 验证（commit 后若已被 push 则等 CI 结论）
- P0c: qa-reviewer 加 Section C 审查红队测试质量
- P3: anti-rationalization 加红队反模式段

理由：用户强调 "skill 非常脆弱，不要导致任何劣化"，最小集风险最低。
P1（契约消费者字段、破坏性变更扫描）和 P2（场景生成器直连、auto-chain CI 信心）留给下一轮。

## Q2：CI 验证怎么做
**用户选择**：merge 末尾若已 push 则等 CI

精化解读（结合用户全局 CLAUDE.md "git push 后要主动观察 cicd"）：
- autopilot **保持默认 commit-only**，不引入主动 push
- merge 阶段 commit 后增加"步骤 2.5: 已推送场景下等 CI"
  - 触发条件：`gh run list --branch <branch> --limit 5` 能看到与 HEAD commit 相关的 in_progress / completed run
  - 等待：`gh run watch --exit-status` (timeout 600s)
  - 失败 → phase: auto-fix
- 不能识别到对应 CI run（即 commit 未被 push）→ 跳过，不阻塞
- 这样不改变 autopilot 默认行为，但解决了"已 push 时不看 CI"的盲区

## Q3：红队质检位置
**用户选择**：qa-reviewer 加 Section C

理由：复用现有合并 sub-agent，避免新增 cold start 成本（参考历史决策"Sub-agent 数量是 token 优化的真正杠杆"）。

## Q4：落地节奏
**用户选择**：走 autopilot 全流程一次过

4 处改动一次性 implement+qa+merge，红队会写 acceptance 测试断言每条铁律实际生效。

## 范围明确不做的事

- 不动 SKILL.md 主决策树（关键规则集中原则，避免 [2026-04-17] AI 跳读）
- 不动 phase 流程顺序、frontmatter 字段
- 不动 plan-reviewer / scenario-generator / blue-team / commit-agent prompt
- 不引入新 sub-agent
- 不改 autopilot 默认是否 push 的行为
