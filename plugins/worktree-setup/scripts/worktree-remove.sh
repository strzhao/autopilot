#!/usr/bin/env bash
# WorktreeRemove hook — Claude Code worktree-setup plugin
# stdin: {"worktree_path": "/abs/path/...", ...}
set -euo pipefail

WORKTREE_PATH=$(node -e "const d=require('fs').readFileSync(0,'utf8');process.stdout.write(JSON.parse(d).worktree_path)")
echo "→ 清理 worktree: $WORKTREE_PATH" >&2

REPO_ROOT=$(git rev-parse --show-toplevel)
LINKS_FILE="$REPO_ROOT/.claude/worktree-links"

# 先删除符号链接（避免 git worktree remove 因 tracked 文件报错）
if [ -f "$LINKS_FILE" ]; then
  while IFS= read -r file || [ -n "$file" ]; do
    [[ "$file" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${file// }" ]] && continue
    if [ -L "$WORKTREE_PATH/$file" ]; then
      rm "$WORKTREE_PATH/$file" >&2
      echo "   ✓ 移除符号链接: $file" >&2
    fi
  done < "$LINKS_FILE"
else
  for link in "$WORKTREE_PATH"/.env*; do
    [ -L "$link" ] && rm "$link" >&2
  done
fi

# 删除自动生成的 local-config.json
[ -f "$WORKTREE_PATH/local-config.json" ] && rm "$WORKTREE_PATH/local-config.json" >&2

# 获取分支名（用于后续删除分支）
BRANCH=$(git -C "$WORKTREE_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || true)

# 删除 worktree 目录
git worktree remove --force "$WORKTREE_PATH" >&2

# 删除对应分支
if [[ -n "$BRANCH" && "$BRANCH" != "main" && "$BRANCH" != "HEAD" ]]; then
  git branch -D "$BRANCH" >&2 || true
  echo "   ✓ 分支已删除: $BRANCH" >&2
fi

echo "✅ 清理完成" >&2
