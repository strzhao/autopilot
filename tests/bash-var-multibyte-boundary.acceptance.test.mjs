/**
 * bash 变量名边界 — 防复现机械守卫
 *
 * 缺陷：双引号内 `$VAR` 后**紧跟非 ASCII 字符**（全角括号 `（）`、中文标点 `，、：；` 等）时，
 * bash 词法分析器会把多字节字符的字节并入变量名（解析出 `VAR` + 非法字节），
 * `set -u` 下报 `VAR\xef: unbound variable`。`bash -n` 检查不出（纯运行时崩）。
 *
 * 为什么值得一道守卫：最坏的后果不是"崩一下"——崩点在 `fail "…$VAR（…"` 这类
 * **诊断消息**里时，它把真正的失败原因吃掉，只留一句 unbound variable。
 * 实证：knowledge-context-fanout scene 5.P4 断言真失败（版本号硬编码 3.69.0 过时）时，
 * fail 消息自身崩在 `$n，`，排查时误以为是契约问题。
 *
 * 历史：知识库 [2026-05-30] 已入库（domains/bash-shell-pitfalls.md），[2026-09-09] 复现过一次
 * （tiered-approve 5 处），[2026-09-25] 又扫出 36 处（11 文件，含 scripts/setup.sh 的
 * "未知的审批门"生产告警路径——那条在 set -u 下直接崩，而不是打印未知 gate 值）。
 * 同一陷阱三次复发 = 约定层（入库知识）防不住（红队 sub-agent 不加载 knowledge），故机械执法。
 *
 * 契约：仓库内所有 `*.sh` 的**非注释行**不得出现 `$NAME` 紧跟非 ASCII 字符。
 *       修法固定为 `${NAME}`（花括号界定变量名边界），语义不变。
 *       注释行豁免（描述该陷阱的文档本身需要写出 `$var（` 原形）。
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, statSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const SKIP_DIRS = new Set(['.git', 'node_modules', '.autopilot']);

/** `$NAME` 后紧跟非 ASCII 字节 —— 即变量名会被多字节字符污染的位置。
 *  前置 `(?<!\\)` 排除转义美元（`\$TASK_DIR」` 是字面量，不展开、无风险）。 */
const VIOLATION = /(?<!\\)\$([A-Za-z_][A-Za-z0-9_]*)(?=[^\x00-\x7f])/;

function collectShellFiles(dir, out = []) {
  for (const name of readdirSync(dir)) {
    if (SKIP_DIRS.has(name)) continue;
    const full = join(dir, name);
    const st = statSync(full);
    if (st.isDirectory()) collectShellFiles(full, out);
    else if (name.endsWith('.sh')) out.push(full);
  }
  return out;
}

test('no `$VAR` immediately followed by a multi-byte char in shell scripts', () => {
  const files = collectShellFiles(REPO_ROOT);
  assert.ok(files.length > 10, `扫描到的 .sh 文件过少（${files.length}）——守卫可能扫错了目录`);

  const violations = [];
  for (const file of files) {
    const lines = readFileSync(file, 'utf8').split('\n');
    lines.forEach((line, i) => {
      if (/^\s*#/.test(line)) return;          // 注释行豁免（陷阱文档需要原形）
      const m = line.match(VIOLATION);
      if (m) violations.push(`${relative(REPO_ROOT, file)}:${i + 1}  $${m[1]}…  → 应写 \${${m[1]}}`);
    });
  }

  assert.deepEqual(
    violations,
    [],
    `发现 ${violations.length} 处 \`$VAR\` 紧跟多字节字符（set -u 下会崩，且会吃掉诊断信息）：\n` +
      violations.map((v) => `  - ${v}`).join('\n') +
      '\n修法：加花括号 —— `${VAR}中文…`'
  );
});

// 守卫自身有效性：正则必须真的能匹配出该形态（防"守卫恒真"）
test('guard regex actually detects the violation shape', () => {
  assert.ok(VIOLATION.test('fail "count=$n，版本缺失"'), '应命中 $n，');
  assert.ok(VIOLATION.test('echo "$GATE（合法值）"'), '应命中 $GATE（');
  assert.ok(!VIOLATION.test('fail "count=${n}，版本缺失"'), '花括号形式不得命中');
  assert.ok(!VIOLATION.test('echo "$GATE （合法值）"'), '半角空格分隔不得命中');
  assert.ok(!VIOLATION.test('fail "或「\\$TASK_DIR」（场景）"'), '转义美元是字面量，不得命中');
});
