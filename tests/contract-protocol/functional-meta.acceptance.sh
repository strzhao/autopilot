#!/usr/bin/env bash
# contract-protocol v3.24.0 — Tier 1.5 功能性元验证（4 项）
# 红队测试 — 本脚本只负责准备 fake 输入文件 + 打印执行指令
# 【重要】Agent 调用需要人工/编排器触发，本脚本退出码 0 仅表示 fixture 准备成功
# 完整验证结论需等 Agent 运行结果，不能以本脚本退出码作为通过依据
#
# 可独立执行：bash tests/contract-protocol/functional-meta.acceptance.sh
set -uo pipefail

TMPDIR_BASE="/tmp/autopilot-contract-meta-verify-$$"
mkdir -p "$TMPDIR_BASE"

echo "=========================================="
echo " contract-protocol v3.24.0 功能性元验证"
echo " 准备 4 组 fake fixture 到 $TMPDIR_BASE"
echo "=========================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILL_DIR="$REPO_ROOT/plugins/autopilot/skills/autopilot"
REFS_DIR="$SKILL_DIR/references"
PLAN_REVIEWER="$REFS_DIR/plan-reviewer-prompt.md"
CHECKER_PROMPT="$REFS_DIR/contract-checker-prompt.md"

# ────────────────────────────────────────────────────────────────────────────
# 元验证 1 — plan-reviewer FAIL（contract_required=true 且缺 ## 契约规约 章节）
# 期望：plan-reviewer 返回 BLOCKER，分数 ≥ 91
# ────────────────────────────────────────────────────────────────────────────
META1_DIR="$TMPDIR_BASE/meta1-plan-reviewer-fail"
mkdir -p "$META1_DIR"

cat > "$META1_DIR/fake-state.md" << 'FAKE_STATE_1'
---
active: true
phase: "implement"
gate: ""
iteration: 1
max_iterations: 30
max_retries: 3
retry_count: 0
mode: ""
fast_mode: false
contract_required: true
started_at: "2026-05-10T10:00:00Z"
---

## 目标
实现 detectBursts API，按时间间隔将照片分组为连拍。

## 设计文档

### 方案
新增 `detectBursts(photos, thresholdMs)` 函数，遍历 photos 数组按相邻时间差分组。
返回结构：{ bursts: Burst[], memberCount: number, photosGrouped: number }

时间间隔 ≤ 3000ms 分组（含边界 3000ms）。

（故意缺少 ## 契约规约 章节 — 触发 plan-reviewer 维度 7 BLOCKER）

## 红队验收测试
（待补充）

## QA 报告
（待补充）

## 变更日志
- [2026-05-10T10:00:00Z] 元验证 1 fake state.md — 用于验证 plan-reviewer 在 contract_required=true + 缺 ## 契约规约 时报 BLOCKER
FAKE_STATE_1

cat > "$META1_DIR/README.md" << 'README_1'
# 元验证 1 — plan-reviewer 应返回 BLOCKER（分数 ≥ 91）

## 场景
- frontmatter `contract_required: true`
- 设计文档**故意缺少** `## 契约规约` 章节

## 期望输出
- plan-reviewer 维度 7「契约完整性」报告 **BLOCKER**，分数 **≥ 91**
- 不应跳过维度 7（因为 contract_required=true）

## 执行命令
```bash
# 将 plan-reviewer-prompt.md 内容替换 {state_content} 后送 claude
# 或直接运行：
claude --print "$(cat <<EOF
你是 autopilot plan-reviewer。请审查以下 state.md 内容，输出标准 plan-review 报告。

$(cat META1_DIR/fake-state.md)
EOF
)"
```

## 验收判定
- PASS: 输出含 "BLOCKER" 字样 AND 维度 7 分数字符串 ≥ 91（如 "91" "92" "95" "100"）
- FAIL: 输出维度 7 为 "✅ N/A" 或 "跳过" 或不含 "BLOCKER"
README_1

echo "[FIXTURE] 元验证 1 已写入: $META1_DIR/"
echo "  fake-state.md: contract_required=true + 缺 ## 契约规约 → 期望 BLOCKER ≥91"
echo ""

# ────────────────────────────────────────────────────────────────────────────
# 元验证 2 — plan-reviewer SKIP（旧 state.md 缺 contract_required 字段）
# 期望：维度 7 显示「✅ N/A」或不出现（历史豁免路径）
# ────────────────────────────────────────────────────────────────────────────
META2_DIR="$TMPDIR_BASE/meta2-plan-reviewer-skip"
mkdir -p "$META2_DIR"

cat > "$META2_DIR/fake-state.md" << 'FAKE_STATE_2'
---
active: true
phase: "implement"
gate: ""
iteration: 1
max_iterations: 30
max_retries: 3
retry_count: 0
mode: ""
fast_mode: false
started_at: "2026-05-09T08:00:00Z"
---

## 目标
老任务：调整首页 banner 样式，改变字体颜色从 #333 → #111。

## 设计文档

### 方案
CSS 调整，修改 `.hero-banner h1 { color: #111; }` 一行代码。
纯样式变更，无接口变更，无数据流。

（注意：frontmatter 故意没有 contract_required 字段 — 模拟旧 state.md 历史豁免）

## 红队验收测试
（待补充）

## QA 报告
（待补充）

## 变更日志
- [2026-05-09T08:00:00Z] 元验证 2 fake state.md — 用于验证旧 state.md（无 contract_required）维度 7 被豁免
FAKE_STATE_2

cat > "$META2_DIR/README.md" << 'README_2'
# 元验证 2 — plan-reviewer 维度 7 应为 N/A（历史豁免）

## 场景
- frontmatter **无** `contract_required` 字段（模拟旧 state.md）
- 设计文档无 `## 契约规约` 章节

## 期望输出
- plan-reviewer 维度 7 显示 **✅ N/A**（或不出现，或注明「contract_required 缺失，跳过」）
- **不应**报告 BLOCKER

## 执行命令
```bash
claude --print "$(cat <<EOF
你是 autopilot plan-reviewer。请审查以下 state.md 内容，输出标准 plan-review 报告。

$(cat META2_DIR/fake-state.md)
EOF
)"
```

## 验收判定
- PASS: 维度 7 为 "✅ N/A" 或 "跳过" 或完全不出现该维度
- FAIL: 维度 7 出现 "BLOCKER" 或要求补充 ## 契约规约（历史任务不应被卡死）
README_2

echo "[FIXTURE] 元验证 2 已写入: $META2_DIR/"
echo "  fake-state.md: 无 contract_required 字段 → 期望维度 7 ✅ N/A（历史豁免）"
echo ""

# ────────────────────────────────────────────────────────────────────────────
# 元验证 3 — contract-checker FAIL（契约写 memberCount，实现用 count）
# 期望：{pass: false, mismatches: [{type: 'field_name', expected: 'memberCount', actual: 'count'}]}
# ────────────────────────────────────────────────────────────────────────────
META3_DIR="$TMPDIR_BASE/meta3-contract-checker-fail"
mkdir -p "$META3_DIR/src"

cat > "$META3_DIR/contract-section.md" << 'CONTRACT_3'
## 契约规约

### 接口签名（invariant）
```ts
fn detectBursts(
  photos: Photo[],
  thresholdMs: number
): {
  bursts: Burst[],
  memberCount: number,
  photosGrouped: number
}
```

### 数据结构
- `Burst.id: string`
- `Burst.memberCount: number`  ← 红队必看，字段名精确匹配

### 边界值（invariant，DbC 谓词）
- 时间间隔: ≤ 3000ms 分组（含边界 3000ms）
- 输入数组长度: ≥ 1（空数组 → 抛 EmptyInputError）

### 错误契约
- 输入空数组 → 抛 `EmptyInputError`

### 副作用清单
N/A — 纯计算函数，无 DB 写入，无事件 emit
CONTRACT_3

# 故意用 count 而不是 memberCount（字段名不匹配契约）
cat > "$META3_DIR/src/burst.ts" << 'IMPL_3'
// fake 实现 — 故意用 count 而非 memberCount（违反契约）
export interface BurstResult {
  bursts: Burst[];
  count: number;         // ← 应该是 memberCount，但蓝队用了 count
  photosGrouped: number;
}

export function detectBursts(photos: Photo[], thresholdMs: number): BurstResult {
  const bursts: Burst[] = [];
  let count = 0;  // ← 本应是 memberCount
  // ... 分组逻辑省略
  return {
    bursts,
    count,         // ← 违反契约：契约要求 memberCount
    photosGrouped: photos.length,
  };
}
IMPL_3

cat > "$META3_DIR/README.md" << 'README_3'
# 元验证 3 — contract-checker 应返回 FAIL（field_name 不匹配）

## 场景
- 契约规约：返回值含 `memberCount: number`
- fake 实现：`src/burst.ts` 用 `count: number`（字段名不一致）

## 期望输出（JSON）
```json
{
  "pass": false,
  "mismatches": [
    {
      "type": "field_name",
      "expected": "memberCount",
      "actual": "count",
      "severity": "high"
    }
  ]
}
```

## 执行命令（需 contract-checker-prompt.md 已实现）
```bash
CHECKER_PROMPT="$(cat /path/to/plugins/autopilot/skills/autopilot/references/contract-checker-prompt.md)"
CONTRACT_SECTION="$(cat META3_DIR/contract-section.md)"
CHANGED_FILES="src/burst.ts"
PROJECT_ROOT="META3_DIR"

claude --print "${CHECKER_PROMPT}

## 契约规约输入
${CONTRACT_SECTION}

## 变更文件
${CHANGED_FILES}

## 项目根目录
${PROJECT_ROOT}
"
```

## 验收判定
- PASS: 输出 JSON 含 `"pass": false` AND `"mismatches"` 数组非空 AND 含 `"memberCount"` 和 `"count"`
- FAIL: 输出 `"pass": true` 或 mismatches 为空（contract-checker 未发现字段名不匹配）
README_3

echo "[FIXTURE] 元验证 3 已写入: $META3_DIR/"
echo "  契约: memberCount，实现: count → 期望 {pass: false, mismatches: [{type: 'field_name', ...}]}"
echo ""

# ────────────────────────────────────────────────────────────────────────────
# 元验证 4 — contract-checker PASS（契约写 memberCount，实现也用 memberCount）
# 期望：{pass: true, mismatches: []}
# ────────────────────────────────────────────────────────────────────────────
META4_DIR="$TMPDIR_BASE/meta4-contract-checker-pass"
mkdir -p "$META4_DIR/src"

# 复用同一份契约
cp "$META3_DIR/contract-section.md" "$META4_DIR/contract-section.md"

# 正确实现——字段名与契约一致
cat > "$META4_DIR/src/burst.ts" << 'IMPL_4'
// fake 实现 — 正确使用 memberCount（与契约一致）
export interface BurstResult {
  bursts: Burst[];
  memberCount: number;   // ← 正确，与契约 memberCount 匹配
  photosGrouped: number;
}

export function detectBursts(photos: Photo[], thresholdMs: number): BurstResult {
  const bursts: Burst[] = [];
  let memberCount = 0;  // ← 正确字段名
  // ... 分组逻辑省略
  return {
    bursts,
    memberCount,         // ← 与契约一致
    photosGrouped: photos.length,
  };
}
IMPL_4

cat > "$META4_DIR/README.md" << 'README_4'
# 元验证 4 — contract-checker 应返回 PASS（字段名与契约完全一致）

## 场景
- 契约规约：返回值含 `memberCount: number`
- fake 实现：`src/burst.ts` 也用 `memberCount: number`（字段名一致）

## 期望输出（JSON）
```json
{
  "pass": true,
  "mismatches": []
}
```

## 执行命令（需 contract-checker-prompt.md 已实现）
```bash
CHECKER_PROMPT="$(cat /path/to/plugins/autopilot/skills/autopilot/references/contract-checker-prompt.md)"
CONTRACT_SECTION="$(cat META4_DIR/contract-section.md)"
CHANGED_FILES="src/burst.ts"
PROJECT_ROOT="META4_DIR"

claude --print "${CHECKER_PROMPT}

## 契约规约输入
${CONTRACT_SECTION}

## 变更文件
${CHANGED_FILES}

## 项目根目录
${PROJECT_ROOT}
"
```

## 验收判定
- PASS: 输出 JSON 含 `"pass": true` AND `"mismatches": []`
- FAIL: 输出 `"pass": false` 或 mismatches 非空（contract-checker 误报了无意义 mismatch）
README_4

echo "[FIXTURE] 元验证 4 已写入: $META4_DIR/"
echo "  契约: memberCount，实现: memberCount → 期望 {pass: true, mismatches: []}"
echo ""

# ── 打印 fixture 目录树 ────────────────────────────────────────────────────
echo "=========================================="
echo " Fixture 目录结构"
echo "=========================================="
find "$TMPDIR_BASE" -type f | sort | while read -r f; do
    echo "  ${f#$TMPDIR_BASE/}"
done
echo ""

# ── 打印人工执行指令 ───────────────────────────────────────────────────────
echo "=========================================="
echo " 请人工/编排器执行以下 4 项元验证"
echo "=========================================="
echo ""
echo "【元验证 1】plan-reviewer 应报 BLOCKER (分数 ≥ 91)"
echo "  输入: $META1_DIR/fake-state.md"
echo "  执行: claude --print \"\$(cat $REFS_DIR/plan-reviewer-prompt.md)\""
echo "        （将 fake-state.md 内容注入 plan-reviewer prompt）"
echo "  判定: 输出含 'BLOCKER' AND 维度 7 分数 ≥ 91"
echo ""
echo "【元验证 2】plan-reviewer 维度 7 应为 N/A（历史豁免）"
echo "  输入: $META2_DIR/fake-state.md"
echo "  执行: 同上，但换 fake-state.md 为 meta2 的版本"
echo "  判定: 维度 7 显示 '✅ N/A' 或 '跳过'，不含 'BLOCKER'"
echo ""
echo "【元验证 3】contract-checker 应返回 {pass: false}"
echo "  契约: $META3_DIR/contract-section.md (含 memberCount)"
echo "  实现: $META3_DIR/src/burst.ts (用 count)"
echo "  执行: claude --print \"\$(cat $CHECKER_PROMPT)\" （注入契约+实现）"
echo "  判定: 输出 JSON {pass: false, mismatches: [{type: 'field_name', expected: 'memberCount', actual: 'count'}]}"
echo ""
echo "【元验证 4】contract-checker 应返回 {pass: true}"
echo "  契约: $META4_DIR/contract-section.md (含 memberCount)"
echo "  实现: $META4_DIR/src/burst.ts (也用 memberCount)"
echo "  执行: 同元验证 3，但换为 meta4 的实现"
echo "  判定: 输出 JSON {pass: true, mismatches: []}"
echo ""
echo "=========================================="
echo " Fixture 已就绪，等待执行后汇报结果。"
echo " 本脚本退出码 0 仅表示 fixture 准备成功。"
echo " 元验证最终结论需人工/编排器确认。"
echo "=========================================="

# 清理临时目录
# 注意：仅在显式要求清理时执行，保留 fixture 供调试
# 如需清理，取消下行注释：
# rm -rf "$TMPDIR_BASE"
echo ""
echo "（fixture 保留在 $TMPDIR_BASE，调试完成后可执行 rm -rf $TMPDIR_BASE 清理）"

exit 0
