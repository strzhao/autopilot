#!/bin/bash

# autopilot 共享函数库
# setup.sh 和 stop-hook.sh 共用的 frontmatter 操作工具
#
# 使用方式：source lib.sh 后调用 init_paths [cwd]
# cwd 可选，传入时会 cd 到该目录再解析路径（解决 worktree 场景下 hook CWD 不可靠问题）

PROJECT_ROOT=""
STATE_FILE=""
TASK_DIR=""
WORKTREE_NAME=""

# 检测当前是否在 git worktree 中，返回 worktree 名称（目录名）
# 不在 worktree 中时返回空字符串
get_worktree_name() {
    if [[ -f "$PROJECT_ROOT/.git" ]]; then
        basename "$PROJECT_ROOT"
    fi
}

# 返回 active 指针文件路径（worktree 感知）
# 在 worktree 中：.autopilot/runtime/sessions/<name>/active.ptr
# 非 worktree：.autopilot/runtime/active.ptr
get_active_file() {
    local wt_name
    wt_name=$(get_worktree_name)
    if [[ -n "$wt_name" ]]; then
        echo "$PROJECT_ROOT/.autopilot/runtime/sessions/$wt_name/active.ptr"
    else
        echo "$PROJECT_ROOT/.autopilot/runtime/active.ptr"
    fi
}

init_paths() {
    local target_cwd="${1:-}"
    if [[ -n "$target_cwd" ]] && [[ -d "$target_cwd" ]]; then
        cd "$target_cwd" || return
    fi
    PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    WORKTREE_NAME=$(get_worktree_name)

    # 读取 active 指针定位状态文件（worktree 感知）
    local active_file
    active_file=$(get_active_file)
    if [[ -f "$active_file" ]]; then
        local slug
        slug=$(cat "$active_file")
        if [[ -n "$WORKTREE_NAME" ]]; then
            TASK_DIR="$PROJECT_ROOT/.autopilot/runtime/sessions/$WORKTREE_NAME/requirements/$slug"
        else
            TASK_DIR="$PROJECT_ROOT/.autopilot/runtime/requirements/$slug"
        fi
        STATE_FILE="$TASK_DIR/state.md"
    else
        # 向后兼容：无 active 指针时使用旧路径（仅非 worktree）
        # worktree 中不落到共享的 autopilot.local.md，避免跨 worktree 泄漏
        if [[ -z "$WORKTREE_NAME" ]]; then
            STATE_FILE="$PROJECT_ROOT/.autopilot/autopilot.local.md"
        else
            STATE_FILE=""
        fi
        TASK_DIR=""
    fi
}

parse_frontmatter() {
    [[ ! -f "$STATE_FILE" ]] && { echo ""; return; }
    sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE"
}

get_field() {
    local fm; fm=$(parse_frontmatter)
    # -m1：重复键（AI Edit 失误产生的 `gate: ""` 两行等）时确定性取第一行，
    # 杜绝多行值打断下游枚举比较。
    echo "$fm" | grep -m1 "^${1}:" | sed "s/${1}: *//" | sed 's/^"\(.*\)"$/\1/'
}

set_field() {
    local temp="${STATE_FILE}.tmp.$$"
    # Upsert 语义：键存在 → 替换首个匹配、删除后续同键行（写入即自愈重复键）；
    # 键缺失 → 在 frontmatter 闭合 --- 前追加一行（修复历史 no-op：初始 frontmatter
    # 不含 qa_scope 等字段时，旧实现静默吞掉写入，导致 fast_mode→smoke 降级从未生效）。
    # awk 用第一对 --- 界定 frontmatter，越过则原样输出（不动正文里形如 "phase: x" 的散文）。
    awk -v key="${1}" -v val="${2}" '
        BEGIN { infm=0; done_fm=0; seen=0 }
        /^---$/ {
            if (!infm && !done_fm) { infm=1; print; next }
            else if (infm) {
                # 闭合 frontmatter：键从未出现过 → 在此追加（upsert insert 分支）
                if (!seen) { print key ": " val; seen=1 }
                infm=0; done_fm=1; print; next
            }
        }
        infm && $0 ~ "^" key ": " {
            if (!seen) { print key ": " val; seen=1 }
            next
        }
        { print }
    ' "$STATE_FILE" > "$temp"
    mv "$temp" "$STATE_FILE"
}

# ── 枚举归一化工具 ────────────────────────────────────────────────
#
# normalize_enum_value <raw> → stdout
#   机械归一：lowercase + trim + 去外层引号 + 下划线→连字符。
#   纯函数，无副作用。空串输入输出空串（幂等）。
normalize_enum_value() {
    local raw="${1:-}"
    # 去掉前后空白
    local v
    v=$(printf '%s' "${raw}" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    # 去掉外层引号（单层，" 或 '）
    if [[ "${v:0:1}" == '"' ]] && [[ "${v: -1}" == '"' ]]; then
        v="${v:1:${#v}-2}"
    elif [[ "${v:0:1}" == "'" ]] && [[ "${v: -1}" == "'" ]]; then
        v="${v:1:${#v}-2}"
    fi
    # lowercase
    v=$(printf '%s' "${v}" | tr '[:upper:]' '[:lower:]')
    # 下划线 → 连字符
    v=$(printf '%s' "${v}" | tr '_' '-')
    printf '%s' "${v}"
}

# is_canonical <field> <value> → exit 0=命中闭集 / 1=越界
#   field 仅接受 5 个枚举字段，其余一律返回 1。
is_canonical() {
    local field="${1:-}"
    local value="${2:-}"
    case "${field}" in
        phase)
            case "${value}" in
                design|implement|qa|auto-fix|merge|done) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        gate)
            case "${value}" in
                ""|review-accept) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        mode)
            case "${value}" in
                ""|single|project|project-qa) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        qa_scope)
            case "${value}" in
                ""|smoke|selective) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        knowledge_extracted)
            case "${value}" in
                ""|true|skipped) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        *)
            return 1
            ;;
    esac
}

# get_enum_field <field> → stdout = normalize_enum_value "$(get_field "$field")"
#   读取 frontmatter 枚举字段并机械归一后输出。
get_enum_field() {
    local raw
    raw=$(get_field "${1}")
    normalize_enum_value "${raw}"
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

# ── 确定性硬信号原语 ──────────────────────────────────────────────

# freshness_check <product> <src_dir> → stdout: STALE | FRESH | UNKNOWN
#
# 判断构建产物相对于源码目录的新鲜度。
#   FRESH (rc0)  ：产物存在且产物中最新文件比 src_dir 所有源码都新（或一样新）
#   STALE (rc1)  ：src_dir 中存在任一文件比产物中最新文件更新
#   UNKNOWN (rc1)：产物路径不存在（无产物 → 不放行）
#
# 跨平台：禁用 `stat -f/-c`；用 `find -newer` + `ls -t`。
# 兼容编译型（二进制/bundle）与解释型（dist/ 目录）。
freshness_check() {
    local product="${1:-}"
    local src="${2:-}"
    local ref=""
    # 找产物中最新的文件作参照
    if [ -f "$product" ]; then
        ref="$product"
    elif [ -d "$product" ]; then
        ref=$(find "$product" -type f -print0 2>/dev/null | xargs -0 ls -1td 2>/dev/null | head -1)
    fi
    if [ -z "$ref" ] || [ ! -e "$ref" ]; then
        echo "UNKNOWN"
        return 1
    fi
    # 任一源码比产物参照新 → STALE
    if [ -n "$(find "$src" -type f -newer "$ref" -print -quit 2>/dev/null)" ]; then
        echo "STALE"
        return 1
    fi
    echo "FRESH"
    return 0
}

# lock_acceptance_tests <lock_file> <file...>
#
# 将指定验收测试文件的 sha256 写入锁文件（格式：每行 "<sha256>  <abs-path>"）。
# 幂等：重复调用会覆盖同一锁文件。锁文件仅在 runtime 目录（不入库）。
# 跨平台 sha256：sha256sum（Linux）或 shasum -a 256（macOS）。
lock_acceptance_tests() {
    local lock="${1:-}"
    shift
    [ -z "$lock" ] && return 0
    : > "$lock"
    local f
    for f in "$@"; do
        if command -v sha256sum >/dev/null 2>&1; then
            echo "$(sha256sum "$f" | awk '{print $1}')  $f" >> "$lock"
        else
            echo "$(shasum -a 256 "$f" | awk '{print $1}')  $f" >> "$lock"
        fi
    done
}

# acceptance_tests_tampered <lock_file>
#
# 校验锁文件中所有文件的 sha256 是否匹配。
# 退出码语义（双信号：rc + stdout 均可判断）：
#   0 = clean（所有文件 sha 匹配）
#   2 = tampered（任一文件 sha 变化或缺失）
#   1 = no-lock（锁文件不存在，自门控 no-op）
# tampered 时 stdout 含 "TAMPER(modified):" 或 "TAMPER(missing):" + 路径。
acceptance_tests_tampered() {
    local lock="${1:-}"
    [ -f "$lock" ] || return 1   # 无锁=未进入受保护期，自门控 no-op
    local bad=0
    local want path got line
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        # 锁格式 "<sha256>␣␣<path>"：按双空格切分，保留路径内空格（awk $2 会截断含空格路径）
        want="${line%%  *}"
        path="${line#*  }"
        [ -z "${want}" ] && continue
        if [ ! -f "${path}" ]; then
            echo "TAMPER(missing): ${path}"
            bad=1
            continue
        fi
        if command -v sha256sum >/dev/null 2>&1; then
            got=$(sha256sum "${path}" | awk '{print $1}')
        else
            got=$(shasum -a 256 "${path}" | awk '{print $1}')
        fi
        if [ "$got" != "$want" ]; then
            echo "TAMPER(modified): ${path}"
            bad=1
        fi
    done < "$lock"
    [ "$bad" -eq 1 ] && return 2
    return 0
}

# snapshot_oracle_regened → stdout: ORACLE-REGHEN(modified|deleted): <path>  （仅 tainted 时输出）
#
# 检测本轮快照 oracle 是否被重录（baseline 重录污染判别力）。
# 治 a56a55fe 实证：AI 删快照 baseline 重录后用 14/14 冒充 T1.5 谓词全 PASS，但从未启动 app。
#
# 信号：git diff（HEAD vs worktree）命中快照/baseline 文件改动（modified 或 deleted）。
#   路径模式覆盖 Jest __snapshots__/*.snap、Storybook/playwright 快照目录下 *.png|*.txt|*.yaml、
#   以及常见 baseline 目录（__Snapshots__、__snapshots__、e2e/snapshots、visual-report/snapshots）。
#
# 退出码语义（与 acceptance_tests_tampered 同构的双信号）：
#   0 = clean（无快照文件改动，或项目无快照类文件且 git diff 为空）
#   2 = tainted（检测到快照/baseline 改动或删除）
#   1 = n/a   （git 不可用 / 非仓库，自门控 no-op）
# tainted 时 stdout 列出被重录文件（每行一条 ORACLE-REGHEN 行），参照 TAMPER 文风。
snapshot_oracle_regened() {
    command -v git >/dev/null 2>&1 || return 1
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1

    # 快照/baseline 路径模式（n/a 自门控与 diff 检测共用；grep -E，路径含空格也按行匹配）
    local snapshot_re='(^|/)(__snapshots__|__Snapshots__|e2e/snapshots|tests/snapshots|tests/visual|visual-report/snapshots|storybook-static/snapshots)/|__snapshots__/.*\.snap$|\.snap$|\.baselines?/'

    # n/a 自门控：仓库无快照类文件（tracked + untracked）→ 不适用，no-op（rc=1）。
    # 治契约三态「项目无快照类文件 = n/a」——避免对纯后端/CLI 项目无意义运行。
    git ls-files --cached --others --exclude-standard 2>/dev/null | grep -qE "$snapshot_re" || return 1

    # 用 git status --porcelain -uall 抓 worktree 全部改动（modified/added/deleted/untracked）。
    # -uall 必需：默认 -unormal 对未跟踪目录只显示顶层目录名（?? e2e/），不展开到文件，
    # 会漏掉 e2e/snapshots/home.png 这类快照；-uall 展开到文件级。
    # 比 git diff HEAD 更全：重录常表现为「删旧 baseline + 建新 untracked」，diff 漏 untracked。
    local diff_out
    diff_out=$(git status --porcelain -uall 2>/dev/null) || diff_out=""
    [ -z "$diff_out" ] && return 0   # 无任何改动 → clean
    # porcelain v1：XY 两列状态码 + 路径（rename 形如 "R  old -> new"，取 new）。
    local xy path bad=0
    while IFS= read -r line; do
        xy="${line:0:2}"
        path="${line:3}"
        # rename/copy：取箭头后的新路径
        case "$path" in
            *" -> "*) path="${path##* -> }" ;;
        esac
        [ -z "$path" ] && continue
        # xy 两列任非空（含 ?? untracked / D 删除 / M 改 / A 新增 / R 重命名）即改动。
        # 空格+空格不会出现在 porcelain（无改动不入列表），此处只要路径命中快照模式即污染。
        if printf '%s' "$path" | grep -qE "$snapshot_re"; then
            # 判 deleted：第二列为 D（worktree 删除）或首列 D（staged 删除）
            if [[ "$xy" == *D* ]]; then
                echo "ORACLE-REGHEN(deleted): ${path}"
            else
                echo "ORACLE-REGHEN(modified): ${path}"
            fi
            bad=1
        fi
    done <<< "$diff_out"

    [ "$bad" -eq 1 ] && return 2
    return 0
}

# ── Task Slug 生成 ──────────────────────────────────────────────

# 生成需求管理文件夹的 slug。格式: YYYYMMDD-<目标前30字符清洗>
# 参数: goal (目标描述文本)
generate_task_slug() {
    local goal="$1"
    local date_prefix
    date_prefix=$(date +%Y%m%d)
    # 取前 30 字符，替换空格和特殊字符为连字符，去除尾部连字符
    local slug
    slug=$(printf '%.30s' "$goal" | tr ' /:*?"<>|\\' '-' | sed 's/-*$//' | sed 's/^-*//')
    # 空 slug 时使用时间戳
    if [[ -z "$slug" ]]; then
        slug="task-$(date +%H%M%S)"
    fi
    echo "${date_prefix}-${slug}"
}

# ── 需求管理路径设置 ────────────────────────────────────────────

# 创建 requirements 文件夹并设置 active 指针和路径变量（worktree 感知）。
# 参数: slug
# 副作用: 更新 TASK_DIR, STATE_FILE 全局变量；写入 active 指针
setup_requirement_dir() {
    local slug="$1"
    local active_file
    active_file=$(get_active_file)
    if [[ -n "$WORKTREE_NAME" ]]; then
        TASK_DIR="$PROJECT_ROOT/.autopilot/runtime/sessions/$WORKTREE_NAME/requirements/$slug"
    else
        TASK_DIR="$PROJECT_ROOT/.autopilot/runtime/requirements/$slug"
    fi
    mkdir -p "$TASK_DIR"
    mkdir -p "$(dirname "$active_file")"
    echo "$slug" > "$active_file"
    STATE_FILE="$TASK_DIR/state.md"
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
    /^[[:space:]]*(title|name):/ {
        gsub(/.*:[[:space:]]*"?/, ""); gsub(/".*/, ""); title=$0
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
        else if (all_done && n > 0) print "ALL_DONE"
    }' "$dag_file"
}

# ── Brief 模式状态文件创建 ────────────────────────────────────

# 为项目 DAG 中的任务创建 brief 模式状态文件。
# 参数: task_file session_id max_iterations max_retries auto_approve
# 注意: 调用前必须先通过 setup_requirement_dir 设置 STATE_FILE 和 TASK_DIR
create_brief_state_file() {
    local brief_file="$1"
    local session_id="${2:-}"
    local max_iterations="${3:-30}"
    local max_retries="${4:-3}"
    local auto_approve="${5:-false}"
    local html_review="${6:-false}"

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
    if [[ -f "$PROJECT_ROOT/.autopilot/knowledge/index.md" ]]; then
        knowledge_hint="
> 📚 项目知识库已存在: .autopilot/knowledge/。design 阶段请先加载相关知识上下文。"
    fi

    mkdir -p "$(dirname "$STATE_FILE")"

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
plan_mode: ""
brief_file: "$brief_file"
next_task: ""
auto_approve: $auto_approve
knowledge_extracted: ""
task_dir: "$TASK_DIR"
session_id: $session_id
started_at: "$(now_iso)"
contract_required: true
html_review: $html_review
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
# 注意: 调用前必须先通过 setup_requirement_dir 设置 STATE_FILE 和 TASK_DIR
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

    mkdir -p "$(dirname "$STATE_FILE")"

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
plan_mode: ""
brief_file: ""
next_task: ""
auto_approve: true
knowledge_extracted: ""
task_dir: "$TASK_DIR"
session_id: $session_id
started_at: "$(now_iso)"
contract_required: true
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
