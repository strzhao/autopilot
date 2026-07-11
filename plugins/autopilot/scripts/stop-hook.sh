#!/bin/bash

# autopilot Stop Hook — 阶段状态机循环引擎
# 基于 ralph-loop 的 Stop hook 模式，增加阶段状态机和审批门逻辑
#
# 行为:
#   1. 状态文件不存在 → 放行
#   2. session_id 不匹配 → 放行
#   3. gate 非空（审批门） → 发通知 + 放行（等待用户审批）
#   4. phase=done → 清理 + 放行
#   5. 超过 max_iterations → 清理 + 放行
#   6. 其他 → block + 注入阶段 prompt，继续循环

# 安全策略：Stop hook 中任何未预期的错误都应放行（exit 0），
# 只有明确需要 block 时才输出 JSON。避免 set -e 导致意外非零退出。
# 仅在直接执行模式安装：source 模式（外部测试）下不安装 trap，
# 否则函数内 `[ ] || return 1` 短路链会被 trap 拦截为 exit 0，
# 导致测试 spawnSync 拿到的退出码与函数 return 值不一致。
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap 'exit 0' ERR
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "$SCRIPT_DIR/lib.sh"

# compress_qa_report — 压缩状态文件 ## QA 报告 区域的历史轮次
#
# 行为：保留最新一轮（### 轮次 N）完整内容，将之前所有轮次压缩为单行摘要：
#   ### 轮次 N (时间) — ✅/❌ 简要
# 状态符号从该块首行（紧跟标题之后第一个非空行）的 ✅/❌ emoji 推断，
# 摘要文本截取该首行剩余内容前 60 个字符。
#
# 不影响 ## QA 报告 之外的 section（## 设计文档 / ## 变更日志 等保持不变）。
# 失败不阻断 stop-hook（调用方使用 || true 兜底）。
# 函数幂等：对已经只剩单轮 + N 行摘要的文件再次调用结果不变。
compress_qa_report() {
    local state_file="$1"
    [ -f "$state_file" ] || return 0

    local tmp="${state_file}.compressed.$$"

    awk '
        BEGIN {
            in_qa = 0          # 当前是否在 ## QA 报告 section
            round_count = 0    # 已遇到的 ### 轮次 N 总数
            buffered = 0       # 当前 round 缓冲区是否已积累内容
        }

        # 刷新缓冲：如果是最后一轮（last_round=1）保留完整；否则压缩为一行摘要
        function flush_buffer(last_round,    i, status, summary, line, header) {
            if (!buffered) return
            if (last_round) {
                print round_header
                for (i = 1; i <= buf_n; i++) print buf_lines[i]
            } else {
                status = "✅"
                summary = ""
                for (i = 1; i <= buf_n; i++) {
                    line = buf_lines[i]
                    # 跳过空行寻找首个有内容的行
                    if (line ~ /^[[:space:]]*$/) continue
                    if (index(line, "❌") > 0) status = "❌"
                    else if (index(line, "✅") > 0) status = "✅"
                    summary = line
                    break
                }
                # 摘要截断到 60 字符（按字节，足够中文 ~20 字）
                if (length(summary) > 60) summary = substr(summary, 1, 60)
                # 若 round_header 已包含 — 状态 简要 形式（之前压缩过），保留原样
                if (round_header ~ /— [✅❌]/) {
                    print round_header
                } else {
                    if (summary == "") {
                        print round_header " — " status " 简要"
                    } else {
                        # 清理 summary 中的 markdown 标记前缀（- / ### / **）
                        gsub(/^[[:space:]]*[-*#]+[[:space:]]*/, "", summary)
                        gsub(/\*\*/, "", summary)
                        # 去掉 summary 中重复的状态 emoji（避免 — ❌ ❌ ... 形式）
                        gsub(/[✅❌][[:space:]]*/, "", summary)
                        gsub(/^[[:space:]]+/, "", summary)
                        print round_header " — " status " " summary
                    }
                }
            }
            buffered = 0
            buf_n = 0
        }

        {
            line = $0

            # 检测 ## QA 报告 section 起始
            if (line ~ /^## QA 报告[[:space:]]*$/) {
                in_qa = 1
                print line
                next
            }

            # 不在 QA 报告区：照常输出
            if (!in_qa) {
                print line
                next
            }

            # 在 QA 报告区遇到下一个 ## section（不是 ###）→ 结束 QA 区
            if (line ~ /^## / && line !~ /^## QA 报告/) {
                # 刷出最后一轮（保留完整）
                flush_buffer(1)
                in_qa = 0
                print line
                next
            }

            # 在 QA 报告区遇到 ### 轮次 N
            if (line ~ /^### 轮次/) {
                # 先把上一轮按"非最后一轮"处理（压缩）
                if (buffered) flush_buffer(0)
                round_header = line
                round_count++
                buffered = 1
                buf_n = 0
                next
            }

            # 在 QA 报告区累积当前轮次内容
            if (buffered) {
                buf_n++
                buf_lines[buf_n] = line
            } else {
                # ## QA 报告 标题与首个 ### 轮次 之间的内容（说明文字等）原样输出
                print line
            }
        }

        END {
            # 文件结束时如还在 QA 区且有缓冲，flush 为最后一轮（保留完整）
            if (in_qa && buffered) flush_buffer(1)
        }
    ' "$state_file" > "$tmp" 2>/dev/null
    if mv "$tmp" "$state_file" 2>/dev/null; then :; else rm -f "$tmp"; fi
}

# has_pending_subagents — 检测主线程是否有未完成的 Agent 调用
#
# 行为：两条独立路径合并判断 —
#   路径 A（同步 Agent）：主线程（isSidechain=false）启动的 Agent tool_use 集合 S，
#       减去所有 tool_result.tool_use_id 集合 R，余项 = 同步 pending。
#   路径 B（异步 Agent，run_in_background=true）：toolUseResult.isAsync==true &&
#       status=="async_launched" 的 .agentId 集合 L，减去 queue-operation 类型
#       enqueue 中 <task-id>X</task-id> 的 X 集合 C，余项 = 异步 pending。
#       异步路径必须独立判定，因其 tool_result 在启动瞬间就回流（写有
#       "Async agent launched..." 文本），路径 A 看不到它仍在跑。
#
# v3.26.0 关键修复：
#   - 窗口 2MB → 4MB（长会话覆盖更稳）
#   - tail -c 后丢弃首行（字节边界几乎必然切在 JSON 行中间，首行半截会让 jq 报
#     "parse error: Invalid literal at line 1" 进而走错误降级，导致死循环唤醒）
#   - jq 失败兜底：grep raw tail 文本 "status":"async_launched"，存在则 fail-safe
#     返回 0（视为 pending），避免重蹈 fail-unsafe 灾难
#
# 退出码：0 = 有 pending（同步∪异步）、1 = 无 pending（含错误降级）。
has_pending_subagents() {
    local transcript="$1"
    [ -n "$transcript" ] && [ -f "$transcript" ] || return 1

    # 末尾 4MB：覆盖含大代码内容的 tool_result（单 turn 通常 < 1MB），长会话留有余地
    local raw_tail
    raw_tail=$(timeout 3 tail -c 4194304 "$transcript" 2>/dev/null) || return 1
    [ -n "$raw_tail" ] || return 1

    # 丢弃首行：tail -c 在字节边界切，首行几乎必然是半截 JSON 行（实测）。
    # 边界 case：若丢首行后为空但原始非空（极短 transcript），回退原始数据，
    # 让 jq 或 grep fail-safe 自己处理。
    local tail_data
    tail_data=$(echo "$raw_tail" | tail -n +2)
    [ -n "$tail_data" ] || tail_data="$raw_tail"

    local pending_count
    # shellcheck disable=SC2016
    pending_count=$(echo "$tail_data" | timeout 3 jq -rs '
        # 路径 A — 同步 Agent
        ([.[] | select(.isSidechain == false or .isSidechain == null)
              | .message.content[]?
              | select(.type == "tool_use" and (.name == "Agent" or .name == "Task"))
              | .id]) as $started
        |
        ([.[] | .message.content[]?
              | select(.type == "tool_result")
              | .tool_use_id]) as $finished
        |
        ($started - $finished) as $sync_pending
        |
        # 路径 B — 异步 Agent (run_in_background=true)
        ([.[] | .toolUseResult? | objects
              | select(.isAsync == true and .status == "async_launched")
              | .agentId]) as $async_launched
        |
        ([.[] | select(.type? == "queue-operation" and .operation? == "enqueue")
              | .content // ""
              | (capture("<task-id>(?<id>[^<]+)</task-id>") | .id)?
              | select(. != null)]) as $async_completed
        |
        ($async_launched - $async_completed) as $async_pending
        |
        ($sync_pending | length) + ($async_pending | length)
    ' 2>/dev/null)
    local jq_exit=$?

    # 成功路径
    if [ $jq_exit -eq 0 ] && [[ "$pending_count" =~ ^[0-9]+$ ]]; then
        if [ "$pending_count" -gt 0 ]; then
            echo "[has_pending_subagents] jq 检测出 pending=$pending_count" >&2
            return 0
        else
            return 1
        fi
    fi

    # Fail-safe 兜底（防止 jq schema 变化导致再次死循环）
    # 用 raw_tail（含首行）扫文本字面量。launched/completed 计数差 > 0 才视为 pending，
    # 避免已完成场景（两边计数相等）触发不必要的 silent block。
    local launched_count completed_count
    launched_count=$(echo "$raw_tail" | grep -c '"status":"async_launched"' 2>/dev/null || echo 0)
    completed_count=$(echo "$raw_tail" | grep -c '<status>completed</status>' 2>/dev/null || echo 0)
    # 防御非数字
    [[ "$launched_count" =~ ^[0-9]+$ ]] || launched_count=0
    [[ "$completed_count" =~ ^[0-9]+$ ]] || completed_count=0

    if [ "$launched_count" -gt "$completed_count" ]; then
        echo "[has_pending_subagents] jq 失败，fail-safe 文本检测 launched=$launched_count completed=$completed_count → pending" >&2
        return 0
    fi

    if [ $jq_exit -ne 0 ]; then
        echo "[has_pending_subagents] jq 失败且 fail-safe 文本检测无 pending (launched=$launched_count completed=$completed_count)" >&2
    fi
    return 1
}

# design_doc_written — 检测 state.md「## 设计文档」区域是否已写入实质内容
#
# 用途：§7.6 据此区分 standard design 阶段两类「无 pending 结束回合」——
#   - 接力点（brainstorm 刚完成、设计文档仍空）：应 fall through §9 自动唤醒接力写设计文档，
#     不该停住。v3.43.1 前 §7.6 一刀切放行把接力点也停住，逼用户手动「继续」（回归 bug）。
#   - 审批点（设计文档已落盘、等用户拍板）：应 §7.6 放行停住，防 §9 block 唤醒冲 implement。
#
# 信号选择：设计文档落盘对「审批用 AskUserQuestion 还是纯文本」「AskUserQuestion pending 时
#   Stop hook 是否触发」均不敏感（两类审批点设计文档都已非空），比检测未闭合 AskUserQuestion
#   鲁棒——后者前提（AskUserQuestion pending 触发 Stop hook）被官方 hooks 文档否定。
#
# 检测：awk 提取 ## 设计文档 到下一个已知 top section（实现计划/红队验收测试/QA 报告/变更日志/
#   用户反馈）的正文——不能用泛 /^## /，否则设计文档内部 ## Context / ## 契约规约 子标题会
#   误截断（实测：实质设计文档首行 ## Context 即把区域截成 0 字节）。去空行后 wc -c 统计字节。
#   初始模板（setup.sh）该区域仅占位符「(待 design 阶段填充)」(UTF-8 ~25 字节)；主 SKILL 接力
#   写入实质设计文档（数百字节以上）。阈值 80：远大于占位符、远小于真实设计文档，稳健区分。
#
# 返回：0 = 已写入实质内容（审批点）、1 = 空/仅占位符（接力点）或文件缺失。
design_doc_written() {
    local state_file="$1"
    [ -f "$state_file" ] || return 1

    local body
    body=$(awk '
        /^## 设计文档[[:space:]]*$/ { in_doc = 1; next }
        in_doc && /^## (实现计划|红队验收测试|QA 报告|变更日志|用户反馈)[[:space:]]*$/ { in_doc = 0; next }
        in_doc
    ' "$state_file" 2>/dev/null)

    local stripped n
    stripped=$(printf '%s\n' "$body" | grep -vE '^[[:space:]]*$' || true)
    n=$(printf '%s' "$stripped" | wc -c | tr -d ' ')
    [[ "$n" =~ ^[0-9]+$ ]] || n=0
    [[ "$n" -gt 80 ]]
}

# detect_smoke_eligible — 检测当前 diff 是否满足 smoke QA 条件，满足则设置 qa_scope=smoke
#
# 触发路径（v3.32.0+：fast_mode=true 不再因 diff 大小降级，相信用户/AI 判断）：
#   路径 A — fast_mode=true → 直接 smoke（无视 diff 大小/依赖变更）
#   路径 B — 标准模式 diff ≤ 30 行 AND ≤ 3 文件且无依赖变更 → smoke
#
# $1（可选）：mock diff 文件路径（红队测试用）。生产留空时跑 `git diff --stat HEAD`。
# 副作用：通过 set_field / append_changelog 修改全局 STATE_FILE 状态文件
# 失败不阻断 stop-hook（调用方使用 || true 兜底）
detect_smoke_eligible() {
    local diff_input="${1:-}"

    # qa_scope 已有值（如 "selective"）时不重复评估
    [[ -n "$(get_enum_field qa_scope)" ]] && return 0

    local diff_lines=0 diff_files=0 has_deps=0

    if [[ -n "$diff_input" ]] && [[ -f "$diff_input" ]]; then
        # 测试模式：从传入文件解析 mock raw diff
        diff_lines=$(grep -cE '^[+-][^+-]' "$diff_input" 2>/dev/null || echo 0)
        diff_files=$(grep -cE '^diff --git' "$diff_input" 2>/dev/null || echo 0)
        if grep -qE '(package\.json|pnpm-lock|yarn\.lock|requirements\.txt|Cargo\.lock)' "$diff_input" 2>/dev/null; then
            has_deps=1
        fi
    else
        # 生产模式：git diff --stat
        local stat_output
        stat_output=$(git diff --stat HEAD 2>/dev/null) || return 0
        [[ -z "$stat_output" ]] && return 0
        diff_lines=$(echo "$stat_output" | tail -1 | grep -oE '[0-9]+ insertion|[0-9]+ deletion' | grep -oE '[0-9]+' | awk '{s+=$1} END{print s+0}')
        diff_files=$(echo "$stat_output" | grep -cE '^\s+\S+\s+\|\s+[0-9]+')
        if echo "$stat_output" | grep -qE '(package\.json|pnpm-lock|yarn\.lock|requirements\.txt|Cargo\.lock)'; then
            has_deps=1
        fi
    fi

    local fast_mode
    fast_mode=$(get_enum_field fast_mode || true)

    # 路径 A — fast_mode=true → 无视 diff 大小直接 smoke（用户/AI 显式选 fast，相信判断）
    if [[ "$fast_mode" == "true" ]]; then
        set_field "qa_scope" '"smoke"'
        append_changelog "stop-hook: fast_mode=true（${diff_lines}行/${diff_files}文件/含依赖=${has_deps}），启用 smoke QA"
        return 0
    fi

    # 路径 B — 标准模式：严格阈值，diff ≤ 30 行 AND ≤ 3 文件 AND 无依赖
    if [[ "$has_deps" -eq 0 ]] && [[ "${diff_lines:-999}" -le 30 ]] && [[ "${diff_files:-999}" -le 3 ]]; then
        set_field "qa_scope" '"smoke"'
        append_changelog "stop-hook: 自动检测 diff 体积小（${diff_lines}行/${diff_files}文件），启用 smoke QA"
    fi
}

# 支持 source 加载模式：被 source 时只导出函数定义（compress_qa_report 等），
# 不执行 main 逻辑。这让外部测试可以单独验证函数行为。
# 直接执行（bash stop-hook.sh）时 BASH_SOURCE[0] == $0，正常往下走。
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    return 0
fi

# ── 0. 先读 stdin，提取 cwd 后再初始化路径 ──
# Stop hook 的 stdin JSON 包含 cwd 字段，是 Claude Code 的实际工作目录。
# 在 worktree 场景下 hook 脚本的 shell CWD 可能不是项目目录，
# 必须用 stdin 中的 cwd 来正确定位状态文件。

HOOK_INPUT=$(timeout 5 cat 2>/dev/null || true)
HOOK_CWD=$(echo "$HOOK_INPUT" | jq -r '.cwd // ""' 2>/dev/null || true)
HOOK_TRANSCRIPT=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // ""' 2>/dev/null || true)

# 用 stdin 的 cwd 初始化路径（为空时 fallback 到当前 CWD）
init_paths "$HOOK_CWD"

# 状态文件不存在时直接放行
# shellcheck disable=SC2153
if [[ ! -f "$STATE_FILE" ]]; then
    exit 0
fi

# ── 2. 解析 frontmatter ──

PHASE=$(get_enum_field "phase" || true)
GATE=$(get_enum_field "gate" || true)
ITERATION=$(get_field "iteration" || true)
MAX_ITERATIONS=$(get_field "max_iterations" || true)
STATE_SESSION=$(get_field "session_id" || true)

# ── 3. Session 隔离（Ralph 兼容 + 首次认领） ──

HOOK_SESSION=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)

# Guard 1: 空 STATE_SESSION → 首次认领
# setup.sh 在 CLAUDE_CODE_SESSION_ID 不可用时写入空值（与 ralph 一致）。
# 首次 Stop hook 触发时，用真实 session_id 认领状态文件，建立隔离。
if [[ -z "$STATE_SESSION" ]]; then
    if [[ -n "$HOOK_SESSION" ]]; then
        set_field "session_id" "$HOOK_SESSION"
        STATE_SESSION="$HOOK_SESSION"
        # 继续执行，不 exit — session 已认领
    fi
    # HOOK_SESSION 也为空时继续执行（与 ralph 的空值跳过隔离一致）
fi

# Guard 2: 非空且不匹配 → 不同会话，放行
if [[ -n "$STATE_SESSION" ]] && [[ "$STATE_SESSION" != "$HOOK_SESSION" ]]; then
    exit 0
fi

# ── 3.5 Phase canonical 守卫 ──
# 若 PHASE 非空但不在闭合枚举内，注入纠正 block，让 AI 用 Edit 改回合法值后再继续。
# 守卫放在 session 隔离之后、数值校验与 phase=done 判断之前。
if [[ -n "${PHASE}" ]] && ! is_canonical phase "${PHASE}"; then
    GUARD_MSG="phase 字段值 '${PHASE}' 不在合法枚举内。合法值（闭合枚举）：design / implement / qa / auto-fix / merge / done。请用 Edit 工具将 ${STATE_FILE} frontmatter 的 phase 字段改为上述合法值之一，然后继续执行。"
    jq -n --arg reason "${GUARD_MSG}" \
        --arg msg "autopilot stop-hook: phase 值越界，需要纠正" \
        '{"decision":"block","reason":$reason,"systemMessage":$msg}'
    exit 0
fi

# ── 4. 数值校验（缺失时自动修复，不删除文件） ──

if [[ ! "$ITERATION" =~ ^[0-9]+$ ]]; then
    echo "⚠️  autopilot: iteration 字段缺失或无效 ('$ITERATION')，自动修复为 1" >&2
    ITERATION=1
    # 尝试修复状态文件：如果字段存在但值非法则修正，如果字段不存在则注入
    if grep -q "^iteration:" "$STATE_FILE" 2>/dev/null; then
        set_field "iteration" "1"
    else
        sed -i.bak '/^phase:/a\
iteration: 1' "$STATE_FILE" && rm -f "${STATE_FILE}.bak"
    fi
fi

if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
    echo "⚠️  autopilot: max_iterations 字段缺失或无效 ('$MAX_ITERATIONS')，自动修复为 30" >&2
    MAX_ITERATIONS=30
    if grep -q "^max_iterations:" "$STATE_FILE" 2>/dev/null; then
        set_field "max_iterations" "30"
    else
        sed -i.bak '/^iteration:/a\
max_iterations: 30' "$STATE_FILE" && rm -f "${STATE_FILE}.bak"
    fi
fi

# ── 5. phase=done → 完成清理 / 自动链接 ──

SKIP_INCREMENT=0

if [[ "$PHASE" == "done" ]]; then
    # 知识提取守卫（三态）：合法值放行 / 空值才回滚（真守卫）/ 非空乱值自动归一不回滚
    KNOWLEDGE_EXTRACTED=$(get_enum_field "knowledge_extracted" || true)
    if [[ "$KNOWLEDGE_EXTRACTED" != "true" ]] && [[ "$KNOWLEDGE_EXTRACTED" != "skipped" ]]; then
        if [[ -n "$KNOWLEDGE_EXTRACTED" ]]; then
            # 非空乱值（yes/done/摘要文本）：AI 已有意标记完成、只是 token 写错 →
            # 自动归一为 true、不回滚（tautological-key 容错：断言"活做了"而非"token 对不对"）。
            # 知识沉淀是 best-effort，误放行低危；回滚重跑烧 iteration 才是高危。
            # 用 stderr 告知（不发 stdout JSON）：done 收尾的 auto-chain 路径后续会输出 block JSON，
            # 这里再发一个 stdout JSON 会造成双 JSON 破坏 hook 协议。沿用脚本既有 >&2 通知惯例。
            set_field "knowledge_extracted" '"true"'
            echo "autopilot · 已将非法 knowledge_extracted 值「${KNOWLEDGE_EXTRACTED}」规范化为 true（知识提取视为已完成，未回滚）" >&2
        else
            # 空值：这一步根本没执行 → 维持严格的豁免/回滚逻辑（防真跳过）
            MODE_CHECK=$(get_enum_field "mode" || true)
            BRIEF_CHECK=$(get_field "brief_file" || true)
            if { [[ "$MODE_CHECK" == "project" ]] && [[ -z "$BRIEF_CHECK" ]]; } || [[ "$MODE_CHECK" == "project-qa" ]]; then
                set_field "knowledge_extracted" '"skipped"'
            else
                set_field "phase" '"merge"'
                NEXT_ITERATION=$((ITERATION + 1))
                set_field "iteration" "$NEXT_ITERATION"
                PROMPT="知识提取字段为空（这一步尚未执行）。读取 ${STATE_FILE}，按照 autopilot skill Phase: merge 的知识提取与沉淀步骤执行。完成后用 Edit 设置 knowledge_extracted 为 true（有新增）或 skipped（无新增）——合法值仅 true / skipped，然后再设 phase: done。"
                jq -n --arg prompt "$PROMPT" --arg msg "autopilot iteration ${NEXT_ITERATION} | phase: merge | 知识提取回滚（字段为空）" \
                    '{"decision":"block","reason":$prompt,"systemMessage":$msg}'
                exit 0
            fi
        fi
    fi

    MODE=$(get_enum_field "mode" || true)

    # Case 0: project-qa 完成 → 项目完成通知 + 清理 active 指针
    if [[ "$MODE" == "project-qa" ]]; then
        bash "$SCRIPT_DIR/notify.sh" project-complete 2>/dev/null || true
        rm -f "$(get_active_file)"
        exit 0
    fi

    NEXT_TASK=$(get_field "next_task" || true)
    BRIEF_FILE=$(get_field "brief_file" || true)
    DAG_FILE="$PROJECT_ROOT/.autopilot/project/dag.yaml"

    # Case 0.5: 项目模式设计完成（非子任务）→ 自动启动首个就绪任务
    if [[ "$MODE" == "project" ]] && [[ -z "$BRIEF_FILE" ]] && [[ -f "$DAG_FILE" ]]; then
        FIRST_READY=$(get_first_ready_task "$DAG_FILE")
        if [[ -n "$FIRST_READY" ]] && [[ "$FIRST_READY" != "ALL_DONE" ]]; then
            # brief 字段优先（显式文件指针，文件命名自由），回退 tasks/<id>.md（v3.54.0 兼容）
            _brief_ptr=$(get_task_brief "$DAG_FILE" "$FIRST_READY" 2>/dev/null || true)
            if [[ -n "$_brief_ptr" ]]; then
                case "$_brief_ptr" in
                    /*) TASK_FILE="$_brief_ptr" ;;
                    *)  TASK_FILE="$PROJECT_ROOT/$_brief_ptr" ;;
                esac
            else
                TASK_FILE="$PROJECT_ROOT/.autopilot/project/tasks/${FIRST_READY}.md"
            fi
            if [[ -f "$TASK_FILE" ]]; then
                new_slug=$(generate_task_slug "$FIRST_READY")
                setup_requirement_dir "$new_slug"
                TASK_FILE_ABS=$(cd "$(dirname "$TASK_FILE")" && pwd)/$(basename "$TASK_FILE")
                create_brief_state_file "$TASK_FILE_ABS" "$HOOK_SESSION" "30" "3"
                bash "$SCRIPT_DIR/notify.sh" auto-chain 2>/dev/null || true
                echo "🔗 project-design → ${FIRST_READY}" >&2
                PHASE=$(get_enum_field "phase" || true)
                # v3.36.3 必须重读 GATE/AUTO_APPROVE：旧 state 残留 gate（如 AI 未清的
                # review-accept）会让下方第 6 步审批门误命中而 exit 0，新 state 的
                # block JSON 永不输出。这是 auto-chain 失效双链第 2 环。
                GATE=$(get_enum_field "gate" || true)
                AUTO_APPROVE=$(get_enum_field "auto_approve" || true)
                ITERATION=$(get_field "iteration" || true)
                MAX_ITERATIONS=$(get_field "max_iterations" || true)
                SKIP_INCREMENT=1
                # 落入下方 block JSON 构造
            else
                bash "$SCRIPT_DIR/notify.sh" project-design-complete 2>/dev/null || true
                rm -f "$(get_active_file)"
                exit 0
            fi
        else
            bash "$SCRIPT_DIR/notify.sh" project-design-complete 2>/dev/null || true
            rm -f "$(get_active_file)"
            exit 0
        fi

    # Case 1: AI 信号了下一个任务 → 自动链接
    elif [[ -n "$NEXT_TASK" ]] && [[ -f "$DAG_FILE" ]]; then
        # brief 字段优先（显式文件指针，文件命名自由），回退 tasks/<id>.md（v3.54.0 兼容）
        _brief_ptr=$(get_task_brief "$DAG_FILE" "$NEXT_TASK" 2>/dev/null || true)
        if [[ -n "$_brief_ptr" ]]; then
            case "$_brief_ptr" in
                /*) TASK_FILE="$_brief_ptr" ;;
                *)  TASK_FILE="$PROJECT_ROOT/$_brief_ptr" ;;
            esac
        else
            TASK_FILE="$PROJECT_ROOT/.autopilot/project/tasks/${NEXT_TASK}.md"
        fi
        if [[ -f "$TASK_FILE" ]]; then
            # 为新任务创建新的 requirements 文件夹
            new_slug=$(generate_task_slug "$NEXT_TASK")
            setup_requirement_dir "$new_slug"
            TASK_FILE_ABS=$(cd "$(dirname "$TASK_FILE")" && pwd)/$(basename "$TASK_FILE")
            create_brief_state_file "$TASK_FILE_ABS" "$HOOK_SESSION" "30" "3"
            bash "$SCRIPT_DIR/notify.sh" auto-chain 2>/dev/null || true
            echo "🔗 auto-chain: ${NEXT_TASK}" >&2
            # 重新读取新状态文件的字段
            PHASE=$(get_enum_field "phase" || true)
            # v3.36.3 必须重读 GATE/AUTO_APPROVE（双链第 2 环修复）
            GATE=$(get_enum_field "gate" || true)
            AUTO_APPROVE=$(get_enum_field "auto_approve" || true)
            ITERATION=$(get_field "iteration" || true)
            MAX_ITERATIONS=$(get_field "max_iterations" || true)
            SKIP_INCREMENT=1
            # 落入下方 block JSON 构造
        else
            echo "⚠️  autopilot: next_task file not found: ${TASK_FILE}" >&2
            bash "$SCRIPT_DIR/notify.sh" complete 2>/dev/null || true
            rm -f "$(get_active_file)"
            exit 0
        fi
    # Case 2: 项目子任务完成 + 无 next_task → 检查是否全部完成
    elif [[ -n "$BRIEF_FILE" ]] && [[ -f "$DAG_FILE" ]]; then
        RESULT=$(get_first_ready_task "$DAG_FILE")
        if [[ "$RESULT" == "ALL_DONE" ]]; then
            # 全部完成 → 启动全项目 QA，创建新的 requirements 文件夹
            qa_slug=$(generate_task_slug "全项目集成QA验证")
            setup_requirement_dir "$qa_slug"
            create_project_qa_state_file "$HOOK_SESSION"
            bash "$SCRIPT_DIR/notify.sh" project-qa 2>/dev/null || true
            echo "🏁 所有任务已完成，启动全项目 QA" >&2
            PHASE=$(get_enum_field "phase" || true)
            # v3.36.3 必须重读 GATE/AUTO_APPROVE（双链第 2 环修复）
            GATE=$(get_enum_field "gate" || true)
            AUTO_APPROVE=$(get_enum_field "auto_approve" || true)
            ITERATION=$(get_field "iteration" || true)
            MAX_ITERATIONS=$(get_field "max_iterations" || true)
            SKIP_INCREMENT=1
            # 落入下方 block JSON 构造
        else
            # 还有任务但 AI 未信号高信心 → 释放，等用户操作
            bash "$SCRIPT_DIR/notify.sh" complete 2>/dev/null || true
            rm -f "$(get_active_file)"
            exit 0
        fi
    # Case 3: 单任务模式 → 正常清理（保留 requirements 文件夹，移除 active 指针）
    else
        bash "$SCRIPT_DIR/notify.sh" complete 2>/dev/null || true
        rm -f "$(get_active_file)"
        exit 0
    fi
fi

# ── 5.5 Auto-approve 子任务在 QA review-accept gate 自动推进 merge ──
# 解决：project 模式 auto-chain 子任务 QA 通过后卡在 gate=review-accept 等用户审批，
# 违背 auto-chain 自动推进初衷。三条件 AND：phase=qa（排除 auto-fix max_retries / implement
# 蓝队失败兜底场景，那两类 phase 不是 qa）+ gate=review-accept + auto_approve=true（仅
# stop-hook 的 create_brief_state_file / create_project_qa_state_file 会写 true，
# 单任务模式默认 false，是 auto-chain 流的充分指标）。
AUTO_APPROVE=$(get_enum_field "auto_approve" || true)
if [[ "${GATE}" == "review-accept" ]] && [[ "${PHASE}" == "qa" ]] && \
   [[ "${AUTO_APPROVE}" == "true" ]]; then
    set_field "gate" '""'
    set_field "phase" '"merge"'
    GATE=""
    PHASE="merge"
    echo "🔗 auto-approve: review-accept → merge (auto-chain subtask)" >&2
fi

# ── 5.6 Tier 5 合规校验（gate=review-accept 时，照 §8.5.1 block+systemMessage 模式） ──
# 编排器设 gate=review-accept 时，校验 tier5_status ∈ {na,skipped,pass,fail}。
#
# **空值兜底补判**（治沉默缺席但不破坏 R12 审批流）：
#   tier5_status 空 → 先内联补判（复用 §8.5.3 同款逻辑：smoke→skipped / 无工具→na / 有工具→留空）。
#   补判后非空 → 放行落入 §6；补判后仍空（有工具但编排器漏判）或越界 → block 回 qa 补判。
#
# **路径区分**（治 B2）：tier5_status block = "回 qa 补判定"，**非 auto-fix**
# （auto-fix 是 Tier 0/1/1.5 失败修复路径，retry_count 不计 tier5 缺失）。
# stop-hook 清 gate + 注入 prompt"只补 Tier 5 判定"，编排器重跑仅 Tier 5。
# **死锁防护**：与 retry_count 解耦，不耗 max_retries。na/skip 不阻塞合并，阻塞的仅"越界/有工具却漏判"。
if [[ "${GATE}" == "review-accept" ]] && [[ "${PHASE}" == "qa" ]]; then
    _tier5_status=$(get_enum_field tier5_status 2>/dev/null || true)
    # 空值兜底：内联补判（与 §8.5.3 同款，幂等——§8.5.3 已判过则 tier5_status 非空不会进此分支）
    if [[ -z "$_tier5_status" ]]; then
        _qa_scope_t5=$(get_enum_field qa_scope 2>/dev/null || true)
        if [[ "$_qa_scope_t5" == "smoke" ]]; then
            set_field "tier5_status" '"skipped"'
            append_changelog "stop-hook §5.6 兜底：qa_scope=smoke，tier5_status=skipped"
            _tier5_status="skipped"
        else
            _tools_json_t5=$(detect_quantitative_tools 2>/dev/null || \
                printf '{"stryker":false,"c8":false,"nyc":false,"istanbul":false,"jest_coverage":false}')
            if echo "$_tools_json_t5" | grep -qE '"(stryker|c8|nyc|istanbul|jest_coverage)"[[:space:]]*:[[:space:]]*true'; then
                : # 有工具 → 留空（编排器应跑工具后写 pass/fail，落入下方越界 block 分支治漏判）
            else
                set_field "tier5_status" '"na"'
                append_changelog "stop-hook §5.6 兜底：无量化工具，tier5_status=na"
                _tier5_status="na"
            fi
        fi
    fi
    case "${_tier5_status}" in
        na|skipped|pass|fail)
            # 合规值（含兜底补判的 na/skipped）→ 放行，落入 §6 正常审批门
            :
            ;;
        *)
            # 越界或"有工具却漏判"（空）→ block 回 qa 补判定（非 auto-fix，不耗 retry_count）
            _tier5_reason="Tier 5 量化指标门禁判定缺失或越界（tier5_status=「${_tier5_status}」）。合法值仅 na/skipped/pass/fail。请只补 Tier 5 判定后重设 gate=review-accept：若有量化工具则跑 mutation/coverage 后用 Edit 设 tier5_status 为 pass/fail；无工具则设 na；smoke 路径则设 skipped。此 block 不耗 max_retries（非 auto-fix 路径）。"
            set_field "gate" '""'
            GATE=""
            jq -n --arg reason "${_tier5_reason}" \
                --arg msg "autopilot stop-hook: Tier 5 判定缺失（tier5_status 空/越界），回 qa 补判后重设 gate" \
                '{"decision":"block","reason":$reason,"systemMessage":$msg}'
            exit 0
            ;;
    esac
fi

# ── 5.7 谓词驱动/产物真实性守卫（gate=review-accept 时，照 §5.6 block 模式） ──
# 治编排器用 mock 单测输出冒充 Tier 1.5 真实产物 artifact：stop-hook 机械校验
#   (a) driver type 与观测语义一致（node-script 不得跑网络/外部依赖——应改 curl/playwright）
#   (b) artifact 字段声明的路径真实存在且非空（确定性路径 /tmp/autopilot-artifacts/<pred-id>.out）
# 自门控：无谓词或全无 driver/artifact 字段 → validate 函数返回 1（no-op）→ 不触发。
# 任一 rc2 → block 回 qa 补真实 artifact（非 auto-fix，不耗 retry_count），与 §8.5.1/§8.5.2 同构。
# 设计 SSOT：谓词格式见 references/scenario-generator-prompt.md；artifact 路径约定见
# references/state-file-guide.md。
if [[ "${GATE}" == "review-accept" ]] && [[ "${PHASE}" == "qa" ]]; then
    _pred_driver_rc=0
    _pred_driver_out=$(validate_predicate_driver "${STATE_FILE}" 2>/dev/null) || _pred_driver_rc=$?
    # 双信号判定：rc==2 或 stdout 含 PRED-DRIVER-VIOLATION（防 rc 歧义，参照 §8.5.1）
    if [[ "${_pred_driver_rc}" -eq 2 ]] || echo "${_pred_driver_out}" | grep -q "PRED-DRIVER-VIOLATION"; then
        _pred_reason="QA 谓词驱动类型与观测语义不一致（${_pred_driver_out}）。node-script 驱动不得执行网络/外部依赖（curl/fetch/playwright/overmind/pylon/mysql），须改用对应真实驱动类型并在 ## 验收场景 预注册 driver 字段后重设 gate=review-accept。此 block 不耗 max_retries（非 auto-fix 路径）。"
        set_field "gate" '""'
        GATE=""
        jq -n --arg reason "${_pred_reason}" \
            --arg msg "autopilot stop-hook §5.7: 谓词驱动类型违规，回 qa 改用真实驱动类型后重设 gate" \
            '{"decision":"block","reason":$reason,"systemMessage":$msg}'
        exit 0
    fi
    _pred_art_rc=0
    _pred_art_out=$(validate_predicate_artifacts "${STATE_FILE}" 2>/dev/null) || _pred_art_rc=$?
    if [[ "${_pred_art_rc}" -eq 2 ]] || echo "${_pred_art_out}" | grep -q "PRED-ARTIFACT-MISSING"; then
        _pred_reason="QA 谓词产物 artifact 缺失或为空（${_pred_art_out}）。每条 PASS 谓词须将真实驱动输出写入 ## 验收场景 预注册的 artifact 路径（/tmp/autopilot-artifacts/<pred-id>.out），stop-hook §5.7 校验存在性，不得用 mock 单测输出冒充。此 block 不耗 max_retries（非 auto-fix 路径）。"
        set_field "gate" '""'
        GATE=""
        jq -n --arg reason "${_pred_reason}" \
            --arg msg "autopilot stop-hook §5.7: 谓词 artifact 缺失，回 qa 补真实产物后重设 gate" \
            '{"decision":"block","reason":$reason,"systemMessage":$msg}'
        exit 0
    fi
fi

# ── 6. 审批门检查 ──

if [[ -n "$GATE" ]]; then
    bash "$SCRIPT_DIR/notify.sh" "$GATE" 2>/dev/null || true
    # 放行退出，等待用户回来审批
    exit 0
fi

# ── 7. max_iterations 检查 ──

if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
    echo "🛑 autopilot: 达到最大迭代次数 ($MAX_ITERATIONS)。" >&2
    bash "$SCRIPT_DIR/notify.sh" error 2>/dev/null || true
    rm -f "$(get_active_file)"
    exit 0
fi

# ── 7.5 后台 sub-agent 检测（全阶段静默等待） ──
# 任何阶段启动的长时 sub-agent 都受此机制保护：
#   - implement 阶段：并行蓝队/红队 sub-agent（5-10 分钟）
#   - merge 阶段：commit-agent 常以 run_in_background=true 启动（异步路径 B），
#     运行数分钟；主 agent 结束响应 → stop-hook 触发 → 若此检查被跳过则落到
#     §8 递增 iteration + §9 重新注入「merge 阶段必须启动 commit-agent」prompt
#     → 反复唤醒近似死循环（flag-asymmetry 历史 bug，2026-05-26）
#   - qa/auto-fix 阶段：qa-reviewer 等长时 sub-agent 同理受护
#
# 旧注释「design/qa/merge 的 sub-agent 都是短时（< 2 分钟）」的假设对
# commit-agent 不成立，是旧版 phase=implement 门控留下的 flag-asymmetry bug 根因。
#
# 该检查自门控：has_pending_subagents 无 pending 时返回 1，正常注入流程继续，
# 故全阶段泛化零副作用。位于 gate 检查（§6）与 max_iterations（§7）之后，
# 到达此处必是 gate 空、phase∈{design,implement,qa,auto-fix,merge}
# （done 在 §5 已提前 exit）。iteration 在静默等待时不递增（exit 0 在 §8 之前）。
#
# Sub-agent 完成后，Claude Code 内置机制让主 agent 自然恢复（tool_result 入流，
# 下次 stop-hook 触发时 pending=0 走正常注入路径）。
#
# 教训（flag-asymmetry）：检测机制必须在所有相关转换点一致生效，
# 单点修复（仅 implement）会在其他阶段留下同类漏洞。
if [[ -n "$HOOK_TRANSCRIPT" ]] && has_pending_subagents "$HOOK_TRANSCRIPT"; then
    echo "[autopilot] 检测到后台 sub-agent 运行中，等待 (phase: ${PHASE}, iter: ${ITERATION})" >&2
    jq -n --arg msg "⏳ autopilot · 正在等待后台 sub-agent 完成（phase: ${PHASE}）。完成后会自动继续；若超过 ~10 分钟仍无进展（sub-agent 可能已异常退出），用 /autopilot cancel 恢复。" \
        '{"systemMessage": $msg}'
    exit 0
fi

# ── 7.6 standard design 放行 + 暂停说明（用户对齐阶段不自动推进） ──
# design 是与用户对齐设计方案的阶段，本质需要用户参与，不应被自动循环强制推进。
# 历史 bug（2026-05-31）：AI 在 design 结束回合等用户后，§9 重新注入"继续 design"
# prompt（block decision），AI 误读为"已通过"直接冲进 implement 把需求做完，绕过对齐。
# 根治：standard design（非 fast/auto）无 pending sub-agent 时不注入 block，改输出
# systemMessage 放行——AI 物理上不被重新唤醒，只能等用户在对话里回应才继续。
#   - 用 systemMessage 而非 decision:block：block 会重新唤醒 AI（正是 bug 成因）；
#     systemMessage 允许 stop（控制权交回用户）同时让用户/AI 都明白"这是有意暂停"。
#   - 放在 §8 递增之前：design 对齐不消耗 implement 的 iteration 预算，避免长设计
#     讨论被 §7 max_iterations 误杀删 active 文件。
#   - 放在 §7.5 has_pending 之后：design 的 Explore/plan-reviewer 等 sub-agent 运行时
#     先静默等待（§7.5），不被误放行。
#   - 仅 standard 路径：fast_mode / auto_approve 是用户显式选择的"跳过审批、全自动"，
#     保留其 §9 re-injection 自动推进到 implement。
#   - flag-asymmetry 防御：未来新增 design 模式 flag 时，此处条件与 §9 design 分支
#     （auto_approve / fast_mode 判断）必须同步处理。
# 缺失字段 get_field 返回空串，"" != "true" 恒真 → 缺失即按 false（fail-safe 朝放行）。
AUTO_APPROVE=$(get_enum_field "auto_approve" || true)
FAST_MODE=$(get_enum_field "fast_mode" || true)
# v3.43.1 加 design_doc_written 前置：只在「设计文档已落盘」的审批点放行。brainstorm 刚完成的
# 接力点设计文档仍空（仅占位符）→ 不命中 → fall through §9 自动唤醒接力写设计文档。
# （一刀切放行会误停接力点，逼用户手动「继续」——v3.43.0 回归 bug，本次修复。）
if [[ "$PHASE" == "design" ]] && [[ "$AUTO_APPROVE" != "true" ]] && [[ "$FAST_MODE" != "true" ]] && design_doc_written "$STATE_FILE"; then
    jq -n --arg msg "⏸️ autopilot · design 阶段暂停：控制权已交回用户，用户尚未确认设计方案。在用户明确表态前不要推进——用户认可后才进入 implement，用户给修改意见则留在 design 修订。" \
        '{"systemMessage": $msg}'
    exit 0
fi

# ── 8. 递增 iteration（自动链接创建的新状态文件跳过递增） ──

if [[ "$SKIP_INCREMENT" -eq 0 ]]; then
    NEXT_ITERATION=$((ITERATION + 1))
    set_field "iteration" "$NEXT_ITERATION"
else
    NEXT_ITERATION="$ITERATION"
fi

# ── 8.5 在 phase 转入 qa/auto-fix 时压缩 QA 报告历史轮次 ──
# 失败不阻断 stop-hook，使用 || true 兜底
NEW_PHASE=$(get_field "phase" || true)
if [[ "$NEW_PHASE" == "qa" ]] || [[ "$NEW_PHASE" == "auto-fix" ]]; then
    compress_qa_report "$STATE_FILE" || true
fi
# 单独的 qa 触发点（不在 auto-fix 触发，避免重复评估）
if [[ "$NEW_PHASE" == "qa" ]]; then
    detect_smoke_eligible || true

    # ── 8.5.0.5 验收测试合流（implement→qa 转入时确定性搬运，C3） ──
    # 自门控：仅当 $TASK_DIR/acceptance-staging/manifest 存在时执行，否则完全 no-op（向后兼容旧任务）。
    # 读 manifest（每条两行 staging:/target:）→ 逐文件 mv → git add 成功文件 → lock_acceptance_tests
    # → 写状态文件 ## 红队验收测试 = target_path 列表。
    # 时序：必须在 §8.5.1 tamper 守卫之前（lock 在此写）。
    # 失败 solve-don't-punt：单文件 mv 失败标 [!] 不纳入 lock；manifest 缺失/全失败 → 降级，不阻塞。
    _merge_acceptance_staging() {
        [ -n "${TASK_DIR}" ] || return 0
        local staging_dir="${TASK_DIR}/acceptance-staging"
        local manifest="${staging_dir}/manifest"
        [ -f "$manifest" ] || return 0   # 自门控：无 manifest = 无红队暂存，no-op

        local staging="" target="" moved_ok="" failed=""
        local line
        while IFS= read -r line; do
            case "$line" in
                staging:*)
                    staging="${line#staging:}"
                    staging="${staging#"${staging%%[![:space:]]*}"}"   # strip 前导空白（容错多空格/tab，I2）
                    ;;
                target:*)
                    target="${line#target:}"
                    target="${target#"${target%%[![:space:]]*}"}"
                    # 四分支：格式错 / staging 在 / 幂等已搬 / 幽灵（I1：幂等不误报全失败）
                    if [ -z "$staging" ] || [ -z "$target" ]; then
                        failed+="${staging:-<empty-staging>}"$'\n'      # manifest 格式错
                    elif [ -f "$staging" ]; then
                        if mkdir -p "$(dirname "$target")" 2>/dev/null && mv "$staging" "$target" 2>/dev/null; then
                            moved_ok+="${target}"$'\n'
                        else
                            failed+="${staging}"$'\n'                   # mv 失败
                        fi
                    elif [ -f "$target" ]; then
                        moved_ok+="${target}"$'\n'                      # 幂等：staging 已搬、target 在 → 重纳重新锁，不报失败
                    else
                        failed+="${staging}"$'\n'                       # 幽灵：staging/target 都不在
                    fi
                    staging=""; target=""
                    ;;
            esac
        done < "$manifest"

        # 有成功搬运 → git add + lock + 写状态文件 ## 红队验收测试 区域
        if [ -n "$moved_ok" ]; then
            # git add 成功搬运的 target 文件（逐行，容错含空格路径）
            local f
            while IFS= read -r f; do
                [ -n "$f" ] && git add -- "$f" 2>/dev/null || true
            done <<< "$moved_ok"
            # lock_acceptance_tests（lib.sh 既有函数）：仅锁成功搬运的 target 文件 sha256。
            # 用数组收集路径以正确传递（lib.sh 函数签名 lock_acceptance_tests <lock> <file...>）。
            local -a ok_files=()
            while IFS= read -r f; do
                [ -n "$f" ] && ok_files+=("$f")
            done <<< "$moved_ok"
            if [ "${#ok_files[@]}" -gt 0 ]; then
                lock_acceptance_tests "${TASK_DIR}/.acceptance-lock" "${ok_files[@]}" 2>/dev/null || true
            fi

            # 写状态文件 ## 红队验收测试 区域 = target_path 列表（非 staging）
            _write_acceptance_section "$STATE_FILE" "$moved_ok"
        fi

        # 全失败 / manifest 空内容 → 不写 lock，留降级提示
        if [ -z "$moved_ok" ] && [ -n "$failed" ]; then
            echo "⚠️ autopilot stop-hook: 验收测试全部 mv 失败，留暂存区，QA 走文本清单降级" >&2
        elif [ -n "$failed" ]; then
            echo "⚠️ autopilot stop-hook: 部分验收测试 mv 失败（见 staging），已成功部分正常合流" >&2
        fi
        return 0
    }

    # _write_acceptance_section <state_file> <target_paths(multiline)>
    # 用 awk 精确替换 ## 红队验收测试 区域内容（到下一个 top section 为止），避免 Write 重写整个文件。
    # paths 多行通过临时文件喂给 awk（awk -v 不支持多行字符串）。
    _write_acceptance_section() {
        local sf="$1" paths="$2"
        [ -f "$sf" ] || return 0
        local paths_file tmp
        paths_file=$(mktemp) || return 0
        tmp=$(mktemp "${sf}.XXXXXX") || { rm -f "$paths_file"; return 0; }
        printf '%s\n' "$paths" | grep -vE '^[[:space:]]*$' > "$paths_file" 2>/dev/null || true
        # 两文件流：状态文件 + paths 文件（FILENAME 区分）。遇到状态文件的 ## 红队验收测试
        # 标题后，立即把 paths_file 全部内容吐出，然后跳过旧区域直到下一个 top section。
        if awk -v paths_file="$paths_file" '
            FILENAME == paths_file { next }
            /^## 红队验收测试[[:space:]]*$/ {
                print
                while ((getline pline < paths_file) > 0) print pline
                close(paths_file)
                skip = 1
                next
            }
            skip && /^## (QA 报告|变更日志|用户反馈|实现计划|设计文档|验收场景)[[:space:]]*$/ { skip = 0 }
            skip { next }
            { print }
        ' "$sf" "$paths_file" > "$tmp" 2>/dev/null; then
            mv "$tmp" "$sf"
        else
            rm -f "$tmp"
        fi
        rm -f "$paths_file"
    }

    _merge_acceptance_staging || true

    # ── 8.5.1 测试篡改守卫（implement→qa 转入时一次性检测） ──
    # 自门控：仅当 .acceptance-lock 存在且 sha 不匹配时触发。
    # 无锁文件 → acceptance_tests_tampered 返回 1（no-lock）→ 不触发（零副作用）。
    # 检出篡改 → decision:block 指责"红队测试被修改，问题在实现不在测试"。
    # 先例：§3.5 canonical 守卫、§5 知识提取回滚守卫均为 early-exit decision:block+exit 0。
    if [[ -n "${TASK_DIR}" ]]; then
        _lock_file="${TASK_DIR}/.acceptance-lock"
        # 用 `|| _tamper_rc=$?` 而非 `|| true`：保留真实 rc（no-lock=1/tampered=2），
        # 左侧在 || 列表中非零不触发顶层 trap ERR（不会误早退破坏 §9 路由）。
        _tamper_rc=0
        _tamper_out=$(acceptance_tests_tampered "${_lock_file}" 2>/dev/null) || _tamper_rc=$?
        # 双信号判断：rc==2 或 stdout contains "TAMPER"（防 rc 歧义）
        if [[ "${_tamper_rc}" -eq 2 ]] || echo "${_tamper_out}" | grep -q "TAMPER"; then
            _tamper_reason="红队验收测试被修改（${_tamper_out}）。autopilot 铁律：默认不允许修改红队测试文件——问题在实现不在测试。若判定属红队测试本身问题（断言与契约矛盾/引用未声明私有seam/断言机制错），须先 AskUserQuestion 询问用户确认，确认后改测试并 source scripts/lib.sh 调 lock_acceptance_tests 重锁放行（详见 references/auto-fix-phase.md §6）；未经此流程不得直接改，必须 git checkout -- <测试文件> 还原后重修实现，再推进到 QA 阶段。"
            jq -n --arg reason "${_tamper_reason}" \
                --arg msg "autopilot stop-hook: 验收测试篡改守卫触发（implement→qa），还原测试后重修实现" \
                '{"decision":"block","reason":$reason,"systemMessage":$msg}'
            exit 0
        fi
    fi

    # ── 8.5.2 快照 oracle 污染守卫（implement→qa 转入时一次性检测） ──
    # 治 a56a55fe 实证：AI 删快照 baseline 重录后用 14/14 冒充 T1.5 谓词全 PASS，但未启动 app。
    # 自门控：snapshot_oracle_regened 在 git 不可用/非仓库时返回 1（n/a）→ 不触发。
    # 与 §8.5.1 同构：双信号判定（rc==2 或 stdout 含 ORACLE-REGHEN）→ decision:block 注入确定性 prompt。
    if [[ -n "${TASK_DIR}" ]]; then
        _oracle_rc=0
        _oracle_out=$(snapshot_oracle_regened 2>/dev/null) || _oracle_rc=$?
        if [[ "${_oracle_rc}" -eq 2 ]] || echo "${_oracle_out}" | grep -q "ORACLE-REGHEN"; then
            _oracle_reason="检测到本轮快照 oracle 重录（${_oracle_out}）。这些快照判别力已失效：删/改 baseline 重录会让任何快照断言无条件 PASS。依赖快照 artifact 的 T1.5 谓词不得 PASS，必须提供独立 oracle（真机截图 / 非快照断言 / freshness 类硬信号）。"
            jq -n --arg reason "${_oracle_reason}" \
                --arg msg "autopilot stop-hook: 快照 oracle 污染守卫触发（implement→qa），快照判别力失效，需独立 oracle" \
                '{"decision":"block","reason":$reason,"systemMessage":$msg}'
            exit 0
        fi
    fi

    # ── 8.5.3 Tier 5 量化门禁判定（na/skip 自动判，幂等前置治 B1） ──
    # 治真实 session Tier 5 三态失效（沉默缺席/措辞偏离/smoke 自觉跳过）：机械活下沉脚本，
    # 智力活（coverage 反向否决的 diff 语义、跑工具命令）留编排器。
    #
    # **幂等铁律**（治 B1）：tier5_status 非空时守卫跳过自动 set（不覆盖编排器已设的 pass/fail）。
    # 仅 `tier5_status 空 ∧ phase=qa` 时判（detect_smoke_eligible 已先于此设 qa_scope）：
    #   - qa_scope=smoke → set tier5_status=skipped（smoke 主动跳过）
    #   - detect_quantitative_tools 全 false → set tier5_status=na + jq 注入 §7 规定文案 systemMessage
    #   - 有工具 → 不 set（留编排器 Wave 1 跑 + 调 lib.sh + set pass/fail）
    #
    # 自门控：无 package.json / 非 qa 阶段（本 §8.5 区已限定 qa）→ no-op。
    # 失败不阻断 stop-hook（|| true 兜底）。
    _tier5_guard() {
        local tier5_status
        tier5_status=$(get_enum_field tier5_status 2>/dev/null || true)
        # 幂等前置：tier5_status 非空（编排器已设 pass/fail 或本守卫已跑）→ 不覆盖
        [[ -n "$tier5_status" ]] && return 0

        local qa_scope
        qa_scope=$(get_enum_field qa_scope 2>/dev/null || true)
        # smoke 路径 → skipped + 注入 systemMessage（治 smoke 报告渲染沉默：让 AI 在报告渲染 Tier 5: skipped 栏）
        if [[ "$qa_scope" == "smoke" ]]; then
            set_field "tier5_status" '"skipped"'
            append_changelog "stop-hook: qa_scope=smoke，tier5_status=skipped（§8.5.3 自动判 + systemMessage 可见化）"
            _TIER5_MSG="⚠️ Tier 5: skipped（smoke 主动跳过量化门禁）。tier5_status=skipped 已自动判定。QA 报告必须显式渲染 Tier 5 栏标注 skipped（让用户知晓此维度被 smoke 跳过，不得静默无此栏）。"
            return 0
        fi

        # 检测量化工具（lib.sh 唯一实现，SSOT）
        local tools_json any_tool=false
        tools_json=$(detect_quantitative_tools 2>/dev/null || \
            printf '{"stryker":false,"c8":false,"nyc":false,"istanbul":false,"jest_coverage":false}')
        if echo "$tools_json" | grep -qE '"(stryker|c8|nyc|istanbul|jest_coverage)"[[:space:]]*:[[:space:]]*true'; then
            any_tool=true
        fi

        if [[ "$any_tool" != "true" ]]; then
            # 无任何量化工具 → na。文案存全局变量 _TIER5_MSG，由 §9 合并进 decision JSON 的 systemMessage
            # （不独立 jq 输出 JSON——避免与 §9 的 decision JSON 形成 double JSON 破坏 hook 协议，治 qa-reviewer Critical-1）
            set_field "tier5_status" '"na"'
            append_changelog "stop-hook: 无 mutation/coverage 工具，tier5_status=na（§8.5.3 自动判 + systemMessage 可见化）"
            _TIER5_MSG="⚠️ 测试有效性维度未验证（无 mutation/coverage 工具）：tier5_status=na。na 表示无法求值（无工具评估测试套件的 kill-rate 与覆盖有效性），不计入放行依据，不得静默放行，QA 报告必须显式渲染此标注且不得含「PASS/绿灯/通过」字样。建议运行 /autopilot doctor 获取安装命令。"
            return 0
        fi

        # 有工具 → 不 set（留编排器 Wave 1 跑 + 调 tier5_coverage_check/tier5_mutation_check + set pass/fail）
        return 0
    }

    _tier5_guard || true
fi

# ── 9. 构造 block JSON ──
# 注意：macOS bash 3.2 有 multibyte bug，$VAR 后紧跟全角标点会吞掉变量值。
# 所有变量必须用 ${VAR} 花括号界定。

# design 阶段直接写设计文档到状态文件（auto_approve 时跳过审批）
AUTO_APPROVE=$(get_enum_field "auto_approve" || true)
# shellcheck disable=SC2034  # 兼容期保留：plan_mode 字段已弃用，分支体已删除（v3.21.0），仅保留赋值便于后续 grep 检测旧字段使用
PLAN_MODE=$(get_field "plan_mode" || true)
FAST_MODE=$(get_enum_field "fast_mode" || true)
if [[ "$PHASE" == "design" ]]; then
    if [[ "$AUTO_APPROVE" == "true" ]]; then
        PROMPT="读取 ${STATE_FILE} 状态文件获取目标描述. auto_approve=true: 直接写设计文档到状态文件. ⚠️ 必须使用 Agent 工具启动 plan-reviewer sub-agent (model: sonnet) 审查设计方案, 参见 references/plan-reviewer-prompt.md. 审查通过则推进到 implement; 失败则设 auto_approve: false 回退到正常审批流程. 按照 autopilot skill 的 Phase: design 指引执行."
    elif [[ "$FAST_MODE" == "true" ]]; then
        PROMPT="读取 ${STATE_FILE} 状态文件获取目标描述, fast_mode=true: 砍所有 plan-review 类节点（红蓝对抗 / QA Wave 1+1.5 是核心，保留不变）. design 阶段: 跳过 brainstorm Q&A，只用 1 个 Explore agent 探索代码，不启动 scenario-generator / plan-reviewer Agent — 设计文档写入状态文件后**直接设 phase: implement**（跳过 AskUserQuestion 审批，fast 信任 AI 判断；html_review=true 时改走步骤 4c HTML 评审）. implement 阶段: blue/red-team 双 Agent 照常启动，**跳过 contract-checker Agent**. 详见 SKILL.md Fast Mode 快速路径章节. 按照 autopilot skill 的 Phase: design 指引执行."
    else
        # §7.6 安全网：正常 standard design（auto_approve≠true ∧ fast_mode≠true）在 §7.6
        # 已输出 systemMessage 放行 exit，此处正常情况下不可达。保留作 §7.6 失效/条件漂移
        # 时的 fallback——本分支 PROMPT 方向是"请求用户审批"，安全；切勿删除：删后 §7.6
        # 万一失效，standard design 会落到无匹配分支、PROMPT 为空 → 空 reason 的 block 唤醒
        # AI 却无指令，更易冲进 implement，与"防 design 绕过审批"目标相悖。
        # 默认含 brainstorm 探索流程（原 deep 行为）。plan_mode=="deep" 的历史 state.md 同样走此分支（兼容期）
        PROMPT="读取 ${STATE_FILE} 状态文件获取目标描述. 默认 standard 路径请走 \`Skill: autopilot-brainstorm\` 委托完成 Q&A 与方案共识，brainstorm skill 输出 brainstorm.md 后主 SKILL 接力写设计文档. ⚠️ 必须使用 Agent 工具启动 plan-reviewer sub-agent (model: sonnet) 审查设计方案, 参见 references/plan-reviewer-prompt.md. 审查通过后使用 AskUserQuestion 请求用户审批. 产出物写入 task_dir: $(get_field 'task_dir'). 按照 autopilot skill 的 Phase: design 指引执行."
    fi
elif [[ "$PHASE" == "implement" ]]; then
    PROMPT="读取 ${STATE_FILE} 状态文件, 当前阶段: implement, 迭代: ${NEXT_ITERATION}. ⚠️ 红蓝对抗铁律: (1) 从状态文件读取设计文档, 检查是否有领域 Skill 委托; (2) 无委托时必须使用 Agent 工具在同一轮响应中同时启动蓝队和红队两个并行 sub-agent (model: sonnet), prompt 模板参见 references/blue-team-prompt.md 和 references/red-team-prompt.md; (3) 红队绝对不能读取蓝队新写的实现代码——红队只看设计文档; (4) 两个 Agent 都完成后合流: 收集产出、写入红队测试文件、更新状态文件. 详细工作流参见 references/implement-phase.md. 按照 autopilot skill 的 Phase: implement 指引执行."
elif [[ "$PHASE" == "qa" ]]; then
    QA_SCOPE=$(get_enum_field "qa_scope" || true)
    if [[ "${QA_SCOPE}" == "smoke" ]]; then
        PROMPT="读取 ${STATE_FILE} 状态文件, 当前阶段: qa (smoke), 迭代: ${NEXT_ITERATION}. ⚠️ smoke QA: 只执行 Wave 1 (Tier 0/1 红队验收测试 + 类型/Lint/单元/构建) + Wave 1.5 真实测试场景, 不启动 qa-reviewer Agent — 编排器自行 Read git diff 后内联做 3 项自审 (设计符合性 / OWASP 关键 / 代码质量明显问题). Tier 1.5 铁律不变: 必须执行设计文档每一个真实测试场景, 场景计数匹配 E≥N. 按照 autopilot skill 的指引执行."
    else
        PROMPT="读取 ${STATE_FILE} 状态文件, 当前阶段: qa, 迭代: ${NEXT_ITERATION}. ⚠️ Tier 1.5 铁律: (1) 必须执行设计文档中的每一个真实测试场景, 不允许跳过任何场景; (2) 结果判定前先做场景计数匹配——统计报告中执行:标记数量 E 与设计文档场景总数 N, E<N 则有场景被跳过, 必须补做. 按照 autopilot skill 的指引执行当前阶段的工作流."
    fi
elif [[ "$PHASE" == "merge" ]]; then
    PROMPT="读取 ${STATE_FILE} 状态文件, 当前阶段: merge, 迭代: ${NEXT_ITERATION}. ⚠️ merge 阶段必须使用 Agent 工具启动 commit-agent (model: sonnet), 参见 references/commit-agent-prompt.md 模板. 不要使用 Skill: autopilot-commit. 完成知识提取后, 用 Edit 设置 knowledge_extracted 为 true 或 skipped, 再设 phase: done. 按照 autopilot skill 的 Phase: merge 指引执行."
else
    PROMPT="读取 ${STATE_FILE} 状态文件, 当前阶段: ${PHASE}, 迭代: ${NEXT_ITERATION}. 按照 autopilot skill 的指引执行当前阶段的工作流."
fi
MODE=$(get_enum_field "mode" || true)
SYSTEM_MSG="autopilot iteration ${NEXT_ITERATION} | phase: ${PHASE}${MODE:+ | mode: $MODE}"
# §8.5.3 na/smoke 路径的可见化文案合并进 systemMessage（单 JSON 输出，治 qa-reviewer Critical-1 double JSON + smoke 渲染沉默）
if [[ -n "${_TIER5_MSG:-}" ]]; then
    SYSTEM_MSG="${SYSTEM_MSG}

${_TIER5_MSG}"
fi

jq -n \
    --arg prompt "$PROMPT" \
    --arg msg "$SYSTEM_MSG" \
    '{
        "decision": "block",
        "reason": $prompt,
        "systemMessage": $msg
    }'

exit 0
