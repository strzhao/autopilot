#!/usr/bin/env bash
# R-TA: tiered-approve 验收测试（分级自动 approve + 按需 tunnel 详审页）
# 红队测试 — 仅基于设计文档编写（黑盒），不读取蓝队本次实现
# （stop-hook.sh 本次改动段 / SKILL.md 新段 / 新 references 文件一概不读）。
#
# 设计文档 SSOT：.autopilot/runtime/requirements/20260909-优化-autopilot-最终-approv/state.md
#   ## 设计文档 D1-D5 + ### 契约规约 + ## 验收场景（场景 1-11，全 det-machine）
#
# 断言信号串 / 字段名 / 枚举 / 区块标题 / 选项字面全部逐字取自 ### 契约规约：
#   「分级未达标」 / 「AC-FIELD-INVALID」 / e2e_status(verified|partial|unverified) /
#   leftover_critical(非负整数) / 「### 端到端真实验证结论」「### 遗留问题」「### 风险」
#   「### 证据一行链」 / 批准合入 / 带遗留合入 / 回炉修复 / 补验证后合入 / twq:submit-top
#
# 行为场景（1-6/11）执行方式：构造 fixture state.md（含 tier5_status: "na" 防 §5.6 兜底噪声）
#   → 真跑 stop-hook.sh（cwd=fixture 根，stdin 注入标准 JSON）→ 断言 stdout JSON 与运行后 state.md。
# 文件锚点场景（7-10）：断言蓝队交付文件的结构锚点；场景 7.P1-P4 按任务指令构造临时
#   fixture 决策卡断结构契约（卡片本体为 QA 收口时编排器 AI 产出的运行时产物，红队阶段不存在）。
#
# 谓词覆盖清单（id = 场景.谓词号）：
#   1.P1  三条件全满足无分级信号串     1.P2 gate 清+phase=merge   1.P3 输出含 systemMessage
#   2.P1  unverified 不放行           2.P2 partial 不放行        2.P3 点名分级未达标   2.P4 retry 不变
#   3.P1  leftover>0 不放行           3.P2 点名分级未达标        3.P3 retry 不变
#   4.P1  e2e_status 缺失必 block     4.P2 leftover 缺失必 block 4.P3 retry 不变
#   5.P1  枚举外值必 block            5.P2 负数/非数字必 block   5.P3 retry 不变
#   6.P1  auto_approve=false 不放行
#   7.P1  卡片存在(fixture)           7.P2 四区块锚点(fixture)   7.P3 exit= 格式
#   7.P4  首行粗体(fixture)           7.P5 「无」规约在 qa-report-template
#   8.P1  radio 三选项锚点            8.P2 tunnel 命令指针       8.P3 按需触发语义   8.P4 降级路径
#   9.P1  SKILL.md wc -l <= 478       9.P2 skill 层锚点          9.P3 D3 三选项锚点
#   10.P1 字段登记 state-file-guide   10.P2 卡片路径登记         10.P3 qa-reviewer 反查条
#   11.P1 phase≠qa 不误判            11.P2 既有轮转不误伤
#
# no-op 杀伤力自查：
#   分级判定 no-op（旧 §5.5 无条件放行）→ 2.P1/2.P2/3.P1/6.P1 中未达标组 state 推进 merge → FAIL
#   字段校验 no-op（无 §5.7b）→ 4.P1/4.P2/5.P1/5.P2 无 block JSON → FAIL
#   卡片规约 no-op → 7.P5 模板无锚点 → FAIL；SKILL/references 未改 → 8-10 锚点缺失 → FAIL
#
# 测试质量铁律：无 if-else 宽容分支 / 无 skip / 无吞错；任一断言失败计入 FAILED，
# 末尾统一 exit 1。注：不用 set -e（grep -c 无匹配 rc=1 会误触发退出），断言由 _log_fail 兜底。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# REPO_ROOT 稳健探测：从 SCRIPT_DIR 往上找 .claude-plugin/marketplace.json
# （兼容暂存区 .autopilot/runtime/requirements/<slug>/acceptance-staging/ 与
#   合流后 plugins/autopilot/tests/acceptance/ 两种部署位置）
_find_repo_root() {
    local d="$SCRIPT_DIR"
    while [[ -n "$d" && "$d" != "/" ]]; do
        if [[ -f "$d/.claude-plugin/marketplace.json" ]]; then
            echo "$d"; return 0
        fi
        d=$(dirname "$d")
    done
    return 1
}
REPO_ROOT="$(_find_repo_root)" || {
    echo "[FAIL] R-TA: 无法定位 REPO_ROOT（缺 .claude-plugin/marketplace.json）" >&2
    exit 1
}

# ── 关键路径（既有机制路径，非本次实现）─────────────────────────────────────
STOP_HOOK="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"
SKILL_MD="$REPO_ROOT/plugins/autopilot/skills/autopilot/SKILL.md"
REF_DIR="$REPO_ROOT/plugins/autopilot/skills/autopilot/references"
STATE_GUIDE="$REF_DIR/state-file-guide.md"
QA_REPORT_TEMPLATE="$REF_DIR/qa-report-template.md"
QA_REVIEWER_PROMPT="$REF_DIR/qa-reviewer-prompt.md"
TUNNEL_GUIDE="$REF_DIR/tunnel-review-guide.md"
ART_DIR="/tmp/autopilot-artifacts"

# ── 计数器 ───────────────────────────────────────────────────────────────────
PASSED=0
FAILED=0
FAILURES=()

_log_pass() {
    local id="$1"; shift
    echo "✓ $id $*"
    PASSED=$((PASSED + 1))
}

_log_fail() {
    local id="$1"; shift
    echo "✗ $id $*" >&2
    FAILED=$((FAILED + 1))
    FAILURES+=("$id $*")
}

# ── 断言工具 ─────────────────────────────────────────────────────────────────
assert_file_exists() {
    local id="$1" f="$2"
    if [[ -f "$f" ]]; then _log_pass "$id" "file exists: $f"
    else _log_fail "$id" "file MISSING: $f"; fi
}

# 字面包含（变量 haystack）
assert_in() {
    local id="$1" hay="$2" needle="$3"
    if printf '%s' "$hay" | grep -qF -- "$needle"; then
        _log_pass "$id" "stdout contains '$needle'"
    else
        _log_fail "$id" "stdout NOT contains '$needle'（预期信号串缺失）"
    fi
}

# 字面不包含（变量 haystack）
assert_not_in() {
    local id="$1" hay="$2" needle="$3"
    if printf '%s' "$hay" | grep -qF -- "$needle"; then
        _log_fail "$id" "stdout 意外 contains '$needle'（禁现信号串泄漏）"
    else
        _log_pass "$id" "stdout NOT contains '$needle'"
    fi
}

# 正则包含（变量 haystack）
assert_regex_in() {
    local id="$1" hay="$2" pattern="$3" desc="$4"
    if printf '%s' "$hay" | grep -qE -- "$pattern"; then
        _log_pass "$id" "$desc"
    else
        _log_fail "$id" "${desc}（未匹配 /$pattern/）"
    fi
}

# 字面包含（文件）
assert_file_grep() {
    local id="$1" f="$2" needle="$3"
    if [[ ! -f "$f" ]]; then _log_fail "$id" "文件不存在: $f"; return; fi
    if grep -qF -- "$needle" "$f"; then
        _log_pass "$id" "$f contains '$needle'"
    else
        _log_fail "$id" "$f NOT contains '$needle'"
    fi
}

# 正则包含（文件）
assert_file_grepE() {
    local id="$1" f="$2" pattern="$3" desc="$4"
    if [[ ! -f "$f" ]]; then _log_fail "$id" "文件不存在: $f"; return; fi
    if grep -qE -- "$pattern" "$f"; then
        _log_pass "$id" "$desc"
    else
        _log_fail "$id" "${desc}（文件未匹配 /$pattern/: ${f}）"
    fi
}

# 正则不包含（文件）
assert_file_not_grepE() {
    local id="$1" f="$2" pattern="$3" desc="$4"
    if [[ ! -f "$f" ]]; then _log_fail "$id" "文件不存在: $f"; return; fi
    if grep -qE -- "$pattern" "$f"; then
        _log_fail "$id" "${desc}（文件意外匹配 /$pattern/: ${f}）"
    else
        _log_pass "$id" "$desc"
    fi
}

# wc -l <= 上限
assert_wc_le() {
    local id="$1" f="$2" max="$3"
    if [[ ! -f "$f" ]]; then _log_fail "$id" "文件不存在: $f"; return; fi
    local lines
    lines=$(wc -l < "$f" | tr -d ' ')
    if [[ "$lines" -le "$max" ]]; then
        _log_pass "$id" "wc -l = $lines <= $max"
    else
        _log_fail "$id" "wc -l = $lines > ${max}（净减行契约被破坏）"
    fi
}

# ── fixture 机制（照既有 auto-approve-gate-bypass.acceptance.test.sh 先例）──
FIXTURES=()

cleanup() {
    if [[ "${#FIXTURES[@]}" -gt 0 ]]; then
        rm -rf "${FIXTURES[@]}" 2>/dev/null
    fi
    [[ -n "${TA7_TMP:-}" ]] && rm -rf "$TA7_TMP" 2>/dev/null
    return 0
}
trap cleanup EXIT

# build_fixture <额外 frontmatter 行> [phase] [gate] [auto_approve]
# 统一 tier5_status: "na"（设计文档 ## 验收场景校正记录④：避免 §5.6 兜底介入噪声）
build_fixture() {
    local extra="${1-}"
    local phase="${2-qa}"
    local gate="${3-review-accept}"
    local auto="${4-true}"
    local dir
    dir="$(mktemp -d -t autopilot-ta-XXXXXX)"
    mkdir -p "$dir/.autopilot/runtime/requirements/test-task"
    echo "test-task" > "$dir/.autopilot/runtime/active.ptr"
    {
        cat <<EOF
---
active: true
phase: "$phase"
gate: "$gate"
iteration: 3
max_iterations: 30
max_retries: 3
retry_count: 0
mode: "single"
plan_mode: ""
fast_mode: true
brief_file: ""
next_task: ""
auto_approve: $auto
knowledge_extracted: ""
task_dir: "$dir/.autopilot/runtime/requirements/test-task"
session_id: tasess
started_at: "2026-09-09T00:00:00Z"
contract_required: false
html_review: false
tier5_status: "na"
EOF
        # 额外字段行（e2e_status / leftover_critical 等；空 = 字段缺失组）
        if [[ -n "$extra" ]]; then printf '%s\n' "$extra"; fi
        cat <<EOF
---

## 目标
tiered-approve fixture
EOF
    } > "$dir/.autopilot/runtime/requirements/test-task/state.md"
    FIXTURES+=("$dir")
    echo "$dir"
}

# 在 fixture 根目录真跑 stop-hook，stdout 捕获返回
run_hook() {
    local dir="$1"
    (cd "$dir" && printf '%s\n' '{"session_id":"tasess","transcript_path":"/tmp/none"}' \
        | bash "$STOP_HOOK" 2>/dev/null)
}

state_file() {
    echo "$1/.autopilot/runtime/requirements/test-task/state.md"
}

# 提取 fixture state.md 字段（去引号，照既有测试先例）
get_state_field() {
    local dir="$1" field="$2" sf
    sf="$(state_file "$dir")"
    grep -E "^${field}:" "$sf" 2>/dev/null \
        | head -1 | sed -E "s/^${field}:[[:space:]]*\"?([^\"]*)\"?$/\1/"
}

save_art() {
    local name="$1" src="$2" is_file="${3:-}"
    mkdir -p "$ART_DIR"
    if [[ "$is_file" == "file" ]]; then
        cp "$src" "$ART_DIR/$name" 2>/dev/null
    else
        printf '%s\n' "$src" > "$ART_DIR/$name" 2>/dev/null
    fi
}

# retry_count 前后相等断言
assert_retry_unchanged() {
    local id="$1" dir="$2" before="$3"
    local after
    after=$(get_state_field "$dir" retry_count)
    if [[ "$after" == "$before" ]]; then
        _log_pass "$id" "retry_count 不变（前=${before} 后=${after}）"
    else
        _log_fail "$id" "retry_count 被消耗：前=$before 后=$after"
    fi
}

# state.md 保持 qa + review-accept 断言（场景 2/3/6 共用）
assert_state_retained() {
    local id="$1" dir="$2" sf
    sf="$(state_file "$dir")"
    assert_file_grepE "$id.a" "$sf" '^phase:[[:space:]]*"qa"' \
        "$id: 运行后 state.md phase 仍为 qa（不自动推进）"
    assert_file_grepE "$id.b" "$sf" '^gate:[[:space:]]*"review-accept"' \
        "$id: 运行后 state.md gate 保持 review-accept"
}

# block JSON 三件套断言（场景 4/5 共用）
# CONTRACT_AMBIGUOUS: 谓词字面为 `"decision":"block"`；JSON 序列化空格有无不确定，
# 用容忍空白正则锚定同一契约字面（字段名 + 值逐字不变）。
assert_block_json() {
    local id="$1" out="$2"
    assert_regex_in "$id.a" "$out" "\"decision\":[[:space:]]*\"block\"" \
        "$id: stdout 为 block JSON"
}

# ─────────────────────────────────────────────────────────────────────────────
# 前置：机制文件存在（不存在 = 测试环境错误）
# 注：TUNNEL_GUIDE 不入前置——它是蓝队交付物，缺失由场景 8 断言捕获（TDD 红灯）
# ─────────────────────────────────────────────────────────────────────────────
assert_file_exists "TA-pre.1" "$STOP_HOOK"
assert_file_exists "TA-pre.2" "$SKILL_MD"
assert_file_exists "TA-pre.3" "$STATE_GUIDE"
assert_file_exists "TA-pre.4" "$QA_REPORT_TEMPLATE"
assert_file_exists "TA-pre.5" "$QA_REVIEWER_PROMPT"

echo ""
echo "════════ 行为场景 1-6 / 11：fixture 真跑 stop-hook ════════"

# ─────────────────────────────────────────────────────────────────────────────
# 场景 1：三条件全满足 → 分级自动放行进 merge
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 1：verified + leftover=0 → 分级放行 ---"

d1="$(build_fixture $'e2e_status: "verified"\nleftover_critical: "0"\nunexecuted_core_paths: "0"')"
out1="$(run_hook "$d1")"
sf1="$(state_file "$d1")"
save_art "tiered-approve-1P1.out" "$out1"
save_art "tiered-approve-1P2.out" "$sf1" file
save_art "tiered-approve-1P3.out" "$out1"

# 1.P1: stdout NOT contains 分级未达标 AND NOT contains AC-FIELD-INVALID
assert_not_in "TA-1.P1a" "$out1" "分级未达标"
assert_not_in "TA-1.P1b" "$out1" "AC-FIELD-INVALID"

# 1.P2: 放行时 gate 清除且 phase=merge
ph1="$(get_state_field "$d1" phase)"
gt1="$(get_state_field "$d1" gate)"
if [[ "$ph1" == "merge" ]]; then
    _log_pass "TA-1.P2a" "运行后 state.md phase=merge"
else
    _log_fail "TA-1.P2a" "运行后 state.md phase 应=merge，实际='$ph1'"
fi
if [[ -z "$gt1" ]]; then
    _log_pass "TA-1.P2b" "运行后 state.md gate 已清空"
else
    _log_fail "TA-1.P2b" "运行后 state.md gate 应清空，实际='$gt1'"
fi
assert_file_grepE "TA-1.P2c" "$sf1" '^phase:[[:space:]]*"?merge"?' \
    "TA-1.P2c: state.md 含 merge phase 行（谓词字面 contains phase: \"merge\"）"
assert_file_not_grepE "TA-1.P2d" "$sf1" '^gate:[[:space:]]*"review-accept"' \
    "TA-1.P2d: state.md 不再含 gate: \"review-accept\""

# 1.P3: 放行输出含用户可见提示
assert_in "TA-1.P3" "$out1" "systemMessage"

# ─────────────────────────────────────────────────────────────────────────────
# 场景 2：e2e_status ≠ verified → 不自动推进保持 gate 放行交回用户
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 2：unverified / partial → 不放行 ---"

d2a="$(build_fixture $'e2e_status: "unverified"\nleftover_critical: "0"\nunexecuted_core_paths: "0"')"
d2b="$(build_fixture $'e2e_status: "partial"\nleftover_critical: "0"\nunexecuted_core_paths: "0"')"
r2a_before="$(get_state_field "$d2a" retry_count)"
r2b_before="$(get_state_field "$d2b" retry_count)"
out2a="$(run_hook "$d2a")"
out2b="$(run_hook "$d2b")"
sf2a="$(state_file "$d2a")"
sf2b="$(state_file "$d2b")"
save_art "tiered-approve-2P1.out" "$sf2a" file
save_art "tiered-approve-2P2.out" "$sf2b" file
save_art "tiered-approve-2P3.out" "$out2a"

assert_state_retained "TA-2.P1" "$d2a"
assert_state_retained "TA-2.P2" "$d2b"
assert_in "TA-2.P3a" "$out2a" "分级未达标"
assert_in "TA-2.P3b" "$out2b" "分级未达标"
assert_retry_unchanged "TA-2.P4a" "$d2a" "$r2a_before"
assert_retry_unchanged "TA-2.P4b" "$d2b" "$r2b_before"

# ─────────────────────────────────────────────────────────────────────────────
# 场景 3：leftover_critical > 0 → 不自动推进保持 gate（verified 也不放行，AND 条件）
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 3：verified + leftover=2 → 不放行 ---"

d3="$(build_fixture $'e2e_status: "verified"\nleftover_critical: "2"\nunexecuted_core_paths: "0"')"
r3_before="$(get_state_field "$d3" retry_count)"
out3="$(run_hook "$d3")"
sf3="$(state_file "$d3")"
save_art "tiered-approve-3P1.out" "$sf3" file
save_art "tiered-approve-3P2.out" "$out3"
save_art "tiered-approve-3P3.out" "$out3"

assert_state_retained "TA-3.P1" "$d3"
assert_in "TA-3.P2" "$out3" "分级未达标"
assert_retry_unchanged "TA-3.P3" "$d3" "$r3_before"

# ─────────────────────────────────────────────────────────────────────────────
# 场景 4：字段缺失 → block 回 qa 补判不耗 retry（防放水）
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 4：字段缺失 → AC-FIELD-INVALID block ---"

d4a="$(build_fixture 'leftover_critical: "0"')"                        # 组 A：缺 e2e_status
d4b="$(build_fixture 'e2e_status: "verified"')"                          # 组 B：缺 leftover_critical
r4a_before="$(get_state_field "$d4a" retry_count)"
r4b_before="$(get_state_field "$d4b" retry_count)"
out4a="$(run_hook "$d4a")"
out4b="$(run_hook "$d4b")"
save_art "tiered-approve-4P1.out" "$out4a"
save_art "tiered-approve-4P2.out" "$out4b"
save_art "tiered-approve-4P3.out" "$out4a$out4b"

assert_block_json "TA-4.P1a" "$out4a"
assert_in "TA-4.P1b" "$out4a" "AC-FIELD-INVALID"
assert_in "TA-4.P1c" "$out4a" "e2e_status"
assert_block_json "TA-4.P2a" "$out4b"
assert_in "TA-4.P2b" "$out4b" "AC-FIELD-INVALID"
assert_in "TA-4.P2c" "$out4b" "leftover_critical"
assert_retry_unchanged "TA-4.P3a" "$d4a" "$r4a_before"
assert_retry_unchanged "TA-4.P3b" "$d4b" "$r4b_before"

# ─────────────────────────────────────────────────────────────────────────────
# 场景 5：字段非法（枚举外/负数/非数字）→ block 不耗 retry
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 5：非法值 → AC-FIELD-INVALID block ---"

d5c="$(build_fixture $'e2e_status: "failed"\nleftover_critical: "0"')"   # 组 C：枚举外
d5d="$(build_fixture $'e2e_status: "verified"\nleftover_critical: "-1"')" # 组 D：负数
d5e="$(build_fixture $'e2e_status: "verified"\nleftover_critical: "many"')" # 组 E：非数字
r5c_before="$(get_state_field "$d5c" retry_count)"
r5d_before="$(get_state_field "$d5d" retry_count)"
r5e_before="$(get_state_field "$d5e" retry_count)"
out5c="$(run_hook "$d5c")"
out5d="$(run_hook "$d5d")"
out5e="$(run_hook "$d5e")"
save_art "tiered-approve-5P1.out" "$out5c"
save_art "tiered-approve-5P2.out" "$out5d$out5e"
save_art "tiered-approve-5P3.out" "$out5c$out5d$out5e"

# 5.P1: 枚举外值必 block
assert_block_json "TA-5.P1a" "$out5c"
assert_in "TA-5.P1b" "$out5c" "AC-FIELD-INVALID"
# 5.P2: 负数与非数字 leftover_critical 必 block（契约规约 row3：非法值 block reason 含 AC-FIELD-INVALID）
assert_block_json "TA-5.P2a" "$out5d"
assert_in "TA-5.P2b" "$out5d" "AC-FIELD-INVALID"
assert_block_json "TA-5.P2c" "$out5e"
assert_in "TA-5.P2d" "$out5e" "AC-FIELD-INVALID"
# 5.P3: 非法值 block 不耗 retry_count
assert_retry_unchanged "TA-5.P3a" "$d5c" "$r5c_before"
assert_retry_unchanged "TA-5.P3b" "$d5d" "$r5d_before"
assert_retry_unchanged "TA-5.P3c" "$d5e" "$r5e_before"

# ─────────────────────────────────────────────────────────────────────────────
# 场景 6：auto_approve=false 时分级放行绝不触发（既有门禁回归保护）
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 6：auto_approve=false + verified+0 → 仍不放行 ---"

d6="$(build_fixture $'e2e_status: "verified"\nleftover_critical: "0"' qa review-accept false)"
out6="$(run_hook "$d6")"
sf6="$(state_file "$d6")"
save_art "tiered-approve-6P1.out" "$sf6" file
save_art "tiered-approve-6P1-stdout.out" "$out6"
assert_state_retained "TA-6.P1" "$d6"

# ─────────────────────────────────────────────────────────────────────────────
# 场景 11：非目标情形零扰动（回归保护）
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 11：非目标组合零扰动 ---"

# 组 F：gate=review-accept 但 phase=implement（字段齐备也不得触发新分支）
d11f="$(build_fixture $'e2e_status: "verified"\nleftover_critical: "0"' implement review-accept true)"
out11f="$(run_hook "$d11f")"
save_art "tiered-approve-11P1.out" "$out11f"
assert_not_in "TA-11.P1a" "$out11f" "AC-FIELD-INVALID"
assert_not_in "TA-11.P1b" "$out11f" "分级未达标"

# 组 G：既有 §5.5 语义场景（gate 空 + auto_approve=true + phase=qa 正常轮转）
d11g="$(build_fixture $'e2e_status: "verified"\nleftover_critical: "0"' qa "" true)"
out11g="$(run_hook "$d11g")"
save_art "tiered-approve-11P2.out" "$out11g"
assert_not_in "TA-11.P2a" "$out11g" "AC-FIELD-INVALID"
assert_not_in "TA-11.P2b" "$out11g" "分级未达标"

echo ""
echo "════════ 文件锚点场景 7-10 ════════"

# ─────────────────────────────────────────────────────────────────────────────
# 场景 7：acceptance-card.md 持久化结构完整性
# 7.P1-P4：按任务指令构造临时 fixture 决策卡断结构契约（卡片本体是 QA 收口时
#   编排器 AI 产出的运行时产物，红队阶段不存在；此处锁定契约结构可满足性）。
# 7.P5：真实断言 qa-report-template.md 已登记决策卡区块规范 + 「无」规约（no-op 杀伤点）。
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 7：acceptance-card 结构契约 ---"

TA7_TMP="$(mktemp -d -t autopilot-ta-card-XXXXXX)"
CARD="$TA7_TMP/acceptance-card.md"
cat > "$CARD" <<'EOF'
**分级验收：核心链路已实证、零关键遗留，合并即得可用交付**

### 端到端真实验证结论
核心变更链路已真实启动并观测，结果符合预期；低频边缘分支未真实触发。

### 遗留问题
- 边缘分支未实证 ｜ 影响面：低频路径 ｜ 建议：下个迭代补验证

### 风险
无

### 证据一行链
- bash tests/acceptance/run-all.sh ｜ 28/28 PASS ｜ exit=0
EOF
save_art "acceptance-card-7P1.out" "$CARD" file

assert_file_exists "TA-7.P1" "$CARD"
assert_file_grep "TA-7.P2a" "$CARD" "### 端到端真实验证结论"
assert_file_grep "TA-7.P2b" "$CARD" "### 遗留问题"
assert_file_grep "TA-7.P2c" "$CARD" "### 风险"
assert_file_grep "TA-7.P2d" "$CARD" "### 证据一行链"
assert_file_grep "TA-7.P3" "$CARD" "exit="
first_line="$(grep -m1 -v '^[[:space:]]*$' "$CARD")"
if printf '%s' "$first_line" | grep -qE '^\*\*'; then
    _log_pass "TA-7.P4" "首个非空行为粗体一句话总结行（^\\*\\*）"
else
    _log_fail "TA-7.P4" "首个非空行非粗体开头：'$first_line'"
fi

# 7.P5: 空区块写「无」规约 + 决策卡区块规范在 qa-report-template.md 登记
# CONTRACT_AMBIGUOUS: 谓词只说「空区块/「无」规约锚点」，未定引号形式；
# 断言「区块规范四标题已登记」（D5 决策卡区块规范）+ 空区块/无 规约锚点（「无」或"空区块"字样）。
assert_file_grep "TA-7.P5a" "$QA_REPORT_TEMPLATE" "### 端到端真实验证结论"
assert_file_grep "TA-7.P5b" "$QA_REPORT_TEMPLATE" "### 遗留问题"
assert_file_grep "TA-7.P5c" "$QA_REPORT_TEMPLATE" "### 风险"
assert_file_grep "TA-7.P5d" "$QA_REPORT_TEMPLATE" "### 证据一行链"
assert_file_grepE "TA-7.P5e" "$QA_REPORT_TEMPLATE" '「无」|空区块' \
    "TA-7.P5e: qa-report-template.md 含空区块写「无」规约锚点"
save_art "acceptance-card-7P5.out" "$QA_REPORT_TEMPLATE" file

# ─────────────────────────────────────────────────────────────────────────────
# 场景 8：tunnel 详审页交互组件契约（references/tunnel-review-guide.md）
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 8：tunnel-review-guide.md 契约 ---"

assert_file_exists "TA-8.P0" "$TUNNEL_GUIDE"
assert_file_grep "TA-8.P1a" "$TUNNEL_GUIDE" "批准合入"
assert_file_grep "TA-8.P1b" "$TUNNEL_GUIDE" "带遗留合入"
assert_file_grep "TA-8.P1c" "$TUNNEL_GUIDE" "回炉修复"
assert_file_grep "TA-8.P2a" "$TUNNEL_GUIDE" "tunnel deploy"
assert_file_grep "TA-8.P2b" "$TUNNEL_GUIDE" "tunnel drops results"
assert_file_grep "TA-8.P2c" "$TUNNEL_GUIDE" "twq:submit-top"
# 8.P3: 按需触发语义（谓词明示「按需 或 用户要求」二选一锚点）
assert_file_grepE "TA-8.P3" "$TUNNEL_GUIDE" '按需|用户要求' \
    "TA-8.P3: guide 含按需/用户要求触发语义锚点"
assert_file_grep "TA-8.P4" "$TUNNEL_GUIDE" "AskUserQuestion"
# 附加契约锚点（契约规约：interactive 组件 radio 三选项 + text 反馈）
assert_file_grep "TA-8.x1" "$TUNNEL_GUIDE" "interactive"
assert_file_grep "TA-8.x2" "$TUNNEL_GUIDE" "radio"
assert_file_grep "TA-8.x3" "$TUNNEL_GUIDE" "text"
save_art "tunnel-review-8P1.out" "$TUNNEL_GUIDE" file

# ─────────────────────────────────────────────────────────────────────────────
# 场景 9：SKILL.md 净减行不变量（基线 478）
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 9：SKILL.md 净减 + 锚点 ---"

assert_wc_le "TA-9.P1" "$SKILL_MD" 478
assert_file_grep "TA-9.P2a" "$SKILL_MD" "e2e_status"
assert_file_grep "TA-9.P2b" "$SKILL_MD" "acceptance-card"
assert_file_grep "TA-9.P3a" "$SKILL_MD" "补验证后合入"
assert_file_grep "TA-9.P3b" "$SKILL_MD" "回炉修复"
save_art "skill-shrink-9P1.out" "$SKILL_MD" file

# ─────────────────────────────────────────────────────────────────────────────
# 场景 10：新字段与卡片在状态规约中登记（SSOT 可发现性）
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 10：state-file-guide / qa-reviewer-prompt 登记 ---"

assert_file_grep "TA-10.P1a" "$STATE_GUIDE" "e2e_status"
assert_file_grep "TA-10.P1b" "$STATE_GUIDE" "leftover_critical"
assert_file_grep "TA-10.P1c" "$STATE_GUIDE" "verified"
assert_file_grep "TA-10.P2" "$STATE_GUIDE" "acceptance-card.md"
assert_file_grep "TA-10.P3" "$QA_REVIEWER_PROMPT" "e2e_status"
save_art "state-guide-10P1.out" "$STATE_GUIDE" file
save_art "state-guide-10P3.out" "$QA_REVIEWER_PROMPT" file

# ─────────────────────────────────────────────────────────────────────────────
# 汇总
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo " R-TA tiered-approve 汇总: PASSED=$PASSED  FAILED=$FAILED"
echo "=========================================="

if [[ $FAILED -gt 0 ]]; then
    echo ""
    echo "失败明细："
    for f in "${FAILURES[@]}"; do
        echo "   - $f"
    done
    echo ""
    echo "FAIL"
    exit 1
fi

echo "PASS"
exit 0
