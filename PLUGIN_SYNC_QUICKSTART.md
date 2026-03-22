# Plugin Sync 快速开始

## ✅ 部署状态

已完成以下配置：
- [x] 共享目录创建：`~/.claude/.shared-plugins/`
- [x] 软链接设置：`plugins → .shared-plugins/`
- [x] Plugin Sync 插件部署
- [x] 插件已启用
- [x] 插件已注册

## 🚀 使用方法

### 无需手动操作（自动同步）

现在你已经可以：**在任意模型下安装插件，切换到其他模型后插件仍然可用**

Hook 会自动处理：
- 安装新插件时 → 自动同步到共享目录
- 切换模型时 → 自动从共享目录恢复

### 手动命令（如需）

```bash
# 进入 plugin-sync 目录
cd ~/.claude/plugins/cache/autopilot/plugin-sync/1.0.0

# 查看状态
./assets/scripts/sync.sh status

# 手动同步到共享目录
./assets/scripts/sync.sh sync-to

# 手动从共享目录恢复
./assets/scripts/sync.sh sync-from
```

## 🧪 验证测试

**测试步骤：**

1. **确认当前插件**（在 kimi-k2.5 下）：
   ```bash
   ls ~/.claude/plugins/cache/
   ```

2. **切换到另一个模型**：
   ```bash
   cc switch deepseek
   ```

3. **检查插件是否还在**：
   ```bash
   ls ~/.claude/plugins/cache/
   # 应该看到相同的插件列表
   ```

## ⚠️ 注意事项

### 这是激进方案
- ✅ 所有模型完全共享插件
- ✅ 安装一次，全模型生效
- ⚠️ 卸载插件会全模型卸载

### 备份
原配置已备份：`~/.claude/plugins.backup.20260208_143314/`

### 恢复独立配置
如需恢复为模型独立配置：
```bash
rm ~/.claude/plugins  # 删除软链接
mv ~/.claude/plugins.backup.xxxx ~/.claude/plugins
```

## 📁 文件位置

```
~/.claude/
├── .shared-plugins/          # 共享插件存储
├── plugins -> .shared-plugins/  # 软链接
└── plugins.backup.xxxx/      # 原配置备份

插件源码:
~/workspace_sync/personal_projects/autopilot/plugins/plugin-sync/
```

---

**现在可以安全地使用 `cc switch` 切换模型了，插件会自动保持同步！**
