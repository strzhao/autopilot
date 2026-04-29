---
name: autopilot-continue
description: 新会话继续一个已有的 autopilot 需求（列出未完成需求供选择）。
---

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/continue.sh" '$ARGUMENTS'`

# Autopilot Continue — 继续已有需求

新 session 想继续一个已有的、尚未完成的 autopilot 需求时使用此 skill。

setup 脚本会扫描 `.autopilot/requirements/*/state.md`，列出所有 phase != done 的需求，
用户选择后写入 `active.$PPID` 指针，然后加载 autopilot skill 继续执行。

读取 setup 脚本的输出：
- 如果输出包含"已绑定"，说明需求已选定，读取状态文件并按 autopilot skill 继续执行当前阶段
- 如果输出包含"没有未完成的需求"，告知用户并结束
- 如果输出包含"请选择"，使用 AskUserQuestion 让用户选择，然后重新运行 setup 脚本传入选择的序号
