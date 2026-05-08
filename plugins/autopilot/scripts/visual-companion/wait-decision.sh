#!/usr/bin/env bash
# wait-decision.sh — 阻塞等待用户通过浏览器做出决策
#
# Usage: wait-decision.sh <state-dir> [timeout-seconds]
#
# 读取 <state-dir>/events JSONL 文件，等待包含
#   "choice":"approve" | "revise" | "abort"
# 的 JSON 行出现，将该行原样输出到 stdout，然后退出。
#
# 成功判据（Claude 解析时使用）：stdout 非空且为合法 JSON。
# 不依赖退出码（macOS tail -F 被 kill 时退出码不可预测）。
#
# 超时（默认 1800 秒）：stdout 为空，退出码 1。

set -euo pipefail

STATE_DIR="${1:?Usage: wait-decision.sh <state-dir> [timeout-seconds]}"
TIMEOUT="${2:-1800}"
EVENTS_FILE="${STATE_DIR}/events"

# 确保目录与事件文件存在
mkdir -p "$STATE_DIR"
touch "$EVENTS_FILE"

# 启动 tail -F 到后台，将输出写入临时 FIFO
FIFO="$(mktemp -t wait-decision-XXXXXX)"
rm -f "$FIFO"
mkfifo "$FIFO"

tail -F -n0 "$EVENTS_FILE" >"$FIFO" 2>/dev/null &
TAIL_PID=$!

# 清理：退出时 kill tail 并删除 FIFO
# shellcheck disable=SC2329  # 通过 trap EXIT 调用，shellcheck 无法静态检测
cleanup() {
  kill "$TAIL_PID" 2>/dev/null || true
  rm -f "$FIFO"
}
trap cleanup EXIT

# 打开 FIFO 用于读取（需要打开 fd，否则 read 阻塞等文件描述符）
exec 3<"$FIFO"

ELAPSED=0
RESULT=""

while [[ $ELAPSED -lt $TIMEOUT ]]; do
  # 非阻塞读（1 秒超时），每秒检查一次
  if IFS= read -r -t 1 line <&3; then
    # 检查是否包含合法 choice 值
    if [[ "$line" =~ \"choice\":\"(approve|revise|abort)\" ]]; then
      RESULT="$line"
      break
    fi
  fi
  ELAPSED=$((ELAPSED + 1))
done

# 关闭 fd（触发 cleanup）
exec 3<&-

if [[ -n "$RESULT" ]]; then
  echo "$RESULT"
  exit 0
else
  # 超时：stdout 为空，退出码非 0
  exit 1
fi
