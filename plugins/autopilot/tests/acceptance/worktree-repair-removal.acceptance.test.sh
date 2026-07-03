#!/usr/bin/env bash
# R_WR_REMOVAL: 删 worktree-repair 死代码 skill + 改 doctor 悬空引用 + 方案 A + 版本号 v3.49.0
# 红队测试 — 仅基于设计文档（state.md ## 契约规约 N1-N5）编写，黑盒视角
#
# 谓词映射（来自设计文档 ## 契约规约 N1-N5）：
#   N1 [det-existence]: plugins/autopilot/skills/worktree-repair/ 目录不存在
#       observe: [[ ! -d <path> ]]
#       assert:  目录已删除（删死代码 skill）
#
#   N2 [det-grep-negative]: doctor SKILL.md 不含字面字符串 `/worktree-repair`（活引用清零）
#       observe: grep -c '/worktree-repair' doctor SKILL.md
#       assert:  count == 0
#       边界:    knowledge-engineering.md 历史案例不受此约束（保留 2026-03-27 历史记录）
#
#   N3 [det-grep-positive]: doctor SKILL.md 含字面字符串 `local-config`（gitignore 检查已覆盖该产物）
#       observe: grep -qF 'local-config' doctor SKILL.md
#       assert:  count >= 1
#
#   N4 [det-version-sync]: 版本号一致 v3.49.0
#       - plugin.json "version" 字段
#       - marketplace.json autopilot 条目 "version" 字段
#       - CLAUDE.md 插件索引表 autopilot 行版本标记
#       observe: 三处分别提取版本字段
#       assert:  均等于 3.49.0
#
#   N5 [det-shrink]: doctor SKILL.md git diff 净增行数 <= 0（行内替换，零净增）
#       observe: git diff --numstat doctor SKILL.md 求 added/deleted
#       assert:  (added - deleted) <= 0  即 deleted >= added
#
# 变更背景（来自设计文档 Context）：
#   三合一：① 删 worktree-repair skill（功能=跑 worktree.mjs repair，与 bootstrap.sh SessionStart
#          自动跑的命令 100% 相同，disable-model-invocation:true + 不在 available skills = 死代码）
#          ② 改 doctor:230 指引（消除对已删 skill 的悬空引用）
#          ③ 方案 A：doctor:289 gitignore 检查从 grep -F '.autopilot/runtime/' 升级为
#            grep -E '\.autopilot/runtime/|local-config\.json'，把 local-config.json 纳入 Layer 3
#   硬约束：skill 只能减不能增、AI 强不写死正则脚本。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 双轨推导：git rev-parse 优先（自动适应 staging 深度 5 / target 深度 4），失败回退相对路径
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
    # 回退：target 路径 plugins/autopilot/tests/acceptance/ 往上 4 层 = 仓库根
    REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
fi

# 期望版本号（动态读 plugin.json，根治硬编码盲区——参照 R12 版本同步守护）
EXPECTED_VERSION=$(grep -m1 '"version"' "$REPO_ROOT/plugins/autopilot/.claude-plugin/plugin.json" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
[ -z "$EXPECTED_VERSION" ] && EXPECTED_VERSION="3.49.0"   # fallback

FAIL=0

fail() {
    echo "[FAIL] R_WR_REMOVAL: $1" >&2
    FAIL=$((FAIL + 1))
}

pass() {
    echo "[PASS] R_WR_REMOVAL: $1"
}

# 关键路径（前置存在性校验，避免后续断言因路径错位而误报）
WORKTREE_REPAIR_DIR="$REPO_ROOT/plugins/autopilot/skills/worktree-repair"
DOCTOR_SKILL="$REPO_ROOT/plugins/autopilot/skills/autopilot-doctor/SKILL.md"
PLUGIN_JSON="$REPO_ROOT/plugins/autopilot/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"

[[ -d "$REPO_ROOT/.git" ]] || { echo "[FAIL] REPO_ROOT 非 git 仓库: $REPO_ROOT" >&2; exit 1; }
[[ -f "$DOCTOR_SKILL"   ]] || fail "doctor SKILL.md 不存在: $DOCTOR_SKILL"
[[ -f "$PLUGIN_JSON"    ]] || fail "plugin.json 不存在: $PLUGIN_JSON"
[[ -f "$MARKETPLACE_JSON" ]] || fail "marketplace.json 不存在: $MARKETPLACE_JSON"
[[ -f "$CLAUDE_MD"      ]] || fail "CLAUDE.md 不存在: $CLAUDE_MD"

# ===========================================================================
# N1：plugins/autopilot/skills/worktree-repair/ 目录不存在（删死代码 skill）
# ===========================================================================
if [[ -d "$WORKTREE_REPAIR_DIR" ]]; then
    fail "N1: worktree-repair 目录仍存在: ${WORKTREE_REPAIR_DIR}（应为死代码 skill，已删除）"
else
    pass "N1: worktree-repair 目录已删除 ($WORKTREE_REPAIR_DIR)"
fi

# 同时断言 SKILL.md 也随之消失（目录被删后内部文件不应残留）
if [[ -f "$WORKTREE_REPAIR_DIR/SKILL.md" ]]; then
    fail "N1: worktree-repair/SKILL.md 仍残留（目录删除应连同 SKILL.md 一起）"
else
    pass "N1: worktree-repair/SKILL.md 不残留"
fi

# ===========================================================================
# N2：doctor SKILL.md 不含字面字符串 `/worktree-repair`（活引用清零）
# ===========================================================================
# 注意：仅检查 doctor SKILL.md，knowledge-engineering.md 历史案例不受约束（设计非目标）
if [[ -f "$DOCTOR_SKILL" ]]; then
    # grep -c 在无匹配且文件存在时返回 1 + 输出 0，用 || true 兜底
    worktree_repair_refs=$(grep -c '/worktree-repair' "$DOCTOR_SKILL" || true)
    if [[ "${worktree_repair_refs:-0}" -ne 0 ]]; then
        fail "N2: doctor SKILL.md 仍含 '/worktree-repair' 引用（找到 ${worktree_repair_refs} 处活引用，应清零）"
    else
        pass "N2: doctor SKILL.md 不含字面字符串 '/worktree-repair'（活引用清零）"
    fi
fi

# ===========================================================================
# N3：doctor SKILL.md 含字面字符串 `local-config`（gitignore 检查已覆盖该产物）
# ===========================================================================
# 设计：doctor:289 grep -F '.autopilot/runtime/' -> grep -E '\.autopilot/runtime/|local-config\.json'
#       升级后 SKILL.md 至少出现一次 local-config（方案 A 落地的字面证据）
if [[ -f "$DOCTOR_SKILL" ]]; then
    if grep -qF 'local-config' "$DOCTOR_SKILL"; then
        local_config_count=$(grep -c 'local-config' "$DOCTOR_SKILL" || true)
        pass "N3: doctor SKILL.md 含字面字符串 'local-config'（gitignore 检查覆盖该产物，${local_config_count} 处）"
    else
        fail "N3: doctor SKILL.md 缺少字面字符串 'local-config'（方案 A 未落地：doctor:289 gitignore 检查未覆盖 local-config.json）"
    fi
fi

# ===========================================================================
# N4：版本号一致 v3.49.0（plugin.json / marketplace.json / CLAUDE.md 三处）
# ===========================================================================
# N4-1：plugin.json "version" 字段
plugin_version=$(grep '"version"' "$PLUGIN_JSON" \
    | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' | head -1)
if [[ "$plugin_version" != "$EXPECTED_VERSION" ]]; then
    fail "N4-1: plugin.json version '$plugin_version' != 期望 '$EXPECTED_VERSION'"
else
    pass "N4-1: plugin.json version = $EXPECTED_VERSION"
fi

# N4-2：marketplace.json autopilot 条目 "version" 字段
# 策略：优先用 python3 严格解析（避免 awk 在多字段数组里的误匹配）
marketplace_version=$(python3 -c "
import json
data = json.load(open('$MARKETPLACE_JSON'))
plugins = data if isinstance(data, list) else data.get('plugins', [])
for p in plugins:
    if p.get('name') == 'autopilot':
        print(p.get('version', ''))
        break
" 2>/dev/null || true)

if [[ -z "$marketplace_version" ]]; then
    # 回退：awk 找到 name=autopilot 条目后提取下一个 version 字段
    marketplace_version=$(awk '
        /"name"[[:space:]]*:[[:space:]]*"autopilot"/ { found=1 }
        found && /"version"/ {
            match($0, /"version"[[:space:]]*:[[:space:]]*"([^"]+)"/, arr)
            if (arr[1] != "") { print arr[1]; found=0 }
        }
    ' "$MARKETPLACE_JSON" | head -1)
fi

if [[ -z "$marketplace_version" ]]; then
    fail "N4-2: marketplace.json 中找不到 autopilot 条目的 version 字段"
elif [[ "$marketplace_version" != "$EXPECTED_VERSION" ]]; then
    fail "N4-2: marketplace.json autopilot version '$marketplace_version' != 期望 '$EXPECTED_VERSION'"
else
    pass "N4-2: marketplace.json autopilot version = $EXPECTED_VERSION"
fi

# N4-3：CLAUDE.md 插件索引表 autopilot 行版本标记
# 表格行格式: | [autopilot](plugins/autopilot/) | v3.49.0 | Skill + Hook | ...
# 同行既要含 autopilot 又要含 v3.49.0 / 3.49.0
claude_md_autopilot_row=""
while IFS= read -r line; do
    if echo "$line" | grep -qE '\[autopilot\]'; then
        claude_md_autopilot_row="$line"
        break
    fi
done < "$CLAUDE_MD"

if [[ -z "$claude_md_autopilot_row" ]]; then
    fail "N4-3: CLAUDE.md 插件索引表找不到 autopilot 行"
elif ! echo "$claude_md_autopilot_row" | grep -qE "v${EXPECTED_VERSION}|${EXPECTED_VERSION}"; then
    fail "N4-3: CLAUDE.md autopilot 行版本未匹配 '$EXPECTED_VERSION'（行内容: $(echo "$claude_md_autopilot_row" | head -c 80)...）"
else
    pass "N4-3: CLAUDE.md 插件索引表 autopilot 行版本 = v$EXPECTED_VERSION"
fi

# N4-4（汇总）：三处版本完全一致
if [[ "$plugin_version" == "$EXPECTED_VERSION" \
   && "$marketplace_version" == "$EXPECTED_VERSION" \
   && -n "$claude_md_autopilot_row" ]] \
   && echo "$claude_md_autopilot_row" | grep -qE "v${EXPECTED_VERSION}|${EXPECTED_VERSION}"; then
    pass "N4-4: plugin.json / marketplace.json / CLAUDE.md 三处版本一致 = $EXPECTED_VERSION"
else
    fail "N4-4: 版本号三方不一致（plugin=$plugin_version marketplace=$marketplace_version claude_md_row=$(echo "$claude_md_autopilot_row" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)）"
fi

# ===========================================================================
# N5：doctor SKILL.md git diff 净增行数 <= 0（行内替换，零净增）
# ===========================================================================
# 设计：doctor:230 与 doctor:289 均为「行内替换」（旧字串 -> 新字串），不增删行。
#       断言 git diff --numstat 的 added - deleted <= 0。
# 策略：优先工作区 vs HEAD；若全空（已 commit）回退 HEAD~1。
compute_doctor_numstat() {
    local diff_ref="${1:-HEAD}"
    local added=0 deleted=0 out line a d

    out=$(git -C "$REPO_ROOT" diff --numstat "$diff_ref" -- "${DOCTOR_SKILL#$REPO_ROOT/}" 2>/dev/null || true)
    while IFS=$'\t' read -r a d _path; do
        [[ -z "$a" && -z "$d" ]] && continue
        [[ "$a" == "-" || "$d" == "-" ]] && continue
        if [[ "$a" =~ ^[0-9]+$ ]]; then added=$((added + a)); fi
        if [[ "$d" =~ ^[0-9]+$ ]]; then deleted=$((deleted + d)); fi
    done <<< "$out"
    echo "$added $deleted"
}

NUMSTAT_HEAD=$(compute_doctor_numstat "HEAD")
DOC_ADDED=${NUMSTAT_HEAD% *}
DOC_DELETED=${NUMSTAT_HEAD#* }
DIFF_DESC="HEAD (working tree, uncommitted)"

if [[ "${DOC_ADDED:-0}" -eq 0 && "${DOC_DELETED:-0}" -eq 0 ]]; then
    NUMSTAT_HEAD1=$(compute_doctor_numstat "HEAD~1")
    DOC_ADDED=${NUMSTAT_HEAD1% *}
    DOC_DELETED=${NUMSTAT_HEAD1#* }
    DIFF_DESC="HEAD~1 (committed, fallback diff)"
fi

pass "N5: doctor SKILL.md numstat [$DIFF_DESC]: added=$DOC_ADDED deleted=$DOC_DELETED"

# 核心断言：净增 <= 0，即 added - deleted <= 0
NET=$((DOC_ADDED - DOC_DELETED))
if [[ "$NET" -gt 0 ]]; then
    fail "N5: doctor SKILL.md 净增行数 = ${NET} > 0（added=${DOC_ADDED} > deleted=${DOC_DELETED}），违反「skill 只能减不能增」硬约束"
else
    pass "N5: doctor SKILL.md 净增行数 = $NET <= 0（行内替换零净增，符合 skill 减法不变量）"
fi

# ===========================================================================
# 汇总
# ===========================================================================
if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "[FAIL] R_WR_REMOVAL — 共 $FAIL 处契约违反（N1-N5）" >&2
    exit 1
fi

echo ""
echo "[OK ] R_WR_REMOVAL worktree-repair-removal — N1-N5 全部契约通过"
exit 0
