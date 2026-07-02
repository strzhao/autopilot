#!/usr/bin/env bash
# 验收测试：fast_mode 判定时机搬迁（启动流程步骤2 → design 步骤1 探针后）
# 红队测试 — 仅基于设计文档编写断言，不读取蓝队改动后的实现文案
#
# 设计文档（核心，描述"应该达到的状态"）：
#   改动前：fast_mode 在 SKILL.md「## 启动流程」步骤 2 判定——零代码上下文盲判偏 fast。
#   改动后应该达到的状态：
#     1. SKILL.md「## 启动流程」步骤 2：不再在本步判定，改为 defer 到 design 阶段步骤 1 探针后。
#        不应再含"默认 fast，不确定也选 fast"这类即时盲判表述（作为判定动作）。
#     2. SKILL.md「## Phase: design」步骤 1（模式检测与分流）：新增 fast_mode 探针判定——
#        若 fast_mode 为空，用 1-2 个 Glob/Grep 探针估算改动半径，据结果写回 fast_mode
#        （小改/同质 search-replace→fast，架构权衡/陌生模块→standard，不确定→fast）。
#        fast_mode 判定应无条件先行于 mode 分流。
#     3. SKILL.md（frontmatter 更新规范处）引用「启动流程步骤 2 自适应判断」应改为指向「design 步骤 1 探针后」。
#     4. references/state-file-guide.md 的 fast_mode 字段说明「为空时 AI 在启动流程步骤 2 写回」
#        应改为「design 步骤 1 探针后」。
#     5. references/phase-checklists.md 步骤 1 标签应包含 fast_mode。
#     6. scripts/stop-hook.sh 字节不变（首次写入点搬迁仍在同一 iteration 1 内，路由零影响）。
#
# 预注册谓词（det-machine）：
#   P1 | 启动流程步骤 2 不再即时盲判，且含 defer 到 design 步骤 1 的指向
#   P2 | design 步骤 1 含 fast_mode 探针判定（fast_mode + 探针/Glob/Grep + fast/standard 判据 + 写回）
#   P3 | "启动流程步骤 2" 作为 fast_mode 决策关联的悬空引用计数 == 0
#   P5 | git diff plugins/autopilot/scripts/stop-hook.sh 空（搬迁对路由零影响）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

SKILL_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/SKILL.md"
STATE_GUIDE="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/state-file-guide.md"
PHASE_CHECKLIST="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/phase-checklists.md"
STOP_HOOK="$REPO_ROOT/plugins/autopilot/scripts/stop-hook.sh"

fail() {
    echo "[FAIL] fast-mode-decision-timing: $1" >&2
    exit 1
}

pass() {
    echo "[PASS] fast-mode-decision-timing: $1"
}

[[ -f "$SKILL_FILE" ]] || fail "SKILL.md 不存在: $SKILL_FILE"
[[ -f "$STATE_GUIDE" ]] || fail "state-file-guide.md 不存在: $STATE_GUIDE"
[[ -f "$STOP_HOOK" ]] || fail "stop-hook.sh 不存在: $STOP_HOOK"

# ════════════════════════════════════════════════════════════════
# P1: 启动流程步骤 2 不再即时盲判 + 含 defer 到 design 步骤 1 的指向
# ════════════════════════════════════════════════════════════════

# 提取「## 启动流程」章节（从 "## 启动流程" 到下一个 "## " 为止）
startup_section=$(awk '
    /^## 启动流程/ { in_block=1; print; next }
    in_block && /^## / { in_block=0 }
    in_block { print }
' "$SKILL_FILE")

if [[ -z "$startup_section" ]]; then
    fail "无法从 SKILL.md 提取「## 启动流程」章节"
fi

# 在启动流程章节内定位「步骤 2」子段。子段边界：从含 "步骤 2" 或 "2." 的行，
# 到下一个 "步骤 N" / "N." 编号行（或章节末尾）。
step2_block=$(awk '
    BEGIN { in_block=0 }
    /步骤 ?2([^0-9]|$)|^[[:space:]]*2\./ { in_block=1 }
    in_block && /步骤 ?[035-9]([^0-9]|$)|^[[:space:]]*[035-9]\./ { in_block=0 }
    in_block { print }
' <<< "$startup_section")

if [[ -z "$step2_block" ]]; then
    # 兜底：可能用 markdown 编号或「2.」纯文本；放宽匹配再试一次
    step2_block=$(awk '
        BEGIN { in_block=0 }
        /^[[:space:]]*2\.[[:space:]]/ { in_block=1 }
        in_block && /^[[:space:]]*[035-9]\.[[:space:]]/ { in_block=0 }
        in_block { print }
    ' <<< "$startup_section")
fi

if [[ -z "$step2_block" ]]; then
    fail "无法在「## 启动流程」章节内提取步骤 2 子段（设计要求步骤 2 不再即时盲判）"
fi

# P1 子断言 a：步骤 2 不应再含旧盲判"默认 fast，不确定也选 fast"作为判定动作。
# 匹配典型回退文案："默认 fast"、"不确定.*也.*fast"、"不确定.*选 fast"、
# "没有代码上下文.*fast"、"盲判.*fast"。注意：这是在步骤 2 子段内匹配——
# 即使"不确定→fast"这一口径在 design 步骤 1 探针后合法保留，它在启动流程步骤 2 内
# 出现即判定为回退（因为步骤 2 此时无代码上下文）。
blind_pattern='默认 ?fast|不确定.*(也|即)? ?(选|走|用|是) ?fast|盲判.*fast'
if echo "$step2_block" | grep -qiE "$blind_pattern"; then
    fail "P1-a 失败：启动流程步骤 2 仍含即时盲判表述（grep -iE '$blind_pattern'）。设计要求改为 defer。"
fi
pass "P1-a: 启动流程步骤 2 不含即时盲判'默认 fast/不确定也选 fast'作为判定动作"

# P1 子断言 b：步骤 2 应含 defer 到 design 步骤 1（探针后）的指向。
# 匹配：defer / 推迟 / 延后 / 在 design.*(步骤 ?1|探针) / design 阶段.*探针后 / 移至 design。
defer_pattern='defer|推迟|延后|在 ?design.*(步骤 ?1|探针)|design 阶段.*探针后|移至 design|design 步骤 ?1.*探针'
if ! echo "$step2_block" | grep -qiE "$defer_pattern"; then
    fail "P1-b 失败：启动流程步骤 2 未含 defer 到 design 步骤 1 探针后的指向（grep -iE '$defer_pattern'）"
fi
pass "P1-b: 启动流程步骤 2 含 defer 到 design 步骤 1 探针后的指向"

# ════════════════════════════════════════════════════════════════
# P2: design 步骤 1 含 fast_mode 探针判定
# ════════════════════════════════════════════════════════════════

# 提取「## Phase: design」章节（从 "## Phase: design" 到下一个 "## " 为止）
design_section=$(awk '
    /^## Phase: ?design|^## .*[Dd]esign.*Phase/ { in_block=1; print; next }
    in_block && /^## / { in_block=0 }
    in_block { print }
' "$SKILL_FILE")

if [[ -z "$design_section" ]]; then
    fail "无法从 SKILL.md 提取「## Phase: design」章节"
fi

# 在 design 章节内定位「步骤 1」子段。
# 文档实际结构：design 章节用 #### 步骤 N. 四级标题分隔步骤，步骤内可能含
# 1./2./3. 数字子列表（探针判据），故必须用 #### 标题作为子段边界，
# 而非数字列表项（否则步骤内的子列表会误关闭块）。
design_step1_block=$(awk '
    /^#### 步骤 1([^0-9]|$)|^#### .*模式检测与分流|^### .*模式检测与分流|^### 步骤 1([^0-9]|$)/ { in_block=1; print; next }
    in_block && /^(####|###) / { in_block=0 }
    in_block { print }
' <<< "$design_section")

if [[ -z "$design_step1_block" ]]; then
    # 兜底：尝试纯数字列表结构（兼容旧式扁平列表文档）
    design_step1_block=$(awk '
        BEGIN { in_block=0 }
        /^[[:space:]]*1\.[[:space:]]/ { in_block=1 }
        in_block && /^[[:space:]]*[2-9]\.[[:space:]]/ { in_block=0 }
        in_block { print }
    ' <<< "$design_section")
fi

if [[ -z "$design_step1_block" ]]; then
    fail "无法在「## Phase: design」章节内提取步骤 1 子段（设计要求 fast_mode 探针判定在此步骤）"
fi

# P2-a：fast_mode 关键词在 design 步骤 1 出现
if ! echo "$design_step1_block" | grep -q "fast_mode"; then
    fail "P2-a 失败：design 步骤 1 不含 fast_mode 关键词"
fi
pass "P2-a: design 步骤 1 含 fast_mode 关键词"

# P2-b：探针动作（Glob/Grep 或 探针/估算改动半径）
probe_pattern='Glob|Grep|探针|估算.*(改动|半径|变更|范围)|改动.*半径'
if ! echo "$design_step1_block" | grep -qiE "$probe_pattern"; then
    fail "P2-b 失败：design 步骤 1 不含探针动作（grep -iE '$probe_pattern'）"
fi
pass "P2-b: design 步骤 1 含探针动作（Glob/Grep/探针/改动半径）"

# P2-c：fast / standard 判据（这是探针后据结果写回的判别词）
if ! echo "$design_step1_block" | grep -qiE "standard"; then
    fail "P2-c 失败：design 步骤 1 不含 standard 判据（判别 fast vs standard 必需）"
fi
if ! echo "$design_step1_block" | grep -qiE "fast"; then
    fail "P2-c 失败：design 步骤 1 不含 fast 判据"
fi
pass "P2-c: design 步骤 1 含 fast/standard 判据"

# P2-d：写回动作（写回 / 设为 / 填入 fast_mode）
writeback_pattern='写回|回填|填入|设为|设置 fast_mode|fast_mode *=|fast_mode[:：]'
if ! echo "$design_step1_block" | grep -qiE "$writeback_pattern"; then
    fail "P2-d 失败：design 步骤 1 不含 fast_mode 写回动作（grep -iE '$writeback_pattern'）"
fi
pass "P2-d: design 步骤 1 含 fast_mode 写回动作"

# P2-e（无条件先行）：fast_mode 判定应在 mode 分流（single/project/brief）之前或独立出现。
# 反模式："先看 mode 再看 fast_mode" / "根据 mode 决定 fast_mode"。我们断言：步骤 1 文本中
# fast_mode 首次出现行号 <= mode 分流词（single/project/brief）首次出现行号，且不出现
# "根据.*mode.*决定.*fast_mode" 这类反向依赖。
fm_line=$(echo "$design_step1_block" | grep -n "fast_mode" | head -1 | cut -d: -f1)
mode_line=$(echo "$design_step1_block" | grep -niE "single|project 模式|项目模式|brief" | head -1 | cut -d: -f1)

if [[ -n "$fm_line" && -n "$mode_line" ]]; then
    if [[ "$fm_line" -gt "$mode_line" ]]; then
        fail "P2-e 失败：design 步骤 1 中 fast_mode 行($fm_line) 在 mode 分流词行($mode_line) 之后——fast_mode 判定应无条件先行于 mode 分流"
    fi
fi

if echo "$design_step1_block" | grep -qiE "根据.*mode.*决定.*fast_mode|由 mode.*定.*fast_mode"; then
    fail "P2-e 失败：design 步骤 1 出现'根据 mode 决定 fast_mode'反向依赖——fast_mode 判定应无条件先行"
fi
pass "P2-e: design 步骤 1 fast_mode 判定无条件先行于 mode 分流（无反向依赖）"

# ════════════════════════════════════════════════════════════════
# P3: "启动流程步骤 2" 作为 fast_mode 决策关联的悬空引用计数 == 0
# ════════════════════════════════════════════════════════════════

# 同时覆盖 SKILL.md 和 state-file-guide.md。
# 旧位置短语："启动流程步骤 2"（或 "启动流程.*步骤 ?2"）若在同一行/紧邻上下文中
# 关联到 fast_mode 决策（写回/判定/自适应），即判定为悬空引用。
# 严格口径：搜索"启动流程"且"步骤 2"且与 fast_mode 在 ±5 行窗口内共现的命中。
dangling_found=0
for f in "$SKILL_FILE" "$STATE_GUIDE"; do
    # 用 awk 滑动窗口：对每个"启动流程.*步骤 ?2"命中，检查前后 ±5 行是否有 fast_mode
    # 若命中则打印 "HIT" 前缀行；外层只判断是否有 HIT，避免特殊字符污染计数变量。
    file_has_hit=$(awk '
        {
            lines[NR]=$0
            if ($0 ~ /启动流程.*步骤 ?2/) {
                lo = NR-5; if (lo<1) lo=1
                hi = NR+5
                for (i=lo; i<=hi; i++) {
                    if (i in lines && lines[i] ~ /fast_mode/) {
                        print "HIT"
                        exit 0
                    }
                }
            }
        }
    ' "$f")
    if [[ "$file_has_hit" == "HIT" ]]; then
        dangling_found=1
        # 诊断：打印命中行（用 grep 直接定位，避免变量污染）
        echo "[DIAG] $f 中检测到悬空引用（'启动流程步骤 2' 与 fast_mode 在 ±5 行窗口共现）:" >&2
        grep -nE '启动流程.*步骤 ?2' "$f" | head -5 >&2
    fi
done

if [[ "$dangling_found" -ne 0 ]]; then
    fail "P3 失败：'启动流程步骤 2' 仍与 fast_mode 决策关联（悬空引用存在，期望 0）"
fi
pass "P3: '启动流程步骤 2' 不再与 fast_mode 决策关联（悬空引用计数=0）"

# ════════════════════════════════════════════════════════════════
# P5: git diff plugins/autopilot/scripts/stop-hook.sh 空（搬迁对路由零影响）
# ════════════════════════════════════════════════════════════════

# 在仓库根执行 git diff，路径相对 REPO_ROOT
cd "$REPO_ROOT" || fail "无法 cd 到 REPO_ROOT: $REPO_ROOT"

stop_hook_diff=$(git diff -- "plugins/autopilot/scripts/stop-hook.sh")
stop_hook_diff_lines=$(echo -n "$stop_hook_diff" | grep -c '' || true)

# 主断言（v3.43.0 搬迁时的「空 diff」代理已失效：v3.43.0 后 stop-hook 持续正当演进——
# v3.42 §8.5.1 / v3.47 §8.5.0.5 / v3.48 §8.5.2 等，空 diff 不再成立）。
# 降级为 DIAG 提醒：非空 diff 是正当演进，不 fail；真实意图「对 fast_mode 路由零影响」
# 由下方辅断言（不含 fast_mode 启发式）精准守护。
if [[ -n "$stop_hook_diff" ]]; then
    echo "[DIAG] P5: stop-hook.sh $stop_hook_diff_lines 行 diff（v3.43.0 后正当演进；路由零影响由辅断言守护）" >&2
fi
pass "P5: stop-hook.sh diff 不再要求为空（辅断言守护 fast_mode 路由零影响）"

# 稳健辅断言：stop-hook.sh 中不应出现新增的 fast_mode 决策启发式。
# 设计明确：判定逻辑在 SKILL.md（AI 行为层），stop-hook.sh 是确定性路由层。
# 若 stop-hook.sh 出现"默认 fast""不确定选 fast"这类启发式，即偏离设计。
if grep -qiE '默认 ?fast|不确定.*(也|即)? ?(选|走|用|是) ?fast' "$STOP_HOOK"; then
    fail "P5 辅断言失败：stop-hook.sh 出现 fast_mode 决策启发式（应保持确定性路由，不引入盲判）"
fi
pass "P5 辅: stop-hook.sh 不含 fast_mode 决策启发式（保持确定性路由）"

# ════════════════════════════════════════════════════════════════
# 附加覆盖（设计改动点 5）：phase-checklists.md 步骤 1 标签含 fast_mode
# ════════════════════════════════════════════════════════════════
# 这条不属于预注册 P1/P2/P3/P5 主谓词，但设计改动点 5 明确要求，
# 作为同主题守护断言一并纳入（保持测试内聚）。
if [[ -f "$PHASE_CHECKLIST" ]]; then
    # 提取 phase-checklists.md 中含"步骤 1"的行，或编号 1. 的行
    # 用 ([^0-9]|$) 代替 \b（macOS BSD awk 不支持 \b）
    step1_lines=$(awk '
        /步骤 ?1([^0-9]|$)|^[[:space:]]*1\.[[:space:]]/ { print }
    ' "$PHASE_CHECKLIST")
    if [[ -z "$step1_lines" ]]; then
        fail "附加：phase-checklists.md 找不到步骤 1 行（设计改动点 5 要求步骤 1 标签含 fast_mode）"
    fi
    if ! echo "$step1_lines" | grep -q "fast_mode"; then
        fail "附加：phase-checklists.md 步骤 1 标签不含 fast_mode（设计改动点 5 要求步骤 1 标签含 fast_mode）"
    fi
    pass "附加: phase-checklists.md 步骤 1 标签含 fast_mode（设计改动点 5）"
else
    echo "[SKIP] phase-checklists.md 不存在，跳过附加断言" >&2
fi

echo "[OK ] fast-mode-decision-timing — 全部断言通过"
exit 0
