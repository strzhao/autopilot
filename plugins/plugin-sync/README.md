# Plugin Sync - Claude Code 跨模型插件同步工具

解决 `cc switch` 切换模型后插件丢失的问题，实现所有模型共享同一套插件配置。

## 问题背景

Claude Code 的 `cc switch` 命令切换模型（如从 kimi-k2.5 切换到 deepseek）时，每个模型使用独立的配置目录，导致：
- 在 kimi-k2.5 下安装的插件，切换到 deepseek 后消失
- 需要为每个模型重复安装相同的插件
- 插件配置无法保持一致

## 解决方案

通过**软链接共享目录**实现激进的同步策略：

```
~/.claude/
├── .shared-plugins/          # 共享插件目录（实际存储）
│   ├── cache/               # 插件缓存
│   ├── marketplaces/        # 市场配置
│   └── installed_plugins.json
└── plugins -> .shared-plugins/  # 软链接（所有模型共享）
```

## 快速开始

### 1. 安装插件

```bash
# 在你的插件市场目录
/install /path/to/autopilot
```

### 2. 运行初始化脚本

```bash
cd ~/.claude/plugins/cache/autopilot/plugin-sync/1.0.0
./setup.sh
```

或手动执行：

```bash
~/.claude/plugins/cache/autopilot/plugin-sync/1.0.0/assets/scripts/sync.sh init
```

### 3. 验证安装

```bash
# 检查状态
~/.claude/plugins/cache/autopilot/plugin-sync/1.0.0/assets/scripts/sync.sh status
```

## 工作原理

### Hook 自动同步

安装此插件后，以下操作会自动触发同步：

1. **插件安装/更新/卸载后** (`PostToolUse`)
   - 自动将当前插件状态同步到共享目录

2. **会话开始时** (`SessionStart`)
   - 自动从共享目录恢复插件配置
   - 这会在每次启动 Claude Code 或切换模型后自动同步

### 手动同步命令

```bash
# 查看当前状态
./sync.sh status

# 同步当前配置到共享目录（安装新插件后）
./sync.sh sync-to

# 从共享目录恢复配置（切换到新模型后）
./sync.sh sync-from

# 自动检测并执行合适的操作
./sync.sh auto
```

## 目录结构

```
plugin-sync/
├── .claude-plugin/
│   └── plugin.json          # 插件元数据
├── hooks/
│   └── hooks.json           # Hook 配置
├── assets/
│   └── scripts/
│       └── sync.sh          # 核心同步脚本
├── setup.sh                 # 一键初始化脚本
└── README.md                # 本文件
```

## 注意事项

### ⚠️ 激进方案警告

此插件使用**软链接共享目录**，意味着：
- ✅ 所有模型看到的插件完全一致
- ✅ 安装一次，全模型生效
- ⚠️ 在一个模型中卸载插件，所有模型都会卸载
- ⚠️ 如果误删共享目录，所有模型的插件都会丢失

### 备份

初始化时会自动备份原有配置到：
```
~/.claude/.plugin-config-backups/
```

### 恢复原始状态

如需恢复为模型独立配置：

```bash
./sync.sh remove-links
# 然后从备份恢复
mv ~/.claude/plugins.backup.xxxx ~/.claude/plugins
```

## 故障排查

### 插件同步后仍然不生效

1. 检查软链接是否正确：
   ```bash
   ls -la ~/.claude/plugins
   # 应该显示: plugins -> /Users/xxx/.claude/.shared-plugins
   ```

2. 检查共享目录内容：
   ```bash
   ls -la ~/.claude/.shared-plugins/
   ```

3. 手动重新同步：
   ```bash
   ./sync.sh sync-from
   ```

### 切换模型后插件消失

确保 plugin-sync 插件本身已安装在用户级别（而非项目级别）：
```bash
# 检查是否在用户级别
cc settings enabledPlugins
```

## 更新日志

### v1.0.0
- 初始版本
- 支持软链接共享方案
- 支持 Hook 自动同步
- 支持手动同步命令

## License

MIT
