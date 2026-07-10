#!/usr/bin/env bash
# migrate-tasks-to-id-naming.sh
#
# 把 .autopilot/project/tasks/ 下的任务文件重命名为 <id>.md / <id>.handoff.md
# （id 从 dag.yaml 读取）。定位源文件优先用 dag 的 brief 字段（显式文件指针），
# 回退按 name glob。治 stop-hook/create_brief 的 id 查找断裂（文件名 stem ≠ id）。
#
# 覆盖两种既有命名模式：
#   - NNN-<name>.md（name 英文，id 短，dag 无 brief 字段）→ name glob 回退
#   - NNN-<id>.md  （id 长，dag 有 brief 字段）→ brief 字段定位
#
# 用法: bash migrate-tasks-to-id-naming.sh /path/to/project
# 幂等：<id>.md 已存在则跳过。失败不中断，exit 0。

set -u

PROJECT_ROOT="${1:-}"
[ -z "$PROJECT_ROOT" ] && { echo "用法: bash $0 /path/to/project" >&2; exit 0; }

DAG_FILE="$PROJECT_ROOT/.autopilot/project/dag.yaml"
TASKS_DIR="$PROJECT_ROOT/.autopilot/project/tasks"
[ ! -f "$DAG_FILE" ] && { echo "提示: dag.yaml 不存在 ($DAG_FILE)，跳过" >&2; exit 0; }
[ ! -d "$TASKS_DIR" ] && { echo "提示: tasks/ 不存在 ($TASKS_DIR)，跳过" >&2; exit 0; }

USE_GIT=0
git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 && USE_GIT=1

rename_one() {
  local src="$1" dst="$2"
  [ -e "$dst" ] && { echo "skip (目标已存在): $(basename "$src") → $(basename "$dst")"; return 0; }
  [ ! -e "$src" ] && return 0
  if [ "$USE_GIT" -eq 1 ] && git -C "$PROJECT_ROOT" ls-files --error-unmatch "$src" >/dev/null 2>&1; then
    git -C "$PROJECT_ROOT" mv "$src" "$dst" 2>/dev/null || mv "$src" "$dst"
  else
    mv "$src" "$dst"
  fi
  echo "rename: $(basename "$src") → $(basename "$dst")"
}

# 解析 dag.yaml 每个 task 的 (id, brief, name)。brief 是显式文件指针（相对 PROJECT_ROOT）。
# 用下一个 `- id:` 作 task 边界收集完整字段，避免字段顺序（id,name,brief）导致提前 print 丢 brief。
parse_tasks() {
  awk '
    /^[[:space:]]*-[[:space:]]*id:/ {
      if (id != "") { print id "\t" brief "\t" name; id=""; brief=""; name="" }
      in_task=1
      sub(/^[[:space:]]*-?[[:space:]]*id:[[:space:]]*/, ""); gsub(/^["'"'"']/, ""); gsub(/["'"'"']$/, ""); id=$0
      next
    }
    in_task && /^[[:space:]]*brief:/ { sub(/^[[:space:]]*brief:[[:space:]]*/, ""); gsub(/^["'"'"']/, ""); gsub(/["'"'"']$/, ""); brief=$0; next }
    in_task && /^[[:space:]]*name:/ { sub(/^[[:space:]]*name:[[:space:]]*/, ""); gsub(/^["'"'"']/, ""); gsub(/["'"'"']$/, ""); name=$0; next }
    END { if (id != "") print id "\t" brief "\t" name }
  ' "$DAG_FILE"
}

# 更新 dag.yaml 的 brief 字段：old_stem.md → new_stem.md（改名后同步，治 v3.55.0 改名不更新 brief 的 bug）。
# 字面替换（index+substr，避免正则元字符），保留路径前缀格式。临时文件 + mv 跨平台。
update_dag_brief() {
  local dag_file="$1" old_stem="$2" new_stem="$3"
  [[ "$old_stem" == "$new_stem" ]] && return 0
  [[ ! -f "$dag_file" ]] && return 0
  awk -v old="$old_stem" -v new="$new_stem" '
    /^[[:space:]]*brief:/ {
      s=$0; out=""; needle=old ".md"
      while ((i=index(s,needle))>0) { out=out substr(s,1,i-1) new ".md"; s=substr(s,i+length(needle)) }
      $0=out s
    }
    { print }
  ' "$dag_file" > "$dag_file.tmp" && mv "$dag_file.tmp" "$dag_file"
}

brief_count=0; handoff_count=0
TASKS=$(parse_tasks)
[ -z "$TASKS" ] && { echo "提示: 未能从 dag.yaml 解析出 task（id + brief/name），跳过" >&2; exit 0; }

while IFS=$'\t' read -r id brief name; do
  [ -z "$id" ] && continue
  [ -e "$TASKS_DIR/$id.md" ] && continue  # 幂等
  # 定位源 brief 文件：优先 brief 字段（相对路径），回退 name glob
  src=""
  if [ -n "$brief" ]; then
    case "$brief" in /*) bpath="$brief";; *) bpath="$PROJECT_ROOT/$brief";; esac
    [ -f "$bpath" ] && src="$bpath"
  fi
  if [ -z "$src" ] && [ -n "$name" ]; then
    for f in "$TASKS_DIR"/*-"$name".md; do [ -f "$f" ] && src="$f" && break; done
  fi
  if [ -z "$src" ]; then
    echo "skip (未定位源文件): id=$id brief='$brief' name='$name'" >&2
    continue
  fi
  rename_one "$src" "$TASKS_DIR/$id.md" && brief_count=$((brief_count + 1))
  # 同步更新 dag brief 指向新文件名（治改名不更新 brief，否则新版 stop-hook 用过期 brief 会 miss）
  update_dag_brief "$DAG_FILE" "$(basename "$src" .md)" "$id"
  # handoff（同 stem）
  hsrc="${src%.md}.handoff.md"
  [ -f "$hsrc" ] && rename_one "$hsrc" "$TASKS_DIR/$id.handoff.md" && handoff_count=$((handoff_count + 1))
done <<EOF
$TASKS
EOF

echo "---"
echo "汇总: 重命名 brief $brief_count 个 / handoff $handoff_count 个"
exit 0
