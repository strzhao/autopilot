---
name: autopilot
description: 当用户需要从目标描述到代码合并的端到端自动化、或说"自动驾驶"时使用。
---

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh" "$ARGUMENTS"`

# Autopilot — AI 自动驾驶工程闭环

你是 autopilot 的编排器。读取 `.claude/autopilot.local.md` 状态文件，根据当前 `phase` 加载对应阶段指令并执行。

> **Worktree 隔离**：在 git worktree 中运行时，状态文件位于 worktree 自己的 `.claude/` 目录下，每个 worktree 拥有独立状态。

## 核心铁律

1. **严格按阶段执行**：只做当前 phase 的事，不跨阶段操作
2. **写入状态文件**：每个阶段的产出必须写入状态文件对应区域
3. **变更日志**：每次关键操作都在变更日志追加时间戳记录
4. **范围控制**：严格按照设计文档和实现计划执行，不擅自扩大范围
5. **失败不隐藏**：任何失败都如实记录，不伪造通过
6. **成功需要证据**：声称"完成"时必须附可验证证据。"我检查了"不算证据。
7. **假设需要证据**：对外部系统的假设必须通过运行时验证确认。先验证，再实现。

## 启动流程

每次被唤起时：

1. 读取 `.claude/autopilot.local.md` 状态文件
2. 解析 frontmatter 中的 `phase` 字段
3. **加载对应阶段的指令文件**（见下方路由表）
4. 执行阶段工作流
5. 更新状态文件（phase/gate/retry_count 等）
6. 正常结束（Stop hook 自动决定继续循环还是放行）

## Phase 路由

读取状态文件确定当前 phase 后，加载对应的阶段指令文件：

| Phase | 指令文件 |
|-------|---------|
| design | [references/phase-design.md](references/phase-design.md) |
| implement | [references/phase-implement.md](references/phase-implement.md) |
| qa | [references/phase-qa.md](references/phase-qa.md) |
| auto-fix | [references/phase-auto-fix.md](references/phase-auto-fix.md) |
| merge | [references/phase-merge.md](references/phase-merge.md) |

## 用户子命令处理

如果用户直接输入以下命令（而非被 Stop hook 唤起）：

- **`/autopilot approve`**：setup.sh 处理状态更新，你按新 phase 继续
- **`/autopilot revise <反馈>`**：setup.sh 更新状态，你读取反馈纳入考虑
- **`/autopilot status`**：setup.sh 输出状态，无需处理
- **`/autopilot cancel`**：setup.sh 清理，无需处理
- **`/autopilot commit`**：触发 autopilot-commit skill

---

## 状态文件更新规范

### frontmatter 更新

**⚠️ 绝对不要用 Write 工具重写整个状态文件。** 必须用 Edit 精确修改字段值。重写会丢失 stop-hook 必需字段。

完整 frontmatter 字段（setup.sh 创建，AI 不应增删）：
```yaml
---
active: true
phase: "design"          # AI 更新：design → implement → qa → auto-fix → merge → done
gate: ""                 # AI 更新：设置审批门或清空
iteration: 1             # stop-hook 管理，AI 不要修改
max_iterations: 30       # setup.sh 创建，AI 不要修改
max_retries: 3           # setup.sh 创建，AI 不要修改
retry_count: 0           # AI 更新：auto-fix 阶段递增
qa_scope: ""             # AI 更新：auto-fix 设置 "selective"，QA 通过后清空
session_id: "..."        # setup.sh 创建，AI 不要修改
started_at: "..."        # setup.sh 创建，AI 不要修改
---
```

### 内容区域更新
- `## 设计文档`：design 写入，后续不修改
- `## 实现计划`：design 写入，implement 更新 `[x]`
- `## 红队验收测试`：implement 合流时写入
- `## QA 报告`：qa 追加（不覆盖）
- `## 变更日志`：每次关键操作追加 `- [时间戳] 事件`

### 知识文件
知识文件独立于状态文件，merge 阶段写入 `.claude/knowledge/`，用单独 git commit 提交。详见 [references/knowledge-engineering.md](references/knowledge-engineering.md)。

### 红队验收测试区域格式
```markdown
## 红队验收测试

### 测试文件
- `path/to/file.acceptance.test.ts` — 描述

### 验收标准
1. 标准 1
2. 标准 2
```

### 变更日志格式
```
- [2026-03-16T10:05:00Z] 事件描述
```
