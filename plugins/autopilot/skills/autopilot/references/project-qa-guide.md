# 全项目 QA 验证指南

## 触发方式

全项目 QA 在以下场景自动触发：
- 最后一个 DAG 任务完成，stop-hook 检测到所有任务 `status: done`
- stop-hook 创建 `mode: "project-qa"` 的状态文件，直接从 `phase: "qa"` 开始

## 与标准 QA 的区别

| 维度 | 标准任务 QA | 全项目 QA |
|------|------------|----------|
| 变更范围 | 单任务 git diff | 项目创建以来的全部变更 |
| Tier 0 | 运行红队验收测试 | 跳过（无项目级红队测试） |
| Tier 1 | 基础验证 | 同上，但验证跨任务集成 |
| Tier 1.5 | 设计文档中的场景 | 跨任务集成场景（从 design.md 提取） |
| Tier 2a | 单任务设计符合性 | 整体架构符合性（对照 design.md） |
| auto-fix | 支持 | 不支持（失败需人工判断修复范围） |
| 结果处理 | gate 或 auto-fix | 通过 → done / 失败 → gate |

## 执行步骤

### 1. 加载上下文
- 读取 `.autopilot/project/design.md` 作为设计参考
- 读取状态文件 `## 任务完成摘要`（所有 handoff 汇总）
- 读取 `dag.yaml` 了解任务拓扑

### 2. 变更分析
- `git log --oneline` 查看项目期间的所有 commit
- `git diff <project-start>..HEAD --stat` 识别全部变更文件
- 分类和影响半径评估（同标准 QA）

### 3. Wave 1 — 命令执行
- **跳过 Tier 0**
- Tier 1：全量构建 + 测试 + lint + 类型检查
- Tier 3：集成验证（如适用）
- Tier 4：全项目回归检查

### 4. Wave 1.5 — 跨任务集成场景
- 从 `design.md` 的"跨任务设计约束"和"Handoff 策略"提取集成点
- 为每个集成点设计至少 1 个验证场景
- 聚焦：共享接口、数据流、命名约定一致性

### 5. Wave 2 — AI 审查
- Tier 2a：对照 `design.md` 检查整体架构符合性
- Tier 2b：全变更范围代码质量审查

### 6. 结果判定
- 全部 ✅ → `phase: "done"`
- 有 ❌ → `gate: "review-accept"`
- **不进入 auto-fix**（项目级失败需人工判断修复范围和优先级）
