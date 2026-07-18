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

# detect_quantitative_tools → stdout JSON {stryker,c8,nyc,istanbul,jest_coverage}（5 bool），rc=0
#
# 检测当前项目是否具备 Tier 5 量化指标门禁所需工具（mutation / coverage）。
# 按子项独立检测（package.json 依赖 + config 文件存在），缺一不影响另一。
# SSOT：本函数是工具检测的唯一实现（qm.md §2 = 接口契约表格；doctor SKILL.md 引用本函数名）。
#
# 检测项：
#   strker       : package.json 含 @stryker-mutator/core 依赖 或 stryker.conf.{js,json,cjs,mjs}
#   c8           : package.json 含 c8 依赖 或 .c8rc* / package.json c8 字段
#   nyc          : package.json 含 nyc 依赖 或 .nycrc* / package.json nyc 字段
#   istanbul     : package.json 含 istanbul / istanbul-lib-coverage 依赖（独立检测，治 I4 欠拟合）
#   jest_coverage: package.json 含 jest/vitest 依赖 且（test script 含 --coverage 或 jest/vitest.config 含 collectCoverage）
#
# 错误契约（solve-don't-punt）：无 package.json / 无 config → 全 false（rc=0，不报错）。
# jq 优先输出 JSON；jq 缺失时降级手工拼 JSON 字面（不硬依赖 jq）。
detect_quantitative_tools() {
    local pkg="./package.json"
    local has_stryker=false has_c8=false has_nyc=false has_istanbul=false has_jest_cov=false
    local deps_text=""

    if [ -f "$pkg" ]; then
        # 提取 dependencies + devDependencies 文本块（grep -A 容错无块时返回空）
        deps_text=$(sed -n '/"dependencies"/,/^    }/p; /"devDependencies"/,/^    }/p' "$pkg" 2>/dev/null || true)
        # stryker
        if echo "$deps_text" | grep -qE '"@stryker-mutator/(core|jest-runner)"'; then
            has_stryker=true
        fi
        # c8
        if echo "$deps_text" | grep -qE '"c8"[[:space:]]*:'; then
            has_c8=true
        fi
        # nyc
        if echo "$deps_text" | grep -qE '"nyc"[[:space:]]*:'; then
            has_nyc=true
        fi
        # istanbul（独立检测，治 I4：istanbul / istanbul-lib-coverage / nyc 内嵌 istanbul 不算）
        if echo "$deps_text" | grep -qE '"istanbul(-lib-coverage|-reports)?"[[:space:]]*:'; then
            has_istanbul=true
        fi
        # jest_coverage / vitest coverage
        if echo "$deps_text" | grep -qE '"(jest|vitest)"[[:space:]]*:'; then
            # test script 含 --coverage 或 config 含 collectCoverage
            if grep -qE '"test".*--coverage' "$pkg" 2>/dev/null \
               || [ -n "$(compgen -G 'jest.config.*')" ] || [ -n "$(compgen -G 'vitest.config.*')" ] \
               && { grep -qE 'collectCoverage' jest.config.* vitest.config.* 2>/dev/null; }; then
                has_jest_cov=true
            fi
            # vitest 默认支持 coverage（有 vitest + 任意 vite/coverage 配置即视为可用）
            if echo "$deps_text" | grep -qE '"vitest"[[:space:]]*:'; then
                if grep -qE '"@vitest/coverage' "$pkg" 2>/dev/null \
                   || [ -n "$(compgen -G 'vitest.config.*')" ] \
                      && grep -qE 'coverage' vitest.config.* 2>/dev/null; then
                    has_jest_cov=true
                fi
            fi
        fi
    fi

    # config 文件兜底（无 package.json 依赖但 config 存在也算装了）
    if [ -n "$(compgen -G 'stryker.conf.*')" ]; then has_stryker=true; fi
    if [ -n "$(compgen -G '.c8rc*')" ]; then has_c8=true; fi
    if [ -n "$(compgen -G '.nycrc*')" ]; then has_nyc=true; fi

    if command -v jq >/dev/null 2>&1; then
        jq -n \
            --argjson stryker "$has_stryker" \
            --argjson c8 "$has_c8" \
            --argjson nyc "$has_nyc" \
            --argjson istanbul "$has_istanbul" \
            --argjson jest_coverage "$has_jest_cov" \
            '{stryker:$stryker,c8:$c8,nyc:$nyc,istanbul:$istanbul,jest_coverage:$jest_coverage}'
    else
        # grep 降级：手工拼 JSON（bool 字面无引号）
        printf '{"stryker":%s,"c8":%s,"nyc":%s,"istanbul":%s,"jest_coverage":%s}\n' \
            "$has_stryker" "$has_c8" "$has_nyc" "$has_istanbul" "$has_jest_cov"
    fi
    return 0
}

# tier5_coverage_check <coverage_summary.json> <changed_files_list>
#   → stdout JSON {line,branch,uncovered_critical:[{file,line}],passed}，rc=0
#
# 解析 istanbul/c8/vitest coverage-summary.json（业界标准 schema）。
# **file 级过滤**（治 I1）：只产出 changed_files_list 中的未覆盖行，非全量（全量=海量伪精度）。
# passed 按 §8 反向否决口径：uncovered_critical 空 → pass=true（覆盖率达标不作 PASS 信号，
# 唯一用途是反向否决：改动行有未覆盖 → pass=false）。总覆盖率 < 80% 不判 fail。
#
# 阈值（沿用 quantitative-metrics.md §1）：coverage_line_threshold=80, coverage_branch_threshold=70。
# 阈值仅用于参考产出（line/branch 数值），passed 判定只看 uncovered_critical。
#
# 错误契约：文件缺失/格式错 → {passed:false,uncovered_critical:[],line:null} rc=0（不抛错给编排器）。
tier5_coverage_check() {
    local cov_json="${1:-}"
    local changed_list="${2:-}"

    # fail-safe：文件缺失 → 空结果（rc=0）
    if [ -z "$cov_json" ] || [ ! -f "$cov_json" ]; then
        if command -v jq >/dev/null 2>&1; then
            jq -n '{line:null,branch:null,uncovered_critical:[],passed:false}'
        else
            printf '{"line":null,"branch":null,"uncovered_critical":[],"passed":false}\n'
        fi
        return 0
    fi

    # 解析总覆盖率（total 行）+ 按 changed_files 过滤未覆盖行
    local line_pct=null branch_pct=null
    local uncovered_json="[]"
    local jq_available=false
    command -v jq >/dev/null 2>&1 && jq_available=true

    if [ "$jq_available" = "true" ]; then
        # 总覆盖率（istanbul/c8/vitest summary 标准格式：total.lines.pct / total.branches.pct，复数）
        line_pct=$(jq -r '.total.lines.pct // empty' "$cov_json" 2>/dev/null || echo null)
        branch_pct=$(jq -r '.total.branches.pct // empty' "$cov_json" 2>/dev/null || echo null)
        [ -z "$line_pct" ] && line_pct=null
        [ -z "$branch_pct" ] && branch_pct=null

        # uncovered_critical：file 级过滤（summary 格式无行级 .s，按 lines.pct<100 判该文件有未覆盖）
        # 治 I1：只产 changed_files 中 pct<100 的文件（非全量）。契约 uncovered_critical=[{file}]（file 级）。
        # 容错：changed_list 参数可能是文件路径（红队 C4 传路径）或换行分隔内容字符串
        local f changed_content="$changed_list"
        if [[ -f "$changed_list" ]]; then
            changed_content=$(cat "$changed_list" 2>/dev/null || echo "")
        fi
        if [ -n "$changed_content" ]; then
            uncovered_json="[]"
            while IFS= read -r f; do
                [ -z "$f" ] && continue
                # 路径归一化：去前导 ./ （coverage key 通常是绝对/相对路径）
                f="${f#./}"
                # 在 coverage json 里找匹配该文件名的 key（容错路径前缀差异）
                local key pct
                key=$(jq -r --arg f "$f" 'to_entries | map(select(.key | endswith($f))) | .[0].key // empty' "$cov_json" 2>/dev/null || true)
                [ -z "$key" ] && continue
                # 该文件 lines.pct（summary 格式）；pct<100 → 有未覆盖 → 产 {file}
                pct=$(jq -r --arg k "$key" '.[$k].lines.pct // 100' "$cov_json" 2>/dev/null || echo 100)
                if [[ -n "$pct" ]] && [[ "$pct" =~ ^[0-9.]+$ ]] && awk "BEGIN{exit !($pct < 100)}" 2>/dev/null; then
                    uncovered_json=$(echo "$uncovered_json" | jq --arg f "$f" '. + [{file:$f}]')
                fi
            done <<< "$changed_content"
        fi

        # passed = uncovered_critical 为空（反向否决口径）；格式错（line_pct=null 解析失败）→ passed=false（错误契约，治 qa-reviewer Medium-1）
        local passed
        if [[ "$line_pct" == "null" ]]; then
            passed=false
        else
            passed=$(echo "$uncovered_json" | jq 'if length == 0 then true else false end')
        fi

        jq -n \
            --argjson line "$line_pct" \
            --argjson branch "$branch_pct" \
            --argjson uncovered "$uncovered_json" \
            --argjson passed "$passed" \
            '{line:$line,branch:$branch,uncovered_critical:$uncovered,passed:$passed}'
    else
        # grep 降级：无 jq 时尽力解析 total 行（istanbul/c8 格式 total": {"lines":{"pct":85}}，复数）
        line_pct=$(grep -oE '"total"[[:space:]]*:[[:space:]]*\{[^}]*"lines"[[:space:]]*:[[:space:]]*\{[^}]*"pct"[[:space:]]*:[[:space:]]*[0-9]+' "$cov_json" 2>/dev/null | grep -oE '"pct"[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1 || echo null)
        branch_pct=$(grep -oE '"total"[[:space:]]*:[[:space:]]*\{[^}]*"branches"[[:space:]]*:[[:space:]]*\{[^}]*"pct"[[:space:]]*:[[:space:]]*[0-9]+' "$cov_json" 2>/dev/null | grep -oE '"pct"[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1 || echo null)
        # grep 降级无法可靠做 file 级过滤 → uncovered_critical=[]（保守，passed=false）
        printf '{"line":%s,"branch":%s,"uncovered_critical":[],"passed":false}\n' "${line_pct:-null}" "${branch_pct:-null}"
    fi
    return 0
}

# tier5_mutation_check <mutation.json> → stdout JSON {kill_rate,killed,total_valid,survived_mutants[],passed}, rc=0
#
# 解析 stryker reports/mutation/mutation.json（metrics.killed / metrics.totalValid）。
# kill_rate = killed * 100 / total_valid（整数百分比），比 60 阈值 → passed。
# 阈值（沿用 quantitative-metrics.md §1）：mutation_threshold=60。
#
# survived_mutants[]：从 stryker mutation.json 的 files.<file>.mutants 中提取 status!=Killed 的条目
#   （含 Survived/NoCoverage/Timeout 等），产 {file,line,mutator}。
#
# 错误契约：文件缺失/格式错 → {kill_rate:null,killed:0,total_valid:0,survived_mutants:[],passed:false} rc=0。
tier5_mutation_check() {
    local mut_json="${1:-}"
    local threshold=60

    # fail-safe：文件缺失 → 空结果（rc=0）
    if [ -z "$mut_json" ] || [ ! -f "$mut_json" ]; then
        if command -v jq >/dev/null 2>&1; then
            jq -n '{kill_rate:null,killed:0,total_valid:0,survived_mutants:[],passed:false}'
        else
            printf '{"kill_rate":null,"killed":0,"total_valid":0,"survived_mutants":[],"passed":false}\n'
        fi
        return 0
    fi

    if command -v jq >/dev/null 2>&1; then
        local killed total_valid kill_rate passed survived
        killed=$(jq -r '.mutationMetrics // .metrics // {} | .killed // 0' "$mut_json" 2>/dev/null || echo 0)
        total_valid=$(jq -r '.mutationMetrics // .metrics // {} | .totalValid // 0' "$mut_json" 2>/dev/null || echo 0)
        # 兼容 stryker schema：顶层 .metrics.killed 或 .mutationMetrics.killed
        if [ "$killed" = "0" ] && [ "$total_valid" = "0" ]; then
            killed=$(jq -r '.metrics.killed // 0' "$mut_json" 2>/dev/null || echo 0)
            total_valid=$(jq -r '.metrics.totalValid // 0' "$mut_json" 2>/dev/null || echo 0)
        fi
        # 数值校验（防 null/字符串）
        [[ "$killed" =~ ^[0-9]+$ ]] || killed=0
        [[ "$total_valid" =~ ^[0-9]+$ ]] || total_valid=0

        if [ "$total_valid" -gt 0 ]; then
            kill_rate=$(( killed * 100 / total_valid ))
        else
            kill_rate=0
        fi
        if [ "$kill_rate" -ge "$threshold" ]; then
            passed=true
        else
            passed=false
        fi

        # survived_mutants：遍历 files.<file>.mutants[]，status != Killed
        survived=$(jq -r '
            (.files // {}) | to_entries | map(
                .key as $file | .value.mutants // [] | map(
                    select(.status != "Killed") | {file:$file, line:(.location.start.line // 0), mutator:(.mutatorName // .mutator // "unknown")}
                )
            ) | add // []
        ' "$mut_json" 2>/dev/null || echo "[]")

        jq -n \
            --argjson kr "$kill_rate" \
            --argjson k "$killed" \
            --argjson tv "$total_valid" \
            --argjson surv "$survived" \
            --argjson passed "$passed" \
            '{kill_rate:$kr,killed:$k,total_valid:$tv,survived_mutants:$surv,passed:$passed}'
    else
        # grep 降级：尽力提取 metrics.killed / totalValid（格式 "killed": 60, "totalValid": 100）
        local killed total_valid kill_rate
        killed=$(grep -oE '"killed"[[:space:]]*:[[:space:]]*[0-9]+' "$mut_json" 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo 0)
        total_valid=$(grep -oE '"totalValid"[[:space:]]*:[[:space:]]*[0-9]+' "$mut_json" 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo 0)
        [[ "$killed" =~ ^[0-9]+$ ]] || killed=0
        [[ "$total_valid" =~ ^[0-9]+$ ]] || total_valid=0
        if [ "$total_valid" -gt 0 ]; then
            kill_rate=$(( killed * 100 / total_valid ))
        else
            kill_rate=0
        fi
        local passed=false
        [ "$kill_rate" -ge "$threshold" ] && passed=true
        printf '{"kill_rate":%s,"killed":%s,"total_valid":%s,"survived_mutants":[],"passed":%s}\n' \
            "$kill_rate" "$killed" "$total_valid" "$passed"
    fi
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
    local snapshot_re='(^|/)(__snapshots__|__Snapshots__|__screenshots__|e2e/snapshots|tests/snapshots|tests/visual|cypress/snapshots|visual-report/snapshots|storybook-static/snapshots|snapshots)/|(^|/)[^/]*-snapshots/|__snapshots__/.*\.snap$|\.snap$|\.baselines?/'

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

# validate_predicate_driver <state_file>
#
# 校验 ## 验收场景 谓词的 driver 字段与观测语义一致性（反向判定）。
# 治编排器用 node-script 驱动冒充网络/外部依赖观测：node-script 不得跑
# curl/fetch/playwright/overmind/pylon/mysql，须改用对应真实驱动类型。
#
# 谓词格式（fullwidth ｜ 分隔，见 scenario-generator-prompt.md）：
#   - **<id> [channel]** <描述> ｜ observe: <观测> ｜ assert: <DbC> ｜ driver: <type>:<target> ｜ artifact: <path>
#
# 退出码语义（与 acceptance_tests_tampered / snapshot_oracle_regened 同构的双信号）：
#   0 = 合规（有谓词且有 driver 字段，无违规）
#   2 = 违规（driver type=node-script 但描述或观测含网络/外部依赖关键字）
#   1 = no-op（## 验收场景 无谓词，或谓词全无 driver 字段）
# 违规时 stdout 含 "PRED-DRIVER-VIOLATION: <id> <reason>"，参照 TAMPER/ORACLE-REGHEN 文风。
validate_predicate_driver() {
    local state_file="${1:-}"
    [ -f "$state_file" ] || return 1
    local rc=0 out
    out=$(awk '
        BEGIN { in_scn = 0; bad = 0; saw_pred = 0; saw_driver = 0 }
        /^## 验收场景[[:space:]]*$/ { in_scn = 1; next }
        in_scn && /^## / { in_scn = 0 }
        in_scn && /^[[:space:]]*-[[:space:]]/ {
            saw_pred = 1
            line = $0
            # 提取 id（首个 ** ** 内文本，去 [channel]）
            id = ""
            if (match(line, /\*\*[^*]+\*\*/)) {
                id = substr(line, RSTART+2, RLENGTH-4)
                sub(/[[:space:]]*\[.*$/, "", id)
                gsub(/[[:space:]]/, "", id)
            }
            # 提取 driver type（driver: <type>:<target>，type 为首个 : 之前）
            driver_type = ""
            if (match(line, /driver:[[:space:]]*/)) {
                saw_driver = 1
                rest = substr(line, RSTART + RLENGTH)
                if (match(rest, /^[^:]+/)) {
                    driver_type = substr(rest, RSTART, RLENGTH)
                    gsub(/[[:space:]]/, "", driver_type)
                }
            }
            # 反向判定：node-script 驱动 + 网络/外部依赖关键字 → 违规
            if (driver_type == "node-script") {
                # description = id 粗体闭合后到首个 ｜
                desc = ""
                if (match(line, /\*\*/)) {
                    after = substr(line, RSTART + RLENGTH)
                    if (match(after, /\*\*/)) {
                        after2 = substr(after, RSTART + RLENGTH)
                        if (match(after2, /｜/)) {
                            desc = substr(after2, 1, RSTART - 1)
                        } else {
                            desc = after2
                        }
                    }
                }
                # observe = observe: 后到首个 ｜
                observe = ""
                if (match(line, /observe:[[:space:]]*/)) {
                    after = substr(line, RSTART + RLENGTH)
                    if (match(after, /｜/)) {
                        observe = substr(after, 1, RSTART - 1)
                    } else {
                        observe = after
                    }
                }
                blob = tolower(desc " " observe)
                if (blob ~ /(curl|fetch|playwright|overmind|pylon|mysql)/) {
                    print "PRED-DRIVER-VIOLATION: " id " driver=node-script 但描述/观测含网络或外部依赖关键字（须改用 curl/playwright 等真实驱动类型）"
                    bad = 1
                }
            }
        }
        END {
            if (bad) exit 2
            else if (!saw_driver) exit 1
            else exit 0
        }
    ' "$state_file") || rc=$?
    [ -n "$out" ] && printf '%s\n' "$out"
    case "$rc" in
        2) return 2 ;;
        1) return 1 ;;
        *) return 0 ;;
    esac
}

# validate_predicate_artifacts <state_file>
#
# 校验 ## 验收场景 谓词声明的 artifact 路径真实存在且非空（方案 A 确定性路径）。
# 治编排器用 mock 单测输出冒充 Tier 1.5 真实产物：artifact 字段填
# /tmp/autopilot-artifacts/<pred-id>.out，编排器 QA 时写入，stop-hook §5.7 校验存在性。
# 不依赖 ## QA 报告（v3.37+ 已不持久化）。
#
# 退出码语义（与 acceptance_tests_tampered 同构的双信号）：
#   0 = 合规（全部 artifact 存在且非空，或谓词全无 artifact 字段）
#   2 = 缺失（任一 artifact 文件不存在或大小为 0）
#   1 = no-op（## 验收场景 无谓词）
# 缺失时 stdout 含 "PRED-ARTIFACT-MISSING: <id> <path>"，参照 TAMPER 文风。
validate_predicate_artifacts() {
    local state_file="${1:-}"
    [ -f "$state_file" ] || return 1
    local saw_pred=0 bad=0
    local tag id artifact
    while IFS=$'\t' read -r tag id artifact; do
        case "$tag" in
            NOPRED) continue ;;
            ART)
                saw_pred=1
                [ -n "$artifact" ] || continue
                if [[ -f "$artifact" ]] && [[ "$(wc -c < "$artifact" 2>/dev/null)" -gt 0 ]]; then
                    :
                else
                    echo "PRED-ARTIFACT-MISSING: ${id} ${artifact}"
                    bad=1
                fi
                ;;
        esac
    done < <(awk '
        BEGIN { in_scn = 0; saw_pred = 0 }
        /^## 验收场景[[:space:]]*$/ { in_scn = 1; next }
        in_scn && /^## / { in_scn = 0 }
        in_scn && /^[[:space:]]*-[[:space:]]/ {
            saw_pred = 1
            line = $0
            id = ""
            if (match(line, /\*\*[^*]+\*\*/)) {
                id = substr(line, RSTART+2, RLENGTH-4)
                sub(/[[:space:]]*\[.*$/, "", id)
                gsub(/[[:space:]]/, "", id)
            }
            artifact = ""
            if (match(line, /artifact:[[:space:]]*/)) {
                rest = substr(line, RSTART + RLENGTH)
                if (match(rest, /｜/)) {
                    artifact = substr(rest, 1, RSTART - 1)
                } else {
                    artifact = rest
                }
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", artifact)
            }
            print "ART\t" id "\t" artifact
        }
        END {
            if (!saw_pred) print "NOPRED\t\t"
        }
    ' "$state_file") || true

    if [ "$saw_pred" -eq 0 ]; then return 1; fi
    [ "$bad" -eq 1 ] && return 2
    return 0
}

# compute_file_hash <file>
#
# 跨平台文件 MD5（C6）。Linux md5sum 输出 "<hash>  <file>"，macOS md5 -q 直接出 hash。
# 文件不存在或哈希失败 → 返回空串（调用方自行判存在性）。
compute_file_hash() {
    local f="${1:-}"
    [ -f "$f" ] || return 0
    if command -v md5sum >/dev/null 2>&1; then
        md5sum "$f" 2>/dev/null | awk '{print $1}'
    else
        md5 -q "$f" 2>/dev/null
    fi
}

# validate_predicate_channels <state_file>
#
# 校验 ## 验收场景 谓词的 [channel] 合法性。合法集 = {det-machine, real-process, visual-residue}
# （SSOT: scenario-generator-prompt.md:42）。治 AI 自创 [human-obs] 等标签豁免 GUI 谓词。
#
# 退出码语义（与 validate_predicate_driver 同构的双信号）：
#   0 = 合规（全 channel ∈ 合法集）
#   2 = 违规（任一 channel 非法，如 human-obs）
#   1 = no-op（## 验收场景 无谓词）
# 违规时 stdout 含 "PRED-CHANNEL-ILLEGAL: <id> <channel>"。
validate_predicate_channels() {
    local state_file="${1:-}"
    [ -f "$state_file" ] || return 1
    local rc=0 out
    out=$(awk '
        BEGIN { in_scn = 0; bad = 0; saw_pred = 0 }
        /^## 验收场景[[:space:]]*$/ { in_scn = 1; next }
        in_scn && /^## / { in_scn = 0 }
        in_scn && /^[[:space:]]*-[[:space:]]/ {
            saw_pred = 1
            line = $0
            # channel = 首个粗体内 [channel]（与 id 共处 ** <id> [channel] **）
            chan = ""
            if (match(line, /\*\*[^*]+\*\*/)) {
                bold = substr(line, RSTART, RLENGTH)
                if (match(bold, /\[([a-z][a-z0-9-]*)\]/)) {
                    chan = substr(bold, RSTART+1, RLENGTH-2)
                }
            }
            if (chan != "" \
                && chan != "det-machine" \
                && chan != "real-process" \
                && chan != "visual-residue") {
                id = bold
                sub(/^\*\*/, "", id); sub(/\*\*.*$/, "", id)
                sub(/[[:space:]]*\[.*$/, "", id)
                gsub(/[[:space:]]/, "", id)
                print "PRED-CHANNEL-ILLEGAL: " id " " chan
                bad = 1
            }
        }
        END {
            if (bad) exit 2
            else if (!saw_pred) exit 1
            else exit 0
        }
    ' "$state_file") || rc=$?
    [ -n "$out" ] && printf '%s\n' "$out"
    case "$rc" in
        2) return 2 ;;
        1) return 1 ;;
        *) return 0 ;;
    esac
}

# validate_predicate_coverage <state_file>
#
# 校验 ## 验收场景 [visual-residue] 谓词须有 artifact 字段（C5 收紧口径）。
# det-machine/real-process 谓词由 validate_predicate_driver 兜底，不强制 artifact（兼容 ACC-GUARD-30）。
# 治 AI 把 GUI 谓词从非法 channel 改标合法 visual-residue 继续逃避 artifact 产出。
#
# 退出码语义：
#   0 = 合规（visual-residue 谓词全有 artifact）
#   2 = 违规（任一 visual-residue 谓词缺 artifact）
#   1 = no-op（无 visual-residue 谓词，或 ## 验收场景 无谓词）
# 违规时 stdout 含 "PRED-COVERAGE-GAP: <id> 无 artifact"。
validate_predicate_coverage() {
    local state_file="${1:-}"
    [ -f "$state_file" ] || return 1
    local rc=0 out
    out=$(awk '
        BEGIN { in_scn = 0; bad = 0; saw_pred = 0; saw_visual = 0 }
        /^## 验收场景[[:space:]]*$/ { in_scn = 1; next }
        in_scn && /^## / { in_scn = 0 }
        in_scn && /^[[:space:]]*-[[:space:]]/ {
            saw_pred = 1
            line = $0
            chan = ""
            if (match(line, /\*\*[^*]+\*\*/)) {
                bold = substr(line, RSTART, RLENGTH)
                if (match(bold, /\[([a-z][a-z0-9-]*)\]/)) {
                    chan = substr(bold, RSTART+1, RLENGTH-2)
                }
            }
            if (chan == "visual-residue") {
                saw_visual = 1
                has_art = (line ~ /artifact:[[:space:]]*[^[:space:]]/)
                if (!has_art) {
                    id = bold
                    sub(/^\*\*/, "", id); sub(/\*\*.*$/, "", id)
                    sub(/[[:space:]]*\[.*$/, "", id)
                    gsub(/[[:space:]]/, "", id)
                    print "PRED-COVERAGE-GAP: " id " 无 artifact"
                    bad = 1
                }
            }
        }
        END {
            if (bad) exit 2
            else if (!saw_visual) exit 1
            else exit 0
        }
    ' "$state_file") || rc=$?
    [ -n "$out" ] && printf '%s\n' "$out"
    case "$rc" in
        2) return 2 ;;
        1) return 1 ;;
        *) return 0 ;;
    esac
}

# _get_md5 <row>
# 内部 helper：从 "<id>\t<path>\t<md5>" 行取 md5（最后一个 tab 之后字段）。避免 IFS 重读副作用。
_get_md5() {
    local row="$1"
    printf '%s' "${row##*$'\t'}"
}

# validate_predicate_artifact_uniqueness <state_file>
#
# 校验 ## 验收场景 artifact 路径不同但 MD5 相同 → 违规（C6）。路径相同 = 显式共用命令输出 → 允许。
# 治 AI 用一张截图复制 7 份（MD5 全同）冒充 7 个独立 visual-residue artifact。
# 跨平台 MD5 经 compute_file_hash（md5sum/md5 -q 双探测）。
#
# 退出码语义：
#   0 = 合规（artifact 路径全唯一、或路径不同但内容不同、或显式共用同路径）
#   2 = 违规（≥2 谓词 artifact 路径不同但 MD5 相同）
#   1 = no-op（无谓词、或谓词全无 artifact、或 artifact 文件全不存在）
# 违规时 stdout 含 "PRED-ARTIFACT-DUP: <id1> <id2> <md5>"（首个冲突对）。
validate_predicate_artifact_uniqueness() {
    local state_file="${1:-}"
    [ -f "$state_file" ] || return 1
    local tmp
    tmp=$(mktemp -t pred-art.XXXXXX) || return 1
    # 阶段1：awk 抽 (id<TAB>artifact_path)，仅记非空路径
    awk '
        BEGIN { in_scn = 0 }
        /^## 验收场景[[:space:]]*$/ { in_scn = 1; next }
        in_scn && /^## / { in_scn = 0 }
        in_scn && /^[[:space:]]*-[[:space:]]/ {
            line = $0
            id = ""; artifact = ""
            if (match(line, /\*\*[^*]+\*\*/)) {
                id = substr(line, RSTART+2, RLENGTH-4)
                sub(/[[:space:]]*\[.*$/, "", id)
                gsub(/[[:space:]]/, "", id)
            }
            if (match(line, /artifact:[[:space:]]*/)) {
                rest = substr(line, RSTART + RLENGTH)
                if (match(rest, /｜/)) {
                    artifact = substr(rest, 1, RSTART - 1)
                } else {
                    artifact = rest
                }
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", artifact)
            }
            if (id != "" && artifact != "") {
                print id "\t" artifact
            }
        }
    ' "$state_file" > "$tmp"

    # 阶段2：算每个 artifact 的 MD5（compute_file_hash 跨平台）
    local id path md5
    local -a rows=()
    while IFS=$'\t' read -r id path; do
        [ -f "$path" ] || continue   # 缺失由 validate_predicate_artifacts 兜底，此函数只查重复
        md5=$(compute_file_hash "$path")
        [ -z "$md5" ] && continue
        rows+=("${id}"$'\t'"${path}"$'\t'"${md5}")
    done < "$tmp"
    rm -f "$tmp"

    # 无有效 artifact 行 → no-op
    [ "${#rows[@]}" -eq 0 ] && return 1

    # 阶段3：按 MD5 分组找首个「路径不同但 MD5 相同」对
    local i j ri_id ri_path ri_md5 rj_id rj_path
    for ((i=0; i<${#rows[@]}; i++)); do
        IFS=$'\t' read -r ri_id ri_path ri_md5 <<< "${rows[$i]}"
        for ((j=i+1; j<${#rows[@]}; j++)); do
            IFS=$'\t' read -r rj_id rj_path _ <<< "${rows[$j]}"
            if [[ "$ri_md5" == "$(_get_md5 "${rows[$j]}")" ]] && [[ "$ri_path" != "$rj_path" ]]; then
                echo "PRED-ARTIFACT-DUP: ${ri_id} ${rj_id} ${ri_md5}"
                return 2
            fi
        done
    done
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
    slug=$(printf '%.30s' "$goal" | tr " /:*?\"<>|\\" '-' | sed 's/-*$//' | sed 's/^-*//')
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

# 从 dag.yaml 读指定 task id 的 brief 字段值（显式文件指针，相对 PROJECT_ROOT 或绝对路径）。
# 无 brief 字段返回空（调用方回退 tasks/<id>.md）。纯函数无副作用。
#
# 用下一个 `- id:` 作 task 边界收集 brief，避免字段顺序（id,name,brief）导致提前 print
# 丢 brief（v3.54.1 迁移脚本 read IFS bug 教训）。
get_task_brief() {
    local dag_file="$1" task_id="$2"
    [[ ! -f "$dag_file" ]] && return
    # 注意：awk 的 exit 会触发 END 块，须用 done 哨卫防止重复 print。
    awk -v tid="$task_id" '
        /^[[:space:]]*-[[:space:]]*id:/ {
            if (matched && brief != "") { print brief; done = 1; exit }
            matched = 0; brief = ""
            in_task = 1
            sub(/^[[:space:]]*-?[[:space:]]*id:[[:space:]]*/, ""); gsub(/^["'"'"']/, ""); gsub(/["'"'"']$/, "")
            if ($0 == tid) matched = 1
            next
        }
        matched && in_task && /^[[:space:]]*brief:/ {
            sub(/^[[:space:]]*brief:[[:space:]]*/, ""); gsub(/^["'"'"']/, ""); gsub(/["'"'"']$/, ""); brief = $0
            next
        }
        END { if (!done && matched && brief != "") print brief }
    ' "$dag_file"
}

# ── Brief 模式状态文件创建 ────────────────────────────────────

# 为项目 DAG 中的任务创建 brief 模式状态文件。
# 参数: task_file session_id max_iterations max_retries auto_approve(默认 true)
# 注意: auto_approve 默认 true——brief 函数唯一用途是项目子任务，全部调用方需 true。
# 注意: 调用前必须先通过 setup_requirement_dir 设置 STATE_FILE 和 TASK_DIR
create_brief_state_file() {
    local brief_file="$1"
    local session_id="${2:-}"
    local max_iterations="${3:-30}"
    local max_retries="${4:-3}"
    local auto_approve="${5:-true}"
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
        # dep brief 字段优先（显式文件指针），回退 ${dep}.handoff.md（v3.54.0 兼容）
        local _dep_brief
        _dep_brief=$(get_task_brief "$PROJECT_ROOT/.autopilot/project/dag.yaml" "$dep" 2>/dev/null || true)
        if [[ -n "$_dep_brief" ]]; then
            local _dep_brief_abs
            case "$_dep_brief" in
                /*) _dep_brief_abs="$_dep_brief" ;;
                *)  _dep_brief_abs="$PROJECT_ROOT/$_dep_brief" ;;
            esac
            handoff="${_dep_brief_abs%.md}.handoff.md"
        else
            handoff="$brief_dir/${dep}.handoff.md"
        fi
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

# ── Dim 13: AI 可观测性/调试友好度探测（doctor Wave 1 客观层） ────────────
#
# 契约（state.md C1）：
#   detect_tech_stack <dir>         → rc=0 + stdout JSON {node,swift,go,python,rust,java,primary}
#   detect_ai_observability <dir>   → rc=0 + stdout JSON {struct_log,log_rotation,cli_diagnostic,
#                                     health_json,cache_clean,debug_switch} 各 {status,value}
#                                     status ∈ {pass,warn,na}
#   6 个私有 _ai_*_detect <dir>     → rc ∈ {0=pass, 1=na 自门控, 2=warn 缺失}
#                                     + stdout `AI-OBS-<DIM>-<STATE>:` 信号
#                                     <DIM>   ∈ {STRUCT-LOG, LOG-ROTATION, CLI-DIAGNOSTIC,
#                                                HEALTH-JSON, CACHE-CLEAN, DEBUG-SWITCH}
#                                     <STATE> ∈ {PASS, NA, MISSING, PARTIAL}
#
# 不变量：
#   - 纯 bash：禁 node/python/python3/npx/cargo/go run（约束守卫.P4）
#   - solve-don't-punt：无标志文件 → 各维 na（rc=1），不抛错、不崩溃
#   - 跨平台：复用既有 find/ls/grep 模式，无 stat -f/-c
#   - 性能：所有 grep/find 限定 maxdepth + 排除产物目录（.git/node_modules/.build/.next/dist/build）

# _ai_grep_src <pattern> <dir>
#   统一源码 grep（性能：exclude-dir 排除产物目录，比 find -not -path 快 ~1000x）。
#   返回首个命中文件路径（head -1），无命中则空。退出码恒为 0（调用方判空串）。
_ai_grep_src() {
    local pat="$1" dir="$2"
    grep -rEl \
        --include='*.swift' --include='*.ts' --include='*.tsx' --include='*.js' \
        --include='*.jsx' --include='*.go' --include='*.py' --include='*.rs' --include='*.java' \
        --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=.build \
        --exclude-dir=.next --exclude-dir=dist --exclude-dir=build --exclude-dir=target \
        --exclude-dir=.venv --exclude-dir=__pycache__ --exclude-dir=.pytest_cache \
        --exclude-dir=.cache --exclude-dir=out --exclude-dir=homebrew \
        --exclude-dir=.swiftpm --exclude-dir=DerivedData --exclude-dir=coverage \
        -E "$pat" "$dir" 2>/dev/null \
        | grep -vE 'node_modules|/\.git/|/\.build/|/\.next/|/dist/|/build/|\.test\.|__tests__|/tests/|/BuddyCoreTests/|/__mocks__/' \
        | head -1
}

# detect_tech_stack <dir> → rc=0 + stdout JSON {node,swift,go,python,rust,java,primary}
#
# 通用技术栈识别（package.json/Info.plist/go.mod/pyproject.toml/Cargo.toml/pom.xml/build.gradle）。
# 函数化 doctor Step 0 现有内联规则表（净减 SKILL.md 行）。
# primary 取首个命中（优先级：swift→node→go→rust→python→java，全无则 unknown）——
#   Swift 桌面 app 优先于 node 前端（monorepo 如 claude-code-buddy primary=swift）。
# 错误契约：目录不存在/无任何标志 → 全 false + primary="unknown"（rc=0，solve-don't-punt）。
detect_tech_stack() {
    local dir="${1:-.}"
    local node=false swift=false go=false python=false rust=false java=false
    [ -d "$dir" ] || dir="."
    # 直接根目录标志文件（快速路径）
    [ -f "$dir/package.json" ] && node=true
    [ -f "$dir/Package.swift" ] && swift=true
    [ -f "$dir/go.mod" ] && go=true
    [ -f "$dir/Cargo.toml" ] && rust=true
    [ -f "$dir/pyproject.toml" ] || [ -f "$dir/setup.py" ] || [ -f "$dir/requirements.txt" ] && python=true
    [ -f "$dir/pom.xml" ] || [ -f "$dir/build.gradle" ] || [ -f "$dir/build.gradle.kts" ] && java=true
    # 子目录兜底（monorepo apps/<x>/Package.swift、apps/<x>/package.json）
    if [ "$swift" = "false" ] && [ -n "$(find "$dir" -maxdepth 3 \( -name Package.swift -o -name Info.plist \) -print -quit 2>/dev/null)" ]; then
        swift=true
    fi
    if [ "$node" = "false" ] && [ -n "$(find "$dir" -maxdepth 3 -name package.json -print -quit 2>/dev/null)" ]; then
        # 排除 node_modules 误判
        local nf
        nf=$(find "$dir" -maxdepth 3 -name package.json -not -path '*/node_modules/*' -print -quit 2>/dev/null)
        [ -n "$nf" ] && node=true
    fi
    if [ "$go" = "false" ] && [ -n "$(find "$dir" -maxdepth 3 -name go.mod -print -quit 2>/dev/null)" ]; then
        go=true
    fi
    if [ "$rust" = "false" ] && [ -n "$(find "$dir" -maxdepth 3 -name Cargo.toml -print -quit 2>/dev/null)" ]; then
        rust=true
    fi
    if [ "$python" = "false" ] && [ -n "$(find "$dir" -maxdepth 2 -name pyproject.toml -print -quit 2>/dev/null)" ]; then
        python=true
    fi
    if [ "$java" = "false" ] && [ -n "$(find "$dir" -maxdepth 3 -name pom.xml -print -quit 2>/dev/null)" ]; then
        java=true
    fi
    # primary 优先级（Swift 桌面 > node 前端：buddy monorepo primary 应为 swift）
    local primary="unknown"
    if [ "$swift" = "true" ]; then primary="swift"
    elif [ "$node" = "true" ]; then primary="node"
    elif [ "$go" = "true" ]; then primary="go"
    elif [ "$rust" = "true" ]; then primary="rust"
    elif [ "$python" = "true" ]; then primary="python"
    elif [ "$java" = "true" ]; then primary="java"
    fi
    printf '{"node":%s,"swift":%s,"go":%s,"python":%s,"rust":%s,"java":%s,"primary":"%s"}\n' \
        "$node" "$swift" "$go" "$python" "$rust" "$java" "$primary"
    return 0
}

# _ai_struct_log_detect <dir> → rc ∈ {0,1,2} + stdout `AI-OBS-STRUCT-LOG-<STATE>:`
#
# 结构化日志维度（客观）：JSONL/JSON 日志文件 + env 级别变量。
#   PASS    (rc0)：JSONL/JSON 日志文件存在 ∧ env 级别变量（LOG_LEVEL/BUDDY_LOG_LEVEL/...）存在
#   PARTIAL (rc2)：仅一项存在
#   MISSING (rc2)：两项全无
#   NA      (rc1)：目录不存在
# _ai_has_source <dir> → 0=有源码/标志（.swift/.ts/.js/.go/.py/.rs/.java 或 package.json）/ 1=无（纯脚本）
# 子探测器自门控：无源码 → 各维 na（rc=1），对齐契约 C1 solve-don't-punt。
_ai_has_source() {
    local dir="${1:-.}"
    [ -d "$dir" ] || return 1
    if [ -n "$(find "$dir" -maxdepth 4 -type f \
        \( -name '*.swift' -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
           -o -name '*.go' -o -name '*.py' -o -name '*.rs' -o -name '*.java' \) \
        -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/.build/*' \
        -not -path '*/.next/*' -not -path '*/dist/*' -not -path '*/build/*' \
        -print -quit 2>/dev/null)" ]; then
        return 0
    fi
    [ -f "$dir/package.json" ] && return 0
    return 1
}

_ai_struct_log_detect() {
    local dir="${1:-.}"
    [ -d "$dir" ] || { echo "AI-OBS-STRUCT-LOG-NA: no dir"; return 1; }
    _ai_has_source "$dir" || { echo "AI-OBS-STRUCT-LOG-NA: no source code"; return 1; }
    # JSONL/JSON 日志文件（项目源码，maxdepth=4 + 排除产物目录）
    local jsonl_hit=""
    jsonl_hit=$(find "$dir" -maxdepth 4 -type f \
        \( -name "*.jsonl" -o -name "app.log" -o -name "access.log" \) \
        -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.build/*' \
        -not -path '*/.next/*' -not -path '*/dist/*' -not -path '*/build/*' \
        -print -quit 2>/dev/null)
    # 业界约定：~/.<ns>/logs/<ns>-*.jsonl（buddy/sentry/pino 等）
    # 目录 basename 可能含 "-cli"/"-code" 后缀（claude-code-buddy → buddy）；多候选尝试
    local ns="" home_logs=""
    local bn
    bn=$(basename "$dir" 2>/dev/null)
    # 候选命名空间：全名 / 去前缀（x-foo → foo）/ 去后缀（foo-cli → foo / foo-bar → bar）
    for ns in "$bn" "${bn#*-}" "${bn%-*}" "${bn%%-*}"; do
        [ -z "$ns" ] && continue
        [ -d "$HOME/.${ns}/logs" ] || continue
        home_logs=$(find "$HOME/.${ns}/logs" -maxdepth 1 -name "*.jsonl" -print -quit 2>/dev/null)
        [ -n "$home_logs" ] && break
    done
    # env 级别变量（源码引用 LOG_LEVEL/<NS>_LOG_LEVEL）
    local env_hit=""
    env_hit=$(_ai_grep_src 'LOG_LEVEL|BUDDY_LOG_LEVEL|NS_LOG_LEVEL|LOGGING_LEVEL|LogLevel\.' "$dir")
    # 源码结构化日志 writer 实现（buddy LogConfig / pino / winston / structlog / FileHandler 等）
    # 项目实现了结构化日志写入（即便运行时产物落在 ~/.<ns>/ 不在项目目录）+ env 级别控制 → PASS
    local writer_hit=""
    writer_hit=$(_ai_grep_src 'LogConfig|Logger\.write|FileLog|JSONL|jsonl|os_log|pino|winston|structlog|logging\.getLogger|RotatingFile|FileHandler' "$dir")
    local have_log=false have_env=false
    { [ -n "$jsonl_hit" ] || [ -n "$home_logs" ] || [ -n "$writer_hit" ]; } && have_log=true
    [ -n "$env_hit" ] && have_env=true
    if [ "$have_log" = "true" ] && [ "$have_env" = "true" ]; then
        echo "AI-OBS-STRUCT-LOG-PASS: source=${jsonl_hit:-${home_logs:-none}} writer=$writer_hit env=$env_hit"
        return 0
    fi
    if [ "$have_log" = "true" ] || [ "$have_env" = "true" ]; then
        echo "AI-OBS-STRUCT-LOG-PARTIAL: log=$have_log env=$have_env"
        return 2
    fi
    echo "AI-OBS-STRUCT-LOG-MISSING: no jsonl no env-level"
    return 2
}

# _ai_log_rotation_detect <dir> → rc + stdout `AI-OBS-LOG-ROTATION-<STATE>:`
#
# 日志轮转维度（客观）：配置/代码含大小或数量上限。
_ai_log_rotation_detect() {
    local dir="${1:-.}"
    [ -d "$dir" ] || { echo "AI-OBS-LOG-ROTATION-NA: no dir"; return 1; }
    _ai_has_source "$dir" || { echo "AI-OBS-LOG-ROTATION-NA: no source code"; return 1; }
    local hit_size="" hit_count=""
    hit_size=$(_ai_grep_src 'rotateSize|rotateSizeBytes|maxFileSize|maxSizeBytes|maxBytes|logSizeLimit|MaxFileSize' "$dir")
    hit_count=$(_ai_grep_src 'retainMaxArchives|maxArchives|retainTotalSize|maxFiles|retainCount|filesToKeep' "$dir")
    if [ -n "$hit_size" ] && [ -n "$hit_count" ]; then
        echo "AI-OBS-LOG-ROTATION-PASS: size=$hit_size count=$hit_count"
        return 0
    fi
    if [ -n "$hit_size" ] || [ -n "$hit_count" ]; then
        echo "AI-OBS-LOG-ROTATION-PARTIAL: size=${hit_size:-none} count=${hit_count:-none}"
        return 2
    fi
    echo "AI-OBS-LOG-ROTATION-MISSING: no size/count cap"
    return 2
}

# _ai_cli_diagnostic_detect <dir> → rc + stdout `AI-OBS-CLI-DIAGNOSTIC-<STATE>:`
#
# CLI 诊断命令维度（客观）：bin/scripts/package.json scripts 含 health/log/diagnose/doctor/status/info。
_ai_cli_diagnostic_detect() {
    local dir="${1:-.}"
    [ -d "$dir" ] || { echo "AI-OBS-CLI-DIAGNOSTIC-NA: no dir"; return 1; }
    _ai_has_source "$dir" || { echo "AI-OBS-CLI-DIAGNOSTIC-NA: no source code"; return 1; }
    # package.json scripts（根 + monorepo apps/packages）
    local npm_hit=""
    if [ -f "$dir/package.json" ]; then
        npm_hit=$(grep -oE '"(health|log|logs|diagnose|doctor|status|info|report)"[[:space:]]*:' "$dir/package.json" 2>/dev/null | head -3 | tr '\n' ',')
    fi
    if [ -z "$npm_hit" ]; then
        local sub f
        sub=$(find "$dir" -maxdepth 3 -name package.json -not -path '*/node_modules/*' -print 2>/dev/null)
        for f in $sub; do
            npm_hit=$(grep -oE '"(health|log|logs|diagnose|doctor|status|info|report)"[[:space:]]*:' "$f" 2>/dev/null | head -3 | tr '\n' ',')
            [ -n "$npm_hit" ] && break
        done
    fi
    # 源码 CLI 子命令分发模式（case "health"|cmdHealth|healthCmd）
    local cli_hit=""
    cli_hit=$(_ai_grep_src 'cmdHealth|healthCmd|case[[:space:]]*"health"|func[[:space:]]+health|Command\.(health|log|status)' "$dir")
    if [ -n "$npm_hit" ] || [ -n "$cli_hit" ]; then
        echo "AI-OBS-CLI-DIAGNOSTIC-PASS: npm=$npm_hit cli=$cli_hit"
        return 0
    fi
    echo "AI-OBS-CLI-DIAGNOSTIC-MISSING: no health/log/diagnose/doctor/status/info subcommand"
    return 2
}

# _ai_health_json_detect <dir> → rc + stdout `AI-OBS-HEALTH-JSON-<STATE>:`
#
# health JSON 维度（客观）：health 命令或 /health 路由存在 + 输出 jq 可解析。
_ai_health_json_detect() {
    local dir="${1:-.}"
    [ -d "$dir" ] || { echo "AI-OBS-HEALTH-JSON-NA: no dir"; return 1; }
    _ai_has_source "$dir" || { echo "AI-OBS-HEALTH-JSON-NA: no source code"; return 1; }
    # health 入口：CLI health 子命令 / /health 或 /api/health 路由 / healthCmd 函数
    local entry_hit=""
    entry_hit=$(_ai_grep_src 'cmdHealth|healthCmd|case[[:space:]]*"health"|func[[:space:]]+health|/api/health' "$dir")
    # npm scripts.health（package.json health script 也算 health 命令入口）
    local npm_health=""
    [ -f "$dir/package.json" ] && npm_health=$(grep -E '"health"[[:space:]]*:' "$dir/package.json" 2>/dev/null)
    [ -n "$npm_health" ] && entry_hit="${entry_hit:+$entry_hit }npm:$npm_health"
    # 路由文件：app/api/health/route.{ts,js}
    local route_hit=""
    route_hit=$(find "$dir" -maxdepth 5 -path '*api/health*' -name 'route.*' -not -path '*/node_modules/*' -print -quit 2>/dev/null)
    if [ -z "$entry_hit" ] && [ -z "$route_hit" ]; then
        echo "AI-OBS-HEALTH-JSON-MISSING: no health entry"
        return 2
    fi
    # jq 可解析输出：源码含 status/healthy JSON 字段或 --json flag
    local json_hit=""
    json_hit=$(_ai_grep_src '"status"[[:space:]]*:|--json|JSON\.stringify|jsonOutput|jsonEncode' "$dir")
    if [ -n "$json_hit" ]; then
        echo "AI-OBS-HEALTH-JSON-PASS: entry=${entry_hit:-$route_hit} json=$json_hit"
        return 0
    fi
    echo "AI-OBS-HEALTH-JSON-PARTIAL: entry=${entry_hit:-$route_hit} no-json-output"
    return 2
}

# _ai_cache_clean_detect <dir> → rc + stdout `AI-OBS-CACHE-CLEAN-<STATE>:`
#
# 缓存清理维度（客观）：scripts 含 clean/purge/prune/cache 子命令或对应 npm/Makefile script。
_ai_cache_clean_detect() {
    local dir="${1:-.}"
    [ -d "$dir" ] || { echo "AI-OBS-CACHE-CLEAN-NA: no dir"; return 1; }
    _ai_has_source "$dir" || { echo "AI-OBS-CACHE-CLEAN-NA: no source code"; return 1; }
    local npm_hit=""
    if [ -f "$dir/package.json" ]; then
        npm_hit=$(grep -oE '"(clean|purge|prune|clean:[a-z:]*|cache:clean|clean:cache|clear-cache)"[[:space:]]*:' "$dir/package.json" 2>/dev/null | head -3 | tr '\n' ',')
    fi
    if [ -z "$npm_hit" ]; then
        local sub f
        sub=$(find "$dir" -maxdepth 3 -name package.json -not -path '*/node_modules/*' -print 2>/dev/null)
        for f in $sub; do
            npm_hit=$(grep -oE '"(clean|purge|prune|clean:[a-z:]*|cache:clean|clear-cache)"[[:space:]]*:' "$f" 2>/dev/null | head -3 | tr '\n' ',')
            [ -n "$npm_hit" ] && break
        done
    fi
    # Makefile clean target
    local mk_hit=""
    if [ -f "$dir/Makefile" ] || [ -f "$dir/apps/desktop/Makefile" ]; then
        mk_hit=$(grep -hE '^[a-z_-]*clean[a-z_-]*:' "$dir/Makefile" "$dir/apps/desktop/Makefile" 2>/dev/null | head -1)
    fi
    # scripts/ 目录
    local sh_hit=""
    sh_hit=$(find "$dir/scripts" -maxdepth 2 -type f \( -name "clean*" -o -name "purge*" -o -name "prune*" \) -print -quit 2>/dev/null)
    if [ -n "$npm_hit" ] || [ -n "$mk_hit" ] || [ -n "$sh_hit" ]; then
        echo "AI-OBS-CACHE-CLEAN-PASS: npm=$npm_hit mk=$mk_hit sh=$sh_hit"
        return 0
    fi
    echo "AI-OBS-CACHE-CLEAN-MISSING: no clean/purge/prune/cache script"
    return 2
}

# _ai_debug_switch_detect <dir> → rc + stdout `AI-OBS-DEBUG-SWITCH-<STATE>:`
#
# debug 开关维度（客观）：LOG_LEVEL/DEBUG/<NS>_LOG_LEVEL env 或 #if DEBUG 配置存在。
_ai_debug_switch_detect() {
    local dir="${1:-.}"
    [ -d "$dir" ] || { echo "AI-OBS-DEBUG-SWITCH-NA: no dir"; return 1; }
    _ai_has_source "$dir" || { echo "AI-OBS-DEBUG-SWITCH-NA: no source code"; return 1; }
    local env_hit=""
    env_hit=$(_ai_grep_src 'BUDDY_LOG_LEVEL|LOG_LEVEL|LOGGING_LEVEL|env\.(DEBUG|LOG_LEVEL)' "$dir")
    local flag_hit=""
    flag_hit=$(_ai_grep_src '#if[[:space:]]+DEBUG|#if[[:space:]]+!DEBUG|process\.env\.NODE_ENV|isProduction|isDebug' "$dir")
    if [ -n "$env_hit" ] || [ -n "$flag_hit" ]; then
        echo "AI-OBS-DEBUG-SWITCH-PASS: env=$env_hit flag=$flag_hit"
        return 0
    fi
    echo "AI-OBS-DEBUG-SWITCH-MISSING: no LOG_LEVEL/DEBUG/#if DEBUG switch"
    return 2
}

# detect_ai_observability <dir> → rc=0 + stdout JSON
#   {struct_log,log_rotation,cli_diagnostic,health_json,cache_clean,debug_switch}
#   每项 {status, value}，status ∈ {pass, warn, na}
#
# 统一入口（doctor Wave 1 单次调用），按技术栈调度 6 客观子探测器。
# 聚合规则：子探测器 rc=0 → pass / rc=1 → na / rc=2 → warn；value 取 stdout 信号（去 PREFIX）。
# 自门控（solve-don't-punt）：纯脚本项目（无任何源码文件）→ 6 维全 na，不抛错（边界情形.P1）。
detect_ai_observability() {
    local dir="${1:-.}"
    [ -d "$dir" ] || dir="."
    local dims=("struct_log" "log_rotation" "cli_diagnostic" "health_json" "cache_clean" "debug_switch")
    local fns=("_ai_struct_log_detect" "_ai_log_rotation_detect" "_ai_cli_diagnostic_detect" \
               "_ai_health_json_detect" "_ai_cache_clean_detect" "_ai_debug_switch_detect")
    # 自门控：纯脚本项目（无源码 + 无 package.json）→ 6 维全 na（复用 _ai_has_source，DRY）
    if ! _ai_has_source "$dir"; then
        printf '{"struct_log":{"status":"na","value":"no source code"},"log_rotation":{"status":"na","value":"no source code"},"cli_diagnostic":{"status":"na","value":"no source code"},"health_json":{"status":"na","value":"no source code"},"cache_clean":{"status":"na","value":"no source code"},"debug_switch":{"status":"na","value":"no source code"}}\n'
        return 0
    fi
    local pairs=""
    local i
    for i in 0 1 2 3 4 5; do
        local out=""
        local rc=0
        local st=""
        local value=""
        out=$("${fns[$i]}" "$dir" 2>/dev/null) || rc=$?
        case "$rc" in
            0) st="pass" ;;
            1) st="na" ;;
            *) st="warn" ;;
        esac
        # value = 去掉 PREFIX（"AI-OBS-<DIM>-<STATE>:"）的部分；若无分隔则整行
        value="${out#*:}"
        value="${value#"${value%%[![:space:]]*}"}"  # 去前导空格
        [ -z "$value" ] && value="$out"
        # JSON 安全：转义双引号/反斜杠
        value=${value//\\/\\\\}
        value=${value//\"/\\\"}
        local pair="\"${dims[$i]}\":{\"status\":\"$st\",\"value\":\"$value\"}"
        if [ -z "$pairs" ]; then
            pairs="$pair"
        else
            pairs="$pairs,$pair"
        fi
    done
    printf '{%s}\n' "$pairs"
    return 0
}
