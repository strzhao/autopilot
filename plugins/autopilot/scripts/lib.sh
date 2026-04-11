#!/bin/bash

# autopilot 共享函数库
# setup.sh 和 stop-hook.sh 共用的 frontmatter 操作工具
#
# 使用方式：source lib.sh 后调用 init_paths [cwd]
# cwd 可选，传入时会 cd 到该目录再解析路径（解决 worktree 场景下 hook CWD 不可靠问题）

PROJECT_ROOT=""
STATE_FILE=""

init_paths() {
    local target_cwd="${1:-}"
    if [[ -n "$target_cwd" ]] && [[ -d "$target_cwd" ]]; then
        cd "$target_cwd" || return
    fi
    PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    STATE_FILE="${PROJECT_ROOT}/.autopilot/autopilot.local.md"
}

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

# ── DAG 解析函数 ──────────────────────────────────────────────

# 返回 DAG 中第一个就绪任务 ID（pending + 依赖全部 done），
# 如果所有任务已完成返回 "ALL_DONE"，否则返回空字符串。
get_first_ready_task() {
    local dag_file="$1"
    [[ ! -f "$dag_file" ]] && return
    awk '
    /^[[:space:]]*-[[:space:]]*id:/ {
        gsub(/.*id:[[:space:]]*"?/, ""); gsub(/".*/, ""); id=$0
        title=""; status=""; deps=""
    }
    /^[[:space:]]*title:/ {
        gsub(/.*title:[[:space:]]*"?/, ""); gsub(/".*/, ""); title=$0
    }
    /^[[:space:]]*status:/ {
        gsub(/.*status:[[:space:]]*"?/, ""); gsub(/".*/, ""); status=$0
    }
    /^[[:space:]]*depends_on:/ {
        gsub(/.*depends_on:[[:space:]]*/, ""); deps=$0
    }
    {
        if (id != "" && title != "" && status != "") {
            ids[++n] = id
            statuses[id] = status
            dep_lists[id] = deps
            id=""; title=""; status=""; deps=""
        }
    }
    END {
        all_done = 1; first_ready = ""
        for (i = 1; i <= n; i++) {
            tid = ids[i]
            if (statuses[tid] != "done" && statuses[tid] != "skipped") all_done = 0
            if (statuses[tid] != "pending") continue
            if (first_ready != "") continue
            d = dep_lists[tid]
            gsub(/[\[\]" ]/, "", d)
            ready = 1
            if (d != "") {
                split(d, darr, ",")
                for (j in darr) {
                    if (darr[j] != "" && statuses[darr[j]] != "done") {
                        ready = 0; break
                    }
                }
            }
            if (ready) first_ready = tid
        }
        if (first_ready != "") print first_ready
        else if (all_done) print "ALL_DONE"
    }' "$dag_file"
}

# ── Brief 模式状态文件创建 ────────────────────────────────────

# 为项目 DAG 中的任务创建 brief 模式状态文件。
# 参数: task_file session_id max_iterations max_retries auto_approve
create_brief_state_file() {
    local brief_file="$1"
    local session_id="${2:-}"
    local max_iterations="${3:-30}"
    local max_retries="${4:-3}"
    local auto_approve="${5:-false}"

    local brief_content
    brief_content=$(head -100 "$brief_file")

    # 解析 depends_on，收集 handoff 文件
    local handoff_content=""
    local brief_dir
    brief_dir=$(dirname "$brief_file")
    local deps
    deps=$(sed -n 's/.*depends_on:.*\[//p' "$brief_file" 2>/dev/null | sed 's/\].*//;s/[",]/ /g' || true)
    local dep handoff
    for dep in $deps; do
        dep="${dep//\"/}"
        handoff="$brief_dir/${dep}.handoff.md"
        if [[ -f "$handoff" ]]; then
            handoff_content="${handoff_content}
--- handoff: ${dep} ---
$(head -50 "$handoff")
"
        fi
    done

    # 读取架构设计摘要
    local design_summary=""
    local design_file="$PROJECT_ROOT/.autopilot/project/design.md"
    if [[ -f "$design_file" ]]; then
        design_summary="
--- 架构设计摘要 ---
$(head -60 "$design_file")"
    fi

    # 知识库提示
    local knowledge_hint=""
    if [[ -f "$PROJECT_ROOT/.autopilot/index.md" ]]; then
        knowledge_hint="
> 📚 项目知识库已存在: .autopilot/。design 阶段请先加载相关知识上下文。"
    fi

    mkdir -p "$PROJECT_ROOT/.autopilot"

    cat > "$STATE_FILE" <<EOF
---
active: true
phase: "design"
gate: ""
iteration: 1
max_iterations: $max_iterations
max_retries: $max_retries
retry_count: 0
mode: "single"
brief_file: "$brief_file"
next_task: ""
auto_approve: $auto_approve
session_id: $session_id
started_at: "$(now_iso)"
---

## 目标
$brief_content
$handoff_content
$design_summary
$knowledge_hint

## 设计文档
(待 design 阶段填充)

## 实现计划
(待 design 阶段填充)

## 红队验收测试
(待 implement 阶段填充)

## QA 报告
(待 qa 阶段填充)

## 变更日志
- [$(now_iso)] autopilot 初始化（brief 模式），任务: $(basename "$brief_file")
EOF
}

# ── 全项目 QA 状态文件创建 ─────────────────────────────────────

# 所有 DAG 任务完成后，创建全项目 QA 验证状态文件。
# 参数: session_id
create_project_qa_state_file() {
    local session_id="${1:-}"

    # 收集所有 handoff 摘要
    local handoff_summary=""
    local tasks_dir="$PROJECT_ROOT/.autopilot/project/tasks"
    if [[ -d "$tasks_dir" ]]; then
        local hf
        for hf in "$tasks_dir"/*.handoff.md; do
            [[ -f "$hf" ]] || continue
            handoff_summary="${handoff_summary}
### $(basename "$hf" .handoff.md)
$(head -30 "$hf")
"
        done
    fi

    # 读取架构设计
    local design_content=""
    local design_file="$PROJECT_ROOT/.autopilot/project/design.md"
    if [[ -f "$design_file" ]]; then
        design_content=$(head -100 "$design_file")
    fi

    mkdir -p "$PROJECT_ROOT/.autopilot"

    cat > "$STATE_FILE" <<EOF
---
active: true
phase: "qa"
gate: ""
iteration: 1
max_iterations: 10
max_retries: 2
retry_count: 0
mode: "project-qa"
brief_file: ""
next_task: ""
auto_approve: true
session_id: $session_id
started_at: "$(now_iso)"
---

## 目标
全项目集成 QA 验证：检查所有已完成任务的整体集成质量。

加载 .autopilot/project/design.md 作为设计参考。
加载 .autopilot/project/dag.yaml 了解任务拓扑。

## 设计文档
$design_content

## 任务完成摘要
$handoff_summary

## QA 报告
(待 qa 阶段填充)

## 变更日志
- [$(now_iso)] 全项目 QA 启动
EOF
}
