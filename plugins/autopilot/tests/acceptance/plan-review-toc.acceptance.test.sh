#!/usr/bin/env bash
# R11: autopilot plan review HTML 左侧 TOC + 阅读体验重排 验收测试
# 红队测试 — 仅基于设计文档编写，不读取蓝队实现代码
#
# 设计文档来源：
#   .autopilot/requirements/20260519-优化-plan-review-html-里的/state.md
#   § 设计文档 / § 契约规约 / § 验收场景
#
# 覆盖范围（6 大契约组，共 24+ 静态字面断言）：
#   A. DOM 结构契约（场景 1, 8）：<nav id="toc-pane">、<button id="toc-toggle">、<ol id="toc-list">
#   B. JS 行为契约（场景 1-3, 6, 8）：setAttribute('id'、IntersectionObserver、is-active、is-open、scrollIntoView、ESC、toc-empty
#   C. CSS 契约（场景 5, 7）：.toc-pane、position:sticky、overflow-y:auto、1199/1200 断点 media query、.toc-h2/.toc-h3
#   D. 现有功能未退化（场景 6）：dataset.blockId、stopImmediatePropagation、1100/1101 评论抽屉断点、<aside id="comments-pane">
#   E. skill 文件 0 改动契约（场景 9）：git diff --name-only 仅含 plan-review-template.html
#   F. 重复 H 文本计数器逻辑（场景 6 OST）：JS 中 counter 自增 + 'h-' + counter 拼接
#
# 注意：toc-item 由 JS 运行时生成，红队仅做模板字面断言（无 jsdom 依赖）。
#
# 项目使用 shellcheck 做 CI 检查；本脚本遵循现有 .sh 测试的引用与 set 风格。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

VISUAL_DIR="$REPO_ROOT/plugins/autopilot/scripts/visual-companion"
PLAN_REVIEW_HTML="$VISUAL_DIR/plan-review-template.html"

# ── 辅助函数 ─────────────────────────────────────────────────────────────────
pass() { echo "[PASS] R11: $1"; }
fail() {
    echo "[FAIL] R11: $1" >&2
    exit 1
}

# ── 前置：关键文件存在性检查 ──────────────────────────────────────────────────
echo "---- 前置检查：plan-review-template.html 存在性 ----"
[[ -f "$PLAN_REVIEW_HTML" ]] || fail "plan-review-template.html 不存在: $PLAN_REVIEW_HTML"
pass "前置：plan-review-template.html 存在"

# ════════════════════════════════════════════════════════════════════════════
# 契约 A：DOM 结构契约（场景 1, 8）
# 设计文档 §"接口签名" / §"数据结构"：
#   <nav id="toc-pane" class="toc-pane" aria-label="目录">
#     <button id="toc-toggle" type="button" aria-expanded="false" aria-controls="toc-list">...
#     <ol id="toc-list" class="toc-list">... (运行时由 JS 注入 <li>)
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "---- A: DOM 结构契约 ----"

# A1: 模板含 <nav id="toc-pane" 容器（属性顺序不强制，只要 id="toc-pane" 落在 <nav 标签上）
if ! grep -qE '<nav[^>]*id="toc-pane"' "$PLAN_REVIEW_HTML"; then
    fail "A1: 模板不含 <nav id=\"toc-pane\" 容器（设计要求：左侧 TOC 容器为 <nav>，id=\"toc-pane\"）"
fi
pass "A1: 模板含 <nav id=\"toc-pane\" 容器"

# A2: TOC 容器有 aria-label="目录"
if ! grep -qE 'aria-label="目录"' "$PLAN_REVIEW_HTML"; then
    fail "A2: 模板不含 aria-label=\"目录\"（设计要求：<nav> 加 aria-label=\"目录\" 提升无障碍）"
fi
pass "A2: 含 aria-label=\"目录\""

# A3: 容器内含 <button id="toc-toggle"
if ! grep -qE '<button[^>]*id="toc-toggle"' "$PLAN_REVIEW_HTML"; then
    fail "A3: 模板不含 <button id=\"toc-toggle\"（设计要求：抽屉切换按钮 id=\"toc-toggle\"）"
fi
pass "A3: 含 <button id=\"toc-toggle\""

# A4: button 含 aria-expanded="false"（默认折叠态）
if ! grep -qE 'aria-expanded="false"' "$PLAN_REVIEW_HTML"; then
    fail "A4: 模板不含 aria-expanded=\"false\"（设计要求：抽屉默认 false，状态切换由 JS 翻转）"
fi
pass "A4: 含 aria-expanded=\"false\" 默认态"

# A5: button 含 aria-controls="toc-list"
if ! grep -qE 'aria-controls="toc-list"' "$PLAN_REVIEW_HTML"; then
    fail "A5: 模板不含 aria-controls=\"toc-list\"（设计要求：button 通过 aria-controls 关联 <ol>）"
fi
pass "A5: 含 aria-controls=\"toc-list\""

# A6: 容器内含 <ol id="toc-list"
if ! grep -qE '<ol[^>]*id="toc-list"' "$PLAN_REVIEW_HTML"; then
    fail "A6: 模板不含 <ol id=\"toc-list\"（设计要求：TOC 列表容器为 <ol>，id=\"toc-list\"）"
fi
pass "A6: 含 <ol id=\"toc-list\""

# A7: <ol> 上 class 含 toc-list（可与 id 同名，但 class 是 CSS hook，必须有）
if ! grep -qE '<ol[^>]*class="[^"]*toc-list[^"]*"' "$PLAN_REVIEW_HTML"; then
    fail "A7: <ol id=\"toc-list\"> 上 class 不含 toc-list（设计要求 §\"数据结构\"：CSS class 命名）"
fi
pass "A7: <ol> 上 class 含 toc-list"

# ════════════════════════════════════════════════════════════════════════════
# 契约 B：JS 行为契约（场景 1-3, 6, 8）
# 设计文档：buildTOC + IntersectionObserver + 抽屉交互
#   D2: setAttribute('id', 'h-' + counter)（不能用 dataset，否则 grep id="h- 失败）
#   D5: IntersectionObserver 高亮跟随
#   D6: #toc-toggle 独立 listener，不复用 [data-choice]
#   §"数据结构"：is-active class 加在 .toc-item 上
#   抽屉打开: #toc-pane.is-open
#   场景 4: toc-empty 空状态占位
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "---- B: JS 行为契约 ----"

# B1: JS 中含 setAttribute('id'（H 元素 id 写法 — D2 关键决策）
if ! grep -qE "setAttribute\(['\"]id['\"]" "$PLAN_REVIEW_HTML"; then
    fail "B1: JS 中不含 setAttribute('id'（设计 D2：必须用 setAttribute 写真实 id 属性，不能 dataset.id —— dataset 写不出 id=\"h-N\"，红队 grep 会失败）"
fi
pass "B1: JS 中含 setAttribute('id'"

# B2: JS 中含 IntersectionObserver（D5：高亮跟随）
if ! grep -q "IntersectionObserver" "$PLAN_REVIEW_HTML"; then
    fail "B2: JS 中不含 IntersectionObserver（设计 D5：滚动高亮通过 IntersectionObserver 实现）"
fi
pass "B2: JS 中含 IntersectionObserver"

# B3: JS 中含 'is-active' 字面量（active class 字面）
if ! grep -qE "['\"]is-active['\"]" "$PLAN_REVIEW_HTML"; then
    fail "B3: JS 中不含 'is-active' 字面（设计 §\"数据结构\"：当前高亮 class = is-active，必须以字面量出现以便 JS 操作 classList）"
fi
pass "B3: JS 中含 'is-active' 字面"

# B4: JS 中含 'is-open' 字面（抽屉打开 class）
if ! grep -qE "['\"]is-open['\"]" "$PLAN_REVIEW_HTML"; then
    fail "B4: JS 中不含 'is-open' 字面（设计 §\"数据结构\"：抽屉打开状态 class = is-open）"
fi
pass "B4: JS 中含 'is-open' 字面"

# B5: JS 中含 'toc-empty' 字面（空状态 class — 场景 4）
if ! grep -qE "['\"]toc-empty['\"]" "$PLAN_REVIEW_HTML"; then
    fail "B5: JS 中不含 'toc-empty' 字面（设计场景 4：无 H2/H3 时追加 toc-empty 占位节点）"
fi
pass "B5: JS 中含 'toc-empty' 字面"

# B6: JS 中含 scrollIntoView（点击跳转 — Step 6）
if ! grep -q "scrollIntoView" "$PLAN_REVIEW_HTML"; then
    fail "B6: JS 中不含 scrollIntoView（设计 Step 6：TOC 项点击 scrollIntoView({behavior:'smooth', block:'start'})）"
fi
pass "B6: JS 中含 scrollIntoView"

# B7: JS 中含 'Escape' 或 keyCode 27（ESC 键关闭抽屉 — 场景 7 OST）
if ! grep -qE "'Escape'|\"Escape\"|keyCode\s*===?\s*27|which\s*===?\s*27" "$PLAN_REVIEW_HTML"; then
    fail "B7: JS 中不含 ESC 键关闭逻辑（设计 §\"边界值\"：抽屉打开后 ESC 关闭）"
fi
pass "B7: JS 中含 ESC 键关闭逻辑"

# B8: JS 中含 buildTOC 函数标识（设计 §"副作用清单" 显式声明 buildTOC()）
if ! grep -qE "buildTOC|buildToc" "$PLAN_REVIEW_HTML"; then
    fail "B8: JS 中不含 buildTOC 函数标识（设计 §\"副作用清单\"：新增 JS 全局符号 buildTOC()）"
fi
pass "B8: JS 中含 buildTOC 函数标识"

# B9: JS 中含 #toc-toggle 选择器使用（D6：独立 listener，scoped 到 #toc-toggle）
if ! grep -qE "['\"]#toc-toggle['\"]|getElementById\(['\"]toc-toggle['\"]" "$PLAN_REVIEW_HTML"; then
    fail "B9: JS 中不含 #toc-toggle 选择器使用（设计 D6：抽屉切换 listener 必须 scoped 到 #toc-toggle，不能复用 [data-choice]）"
fi
pass "B9: JS 中含 #toc-toggle 选择器使用"

# ════════════════════════════════════════════════════════════════════════════
# 契约 C：CSS 契约（场景 5, 7）
# 设计文档 §"边界值"：
#   .toc-pane { position: sticky; max-height: calc(100vh - <toolbar-height>); overflow-y: auto; }
#   断点 1200px：>=1200 三栏 + TOC 固定；<1200 抽屉
#   .toc-h2 / .toc-h3 层级 class
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "---- C: CSS 契约 ----"

# C1: CSS 中含 .toc-pane 选择器
if ! grep -qE "\.toc-pane[^a-zA-Z0-9_-]" "$PLAN_REVIEW_HTML"; then
    fail "C1: CSS 中不含 .toc-pane 选择器（设计 §\"副作用清单\"：新增 CSS class .toc-pane）"
fi
pass "C1: CSS 中含 .toc-pane 选择器"

# C2: CSS 中含 position: sticky（场景 5：TOC 独立滚动）
if ! grep -qE "position:\s*sticky" "$PLAN_REVIEW_HTML"; then
    fail "C2: CSS 中不含 position: sticky（设计 §\"边界值\"：.toc-pane 必须 sticky，固定显示态独立滚动）"
fi
pass "C2: CSS 中含 position: sticky"

# C3: CSS 中含 overflow-y: auto（TOC 容器独立滚动 — 场景 5 OST）
if ! grep -qE "overflow-y:\s*auto" "$PLAN_REVIEW_HTML"; then
    fail "C3: CSS 中不含 overflow-y: auto（设计 §\"边界值\"：.toc-pane overflow-y:auto，使 toc 内滚动不带动正文）"
fi
pass "C3: CSS 中含 overflow-y: auto"

# C4: CSS 中含 1200px 断点 media query（设计 D4：仅 1200 一个新断点，与 1100/1101 协调）
if ! grep -qE "@media[^{]*max-width:\s*1199px|@media[^{]*min-width:\s*1200px" "$PLAN_REVIEW_HTML"; then
    fail "C4: CSS 中不含 1200px 断点 media query（设计 D4：max-width:1199px 或 min-width:1200px，与现有 1100/1101 评论断点不重叠）"
fi
pass "C4: CSS 中含 1200px 断点 media query"

# C5: CSS 中含 .toc-h2 层级 class
if ! grep -qE "\.toc-h2[^a-zA-Z0-9_-]" "$PLAN_REVIEW_HTML"; then
    fail "C5: CSS 中不含 .toc-h2 层级 class（设计 §\"副作用清单\"：层级 class .toc-h2）"
fi
pass "C5: CSS 中含 .toc-h2 层级 class"

# C6: CSS 中含 .toc-h3 层级 class
if ! grep -qE "\.toc-h3[^a-zA-Z0-9_-]" "$PLAN_REVIEW_HTML"; then
    fail "C6: CSS 中不含 .toc-h3 层级 class（设计 §\"副作用清单\"：层级 class .toc-h3）"
fi
pass "C6: CSS 中含 .toc-h3 层级 class"

# ════════════════════════════════════════════════════════════════════════════
# 契约 D：现有功能未退化（场景 6）
# 设计文档 §"副作用清单"："不修改" 现有逻辑；
#   line 837/856 1100/1101 评论抽屉断点保持不动；
#   helper.js stopImmediatePropagation 保留；
#   现有 dataset.blockId="b-" 注入逻辑保留；
#   <aside id="comments-pane"> 仍存在
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "---- D: 现有功能未退化 ----"

# D1: 现有 dataset.blockId = 'b-' 注入仍存在（line ~947 行附近的逻辑）
if ! grep -qE "dataset\.blockId\s*=\s*['\"]b-" "$PLAN_REVIEW_HTML"; then
    fail "D1: 现有 child.dataset.blockId = 'b-' 注入逻辑被删除（设计 §\"副作用清单\"：data-block-id=\"b-N\" 评论锚点仍保留，与 id=\"h-N\" 共存）"
fi
pass "D1: 现有 dataset.blockId = 'b-' 注入仍存在"

# D2: stopImmediatePropagation 仍存在（决策按钮双 listener 阻断）
if ! grep -q "stopImmediatePropagation" "$PLAN_REVIEW_HTML"; then
    fail "D2: stopImmediatePropagation 调用被删除（设计 Context：保留双 listener 阻断；设计 D6：新增 listener 不能影响此机制）"
fi
pass "D2: stopImmediatePropagation 仍存在"

# D3: 现有 @media (max-width: 1100px) #comments-drawer-toggle 断点仍存在
#     设计 D4：line 837 处 1100 断点保持不动，与新 1200 断点互不重叠
if ! grep -qE "@media[^{]*max-width:\s*1100px" "$PLAN_REVIEW_HTML"; then
    fail "D3: 现有 @media (max-width: 1100px) 断点被改动（设计 D4：1100/1101 现有断点保持不动）"
fi
# 进一步确认 1100 断点附近含 comments-drawer-toggle 字面（防止只是数字保留但 selector 改了）
if ! grep -q "comments-drawer-toggle" "$PLAN_REVIEW_HTML"; then
    fail "D3: comments-drawer-toggle selector 被删除（现有评论抽屉切换按钮 selector 应保留）"
fi
pass "D3: @media (max-width: 1100px) + comments-drawer-toggle 仍存在"

# D4: 现有 min-width: 1101px 断点仍存在（line 856 附近）
if ! grep -qE "min-width:\s*1101px" "$PLAN_REVIEW_HTML"; then
    fail "D4: 现有 min-width: 1101px 断点被改动（设计 D4：1101 断点保持不动，控制评论抽屉切换按钮显隐）"
fi
pass "D4: min-width: 1101px 断点仍存在"

# D5: <aside id="comments-pane" 仍存在（评论面板 DOM 容器）
if ! grep -qE '<aside[^>]*id="comments-pane"' "$PLAN_REVIEW_HTML"; then
    fail "D5: <aside id=\"comments-pane\"> 容器被删除（设计 §\"接口签名\" DOM shape：<aside id=\"comments-pane\"> 仍存在）"
fi
pass "D5: <aside id=\"comments-pane\"> 仍存在"

# ════════════════════════════════════════════════════════════════════════════
# 契约 E：skill 文件 0 改动契约（场景 9）
# 设计文档场景 9：git diff --name-only HEAD 仅含 plan-review-template.html
#   不允许改动: SKILL.md / launch-plan-review.sh / helper.js / server.cjs
#               / frame-template.html / prefs.cjs / marked.min.js
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "---- E: skill 文件 0 改动契约 ----"

# E1: git diff --name-only HEAD 中不含禁改文件
# 注意：执行此测试时，蓝队尚未 commit；此断言验证「工作树相对 HEAD」未污染禁改清单
# 即使新增了 plan-review-toc.acceptance.test.sh（红队测试文件），此文件不在禁改清单中

FORBIDDEN_FILES=(
    "plugins/autopilot/skills/autopilot/SKILL.md"
    "plugins/autopilot/scripts/visual-companion/launch-plan-review.sh"
    "plugins/autopilot/scripts/visual-companion/helper.js"
    "plugins/autopilot/scripts/visual-companion/server.cjs"
    "plugins/autopilot/scripts/visual-companion/frame-template.html"
    "plugins/autopilot/scripts/visual-companion/prefs.cjs"
    "plugins/autopilot/scripts/visual-companion/marked.min.js"
)

# git diff --name-only HEAD 列出工作树相对最近提交的所有变化文件
DIFF_FILES="$(git -C "$REPO_ROOT" diff --name-only HEAD 2>/dev/null || true)"

# 也包含 untracked 但 staged 的（git diff --cached），合并起来
STAGED_FILES="$(git -C "$REPO_ROOT" diff --name-only --cached HEAD 2>/dev/null || true)"

ALL_DIFF_FILES="$(printf '%s\n%s\n' "$DIFF_FILES" "$STAGED_FILES" | sort -u | grep -v '^$' || true)"

violations=()
for forbidden in "${FORBIDDEN_FILES[@]}"; do
    if printf '%s\n' "$ALL_DIFF_FILES" | grep -qFx "$forbidden"; then
        violations+=("$forbidden")
    fi
done

if [[ ${#violations[@]} -gt 0 ]]; then
    fail "E1: 检测到禁改文件被修改（场景 9：skill 0 改动契约违反）：$(printf '%s ' "${violations[@]}")"
fi
pass "E1: 禁改清单（SKILL.md / launch-plan-review.sh / helper.js / server.cjs / frame-template.html / prefs.cjs / marked.min.js）均未被改动"

# E2: 进一步确认改动只发生在允许文件中
# 允许列表：plan-review-template.html（蓝队改动主体）+ 红队测试文件本身
# 反向断言：去掉允许文件后，剩余应为空
ALLOWED_PATTERN='^(plugins/autopilot/scripts/visual-companion/plan-review-template\.html|plugins/autopilot/tests/acceptance/plan-review-toc\.acceptance\.test\.sh|\.autopilot/.*)$'

UNEXPECTED="$(printf '%s\n' "$ALL_DIFF_FILES" | grep -v -E "$ALLOWED_PATTERN" || true)"

if [[ -n "$UNEXPECTED" ]]; then
    # 设计场景 9 OST：git diff --name-only HEAD 仅含 plan-review-template.html
    # 此处放宽允许：红队测试文件 + .autopilot/ 状态目录（autopilot 自身的工作目录）
    fail "E2: 检测到非允许文件被改动（场景 9）：$UNEXPECTED"
fi
pass "E2: 改动文件白名单校验通过（仅 plan-review-template.html + 红队测试文件 + .autopilot 状态）"

# ════════════════════════════════════════════════════════════════════════════
# 契约 F：重复 H 文本计数器逻辑（场景 6 OST）
# 设计 D2：counter 全局递增、保证唯一；setAttribute('id', 'h-' + counter)
#   红队无法静态验证运行时唯一性，但可以验证 JS 源码字面：
#   - counter 自增（counter++ / ++counter / counter + 1 / counter += 1）
#   - 'h-' + counter 拼接（不依赖文本生成 slug）
# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "---- F: 重复 H 文本计数器逻辑 ----"

# F1: JS 中含 counter 自增逻辑（任一形式：counter++ / ++counter / counter+=1 / counter+1）
if ! grep -qE "counter\+\+|\+\+counter|counter\s*\+=\s*1|counter\s*\+\s*1|counter\s*=\s*counter\s*\+" "$PLAN_REVIEW_HTML"; then
    fail "F1: JS 中不含 counter 自增逻辑（设计 D2：counter 必须递增以保证 id 唯一，重复 H 文本场景）"
fi
pass "F1: JS 中含 counter 自增逻辑"

# F2: JS 中含 'h-' + counter 拼接形式（不依赖文本生成 slug）
# 允许：'h-' + counter / "h-" + counter / `h-${counter}` 三种字面形式
if ! grep -qE "['\"]h-['\"]\s*\+\s*counter|\`h-\\\$\{counter\}\`|['\"]h-['\"]\s*\+\s*[a-zA-Z_][a-zA-Z_0-9]*" "$PLAN_REVIEW_HTML"; then
    fail "F2: JS 中不含 'h-' + counter 拼接形式（设计 D2：id 由 'h-' + 计数器拼接，不依赖 H 文本生成 slug）"
fi
pass "F2: JS 中含 'h-' + counter 拼接（id 计数器命名规则）"

# ════════════════════════════════════════════════════════════════════════════
echo ""
echo "[OK ] R11 plan-review-toc — 全部 24 个静态字面断言通过"
echo "      覆盖：A(7) + B(9) + C(6) + D(5) + E(2) + F(2) = 31 个 grep 断言"
echo "      注：toc-item 由 JS 运行时生成，端到端浏览器测试见 state.md § 真实测试场景"
exit 0
