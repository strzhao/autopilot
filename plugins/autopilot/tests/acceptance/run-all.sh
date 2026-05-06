#!/usr/bin/env bash
# 红队验收测试汇总 runner
# 依次执行 R1 → R2 → R3，统计 pass/fail
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 固定执行顺序：R1 (compress) → R2 (qa-reviewer-prompt) → R3 (skill-references)
ORDERED_TESTS=(
    "compress-qa-report.acceptance.test.sh"
    "qa-reviewer-prompt.acceptance.test.sh"
    "skill-references-consistency.acceptance.test.sh"
)

total=0
passed=0
failed=0
failed_names=()

echo "=========================================="
echo " 红队 autopilot v3.16.0 验收测试"
echo "=========================================="

for test_name in "${ORDERED_TESTS[@]}"; do
    test_path="$SCRIPT_DIR/$test_name"
    if [[ ! -f "$test_path" ]]; then
        echo "[SKIP] 测试文件不存在: $test_name"
        continue
    fi
    total=$((total + 1))
    echo ""
    echo "------ Running: $test_name ------"
    if bash "$test_path"; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        failed_names+=("$test_name")
    fi
done

# 兜底：扫描目录里其他可能存在的 *.acceptance.test.sh（除已运行的外）
while IFS= read -r -d '' extra; do
    base="$(basename "$extra")"
    skip=0
    for already in "${ORDERED_TESTS[@]}"; do
        [[ "$base" == "$already" ]] && skip=1 && break
    done
    [[ $skip -eq 1 ]] && continue
    total=$((total + 1))
    echo ""
    echo "------ Running (extra): $base ------"
    if bash "$extra"; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        failed_names+=("$base")
    fi
done < <(find "$SCRIPT_DIR" -maxdepth 1 -name "*.acceptance.test.sh" -print0 2>/dev/null)

echo ""
echo "=========================================="
echo " 汇总：$passed / $total 通过，$failed 失败"
if [[ $failed -gt 0 ]]; then
    echo " 失败用例："
    for name in "${failed_names[@]}"; do
        echo "   - $name"
    done
fi
echo "=========================================="

if [[ $failed -gt 0 ]]; then
    exit 1
fi
exit 0
