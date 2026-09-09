#!/usr/bin/env bash
# R-ES: execution-surface 验收测试（真实验收执行面闭环 v3.69.0）
# 红队测试 — 仅基于设计文档编写（黑盒），不读取蓝队本次实现
# （stop-hook.sh 本次改动段 / SKILL.md 新段 / 4 个 references 本次改动部分一概不读）。
#
# 设计文档 SSOT：.autopilot/runtime/requirements/20260909-开始实现/state.md
#   ## 设计文档 D1-D6 + ### 契约规约 + ## 验收场景（场景 1-16，15 det-machine + 1 real-process）
#
# 断言信号串 / 字段名 / 锚点字面全部逐字取自 ### 契约规约 与 ## 验收场景 assert 字段：
#   「分级未达标」 / 「AC-FIELD-INVALID」 / unexecuted_core_paths(非负整数) /
#   「无可执行链路」 / 「已执行」「未执行」「链路」「核心」「理由」 / real-process / 「至少 1 条」 /
#   Config + 禁 / 未执行 + Critical + 一致性 / 文档型交付物 / 非负整数 / partial /
#   首次交付冒烟 / tunnel deploy / tunnel drops results / tunnel rm / artifact
#
# 行为场景（1-4/6.P1/11-15）执行方式：构造 fixture state.md（四字段显式写全，
#   tier5_status: "na" 防 §5.6 兜底噪声——本测试不依赖 build_fixture 默认值，缺字段场景
#   显式省略该键）→ 真跑 stop-hook.sh（cwd=fixture 根，stdin 注入标准 JSON）→
#   断言 stdout JSON 与运行后 state.md。
# 文件锚点场景（5.P2/6.P2/7-10/13.P2）：断言蓝队交付 references 的结构锚点（TDD 红灯）。
# 场景 16（real-process 真跑）：构造样例 review md（含「验收决策卡」标题 + interactive
#   radio 组件 + twq:submit-top 注释锚点）→ 真跑 tunnel deploy → curl 公网可达性 →
#   tunnel drops results → tunnel rm → tunnel list 清理确认；trap 兜底清理不留公网垃圾。
#   tunnel CLI 不可用时输出 SKIP 标记并计 FAIL（环境问题如实报告，不许静默通过）。
#
# 谓词覆盖清单（id = 场景.谓词号）：
#   1.P1  四字段达标无信号串            1.P2 gate 清+phase=merge   1.P3 retry 不变
#   2.P1  unexecuted>0 不放行           2.P2 点名分级未达标        2.P3 retry 不变
#   3.P1  第三字段缺失必 block           3.P2 retry 不变
#   4.P1  三种非法值一律 block           4.P2 非法值不得当 0 放行
#   5.P1  清单行三段格式锚点             5.P2 降级行内留理由锚点
#   6.P1  纯文档达标组合正常放行         6.P2 豁免行字面锚点
#   7.P1  real-process + 至少 1 条       7.P2 Config + 禁
#   8.P1  未执行+Critical+一致性         8.P2 文档型交付物面
#   9.P1  字段语义+非负整数登记          9.P2 partial+未执行硬判据
#   10.P1 冒烟段三步命令字面             10.P2 artifact 留痕锚点
#   11.P1 非目标组合零信号泄漏           11.P2 gate/retry 保持原值
#   12.P1 旧字段未达标仍卡（不替代）
#   13.P1 矛盾组合拒绝推进               13.P2 反查 Critical+一致性锚点
#   14.P1 phase≠qa 校验不误触发
#   15.P1 两路径 stdout 均恰一个 JSON 对象
#   16.P1 deploy 公网可达+内容正确       16.P2 drops results 可解析 16.P3 rm 后 list 无 slug
#
# no-op 杀伤力自查：
#   分级第三∧ no-op（§5.5 仍三条件）→ 2.P1/13.P1 state 推进 merge → FAIL
#   第三字段校验 no-op（无 §5.7b 扩展）→ 3.P1/4.P1 无 block JSON → FAIL
#   模板未升级执行面清单 → 5/6.P2 锚点缺失 → FAIL
#   scenario-generator/qa-reviewer/state-file-guide/tunnel-guide 未改 → 7-10/9.P2/13.P2 FAIL
#   校验/分级路径多发 JSON → 15.P1 json.loads 解析失败 → FAIL
#   tunnel 冒烟未真跑 → 16.P1 部署不可达 / 16.P3 list 仍含 slug → FAIL（real-process 不可伪造）
#
# 测试质量铁律：无 skip / 无吞错 / 无宽容分支（场景 16 的 tunnel 不可用按规则计 FAIL）；
#   任一断言失败计入 FAILED，末尾统一 exit 1。注：不用 set -e（grep -c 无匹配 rc=1 会
#   误触发退出），断言由 _log_fail 兜底。
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
    echo "[FAIL] R-ES: 无法定位 REPO_ROOT（缺 .claude-plugin/marketplace.json）" >&2
    exit 1
}

# ── 关键路径（既有机制路径，非本次实现）─────────────────────────────────────
STOP_HOOK="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"
REF_DIR="$REPO_ROOT/plugins/autopilot/skills/autopilot/references"
STATE_GUIDE="$REF_DIR/state-file-guide.md"
QA_REPORT_TEMPLATE="$REF_DIR/qa-report-template.md"
QA_REVIEWER_PROMPT="$REF_DIR/qa-reviewer-prompt.md"
SCENARIO_GENERATOR_PROMPT="$REF_DIR/scenario-generator-prompt.md"
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

# ── 断言工具（照 tiered-approve 既有先例）────────────────────────────────────
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

# ── fixture 机制（照 tiered-approve 先例；四字段由调用方显式传全）────────────
FIXTURES=()

cleanup() {
    if [[ "${#FIXTURES[@]}" -gt 0 ]]; then
        rm -rf "${FIXTURES[@]}" 2>/dev/null
    fi
    [[ -n "${ES16_TMP:-}" ]] && rm -rf "$ES16_TMP" 2>/dev/null
    # 场景 16 兜底清理：部署成功但后续断言失败退出时，不留公网垃圾
    if [[ "${ES16_DEPLOYED:-0}" == "1" && -n "${ES16_SLUG:-}" ]]; then
        tunnel rm "$ES16_SLUG" >/dev/null 2>&1
    fi
    return 0
}
trap cleanup EXIT

# build_fixture <额外 frontmatter 行> [phase] [gate] [auto_approve]
# tier5_status: "na" 显式写死（不依赖默认值）；e2e_status / leftover_critical /
#   unexecuted_core_paths 三字段由调用方经 extra 显式传入（缺字段场景显式省略该键）。
build_fixture() {
    local extra="${1-}"
    local phase="${2-qa}"
    local gate="${3-review-accept}"
    local auto="${4-true}"
    local dir
    dir="$(mktemp -d -t autopilot-es-XXXXXX)"
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
        # 额外字段行（e2e_status / leftover_critical / unexecuted_core_paths；空 = 全缺组）
        if [[ -n "$extra" ]]; then printf '%s\n' "$extra"; fi
        cat <<EOF
---

## 目标
execution-surface fixture
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
        _log_fail "$id" "retry_count 被消耗：前=${before} 后=${after}"
    fi
}

# state.md 保持 qa + review-accept 断言（场景 2/12/13 共用）
assert_state_retained() {
    local id="$1" dir="$2" sf
    sf="$(state_file "$dir")"
    assert_file_grepE "$id.a" "$sf" '^phase:[[:space:]]*"qa"' \
        "$id: 运行后 state.md phase 仍为 qa（不自动推进）"
    assert_file_grepE "$id.b" "$sf" '^gate:[[:space:]]*"review-accept"' \
        "$id: 运行后 state.md gate 保持 review-accept"
}

# block JSON 断言
# CONTRACT_AMBIGUOUS: 谓词字面为 `"decision":"block"`；JSON 序列化空格有无不确定，
# 用容忍空白正则锚定同一契约字面（字段名 + 值逐字不变）。
assert_block_json() {
    local id="$1" out="$2"
    assert_regex_in "$id" "$out" "\"decision\":[[:space:]]*\"block\"" \
        "$id: stdout 为 block JSON"
}

# ─────────────────────────────────────────────────────────────────────────────
# 前置：机制文件存在（不存在 = 测试环境错误）
# 注：5 个蓝队交付 references 不入前置——缺失由场景 5-10 断言捕获（TDD 红灯）
# ─────────────────────────────────────────────────────────────────────────────
assert_file_exists "ES-pre.1" "$STOP_HOOK"

echo ""
echo "════════ 行为场景 1-4 / 6.P1 / 11-15：fixture 真跑 stop-hook ════════"

# ─────────────────────────────────────────────────────────────────────────────
# 场景 1：四字段全达标 → 分级自动推进清 gate 进 merge
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 1：四字段全达标 → 自动推进 ---"

d1="$(build_fixture $'e2e_status: "verified"\nleftover_critical: "0"\nunexecuted_core_paths: "0"')"
r1_before="$(get_state_field "$d1" retry_count)"
out1="$(run_hook "$d1")"
sf1="$(state_file "$d1")"
save_art "exec-surface-1P1.out" "$out1"
save_art "exec-surface-1P2.out" "$sf1" file
save_art "exec-surface-1P3.out" "$out1"

# 1.P1: stdout NOT contains 分级未达标 AND NOT contains AC-FIELD-INVALID
assert_not_in "ES-1.P1a" "$out1" "分级未达标"
assert_not_in "ES-1.P1b" "$out1" "AC-FIELD-INVALID"

# 1.P2: 运行后 state.md contains phase: "merge" AND NOT gate: "review-accept"
assert_file_grepE "ES-1.P2a" "$sf1" '^phase:[[:space:]]*"?merge"?' \
    "ES-1.P2a: state.md contains phase: \"merge\"（自动推进进 merge）"
assert_file_not_grepE "ES-1.P2b" "$sf1" '^gate:[[:space:]]*"review-accept"' \
    "ES-1.P2b: state.md NOT contains gate: \"review-accept\"（gate 已清）"

# 1.P3: retry_count(后) == retry_count(前)
assert_retry_unchanged "ES-1.P3" "$d1" "$r1_before"

# ─────────────────────────────────────────────────────────────────────────────
# 场景 2：unexecuted_core_paths>0 → 不自动放行保持 gate 交回用户
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 2：unexecuted_core_paths=2 → 分级卡点 ---"

d2="$(build_fixture $'e2e_status: "verified"\nleftover_critical: "0"\nunexecuted_core_paths: "2"')"
r2_before="$(get_state_field "$d2" retry_count)"
out2="$(run_hook "$d2")"
sf2="$(state_file "$d2")"
save_art "exec-surface-2P1.out" "$sf2" file
save_art "exec-surface-2P2.out" "$out2"
save_art "exec-surface-2P3.out" "$out2"

# 2.P1: 运行后 state.md contains phase: "qa" AND gate: "review-accept"
assert_state_retained "ES-2.P1" "$d2"
# 2.P2: stdout contains 分级未达标
assert_in "ES-2.P2" "$out2" "分级未达标"
# 2.P3: retry_count 不变
assert_retry_unchanged "ES-2.P3" "$d2" "$r2_before"

# ─────────────────────────────────────────────────────────────────────────────
# 场景 3：第三字段缺失 → AC-FIELD-INVALID block 回 qa 不耗 retry
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 3：unexecuted_core_paths 缺失 → block ---"

d3="$(build_fixture $'e2e_status: "verified"\nleftover_critical: "0"')"
r3_before="$(get_state_field "$d3" retry_count)"
out3="$(run_hook "$d3")"
save_art "exec-surface-3P1.out" "$out3"
save_art "exec-surface-3P2.out" "$out3"

# 3.P1: stdout contains "decision":"block" AND AC-FIELD-INVALID AND unexecuted_core_paths
assert_block_json "ES-3.P1a" "$out3"
assert_in "ES-3.P1b" "$out3" "AC-FIELD-INVALID"
assert_in "ES-3.P1c" "$out3" "unexecuted_core_paths"
# 3.P2: retry_count 不变
assert_retry_unchanged "ES-3.P2" "$d3" "$r3_before"

# ─────────────────────────────────────────────────────────────────────────────
# 场景 4：第三字段非法值（负数/非十进制/非数字）→ 同路径 block 绝不当 0 放行
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 4：非法值 -1 / 0x2 / abc → block ---"

d4a="$(build_fixture $'e2e_status: "verified"\nleftover_critical: "0"\nunexecuted_core_paths: "-1"')"
d4b="$(build_fixture $'e2e_status: "verified"\nleftover_critical: "0"\nunexecuted_core_paths: "0x2"')"
d4c="$(build_fixture $'e2e_status: "verified"\nleftover_critical: "0"\nunexecuted_core_paths: "abc"')"
out4a="$(run_hook "$d4a")"
out4b="$(run_hook "$d4b")"
out4c="$(run_hook "$d4c")"
sf4a="$(state_file "$d4a")"
sf4b="$(state_file "$d4b")"
sf4c="$(state_file "$d4c")"
save_art "exec-surface-4P1.out" "$out4a$out4b$out4c"
save_art "exec-surface-4P2.out" "$sf4a$sf4b$sf4c" file

# 4.P1: 三份均 contains "decision":"block" AND AC-FIELD-INVALID
assert_block_json "ES-4.P1a" "$out4a"
assert_in "ES-4.P1b" "$out4a" "AC-FIELD-INVALID"
assert_block_json "ES-4.P1c" "$out4b"
assert_in "ES-4.P1d" "$out4b" "AC-FIELD-INVALID"
assert_block_json "ES-4.P1e" "$out4c"
assert_in "ES-4.P1f" "$out4c" "AC-FIELD-INVALID"

# 4.P2: 三份运行后 state.md 均 NOT contains phase: "merge"（绝不当作 0 放行）
assert_file_not_grepE "ES-4.P2a" "$sf4a" '^phase:[[:space:]]*"merge"' \
    "ES-4.P2a: -1 组未放行进 merge"
assert_file_not_grepE "ES-4.P2b" "$sf4b" '^phase:[[:space:]]*"merge"' \
    "ES-4.P2b: 0x2 组未放行进 merge"
assert_file_not_grepE "ES-4.P2c" "$sf4c" '^phase:[[:space:]]*"merge"' \
    "ES-4.P2c: abc 组未放行进 merge"

# ─────────────────────────────────────────────────────────────────────────────
# 场景 5：决策卡执行面清单结构锚点（模板层）
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 5：qa-report-template 执行面清单锚点 ---"

# 5.P1: contains 已执行 AND 未执行 AND 链路
assert_file_grep "ES-5.P1a" "$QA_REPORT_TEMPLATE" "已执行"
assert_file_grep "ES-5.P1b" "$QA_REPORT_TEMPLATE" "未执行"
assert_file_grep "ES-5.P1c" "$QA_REPORT_TEMPLATE" "链路"
# 5.P2: contains 核心 AND 理由（非核心降级行内留理由规约）
assert_file_grep "ES-5.P2a" "$QA_REPORT_TEMPLATE" "核心"
assert_file_grep "ES-5.P2b" "$QA_REPORT_TEMPLATE" "理由"
save_art "exec-surface-5P1.out" "$QA_REPORT_TEMPLATE" file
save_art "exec-surface-5P2.out" "$QA_REPORT_TEMPLATE" file

# ─────────────────────────────────────────────────────────────────────────────
# 场景 6：纯文档任务「无可执行链路」豁免——verified 可达不误伤
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 6：纯文档豁免 ---"

# 6.P1: 场景 1 全字段达标组合（独立 fixture）真跑 → phase=merge
d6="$(build_fixture $'e2e_status: "verified"\nleftover_critical: "0"\nunexecuted_core_paths: "0"')"
run_hook "$d6" >/dev/null
sf6="$(state_file "$d6")"
save_art "exec-surface-6P1.out" "$sf6" file
assert_file_grepE "ES-6.P1" "$sf6" '^phase:[[:space:]]*"?merge"?' \
    "ES-6.P1: 纯文档达标组合运行后 state.md contains phase: \"merge\"（豁免不设卡）"
# 6.P2: qa-report-template.md contains 无可执行链路
assert_file_grep "ES-6.P2" "$QA_REPORT_TEMPLATE" "无可执行链路"

# ─────────────────────────────────────────────────────────────────────────────
# 场景 7：scenario-generator 强制 real-process 规则锚点
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 7：scenario-generator real-process 强制规则 ---"

# 7.P1: contains real-process AND 至少 1 条
assert_file_grep "ES-7.P1a" "$SCENARIO_GENERATOR_PROMPT" "real-process"
assert_file_grep "ES-7.P1b" "$SCENARIO_GENERATOR_PROMPT" "至少 1 条"
# 7.P2: contains Config AND 禁（禁全 Config 锚点）
assert_file_grep "ES-7.P2a" "$SCENARIO_GENERATOR_PROMPT" "Config"
assert_file_grep "ES-7.P2b" "$SCENARIO_GENERATOR_PROMPT" "禁"
save_art "exec-surface-7P1.out" "$SCENARIO_GENERATOR_PROMPT" file
save_art "exec-surface-7P2.out" "$SCENARIO_GENERATOR_PROMPT" file

# ─────────────────────────────────────────────────────────────────────────────
# 场景 8：qa-reviewer 执行面一致性反查锚点（Critical 级）
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 8：qa-reviewer 执行面一致性反查 ---"

# 8.P1: contains 未执行 AND Critical AND 一致性
assert_file_grep "ES-8.P1a" "$QA_REVIEWER_PROMPT" "未执行"
assert_file_grep "ES-8.P1b" "$QA_REVIEWER_PROMPT" "Critical"
assert_file_grep "ES-8.P1c" "$QA_REVIEWER_PROMPT" "一致性"
# 8.P2: contains 文档型交付物
assert_file_grep "ES-8.P2" "$QA_REVIEWER_PROMPT" "文档型交付物"
save_art "exec-surface-8P1.out" "$QA_REVIEWER_PROMPT" file
save_art "exec-surface-8P2.out" "$QA_REVIEWER_PROMPT" file

# ─────────────────────────────────────────────────────────────────────────────
# 场景 9：state-file-guide 第三字段登记锚点
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 9：state-file-guide 第三字段登记 ---"

# 9.P1: contains unexecuted_core_paths AND 非负整数
assert_file_grep "ES-9.P1a" "$STATE_GUIDE" "unexecuted_core_paths"
assert_file_grep "ES-9.P1b" "$STATE_GUIDE" "非负整数"
# 9.P2: contains partial AND 未执行（verified 硬判据：未执行核心 → 最多 partial）
assert_file_grep "ES-9.P2a" "$STATE_GUIDE" "partial"
assert_file_grep "ES-9.P2b" "$STATE_GUIDE" "未执行"
save_art "exec-surface-9P1.out" "$STATE_GUIDE" file
save_art "exec-surface-9P2.out" "$STATE_GUIDE" file

# ─────────────────────────────────────────────────────────────────────────────
# 场景 10：tunnel 首次交付冒烟规约锚点
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 10：tunnel-review-guide 首次交付冒烟 ---"

# 10.P1: contains 首次交付冒烟 AND tunnel deploy AND tunnel drops results AND tunnel rm
assert_file_grep "ES-10.P1a" "$TUNNEL_GUIDE" "首次交付冒烟"
assert_file_grep "ES-10.P1b" "$TUNNEL_GUIDE" "tunnel deploy"
assert_file_grep "ES-10.P1c" "$TUNNEL_GUIDE" "tunnel drops results"
assert_file_grep "ES-10.P1d" "$TUNNEL_GUIDE" "tunnel rm"
# 10.P2: contains artifact
assert_file_grep "ES-10.P2" "$TUNNEL_GUIDE" "artifact"
save_art "exec-surface-10P1.out" "$TUNNEL_GUIDE" file
save_art "exec-surface-10P2.out" "$TUNNEL_GUIDE" file

# ─────────────────────────────────────────────────────────────────────────────
# 场景 11：回归保护——非目标组合零扰动
# ① gate 空 ② gate=review-accept ∧ phase=implement ③ auto_approve=false（均显式四字段）
# （d11g 型组合实际靠 gate 空豁免——见设计文档 Plan 审查留痕④）
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 11：非目标组合零扰动 ---"

FIELDS_ALL=$'e2e_status: "verified"\nleftover_critical: "0"\nunexecuted_core_paths: "0"'

d11a="$(build_fixture "$FIELDS_ALL" qa "" true)"               # ① gate 空
d11b="$(build_fixture "$FIELDS_ALL" implement review-accept true)"  # ② phase=implement
d11c="$(build_fixture "$FIELDS_ALL" qa review-accept false)"   # ③ auto_approve=false

g11a_before="$(get_state_field "$d11a" gate)"
g11b_before="$(get_state_field "$d11b" gate)"
g11c_before="$(get_state_field "$d11c" gate)"
r11a_before="$(get_state_field "$d11a" retry_count)"
r11b_before="$(get_state_field "$d11b" retry_count)"
r11c_before="$(get_state_field "$d11c" retry_count)"

out11a="$(run_hook "$d11a")"
out11b="$(run_hook "$d11b")"
out11c="$(run_hook "$d11c")"
g11a_after="$(get_state_field "$d11a" gate)"
g11b_after="$(get_state_field "$d11b" gate)"
g11c_after="$(get_state_field "$d11c" gate)"
save_art "exec-surface-11P1.out" "$out11a$out11b$out11c"
mkdir -p "$ART_DIR"
{
    printf 'gate ① before=%s after=%s\n' "$g11a_before" "$g11a_after"
    printf 'gate ② before=%s after=%s\n' "$g11b_before" "$g11b_after"
    printf 'gate ③ before=%s after=%s\n' "$g11c_before" "$g11c_after"
    printf 'retry ① before=%s after=%s\n' "$r11a_before" "$(get_state_field "$d11a" retry_count)"
    printf 'retry ② before=%s after=%s\n' "$r11b_before" "$(get_state_field "$d11b" retry_count)"
    printf 'retry ③ before=%s after=%s\n' "$r11c_before" "$(get_state_field "$d11c" retry_count)"
} > "$ART_DIR/exec-surface-11P2.out"

# 11.P1: 三份均 NOT contains AC-FIELD-INVALID AND NOT contains 分级未达标
assert_not_in "ES-11.P1a" "$out11a" "AC-FIELD-INVALID"
assert_not_in "ES-11.P1b" "$out11a" "分级未达标"
assert_not_in "ES-11.P1c" "$out11b" "AC-FIELD-INVALID"
assert_not_in "ES-11.P1d" "$out11b" "分级未达标"
assert_not_in "ES-11.P1e" "$out11c" "AC-FIELD-INVALID"
assert_not_in "ES-11.P1f" "$out11c" "分级未达标"

# 11.P2: gate_after == gate_before AND retry_count_after == retry_count_before（三组）
if [[ "$g11a_after" == "$g11a_before" ]]; then
    _log_pass "ES-11.P2a" "① gate 保持原值（'${g11a_before}'）"
else
    _log_fail "ES-11.P2a" "① gate 被扰动：前='${g11a_before}' 后='${g11a_after}'"
fi
if [[ "$g11b_after" == "$g11b_before" ]]; then
    _log_pass "ES-11.P2b" "② gate 保持原值（'${g11b_before}'）"
else
    _log_fail "ES-11.P2b" "② gate 被扰动：前='${g11b_before}' 后='${g11b_after}'"
fi
if [[ "$g11c_after" == "$g11c_before" ]]; then
    _log_pass "ES-11.P2c" "③ gate 保持原值（'${g11c_before}'）"
else
    _log_fail "ES-11.P2c" "③ gate 被扰动：前='${g11c_before}' 后='${g11c_after}'"
fi
assert_retry_unchanged "ES-11.P2d" "$d11a" "$r11a_before"
assert_retry_unchanged "ES-11.P2e" "$d11b" "$r11b_before"
assert_retry_unchanged "ES-11.P2f" "$d11c" "$r11c_before"

# ─────────────────────────────────────────────────────────────────────────────
# 场景 12：leftover_critical>0 组合仍卡（第三字段是追加 ∧ 非替换）
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 12：leftover_critical=1 仍卡 ---"

d12="$(build_fixture $'e2e_status: "verified"\nleftover_critical: "1"\nunexecuted_core_paths: "0"')"
run_hook "$d12" >/dev/null
sf12="$(state_file "$d12")"
save_art "exec-surface-12P1.out" "$sf12" file

# 12.P1: 运行后 state.md contains phase: "qa" AND gate: "review-accept"（新字段不替代旧字段）
assert_state_retained "ES-12.P1" "$d12"

# ─────────────────────────────────────────────────────────────────────────────
# 场景 13：verified ∧ 清单未执行核心矛盾组合 → 拒绝推进 + 反查 Critical
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 13：verified + unexecuted_core_paths=3 矛盾 ---"

d13="$(build_fixture $'e2e_status: "verified"\nleftover_critical: "0"\nunexecuted_core_paths: "3"')"
run_hook "$d13" >/dev/null
sf13="$(state_file "$d13")"
save_art "exec-surface-13P1.out" "$sf13" file

# 13.P1: 矛盾组合拒绝自动推进（state.md contains qa AND review-accept）
assert_state_retained "ES-13.P1" "$d13"
# 13.P2: qa-reviewer-prompt contains Critical AND 一致性（反查规则锚点覆盖矛盾组合）
assert_file_grep "ES-13.P2a" "$QA_REVIEWER_PROMPT" "Critical"
assert_file_grep "ES-13.P2b" "$QA_REVIEWER_PROMPT" "一致性"

# ─────────────────────────────────────────────────────────────────────────────
# 场景 14：§5.7b 仅对目标组合生效（phase≠qa 不误触发）
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 14：phase=implement 缺第三字段不误触发 ---"

d14="$(build_fixture $'e2e_status: "verified"\nleftover_critical: "0"' implement review-accept true)"
out14="$(run_hook "$d14")"
save_art "exec-surface-14P1.out" "$out14"

# 14.P1: stdout NOT contains AC-FIELD-INVALID
assert_not_in "ES-14.P1" "$out14" "AC-FIELD-INVALID"

# ─────────────────────────────────────────────────────────────────────────────
# 场景 15：单 JSON 铁律保持（校验/分级路径均单 JSON）
# 复用场景 3（校验 block 路径）与场景 2（分级未达标路径）配置，独立新 fixture
# （复用旧 fixture 目录会被首轮运行改写 gate，失去路径语义）
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 15：两路径均恰一个可解析 JSON 对象 ---"

d15a="$(build_fixture $'e2e_status: "verified"\nleftover_critical: "0"')"                                    # 场景 3 配置：校验 block
d15b="$(build_fixture $'e2e_status: "verified"\nleftover_critical: "0"\nunexecuted_core_paths: "2"')"        # 场景 2 配置：分级未达标
out15a="$(run_hook "$d15a")"
out15b="$(run_hook "$d15b")"
save_art "exec-surface-15P1.out" "$out15a$out15b"

# 15.P1: 两 fixture 均满足 合法 JSON 对象数 == 1（python3 json.loads 全文解析，
#   照 plan-review-html 既有先例；全文恰一个对象时解析成功，多发/尾部噪声即失败）
# CONTRACT_AMBIGUOUS: 谓词「合法 JSON 对象数 == 1」未规定解析器；取 python3
#   json.loads 全文严格解析为同一契约的操作化（恰一对象 ⇔ 全文可解析且为 dict）。
for pair in "a:$out15a" "b:$out15b"; do
    grp="${pair%%:*}"
    es_out="${pair#*:}"
    if printf '%s' "$es_out" | python3 -c '
import sys, json
data = json.load(sys.stdin)
sys.exit(0 if isinstance(data, dict) else 1)
' 2>/dev/null; then
        _log_pass "ES-15.P1$grp" "路径 $grp stdout 恰一个合法 JSON 对象"
    else
        _log_fail "ES-15.P1$grp" "路径 $grp stdout 非恰一个合法 JSON 对象（单 JSON 铁律破坏）"
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# 场景 16：tunnel 首次交付冒烟真跑（real-process，brainstorm 决策 10 落地）
# 执行步骤：① tunnel deploy 样例 md → ② curl 部署 URL → ③ tunnel drops results
#   → ④ tunnel rm → ⑤ tunnel list 确认清理；全链路输出留痕 artifact；trap 兜底 rm。
# tunnel CLI 不可用 → 输出 SKIP 标记并计 FAIL（环境问题如实报告，不许静默通过）。
# ─────────────────────────────────────────────────────────────────────────────
echo "--- 场景 16：tunnel 首次交付冒烟真跑 ---"

ES16_TMP=""
ES16_SLUG=""
ES16_DEPLOYED=0

if ! command -v tunnel >/dev/null 2>&1; then
    echo "SKIP: tunnel CLI 不可用（command -v tunnel 失败）——场景 16 按规则计 FAIL" >&2
    _log_fail "ES-16.env" "SKIP: tunnel CLI 不可用，real-process 冒烟无法执行（环境问题，不许静默通过）"
else
    ES16_TMP="$(mktemp -d -t autopilot-es-smoke-XXXXXX)"
    SMOKE_MD="$ES16_TMP/review-sample.md"
    ES16_SLUG="autopilot-smoke-$(date +%Y%m%d%H%M%S)"
    cat > "$SMOKE_MD" <<'EOF'
# 验收决策卡

**分级验收：核心链路已实证、零关键遗留，合并即得可用交付**

### 端到端真实验证结论
- tunnel 交付链路 ｜ 已执行 ｜ tunnel deploy + curl 200 + drops results 可读
- 本地测试链路 ｜ 已执行 ｜ bash run-all.sh 全量 PASS

单选（radio）——多选一：
```interactive
id: merge-decision
type: radio
question: 是否批准合入？
options:
  - 批准合入
  - 带遗留合入
  - 回炉修复
```

<!-- twq:submit-top -->

### 遗留问题
无

### 风险
无
EOF

    # ① tunnel deploy（真跑）
    deploy_out="$(tunnel deploy "$SMOKE_MD" --name "$ES16_SLUG" 2>&1)"
    deploy_rc=$?
    save_art "exec-surface-16-deploy.out" "${deploy_out}（rc=${deploy_rc}）"
    if [[ $deploy_rc -eq 0 ]]; then
        ES16_DEPLOYED=1
        _log_pass "ES-16.deploy" "tunnel deploy rc=0（slug=${ES16_SLUG}）"
    else
        _log_fail "ES-16.deploy" "tunnel deploy rc=${deploy_rc}（部署失败，冒烟链路断裂）"
    fi

    # 部署 URL：优先从 deploy 输出提取，回退契约字面 https://d.stringzhao.life/<slug>
    # CONTRACT_AMBIGUOUS: 谓词 driver 为 curl:<deployed-url>，URL 由 deploy 输出决定；
    #   提取失败时回退全局 CLAUDE.md 契约字面（https://d.stringzhao.life/<slug>）。
    deployed_url="$(printf '%s' "$deploy_out" | grep -oE 'https://[^[:space:]]+' | head -1)"
    if [[ -z "$deployed_url" ]]; then
        deployed_url="https://d.stringzhao.life/$ES16_SLUG"
    fi

    # ② curl 部署 URL 验证公网可达且内容正确（16.P1）
    http_code=""
    body_file="$ES16_TMP/body.html"
    for _ in 1 2 3; do
        http_code="$(curl -s -o "$body_file" -w '%{http_code}' --max-time 30 "$deployed_url" 2>/dev/null)"
        if [[ "$http_code" == "200" ]]; then
            break
        fi
        sleep 2
    done
    mkdir -p "$ART_DIR"
    {
        printf 'url=%s\nhttp_code=%s\n---body---\n' "$deployed_url" "$http_code"
        cat "$body_file" 2>/dev/null
    } > "$ART_DIR/exec-surface-16P1.out"
    if [[ "$http_code" == "200" ]]; then
        _log_pass "ES-16.P1a" "curl HTTP 200（${deployed_url}）"
    else
        _log_fail "ES-16.P1a" "部署 URL HTTP 状态=${http_code}（预期 200，公网不可达）"
    fi
    if [[ -f "$body_file" ]] && grep -qF "验收决策卡" "$body_file"; then
        _log_pass "ES-16.P1b" "页面 body contains 验收决策卡"
    else
        _log_fail "ES-16.P1b" "页面 body NOT contains 验收决策卡（内容不正确）"
    fi

    # ③ tunnel drops results 输出落 artifact（16.P2）
    drops_out="$(tunnel drops results "$ES16_SLUG" 2>&1)"
    drops_rc=$?
    save_art "exec-surface-16P2.out" "${drops_out}（rc=${drops_rc}）"
    # 谓词析取字面：contains radio（或 rc == 0）
    if printf '%s' "$drops_out" | grep -qF "radio"; then
        _log_pass "ES-16.P2" "drops results 输出 contains radio（rc=${drops_rc}）"
    elif [[ $drops_rc -eq 0 ]]; then
        _log_pass "ES-16.P2" "drops results rc=0（谓词析取「或 rc == 0」分支）"
    else
        _log_fail "ES-16.P2" "drops results 输出 NOT contains radio 且 rc=${drops_rc}（收结果通道不可解析）"
    fi

    # ④ tunnel rm 清理（真跑）
    rm_out="$(tunnel rm "$ES16_SLUG" 2>&1)"
    rm_rc=$?
    save_art "exec-surface-16-rm.out" "${rm_out}（rc=${rm_rc}）"
    if [[ $rm_rc -eq 0 ]]; then
        ES16_DEPLOYED=0
        _log_pass "ES-16.rm" "tunnel rm rc=0（资源已清理）"
    else
        _log_fail "ES-16.rm" "tunnel rm rc=${rm_rc}（清理失败）"
    fi

    # ⑤ tunnel list 确认清理（16.P3）
    list_out="$(tunnel list 2>&1)"
    save_art "exec-surface-16P3.out" "$list_out"
    if printf '%s' "$list_out" | grep -qF "$ES16_SLUG"; then
        _log_fail "ES-16.P3" "tunnel list 意外 contains ${ES16_SLUG}（清理未生效，公网垃圾残留）"
    else
        _log_pass "ES-16.P3" "tunnel list NOT contains ${ES16_SLUG}（清理确认）"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# 汇总
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo " R-ES execution-surface 汇总: PASSED=$PASSED  FAILED=$FAILED"
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
