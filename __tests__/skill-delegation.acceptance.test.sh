#!/bin/bash
# 验收测试：autopilot 领域 Skill 委托机制
# 红队验证者编写，基于设计文档，未读取蓝队实现代码

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_FILE="$PROJECT_ROOT/plugins/autopilot/skills/autopilot/SKILL.md"

PASS=0
FAIL=0

assert_contains() {
    local desc="$1"
    local pattern="$2"
    if grep -qE "$pattern" "$SKILL_FILE"; then
        echo "✅ $desc"
        ((PASS++))
    else
        echo "❌ $desc — 未找到: $pattern"
        ((FAIL++))
    fi
}

assert_contains_icase() {
    local desc="$1"
    local pattern="$2"
    if grep -qiE "$pattern" "$SKILL_FILE"; then
        echo "✅ $desc"
        ((PASS++))
    else
        echo "❌ $desc — 未找到: $pattern"
        ((FAIL++))
    fi
}

# 前置检查
if [ ! -f "$SKILL_FILE" ]; then
    echo "❌ FATAL: SKILL.md 不存在: $SKILL_FILE"
    exit 1
fi

echo "=== 验收测试：autopilot 领域 Skill 委托机制 ==="
echo "被测文件: $SKILL_FILE"
echo ""

# ─── 验收标准 1: design 阶段模板包含领域 Skill 委托可选字段 ───

echo "--- 验收标准 1: Design 阶段模板包含委托字段 ---"

assert_contains \
    "1.1 设计模板包含「领域 Skill 委托」标题（标记为可选）" \
    "##.*领域.*Skill.*委托.*可选"

assert_contains \
    "1.2 委托字段包含 Skill 名称说明" \
    "委托.*Skill.*名称|Skill.*名称|skill.*name"

assert_contains \
    "1.3 委托字段包含委托范围说明" \
    "委托范围|委托.*范围|delegation.*scope"

assert_contains \
    "1.4 委托字段包含委托输入说明" \
    "委托输入|委托.*输入|delegation.*input"

echo ""

# ─── 验收标准 2: implement 阶段有路由判断 ───

echo "--- 验收标准 2: Implement 阶段有路由判断 ---"

assert_contains \
    "2.1 implement 阶段检查设计文档中是否包含委托声明" \
    "检查.*委托|判断.*委托|委托.*声明|设计文档.*委托"

assert_contains \
    "2.2 路由判断区分有/无委托两条路径" \
    "有.*委托|无.*委托|委托.*路径|路由"

echo ""

# ─── 验收标准 3: 有委托声明时走 Skill 委托路径 ───

echo "--- 验收标准 3: Skill 委托路径完整性 ---"

assert_contains_icase \
    "3.1 委托路径包含调用 Skill 步骤" \
    "调用.*skill|执行.*skill|skill.*调用|invoke.*skill|call.*skill"

assert_contains \
    "3.2 委托路径包含收集产出步骤" \
    "收集.*产出|产出.*收集|收集.*结果|产出"

assert_contains \
    "3.3 委托路径包含红队验收测试步骤" \
    "红队.*验收|红队.*测试|验收测试"

assert_contains_icase \
    "3.4 委托路径包含合流步骤（回到主流程）" \
    "合流|合并.*主流程|回到.*QA|进入.*QA|继续.*QA"

echo ""

# ─── 验收标准 4: 无委托声明时走原有蓝/红队路径（向后兼容） ───

echo "--- 验收标准 4: 向后兼容 —— 无委托走蓝/红队路径 ---"

assert_contains \
    "4.1 无委托声明时走蓝/红队对抗路径" \
    "无.*委托.*蓝.*红|无.*委托.*原有|不声明.*默认|默认.*蓝.*红"

assert_contains \
    "4.2 蓝队 Agent 相关内容仍然存在" \
    "蓝队"

assert_contains \
    "4.3 红队 Agent 相关内容仍然存在" \
    "红队"

echo ""

# ─── 验收标准 5: 降级策略 ───

echo "--- 验收标准 5: Skill 失败降级策略 ---"

assert_contains_icase \
    "5.1 存在降级/回退策略描述" \
    "降级|回退|fallback|fail.*back"

assert_contains_icase \
    "5.2 降级策略明确回退到蓝/红队路径" \
    "(降级|回退|fallback).*蓝.*红|(降级|回退|fallback).*对抗|失败.*回退.*蓝|失败.*蓝.*红"

echo ""

# ─── 验收标准 6: Design 阶段有指引检查可用 skill 列表 ───

echo "--- 验收标准 6: Design 阶段检查可用 Skill 列表 ---"

assert_contains_icase \
    "6.1 Design 阶段有检查/扫描可用 skill 的指引" \
    "可用.*skill|skill.*列表|检查.*skill|扫描.*skill|available.*skill"

echo ""

# ─── 验收标准 7: 原有蓝/红队对抗路径完整未删除 ───

echo "--- 验收标准 7: 原有蓝/红队对抗路径完整性 ---"

assert_contains \
    "7.1 蓝队编码/实现相关指令仍存在" \
    "蓝队.*编码|蓝队.*实现|蓝队.*Agent|蓝队.*按.*计划"

assert_contains \
    "7.2 红队编写验收测试相关指令仍存在" \
    "红队.*验收|红队.*测试|红队.*仅看.*设计"

assert_contains \
    "7.3 信息隔离原则仍存在" \
    "信息隔离|隔离.*执行"

assert_contains \
    "7.4 防合理化表格仍存在" \
    "防合理化|合理化.*表"

assert_contains \
    "7.5 铁律（不允许修改红队测试）仍存在" \
    "不允许.*修改.*红队|不能.*修改.*红队|禁止.*修改.*红队"

echo ""

# ─── 结果汇总 ───

TOTAL=$((PASS + FAIL))
echo "========================================"
echo "结果: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
else
    exit 0
fi
