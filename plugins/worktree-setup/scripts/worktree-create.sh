#!/usr/bin/env bash
# WorktreeCreate hook — Claude Code worktree-setup plugin
# stdin: {"name": "feature-xxx", ...}
# stdout: 只输出 worktree 绝对路径（其他输出必须 >&2，否则 Claude 静默卡住）
set -euo pipefail

RAW_NAME=$(node -e "const d=require('fs').readFileSync(0,'utf8');process.stdout.write(JSON.parse(d).name)")

# Sanitize: 空格/特殊字符替换为连字符，确保 git 分支名合法
NAME=$(echo "$RAW_NAME" | sed 's/[[:space:]]/-/g; s/[^a-zA-Z0-9\u4e00-\u9fff._/-]/-/g; s/--*/-/g; s/^-//; s/-$//')

REPO_ROOT=$(git rev-parse --show-toplevel)
WORKTREE_PATH="$REPO_ROOT/.claude/worktrees/$NAME"
BRANCH="worktree-$NAME"

echo "→ 创建 worktree: $NAME (分支: $BRANCH)" >&2

# 自动检测默认分支（main/master/...），fallback 到当前 HEAD
DEFAULT_BRANCH=""
if git remote show origin &>/dev/null; then
    DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p')
    if [[ -n "$DEFAULT_BRANCH" ]]; then
        git fetch origin "$DEFAULT_BRANCH" >&2
        git worktree add "$WORKTREE_PATH" -b "$BRANCH" "origin/$DEFAULT_BRANCH" >&2
    fi
fi
if [[ -z "$DEFAULT_BRANCH" ]]; then
    echo "→ 无 origin remote 或无法检测默认分支，基于当前 HEAD 创建" >&2
    git worktree add "$WORKTREE_PATH" -b "$BRANCH" HEAD >&2
fi

# 符号链接 + 依赖安装（共用 repair 脚本）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/worktree-repair.sh" "$WORKTREE_PATH" >&2

# 确定性端口：hash(branch) → 4001-4999，避免多 worktree 同时运行时端口冲突
PORT=$(echo "$BRANCH" | node -e "
  const s=require('fs').readFileSync(0,'utf8').trim();
  let h=0; for(let i=0;i<s.length;i++) h=(h*31+s.charCodeAt(i))>>>0;
  process.stdout.write(String(4001+(h%999)))")
echo "→ 分配端口: $PORT" >&2
cat > "$WORKTREE_PATH/local-config.json" <<EOF
{"server":{"devPort":$PORT,"hostname":"localhost","enableHttps":false}}
EOF

echo "✅ Worktree 就绪，dev 端口: $PORT" >&2
echo "$WORKTREE_PATH"   # ← 唯一 stdout，Claude Code 用于定位 worktree
