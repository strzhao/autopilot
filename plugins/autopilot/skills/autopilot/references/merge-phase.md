# Phase: merge — 详细工作流

## 1. 调用 commit Agent（上下文隔离提交）

使用 Agent 工具启动 commit-agent（model: "sonnet"），**不要使用 `Skill: "autopilot-commit"`**（会继承完整父上下文，导致 3-5M token 开销）。

**预收集 Agent 输入**（编排器在启动 Agent 前通过 Bash 获取）：
- `git diff --stat` 输出（变更概况）
- `git diff` 完整 diff（供分析具体改动）
- 设计文档的目标一句话（从状态文件 `## 设计文档` 提取）
- commit type 判断依据（根据变更性质判断 feat/fix/refactor 等）
- 项目根目录路径

**启动 Agent**：prompt 参考 `references/commit-agent-prompt.md` 模板，填入上述输入。Agent 执行：分析变更 → 生成 commit message（中文） → git add → git commit → 版本号升级 → CLAUDE.md 更新。

编排器收到 Agent 结果后，验证 `git log --oneline -1` 确认提交成功。

## 1.5. 写入 Handoff（brief 模式）

如果 frontmatter `brief_file` 非空（任务来自项目 DAG）：

1. 从 `brief_file` 路径推导 handoff 路径：将 `.md` 替换为 `.handoff.md`（如 `tasks/001-wire-schema.md` → `tasks/001-wire-schema.handoff.md`）
2. 写入 handoff 文件（≤500 字），包含：实现摘要、文件变更列表、下游须知、偏差说明
3. 更新 `.autopilot/project/dag.yaml` 中对应任务的 `status` 从 `pending`/`in_progress` 改为 `done`
4. 追加变更日志：handoff 已写入

## 2. Auto-Chain 评估（brief 模式专用）

如果 `brief_file` 非空（项目子任务），在提交和 handoff 完成后评估是否自动链接下一个任务。

详细的信心评估标准参见 `references/auto-chain-guide.md`。

简要流程：
1. 读取 QA 报告：是否全部 ✅，retry_count 是否为 0
2. 读取 handoff：是否有"偏差说明"
3. 读取 `.autopilot/project/dag.yaml`：找下一个就绪任务
4. 高信心 + 有就绪任务 → Edit frontmatter `next_task: "<task-id>"`
5. 低信心或无就绪任务 → 保持 `next_task: ""`

## 2.5. CI 验证（条件触发）

commit 完成后，如果当前 commit 已被 push 到远端且远端配置了 GitHub Actions，必须等待 CI 结论。

### 触发条件（全部满足才执行）
1. 项目根目录存在 `.github/workflows/*.yml`（`ls .github/workflows/*.yml 2>/dev/null` 非空）
2. `gh` CLI 可用（`command -v gh` 成功）
3. 远端能查到本次 commit 触发的 CI run（`gh run list --branch "$(git rev-parse --abbrev-ref HEAD)" --limit 5 --json databaseId,headSha,status` 中存在 headSha 等于本次 HEAD 的 run）

### 执行流程
1. 找到本次 commit 对应的 run id
2. `gh run watch <run-id> --exit-status`，超时 600s
3. CI 通过（exit 0）→ 追加变更日志"CI 通过：<run-url>"，继续步骤 3
4. CI 失败（exit ≠ 0）→ 设置 frontmatter `phase: "auto-fix"` 和 `qa_scope: "selective"`，`retry_count` 不变（CI 失败属于新一轮 QA 不计入 auto-fix retry），追加变更日志"CI 失败：<run-url> + 失败 job 摘要"

### 降级（任何一项不满足即跳过，不阻塞）
- `.github/workflows` 不存在 → 静默跳过
- gh CLI 未安装 → 变更日志记录"gh CLI 不可用，跳过 CI 验证"
- gh run list 找不到对应 run（commit 未被 push 或 CI 未触发）→ 变更日志记录"未找到对应 CI run，commit 可能未推送，跳过"
- gh run watch 超时（600s）→ 变更日志记录"CI 仍在跑，请手动 gh run view <id> 检查"，不阻塞 phase 推进
- 本步骤抛任何异常 → 视同降级跳过，不影响 merge 完成

### 与默认行为的关系
**不改变 autopilot 默认 commit-only 行为**。本步骤不发起 push，仅在 commit 已被 push 的场景下检测 CI。这与全局 CLAUDE.md "git push 后如果当前工程有 cicd, 那么要主动观察 cicd 的结论"一致。

## 3. 知识提取与沉淀

commit Agent 完成后，回顾本次全流程产出，提取值得持久化的知识。

1. 读取 `references/knowledge-engineering.md` 获取完整提取规则和格式模板
2. 分析状态文件中的设计文档、QA 报告、变更日志、auto-fix 修复历程
3. 反馈驱动判断：仅记录有真实学习价值的条目（设计权衡、调试教训、项目特有约定）
4. 有值得记录的条目：
   a. 自动生成 tags
   b. 确定写入目标文件：通用条目 → `decisions.md` / `patterns.md`；领域特定条目 → `domains/{domain}.md`
   c. 追加条目到目标文件（使用 `<!-- tags: ... -->` 格式）
   d. 同步更新 `index.md`
   e. 检查全局文件行数：>100 行时建议迁移到 `domains/`
   f. 确定知识库 git 提交上下文（worktree 安全路由，v3.18+ 选择性 symlink）：
      - **步骤 1**：遍历 SHARED 项（`decisions.md`/`patterns.md`/`index.md`/`domains`/`project`/`requirements`）找第一个 symlink 作为锚点 → 解析其真实路径所在仓库（`MAIN_REPO=$(cd "$(dirname "$(realpath "$ANCHOR")")/.." && git rev-parse --show-toplevel)`），用 `git -C "$MAIN_REPO"` 提交 → 完成
      - **步骤 2**（无任何 SHARED 项是 symlink）：检查 `.git` 是文件（worktree）还是目录（主仓库）→ 参见 references/knowledge-engineering.md
      - **步骤 3**（非 worktree、无 SHARED symlink）：当前目录就是主仓库，正常 `git add .autopilot/ && git commit -m "docs(knowledge): ..."`
5. 无值得记录的内容 → 在变更日志追加"知识提取：本次无新增"后跳过

时间限制 2 分钟。宁可少写高质量条目，不要穷举。

## 4. 最终总结

输出结构化完成报告（6 个区块）。报告模板和格式要求参见 `references/completion-report-template.md`。

## 5. 清理
- 更新 frontmatter：`phase: "done"`
- Stop hook 检测到 done 后会自动清理状态文件并发送完成通知
- 如果设置了 `next_task`，stop-hook 会自动创建下一个任务的状态文件并继续循环
