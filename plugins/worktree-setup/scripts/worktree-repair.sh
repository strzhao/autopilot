#!/usr/bin/env bash
# 修复/补全一个已存在 worktree 的配置（symlinks + deps）
# 被 worktree-create.sh 和 repair skill 共同调用
# 用法: bash worktree-repair.sh [worktree_path]
set -euo pipefail

WORKTREE_PATH="${1:-$(pwd)}"
REPO_ROOT=$(git -C "$WORKTREE_PATH" rev-parse --show-toplevel 2>/dev/null \
  || git rev-parse --show-toplevel)

echo "→ 修复 worktree: $WORKTREE_PATH" >&2
LINKS_FILE="$REPO_ROOT/.claude/worktree-links"

if [ -f "$LINKS_FILE" ]; then
  echo "→ 按 .claude/worktree-links 创建符号链接..." >&2
  while IFS= read -r file || [ -n "$file" ]; do
    [[ "$file" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${file// }" ]] && continue
    src="$REPO_ROOT/$file"
    dst="$WORKTREE_PATH/$file"
    if [ -f "$src" ] && [ ! -e "$dst" ]; then
      ln -sf "$src" "$dst" >&2
      echo "   ✓ 链接: $file" >&2
    elif [ -L "$dst" ]; then
      echo "   — 已存在: $file" >&2
    else
      echo "   ⚠ 跳过（源文件不存在）: $file" >&2
    fi
  done < "$LINKS_FILE"
else
  echo "→ 无 .claude/worktree-links，自动链接 .env* 文件..." >&2
  for src in "$REPO_ROOT"/.env*; do
    [ -f "$src" ] || continue
    file=$(basename "$src")
    dst="$WORKTREE_PATH/$file"
    if [ ! -e "$dst" ]; then
      ln -sf "$src" "$dst" >&2
      echo "   ✓ $file（自动）" >&2
    fi
  done
fi

if [ ! -d "$WORKTREE_PATH/node_modules" ]; then
  echo "→ 安装依赖（自动识别包管理器）..." >&2
  cd "$WORKTREE_PATH"
  if [ -f "pnpm-lock.yaml" ]; then
    pnpm install >&2
  elif [ -f "yarn.lock" ]; then
    yarn install >&2
  else
    npm install >&2
  fi
else
  echo "→ node_modules 已存在，跳过安装" >&2
fi

echo "✅ 修复完成" >&2
