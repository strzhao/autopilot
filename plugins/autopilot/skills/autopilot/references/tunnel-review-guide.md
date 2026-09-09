# Tunnel 详审页（按需触发）

## 触发条件

仅在用户于审批卡点 / 验收决策卡之后表达「要细看 / 想看全部过程」时使用。预授权（auto_approve=true 或用户已明确决策）**不主动部署**——决策卡顶格信息已够决策，详审页是按需加载，不是默认产物。

## 流程

### 1. 生成 review md

从 QA 报告与状态文件汇集**决策卡顶格 + 过程审计全部下沉**：

```markdown
# autopilot 详审：<一句话目标>

{验收决策卡原样顶格：粗体一句话总结 + ### 端到端真实验证结论 / ### 遗留问题 / ### 风险 / ### 证据一行链（结构与规约见 references/qa-report-template.md）}

---

## 过程审计（按需下沉区）

### Tier 全表
{QA 报告 Tier 0/1/1.5/2/3.5/5 完整表格}

### auto-fix 清单
{各轮失败项 → 根因 → 修复 → 验证记录}

### plan-reviewer 历史
{设计审查轮次与结论摘要}
```

### 2. 内嵌交互组件（审批钮前置）

在文件**顶部**（决策卡之前）插入 `<!-- twq:submit-top -->`（审批钮前置，读者不用滚到页尾），随后内嵌 interactive 组件收集决策与反馈。组件骨架可用 `tunnel drops example --out 方案.md` 拿模板后改用：

````markdown
<!-- twq:submit-top -->

```interactive
- id: decision
  label: 你的决策
  type: radio
  options:
    - 批准合入
    - 带遗留合入
    - 回炉修复
- id: feedback
  label: 补充反馈（可选）
  type: text
```
````

三选项为契约字面；`feedback` text 组件收集读者反馈（选「带遗留合入 / 回炉修复」时写明留痕或回炉重点）。

### 3. 部署与收结论

```bash
tunnel deploy <review.md 路径> --name autopilot-review-<slug>   # slug 取任务 slug，防撞名
```

发链接给用户 → 用户网页操作 → 编排器收聚合结论：

```bash
tunnel drops results autopilot-review-<slug>
```

### 4. 按 choice 推进

| choice | 动作 |
|--------|------|
| 批准合入 | 照常推进 merge（`gate: ""` → `phase: "merge"`） |
| 带遗留合入 | 推进 merge + 变更日志留痕（遗留条目 + 用户反馈原文） |
| 回炉修复 | `phase: "auto-fix"`（把反馈写入失败项清单，走既有 auto-fix 流） |

## 降级路径

tunnel 不可用 / 部署失败 / `tunnel drops results` 收不到结论 → 回退 `AskUserQuestion`，复用三选项字面（与 SKILL.md 结果判定段收口点名问一致）：**补验证后合入 / 带遗留合入 / 回炉修复**。不因部署失败阻塞任务。
