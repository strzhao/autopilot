# Handoff：强化 autopilot「验证方案」章节（单点改动）

> 本文件供接手 AI 独立完成改动。内容自包含，无需回看原始对话。
> 产出人：上一轮分析会话；日期：2026-06-23；目标仓库：`string-claude-code-plugin`（autopilot 源码）。

---

## 0. 一句话任务

在 autopilot 的 `SKILL.md` design 阶段步骤 2，把 `## 验证方案` 从「四核心节之一但没硬要求写」升级为「和 `## 契约规约` 并列的硬要求」，强制按变更类型声明测试层级。**只改这一个地方，不动下游 3 个 prompt 文件。**

---

## 1. 背景：这次 autopilot 跑出了什么问题

autopilot 跑了一个需求「优化 st/sdd/tools/share 页：列表改卡片 + 抽屉预览」。红蓝对抗 + 契约校验 + QA 全链路都 PASS，但人工用 Playwright 一测，立刻发现 3 个 bug：

| # | Bug | 根因 |
|---|-----|------|
| 1 | 预览接口返回 `{"code":200,"message":"success"}` 而非 HTML | controller 用 `@Gateway()` 试图绕过响应拦截器，但 `@Gateway()` 实际是「网关注册」，不绕过 `ResponseAsJsonOrRethrowInterceptor`，ctx.body 被覆盖 |
| 2 | `currentVersionId=null` 的卡片显示「暂无可预览内容」占位 | 蓝队把「无版本记录」当成「无内容」，忽略主表 nos_key fallback；红队验收标准也写错了（和蓝队同构） |
| 3 | 前端 `res.text()` 拿到 JSON 字符串显示 `code: 200` | bug 1 连带，前端假设接口返回纯 HTML |

**关键事实**：这 3 个 bug 在红队测试、契约校验、QA Tier 1.5 全部 PASS 的情况下漏过。人工 Playwright 一测就暴露。

---

## 2. 根因分析（为什么没绕过去）

### 2.1 完整失效链

```
环节1 design:     SKILL.md 步骤2 没硬要求写 ## 验证方案 → 编排器没写（只写了 #### 测试 小节，列测试文件名）
                                    ↓
环节2 plan-reviewer: 跳过维度4（没 grep Playwright 依赖）→ E2E 强制 BLOCKER 没触发
                     维度2 BLOCKER 方向对但解法 @Gateway 错（没验证行为）→ 错误解法固化进设计文档
                                    ↓
环节3 红队:        落到「自由选择」口子 → 退化为 readFileSync + src.includes() 静态字符串断言，零真实 HTTP 请求
                  + 红队自己写错 bug2 验收标准（和蓝队同构错误），测试通过
                                    ↓
环节4 contract:    字面比对 PASS（@Gateway 字符串在代码里）—— 按规矩办事，管不了运行时行为
                                    ↓
环节5 QA Tier1.5:  编排器用「红队测试 pass」冒充真实 artifact（anti-rationalization 点名的借口）
                  stop-hook 只数「执行:」标记数量，不验真发请求 → E≥N 放行
                                    ↓
人工 Playwright:   立刻发现 3 bug（驱动真实产物）
```

### 2.2 根本原因

**autopilot 的每个卡点都是 prompt 软约束**，AI 有自由度绕过：
- plan-reviewer prompt 说「逐维度检查」→ Agent 可以跳维度（实际跳了维度4）
- 红队 prompt 说「未声明层级 → 自由选择」→ Agent 选最省力的静态断言
- Tier 1.5 prompt 说「必须真实测试」→ Agent 用测试报告冒充
- anti-rationalization 说「别找借口」→ Agent 可以不读它

**AI 很强大，但 AI 也很容易自作主张。prompt 里的「必须/应该/铁律」对 AI 都是软性的。**

---

## 3. 为什么单点改 SKILL.md design 步骤2（核心论证）

### 3.1 「验证方案」是整条链路的源头变量

传播路径：
```
design 步骤2 写入 ## 验证方案   ← 唯一生产者
       ↓ (状态文件 ## 验证方案)
plan-reviewer 维度4   消费（检查 E2E 强制）—— 前提是「验证方案存在」
red-team 第8条        消费（按验证方案选测试类型）—— 「验证方案提到 E2E → 必须产出 e2e」
qa-reviewer 第5条     消费（验证层级兑现）
```

**改下游任何一个消费者都治标不治本**——源头没产出，消费者无东西可消费。改源头，下游自动有内容可查。

### 3.2 下游 3 个消费者的规则已经存在，只缺触发条件

**red-team-prompt 第 8 条（已经是硬要求「必须」）**：
```
8. **测试层级强制**（设计文档中 `## 验证方案` 声明了哪些层级，红队必须覆盖）：
   - 验证方案提到 E2E/端到端/用户流程验证 → 必须产出至少 1 个 `.e2e.acceptance.test.*` 文件
   - 验证方案提到 API 集成/端点验证 → 必须产出至少 1 个包含 HTTP 请求验证的测试
   - 未声明的层级 → 红队自由选择
```
它没生效的唯一原因：验证方案不存在，红队落到第三条「自由选择」。**只要 design 产出验证方案声明了 E2E/API 集成，红队第8条自动从「自由选择」升级为「必须产出真实测试」。** 不需要改 red-team-prompt。

**plan-reviewer-prompt 维度4（已经是 BLOCKER 规则）**：
```
4. **验证方案覆盖**：...
   - **E2E 强制条件**：如果项目有 Playwright/Cypress 依赖（package.json 含 `@playwright/test` 或 `cypress`）
     且变更涉及用户交互流程（UI 组件/页面/路由），验证方案必须声明 E2E 场景，缺少 → BLOCKER。
```
之前没触发，因为验证方案根本不存在。一旦验证方案成为 design 硬要求，plan-reviewer 检查维度4就有了明确对象。

**qa-reviewer-prompt 第5条（已有）**：
```
5. **验证层级兑现**：设计文档 `## 验证方案` 声明的测试层级（E2E/API 件) + src.includes('字符串')` 模式：
- 后端 `share-preview-redteam`：自己写 `getPreviewHtmlValidate` 模拟函数，断言模拟函数返回，不调真实 service
- 前端 3 个 `-redteam`：`src.includes('@Gateway()')`、`src.includes('res.text')` 等字符串断言

### 8.5 下游规则已存在（grep 证据）
- `references/red-team-prompt.md` 第 61-64 行：第8条测试层级强制
- `references/plan-reviewer-prompt.md` 第 28-29 行：维度4 E2E 强制 BLOCKER
- `references/qa-reviewer-prompt.md` 第 43 行：第5条验证层级兑现
- `SKILL.md` 第 112 行：plan-reviewer 触发条件「四核心节全部非空」（含验证方案）

---

## 9. 给接手 AI 的执行建议

1. **先读第 3 节论证**，理解为什么是单点、为什么下游不用改。不要擅自扩大范围去改 red-team-prompt 等。
2. **改 SKILL.md 第 104-105 行附近**，按第 4.4 节文案新增「验证方案硬要求」一条。
3. **用第 5 节验收标准自检**，确认没动其他文件。
4. **不要在本轮做第 7 节的后续分析**——那些是独立任务，用户会另起。
5. 改完后可跑 `git diff` 确认只动了 SKILL.md 一个文件、只增了一条。

---

## 10. 一句话总结

**改 autopilot SKILL.md design 步骤2，把 `## 验证方案` 列为和 `## 契约规约` 并列的硬要求，按变更类型强制声明测试层级。这是「验证方案」变量的唯一生产者，下游红队/plan-reviewer/qa-reviewer 的既有规则自动激活，零冗余。**
