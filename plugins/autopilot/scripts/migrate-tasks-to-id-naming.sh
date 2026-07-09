#!/usr/bin/env bash
# migrate-tasks-to-id-naming.sh
#
# 把项目的 .autopilot/project/tasks/ 下按 NNN-<name>.md 命名的任务文件
# 重命名为 <id>.md / <id>.handoff.md（id 从 dag.yaml 读取，按 name 反查匹配文件）。
#
# 背景：autopilot project 模式 auto-chain 要求 dag.yaml 的 id ≡ 任务文件名 stem。
# 旧项目文件命名为 NNN-<name>.md（如 005-t4-media.md），但 dag.yaml 的 id 可能是 T4，
# 导致 stop-hook/lib.sh/setup.sh 的 id 查找全失败。
#
# 用法：
#   bash migrate-tasks-to-id-naming.sh /path/to/project
#
# 幂等：若文件已符合 <id>.md 命名（无 NNN 前缀，或已是目标名），跳过。
# 失败不中断，最后 exit 0。

set -u

PROJECT_ROOT="${1:-}"

if [ -z "$PROJECT_ROOT" ]; then
  echo "用法: bash migrate-tasks-to-id-naming.sh /path/to/project" >&2
  exit 0
fi

DAG_FILE="$PROJECT_ROOT/.autopilot/project/dag.yaml"
TASKS_DIR="$PROJECT_ROOT/.autopilot/project/tasks"

if [ ! -f "$DAG_FILE" ]; then
  echo "提示: dag.yaml 不存在 ($DAG_FILE)，跳过迁移" >&2
  exit 0
fi

if [ ! -d "$TASKS_DIR" ]; then
  echo "提示: tasks/ 目录不存在 ($TASKS_DIR)，跳过迁移" >&2
  exit 0
fi

# 判断项目是否 git 仓库（决定用 git mv 还是 mv）
USE_GIT=0
if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  USE_GIT=1
fi

rename_one() {
  local src="$1"
  local dst="$2"
  if [ -e "$dst" ]; then
    echo "skip (目标已存在): $(basename "$src") → $(basename "$dst")"
    return 0
  fi
  if [ ! -e "$src" ]; then
    return 0
  fi
  if [ "$USE_GIT" -eq 1 ] && git -C "$PROJECT_ROOT" ls-files --error-unmatch "$src" >/dev/null 2>&1; then
    git -C "$PROJECT_ROOT" mv "$src" "$dst" 2>/dev/null || mv "$src" "$dst"
  else
    mv "$src" "$dst"
  fi
  echo "rename: $(basename "$src") → $(basename "$dst")"
}

# 从 dag.yaml 提取 (id, name) 对。
# 期望 dag.yaml 每个 task 块含 id 和 name 字段。兼容 title 作为 name 的回退。
# 输出两列：id<TAB>name
parse_tasks() {
  awk '
    /^[[:space:]]*-[[:space:]]*id:/ { in_task=1 }
    in_task && /[[:space:]]*id:/ {
      sub(/^[[:space:]]*-?[[:space:]]*id:[[:space:]]*/, "")
      gsub(/^["'"'"']/, ""); gsub(/["'"'"']$/, "")
      id=$0
    }
    in_task && /[[:space:]]*name:/ {
      sub(/^[[:space:]]*name:[[:space:]]*/, "")
      gsub(/^["'"'"']/, ""); gsub(/["'"'"']$/, "")
      name=$0
    }
    in_task && id!="" && name!="" {
      print id "\t" name
      id=""; name=""; in_task=0
    }
  ' "$DAG_FILE"
}

# 回退：若无 name 字段，用 title 当作反查键
parse_tasks_title_fallback() {
  awk '
    /^[[:space:]]*-[[:space:]]*id:/ { in_task=1 }
    in_task && /[[:space:]]*id:/ {
      sub(/^[[:space:]]*-?[[:space:]]*id:[[:space:]]*/, "")
      gsub(/^["'"'"']/, ""); gsub(/["'"'"']$/, "")
      id=$0
    }
    in_task && /[[:space:]]*title:/ {
      sub(/^[[:space:]]*title:[[:space:]]*/, "")
      gsub(/^["'"'"']/, ""); gsub(/["'"'"']$/, "")
      title=$0
    }
    in_task && id!="" && title!="" {
      print id "\t" title
      id=""; title=""; in_task=0
    }
  ' "$DAG_FILE"
}

brief_count=0
handoff_count=0

# 读 dag.yaml，逐 task 反查文件
TASKS=$(parse_tasks)
if [ -z "$TASKS" ]; then
  TASKS=$(parse_tasks_title_fallback)
  if [ -z "$TASKS" ]; then
    echo "提示: 未能从 dag.yaml 解析出任何 task（id + name/title），跳过" >&2
    exit 0
  fi
  echo "提示: dag.yaml 无 name 字段，回退用 title 反查" >&2
fi

while IFS=$'\t' read -r id name; do
  [ -z "$id" ] && continue
  # 幂等：若已存在 <id>.md，跳过
  if [ -e "$TASKS_DIR/$id.md" ]; then
    continue
  fi
  # 查找匹配 name 的 NNN-<name>.md 与 NNN-<name>.handoff.md
  # name 可能含特殊字符，用 find + 后缀锚定
  for src in "$TASKS_DIR"/*-"$name".md "$TASKS_DIR"/*-"$name".handoff.md; do
    [ -e "$src" ] || continue
    base=$(basename "$src")
    case "$base" in
      *.handoff.md)
        dst="$TASKS_DIR/$id.handoff.md"
        rename_one "$src" "$dst"
        handoff_count=$((handoff_count + 1))
        ;;
      *.md)
        dst="$TASKS_DIR/$id.md"
        rename_one "$src" "$dst"
        brief_count=$((brief_count + 1))
        ;;
    esac
  done
done <<EOF
$TASKS
EOF

echo "---"
echo "汇总: 重命名 brief $brief_count 个 / handoff $handoff_count 个"
exit 0
