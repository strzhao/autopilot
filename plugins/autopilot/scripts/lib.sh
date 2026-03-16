#!/bin/bash

# autopilot 共享函数库
# setup.sh 和 stop-hook.sh 共用的 frontmatter 操作工具

STATE_FILE=".claude/autopilot.local.md"

parse_frontmatter() {
    [[ ! -f "$STATE_FILE" ]] && { echo ""; return; }
    sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE"
}

get_field() {
    local fm; fm=$(parse_frontmatter)
    echo "$fm" | grep "^${1}:" | sed "s/${1}: *//" | sed 's/^"\(.*\)"$/\1/'
}

set_field() {
    local temp="${STATE_FILE}.tmp.$$"
    sed "s/^${1}: .*/${1}: ${2}/" "$STATE_FILE" > "$temp"
    mv "$temp" "$STATE_FILE"
}

append_changelog() {
    local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local temp="${STATE_FILE}.tmp.$$"
    awk -v entry="- [${ts}] ${1}" \
        '/^## 变更日志/ { print; getline; print entry; print; next } { print }' \
        "$STATE_FILE" > "$temp"
    mv "$temp" "$STATE_FILE"
}

now_iso() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}
