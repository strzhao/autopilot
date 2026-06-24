#!/usr/bin/env bash
# R_SHRINK: skill md 四文件净减行硬约束（场景6）
# 红队测试 — 黑盒视角，基于设计契约（state.md 验收场景 6.P1）编写，
#            绝不读取蓝队改后的四 md 实际内容来凑断言（TDD 红灯）。
#
# 变更背景：本任务硬约束「skill md 只能精简不能增行」——合流机械操作下沉 stop-hook bash（不计 md 行数），
#           prompt 机械指令删除。场景6 守护这一约束。
#
# 谓词映射：
#   场景6.P1 [det-machine]: 改动后 red-team-prompt.md/blue-team-prompt.md/implement-phase.md/SKILL.md
#                            四文件合计净行数 <= 改动前
#   observe: git diff --numstat <四文件> 求 deleted/added
#   assert: sum(deleted) >= sum(added)
#
# 实现说明：
#   - git diff --numstat 输出三列：<added>\t<deleted>\t<path>（二进制文件为 -\t-\t<path>）
#   - 对四文件求 added/deleted 各自总和，断言 sum(deleted) >= sum(added)。
#   - 若文件未改动（numstat 无输出），added=0/deleted=0，不影响总和判定。
#   - 若文件是新增（无历史），numstat 第一列=新增行数、第二列=0；本任务四文件均为既有文件改造，
#     若出现"新增"判定（numstat 第二列 0 且第一列 >0）会被 added 累加，导致 FAIL——符合硬约束语义。
#   - stop-hook.sh 不计入（C3 明确：新增 bash 不计入 skill md 行数）。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

RED_TEAM_FILE="plugins/autopilot/skills/autopilot/references/red-team-prompt.md"
BLUE_TEAM_FILE="plugins/autopilot/skills/autopilot/references/blue-team-prompt.md"
IMPLEMENT_PHASE_FILE="plugins/autopilot/skills/autopilot/references/implement-phase.md"
SKILL_FILE="plugins/autopilot/skills/autopilot/SKILL.md"

fail() {
    echo "[FAIL] R_SHRINK: $1" >&2
    exit 1
}

pass() {
    echo "[PASS] R_SHRINK: $1"
}

# 前置：仓库根可识别为 git 仓库
[[ -d "$REPO_ROOT/.git" ]] || fail "REPO_ROOT 非 git 仓库: $REPO_ROOT（无法 git diff --numstat）"

# 四文件必须存在（相对路径用于 git diff）
for f in "$RED_TEAM_FILE" "$BLUE_TEAM_FILE" "$IMPLEMENT_PHASE_FILE" "$SKILL_FILE"; do
    [[ -f "$REPO_ROOT/$f" ]] || fail "源文件不存在: $REPO_ROOT/$f"
done

# ---------------------------------------------------------------------------
# 断言 6.1（场景6.P1，skill md 四文件净减行硬约束）：
#   改动后四文件合计净行数 <= 改动前
#   observe: git diff --numstat <四文件>
#   assert: sum(deleted) >= sum(added)
#
#   策略：
#     1. git diff --numstat 取四文件 added/deleted（工作区 vs HEAD，含未提交改动）
#     2. 累加 added/deleted（跳过二进制 - 行）
#     3. 断言 total_deleted >= total_added
#
#   注：git diff 默认对比工作区与 HEAD。若改动已 commit，numstat 返回空（added=0/deleted=0），
#       此时需用 git diff HEAD~1 --numstat 回溯。本断言优先用工作区 diff，若全空则回退到 HEAD~1。
# ---------------------------------------------------------------------------

FOUR_FILES=(
    "$RED_TEAM_FILE"
    "$BLUE_TEAM_FILE"
    "$IMPLEMENT_PHASE_FILE"
    "$SKILL_FILE"
)

compute_numstat() {
    local diff_ref="${1:-HEAD}"
    local total_added=0
    local total_deleted=0
    local numstat_output

    # git diff --numstat <ref> -- <files>：输出 added \t deleted \t path
    numstat_output=$(git -C "$REPO_ROOT" diff --numstat "$diff_ref" -- "${FOUR_FILES[@]}" 2>/dev/null || true)

    if [[ -n "$numstat_output" ]]; then
        while IFS=$'\t' read -r added deleted _path; do
            # 跳过二进制（- 表示）
            [[ "$added" == "-" || "$deleted" == "-" ]] && continue
            # 仅累加数字（防意外字符）
            if [[ "$added" =~ ^[0-9]+$ ]]; then
                total_added=$((total_added + added))
            fi
            if [[ "$deleted" =~ ^[0-9]+$ ]]; then
                total_deleted=$((total_deleted + deleted))
            fi
        done <<< "$numstat_output"
    fi

    echo "$total_added $total_deleted"
}

# 优先：工作区 vs HEAD
NUMSTAT_HEAD=$(compute_numstat "HEAD")
TOTAL_ADDED=${NUMSTAT_HEAD% *}
TOTAL_DELETED=${NUMSTAT_HEAD#* }
DIFF_REF_DESC="HEAD (working tree, uncommitted)"

# 若工作区无改动（全部已 commit），回退到 HEAD~1 vs HEAD
if [[ "${TOTAL_ADDED:-0}" -eq 0 && "${TOTAL_DELETED:-0}" -eq 0 ]]; then
    NUMSTAT_HEAD1=$(compute_numstat "HEAD~1")
    TOTAL_ADDED=${NUMSTAT_HEAD1% *}
    TOTAL_DELETED=${NUMSTAT_HEAD1#* }
    DIFF_REF_DESC="HEAD~1 (committed, fallback diff)"
fi

pass "git diff --numstat 4 md files [$DIFF_REF_DESC]: added=$TOTAL_ADDED deleted=$TOTAL_DELETED"

# 核心断言：sum(deleted) >= sum(added)
if [[ "$TOTAL_DELETED" -lt "$TOTAL_ADDED" ]]; then
    NET_INC=$((TOTAL_ADDED - TOTAL_DELETED))
    fail "scene 6.P1: skill md net growth (added=$TOTAL_ADDED > deleted=$TOTAL_DELETED), violates shrink-only constraint. net=$NET_INC lines"
fi
NET_DEC=$((TOTAL_DELETED - TOTAL_ADDED))
pass "scene 6.P1: skill md shrink constraint satisfied (deleted=$TOTAL_DELETED >= added=$TOTAL_ADDED, net=$NET_DEC lines)"

echo "[OK ] R_SHRINK skill-md-net-shrinkage — 全部断言通过"
exit 0
