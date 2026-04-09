---
name: autopilot-project
description: 管理 autopilot 项目模式的任务 DAG。当用户运行 /autopilot status（有项目时）或 /autopilot next 时提供上下文参考。
---

# Autopilot Project — 多任务项目编排

管理 `.autopilot/project/` 下的项目文件，为大型多任务目标提供 DAG 驱动的任务编排。

## 项目文件结构

```
.autopilot/project/
├── design.md                    # 整体架构设计
├── dag.yaml                     # 任务 DAG
└── tasks/
    ├── 001-xxx.md               # 任务简报
    ├── 001-xxx.handoff.md       # 任务完成后的交接文档
    └── ...
```

## DAG YAML 格式

```yaml
project: "<name>"
created_at: "<ISO timestamp>"
tasks:
  - id: "001-wire-schema"
    title: "定义共享协议包"
    depends_on: []
    status: pending           # pending | in_progress | done | failed | skipped
  - id: "002-db-models"
    title: "新增数据模型"
    depends_on: ["001-wire-schema"]
    status: pending
```

## 任务简报格式

```markdown
---
id: "NNN-name"
depends_on: ["XXX", "YYY"]
---

## 目标
(一句话)

## 架构上下文
(从 design.md 摘取相关部分)

## 输入/输出契约
- 输入: ...
- 输出: ...

## 验收标准
1. ...
```

## Handoff 格式

```markdown
## 实现摘要
(做了什么，关键决策)

## 文件变更
(新增/修改的文件)

## 下游须知
(接口、约定、注意事项)

## 偏差说明
(与简报的任何偏差及原因)
```

## 核心原则

1. **原子性**: 每个任务是独立的 autopilot 运行，有完整的 design → implement → qa → merge 闭环
2. **信息隔离**: 任务间通过 handoff 文件传递上下文，不共享会话状态
3. **上下文预算 <10KB**: L0 DAG 概览 + L1 任务简报 + L2 依赖 handoff + L3 架构摘要
4. **Handoff 链**: 每个任务完成后写 ≤500 字 handoff，只有直接下游读取
5. **失败隔离**: 一个任务失败不影响无依赖关系的其他任务
6. **人工编排**: 用户决定何时启动哪个任务，系统只建议就绪任务
7. **AI Native**: 任务粒度、DAG 结构、handoff 内容由 AI 运行时判断，不硬编码规则

## 用户命令

| 命令 | 行为 |
|------|------|
| `/autopilot status` | 无活跃 autopilot 时自动显示项目 DAG 概览 |
| `/autopilot next` | 找就绪任务（deps 全部 done），输出 `/autopilot NNN-name` 建议 |
| `/autopilot NNN-name` | 自动匹配 tasks/ 下的任务文件，brief 模式启动标准 autopilot |
| `/autopilot --project <goal>` | 强制项目模式（跳过复杂度检测） |
| `/autopilot --single <goal>` | 强制单任务模式 |
