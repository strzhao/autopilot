# Knowledge Index

> 三层 Progressive Disclosure：本索引（≤5s 扫描）→ 全局 decisions/patterns（热区）→ domains/（历史归档按主题）。2026-06 前长尾条目在 domains/ 分区文件内可全文扫描发现。

- [2026-10-18] UI 视觉质量三断点沿谓词骨架补齐——ux-exploration channel 双形态 + 冻结锚协议（v3.79.0） | tags: autopilot, qa, ux-exploration, visual-fidelity, design-anchor, predicate-channel, acc-guard-30, ai-first, v3.79.0 | → decisions.md
- [2026-10-18] 冻结谓词自指触发自家守卫——QA 门死锁陷阱 | tags: autopilot, qa, predicate-gate, self-reference, driver-guard, fixture-keyword, deadlock, dogfood | → patterns.md
- [2026-10-18] 白名单制测试运行器的执行面假全量 | tags: autopilot, qa, execution-surface, npm-test, whitelist, false-green, regression-closure | → patterns.md
- [2026-10-18] 循环引擎自毁链根治——brief 三级解析 + 指针自愈 + 终止信号闭集落盘（v3.78.0） | tags: autopilot, stop-hook, active-ptr, self-heal, auto-chain, brief-path-resolution, termination-signal-closure, silent-exit, v3.78.0 | → decisions.md
- [2026-10-18] QA 谓词口径裁决三型（E1 基线红闭集 / CONTRACT_AMBIGUOUS 对称留痕 / 弱 marker 锚注册行） | tags: autopilot, qa, predicate-gate, e1-adjudication, contract-ambiguous, baseline-red-closure, weak-marker, false-green, v3.78.0 | → patterns.md
- [2026-09-15] design 步骤 4 审批域 AI-First 落地——删闭合 guardrail 清单 + 机械门禁为安全真源（v3.72.0） | tags: autopilot, design, approval-gate, auto-approve, ai-first, mechanical-gate, v3.72.0 | → decisions.md
- [2026-09-15] 验证链的三处"假绿"（artifact 同名覆盖 / 校验器恒真 / 解析崩溃回落空值）+ 全局 env 干扰源与 PATH 桩隔离法 | tags: autopilot, qa, false-green, artifact-collision, env-global, path-stub, test-isolation | → patterns.md

## Domains 导航（历史归档，按主题）
- [stop-hook-state-machine](domains/stop-hook-state-machine.md) — stop-hook 兜底 / 状态机 / flag-asymmetry / pending-subagent（10 entry）
- [skill-authoring](domains/skill-authoring.md) — SKILL.md 改动纪律 / 命名 / best-practice / 版本同步（22 entry）
- [qa-testing](domains/qa-testing.md) — QA 判定 / red-team / mutation / contract / 量化门禁（15 entry）
- [worktree-git](domains/worktree-git.md) — worktree 检测 / symlink / git porcelain / 文件管理（7 entry）
- [knowledge-token-arch](domains/knowledge-token-arch.md) — progressive disclosure / token / sub-agent / 架构 / doctor（11 entry）
- [bash-shell-pitfalls](domains/bash-shell-pitfalls.md) — bash 陷阱 / exit-code / trap-err / set-u / macOS / awk-单词边界（6 entry）

## Decisions（52）
- [2026-09-25] Plan 审查轮次上限 2→5（v3.74.0）——停点写死「0 BLOCKER」非轮数；成本条件性（仅 R2 仍 FAIL 的复杂任务多跑） | tags: autopilot, design, plan-reviewer, review-rounds, convergence, v3.74.0 | → domains/skill-authoring.md
- [2026-09-25] TaskStop 终止信号缺失（v3.73.1）——终止集=完成通知 ∪ TaskStop 成功停止（教训：集合差型检测的终止信号须穷举完备） | tags: autopilot, stop-hook, taskstop, silent-wait, terminal-signal-union, v3.73.1 | → domains/stop-hook-state-machine.md
- [2026-09-09] pending 检测双盲区根治（v3.70.1）——jq 全量直读逐行容错（教训：验证证据须覆盖「机制被真实触发」场景） | tags: autopilot, stop-hook, wc-leading-space, window-blind, false-negative, v3.70.1 | → domains/stop-hook-state-machine.md
- [2026-09-09] 真实验收执行面闭环——执行面清单 + unexecuted_core_paths 第三字段 + real-process 强制（验证边界=执行面闭集非谓词集） | tags: autopilot, execution-surface, unexecuted-core-paths, real-process, acceptance-card, v3.69.0 | → decisions.md
- [2026-09-09] v3.69.0 knowledge 扇出五节化——红队知识绝缘经 context.md 既有通道扇出（零新机制）+ dogfood 自指三教训 | tags: autopilot, knowledge-fanout, context-md, red-team, artifact-self-describing, dogfood, v3.69.0 | → decisions.md
- [2026-09-09] 分级自动 approve——机器可读分级字段 + stop-hook 机械分级 + 验收决策卡 | tags: autopilot, approve, tiered-approve, e2e-status, leftover-critical, acceptance-card, v3.68.0 | → decisions.md
- [2026-09-08] 红队铁律仲裁点迁移——人审升级为 AI 证据门槛自决 + 事后留痕审计（双层决策树 E1-E3/U1-U4） | tags: autopilot, red-team, iron-law, evidence-gate, self-decision, decision-tree, v3.66.0 | → decisions.md
- [2026-08-09] 独立 brainstorm 产物主流程发现机制——编排器语义扫描复用（智力活留 AI 不塞 bash；治三断点 slug 双轨/active.ptr/无条件重跑） | tags: autopilot, brainstorm, independent-skill, reuse, semantic-scan, v3.61.0 | → decisions.md
- [2026-07-23] doctor Dim 14「命脉链路 readiness 覆盖」——纯 AI 语义维治假绿（命脉穿透审计 High freedom） | tags: autopilot, doctor, dim-14, readiness, critical-path, false-green, v3.59.0 | → decisions.md
- [2026-07-19] doctor Dim 13「AI 可观测性」——客观信号确定性下沉 + 语义留 AI（判据=客观事实存在性 vs 语义质量判断） | tags: autopilot, doctor, dim-13, ai-observability, deterministic-signal, v3.58.0 | → decisions.md
- [2026-07-17] v3.57.0 谓词三守卫（channel/coverage/uniqueness）治 human-obs + 复制 artifact 双重失效（守卫口径收紧兼容 ACC-GUARD-30 / SKILL 零改动执法全下沉 bash） | tags: autopilot, qa, predicate-guard, channel, artifact-uniqueness, md5, acc-guard-30-compat, v3.57.0 | → decisions.md
- [2026-07-11] project auto-mode 三卡点完整自洽——默认值 latent bug 检测信号：全部调用方都传同一非默认值=默认值本身错（solve don't punt） | tags: autopilot, project-mode, auto-mode, default-value, latent-bug, v3.56.0 | → decisions.md
- [2026-07-10] auto-chain 文件名=id 隐含契约——AI 偏离致三处 id 查找全失效（修命名非加查找，脚本零改动） | tags: autopilot, auto-chain, project-mode, naming-contract, implicit-contract, v3.54.0 | → decisions.md
- [2026-07-09] 红队铁律 escape hatch——复用既有 lock 函数解确定性守卫冲突 | tags: autopilot, red-team, iron-law, escape-hatch, deterministic-guard, reuse-over-new, v3.53.0 | → decisions.md
- [2026-07-08] QA 谓词覆盖率机制——复用独立 agent 加维度非新增环节；客观闭集子集非伪精度 | tags: autopilot, qa, predicate-coverage, plan-reviewer, qa-reviewer, closed-set, v3.51.0 | → decisions.md
- [2026-07-04] 自由度匹配边界——systemMessage 注入治机制层不治展示层 | tags: autopilot, tier-5, degrees-of-freedom, systemMessage, prompt-layer, low-freedom | → decisions.md
- [2026-06-24] 红蓝编译耦合根治——验收测试暂存区 + stop-hook 确定性合流；机械活下沉 hook / 智力活留 agent | tags: autopilot, red-blue-team, compile-coupling, acceptance-staging, determinism, degrees-of-freedom | → decisions.md
- [2026-06-22] 红蓝对抗蓝队"多做"越界：消解职责重叠 + AI 决策心智 + 终止边界复用[!] | tags: autopilot, red-blue-team, blue-team, scope-creep, role-boundary, ai-first | → decisions.md
- [2026-06-18] 编排器自审自己的产物 = 零独立性橡皮图章；零价值环节直接删，下游链覆盖则无需替换 | tags: autopilot, fast-mode, design, self-review, zero-independence, deletion-over-replacement, anti-pattern | → decisions.md
- [2026-07-17] 独立 skill 调用必须有 task_dir fallback——否则产物落旧路径污染入库 | tags: autopilot, brainstorm, independent-skill, task-dir, fallback, gitignore, pollution, v3.56.1 | → patterns.md
- [2026-07-01] 删 baseline 重录 = 污染 oracle — artifact 冒充比"改断言"更隐蔽（§8.5.2 治） | tags: autopilot, test-quality, oracle-pollution, snapshot-regen, false-green, deterministic-signal | → patterns.md
- [2026-06-02] QA 假阳性根治：客观工具门禁不够，要更便宜的确定性硬信号 + 散文铁律转 hook backstop | tags: autopilot, qa, false-positive, deterministic-signal, artifact-freshness, prose-iron-law-to-hook | → decisions.md

## Patterns（65）
- [2026-09-10] headless 机制上线（v3.71.0）——设计期 plan-reviewer 沙箱实测谓词杀伤力（contains 污染锚 + 正确实现必假失败的引号格式锚）+ fixture 前缀精确性 + flag-asymmetry 全边矩阵 | tags: autopilot, headless, mutation-killing, predicate-design, sandbox-probe, fixture-precision, v3.71.0 | → patterns.md
- [2026-09-10] bash 接受 CJK 函数名但 ShellCheck 拒之（SC1036）——lint 门禁在 bash -n 之外 | tags: bash, shellcheck, cjk, function-name, sc1036, lint-gate, macos | → domains/bash-shell-pitfalls.md
- [2026-09-10] autopilot headless（zcode runtime）标准用法——模式自判偏 fast + 预授权话术确定性跳审批 + env 剥离红线 | tags: autopilot, headless, zcode, fast-mode, auto-approve, env-leak, v3.70.1 | → patterns.md
- [2026-09-08] Tier 1.5 谓词 artifact 两个机械陷阱——裸数字跨谓词 MD5 撞车 + staged 状态字面 git diff 为空须按约束本质选基线 | tags: autopilot, tier-1.5, artifact, md5-collision, git-staged, numstat, baseline, v3.66.0 | → patterns.md
- [2026-09-07] 平价谓词 vs 更严格新契约——边界 fixture 必然互斥，平价比对显式排除被收紧的边界 | tags: autopilot, acceptance-test, parity-predicate, contract-migration, red-team-iron-law, v3.65.0 | → patterns.md
- [2026-09-07] 新机制上线的「自适用盲区」——编排器执行新 prompt 机制时自己也会漏执行（降级优雅化 + 自指检查 + hook 兜底三对策） | tags: autopilot, dogfood, mechanism-rollout, self-applicability, execution-drift, v3.64.0 | → patterns.md
- [2026-09-07] 验收测试「一次性任务证明」读工作区 git diff/status = 时序耦合假阳性定时炸弹——断言分两类判别 + 存量处置（转 standing invariant 或删） | tags: autopilot, acceptance-test, git-diff, time-scoped-assertion, false-positive, standing-invariant, v3.63.0 | → patterns.md
- [2026-07-23] awk 正则单词边界 `\b` 在 BSD/macOS 不支持 → 反向断言永真（改 `[^a-zA-Z]` POSIX 兼容） | tags: bash, awk, bsd, macos, word-boundary, regex, tautological | → domains/bash-shell-pitfalls.md
- [2026-07-19] 红队测试 FAIL 三分类——断言机制错/与契约矛盾/实现 bug（auto-fix 先分类再改） | tags: autopilot, red-team, acceptance-test, auto-fix, false-positive, assertion-mechanism, v3.58.0 | → patterns.md
- [2026-07-19] 业务维度数 vs 实现函数数——契约/验收措辞澄清避免 count 矛盾 | tags: autopilot, contract, plan-reviewer, naming, count-mismatch, v3.58.0 | → patterns.md
- [2026-07-17] 谓词描述禁用 artifact:/driver:/observe:/assert: 字面量——awk match 首个命中落描述致误报（dogfood §5.7 自踩） | tags: autopilot, predicate, awk, field-extraction, literal-collision, false-negative, v3.57.0 | → patterns.md
- [2026-07-08] smoke 模式编排器本能 deferred real-process 谓词，stop-hook Tier 1.5 铁律 E≥N 强制真跑（dogfood 自我纠偏） | tags: autopilot, smoke, tier-1.5, deferred, real-process, e-ge-n, v3.51.0 | → patterns.md
- [2026-07-08] plan-reviewer 在 claude -p（headless）下难触发——fast 跳过/standard 经 brainstorm 卡 | tags: autopilot, claude-p, headless, plan-reviewer, fast-mode, v3.51.0 | → patterns.md
- [2026-07-04] claude -p 跑普通需求客观验证 autopilot 改动 + 缓存多版本路径重装坑 | tags: autopilot, verification, claude-p, dogfood, cache, plugin-reinstall | → patterns.md
- [2026-06-02] `$(cmd || true); rc=$?` 把退出码永久吞成 0；保留 rc 又不触发 trap ERR 用 `cmd || rc=$?` | tags: bash, exit-code, command-substitution, or-true, rc-masking, trap-err | → patterns.md
- [2026-06-02] frontmatter set_field 必须 upsert（键缺失追加），且测试 mock 不能恒含被测字段 | tags: autopilot, lib.sh, set_field, upsert, test-mock-masking, latent-bug, fixture-realism | → patterns.md
- [2026-05-31] 用"静默放行/等待"修死循环时，必须补"用户可见 + 活性自救"，否则把吵闹死循环换成无声卡死 | tags: autopilot, stop-hook, silent-wait, liveness, observability, inverse-failure-mode | → patterns.md
- [2026-05-31] 断言"stdout 含某 JSON 键"易成 tautological — mutation 落点若也输出该键则断言失效 | tags: autopilot, test-quality, tautological-assertion, mutation-survival, json-key-grep, false-green | → patterns.md
- [2026-05-31] 自门控的横切检测函数不要再加 phase/条件门控 — 否则退化成 flag-asymmetry | tags: autopilot, stop-hook, self-gating, phase-gate, flag-asymmetry, near-infinite-loop | → patterns.md
- [2026-05-30] bash set -u 下变量紧跟多字节中文标点被误解析为变量名 → unbound variable 崩溃 | tags: bash, set-u, multibyte, cjk, unbound-variable, brace-disambiguation, latent-bug | → patterns.md
- [2026-05-26] 「状态机切换 state file 后必须重读所有缓存字段」+「修第 1 个 bug 时不问第 N 个」三连击复刻 | tags: autopilot, stop-hook, state-switch, stale-variable, multi-link-failure, meta-lesson | → patterns.md
- [2026-05-24] 精简清单必须 wc -l + grep 复核，凭直觉估算行数是 case 反模式元复刻 | tags: autopilot, refactor, simplification, wc-verify, anti-rationalization, false-precision | → patterns.md
- [2026-05-24] 单个 commit 内多区域同步是 BLOCKER 元复刻陷阱（修表层漏整体） | tags: autopilot, plan-reviewer, blocker, partial-fix, multi-location-update, false-completion | → patterns.md
- [2026-05-19] 静态 HTML 模板的 Tier 1.5 用 Chrome DevTools MCP + file:// 直接 evaluate_script | tags: autopilot, qa, tier-1.5, smoke-test, html-template, chrome-devtools-mcp | → patterns.md
- [2026-05-17] documentation-only 变更的 QA 降级模式：Tier 1/3.5 N/A、Tier 1.5 用产出审阅替代浏览器冒烟 | tags: autopilot, qa, documentation-only, tier-1.5, content-review, fallback | → patterns.md
- [2026-05-17] 设计阶段量化承诺（行数 / token 数 / 性能数）必须 grep 验证而非估算 | tags: autopilot, design, prediction, quantitative-commitment, grep-verify, estimate-bias | → patterns.md
