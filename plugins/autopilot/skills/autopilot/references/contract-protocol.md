# 契约协议（Contract Protocol）

> 这是 autopilot 红蓝对抗中**契约的唯一真相源**。设计文档 `## 契约规约` 章节、plan-reviewer 维度 7、红队 prompt、蓝队 prompt、contract-checker agent 全部以此文件为准。

## 1. 五条核心规则

1. **字段名用反引号代码标记**：`memberCount`、`manual_override`，不写"成员数字段"
2. **边界值用 DbC 谓词**：`≤ 3000ms`、`≥ 10`、`< 1000`，禁用"约/大概/不超过/通常"等自然语言（基于 Bertrand Meyer DbC + Hoare Logic）
3. **错误码用枚举常量名**：`EmptyInputError`、`SPAWN_FAILED`，不写"输入为空时报错"
4. **任务类型必填字段表**（自适应）：见 §3
5. **N/A 必须含一句理由**：`错误契约: N/A — 纯渲染组件，无错误路径`，区分"忘了写"与"不需要"

## 2. 双层表达推荐（业界 SOTA，不强制）

每个契约规约段落推荐同时给：
- **invariant**（DbC 谓词形式精确边界，给精度）
- **example**（Pact/Given-When-Then 风格 1 正例 + 1 边界 + 1 反例，给 LLM 直觉锚定）

两者合一抵抗 LLM 推理跑偏。

## 3. 任务类型必填字段表

| 任务类型 | 必填字段 |
|---|---|
| 后端 API / 路由 | 接口签名 + status code + 错误码枚举 + 请求体 schema + 响应体 schema |
| 数据库变更 | 表名 + 字段清单（名+类型+nullable）+ 事务边界 |
| 计算 / 算法 / 解析 | 输入类型 + 输出类型 + 边界值 DbC 谓词 + 错误场景枚举 |
| 前端 UI 组件 | props shape + state shape + 暴露事件 |
| CLI / 脚本 | 命令签名 + 参数列表 + 退出码 + stdout 格式 |
| Hook / 中间件 | 触发事件 + 输入数据 shape + 副作用清单 |

任务跨类型时多类并填（如全栈 API+UI 任务）。不适用类型在该字段写 N/A + 理由。

## 4. 完整契约规约示例（API + 算法）

```markdown
## 契约规约

### 接口签名（invariant）
\`\`\`ts
fn detectBursts(
  photos: Photo[],
  thresholdMs: number
): {
  bursts: Burst[],
  memberCount: number,
  photosGrouped: number
}
\`\`\`

### 接口签名（example，Pact 风格）
- Given: photos = [p1@t=0, p2@t=2000, p3@t=2500] (3 张), thresholdMs = 3000
- When: detectBursts(photos, 3000)
- Then: { bursts: [{members: [p1,p2,p3]}], memberCount: 3, photosGrouped: 3 }

### 数据结构
- `Burst.id: string`
- `Burst.manualOverride: boolean`
- `Burst.isBurstRepresentative: 0 | 1`  // 注意 number 不是 boolean

### 边界值（invariant，DbC 谓词）
- 时间间隔: ≤ 3000ms 分组（包含 3000ms）
- pHash 汉明距离: ≤ 10 视为相似（包含 10）

### 边界值（example，正/边界/反）
- 正例: 间隔 = 1500ms → 分组
- 边界: 间隔 = 3000ms → 分组（含边界）
- 反例: 间隔 = 3001ms → 不分组

### 错误契约
- 输入空数组 → 抛 `EmptyInputError`
- 输入含损坏照片 → 抛 `CorruptPhotoError`，含 `photoId` 字段

### 副作用清单
- 写 DB: `bursts.manual_override = 1`
- emit: `burst:created` 事件 (payload: `{ burstId, memberCount }`)
```

## 5. 最小契约示例（N/A 全用例）

```markdown
## 契约规约

### 接口签名
N/A — 纯样式调整，无函数变更

### 数据结构
N/A — 无数据流

### 边界值
N/A — 无数值边界

### 错误契约
N/A — 无错误路径

### 副作用清单
N/A — CSS only
```

## 6. 模糊契约处理

### 红队遇到模糊契约
- 在测试文件**顶部**添加注释 `// CONTRACT_AMBIGUOUS: <具体歧义点>`
- 字段命名用与契约**最贴近的真实命名**（不要用 `EXPECTED_FIELD_NAME_FROM_CONTRACT` 之类**无法 lint 的占位符变量**）
- 在产出报告「验收标准摘要」末尾列出所有 CONTRACT_AMBIGUOUS 标记

### 蓝队遇到模糊契约
- 不要悄悄改实现，提交 contract-change-request：
  - 在变更日志追加 `[契约变更请求] <原契约>` → `<建议契约> 因 <原因>`
  - 设 `phase: "design"`、`gate: "review-accept"`
  - 编排器收到后回到 design 阶段，更新 `## 契约规约` 章节，重新走红蓝对抗

### contract-checker 遇到模糊契约
- 视为 mismatch.severity = 'medium'，记录但不阻断（PASS）
- 让红队验收测试自然暴露问题
