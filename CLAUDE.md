# Claude Code 插件市场

本仓库是 String 维护的 Claude Code 插件集合，提供高质量、实用的插件来增强 Claude Code 的功能。

## 项目信息

- **名称**: string-claude-code-plugin-market
- **维护者**: String Zhao
- **邮箱**: zhaoguixiong@corp.netease.com
- **仓库**: https://g.hz.netease.com/cloudmusic-agi/plugins/vip-claude-code-plugin.git

## 插件列表

### 1. summarizer (v1.0.0)
**类型**: Skill 插件
**功能**: 多模态内容摘要工具

**核心能力**:
- 自动识别文章、视频、音频链接
- 使用 Playwright 提取网页内容
- 使用 Video-to-Text MCP 处理视频/音频
- 生成结构化摘要（核心思想、核心论点、关键信息、结论）
- 通过 flomo MCP 保存到笔记

**使用方式**:
用户在对话中发送链接，AI 自动识别并提取摘要。

**依赖 MCP**:
- Playwright MCP
- Video-to-Text MCP
- flomo MCP

---

### 2. task-notifier (v1.0.0)
**类型**: Hook 插件
**功能**: 任务完成提示音

**核心能力**:
- 监听 Task、TodoWrite、TaskComplete、TaskUpdate 工具
- 任务完成后自动播放系统提示音
- 跨平台支持（macOS、Linux、Windows）
- 使用系统原生通知，零配置

**配置位置**:
- `hooks/hooks.json`: Hook 匹配规则
- `assets/scripts/play-sound.sh`: 跨平台通知脚本

---

### 3. autopilot (v2.6.2)
**类型**: Skill + Hook 插件
**功能**: AI 自动驾驶工程套件（全流程闭环 + 智能提交 + 工程诊断）

**包含 Skill**:
- `autopilot`：全流程闭环编排器（红蓝对抗 + 五层 QA + 知识工程 + 自动修复）
- `autopilot-commit`：智能提交工具（React 检测、最佳实践优化、代码理解测验、任务同步）
- `autopilot-doctor`：工程健康度诊断（10 维度评分 + autopilot 兼容性矩阵 + 自动修复）

**核心能力**:
- 从目标描述到代码合并的全程自动化
- 阶段状态机驱动：design → implement → qa → auto-fix → merge
- 仅在两个审批门需要人工介入（设计审批 + 验收审批）
- 红蓝对抗：蓝队按计划编码 + 红队仅看设计文档写验收测试，并行执行、信息隔离
- 五层 QA 检查（Tier 0 红队验收测试 + Tier 1-4）+ 自动修复循环（最多 3 次重试）
- 系统化调试方法论：观察 → 假设 → 验证 → 修复（四阶段）
- 两阶段代码审查：设计符合性 + 代码质量，并行 Sub-Agent 执行（置信度 ≥80 过滤）
- 防合理化表格：对抗 AI 跳过测试/修改红队测试的借口
- 铁律：不允许修改红队测试来通过 QA，成功需要证据，假设需要证据
- 知识工程：design 阶段消费历史决策和模式提升设计质量，merge 阶段反馈驱动提取知识持续积累（.claude/knowledge/）
- 智能提交：三阶段并行执行模型，React 优化、Bugfix 双模式验证（自动化测试 + 运行时验证）、代码测验、CLAUDE.md 更新、版本升级、ai-todo 同步
- 生成高质量中文提交信息（业务描述 + 技术说明）
- 工程诊断：10 维度加权评分（测试/类型/lint/构建/CI/结构/文档/Git/依赖/AI就绪度），S-F 等级，autopilot 兼容性矩阵，`--fix` 自动修复

**使用方式**:
- 运行 `/autopilot <目标描述>` 启动全流程闭环
- `/autopilot commit` 智能提交（独立使用）
- `/autopilot doctor [--fix]` 工程健康度诊断
- `/autopilot approve` 批准审批门
- `/autopilot revise <反馈>` 要求修改

---

### 4. plugin-sync (v1.0.0)
**类型**: Hook 插件
**功能**: 跨模型插件同步工具

**核心能力**:
- 解决 `cc switch` 切换模型后插件丢失问题
- 使用软链接实现所有模型共享插件目录
- 安装插件时自动同步到共享目录
- 切换模型时自动从共享目录恢复

**使用方法**:
1. 安装 plugin-sync 插件
2. 运行初始化脚本：`./plugins/plugin-sync/setup.sh`
3. 之后所有模型的插件自动保持同步

---

---

## 项目结构

```
.
├── .claude-plugin/
│   └── marketplace.json          # 插件市场配置
├── document/
│   ├── hooks.md                  # Hooks 开发文档
│   └── skill_best_practices.md   # Skill 开发最佳实践
├── plugins/
│   ├── summarizer/               # 内容摘要插件
│   │   ├── .claude-plugin/
│   │   ├── .mcp.json
│   │   └── skills/
│   ├── task-notifier/            # 任务提示音插件
│   │   ├── .claude-plugin/
│   │   ├── hooks/
│   │   └── assets/
│   ├── autopilot/                # AI 自动驾驶工程套件
│   │   ├── .claude-plugin/
│   │   ├── hooks/
│   │   ├── scripts/
│   │   └── skills/
│   ├── plugin-sync/              # 跨模型插件同步工具
│       ├── .claude-plugin/
│       ├── hooks/
│       └── assets/
│   └── writer-skill/             # 写作技能包
│       ├── .claude-plugin/
│       └── skills/
│   └── worktree-setup/           # Git Worktree 自动初始化插件
│       ├── .claude-plugin/
│       ├── hooks/
│       ├── scripts/
│       └── skills/
├── README.md                     # 用户文档
├── QUICK_START.md               # 快速开始指南
└── CLAUDE.md                    # 本文件
```

## 开发规范

### Skill 插件规范

1. **目录结构**:
   ```
   skills/skill-name/
   ├── SKILL.md              # AI 行为指南（必需）
   ├── assets/               # 模板和资源
   ├── references/           # 参考文档
   └── scripts/              # 辅助脚本
   ```

2. **SKILL.md 要求**:
   - 明确定义角色和工作流程
   - 提供清晰的指令和示例
   - 包含边界条件和限制

3. **引用文件**:
   - 使用相对路径引用项目内文件
   - 引用文件必须存在且可访问

### Hook 插件规范

1. **目录结构**:
   ```
   hooks/
   └── hooks.json            # Hook 配置
   ```

2. **hooks.json 格式**:
   ```json
   {
       "description": "描述",
       "hooks": {
           "PostToolUse": [
               {
                   "matcher": "ToolName|OtherTool",
                   "hooks": [
                       {
                           "type": "command",
                           "command": "${CLAUDE_PLUGIN_ROOT}/path/to/script.sh",
                           "timeout": 10
                       }
                   ]
               }
           ]
       }
   }
   ```

3. **脚本要求**:
   - 使用 `${CLAUDE_PLUGIN_ROOT}` 变量引用插件根目录
   - 设置合理的超时时间（默认 10 秒）
   - 脚本需要有执行权限

### MCP 配置规范

1. **.mcp.json 格式**:
   ```json
   {
       "mcpServers": {
           "server-name": {
               "command": "npx",
               "args": ["-y", "package-name"],
               "env": {
                   "ENV_VAR": "value"
               }
           }
       }
   }
   ```

2. **环境变量**:
   - 不要在配置中硬编码敏感信息
   - 使用 `${ENV_VAR}` 语法引用环境变量

## 贡献流程

1. 创建新的插件目录 `plugins/plugin-name/`
2. 编写 `.claude-plugin/plugin.json` 元数据
3. 实现插件功能（Skill/Hook/MCP）
4. 编写插件 README.md
5. 更新 `marketplace.json` 添加插件
6. 更新根目录 README.md 和 QUICK_START.md
7. 本地测试验证
8. 提交 PR

## 注意事项

### 安全性
- 不要提交敏感信息（API keys、密码等）
- Hook 脚本需要检查输入有效性
- MCP 命令使用只读操作优先

### 性能
- Hook 超时设置合理（默认 10 秒）
- 避免在 Hook 中执行长时间操作
- Skill 引用文件不要过大

### 兼容性
- 脚本需要跨平台支持（macOS/Linux/Windows）
- 使用标准 POSIX 命令
- 提供降级方案（如 notify-send 不存在时回退到终端响铃）

### 5. writer-skill (v1.6.0)
**类型**: Skill 插件
**功能**: 写作技能包（博客向 + 通用向 + 技术文档向）

**包含 Skill**:
- `writer-blog-skill`：科技博客向，叙事驱动、口语化、类比落地
- `writer-general-skill`：通用写作向，适配评论、分析、访谈整理等多种场景
- `writer-tech-skill`：技术文档向，面向 RFC/Design Doc，语气精确、克制、直接

**使用方式**:
安装插件后，根据场景调用 `/writer-blog-skill`、`/writer-general-skill` 或 `/writer-tech-skill`。

---

### 6. worktree-setup (v2.0.0)
**类型**: Hook 插件
**功能**: Git Worktree 自动初始化工具

**核心能力**:
- `WorktreeCreate` hook：`claude -w <name>` 后自动完成 worktree 初始化
- 按项目 `.claude/worktree-links` 创建符号链接（`.env.local`、`.mcp.json` 等）
- 无配置时自动扫描 `.env*` 文件（新项目零配置可用）
- 确定性端口分配：hash(branch_name) → 4001-4999，避免多 worktree 端口冲突
- 自动识别 npm/yarn/pnpm 并安装依赖（含 `prisma generate`）
- `WorktreeRemove` hook：退出时自动清理符号链接和分支
- `/worktree-setup:repair` skill：手动修复已有 worktree 的配置缺失

**使用方式**:
安装插件后，直接使用 `claude -w <feature-name>` 即可，worktree 创建完即可使用。
如需定制链接文件，在项目 `.claude/worktree-links` 中声明。

---

## 更新日志

### 2026-03-20
- autopilot 升级至 v2.7.1：修复 setup.sh 从未被自动调用 + exit 1 阻断 skill 加载
  - v2.7.0: SKILL.md 添加 `!`command`` 预处理命令注入，setup.sh 不再是死代码
  - v2.7.1: setup.sh 所有 exit 1 改为 exit 0，错误从 stderr 改到 stdout
  - 根因1：SKILL.md 没有使用预处理命令注入 → 状态文件从未被自动创建
  - 根因2：`!`command`` 机制中脚本非零退出会阻止整个 skill 加载 → 用户连 cancel 都用不了
  - 效果：setup.sh 总是 exit 0，错误信息输出到 stdout 让 AI 智能处理，skill 总能正常加载
- worktree-setup 升级至 v2.0.0：Shell 脚本全面重写为 Node.js，消除跨平台兼容性问题
  - 三个 .sh 脚本（worktree-create/remove/repair）合并为统一入口 `scripts/worktree.mjs`
  - 名称清洗改用 JS 原生 regex（天然支持 Unicode），彻底解决 macOS sed/perl 反复报错
  - git 命令改用 `execFileSync` 数组参数，消除命令注入风险
  - 新增 22 个验收测试（node:test），覆盖名称清洗、端口计算、文件解析、子命令路由
  - hooks.json command 改为 `node ... worktree.mjs create/remove`
- autopilot 升级至 v2.6.2：修复状态文件被 stop-hook 误删的严重 bug
  - 根因：AI 用 Write 重写状态文件时丢失 `iteration`/`max_iterations` 字段，stop-hook 数值校验失败后直接 `rm` 删除
  - stop-hook.sh: 数值校验从"删除文件"改为"自动修复缺失字段"（防御性编程）
  - SKILL.md: frontmatter 更新规范中明确列出所有必需字段，禁止用 Write 重写整个状态文件
- autopilot 升级至 v2.6.1：修复 worktree 场景下状态文件找不到的问题
  - lib.sh: PROJECT_ROOT/STATE_FILE 改为延迟初始化函数 `init_paths()`，支持传入 cwd 参数
  - stop-hook.sh: 从 stdin JSON 提取 `cwd` 字段后再初始化路径，解决 hook CWD 不可靠的时序问题
  - setup.sh: 显式调用 `init_paths`，行为更加健壮
- autopilot 升级至 v2.6.0：新增知识工程复合能力
  - design 阶段：进入 Plan Mode 前自动加载 `.claude/knowledge/` 中的历史决策和模式
  - merge 阶段：反馈驱动提取本次工作中的设计决策和调试教训，追加到知识文件
  - 新增 `references/knowledge-engineering.md` 详细消费/提取规则（Progressive Disclosure）
  - 知识存储：decisions.md（决策日志）+ patterns.md（模式教训），单文件 ≤150 行
  - 状态文件模板增加知识库存在性提示
  - 基于业内调研设计（Claude Code memory、Cursor rules、OpenAI AGENTS.md 等）

### 2026-03-19
- autopilot 升级至 v2.5.0：QA 代码审查 Sub-Agent 化
  - Wave 2（Tier 2a/2b）从编排器串行执行改为两个并行 Sub-Agent
  - design-reviewer Agent：设计符合性审查，"不信任报告"独立验证原则
  - code-quality-reviewer Agent：代码质量审查，置信度评分 ≥80 过滤假阳性
  - 新增外置审查清单 review-checklist.md（两级清单 + Suppressions）
  - 完整降级策略：单 Agent 失败不阻塞，双失败编排器兜底
- autopilot 升级至 v2.4.0：新增 autopilot-doctor 工程健康度诊断 skill
  - 10 维度加权评分体系（测试/类型/lint/构建/CI/结构/文档/Git/依赖/AI就绪度）
  - S/A/B/C/D/F 六级评分 + autopilot 兼容性矩阵
  - `--fix` 模式自动修复低分项（每项确认）
  - Wave 1/2 并行策略加速诊断
  - 主 autopilot 在 QA 降级和 merge 阶段自动建议运行 doctor

### 2026-03-18
- autopilot 升级至 v2.3.0：优化 git worktree 适配性
  - `lib.sh` 使用 `git rev-parse --show-toplevel` 计算绝对 PROJECT_ROOT，STATE_FILE 改为绝对路径
  - `setup.sh` 启动信息增加 worktree 检测和状态文件路径提示
  - `stop-hook.sh` prompt 引用改用 $STATE_FILE 变量
  - SKILL.md 增加 worktree 隔离语义说明
- autopilot 升级至 v2.2.0：注入「假设需要证据」原则
  - 新增核心铁律第 7 条：对外部系统行为的假设必须通过运行时验证确认
  - Bugfix 验证重写为双模式：自动化测试 + 运行时验证，无测试框架不再跳过
  - 代码理解测验增强：优先覆盖核心数据流假设
  - 蓝队工作规则追加「假设先验证」：集成外部系统前先用最小手段验证

### 2026-03-16
- autopilot 升级至 v2.1.0：节点级时序修正 + 全面并行化
  - 代码优化前置为 Phase 1.5（串行），修复优化后代码未经验证的时序风险
  - 新增上下文感知：主链路模式自动跳过已由 QA 保障的步骤
  - QA 重构为 Wave 1（Tier 0+1+3+4 并行命令）+ Wave 2（Tier 2a→2b 串行审查），耗时从 ~360s 降至 ~120s
  - implement 准备简化：测试框架发现下放给 Agent，编排器直接并行启动蓝红队
  - auto-fix 支持不同文件的失败项并行修复
- dev-loop + git-tools 合并为 autopilot (v2.0.0)：品牌升级 + 统一工程套件
  - 全流程闭环 `/autopilot <目标>` + 智能提交 `/autopilot commit`
  - 从 superpowers 引入：防合理化表格、CSO 描述优化、成功需要证据原则、系统化调试方法论、两阶段代码审查
  - local-test 融入 QA Tier 1 自动化流程，不再独立暴露

### 2026-03-15
- 新增 worktree-setup 插件 (v1.0.0)：Git Worktree 自动初始化，创建后开箱即用

### 2026-03-10
- git-tools 升级至 v1.8.0：local-test 拟真服务验证 + 用户验收环节
- git-tools 升级至 v1.7.0：三阶段并行执行模型 + Bugfix 自动验证能力
- git-tools 升级至 v1.6.0：新增 local-test skill，本地拟真测试验证工具

### 2026-03-01
- git-tools 升级至 v1.3.0：新增提交前 CLAUDE.md 智能更新步骤、版本自动升级步骤
- 重组 writer-skill 为写作技能包 (v1.4.0)，统一容纳 writer-blog-skill 和 writer-general-skill
- writer-skill 升级至 v1.6.0：新增 writer-tech-skill，专注 RFC/Design Doc 工程规范型文档写作

### 2026-02-08
- 添加 plugin-sync 插件，解决跨模型插件同步问题
- 添加 task-notifier 插件
- 更新文档结构

### 2026-02-07
- 初始版本
- 添加 summarizer 插件
