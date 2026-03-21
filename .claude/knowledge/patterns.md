# Patterns & Lessons

### [2026-03-21] README.md 版本号与 CLAUDE.md 长期不同步
**Scenario**: 插件版本在 CLAUDE.md 更新日志中迭代（v2.0.0 → v2.9.0），但 README.md 标题行版本号从未同步更新
**Lesson**: autopilot-commit 的版本升级步骤只检查 `.claude-plugin/plugin.json` 和 `package.json`，不会自动同步 README.md 中的版本号。多处记录版本号时，升级流程应覆盖所有版本出现位置，或在 autopilot-commit 中增加 README 版本同步检查
**Evidence**: README.md L54 `autopilot (v2.0.0)` 停留了 9 个版本未更新，CLAUDE.md 已记录到 v2.9.0。`grep "autopilot.*v2" README.md CLAUDE.md` 可复现不一致
