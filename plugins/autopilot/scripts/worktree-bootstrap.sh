#!/bin/bash
# autopilot SessionStart hook — worktree 兜底初始化
#
# 背景：Claude Code 当前版本 (≤ 2.1.128) 的 `claude code -w` 只派发
# WorktreeCreate hook 给 user/project settings.json，不派发给 plugin
# hooks.json (https://github.com/anthropics/claude-code/issues/36205)。
# plugin 的 WorktreeCreate hook 在 -w 流程下不会触发，本脚本通过
# SessionStart hook 兜底完成 symlink + 依赖安装 + local-config.json。
#
# 必须幂等：主仓库 session 立即退出；已配好的 worktree 立即退出。

set -e

# 读 stdin 拿 cwd（Claude Code 传 JSON: {session_id, cwd, hook_event_name, ...}）
# 用 jq 与项目其他 hook（stop-hook.sh）保持一致风格
INPUT="$(cat)"
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null) || CWD=""

# 兜底：jq 解析失败 / 无 jq / cwd 缺失时用当前 pwd
[ -z "$CWD" ] && CWD="$(pwd)"

# 不在 worktree（.git 是目录而非文件）→ silent exit
[ -f "$CWD/.git" ] || exit 0

# 已配好（.autopilot 是 symlink + node_modules 存在）→ silent exit
[ -L "$CWD/.autopilot" ] && [ -d "$CWD/node_modules" ] && exit 0

# 真要跑 repair——通过 stderr 让用户看到进度
echo "[autopilot] worktree 检测到未配置，自动 repair（首次会跑 pnpm install）..." >&2
node "${CLAUDE_PLUGIN_ROOT}/scripts/worktree.mjs" repair "$CWD" >&2 || {
    echo "[autopilot] repair 失败，保持原状不影响 session 启动" >&2
}
exit 0
