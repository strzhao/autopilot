# Brainstorm Q&A

## 研究阶段（先于 Q&A）

### relight 真实案例（7 个，从 11 个 session 历史扫描）
- B 数据格式不一致 (3): burst-detector `memberCount` 字段缺失 / bursts PATCH 字段更新失败 / sprite buffer < 1000 字节
- D 边界值不一致 (2): 3s 边界包不包含 / pHash 汉明距离阈值
- H+A 路由缺失 (1): scanRouter 整个未注册 → 404
- C Mock 契约不兼容 (1): ESM `vi.spyOn(spawn)` TypeError

7/7 蓝队是理解偏差方（红队测试规则上不能改）。auto-fix 反复修不好。

### relight 知识库相关沉淀
- `decisions.md` 暂无契约对齐专项决策
- `patterns.md` 已沉淀「vi.mock 形状漂移」「BullMQ Job mock 字段缺失」
- `doctor-report.md` 直接诊断："无 OpenAPI schema，红队依赖设计文档推断 API 契约"

### autopilot 当前架构空白点
1. 设计文档模板（`state-file-guide.md`）无任何"契约"专属字段
2. plan-reviewer 6 维度不审契约对齐
3. 红/蓝队 prompt 各自从自然语言设计文档里推断契约
4. red-team-prompt.md line 51 仅在跨系统数据流场景提了一句"字段名一致性"，无机制保证

### 根因 hypothesis
契约（接口签名/数据结构/边界值/错误码/副作用）应是 single source of truth，但当前埋在自然语言设计文档里。红蓝队信息隔离 + 各自归纳 → 必然漂移。

## Q&A

### Q1: 契约定义层放在哪里？
**选**: 设计文档新增 `## 契约规约` 章节（MD 轻量）
- 备选 1: 独立 contracts/ 目录（强类型，重）
- 备选 2: 混合（项目有 OpenAPI/Zod 时升级）

### Q2: 契约对齐的强制时机？
**选**: design 阶段加严，plan-reviewer 强制审（新增第 7 维度）
- 备选 1: implement 阶段加 contract reconciliation handshake（重，多一轮 Agent）
- 备选 2: 两道防线并存（最稳但成本高）

### Q3: ## 契约规约 必填字段范围？
**选**: 任务自适应
- API/路由: 接口签名 + status code + 错误码 + req/resp schema
- DB 变更: 字段清单（名+类型+nullable）+ 事务边界
- 计算/算法: 输入输出类型 + 边界值数学化 + 错误场景
- UI: props/state shape
- CLI/脚本: 命令签名 + 退出码 + stdout 格式
- Hook: 触发事件 + 副作用清单

### Q4: 红队 Agent 如何使用契约规约？
**选**: 铁律 prompt（不加 validator Agent）
- 测试中的接口名/字段名/错误码/边界值必须与契约规约逐字一致
- 契约脸谱不清不能唯一推导 → 标 `CONTRACT_AMBIGUOUS`，不猜
- 违反 → 整套测试作废

## 衍生设计原则
1. **轻量优先**：纯 MD 章节 + prompt 加段，不引入新 Agent / 新工具
2. **任务自适应不一刀切**：plan-reviewer 按变更类型动态判 BLOCKER
3. **逐字一致是底线**：字面量比抽象更难漂移，所以必须落到代码块
4. **N/A 必须显式说明**：避免"忘了写"和"不需要"无法区分
