#!/bin/bash
# migrate-knowledge.sh — 将 .claude/knowledge/ 迁移到 .autopilot/
#
# 设计原则：
#   - 幂等：可安全重复运行，第二次无副作用
#   - 非破坏性：先 cp -n 合并再清理，不覆盖已存在内容
#   - 不阻断：失败只输出警告，exit 0
#
# 使用场景：
#   1. 主仓库：普通目录 .claude/knowledge/ → .autopilot/
#   2. Worktree：符号链接 .claude/knowledge → .autopilot/ 符号链接
#   3. 两者都不存在：无操作

set -uo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
OLD_PATH="$PROJECT_ROOT/.claude/knowledge"
NEW_PATH="$PROJECT_ROOT/.autopilot"

# 两者都不存在 → 无需迁移
if [[ ! -e "$OLD_PATH" && ! -e "$NEW_PATH" ]]; then
    exit 0
fi

# NEW 已存在且 OLD 不存在 → 已迁移完成
if [[ -e "$NEW_PATH" && ! -e "$OLD_PATH" ]]; then
    exit 0
fi

# OLD 不存在 → 无需迁移
if [[ ! -e "$OLD_PATH" ]]; then
    exit 0
fi

# ─── 场景 1: OLD 是符号链接（worktree） ───
if [[ -L "$OLD_PATH" ]]; then
    RESOLVED_TARGET="$(realpath "$OLD_PATH" 2>/dev/null || true)"

    # 解析主仓库根路径
    MAIN_REPO=""
    if [[ -n "$RESOLVED_TARGET" ]]; then
        # resolved path 形如 /path/to/main/.claude/knowledge，向上两级到主仓库根
        MAIN_REPO="$(cd "$(dirname "$RESOLVED_TARGET")/../.." 2>/dev/null && pwd || true)"
    fi

    # 检查主仓库是否已完成迁移
    if [[ -z "$MAIN_REPO" || ! -d "$MAIN_REPO/.autopilot" ]]; then
        echo "⚠️ 主仓库尚未完成知识库迁移。请先在主仓库运行此脚本。" >&2
        echo "   主仓库路径: ${MAIN_REPO:-未知}" >&2
        exit 0
    fi

    # NEW 已存在
    if [[ -e "$NEW_PATH" ]]; then
        # 已有 .autopilot，只清理旧符号链接
        rm "$OLD_PATH"
        echo "✅ 已移除旧符号链接 .claude/knowledge"
    else
        # 创建 .autopilot 符号链接指向主仓库
        ln -s "$MAIN_REPO/.autopilot" "$NEW_PATH"
        rm "$OLD_PATH"
        echo "✅ worktree 符号链接已更新: .autopilot → $MAIN_REPO/.autopilot"
    fi
    exit 0
fi

# ─── 场景 2: OLD 是普通目录 ───
if [[ -d "$OLD_PATH" ]]; then
    if [[ -d "$NEW_PATH" ]]; then
        # NEW 已存在 → 逐文件合并不覆盖
        cp -n "$OLD_PATH"/* "$NEW_PATH/" 2>/dev/null || true
        if [[ -d "$OLD_PATH/domains" ]]; then
            mkdir -p "$NEW_PATH/domains"
            cp -n "$OLD_PATH/domains"/* "$NEW_PATH/domains/" 2>/dev/null || true
        fi
        echo "✅ 已将 .claude/knowledge/ 内容合并到 .autopilot/（跳过已存在文件）"
    else
        # NEW 不存在 → 直接移动
        mv "$OLD_PATH" "$NEW_PATH"
        echo "✅ 已将 .claude/knowledge/ 迁移到 .autopilot/"
    fi

    # 清理旧的空目录（合并后可能残留）
    if [[ -d "$OLD_PATH" ]]; then
        CONTENTS=$(ls -A "$OLD_PATH" 2>/dev/null || true)
        if [[ -z "$CONTENTS" ]]; then
            rmdir "$OLD_PATH"
        fi
    fi

    # 检测 .gitignore
    GITIGNORE="$PROJECT_ROOT/.gitignore"
    if [[ -f "$GITIGNORE" ]]; then
        if grep -qE '^\*\.autopilot' "$GITIGNORE" 2>/dev/null || \
           grep -qE '^\.autopilot/?$' "$GITIGNORE" 2>/dev/null || \
           grep -qE '^\*' "$GITIGNORE" 2>/dev/null; then
            echo "⚠️ .gitignore 可能忽略 .autopilot/ 目录，建议添加例外："
            echo "   echo '!.autopilot/' >> .gitignore"
        fi
    fi
fi

exit 0
