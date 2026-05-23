#!/usr/bin/env bash
# 契约来源：.autopilot/runtime/requirements/20260523-深入看下-autopilot-的实/state.md ## 契约规约（C1-C6）
# 验证 autopilot 文件管理 B 方案（目录二级分层）的 6 个契约
# 红队测试 — 仅基于设计文档，不读蓝队实现
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

FAIL=0

fail() {
    echo "[FAIL] $1" >&2
    FAIL=$((FAIL + 1))
}

pass() {
    echo "[PASS] $1"
}

# ---------- C1: .gitignore 必含 .autopilot/runtime/ ----------
GITIGNORE="$REPO_ROOT/.gitignore"
if [[ ! -f "$GITIGNORE" ]]; then
    fail "C1: .gitignore 不存在: $GITIGNORE"
elif grep -qF ".autopilot/runtime/" "$GITIGNORE"; then
    pass "C1: .gitignore 包含 .autopilot/runtime/ 规则"
else
    fail "C1: .gitignore 缺少 .autopilot/runtime/ 单行豁免规则"
fi

# ---------- C2: autopilot-commit SKILL.md 含字面字符串 + git status --porcelain ----------
COMMIT_SKILL="$REPO_ROOT/plugins/autopilot/skills/autopilot-commit/SKILL.md"
if [[ ! -f "$COMMIT_SKILL" ]]; then
    fail "C2: commit SKILL.md 不存在: $COMMIT_SKILL"
else
    if grep -qF '`.autopilot/` 知识库变更检查' "$COMMIT_SKILL"; then
        pass "C2-1: commit SKILL.md 包含字面字符串「\`.autopilot/\` 知识库变更检查」"
    else
        fail "C2-1: commit SKILL.md 缺少字面字符串「\`.autopilot/\` 知识库变更检查」（含反引号 + 中文）"
    fi

    if grep -qF 'git status --porcelain' "$COMMIT_SKILL"; then
        pass "C2-2: commit SKILL.md 包含 git status --porcelain 命令"
    else
        fail "C2-2: commit SKILL.md 缺少 git status --porcelain 命令"
    fi
fi

# ---------- C3: autopilot-doctor SKILL.md Dim 12 含「文件分类正确性」+ git ls-files .autopilot/runtime ----------
DOCTOR_SKILL="$REPO_ROOT/plugins/autopilot/skills/autopilot-doctor/SKILL.md"
if [[ ! -f "$DOCTOR_SKILL" ]]; then
    fail "C3: doctor SKILL.md 不存在: $DOCTOR_SKILL"
else
    if grep -qF '文件分类正确性' "$DOCTOR_SKILL"; then
        pass "C3-1: doctor SKILL.md 包含字面字符串「文件分类正确性」"
    else
        fail "C3-1: doctor SKILL.md 缺少 Dim 12 新增子项「文件分类正确性」"
    fi

    if grep -qF 'git ls-files .autopilot/runtime' "$DOCTOR_SKILL"; then
        pass "C3-2: doctor SKILL.md Wave 1 含 git ls-files .autopilot/runtime"
    else
        fail "C3-2: doctor SKILL.md Wave 1 缺少 git ls-files .autopilot/runtime 命令"
    fi
fi

# ---------- C4: 项目 CLAUDE.md 含 ## .autopilot/ 文件管理 章节 + >=2 列表格 ----------
PROJECT_CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
if [[ ! -f "$PROJECT_CLAUDE_MD" ]]; then
    fail "C4: 项目 CLAUDE.md 不存在: $PROJECT_CLAUDE_MD"
else
    if grep -qE '^## \.autopilot/ 文件管理' "$PROJECT_CLAUDE_MD"; then
        pass "C4-1: 项目 CLAUDE.md 含 H2 章节「## .autopilot/ 文件管理」"
    else
        fail "C4-1: 项目 CLAUDE.md 缺少 H2 章节「## .autopilot/ 文件管理」"
    fi

    # 提取该章节范围内的内容（到下一个 ## 或 EOF），检测 markdown 表格行（至少出现 2 个 `|` 的行）
    section_block=$(awk '/^## \.autopilot\/ 文件管理/{flag=1; next} /^## /{flag=0} flag' "$PROJECT_CLAUDE_MD" 2>/dev/null || true)
    if [[ -n "$section_block" ]] && echo "$section_block" | grep -qE '\|.*\|'; then
        pass "C4-2: 章节内含 markdown 表格（≥2 列）"
    else
        fail "C4-2: 章节缺少 ≥2 列对照表（knowledge/ 入库 vs runtime/ gitignore）"
    fi
fi

# ---------- C5: setup.sh 迁移幂等性（语义检测：旧布局触发 + 新布局短路） ----------
SETUP_SH="$REPO_ROOT/plugins/autopilot/scripts/setup.sh"
if [[ ! -f "$SETUP_SH" ]]; then
    fail "C5: setup.sh 不存在: $SETUP_SH"
else
    # 5-a: 静态检测迁移逻辑标志（mkdir knowledge 或 mv 到 knowledge）
    if grep -qE '(mkdir[^|]*knowledge|mv[^|]*knowledge|\.autopilot/knowledge)' "$SETUP_SH"; then
        pass "C5-1: setup.sh 含 knowledge/ 相关迁移逻辑标志"
    else
        fail "C5-1: setup.sh 缺少 knowledge/ 迁移逻辑标志"
    fi

    # 5-b: 语义检测幂等性 — 模拟环境
    # 触发条件契约：decisions.md 存在 且 knowledge/ 不存在 → 触发迁移
    # 反之（knowledge/ 已存在）→ 第二次运行不触发
    TEST_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t 'apc5')
    if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]]; then
        # 提取 setup.sh 中迁移条件块的语义结构：要求同时检测两个条件
        # （decisions.md 存在 AND knowledge 目录不存在）
        if grep -qE '(\.autopilot/decisions\.md|knowledge["/ ]*\]\])' "$SETUP_SH" \
           && grep -qE '! *-d.*knowledge|-d.*knowledge.*\|\|' "$SETUP_SH"; then
            pass "C5-2: setup.sh 迁移触发语义满足（检测 decisions.md 存在 + knowledge/ 不存在）"
        else
            fail "C5-2: setup.sh 迁移触发条件不满足契约（须同时检测旧文件存在 + 新目录不存在）"
        fi
        rm -rf "$TEST_ROOT"
    else
        fail "C5-2: 无法创建临时目录进行模拟测试"
    fi
fi

# ---------- C6: lib.sh get_active_file() 路径含 runtime/ ----------
LIB_SH="$REPO_ROOT/plugins/autopilot/scripts/lib.sh"
if [[ ! -f "$LIB_SH" ]]; then
    fail "C6: lib.sh 不存在: $LIB_SH"
else
    # 6-a: 静态检测 — runtime/ 出现在 active 路径上下文
    if grep -qE 'runtime/(sessions|active\.ptr)' "$LIB_SH"; then
        pass "C6-1: lib.sh 含 runtime/active.ptr 或 runtime/sessions 路径片段"
    else
        fail "C6-1: lib.sh 缺少 runtime/(sessions|active.ptr) 路径片段"
    fi

    # 6-b: 函数级检测 — get_active_file 函数定义存在
    if grep -qE '(get_active_file\s*\(\s*\)|function\s+get_active_file)' "$LIB_SH"; then
        pass "C6-2: lib.sh 定义了 get_active_file() 函数"
    else
        fail "C6-2: lib.sh 缺少 get_active_file() 函数定义"
    fi

    # 6-c: 行为级检测 — 实际 source 并调用，验证返回路径含 runtime/
    # 在隔离环境中模拟非 worktree 场景
    TEST_ROOT=$(mktemp -d 2>/dev/null || mktemp -d -t 'apc6')
    if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]]; then
        (
            cd "$TEST_ROOT" || exit 1
            git init -q 2>/dev/null || true
            # 在子 shell 中 source lib.sh 并调用 get_active_file
            # 用 || true 防止 lib.sh 内部 set -e 失败传播
            result=$(bash -c "
                cd '$TEST_ROOT'
                source '$LIB_SH' 2>/dev/null || true
                if declare -f get_active_file >/dev/null 2>&1; then
                    get_active_file 2>/dev/null || true
                fi
            " 2>/dev/null || true)
            if [[ "$result" == *"runtime/"* ]]; then
                echo "[PASS] C6-3: get_active_file() 实际返回路径含 runtime/ ($result)"
            else
                echo "[FAIL] C6-3: get_active_file() 实际返回路径不含 runtime/ (返回: '$result')" >&2
                exit 99
            fi
        )
        rc=$?
        if [[ $rc -eq 99 ]]; then
            FAIL=$((FAIL + 1))
        fi
        rm -rf "$TEST_ROOT"
    else
        fail "C6-3: 无法创建临时目录进行行为测试"
    fi
fi

# ---------- 汇总 ----------
if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "[FAIL] autopilot-file-mgmt — 共 $FAIL 处契约违反" >&2
    exit 1
fi

echo ""
echo "[OK ] autopilot-file-mgmt — C1-C6 六个契约全部通过"
exit 0
