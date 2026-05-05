---
active: true
phase: "done"
gate: ""
iteration: 2
max_iterations: 30
max_retries: 3
retry_count: 0
mode: ""
plan_mode: ""
brief_file: ""
next_task: ""
auto_approve: false
knowledge_extracted: "true"
task_dir: "/Users/stringzhao/workspace/string-claude-code-plugin/.autopilot/requirements/20260504-当前-claude-code--w-执行"
session_id: 7b39e2c0-d3fe-4fd6-bae8-34a70ca3c247
started_at: "2026-05-04T07:17:51Z"
---

## 目标
当前 claude code -w 执行时 autopilot 的当前任务选择策略有问题，不应该把其他任务带过来，这个导致我经常通过 -w 开启新任务结果都有老的任务在干扰我

> 📚 项目知识库已存在: .autopilot/。design 阶段请先加载相关知识上下文。

## 设计文档

### 问题
`worktree.mjs` repair() 将整个 `.autopilot/` 通过符号链接共享到所有 worktree，导致 `.autopilot/active` 和 `requirements/` 在所有 worktree 间共享。用户通过 `claude -w` 开启新 worktree 时旧任务状态会干扰新任务。

### 方案
将 active 指针和 requirements 目录改为 per-worktree 隔离，知识文件保持共享：
- 非 worktree: `.autopilot/active` + `.autopilot/requirements/<slug>/`（不变）
- worktree: `.autopilot/sessions/<name>/active` + `.autopilot/sessions/<name>/requirements/<slug>/`
- 检测方式: `.git` 在 worktree 中是文件而非目录

## 实现计划
- [x] lib.sh: 新增 `get_worktree_name()`、`get_active_file()`；`init_paths()`/`setup_requirement_dir()` worktree 感知路由；fallback 加固
- [x] setup.sh: 4处 active cleanup → `$(get_active_file)`；2处旧格式迁移检查适配
- [x] stop-hook.sh: 7处 active cleanup → `$(get_active_file)`
- [x] worktree.mjs: `remove()` 新增清理 `.autopilot/sessions/<name>/` 目录
- [x] SKILL.md: 路径描述更新，注明 worktree sessions 路径

## 红队验收测试
(待 implement 阶段填充)

## QA 报告

### QA 轮次 1 (2026-05-04T07:40:00Z) — ✅ 全部通过

#### 变更分析
- 5 文件变更，+76/-24 行
- 分类：Shell 脚本 (lib.sh, setup.sh, stop-hook.sh)、Node.js (worktree.mjs)、文档 (SKILL.md)
- 影响半径：中 — 核心路径解析逻辑

#### Tier 0: 红队验收测试
- N/A（直接实现，无独立红队测试，通过场景验证覆盖）

#### Tier 1: 基础验证
| 检查项 | 状态 | 证据 |
|--------|------|------|
| bash 语法 (3文件) | ✅ | bash -n 全部通过 |
| Node.js 语法 (1文件) | ✅ | node --check 通过 |
| 测试套件 (44 tests) | ✅ | 44 pass, 0 fail |

#### Tier 3.5: 性能保障
- N/A（非前端项目，无前端代码变更）

#### Wave 1.5: 真实场景验证
| 场景 | 执行 | 输出 | 状态 |
|------|------|------|------|
| 1. 非 worktree 路径解析 | `source lib.sh && init_paths` | WORKTREE_NAME='', active_file=.autopilot/active | ✅ |
| 2. worktree 隔离 | 创建2个模拟 worktree | 不同路径，完全隔离 | ✅ |
| 3. setup_requirement_dir | 创建 slug + active | active 正确写入 sessions/<name>/ | ✅ |
| 4. fallback 加固 | worktree 中无 active | STATE_FILE="" (不落到autopilot.local.md) | ✅ |

#### Wave 2: AI 审查
- plan-reviewer: ✅ PASS (6/6 维度，无 BLOCKER)

#### 结果
- **全部 ✅**

## 变更日志
- [2026-05-04T07:42:19Z] 用户批准验收，进入合并阶段
- [2026-05-04T07:17:51Z] autopilot 初始化，目标: 当前 claude code -w 执行时 autopilot 的当前任务选择策略有问题，不应该把其他任务带过来，这个导致我经常通过 -w 开启新任务结果都有老的任务在干扰我
- [2026-05-04T07:25:00Z] 设计方案通过 Plan Mode 审批
- [2026-05-04T07:28:00Z] 核心实现完成（4文件修改）：lib.sh worktree感知路径、setup.sh/stop-hook.sh active指针清理适配、worktree.mjs sessions目录清理
- [2026-05-04T07:30:00Z] Plan 审查通过（6/6维度无BLOCKER）+ 审查建议改进：init_paths fallback加固、SKILL.md路径文档更新
- [2026-05-04T07:35:00Z] 真实场景验证通过：非worktree/worktree路径解析、多worktree隔离、44测试全通过
