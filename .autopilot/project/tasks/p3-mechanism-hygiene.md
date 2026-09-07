---
id: p3-mechanism-hygiene
depends_on: [p2-qa-loop]
status: pending
---

# p3-mechanism-hygiene · 机制性能与卫生 → v3.65.0

## 目标
消除 stop-hook 每次 stop 的固定浪费与产物零清理：① lib.sh `load_state` 批量化——一次 awk 吐全部 frontmatter 字段，stop-hook 43 处 get_field/get_enum_field（16+27）改读变量 ② /tmp/autopilot-artifacts TTL 清理 + doctor runtime/ 体积客观信号。

## 架构上下文
- 完整设计见 `.autopilot/project/design.md`（T3 节 + 契约规约 C4）
- **先读上游 handoff** `tasks/p2-qa-loop.handoff.md`
- 现状：lib.sh:67-77（get_field = parse_frontmatter sed 全扫 + grep + 2×sed）、lib.sh:171-175（get_enum_field 含枚举归一逻辑）；stop-hook.sh 43 处调用点；状态切换重读点 stop-hook.sh:489-494 / 531-536 / 555-560（create_brief_state_file 后显式重读 PHASE/GATE/AUTO_APPROVE/ITERATION/MAX_ITERATIONS，v3.36.3 注释「auto-chain 失效双链第 2 环」）
- /tmp/autopilot-artifacts 已 238MB 跨项目混放无清理；relight runtime 3.3GB 实证

## 输出契约
- C4 `load_state <state.md>` stdout 逐行 `KEY=value`（frontmatter 全字段，键原样）；stop-hook source 后字段值与改前 get_field 语义逐字节一致，**get_enum_field 的枚举归一逻辑保留在变量赋值处**；**每次状态文件切换点（auto-chain / 全项目 QA 创建后）须重新调用 load_state，重读时机与改前 get_field 调用点一一对应**（防 [2026-05-26] stale-variable 同构回归）
- setup.sh 加 /tmp/autopilot-artifacts TTL 清理（>7 天，SessionStart 幂等，只删本工具产物目录内文件）
- doctor 报告加 runtime/ 体积客观信号（>500MB 警告）：体积检测下沉 lib.sh，语义建议留 AI（对齐 Dim 13/14 哲学），doctor SKILL.md 行数只减不增（基线 570）
- C5 版本号 v3.65.0，四处同步

## 跨任务约束
- SKILL.md 行数只减不增（≤ T2 后基线）；load_state 是纯行为保持重构，不改任何判定逻辑
- bash 兼容性：BSD awk（macOS）无 `\b` 单词边界（[2026-07-23]）；`cmd || rc=$?` 保退出码（[2026-06-02]）；BASH_SOURCE[0] source 测试（[2026-05-07]）

## 受影响既有 acceptance 测试
- **全部**（load_state 触及 stop-hook 每次 stop 的字段读取，行为不变量 = run-all.sh 全绿逐字节证明）
- auto-approve-gate-bypass 断言 6（auto-chain 重读场景）是 C4 重读时机的关键锁
- 新增：artifacts TTL 清理的幂等/不误删断言

## 验收标准
- `bash tests/acceptance/run-all.sh` 全绿（改前改后各跑一次对比）
- 新增 load_state 契约测试（KEY=value 完整性 / 枚举归一 / 切换点重读）
- TTL 清理只删 >7 天且仅 /tmp/autopilot-artifacts 内文件
