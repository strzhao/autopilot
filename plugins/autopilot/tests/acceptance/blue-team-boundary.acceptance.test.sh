#!/usr/bin/env bash
# R_BLUE_BOUNDARY: 验证蓝队 prompt 边界收窄——规则8「真实场景冒烟验证」重定义为「编译期健康自检（交付前）」
# 红队测试 — 黑盒视角，基于设计契约（state.md 的 验收场景 P1/P2/P3/P5 + 契约规约 C1-C5）编写，
#            绝不读取蓝队改后的 blue-team-prompt.md / anti-rationalization.md 实际内容来凑断言。
#
# 变更背景：蓝队系统性越界进入 QA 职责（完整测试/构建/冒烟/运行时调试），实测耗时 4.2x（蓝队中位数 38m vs 红队 9m）。
#   根因：blue-team-prompt.md 规则8「真实场景冒烟验证」与 SKILL.md QA Tier 1.5「真实场景谓词求值」职责直接重叠，
#         规则8 授权"不可跳过+当场修复+不留给 QA" → 蓝队获越界的结构性授权。
# 修复：
#   - 规则8 重定义为「编译期健康自检（交付前）」：蓝队只做 build/import/类型/自写单测；真实场景/集成/调试/全量回归=QA
#   - 规则8 内追加终止边界：反复失败/超时/挂死 或 与本次改动无关 → 标 [!] 交 QA（复用规则6 [!] 语义，不加计数器）
#   - anti-rationalization.md implement 段补「多做越界」反向条目（只防"少做"→也防"多做"）
# 必须保留（范围守护 / 不变量护栏 [2026-05-25]）：
#   - blue-team-prompt.md 规则2「全量留给 QA」字面 ∧ 规则7「不擅自扩大范围」字面（防蓝队顺手改规则2/7 措辞破坏边界）
#
# 谓词映射：
#   P1 → 断言 1/2/3（双重 grep [2026-05-25]：旧词=0 ∧ 新词≥1）
#   P2 → 断言 4（规则8 区域含 [!] 与 交 QA 共现）
#   P3 → 断言 6（anti-rationalization implement 段含 多做/越界 反向条目）
#   P5 → 断言 7/8（规则2/7 不变量字面）
#   附加范围守护 → 断言 5（C2 边界：blue-team-prompt.md 不含"真实场景"作为蓝队职责的表述）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
BLUE_TEAM_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/blue-team-prompt.md"
ANTI_RAT_FILE="$REPO_ROOT/plugins/autopilot/skills/autopilot/references/anti-rationalization.md"

fail() {
    echo "[FAIL] R_BLUE_BOUNDARY: $1" >&2
    exit 1
}

pass() {
    echo "[PASS] R_BLUE_BOUNDARY: $1"
}

# 前置：两文件必须存在
[[ -f "$BLUE_TEAM_FILE" ]] \
    || fail "blue-team-prompt.md 不存在: $BLUE_TEAM_FILE（蓝队 prompt 源文件丢失，严重）"
[[ -f "$ANTI_RAT_FILE" ]] \
    || fail "anti-rationalization.md 不存在: $ANTI_RAT_FILE（防合理化指南源文件丢失，严重）"

# 提取 blue-team-prompt.md「## 工作规则」章节（规则 1-N 所在区，C1/C3 的字面契约都落在此章节内）
#   锚点：从「## 工作规则」到下一个 H2 (## ) 之间。
#   若锚点漂移（章节名被改），单独 fail —— 它是所有后续 P1/P2 断言的容器。
RULES_SECTION=$(awk '/^## 工作规则/ {in_sec=1; next} in_sec && /^## / {in_sec=0} in_sec {print}' "$BLUE_TEAM_FILE")
if [[ -z "$RULES_SECTION" ]]; then
    fail "blue-team-prompt.md 未找到「## 工作规则」章节（awk 提取为空，锚点漂移？规则8 边界契约无法定位）"
fi

# ---------------------------------------------------------------------------
# 断言 1（P1 双重 grep — 旧词零命中 a）：blue-team-prompt.md 不含旧字面量「真实场景冒烟验证」
#   守护：规则8 旧标题「真实场景冒烟验证」必须消失（全文件 grep -c == 0）。
#   这是规则8 重定义的「删除确认」——旧措辞是结构性越界授权的标题锚点。
# ---------------------------------------------------------------------------
OLD_TITLE_HIT=$(grep -c '真实场景冒烟验证' "$BLUE_TEAM_FILE" || true)
if [[ "$OLD_TITLE_HIT" -ne 0 ]]; then
    fail "blue-team-prompt.md 仍含「真实场景冒烟验证」x$OLD_TITLE_HIT 次（P1：旧标题未删除，规则8 重定义未生效）"
fi
pass "blue-team-prompt.md 已无旧字面「真实场景冒烟验证」（grep -c == 0）"

# ---------------------------------------------------------------------------
# 断言 2（P1 双重 grep — 旧词零命中 b）：blue-team-prompt.md 不含「当场修复」
#   守护：旧规则8 的「当场修复」措辞（授权蓝队就地修复越界问题）必须消失。
#   第二角度交叉验证 P1——与断言1 共同防"只删标题不删内容"的弱实现骗过断言。
# ---------------------------------------------------------------------------
OLD_FIX_HIT=$(grep -c '当场修复' "$BLUE_TEAM_FILE" || true)
if [[ "$OLD_FIX_HIT" -ne 0 ]]; then
    fail "blue-team-prompt.md 仍含「当场修复」x$OLD_FIX_HIT 次（P1：越界授权措辞未删除）"
fi
pass "blue-team-prompt.md 已无「当场修复」（grep -c == 0）"

# ---------------------------------------------------------------------------
# 断言 3（P1 双重 grep — 新词命中）：blue-team-prompt.md 含新定义「编译期健康自检」
#   守护：规则8 新标题字面 = 「编译期健康自检（交付前）」（C1 字面契约）。
#   与断言1/2 交叉——既删旧词又加新词，才是真重定义（防"删了旧词但没加新词"的半成品）。
#   「工作规则」章节内命中 ≥1 次。
# ---------------------------------------------------------------------------
NEW_TITLE_HIT=$(printf '%s\n' "$RULES_SECTION" | grep -c '编译期健康自检' || true)
if [[ "$NEW_TITLE_HIT" -lt 1 ]]; then
    fail "blue-team-prompt.md「## 工作规则」章节不含「编译期健康自检」（P1：规则8 新定义未写入，命中 $NEW_TITLE_HIT < 1）"
fi
pass "blue-team-prompt.md「## 工作规则」章节含「编译期健康自检」x$NEW_TITLE_HIT 次（≥1，规则8 新定义生效）"

# ---------------------------------------------------------------------------
# 断言 4（P2 / C3 终止边界）：规则8 区域含 [!] 与「交 QA」共现
#   守护：编译期健康自检遇反复失败/超时/挂死 或 与本次改动无关 → 标 [!] 交 QA。
#   C3 终止契约的字面要求：[!] 标记 + 交 QA 措辞在同一章节共现。
#   断言策略：「## 工作规则」章节内既有 [!] 标记，又有「交 QA」（或「交给 QA」）措辞。
#   两者各自 ≥1 命中即视为共现（不强求同一行——设计是"标 [!] 困难项交 QA"的两步表述）。
# ---------------------------------------------------------------------------
BANG_HIT=$(printf '%s\n' "$RULES_SECTION" | grep -c '\[!\]' || true)
HANDOFF_HIT=$(printf '%s\n' "$RULES_SECTION" | grep -cE '交 ?QA|交给 ?QA|交给 QA' || true)
if [[ "$BANG_HIT" -lt 1 ]]; then
    fail "blue-team-prompt.md「## 工作规则」章节不含 [!] 标记（P2：C3 终止边界的困难项标记缺失，命中 $BANG_HIT < 1）"
fi
if [[ "$HANDOFF_HIT" -lt 1 ]]; then
    fail "blue-team-prompt.md「## 工作规则」章节不含「交 QA」措辞（P2：C3 终止边界的移交语义缺失，命中 $HANDOFF_HIT < 1）"
fi
pass "blue-team-prompt.md「## 工作规则」章节 [!] x$BANG_HIT ∧ 交 QA x$HANDOFF_HIT 共现（P2：终止边界就位）"

# ---------------------------------------------------------------------------
# 断言 5（C2 边界契约 — 附加范围守护）：blue-team-prompt.md 不含「真实场景」作为蓝队职责表述
#   守护：C2 边界契约要求"蓝队 prompt 不出现真实场景作为蓝队职责的表述"。
#   规则8 旧标题已删（断言1），但需再扫一次"真实场景"字面量——
#   若规则8 重定义后仍残留"真实场景"作为蓝队动作（如"蓝队做真实场景验证"），仍判 FAIL。
#   允许的豁免：若「真实场景」出现仅作为"交 QA / 归 QA Tier 1.5"的对照对象（同一行同时含 QA 字样），
#   视为正向边界声明，不算违规——故断言只 FAIL 纯"真实场景"无 QA 对照的命中。
# ---------------------------------------------------------------------------
VIOLATIONS=0
while IFS= read -r line; do
    # 跳过空行
    [[ -z "$line" ]] && continue
    # 该行含「真实场景」但不含 QA 字样 → 视为越界表述
    if printf '%s' "$line" | grep -q '真实场景'; then
        if ! printf '%s' "$line" | grep -qE 'QA|Tier 1\.5|交给|交出|不|禁止|归' ; then
            VIOLATIONS=$((VIOLATIONS + 1))
        fi
    fi
done < <(printf '%s\n' "$RULES_SECTION")
if [[ "$VIOLATIONS" -ne 0 ]]; then
    fail "blue-team-prompt.md「## 工作规则」章节含 $VIOLATIONS 行「真实场景」作为蓝队职责表述且无 QA 对照（C2 边界：真实场景验证归 QA Tier 1.5，非蓝队职责）"
fi
pass "blue-team-prompt.md「## 工作规则」章节无「真实场景作为蓝队职责」表述（C2 边界对齐）"

# ---------------------------------------------------------------------------
# 断言 6（P3 / anti-rationalization 多做越界反向条目）：implement 段含「多做」或「越界」反向条目
#   守护：anti-rationalization.md 当前只防"少做"（跳过 TDD/红队），需补"多做越界"反向条目。
#   C5 守护契约 + 设计契约 P3：implement 段含「多做」或「越界」字样 ≥1 次。
#   只扫「## implement 阶段」章节（首个 implement 段，红队 Agent 视角的反向条目表落在此）。
# ---------------------------------------------------------------------------
IMPL_SECTION=$(awk '/^## implement 阶段/ {in_sec=1; next} in_sec && /^## / {in_sec=0} in_sec {print}' "$ANTI_RAT_FILE")
if [[ -z "$IMPL_SECTION" ]]; then
    fail "anti-rationalization.md 未找到「## implement 阶段」章节（awk 提取为空，锚点漂移？）"
fi
MULTI_DO_HIT=$(printf '%s\n' "$IMPL_SECTION" | grep -cE '多做|越界' || true)
if [[ "$MULTI_DO_HIT" -lt 1 ]]; then
    fail "anti-rationalization.md「## implement 阶段」章节不含「多做/越界」反向条目（P3：命中 $MULTI_DO_HIT < 1，仍只防少做不防多做越界）"
fi
pass "anti-rationalization.md「## implement 阶段」章节含「多做/越界」x$MULTI_DO_HIT 次（≥1，反向条目已补）"

# ---------------------------------------------------------------------------
# 断言 7（P5 / 规则2 不变量 — 全文件字面 grep）：blue-team-prompt.md 仍含「全量留给 QA」
#   守护：规则2「全量留给 QA」字面必须保留（P5 不变量护栏 [2026-05-25]）。
#   防实施者在重定义规则8 时顺手改规则2 措辞，破坏 C2 边界（规则2/7 是蓝队边界的横向不变量）。
#   全文件 grep（规则2 字面在「## 工作规则」章节，但全文件字面命中是最稳的确定性判定）。
# ---------------------------------------------------------------------------
RULE2_HIT=$(grep -c '全量留给 QA' "$BLUE_TEAM_FILE" || true)
if [[ "$RULE2_HIT" -lt 1 ]]; then
    fail "blue-team-prompt.md 不再含「全量留给 QA」（P5：规则2 不变量被破坏，命中 $RULE2_HIT < 1）"
fi
pass "blue-team-prompt.md 仍含「全量留给 QA」x$RULE2_HIT 次（P5：规则2 不变量保留）"

# ---------------------------------------------------------------------------
# 断言 8（P5 / 规则7 不变量 — 全文件字面 grep）：blue-team-prompt.md 仍含「不擅自扩大范围」
#   守护：规则7「不擅自扩大范围」字面必须保留（P5 不变量护栏 [2026-05-25]）。
#   与断言7 共同构成规则2/7 横向不变量守护——这两条是蓝队"不越界"的既有边界，
#   本次规则8 重定义只是消解与 Tier 1.5 的垂直重叠，不应顺手改横向规则。
# ---------------------------------------------------------------------------
RULE7_HIT=$(grep -c '不擅自扩大范围' "$BLUE_TEAM_FILE" || true)
if [[ "$RULE7_HIT" -lt 1 ]]; then
    fail "blue-team-prompt.md 不再含「不擅自扩大范围」（P5：规则7 不变量被破坏，命中 $RULE7_HIT < 1）"
fi
pass "blue-team-prompt.md 仍含「不擅自扩大范围」x$RULE7_HIT 次（P5：规则7 不变量保留）"

echo "[OK ] R_BLUE_BOUNDARY blue-team-boundary — 全部断言通过"
exit 0
