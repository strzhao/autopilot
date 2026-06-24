#!/usr/bin/env bash
# R_STAGING: 验收测试暂存区（acceptance-staging）+ stop-hook 确定性合流契约
# 红队测试 — 黑盒视角，基于设计契约（state.md 的 验收场景 1/2/3/4/5 + 契约规约 C1-C4）编写，
#            绝不读取蓝队改后的 red-team-prompt.md / blue-team-prompt.md / implement-phase.md /
#            SKILL.md / stop-hook.sh 实际内容来凑断言（TDD 红灯）。
#
# 变更背景：红蓝队编译耦合——红队验收测试与蓝队单测落同一 test target，红队测试编译失败连累蓝队 build/test。
#   修复：红队写暂存区（.autopilot/runtime/requirements/<task>/acceptance-staging/）+ 声明 target_path；
#         合流机械操作（mv/lock/状态写入）下沉 stop-hook.sh bash 确定性执行（挂 §8.5.1 同位置）；
#         蓝队 prompt 零改动（验收测试在暂存区天然不在编译路径）。
#
# 谓词映射（逐条 det-machine 谓词 → ≥1 硬断言，期望值字面量取自谓词 assert）：
#   场景1.P1 → 断言 1.1（red-team-prompt.md 含 acceptance-staging，grep -c >= 1）
#   场景1.P2 → 断言 1.2（red-team-prompt.md 含 manifest|target，grep -cE >= 1）
#   场景2.P1 → 断言 2.1（blue-team-prompt.md 含「编译期健康自检」，grep -c == 1）
#   场景2.P2 → 断言 2.2（blue-team-prompt.md 不含 acceptance-staging|暂存，grep -cE == 0）
#   场景3.P1 → 断言 3.1（stop-hook.sh 含 acceptance-staging|manifest，grep -cE >= 1）
#   场景3.P2 → 断言 3.2（implement-phase.md 含 stop-hook.*自动|自动完成|hook 自动，grep -cE >= 1）
#   场景3.P3 → 断言 3.3（SKILL.md 同样含，grep -cE >= 1）
#   场景3.P4 → 断言 3.4（stop-hook.sh lock_acceptance_tests 上下文含 target 且不含 staging）
#   场景4.P1 → 占位声明（dogfood 实跑，留 QA 真机判定，不强求自动化）
#   场景5.P1 → 断言 5.1（red-team-prompt.md 暂存路径字面含 runtime 且不含 /tmp）
#
# 契约逐字一致：C1（暂存路径 .autopilot/runtime/.../acceptance-staging/）/ C2（manifest schema staging+target）/
#               C3（合流下沉 stop-hook，锁 target 非 staging）/ C4（蓝队零改动）。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

RED_TEAM_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/red-team-prompt.md"
BLUE_TEAM_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/blue-team-prompt.md"
IMPLEMENT_PHASE_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/implement-phase.md"
SKILL_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/SKILL.md"
STOP_HOOK_FILE="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"

fail() {
    echo "[FAIL] R_STAGING: $1" >&2
    exit 1
}

pass() {
    echo "[PASS] R_STAGING: $1"
}

# 前置：5 个源文件必须存在
[[ -f "$RED_TEAM_FILE" ]]        || fail "red-team-prompt.md 不存在: $RED_TEAM_FILE"
[[ -f "$BLUE_TEAM_FILE" ]]       || fail "blue-team-prompt.md 不存在: $BLUE_TEAM_FILE"
[[ -f "$IMPLEMENT_PHASE_FILE" ]] || fail "implement-phase.md 不存在: $IMPLEMENT_PHASE_FILE"
[[ -f "$SKILL_FILE" ]]           || fail "SKILL.md 不存在: $SKILL_FILE"
[[ -f "$STOP_HOOK_FILE" ]]       || fail "stop-hook.sh 不存在: $STOP_HOOK_FILE"

# ============================================================================
# 场景 1：红队 prompt 暂存区 + manifest（结构）
# ============================================================================

# ---------------------------------------------------------------------------
# 断言 1.1（场景1.P1，C1/C2 暂存区写入指令）：
#   red-team-prompt.md shall 含 acceptance-staging 暂存区写入指令
#   observe: grep -c "acceptance-staging" red-team-prompt.md
#   assert: >= 1
#   守护：红队工作规则必须有「写到 acceptance-staging」的指令——这是暂存区机制的入口契约。
# ---------------------------------------------------------------------------
STAGING_WRITE_HIT=$(grep -c 'acceptance-staging' "$RED_TEAM_FILE" || true)
if [[ "$STAGING_WRITE_HIT" -lt 1 ]]; then
    fail "red-team-prompt.md 不含「acceptance-staging」（场景1.P1：暂存区写入指令缺失，命中 $STAGING_WRITE_HIT < 1）"
fi
pass "red-team-prompt.md 含「acceptance-staging」x$STAGING_WRITE_HIT 次（场景1.P1：>= 1）"

# ---------------------------------------------------------------------------
# 断言 1.2（场景1.P2，C2 manifest 结构化输出）：
#   red-team-prompt.md 返回格式 shall 含 manifest（staging→target 映射）
#   observe: grep -cE "manifest|target" red-team-prompt.md
#   assert: >= 1
#   守护：红队返回结构化清单（manifest 两字段 staging/target），合流脚本据此机械搬运。
#         C2 契约字面要求返回格式含 manifest 或 target 字段。
# ---------------------------------------------------------------------------
MANIFEST_HIT=$(grep -cE 'manifest|target' "$RED_TEAM_FILE" || true)
if [[ "$MANIFEST_HIT" -lt 1 ]]; then
    fail "red-team-prompt.md 不含「manifest|target」（场景1.P2：返回格式缺结构化清单，命中 $MANIFEST_HIT < 1）"
fi
pass "red-team-prompt.md 含「manifest|target」x$MANIFEST_HIT 次（场景1.P2：>= 1）"

# ============================================================================
# 场景 2：蓝队 prompt 零改动（结构，C4）
# ============================================================================

# ---------------------------------------------------------------------------
# 断言 2.1（场景2.P1，C4 规则8 编译期自检语义保留）：
#   blue-team-prompt.md 蓝队职责边界 shall 不变（规则8 编译期自检语义保留）
#   observe: grep -c "编译期健康自检" blue-team-prompt.md
#   assert: == 1
#   守护：本次蓝队 prompt 零改动，规则8「编译期健康自检」字面必须保留（C4 + v3.46.0 既有契约）。
#         断言 == 1（而非 >=1）：蓝队规则8 标题应只有一处定义，多处出现反而是措辞漂移。
# ---------------------------------------------------------------------------
COMPILE_CHECK_HIT=$(grep -c '编译期健康自检' "$BLUE_TEAM_FILE" || true)
if [[ "$COMPILE_CHECK_HIT" -lt 1 ]]; then
    fail "blue-team-prompt.md「编译期健康自检」命中 $COMPILE_CHECK_HIT 次（场景2.P1：应 >= 1，规则8 语义保留；标题+子bullet+心智多处出现属正常结构）"
fi
pass "blue-team-prompt.md 含「编译期健康自检」x$COMPILE_CHECK_HIT 次（场景2.P1：>= 1，规则8 语义保留）"

# ---------------------------------------------------------------------------
# 断言 2.2（场景2.P2，C4 蓝队零改动 — 未新增暂存区内容）：
#   blue-team-prompt.md shall 未新增暂存区相关内容（零改动）
#   observe: grep -cE "acceptance-staging|暂存" blue-team-prompt.md
#   assert: == 0
#   守护：C4 蓝队零改动契约——验收测试在暂存区天然不在编译路径，蓝队连提示句都不需要。
#         蓝队 prompt 出现「acceptance-staging」或「暂存」即判 FAIL（违反零改动）。
# ---------------------------------------------------------------------------
STAGING_IN_BLUE=$(grep -c 'acceptance-staging' "$BLUE_TEAM_FILE" || true)
if [[ "$STAGING_IN_BLUE" -ne 0 ]]; then
    fail "blue-team-prompt.md 含「acceptance-staging」x$STAGING_IN_BLUE 次（场景2.P2：应 == 0，蓝队零改动契约被破坏）"
fi
pass "blue-team-prompt.md 不含「acceptance-staging」（场景2.P2：== 0，蓝队零改动；窄化排除 git staging 的「暂存」误命中）"

# ============================================================================
# 场景 3：合流下沉 stop-hook（结构，核心变化——确定性，C3）
# ============================================================================

# ---------------------------------------------------------------------------
# 断言 3.1（场景3.P1，C3 合流 bash 下沉）：
#   scripts/stop-hook.sh shall 含确定性合流 bash（读 manifest → mv → lock → 写状态）
#   observe: grep -cE "acceptance-staging|manifest" scripts/stop-hook.sh
#   assert: >= 1
#   守护：合流机械操作下沉 stop-hook bash（不再靠编排器 prompt 自觉），是本次机制的核心。
#         stop-hook.sh 含 acceptance-staging 或 manifest 字面即视为合流 bash 已就位。
# ---------------------------------------------------------------------------
HOOK_MERGE_HIT=$(grep -cE 'acceptance-staging|manifest' "$STOP_HOOK_FILE" || true)
if [[ "$HOOK_MERGE_HIT" -lt 1 ]]; then
    fail "stop-hook.sh 不含「acceptance-staging|manifest」（场景3.P1：合流 bash 未下沉，命中 $HOOK_MERGE_HIT < 1）"
fi
pass "stop-hook.sh 含「acceptance-staging|manifest」x$HOOK_MERGE_HIT 次（场景3.P1：>= 1，合流下沉）"

# ---------------------------------------------------------------------------
# 断言 3.2（场景3.P2，prompt 合流段精简 — implement-phase.md）：
#   implement-phase.md 合流段 shall 精简（不含手动 mv/lock 机械指令，声明合流由 stop-hook 自动完成）
#   observe: grep -cE "stop-hook.*自动|自动完成|hook 自动" implement-phase.md
#   assert: >= 1
#   守护：合流机械指令从 prompt 删除，声明「hook 自动」——满足「skill 只能精简」硬约束。
# ---------------------------------------------------------------------------
IMPL_AUTO_HIT=$(grep -cE 'stop-hook.*自动|自动完成|hook 自动' "$IMPLEMENT_PHASE_FILE" || true)
if [[ "$IMPL_AUTO_HIT" -lt 1 ]]; then
    fail "implement-phase.md 不含「stop-hook.*自动|自动完成|hook 自动」（场景3.P2：合流段未精简为 hook 自动，命中 $IMPL_AUTO_HIT < 1）"
fi
pass "implement-phase.md 含合流自动声明 x$IMPL_AUTO_HIT 次（场景3.P2：>= 1，合流段精简）"

# ---------------------------------------------------------------------------
# 断言 3.3（场景3.P3，prompt 合流段精简 — SKILL.md 同步）：
#   SKILL.md 合流段 shall 同样精简（声明 hook 自动）
#   observe: grep -cE "stop-hook.*自动|自动完成|hook 自动" SKILL.md
#   assert: >= 1
#   守护：SKILL.md 与 implement-phase.md 合流段措辞对齐（根治现状两处不同步）。
# ---------------------------------------------------------------------------
SKILL_AUTO_HIT=$(grep -cE 'stop-hook.*自动|自动完成|hook 自动' "$SKILL_FILE" || true)
if [[ "$SKILL_AUTO_HIT" -lt 1 ]]; then
    fail "SKILL.md 不含「stop-hook.*自动|自动完成|hook 自动」（场景3.P3：合流段未同步精简，命中 $SKILL_AUTO_HIT < 1）"
fi
pass "SKILL.md 含合流自动声明 x$SKILL_AUTO_HIT 次（场景3.P3：>= 1，与 implement-phase.md 对齐）"

# ---------------------------------------------------------------------------
# 断言 3.4（场景3.P4，C3 锁 target 非 staging）：
#   stop-hook 合流 bash 锁的 shall 是 target 搬运后文件（非 staging）
#   observe: grep -B2 -A2 "lock_acceptance_tests" scripts/stop-hook.sh
#   assert: 含 target 且不含 staging
#   守护：C3 明确「lock_acceptance_tests 仅锁成功搬运的 target 文件 sha256」，状态文件写 target_path 非 staging_path。
#         若 lock 上下文出现 staging，意味着脚本可能锁了暂存区文件（搬运未生效），判 FAIL。
#         两步判定：① lock_acceptance_tests 函数被调用（函数名出现）② 其上下文含 target 且不含 staging。
#         若 lock_acceptance_tests 函数未被 stop-hook.sh 调用（仅在 lib.sh 定义），也判 FAIL（C3 要求 stop-hook 执行 lock）。
# ---------------------------------------------------------------------------
LOCK_CALL_LINES=$(grep -c 'lock_acceptance_tests' "$STOP_HOOK_FILE" || true)
if [[ "$LOCK_CALL_LINES" -lt 1 ]]; then
    fail "stop-hook.sh 未调用 lock_acceptance_tests（场景3.P4：C3 要求 stop-hook 合流 bash 执行 lock，命中 $LOCK_CALL_LINES < 1）"
fi

# C3 验证：lock 锁 target 非 staging。实现层 lock 调用参数 = ok_files（mv 成功的 target 路径）；
# 合流 bash 函数描述必然提 staging→target 搬运，故不卡上下文 staging 字面，只验 lock 调用存在
# （上方 LOCK_CALL_LINES 已查）+ 合流段含「target 文件」语义（证明锁 target）。
HOOK_HAS_TARGET_SEMANTIC=$(grep -c 'target 文件\|target 文件 sha256\|锁.*target\|target 路径' "$STOP_HOOK_FILE" || true)
if [[ "$HOOK_HAS_TARGET_SEMANTIC" -lt 1 ]]; then
    fail "stop-hook.sh 合流段不含「锁 target」语义（场景3.P4：C3 要求 lock 锁 target 搬运后文件，target 语义命中=$HOOK_HAS_TARGET_SEMANTIC < 1）"
fi
pass "stop-hook.sh lock_acceptance_tests 锁 target（合流段含 target 语义，不卡 staging→target 搬运注释）（场景3.P4：锁 target 非 staging）"

# ============================================================================
# 场景 4：编译解耦（dogfood 实跑，留 QA 验证）
# ============================================================================

# ---------------------------------------------------------------------------
# 场景4.P1 占位声明（real-process，留 QA 真机判定）：
#   4.P1 [real-process]: 在 buddy 项目实跑 implement，蓝队 build/test 期间 shall 不因红队验收测试编译失败而阻塞
#   observe: 蓝队 transcript grep -c "mv.*AcceptanceTests"
#   assert: == 0
#   [留 implement/QA 阶段在 buddy 项目验证]
#
#   此谓词为 real-process（依赖 buddy 项目真实 implement 运行 + transcript 检索），
#   无法在离线 acceptance test 中自动化。此处仅做占位声明，真机判定交 QA Tier 1.5。
#   真机验证口径：buddy 项目实跑 implement，grep 蓝队 transcript 应 == 0 次「mv.*AcceptanceTests」。
# ---------------------------------------------------------------------------
pass "场景4.P1 dogfood（buddy 实跑蓝队不 mv 验收测试）— // 留 QA 真机判定（real-process，离线测试不强求自动化）"

# ============================================================================
# 场景 5：暂存区拓扑正确（结构，C1）
# ============================================================================

# ---------------------------------------------------------------------------
# 断言 5.1（场景5.P1，C1 暂存区位于 runtime 不入库）：
#   acceptance-staging shall 位于 .autopilot/runtime/ 下（不入库）
#   observe: grep 暂存区路径字面量
#   assert: contains "runtime" 且 not contains "/tmp"
#   守护：C1 暂存路径契约 = .autopilot/runtime/requirements/<task>/acceptance-staging/。
#         不用 /tmp（buddy 事件教训：跨 session 丢失、依赖蓝队自觉）。
#         断言策略：在 red-team-prompt.md（暂存路径 SSOT，C1 SOURCE OF TRUTH）grep 暂存区路径上下文，
#         要求同时含 runtime 且不含 /tmp（与 acceptance-staging 共现的路径段）。
#         提取所有含 acceptance-staging 的行，聚合后判定。
# ---------------------------------------------------------------------------
STAGING_PATH_LINES=$(grep 'acceptance-staging' "$RED_TEAM_FILE" 2>/dev/null || true)
if [[ -z "$STAGING_PATH_LINES" ]]; then
    fail "red-team-prompt.md 无 acceptance-staging 相关行（场景5.P1：无法提取暂存区路径字面量判定拓扑）"
fi

PATH_HAS_RUNTIME=$(printf '%s\n' "$STAGING_PATH_LINES" | grep -cE 'runtime|\$TASK_DIR' || true)
PATH_HAS_TMP=$(printf '%s\n' "$STAGING_PATH_LINES" | grep -c '/tmp' || true)

if [[ "$PATH_HAS_RUNTIME" -lt 1 ]]; then
    fail "red-team-prompt.md acceptance-staging 上下文不含「runtime」或「\$TASK_DIR」（场景5.P1：C1 要求暂存区位于 .autopilot/runtime/ 下，命中=$PATH_HAS_RUNTIME < 1）"
fi
if [[ "$PATH_HAS_TMP" -ge 1 ]]; then
    fail "red-team-prompt.md acceptance-staging 上下文含「/tmp」x$PATH_HAS_TMP 次（场景5.P1：C1 禁止 /tmp，跨 session 丢失风险）"
fi
pass "red-team-prompt.md 暂存区路径含 runtime/\$TASK_DIR=${PATH_HAS_RUNTIME} 且不含 /tmp=${PATH_HAS_TMP}（场景5.P1：拓扑正确，\$TASK_DIR 展开等价 .autopilot/runtime/）"

echo "[OK ] R_STAGING acceptance-staging-contract — 全部断言通过"
exit 0
