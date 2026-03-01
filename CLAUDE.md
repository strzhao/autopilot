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

### 3. plugin-sync (v1.0.0)
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
│   ├── git-tools/                # Git 提交工具
│   │   ├── .claude-plugin/
│   │   └── skills/
│   └── plugin-sync/              # 跨模型插件同步工具
│       ├── .claude-plugin/
│       ├── hooks/
│       └── assets/
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

### 5. writer-blog-skill (v1.3.0)
**类型**: Skill 插件
**功能**: 写作风格 Skill（博客向）

**核心能力**:
- 让 AI 产出有个人味道的科技文章
- 叙事驱动、口语化、类比落地的写作风格
- 包含禁止清单和格式规范

**使用方式**:
安装插件后，在写作场景中 AI 自动加载写作风格 Skill。

---

## 更新日志

### 2026-03-01
- 将 writer-skill 重命名为 writer-blog-skill (v1.3.0)，为后续 writer-general-skill 做准备

### 2026-02-08
- 添加 plugin-sync 插件，解决跨模型插件同步问题
- 添加 task-notifier 插件
- 更新文档结构

### 2026-02-07
- 初始版本
- 添加 summarizer 插件
