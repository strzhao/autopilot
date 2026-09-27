#!/usr/bin/env bash
# knowledge-inbox: 知识收件箱（inbox）零冲突机制 — 红队验收测试（bash 断言形态）
#
# 红队测试 — 仅基于设计文档编写（state.md `## 目标`/`## 设计文档`/`## 契约规约`/`## 验收场景`
# 谓词 SSOT），未读取任何蓝队实现改动。
# TDD 红灯：基线 main@937f6e3 的 SKILL.md / knowledge-engineering.md / plan-reviewer-prompt.md /
# autopilot-doctor SKILL.md 均不含 "inbox"/"收编" 字样，本文件全部协议文案锁在基线必失败。
#
# 覆盖谓词（与 /tmp/autopilot-artifacts/ artifact 一一对应）：
#   场景2.P1 [det-machine] → s2-p1.out  双会话独立 inbox 新文件 + 命名模式 + size>0
#   场景2.P2 [det-machine] → s2-p2.out  提取阶段聚合层四类文件零改动（git porcelain）
#   场景2.P4 [det-machine] → s2-p4.out  同 slug 二次写 → `<slug>-2.md` 递增 + 全模式匹配
#   场景3.P1 [det-machine] → s3-p1.out  两跳发现 union 命中未收编主题
#   场景3.P2 [det-machine] → s3-p2.out  第二跳独立命中（index 不含 ∧ inbox 含）
#   场景3.P3 [det-machine] → s3-p3.out  协议文档两处明文两跳发现（SKILL.md 步骤0 + plan-reviewer）
#   场景4.P3 [det-machine] → s4-p3.out  协议明文：仅主检出（.git 为目录）可收编 + worktree 永不收编
#   场景5.P1 [det-machine] → s5-p1.out  N 条积压条目两跳发现全覆盖
#   场景6.P3 [det-machine] → s6-p3.out  doctor 文档明文 inbox 积压计数信号与阈值 10
#   场景7.P1 [det-machine] → s7-p1.out  新沉淀 decision 条目无行首手工全局序号
#   场景7.P2 [det-machine] → s7-p2.out  协议明文禁手工全局序号 + 防并行撞号动机
#   场景7.P3 [det-machine] → s7-p3.out  错误契约三句：tags 2-5 / mkdir -p / union 禁丢弃
#   场景8.P1 [det-machine] → s8-p1.out  主 SKILL.md 行数 ≤ 476（基线锚 main 937f6e3）
#   场景8.P2 [det-machine] → s8-p2.out  零新增 hook/机械守卫 + 零改动脚本未被触碰
#   场景8.P3 [det-machine] → s8-p3.out  引用链零重命名零删除 + 交叉链接零断链
#
# （场景1 收编闭环 / 场景2.P3 git merge / 场景4.P1-P2 worktree 拓扑 / 场景5.P2 两跳冒烟 /
#   场景6.P1-P2 doctor 真跑 / 场景9.P1 npm test → knowledge-inbox-smoke.acceptance.test.mjs）
#
# 契约规约（逐字）：
#   收件箱路径 .autopilot/knowledge/inbox/；文件名 YYYY-MM-DD-<slug>.md，slug ∈ [a-z0-9-] ≤40，
#   全模式 [0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]{1,40}.md；同名 → `-2` 递增；
#   收编触发 = 主检出（.git 为目录）∧ inbox ≥ 1；doctor 阈值 > 10；index.md ≤ 100 行；
#   错误契约：目录不存在 mkdir -p / 冲突 union 两文件都保留禁丢弃任侧 / worktree 永不收编
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../" && pwd)"
PLUGIN_DIR="$REPO_ROOT/plugins/autopilot"
SKILL_MD="$PLUGIN_DIR/skills/autopilot/SKILL.md"
KE_MD="$PLUGIN_DIR/skills/autopilot/references/knowledge-engineering.md"
PR_MD="$PLUGIN_DIR/skills/autopilot/references/plan-reviewer-prompt.md"
DOCTOR_MD="$PLUGIN_DIR/skills/autopilot-doctor/SKILL.md"
BASE_COMMIT="937f6e3"
ART_DIR="/tmp/autopilot-artifacts"
TODAY="$(date +%Y-%m-%d)"
NL=$'\n'
INBOX_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]{1,40}\.md$'

mkdir -p "$ART_DIR"
TMP_ROOT="$(mktemp -d -t autopilot-inbox-rt-XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT

[[ -f "$SKILL_MD" ]]   || { echo "[FATAL] SKILL.md 不存在: $SKILL_MD"; exit 1; }
[[ -f "$KE_MD" ]]      || { echo "[FATAL] knowledge-engineering.md 不存在: $KE_MD"; exit 1; }
[[ -f "$PR_MD" ]]      || { echo "[FATAL] plan-reviewer-prompt.md 不存在: $PR_MD"; exit 1; }
[[ -f "$DOCTOR_MD" ]]  || { echo "[FATAL] doctor SKILL.md 不存在: $DOCTOR_MD"; exit 1; }
command -v git >/dev/null || { echo "[FATAL] 需要 git"; exit 1; }
# 基线锚点（谓词注记：主 SKILL.md 行数基线 = 476（main 937f6e3））必须可达
git -C "$REPO_ROOT" cat-file -e "${BASE_COMMIT}^{commit}" 2>/dev/null \
  || { echo "[FATAL] 基线锚点 ${BASE_COMMIT} 不可达（CONTRACT: 场景8 前后对比基）"; exit 1; }

PASS_COUNT=0
FAIL_COUNT=0
fail() { echo "[FAIL] knowledge-inbox: $1" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }
pass() { echo "[PASS] knowledge-inbox: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
artifact() { printf '%s\n' "$2" > "$ART_DIR/$1"; }

# 摘取锚点标题之后、下一个 markdown 标题之前的章节内容（固定串匹配，非正则）
extract_section() { # $1=file $2=anchor_plain_text
  awk -v anc="$2" '
    !found { if (index($0, anc) > 0) found = 1; next }
    $0 ~ /^#{1,6} / { exit }
    { print }
  ' "$1"
}

# 建一个 git 化夹具仓库：聚合层基线已提交、inbox/ 为真实跟踪目录（契约：worktree 中亦然）
new_fixture_repo() {
  local dir
  dir="$(mktemp -d "$TMP_ROOT/fixture-XXXXXX")"
  mkdir -p "$dir/.autopilot/knowledge/domains" "$dir/.autopilot/knowledge/inbox"
  printf 'Decision: 基线决策\n' > "$dir/.autopilot/knowledge/decisions.md"
  printf 'Pattern: 基线模式\n' > "$dir/.autopilot/knowledge/patterns.md"
  printf '# Index\n- [2026-01-01] 基线条目 → decisions.md\n' > "$dir/.autopilot/knowledge/index.md"
  (
    cd "$dir" \
      && git init -q -b main \
      && git config user.email red-team@test \
      && git config user.name red-team \
      && git add -A \
      && git commit -qm "knowledge baseline"
  ) >/dev/null 2>&1 || { echo "[FATAL] 夹具仓库初始化失败: $dir"; exit 1; }
  echo "$dir"
}

inbox_md_count() { ls "$1"/*.md 2>/dev/null | wc -l | tr -d ' '; }

# ═════════════════════════════════════════════════════════════════════════
# 场景 2：任意会话 merge 阶段知识提取落独立 inbox 文件
# ═════════════════════════════════════════════════════════════════════════
FX2="$(new_fixture_repo)"
INBOX2="$FX2/.autopilot/knowledge/inbox"
before2="$(inbox_md_count "$INBOX2")"

# 两会话按写侧协议各自沉淀（目录已存在；若不存在协议要求 mkdir -p 后写入）
S1_FILE="$INBOX2/${TODAY}-alpha-knowledge.md"
S2_FILE="$INBOX2/${TODAY}-beta-pattern.md"
printf '### [%s] alpha 会话知识\n<!-- tags: knowledge, inbox -->\n- 写入 = 新文件，冲突按构造消失\n' "$TODAY" > "$S1_FILE"
printf '### [%s] beta 会话模式\n<!-- tags: pattern, inbox -->\n- Scenario: 独立条目自足可消费\n' "$TODAY" > "$S2_FILE"

after2="$(inbox_md_count "$INBOX2")"
delta2=$(( after2 - before2 ))

# P1: 文件计数差 == 2 && 文件名互异 && 每个匹配日期-slug 模式 && size > 0
ev2p1="before=$before2 after=$after2 delta=$delta2"
[[ "$delta2" -eq 2 ]] || fail "场景2.P1 inbox 文件计数差应 ==2，实际 $delta2"
[[ "$S1_FILE" != "$S2_FILE" ]] || fail "场景2.P1 两会话文件名互异"
for f in "$S1_FILE" "$S2_FILE"; do
  b="$(basename "$f")"
  [[ "$b" =~ $INBOX_RE ]] || fail "场景2.P1 文件名不符全模式: $b"
  [[ -s "$f" ]] || fail "场景2.P1 文件应为非空: $b"
  ev2p1+=$'\n'"$b size=$(wc -c < "$f" | tr -d ' ')"
done
artifact s2-p1.out "$ev2p1"
[[ $delta2 -eq 2 ]] && pass "场景2.P1 双会话产出两个互不重名、命名合规的 inbox 新文件"

# P2: 聚合层四类文件零改动（negate: 提取阶段直接写聚合层）
agg_paths=".autopilot/knowledge/decisions.md .autopilot/knowledge/patterns.md .autopilot/knowledge/index.md .autopilot/knowledge/domains"
agg_status="$(git -C "$FX2" status --porcelain -- $agg_paths)"
ev2p2="git status --porcelain -- 聚合层四类路径:
${agg_status:-（空 = 零改动）}
inbox 未跟踪新文件:
$(git -C "$FX2" status --porcelain -- .autopilot/knowledge/inbox/)"
artifact s2-p2.out "$ev2p2"
if [[ -n "$agg_status" ]]; then
  fail "场景2.P2 聚合层四类文件在提取阶段被改动（写穿）: $agg_status"
else
  pass "场景2.P2 提取阶段聚合层四类文件零改动（改动只在 inbox/）"
fi

# P4: 同一检出内同 slug 二次写入 → <slug>-2.md 且原文件保留，全部文件名匹配全模式
DUP1="$INBOX2/${TODAY}-alpha-knowledge.md"
DUP2="$INBOX2/${TODAY}-alpha-knowledge-2.md"
printf '### [%s] alpha 会话知识（第二次沉淀）\n<!-- tags: knowledge, inbox -->\n- 同名已存在 → -2 递增\n' "$TODAY" > "$DUP2"
ev2p4="inbox 终态文件名:
$(ls "$INBOX2")"
artifact s2-p4.out "$ev2p4"
if [[ ! -f "$DUP2" ]]; then
  fail "场景2.P4 同 slug 二次写应产出 $(basename "$DUP2")"
elif [[ ! -f "$DUP1" ]]; then
  fail "场景2.P4 -2 递增时原文件必须保留，实际 $(basename "$DUP1") 消失"
else
  badname=""
  for f in "$INBOX2"/*.md; do
    b="$(basename "$f")"
    [[ "$b" =~ $INBOX_RE ]] || badname="$badname $b"
  done
  if [[ -n "$badname" ]]; then
    fail "场景2.P4 存在不匹配全模式 [$INBOX_RE] 的文件名:$badname"
  else
    pass "场景2.P4 同 slug 二次写 → -2 递增、原文件保留、全部文件名匹配全模式"
  fi
fi
# P4 文案锁：knowledge-engineering.md 明文 `-2` 递增规则（契约：同名已存在 → 后缀 -2 递增）
if grep -q '递增' "$KE_MD" && grep -q -- '-2' "$KE_MD"; then
  pass "场景2.P4(锁) knowledge-engineering.md 明文 -2 递增规则"
else
  fail "场景2.P4(锁) knowledge-engineering.md 缺 -2 递增规则文案"
fi

# ═════════════════════════════════════════════════════════════════════════
# 场景 3：消费端两跳发现——未收编 inbox 条目可发现可消费
# ═════════════════════════════════════════════════════════════════════════
FX3="$TMP_ROOT/fx3"
mkdir -p "$FX3/knowledge/inbox"
THEME3="未收编主题两跳验证"
printf '# Index\n- [2026-01-01] 基线条目 → decisions.md\n' > "$FX3/knowledge/index.md"   # index 不含主题
printf '### [%s] 未收编条目\n<!-- tags: inbox, pending -->\n- 主题：%s\n' "$TODAY" "$THEME3" \
  > "$FX3/knowledge/inbox/${TODAY}-unincorporated.md"

hop1="$(grep -l "$THEME3" "$FX3/knowledge/index.md" 2>/dev/null || true)"
hop2="$(grep -rl "$THEME3" "$FX3/knowledge/inbox/" 2>/dev/null || true)"
union_hit="$(grep -rl "$THEME3" "$FX3/knowledge/" 2>/dev/null || true)"
ev3p1="hop1(index) 命中: ${hop1:-（无，未收编）}
hop2(inbox) 命中: ${hop2:-（无）}
union 命中: ${union_hit:-（无）}"
artifact s3-p1.out "$ev3p1"
if [[ -n "$hop2" && -n "$union_hit" ]]; then
  pass "场景3.P1 未收编条目主题出现在两跳发现 union 结果集合"
else
  fail "场景3.P1 union 发现未命中未收编主题（hop2='$hop2' union='$union_hit'）"
fi

# P2: index.md not contains 主题 && inbox 列举 contains 主题（发现不依赖收编）
if grep -q "$THEME3" "$FX3/knowledge/index.md"; then
  fail "场景3.P2 index.md 不应包含未收编条目主题（前置被破坏）"
elif [[ -z "$hop2" ]]; then
  fail "场景3.P2 第二跳（inbox 列举）应独立命中该条目"
else
  pass "场景3.P2 第二跳独立命中：index 不含主题 ∧ inbox 含主题"
fi
artifact s3-p2.out "index.md 含主题: $(grep -c "$THEME3" "$FX3/knowledge/index.md" || true) 次（应为 0）
inbox 含主题文件: ${hop2:-（无）}"

# P3: 协议文档两处明文两跳发现（design 步骤 0 + plan-reviewer 盲区对照）
step0="$(extract_section "$SKILL_MD" '#### 步骤 0. 知识上下文加载')"
pr_content="$(cat "$PR_MD")"
ev3p3="SKILL.md 步骤0 节:
$step0
─────
plan-reviewer-prompt.md inbox 相关行:
$(grep -n 'inbox' "$PR_MD" || echo '（无 — 基线红）')"
artifact s3-p3.out "$ev3p3"
if ! echo "$step0" | grep -q 'inbox'; then
  fail "场景3.P3 SKILL.md 步骤0 知识上下文加载节未含 inbox 两跳发现（design 步骤 0 加 ls inbox 半句）"
elif ! echo "$step0" | grep -Eq 'ls|列举'; then
  fail "场景3.P3 SKILL.md 步骤0 节缺列举语义关键词（ls inbox/）"
elif ! echo "$pr_content" | grep -q 'inbox'; then
  fail "场景3.P3 plan-reviewer-prompt.md 未含 inbox 两跳发现（维度 9 补 ls inbox 半句）"
elif ! echo "$pr_content" | grep -Eq 'ls|列举'; then
  fail "场景3.P3 plan-reviewer-prompt.md 缺列举语义关键词"
else
  pass "场景3.P3 design 步骤0 与 plan-reviewer 两处均明文两跳发现（index + inbox 列举）"
fi
# 伴随文案锁（设计改动清单）：merge 步骤 1 写目标改 inbox + 尾节知识文件补 inbox 半句
merge_sec="$(extract_section "$SKILL_MD" '#### 1. 知识提取与沉淀')"
tail_sec="$(extract_section "$SKILL_MD" '### 知识文件')"
if echo "$merge_sec" | grep -q 'inbox' && echo "$tail_sec" | grep -q 'inbox'; then
  pass "场景3.P3(锁) SKILL.md merge 提取节与尾节知识文件均含 inbox 写目标"
else
  fail "场景3.P3(锁) SKILL.md merge 提取节/尾节知识文件缺 inbox 写目标文案"
fi

# ═════════════════════════════════════════════════════════════════════════
# 场景 4.P3：收编规则明文——仅主检出（.git 为目录）可收编，worktree 永不收编
# ═════════════════════════════════════════════════════════════════════════
ke_content="$(cat "$KE_MD")"
ev4p3="knowledge-engineering.md .git 相关行:
$(grep -n '\.git' "$KE_MD" | grep -E '收编|目录|主检出' || echo '（无 — 基线红）')
永不收编相关行:
$(grep -n '永不收编' "$KE_MD" || echo '（无 — 基线红）')"
artifact s4-p3.out "$ev4p3"
if ! echo "$ke_content" | grep -q '\.git'; then
  fail "场景4.P3 协议未含收编主体判据 .git"
elif ! echo "$ke_content" | grep -q '收编'; then
  fail "场景4.P3 协议未含收编语义（基线红：收编协议应新增）"
elif ! echo "$ke_content" | grep -q '永不收编'; then
  fail "场景4.P3 协议未明文 worktree 永不收编"
else
  pass "场景4.P3 协议明文：主检出（.git 为目录）判定收编 + worktree 永不收编"
fi

# ═════════════════════════════════════════════════════════════════════════
# 场景 5.P1：inbox 正式态——N 条积压全部可发现（无收编发生）
# ═════════════════════════════════════════════════════════════════════════
FX5="$TMP_ROOT/fx5"
mkdir -p "$FX5/knowledge/inbox"
printf '# Index\n- [2026-01-01] 基线条目 → decisions.md\n' > "$FX5/knowledge/index.md"
N=5
themes5=()
for i in $(seq 1 "$N"); do
  t="积压主题${i}验证"
  themes5+=("$t")
  printf '### [%s] 积压条目%d\n<!-- tags: inbox, backlog -->\n- 主题：%s\n' "$TODAY" "$i" "$t" \
    > "$FX5/knowledge/inbox/${TODAY}-backlog-${i}.md"
done
hit_count=0
miss_list=""
for t in "${themes5[@]}"; do
  if grep -rq "$t" "$FX5/knowledge/" 2>/dev/null; then
    hit_count=$((hit_count + 1))
  else
    miss_list="$miss_list $t"
  fi
done
ev5p1="积压条目数: $(inbox_md_count "$FX5/knowledge/inbox")
发现命中: $hit_count / $N
未命中:${miss_list:-（无）}"
artifact s5-p1.out "$ev5p1"
if [[ "$hit_count" -eq "$N" ]]; then
  pass "场景5.P1 全部 $N 条积压条目经两跳发现可发现可消费（发现命中数 == N）"
else
  fail "场景5.P1 发现命中 $hit_count / ${N}，未全覆盖:$miss_list"
fi

# ═════════════════════════════════════════════════════════════════════════
# 场景 6.P3：doctor 巡检文档明文 inbox 积压计数信号与阈值 10
# ═════════════════════════════════════════════════════════════════════════
ev6p3="doctor SKILL.md inbox 相关行:
$(grep -n 'inbox' "$DOCTOR_MD" || echo '（无 — 基线红）')"
artifact s6-p3.out "$ev6p3"
if grep -q 'inbox' "$DOCTOR_MD" && grep -q '10' "$DOCTOR_MD"; then
  pass "场景6.P3 doctor 巡检文档明文 inbox 积压计数信号及阈值 10"
else
  fail "场景6.P3 doctor 文档缺 inbox 计数信号或阈值 10（Dim 12 Wave1 数据收集 + Step2 判读）"
fi

# ═════════════════════════════════════════════════════════════════════════
# 场景 7：decisions 条目禁手工全局序号
# ═════════════════════════════════════════════════════════════════════════
FX7="$TMP_ROOT/fx7"
mkdir -p "$FX7/inbox"
ENTRY7="$FX7/inbox/${TODAY}-serial-check.md"
cat > "$ENTRY7" <<EOF
### [$TODAY] 禁序号验证 decision 条目
<!-- tags: knowledge, inbox, decision -->
Decision:
- Background: 红队夹具条目，验证条目形态契约
- Choice: 采用收件箱独立文件机制沉淀本条知识
- Alternatives rejected: 直接追加聚合层（写穿冲突）
- Trade-offs: 换来并行零冲突与收编侧一次性聚合
EOF
serial_count="$(grep -cE '^[[:space:]]*[0-9]{1,4}[.、）)]' "$ENTRY7" || true)"
ev7p1="条目全文:
$(cat "$ENTRY7")
─────
行首数字序号命中行数: ${serial_count}（应 == 0）"
artifact s7-p1.out "$ev7p1"
if [[ "$serial_count" -eq 0 ]]; then
  pass "场景7.P1 新沉淀 decision 条目无行首手工全局序号"
else
  fail "场景7.P1 条目携带行首手工全局序号（命中 $serial_count 行）"
fi

# P2: 协议明文禁手工全局序号 + 防并行撞号动机
ev7p2="knowledge-engineering.md 序号相关行:
$(grep -n '序号' "$KE_MD" || echo '（无 — 基线红）')"
artifact s7-p2.out "$ev7p2"
if ! echo "$ke_content" | grep -q '序号'; then
  fail "场景7.P2 协议未含序号禁令（防 harmony-space 撞号类习惯）"
elif ! echo "$ke_content" | grep -q '禁'; then
  fail "场景7.P2 序号规则缺禁止语义关键词"
elif ! echo "$ke_content" | grep -Eq '撞号|并行'; then
  fail "场景7.P2 序号禁令缺防并行撞号动机说明"
else
  pass "场景7.P2 协议明文禁手工全局序号并说明防并行撞号动机"
fi

# P3: 错误契约三句——tags 2-5 / mkdir -p / union 禁丢弃（契约规约逐字）
ev7p3="tags 2-5: $(grep -c '2-5' "$KE_MD" || true) 处
mkdir -p: $(grep -c 'mkdir -p' "$KE_MD" || true) 处
union: $(grep -c 'union' "$KE_MD" || true) 处
禁丢弃: $(grep -c '禁丢弃' "$KE_MD" || true) 处"
artifact s7-p3.out "$ev7p3"
if ! grep -q '2-5' "$KE_MD"; then
  fail "场景7.P3 协议缺 tags 2-5 个约束"
elif ! grep -q 'mkdir -p' "$KE_MD"; then
  fail "场景7.P3 协议缺 inbox 目录不存在时 mkdir -p 错误契约"
elif ! grep -q 'union' "$KE_MD"; then
  fail "场景7.P3 协议缺冲突 union 处置契约"
elif ! grep -q '禁丢弃' "$KE_MD"; then
  fail "场景7.P3 union 处置缺「禁丢弃任侧」约束"
else
  pass "场景7.P3 错误契约三句齐备：tags 2-5 / mkdir -p / union 两文件都保留禁丢弃任侧"
fi

# ═════════════════════════════════════════════════════════════════════════
# 场景 8：工程硬约束
# ═════════════════════════════════════════════════════════════════════════
# P1: 主 SKILL.md 行数 ≤ 476（基线锚 main 937f6e3 = 476）
skill_lines="$(wc -l < "$SKILL_MD" | tr -d ' ')"
ev8p1="主 SKILL.md 行数: ${skill_lines}（基线 476，契约 ≤476：只能少不能多）"
artifact s8-p1.out "$ev8p1"
if [[ "$skill_lines" -le 476 ]]; then
  pass "场景8.P1 主 SKILL.md $skill_lines 行 ≤ 476（净持平/净减）"
else
  fail "场景8.P1 主 SKILL.md $skill_lines 行 > 476，违反「主 skill 只能少不能多」"
fi

# P2: 零新增 hook/机械守卫 + 零改动脚本未被触碰（副作用清单：无 hook、无脚本改动）
hook_diff="$(git -C "$REPO_ROOT" diff "$BASE_COMMIT" --name-only -- plugins/autopilot/hooks/)"
zero_scripts="plugins/autopilot/scripts/stop-hook.sh plugins/autopilot/scripts/lib.sh plugins/autopilot/scripts/setup.sh plugins/autopilot/scripts/worktree.mjs"
zero_diff="$(git -C "$REPO_ROOT" diff "$BASE_COMMIT" --name-only -- $zero_scripts)"
ev8p2="hooks/ 相对基线改动:
${hook_diff:-（空 = 零改动）}
零改动清单脚本相对基线改动:
${zero_diff:-（空 = 零改动）}"
artifact s8-p2.out "$ev8p2"
if [[ -n "$hook_diff" ]]; then
  fail "场景8.P2 hooks 注册相对基线被改动（应零新增机械守卫）: $hook_diff"
elif [[ -n "$zero_diff" ]]; then
  fail "场景8.P2 零改动清单脚本被触碰（skill 脆弱性保护违约）: $zero_diff"
else
  pass "场景8.P2 零新增 hook/机械守卫，stop-hook/lib/setup/worktree.mjs 零改动"
fi

# P3: 引用链零重命名零删除 + 文档交叉链接全部可解析
del_ren="$(git -C "$REPO_ROOT" diff "$BASE_COMMIT" --name-status -- plugins/autopilot/skills/ | grep -E '^(D|R)' || true)"
broken=0
broken_list=""
while IFS= read -r md; do
  md_dir="$(dirname "$md")"
  while IFS= read -r lk; do
    lk="${lk%%#*}"
    case "$lk" in http*|mailto:*|"") continue ;; esac
    if [[ ! -e "$md_dir/$lk" ]]; then
      broken=$((broken + 1))
      broken_list="$broken_list${NL}${md} -> ${lk}"
    fi
  done < <(grep -oE '\]\([^)]+\)' "$md" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//')
done < <(find "$PLUGIN_DIR/skills" -name '*.md')
ev8p3="相对基线 $BASE_COMMIT 的删除/重命名（应空）:
${del_ren:-（空）}
交叉链接断链数: $broken
断链明细:${broken_list:-（无）}"
artifact s8-p3.out "$ev8p3"
if [[ -n "$del_ren" ]]; then
  fail "场景8.P3 既有引用文件被删除/重命名（skill 脆弱性保护违约）: $del_ren"
elif [[ "$broken" -ne 0 ]]; then
  fail "场景8.P3 文档交叉链接存在断链（broken_link_count=${broken}）:${broken_list}"
else
  pass "场景8.P3 引用链零重命名零删除，交叉链接全部可解析（broken=0）"
fi

# ═════════════════════════════════════════════════════════════════════════
echo ""
echo "─────────────────────────────────────────"
echo "knowledge-inbox 汇总: PASS=${PASS_COUNT} FAIL=${FAIL_COUNT}（artifact → ${ART_DIR}）"
echo "─────────────────────────────────────────"
[[ $FAIL_COUNT -gt 0 ]] && exit 1
exit 0
