<!-- domain: bash 语言陷阱 / exit-code / trap-err / set-u / 多字节 / macOS 兼容 -->
# Bash & Shell Pitfalls

### [2026-05-09] macOS `tail -F | grep -m1 | timeout` 退出码语义不可靠，依赖 stdout 非空判成功
<!-- tags: bash, macos, tail, grep, timeout, exit-code, event-watching, wait-decision, autopilot -->
**Scenario**: 实现"watch 一个 append-only 文件，匹配第一行符合条件的内容后退出"的 bash 脚本。直觉写法 `timeout 30 tail -F file | grep -m1 PATTERN`，期望成功匹配 → exit 0，超时 → exit 124。
**Lesson**: macOS（BSD tail + GNU coreutils timeout）下，**即使 grep -m1 匹配成功**，tail 进程不会因为 grep 关闭管道（SIGPIPE）主动退出，外层 timeout 持续到时限到达 → 整个管道被 SIGTERM 杀死 → 退出码 = 124（超时码），与真正超时无法区分。三种修复方案：(1) 调用方以"stdout 非空且为合法 JSON"作为成功判据，不查退出码；(2) 脚本内用 FIFO + 后台 tail + while read 循环，匹配后主动 `kill $TAIL_PID`；(3) 用 `head -1` 替代 grep（但需要预过滤）。autopilot 同时采用 (1)+(2) 双保险，并在 SKILL.md 文档明确写"以 stdout 非空判成功"。
**Evidence**: wait-decision.sh 实现时遇到，Plan 审查 `references/plan-reviewer-prompt.md` 的"BLOCKER 级"阶段已发现并预警（设计文档「Plan 审查改进建议 1」记录）。修复后红队 22 项断言通过（含超时场景 stdout 为空 + 退出码非 0 的双重断言 C1g）。

### [2026-05-07] Shell 脚本要支持外部 source 测试，必须用 BASH_SOURCE[0]
<!-- tags: bash, shell, testing, source, BASH_SOURCE, autopilot, stop-hook -->
**Scenario**: stop-hook.sh 第 18 行 `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"` 在直接执行时 `$0` 是脚本路径，但被 source 时 `$0` 是调用者 shell（通常 `bash`），导致 `dirname "$0"` 取错路径，进而 `source "$SCRIPT_DIR/lib.sh"` 找不到文件，配合 `trap 'exit 0' ERR` 让整个 source 静默失败。红队测试的 invoke_compress 路径因此根本没成功调用 compress_qa_report 函数，但测试中早期断言（基于原文件内容）误 PASS 掩盖了真问题，只有最严格的断言（轮次 1 应被压缩）暴露失败。
**Lesson**: bash 脚本中所有用于「定位脚本自身目录」的逻辑必须用 `${BASH_SOURCE[0]}` 而非 `$0`。同时为了让函数可被外部独立测试，应在 main 逻辑前添加 source 守卫：`if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then return 0 2>/dev/null || exit 0; fi`。两者一起才能兼容直接执行 + 外部 source 两种用法。这也提示红队测试设计：早期/弱断言可能因「函数没真正运行 + 原文件刚好满足」而误 PASS，需要至少一个能 distinguish「函数有效执行」与「函数从未运行」的强断言。
**Evidence**: 本轮 implement 合流时红队 R1 fail「轮次 1 仍 4 行」，调试发现 source 静默失败导致函数从未被调用。修复 dirname + 加 source 守卫后 R1 全过。

### [2026-05-07] 顶层 `trap 'exit 0' ERR` 拦截函数内 `|| return 1` 短路链
<!-- tags: bash, trap-err, return, source-mode, testing, stop-hook, autopilot -->
**Scenario**: `stop-hook.sh` 顶层 `trap 'exit 0' ERR` 是为脚本主流程兜底（任何未预期错误放行）。新增 `has_pending_subagents` 函数用 `[ -n "$transcript" ] && [ -f "$transcript" ] || return 1` 短路链做错误降级，期望 `return 1` 表示"无 pending"。生产代码通过 `if has_pending_subagents "$x"; then ... fi` 调用，在 if 条件保护下 ERR 不触发——看起来一切正常。但红队测试通过 `bash -c 'source stop-hook.sh; has_pending_subagents ""'` 顶层裸调用，所有错误降级路径返回的 1 全部被 ERR trap 转成 exit 0，spawnSync 拿到 status=0 与函数 return 1 不一致，10 个测试有 7 个失败。
**Lesson**: bash ERR trap 对"函数返回非零"的触发条件取决于调用上下文：在 `if`/`while`/`until` 条件、`||` `&&` 链、`!` 否定中调用 → 不触发；裸调用（顶层 simple command）→ 触发。这意味着脚本的"生产正确性"和"测试可观察性"在 trap ERR 存在时是两套语义。修复模式：trap 仅在直接执行模式安装（`if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then trap 'exit 0' ERR; fi`），让 source 测试模式下函数 return 直接传递给 spawnSync。子 shell 包装也行不通——子 shell 仍继承父 shell 的 ERR trap。
**Evidence**: 实测 `trap "echo TRAP; exit 0" ERR; foo() { return 1; }; foo` 输出 `TRAP` 退出，但 `if foo; then ...; fi` 不触发。本次 QA 轮次 1 红队测试 7/10 失败，root cause 定位通过 5 行最小复现脚本在 `bash -c` 中直接验证。

### [2026-06-24] `set -u` 下中文字符串内 `$VAR（全角）` 词法分析误报 unbound variable
<!-- tags: bash, set-u, unicode, variable-expansion, fullwidth-parenthesis, acceptance-test, quoting, word-boundary -->
**Scenario**: 红队验收测试 `set -uo pipefail`，pass 消息含 `$PATH_HAS_TMP（场景5.P1...`——`$VAR` 后紧跟全角括号「（」（U+FF08）。变量实际已定义并赋值，但 bash 词法分析器把多字节字符的字节并入变量名 → 解析出 `PATH_HAS_TMP` + 非法字节，`set -u` 报 `PATH_HAS_TMP�: unbound variable`。该行此前因另一断言先 FAIL exit 没跑到（latent bug，改了上一条断言后暴露）。
**Lesson**: bash `set -u` 下，双引号内 `$VAR` 后紧跟**非 ASCII / 多字节字符**（全角括号、中文、Unicode 符号）时，词法分析器可能把多字节字符的字节并入变量名 → 误报 unbound。**修复**：用 `${VAR}` 花括号明确界定变量名边界（`pass "...${PATH_HAS_TMP}（场景..."`）。判据：`set -u` + 双引号 + `$VAR` + 紧邻多字节字符 = 必须用 `${VAR}`。同类：含 `$VAR` 插值的 pass/fail 消息避免 `$VAR` 直接接全角字符；中文字符串内 `$((...))` 算术展开也有类似词法问题。`$VAR `（后接半角空格/ASCII）无此问题——半角空格是变量名截止符。
**Evidence**: acceptance-staging-contract.acceptance.test.sh:231 `$PATH_HAS_TMP（` 报 unbound（bash -n 通过，纯运行时 set -u 暴露），改 `${PATH_HAS_TMP}` 后全 PASS。同文件 `$PATH_HAS_RUNTIME ` / `$STAGING_IN_BLUE `（半角空格分隔）均无问题，证明确是全角字符边界问题。

### [2026-07-23] awk 正则单词边界 `\b` 在 BSD/macOS 不支持 → 反向断言永真无判别力
<!-- tags: bash, awk, bsd, macos, word-boundary, regex, tautological, mutation-survival, red-team, acceptance-test -->
**Scenario**: 红队验收测试用 awk 做反向断言（检测「命脉未覆盖 + pass/na 放行词共现 == 0」防假绿），正则用 `\b` 单词边界（如 `/[[:space:]"(]pass\b/`）。macOS BSD awk（version 20200816）不把 `\b` 识别为单词边界 → 该模式永不匹配任何行 → 反向断言 co_occurrence 永远 == 0 → 永真 PASS。注入「未覆盖 pass」假绿词的 mutation 无法被此断言拦截（M6 mutation 实证：注入后仍 co==0 PASS）。tautological/mutation-survival 反模式——断言对任何 mutation 都通过，零判别力。
**Lesson**: awk 正则禁用 `\b` / `\<` / `\>`（GNU awk 扩展，BSD/macOS awk 不支持，跨平台失效）。需要「单词边界」语义时用 `[^a-zA-Z]`（非字母字符）或 `([^a-zA-Z]|$)`（非字母或行尾）替代——POSIX 兼容、跨平台一致。判据：跨平台 bash 脚本的 awk 正则只用 POSIX 字符类，不用 GNU 扩展。注意：grep 的 `\b` 在 BSD grep 支持（与 awk 行为不同），同一脚本里 awk 用 `\b` 失效但 grep 用 `\b` 工作会掩盖 bug（debug 输出匹配但断言不匹配）。
**Evidence**: critical-path-readiness.acceptance.test.sh:458-461 场景7.P3.NEGATE；`printf "未覆盖 pass" | awk '/未覆盖/ && /[[:space:]"(]pass\b/'` → 不匹配（c=0，失效）；改 `([^a-zA-Z]|$)` → c=1 恢复判别力。qa-reviewer M6 mutation 实证 + 用户 AskUserQuestion 确认红队铁律例外（「断言机制错」）+ 重锁修复（核对锚点：2026-07-23 v3.59.0 acceptance.test.sh:458）。

