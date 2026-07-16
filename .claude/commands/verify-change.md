---
description: claude -p 客观验证 autopilot 当前改动符合预期 + 无破坏，普适所有改动
---

用 claude -p（独立 headless session）客观验证 autopilot 仓库**当前改动**（`git diff` / `git status` 识别）是否符合预期、是否带来破坏性变更。

## 三条约束（其余你自行决定）

1. **缓存同步**：claude skill 有缓存——claude -p 加载 `~/.claude/plugins/cache/autopilot/autopilot/<最新版本>/`，而改动在 `plugins/autopilot/` 源码。**验证前必须把改动文件 cp 到缓存对应版本目录**，否则 claude -p 跑旧版，整个验证无效。验证后确认「缓存=源码」。

2. **客观不引导**：claude -p 用中性方式触发（不暗示预期结果），你只读证据陈述事实——**禁用「符合预期 / 应 PASS / 正确 / work」等判断词**，结论留给人据证据下。

3. **AI 自由设计验证**：你根据改动目的，**自行决定**验证哪些场景、怎么用 claude -p 触发、怎么覆盖「符合预期」+「破坏性检查」两个维度。不限制方法。

## 输出
事实陈述：跑了什么、观察到什么。最后给结论。

$ARGUMENTS
