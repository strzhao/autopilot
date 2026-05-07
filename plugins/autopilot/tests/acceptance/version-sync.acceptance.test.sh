#!/usr/bin/env bash
# R8: 验证版本号同步：plugin.json / marketplace.json / CLAUDE.md 均为 v3.17.0
# 红队测试 — 仅基于设计文档编写，不读取蓝队实现
#
# 设计文档要求（改动点 7）：
#   - plugin.json: 3.16.0 → 3.17.0
#   - marketplace.json: autopilot 条目同步
#   - CLAUDE.md 插件索引表 autopilot 行同步
#   - plugins/autopilot/README.md 顶部加 v3.17.0 一句话变更说明
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

PLUGIN_JSON="$REPO_ROOT/plugins/autopilot/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
AUTOPILOT_README="$REPO_ROOT/plugins/autopilot/README.md"

TARGET_VERSION="3.17.1"

fail() {
    echo "[FAIL] R8: $1" >&2
    exit 1
}

pass() {
    echo "[PASS] R8: $1"
}

# ── 断言 1：plugin.json 版本为 3.17.0 ───────────────────────────────────────
[[ -f "$PLUGIN_JSON" ]] || fail "plugin.json 不存在: $PLUGIN_JSON"

plugin_version=$(grep '"version"' "$PLUGIN_JSON" | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)
if [[ "$plugin_version" != "$TARGET_VERSION" ]]; then
    fail "plugin.json 版本 '$plugin_version' != 期望 '$TARGET_VERSION'"
fi
pass "plugin.json 版本 = $TARGET_VERSION"

# ── 断言 2：marketplace.json autopilot 条目版本为 3.17.0 ─────────────────────
[[ -f "$MARKETPLACE_JSON" ]] || fail "marketplace.json 不存在: $MARKETPLACE_JSON"

# 策略：找到 autopilot name 的条目，提取其 version 字段
# marketplace.json 是 JSON 数组，条目包含 "name": "autopilot"
marketplace_version=$(awk '
    /"name"[[:space:]]*:[[:space:]]*"autopilot"/ { found=1 }
    found && /"version"/ {
        match($0, /"version"[[:space:]]*:[[:space:]]*"([^"]+)"/, arr)
        if (arr[1] != "") { print arr[1]; found=0 }
    }
' "$MARKETPLACE_JSON")

# 兼容 awk match 不支持 POSIX 的情况，回退到 python/grep 方案
if [[ -z "$marketplace_version" ]]; then
    marketplace_version=$(python3 -c "
import json, sys
data = json.load(open('$MARKETPLACE_JSON'))
plugins = data if isinstance(data, list) else data.get('plugins', [])
for p in plugins:
    if p.get('name') == 'autopilot':
        print(p.get('version', ''))
        break
" 2>/dev/null || true)
fi

if [[ -z "$marketplace_version" ]]; then
    fail "marketplace.json 中找不到 autopilot 条目的 version 字段"
fi
if [[ "$marketplace_version" != "$TARGET_VERSION" ]]; then
    fail "marketplace.json autopilot 版本 '$marketplace_version' != 期望 '$TARGET_VERSION'"
fi
pass "marketplace.json autopilot 版本 = $TARGET_VERSION"

# ── 断言 3：CLAUDE.md 插件索引表中 autopilot 行版本为 v3.17.0 ────────────────
[[ -f "$CLAUDE_MD" ]] || fail "CLAUDE.md 不存在: $CLAUDE_MD"

# 设计文档：CLAUDE.md 插件索引表有 autopilot 行，版本列含 v3.17.0
# 表格行格式: | [autopilot](...) | v3.17.0 | ...
if ! grep -E "autopilot" "$CLAUDE_MD" | grep -qE "v${TARGET_VERSION}|${TARGET_VERSION}"; then
    fail "CLAUDE.md 插件索引表中 autopilot 行未找到版本 v${TARGET_VERSION}（设计要求同步更新插件索引）"
fi
pass "CLAUDE.md 插件索引表 autopilot 行版本 = v${TARGET_VERSION}"

# ── 断言 4：plugin.json、marketplace.json、CLAUDE.md 三处版本一致 ─────────────
# 额外确认三处完全一致（防止只改了部分）
versions_consistent=1
if [[ "$plugin_version" != "$marketplace_version" ]]; then
    versions_consistent=0
    echo "  plugin.json: $plugin_version" >&2
    echo "  marketplace.json: $marketplace_version" >&2
fi
if [[ $versions_consistent -eq 0 ]]; then
    fail "plugin.json 与 marketplace.json 版本不一致（应全部为 ${TARGET_VERSION}）"
fi
pass "plugin.json 与 marketplace.json 版本一致（${TARGET_VERSION}）"

# ── 断言 5：autopilot README.md 顶部含 v3.17.0 变更说明 ─────────────────────
[[ -f "$AUTOPILOT_README" ]] || fail "autopilot README.md 不存在: $AUTOPILOT_README"

# 设计文档: "README.md 顶部加 v3.17.0 一句话变更说明"
# 检查 README.md 前 30 行中存在 v3.17.0 或 3.17.0
readme_head=$(head -30 "$AUTOPILOT_README")
if ! echo "$readme_head" | grep -qE "v${TARGET_VERSION}|${TARGET_VERSION}"; then
    fail "autopilot README.md 顶部（前 30 行）未找到 v${TARGET_VERSION} 变更说明（设计要求顶部新增一句话说明）"
fi
pass "autopilot README.md 顶部包含 v${TARGET_VERSION} 变更说明"

# ── 断言 6：版本格式合法（语义版本 x.y.z）────────────────────────────────────
if ! echo "$plugin_version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    fail "plugin.json 版本 '$plugin_version' 不符合语义版本格式 x.y.z"
fi
pass "版本号格式合法（语义版本 ${plugin_version}）"

# ── 断言 7：版本号确实比上一版（3.16.0）更高 ─────────────────────────────────
prev_version="3.16.0"
# 简单比较：提取 minor 版本号
prev_minor=$(echo "$prev_version" | cut -d. -f2)
curr_minor=$(echo "$plugin_version" | cut -d. -f2)
prev_major=$(echo "$prev_version" | cut -d. -f1)
curr_major=$(echo "$plugin_version" | cut -d. -f1)
prev_patch=$(echo "$prev_version" | cut -d. -f3)
curr_patch=$(echo "$plugin_version" | cut -d. -f3)

is_greater=0
if [[ "$curr_major" -gt "$prev_major" ]]; then
    is_greater=1
elif [[ "$curr_major" -eq "$prev_major" ]] && [[ "$curr_minor" -gt "$prev_minor" ]]; then
    is_greater=1
elif [[ "$curr_major" -eq "$prev_major" ]] && [[ "$curr_minor" -eq "$prev_minor" ]] && [[ "$curr_patch" -gt "$prev_patch" ]]; then
    is_greater=1
fi

if [[ $is_greater -eq 0 ]]; then
    fail "版本 $plugin_version 不高于上一版 ${prev_version}（设计要求从 3.16.0 升级到 3.17.0）"
fi
pass "版本 $plugin_version > $prev_version — 版本升级方向正确"

echo "[OK ] R8 version-sync — 全部断言通过"
exit 0
