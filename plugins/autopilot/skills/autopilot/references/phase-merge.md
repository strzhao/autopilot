# Phase: merge — 合并阶段

> 📋 读取状态文件后，本阶段重点关注 `## 设计文档` 和 `## QA 报告`（最近一轮）区域。

## 目标
完成代码提交和最终收尾。

## 工作流程

### 1. 调用 autopilot-commit
使用 `Skill: "autopilot-commit"` 执行智能提交。

### 2. 知识提取与沉淀

autopilot-commit 完成后，回顾全流程产出提取知识。

1. 读取 `references/knowledge-engineering.md` 的 `## Extraction Rules` 节
2. 分析状态文件中的设计文档、QA 报告、变更日志、auto-fix 历程
3. 反馈驱动判断：仅记录有真实学习价值的条目
4. 有值得记录的条目：
   a. 自动生成 tags（模块名、技术栈、问题类型）
   b. 确定目标文件：通用 → `decisions.md`/`patterns.md`；领域 → `domains/{domain}.md`
   c. 追加条目（`<!-- tags: ... -->` 格式）
   d. 同步更新 `index.md`
   e. 全局文件 >100 行时建议迁移到 `domains/`
   f. 知识库 git 提交（worktree 安全路由）：
      - **步骤 1**：`.claude/knowledge` 是符号链接 → 解析主仓库，`git -C` 提交
      - **步骤 2**：非符号链接但在 worktree 中（`.git` 是文件）→ 复制到主仓库 + `git -C` 提交 + 自愈符号链接
      - **步骤 3**：非 worktree → 正常 `git add && git commit`
5. 无新增 → 变更日志追加"知识提取：本次无新增"

时间限制 2 分钟。宁可少写高质量条目。

### 3. 最终总结
输出结构化完成报告（6 区块）。格式参见 `references/completion-report-template.md`。

### 4. 清理
- 更新 frontmatter：`phase: "done"`
- Stop hook 检测到 done 后自动清理
