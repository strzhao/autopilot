# Claude Code 插件市场

String 维护的 Claude Code 插件集合。

- **维护者**: String Zhao（stringzhao@foxmail.com）
- **仓库**: https://github.com/strzhao/autopilot.git

## 插件索引

详细能力见各插件 `plugins/<name>/README.md` 与 `SKILL.md`，本表只做导航。

| 插件 | 版本 | 类型 | 一句话 |
|------|------|------|--------|
| [autopilot](plugins/autopilot/) | v3.48.0 | Skill + Hook | AI 自动驾驶工程套件：全流程闭环、AI 自适应 fast/standard、智能提交、工程诊断、worktree 自动初始化（选择性 symlink）+ brainstorm 独立 skill + plan-review HTML 左侧 TOC 导航 + `.autopilot/` 二级分层 knowledge/+runtime/（三层防御）+ QA 谓词闸门（EARS-OST + 观测绑定 + 三元组 + 强制 artifact）+ **谓词传动轴接线：`## 验收场景` 成全链路谓词 SSOT，贯通红队双消费（据 det/real 谓词写 Tier-0 硬断言）/ Tier 1.5（编排器据谓词驱动真实产物产三元组）/ 闸门 / 报告，治 B 遗留的悬空引用** + **Tier 1 AI-First 反过拟合减法（plan-reviewer 去伪精度分数线 / qa-reviewer 正则转语义 / Explore 计数自适应 / 防合理化去重）** + stop-hook 后台 sub-agent 静默等待泛化到全阶段（根治 merge commit-agent 近似死循环，消灭 flag-asymmetry）+ **stop-hook §7.6 standard design 放行交回用户对齐，根治 design 阶段被自动推进绕过审批** + **stop-hook §7.5 silent-wait 放行加 systemMessage 可见性（等待从用户不可见改为可见提示）+ /autopilot cancel 自救出路** + **v3.42.0: 4 个确定性硬信号根治 QA 假阳性（lib.sh freshness_check 产物新鲜度判定 + lock_acceptance_tests/acceptance_tests_tampered + stop-hook §8.5.1 tamper 守卫 + Tier 5 na 可见化「⚠️ 测试有效性维度未验证」非 PASS + coverage 反向否决口径成文，全脚本/成文规则层，零 prompt 自检规则）** + **v3.42.1: set_field upsert 修复（键缺失从 no-op 改追加，根治 fast_mode→smoke 降级在生产单任务模式从未生效，知识库 [2026-05-30]）+ detect-smoke-eligible 生产口径回归路径 I** + **v3.43.0: fast_mode 判定时机搬迁（启动流程步骤 2 零代码上下文盲判 → design 步骤 1 探针后定，与 single/project 共用一次探针；SKILL 行数净 0、stop-hook 零改动）** + **v3.43.1: §7.6 加 design_doc_written 前置（只在设计文档已落盘的审批点放行；brainstorm 完成的接力点设计文档空 → fall through §9 自动唤醒接力，根治 v3.43.0 一刀切放行误停接力点、逼用户手动「继续」的回归）** + **v3.44.0: knowledge 时效性信号（design 加载 >180 天条目引用代码事实前须 grep/Read 核对 + merge 提取在 Evidence 留「核对锚点」，治 knowledge 随版本演进静默失效；源自 memdir memoryFreshnessText 对比调研）** + **v3.45.0: 删除 fast mode design 自审（自审无独立性橡皮图章、几乎不发现问题，纯浪费 token；改直进 implement/HTML 评审）** + **v3.46.0: 蓝队交付前验证边界重定义——规则8「真实场景冒烟」→「编译期健康自检」，消解与 QA Tier 1.5 职责重叠；纯追加 AI 决策心智 + 终止边界(复用[!]) + anti-rationalization「多做越界」反向条目；治蓝队越界做完整测试致耗时(实测 4.2x)** + **v3.47.0: 红蓝编译耦合根治——红队验收测试写 acceptance-staging 暂存区脱离编译路径 + stop-hook §8.5.0.5 确定性合流 bash（读 manifest→mv→lock→写状态，挂 §8.5.1 tamper 守卫前）；机械活下沉 hook 不塞 prompt（skill脆弱→确定性）+ 智力活（target_path 判断）留红队 agent（AI强大）；蓝队 prompt 零改动、skill md 净减行；治红队验收测试编译失败连累蓝队 build/test（buddy 实证 Swift --filter 不过滤编译）** + **v3.48.0: 快照 oracle 污染守卫——lib.sh snapshot_oracle_regened（git diff 检测快照/baseline 改动或删除，三态 0/2/1）+ stop-hook §8.5.2（implement→qa 一次性检测，rc==2 或 stdout 含 ORACLE-REGHEN → block 注入确定性 prompt「快照判别力失效，需独立 oracle」）；治 a56a55fe 实证 AI 删快照 baseline 重录后用 14/14 冒充 T1.5 谓词全 PASS（未启动 app）；SKILL.md 零改动，确定性硬信号层兜底** |
| [writer-skill](plugins/writer-skill/) | v1.11.0 | Skill | 写作技能包：博客向 / 技术文档向 / 专业技术博客向 / 文章评价 |
| [summarizer](plugins/summarizer/) | v1.0.0 | Skill | 多模态内容摘要（文章/视频/音频 → flomo） |
| [task-notifier](plugins/task-notifier/) | v1.0.0 | Hook | 任务完成系统提示音 |
| [plugin-sync](plugins/plugin-sync/) | v1.0.0 | Hook | 跨模型插件同步（解决 `cc switch` 切换后插件丢失） |

## ⚠️ 核心开发原则

### 源码唯一性（Single Source of Truth）

**所有插件修改必须在本仓库源码（`plugins/`）中进行，禁止直接改 `~/.claude/plugins/cache/`。**

- 缓存目录是只读副本，在那里改不会回流到仓库，会导致版本分叉
- 历史教训：autopilot v2.8.0 一次 SKILL.md 整体重写曾意外回退 v2.9.0~v2.10.0 的功能，缓存却继续迭代到 v2.13.0，源码与运行版本长期不一致
- 流程：改源码 → 提交 → 重新安装插件

### 版本管理（升级时必须全部同步）

| 文件 | 说明 |
|------|------|
| `plugins/<name>/.claude-plugin/plugin.json` | 插件系统据此检测新版本，遗漏 = 用户无法更新 |
| `plugins/<name>/package.json`（如存在） | npm 包版本 |
| `.claude-plugin/marketplace.json` | 仓库级索引，按 `name` 字段定位条目更新 `version` |
| 本文件「插件索引」表中的 `vX.Y.Z` | 列表展示版本号 |

autopilot-commit 已通过"读 CLAUDE.md + grep 校验"动态发现这些位置，新增版本文件时同步更新本表即可。

## 开发规范

- **Skill 插件**：`plugins/<name>/skills/<skill-name>/SKILL.md` 必需。详见 `document/skill_best_practices.md`
- **Hook 插件**：`plugins/<name>/hooks/hooks.json` 配置匹配规则，脚本用 `${CLAUDE_PLUGIN_ROOT}` 引用，超时默认 10s。详见 `document/hooks.md`
- **MCP 配置**：`.mcp.json` 中用 `${ENV_VAR}` 引用敏感信息，禁止硬编码

## 贡献流程

1. 新建 `plugins/<name>/` 与 `.claude-plugin/plugin.json`
2. 实现功能 + 写 README.md
3. 更新 `.claude-plugin/marketplace.json` 与本文件「插件索引」
4. 本地验证后提交 PR

## 注意事项

- **安全**：不提交 secrets；hook 校验输入；MCP 优先只读
- **性能**：hook 超时合理，避免长任务；skill 引用文件不要过大
- **兼容**：脚本跨平台（macOS/Linux/Windows），用 POSIX 命令，提供降级方案

## .autopilot/ 文件管理

autopilot 工具的所有产物分为两类，目录拓扑即语义：

| 目录 | 入库策略 | 含义 | 典型内容 |
|------|----------|------|----------|
| `.autopilot/knowledge/` | **入库**（git 跟踪） | 跨任务、跨协作者共享的持久知识 | `decisions.md`（架构决策）/ `patterns.md`（最佳实践模式）/ `index.md`（知识索引）/ `domains/`（领域专项知识） |
| `.autopilot/runtime/` | **不入库**（`.gitignore`） | 单次运行的状态、per-worktree session、临时产物 | `active.ptr`（当前任务指针）/ `requirements/<slug>/`（任务实例：state.md/brainstorm.md/visual/）/ `sessions/`（per-worktree 隔离）/ `sub-agent/` / `worktree-links.txt` / `doctor-report.md` |

**判定原则（AI commit 时无需记规则，目录名即答案）**：

- `git status` 看到 `.autopilot/knowledge/` 下改动 → **正常 commit**，这是知识沉淀，需要共享
- `.autopilot/runtime/` 下的内容由 `.gitignore` 拦截，**永远不会出现在 `git status`**，无需判断
- 一旦 `git status` 显示 `runtime/` 下文件 → **配置异常**，先检查 `.gitignore` 是否包含 `.autopilot/runtime/`

**向后兼容**：旧版 `.autopilot/` 平铺布局（`decisions.md` / `active` / `requirements/` 在顶层）由 `setup.sh` 首次运行时自动迁移，迁移幂等，详见 `plugins/autopilot/scripts/setup.sh` 早期迁移区。

## 历史

更新历史见 `git log`。重大变更会在对应插件的 README / SKILL.md 顶部注明。
