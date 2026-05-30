/**
 * Field Enum Normalization — Acceptance Tests (Red Team)
 *
 * 验收目标：修复 autopilot 状态机字段值错配。
 * 测试仅基于设计文档（契约规约 SSOT），不读蓝队实现函数体。
 *
 * 覆盖范围：
 *   A. normalize_enum_value 机械归一（大小写/下划线/引号/空串/幂等）
 *   B. is_canonical 五字段边界（命中 + 越界）
 *   C. get_enum_field 集成（从 state.md 读取并归一）
 *   D. stop-hook phase 越界自愈 block（非法 phase 输出 decision:block + 合法枚举说明）
 *   E. stop-hook canonical 归一不误触发（Auto-Fix / auto_fix 不被视为越界）
 *   F. setup.sh approve gate 近义路由（Review-Accept → merge）
 *   G. done + knowledge_extracted 近义不回滚（Skipped 归一后视为 skipped，保持 done）
 *   H. 空值不变量回归（空串 / 空 gate / 空 qa_scope 幂等）
 *
 * Run: node --test plugins/autopilot/scripts/field-enum-normalization.acceptance.test.mjs
 */

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync, execFileSync } from 'node:child_process';
import {
  mkdtempSync, writeFileSync, mkdirSync, rmSync, readFileSync, existsSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const LIB_SH     = resolve(__dirname, 'lib.sh');
const STOP_HOOK   = resolve(__dirname, 'stop-hook.sh');
const SETUP_SH    = resolve(__dirname, 'setup.sh');

// ---------------------------------------------------------------------------
// 临时目录管理 — 测试结束时统一清理
// ---------------------------------------------------------------------------
const _tempDirs = [];
process.on('exit', () => {
  for (const d of _tempDirs) {
    try { rmSync(d, { recursive: true, force: true }); } catch { /* ignore */ }
  }
});

function makeTempDir(prefix = 'enum-norm') {
  const d = mkdtempSync(join(tmpdir(), `${prefix}-`));
  _tempDirs.push(d);
  return d;
}

// ---------------------------------------------------------------------------
// 基础夹具构造器
// ---------------------------------------------------------------------------

/**
 * 在 tmpDir 下构建一个 .autopilot 运行时结构，并写入 state.md 文件。
 * 返回 { projectRoot, stateFile, activePtrFile }
 *
 * stop-hook 通过 stdin JSON 中的 cwd 调用 init_paths，
 * init_paths 读 .autopilot/runtime/active.ptr → slug → state.md 路径。
 */
function scaffoldAutopilot(tmpDir, frontmatter) {
  const projectRoot  = tmpDir;
  const runtimeDir   = join(projectRoot, '.autopilot', 'runtime');
  const reqSlug      = 'test-task-001';
  const requirementsDir = join(runtimeDir, 'requirements', reqSlug);
  const stateFile    = join(requirementsDir, 'state.md');
  const activePtrFile = join(runtimeDir, 'active.ptr');

  mkdirSync(requirementsDir, { recursive: true });

  // active.ptr 指向 slug
  writeFileSync(activePtrFile, reqSlug, 'utf8');

  // state.md — YAML frontmatter
  const fm = Object.entries(frontmatter)
    .map(([k, v]) => `${k}: ${v}`)
    .join('\n');
  const stateContent = `---\n${fm}\n---\n\n## 目标\n测试夹具\n`;
  writeFileSync(stateFile, stateContent, 'utf8');

  return { projectRoot, stateFile, activePtrFile };
}

/**
 * 调用 bash -c "source lib.sh; <expr>" 并返回 spawnSync 结果。
 * 注意：lib.sh 需要 STATE_FILE 已在环境中（或通过 init_paths 解析）。
 * 对于纯函数测试（normalize_enum_value / is_canonical）不依赖 STATE_FILE。
 */
function bashSource(expr, env = {}) {
  return spawnSync(
    'bash',
    ['-c', `source "${LIB_SH}"; ${expr}`],
    { encoding: 'utf8', timeout: 10000, env: { ...process.env, ...env } }
  );
}

// bashSourceWithPaths 已被 C 组内部的 bashWithStateFile 取代，此处保留占位注释。

/**
 * 调用 stop-hook.sh，通过 stdin 传入 JSON payload。
 * 返回 { status, stdout, stderr }
 */
function runStopHook(cwd, stdinExtra = {}, transcriptPath = '') {
  const payload = JSON.stringify({
    session_id: '',
    cwd,
    transcript_path: transcriptPath,
    hook_event_name: 'Stop',
    ...stdinExtra,
  });

  const result = spawnSync(
    'bash',
    [STOP_HOOK],
    {
      input: payload,
      encoding: 'utf8',
      timeout: 15000,
    }
  );
  return result;
}

/**
 * 调用 setup.sh approve（直接 spawn），返回 { status, stdout, stderr }
 */
function runSetupApprove(projectRoot, env = {}) {
  // setup.sh 通过 init_paths 读取 CWD，需要 cd 到项目根
  const result = spawnSync(
    'bash',
    [SETUP_SH, 'approve'],
    {
      encoding: 'utf8',
      timeout: 15000,
      cwd: projectRoot,
      env: { ...process.env, ...env },
    }
  );
  return result;
}

// ===========================================================================
// A. normalize_enum_value — 机械归一
// ===========================================================================

describe('A. normalize_enum_value 机械归一', () => {

  test('A1: 空串输入 → 空串输出（不变量）', () => {
    const r = bashSource('normalize_enum_value ""');
    assert.equal(r.status, 0, `bash 退出失败: ${r.stderr}`);
    // 空串输出：stdout 为空
    assert.equal(
      r.stdout.trim(),
      '',
      `空串应输出空串，实际输出: "${r.stdout}"`
    );
  });

  test('A2: 大写 → 小写归一（Auto-Fix → auto-fix）', () => {
    const r = bashSource('normalize_enum_value "Auto-Fix"');
    assert.equal(r.status, 0, `bash 退出失败: ${r.stderr}`);
    assert.equal(
      r.stdout,
      'auto-fix',
      `Auto-Fix 应归一为 auto-fix，实际: "${r.stdout}"`
    );
  });

  test('A3: 下划线 → 连字符（auto_fix → auto-fix）', () => {
    const r = bashSource('normalize_enum_value "auto_fix"');
    assert.equal(r.status, 0, `bash 退出失败: ${r.stderr}`);
    assert.equal(r.stdout, 'auto-fix', `auto_fix 应归一为 auto-fix，实际: "${r.stdout}"`);
  });

  test('A4: 外层双引号去除（"review-accept" → review-accept）', () => {
    // 传入时已经是带引号的字符串值（frontmatter 中的格式）
    const r = bashSource(`normalize_enum_value '"review-accept"'`);
    assert.equal(r.status, 0, `bash 退出失败: ${r.stderr}`);
    assert.equal(
      r.stdout,
      'review-accept',
      `带双引号应去除外层引号，实际: "${r.stdout}"`
    );
  });

  test('A5: 大写 + 下划线组合（Review_Accept → review-accept）', () => {
    const r = bashSource('normalize_enum_value "Review_Accept"');
    assert.equal(r.status, 0, `bash 退出失败: ${r.stderr}`);
    assert.equal(r.stdout, 'review-accept', `Review_Accept 应归一为 review-accept，实际: "${r.stdout}"`);
  });

  test('A6: 首尾空白被 trim（"  auto-fix  " → auto-fix）', () => {
    const r = bashSource('normalize_enum_value "  auto-fix  "');
    assert.equal(r.status, 0, `bash 退出失败: ${r.stderr}`);
    assert.equal(r.stdout, 'auto-fix', `首尾空白应被 trim，实际: "${r.stdout}"`);
  });

  test('A7: 已 canonical 值幂等（auto-fix → auto-fix）', () => {
    const r = bashSource('normalize_enum_value "auto-fix"');
    assert.equal(r.status, 0, `bash 退出失败: ${r.stderr}`);
    assert.equal(r.stdout, 'auto-fix', `已 canonical 值应幂等，实际: "${r.stdout}"`);
  });

  test('A8: 已 canonical 值幂等（project-qa → project-qa）', () => {
    const r = bashSource('normalize_enum_value "project-qa"');
    assert.equal(r.status, 0, `bash 退出失败: ${r.stderr}`);
    assert.equal(r.stdout, 'project-qa', `project-qa 幂等，实际: "${r.stdout}"`);
  });

  test('A9: 已 canonical 值幂等（review-accept → review-accept）', () => {
    const r = bashSource('normalize_enum_value "review-accept"');
    assert.equal(r.status, 0, `bash 退出失败: ${r.stderr}`);
    assert.equal(r.stdout, 'review-accept', `review-accept 幂等，实际: "${r.stdout}"`);
  });

  test('A10: 大写 + 引号组合（"AUTO_FIX" → auto-fix）', () => {
    const r = bashSource(`normalize_enum_value '"AUTO_FIX"'`);
    assert.equal(r.status, 0, `bash 退出失败: ${r.stderr}`);
    assert.equal(r.stdout, 'auto-fix', `"AUTO_FIX" 应归一为 auto-fix，实际: "${r.stdout}"`);
  });

});

// ===========================================================================
// B. is_canonical — 五字段闭集边界（命中 + 越界）
// ===========================================================================

describe('B. is_canonical 五字段边界', () => {

  // ── phase ──

  test('B1: phase="design" → exit 0（命中）', () => {
    const r = bashSource('is_canonical phase design; echo $?');
    assert.equal(r.status, 0);
    assert.equal(r.stdout.trim(), '0', `phase=design 应命中（exit 0），实际: ${r.stdout.trim()}`);
  });

  test('B2: phase="auto-fix" → exit 0（命中，含连字符）', () => {
    const r = bashSource('is_canonical phase auto-fix; echo $?');
    assert.equal(r.status, 0);
    assert.equal(r.stdout.trim(), '0', `phase=auto-fix 应命中，实际: ${r.stdout.trim()}`);
  });

  test('B3: phase="done" → exit 0（命中）', () => {
    const r = bashSource('is_canonical phase done; echo $?');
    assert.equal(r.status, 0);
    assert.equal(r.stdout.trim(), '0', `phase=done 应命中，实际: ${r.stdout.trim()}`);
  });

  test('B4: phase="fixx" → exit 1（越界）', () => {
    const r = bashSource('is_canonical phase fixx; echo $?');
    assert.equal(r.status, 0);
    assert.equal(r.stdout.trim(), '1', `phase=fixx 应越界（exit 1），实际: ${r.stdout.trim()}`);
  });

  test('B5: phase="Auto-Fix"（未归一的大写）→ exit 1（越界，is_canonical 不做归一）', () => {
    // is_canonical 接受 canonical value；大写 Auto-Fix 不在闭集中
    const r = bashSource('is_canonical phase "Auto-Fix"; echo $?');
    assert.equal(r.status, 0);
    assert.equal(r.stdout.trim(), '1', `未归一的 Auto-Fix 应越界，实际: ${r.stdout.trim()}`);
  });

  // ── gate ──

  test('B6: gate="" → exit 0（命中空串）', () => {
    const r = bashSource('is_canonical gate ""; echo $?');
    assert.equal(r.status, 0);
    assert.equal(r.stdout.trim(), '0', `gate="" 应命中，实际: ${r.stdout.trim()}`);
  });

  test('B7: gate="review-accept" → exit 0（命中）', () => {
    const r = bashSource('is_canonical gate review-accept; echo $?');
    assert.equal(r.status, 0);
    assert.equal(r.stdout.trim(), '0', `gate=review-accept 应命中，实际: ${r.stdout.trim()}`);
  });

  test('B8: gate="approve" → exit 1（越界）', () => {
    const r = bashSource('is_canonical gate approve; echo $?');
    assert.equal(r.status, 0);
    assert.equal(r.stdout.trim(), '1', `gate=approve 应越界，实际: ${r.stdout.trim()}`);
  });

  // ── mode ──

  test('B9: mode="" → exit 0（命中空串）', () => {
    const r = bashSource('is_canonical mode ""; echo $?');
    assert.equal(r.status, 0);
    assert.equal(r.stdout.trim(), '0', `mode="" 应命中，实际: ${r.stdout.trim()}`);
  });

  test('B10: mode="project-qa" → exit 0（命中）', () => {
    const r = bashSource('is_canonical mode project-qa; echo $?');
    assert.equal(r.status, 0);
    assert.equal(r.stdout.trim(), '0', `mode=project-qa 应命中，实际: ${r.stdout.trim()}`);
  });

  test('B11: mode="batch" → exit 1（越界）', () => {
    const r = bashSource('is_canonical mode batch; echo $?');
    assert.equal(r.status, 0);
    assert.equal(r.stdout.trim(), '1', `mode=batch 应越界，实际: ${r.stdout.trim()}`);
  });

  // ── qa_scope ──

  test('B12: qa_scope="" → exit 0（命中空串）', () => {
    const r = bashSource('is_canonical qa_scope ""; echo $?');
    assert.equal(r.status, 0);
    assert.equal(r.stdout.trim(), '0', `qa_scope="" 应命中，实际: ${r.stdout.trim()}`);
  });

  test('B13: qa_scope="smoke" → exit 0（命中）', () => {
    const r = bashSource('is_canonical qa_scope smoke; echo $?');
    assert.equal(r.status, 0);
    assert.equal(r.stdout.trim(), '0', `qa_scope=smoke 应命中，实际: ${r.stdout.trim()}`);
  });

  test('B14: qa_scope="full" → exit 1（越界）', () => {
    const r = bashSource('is_canonical qa_scope full; echo $?');
    assert.equal(r.status, 0);
    assert.equal(r.stdout.trim(), '1', `qa_scope=full 应越界，实际: ${r.stdout.trim()}`);
  });

  // ── knowledge_extracted ──

  test('B15: knowledge_extracted="" → exit 0（命中空串）', () => {
    const r = bashSource('is_canonical knowledge_extracted ""; echo $?');
    assert.equal(r.status, 0);
    assert.equal(r.stdout.trim(), '0', `knowledge_extracted="" 应命中，实际: ${r.stdout.trim()}`);
  });

  test('B16: knowledge_extracted="true" → exit 0（命中）', () => {
    const r = bashSource('is_canonical knowledge_extracted true; echo $?');
    assert.equal(r.status, 0);
    assert.equal(r.stdout.trim(), '0', `knowledge_extracted=true 应命中，实际: ${r.stdout.trim()}`);
  });

  test('B17: knowledge_extracted="skipped" → exit 0（命中）', () => {
    const r = bashSource('is_canonical knowledge_extracted skipped; echo $?');
    assert.equal(r.status, 0);
    assert.equal(r.stdout.trim(), '0', `knowledge_extracted=skipped 应命中，实际: ${r.stdout.trim()}`);
  });

  test('B18: knowledge_extracted="yes" → exit 1（越界）', () => {
    const r = bashSource('is_canonical knowledge_extracted yes; echo $?');
    assert.equal(r.status, 0);
    assert.equal(r.stdout.trim(), '1', `knowledge_extracted=yes 应越界，实际: ${r.stdout.trim()}`);
  });

  // ── 未知字段 ──

  test('B19: 未知字段 "status" → exit 1', () => {
    const r = bashSource('is_canonical status active; echo $?');
    assert.equal(r.status, 0);
    assert.equal(r.stdout.trim(), '1', `未知字段 status 应返回 1，实际: ${r.stdout.trim()}`);
  });

});

// ===========================================================================
// C. get_enum_field — 从 state.md 读取并机械归一
// ===========================================================================

describe('C. get_enum_field 集成', () => {

  // 注意：lib.sh 顶层有 STATE_FILE="" 初始化，因此必须先 source 再设置 STATE_FILE，
  // 不能用 export STATE_FILE=... 前置，否则 source 会把它重置为空串。
  function bashWithStateFile(stateFile, field) {
    return spawnSync(
      'bash',
      ['-c', `source "${LIB_SH}"; STATE_FILE="${stateFile}"; get_enum_field ${field}`],
      { encoding: 'utf8', timeout: 10000 }
    );
  }

  test('C1: 空 gate 字段 → 返回空串（循环不被误判 halt）', () => {
    const dir = makeTempDir('get-enum-empty-gate');
    const { stateFile } = scaffoldAutopilot(dir, {
      phase:   '"implement"',
      gate:    '""',
      iteration: '1',
      max_iterations: '30',
      session_id: '',
      knowledge_extracted: '""',
    });
    const r = bashWithStateFile(stateFile, 'gate');
    assert.equal(r.status, 0, `bash 失败: ${r.stderr}`);
    assert.equal(
      r.stdout,
      '',
      `空 gate 应归一为空串，实际: "${r.stdout}"`
    );
  });

  test('C2: 空 qa_scope 字段 → 返回空串（全量 QA 不被误判）', () => {
    const dir = makeTempDir('get-enum-empty-qascope');
    const { stateFile } = scaffoldAutopilot(dir, {
      phase:    '"qa"',
      gate:     '""',
      qa_scope: '""',
      iteration: '1',
      max_iterations: '30',
      session_id: '',
      knowledge_extracted: '""',
    });
    const r = bashWithStateFile(stateFile, 'qa_scope');
    assert.equal(r.status, 0, `bash 失败: ${r.stderr}`);
    assert.equal(
      r.stdout,
      '',
      `空 qa_scope 应归一为空串，实际: "${r.stdout}"`
    );
  });

  test('C3: phase="Auto-Fix" 写入 → get_enum_field 返回 auto-fix', () => {
    const dir = makeTempDir('get-enum-autofix');
    const { stateFile } = scaffoldAutopilot(dir, {
      phase:   '"Auto-Fix"',
      gate:    '""',
      iteration: '1',
      max_iterations: '30',
      session_id: '',
      knowledge_extracted: '""',
    });
    const r = bashWithStateFile(stateFile, 'phase');
    assert.equal(r.status, 0, `bash 失败: ${r.stderr}`);
    assert.equal(
      r.stdout,
      'auto-fix',
      `Auto-Fix 经 get_enum_field 应归一为 auto-fix，实际: "${r.stdout}"`
    );
  });

  test('C4: gate="review-accept" → get_enum_field 返回 review-accept（幂等）', () => {
    const dir = makeTempDir('get-enum-gate');
    const { stateFile } = scaffoldAutopilot(dir, {
      phase:   '"qa"',
      gate:    '"review-accept"',
      iteration: '2',
      max_iterations: '30',
      session_id: '',
      knowledge_extracted: '""',
    });
    const r = bashWithStateFile(stateFile, 'gate');
    assert.equal(r.status, 0, `bash 失败: ${r.stderr}`);
    assert.equal(
      r.stdout,
      'review-accept',
      `review-accept 经 get_enum_field 应幂等，实际: "${r.stdout}"`
    );
  });

  test('C5: knowledge_extracted="Skipped" → get_enum_field 返回 skipped', () => {
    const dir = makeTempDir('get-enum-ke-skipped');
    const { stateFile } = scaffoldAutopilot(dir, {
      phase:   '"done"',
      gate:    '""',
      iteration: '3',
      max_iterations: '30',
      session_id: '',
      knowledge_extracted: '"Skipped"',
    });
    const r = bashWithStateFile(stateFile, 'knowledge_extracted');
    assert.equal(r.status, 0, `bash 失败: ${r.stderr}`);
    assert.equal(
      r.stdout,
      'skipped',
      `Skipped 经 get_enum_field 应归一为 skipped，实际: "${r.stdout}"`
    );
  });

  test('C6: mode="project-qa" → get_enum_field 返回 project-qa（幂等）', () => {
    const dir = makeTempDir('get-enum-mode');
    const { stateFile } = scaffoldAutopilot(dir, {
      phase:   '"qa"',
      gate:    '""',
      mode:    '"project-qa"',
      iteration: '1',
      max_iterations: '30',
      session_id: '',
      knowledge_extracted: '""',
    });
    const r = bashWithStateFile(stateFile, 'mode');
    assert.equal(r.status, 0, `bash 失败: ${r.stderr}`);
    assert.equal(
      r.stdout,
      'project-qa',
      `project-qa 经 get_enum_field 应幂等，实际: "${r.stdout}"`
    );
  });

});

// ===========================================================================
// D. stop-hook phase 越界自愈 block
// ===========================================================================

describe('D. stop-hook phase 越界自愈 block', () => {

  test('D1: phase="fixx"（非法）→ stop-hook 输出 decision:block，reason 点名合法枚举', () => {
    const dir = makeTempDir('stop-hook-phase-invalid');
    const { projectRoot, stateFile } = scaffoldAutopilot(dir, {
      phase:   '"fixx"',
      gate:    '""',
      iteration: '1',
      max_iterations: '30',
      session_id: '',
      knowledge_extracted: '""',
    });

    const originalContent = readFileSync(stateFile, 'utf8');
    const r = runStopHook(projectRoot);

    // 断言 1：exit 0（stop-hook 在 block 时也必须 exit 0）
    assert.equal(
      r.status,
      0,
      `stop-hook 应 exit 0（即使 block），实际 exit ${r.status}. stderr: ${r.stderr}`
    );

    // 断言 2：stdout 包含有效 JSON
    let parsed;
    try {
      parsed = JSON.parse(r.stdout.trim());
    } catch (e) {
      assert.fail(`stop-hook stdout 应为 JSON，实际: "${r.stdout}". err: ${e.message}`);
    }

    // 断言 3：decision 字段值为 "block"
    assert.equal(
      parsed.decision,
      'block',
      `decision 字段应为 "block"，实际: ${JSON.stringify(parsed.decision)}`
    );

    // 断言 4：reason 中包含合法枚举字样（至少含 auto-fix 或 merge）
    const reason = parsed.reason || '';
    const mentionsLegalValues =
      reason.includes('auto-fix') ||
      reason.includes('merge') ||
      reason.includes('design') ||
      reason.includes('implement');
    assert.ok(
      mentionsLegalValues,
      `reason 应点名合法枚举值（含 auto-fix/merge 等），实际 reason: "${reason}"`
    );

    // 断言 5：state 文件未被破坏（与 block 前一致）
    const afterContent = readFileSync(stateFile, 'utf8');
    // phase 行应仍存在（文件没被清空或损坏）
    assert.ok(
      afterContent.includes('phase:'),
      `state 文件中应仍包含 phase: 字段，实际内容: "${afterContent}"`
    );
  });

  test('D2: phase="random_garbage"（非法）→ stop-hook 输出 decision:block，exit 0', () => {
    const dir = makeTempDir('stop-hook-phase-garbage');
    const { projectRoot } = scaffoldAutopilot(dir, {
      phase:   '"random_garbage"',
      gate:    '""',
      iteration: '1',
      max_iterations: '30',
      session_id: '',
      knowledge_extracted: '""',
    });

    const r = runStopHook(projectRoot);

    assert.equal(r.status, 0, `exit 0 必须，实际: ${r.status}. stderr: ${r.stderr}`);

    let parsed;
    try {
      parsed = JSON.parse(r.stdout.trim());
    } catch (e) {
      assert.fail(`stop-hook stdout 应为 JSON，实际: "${r.stdout}"`);
    }

    assert.equal(parsed.decision, 'block', `decision 应为 block，实际: ${parsed.decision}`);
  });

});

// ===========================================================================
// E. stop-hook canonical 归一不误触发（Auto-Fix / auto_fix 不应被当作越界）
// ===========================================================================

describe('E. stop-hook canonical 归一不误触发', () => {

  test('E1: phase="Auto-Fix"（大写）→ 归一后视为 auto-fix，stop-hook 不输出 decision:block', () => {
    const dir = makeTempDir('stop-hook-autofix-upper');
    const { projectRoot } = scaffoldAutopilot(dir, {
      phase:   '"Auto-Fix"',
      gate:    '""',
      iteration: '1',
      max_iterations: '30',
      session_id: '',
      knowledge_extracted: '""',
    });

    const r = runStopHook(projectRoot);

    // stop-hook 应放行（exit 0）或继续状态机循环（block 是因为 phase 非 done，而非因为越界）
    // 关键断言：stdout 中不存在 {"decision":"block"} 且 reason 中不含"合法枚举"纠正提示
    // 即：如果有 block，reason 中不应点名是因为 phase 越界（枚举纠正提示）
    assert.equal(r.status, 0, `exit 0 必须，实际: ${r.status}. stderr: ${r.stderr}`);

    const stdout = r.stdout.trim();
    if (stdout) {
      let parsed;
      try {
        parsed = JSON.parse(stdout);
      } catch (_) {
        // 非 JSON 输出 → 正常放行，无 block
        return;
      }
      if (parsed.decision === 'block') {
        // 如果是 block，reason 不应包含"合法枚举内"的越界纠正说明
        const reason = parsed.reason || '';
        const isEnumBoundaryBlock =
          reason.includes('不在合法枚举内') ||
          reason.includes('合法值（闭合枚举）') ||
          (reason.includes('phase') && reason.includes('design / implement'));
        assert.ok(
          !isEnumBoundaryBlock,
          `Auto-Fix 归一后属于合法值，不应触发越界 block。reason: "${reason}"`
        );
      }
    }
  });

  test('E2: phase="auto_fix"（下划线）→ 归一后视为 auto-fix，stop-hook 不因越界 block', () => {
    const dir = makeTempDir('stop-hook-autofix-underscore');
    const { projectRoot } = scaffoldAutopilot(dir, {
      phase:   '"auto_fix"',
      gate:    '""',
      iteration: '1',
      max_iterations: '30',
      session_id: '',
      knowledge_extracted: '""',
    });

    const r = runStopHook(projectRoot);
    assert.equal(r.status, 0, `exit 0 必须，实际: ${r.status}. stderr: ${r.stderr}`);

    const stdout = r.stdout.trim();
    if (stdout) {
      let parsed;
      try {
        parsed = JSON.parse(stdout);
      } catch (_) {
        return;
      }
      if (parsed.decision === 'block') {
        const reason = parsed.reason || '';
        const isEnumBoundaryBlock =
          reason.includes('不在合法枚举内') ||
          reason.includes('合法值（闭合枚举）') ||
          (reason.includes('phase') && reason.includes('design / implement'));
        assert.ok(
          !isEnumBoundaryBlock,
          `auto_fix 归一后属于合法值，不应触发越界 block。reason: "${reason}"`
        );
      }
    }
  });

});

// ===========================================================================
// F. setup.sh approve gate 近义路由 → merge
// ===========================================================================

describe('F. setup.sh approve gate 近义路由', () => {

  test('F1: gate="Review-Accept"（大写连字符）→ approve 推进 phase 到 merge', () => {
    const dir = makeTempDir('setup-approve-gate-upper');
    const { projectRoot, stateFile } = scaffoldAutopilot(dir, {
      phase:   '"qa"',
      gate:    '"Review-Accept"',
      iteration: '2',
      max_iterations: '30',
      session_id: '',
      knowledge_extracted: '""',
    });

    const r = runSetupApprove(projectRoot);

    // 允许 exit 0 或非零（setup.sh 本身 exit 0 策略）
    // 关键断言：state.md 中 phase 已被更新为 "merge"
    const afterContent = readFileSync(stateFile, 'utf8');
    const phaseMatch = afterContent.match(/^phase:\s*"?([^"\n]+)"?/m);
    assert.ok(
      phaseMatch,
      `state.md 应包含 phase: 字段，内容: "${afterContent}"`
    );
    assert.equal(
      phaseMatch[1].trim(),
      'merge',
      `gate=Review-Accept 经归一应路由到 merge，实际 phase: "${phaseMatch[1]}". ` +
      `setup stdout: "${r.stdout}". setup stderr: "${r.stderr}"`
    );
  });

  test('F2: gate="review_accept"（下划线）→ approve 推进 phase 到 merge', () => {
    const dir = makeTempDir('setup-approve-gate-underscore');
    const { projectRoot, stateFile } = scaffoldAutopilot(dir, {
      phase:   '"qa"',
      gate:    '"review_accept"',
      iteration: '2',
      max_iterations: '30',
      session_id: '',
      knowledge_extracted: '""',
    });

    const r = runSetupApprove(projectRoot);

    const afterContent = readFileSync(stateFile, 'utf8');
    const phaseMatch = afterContent.match(/^phase:\s*"?([^"\n]+)"?/m);
    assert.ok(phaseMatch, `state.md 应包含 phase: 字段`);
    assert.equal(
      phaseMatch[1].trim(),
      'merge',
      `gate=review_accept 经归一应路由到 merge，实际 phase: "${phaseMatch[1]}". ` +
      `setup stdout: "${r.stdout}"`
    );
  });

  test('F3: gate="REVIEW-ACCEPT"（全大写）→ approve 推进 phase 到 merge', () => {
    const dir = makeTempDir('setup-approve-gate-allcaps');
    const { projectRoot, stateFile } = scaffoldAutopilot(dir, {
      phase:   '"qa"',
      gate:    '"REVIEW-ACCEPT"',
      iteration: '1',
      max_iterations: '30',
      session_id: '',
      knowledge_extracted: '""',
    });

    const r = runSetupApprove(projectRoot);

    const afterContent = readFileSync(stateFile, 'utf8');
    const phaseMatch = afterContent.match(/^phase:\s*"?([^"\n]+)"?/m);
    assert.ok(phaseMatch, `state.md 应包含 phase: 字段`);
    assert.equal(
      phaseMatch[1].trim(),
      'merge',
      `gate=REVIEW-ACCEPT 经归一应路由到 merge，实际 phase: "${phaseMatch[1]}". ` +
      `setup stdout: "${r.stdout}"`
    );
  });

});

// ===========================================================================
// G. done + knowledge_extracted 近义不回滚
// ===========================================================================

describe('G. phase=done + knowledge_extracted 近义不回滚', () => {

  test('G1: phase="done" + knowledge_extracted="Skipped"（大写）→ stop-hook 不回滚到 merge', () => {
    const dir = makeTempDir('stop-hook-done-skipped-upper');
    const { projectRoot, stateFile } = scaffoldAutopilot(dir, {
      phase:   '"done"',
      gate:    '""',
      mode:    '""',
      iteration: '3',
      max_iterations: '30',
      session_id: '',
      knowledge_extracted: '"Skipped"',
      brief_file: '""',
      next_task: '""',
    });

    const originalContent = readFileSync(stateFile, 'utf8');
    const r = runStopHook(projectRoot);

    assert.equal(r.status, 0, `exit 0 必须，实际: ${r.status}. stderr: ${r.stderr}`);

    // 关键断言：state.md 中 phase 仍为 done，未被回滚为 merge
    const afterContent = readFileSync(stateFile, 'utf8');
    const phaseMatch = afterContent.match(/^phase:\s*"?([^"\n]+)"?/m);
    assert.ok(phaseMatch, `state.md 应包含 phase: 字段`);
    assert.equal(
      phaseMatch[1].trim(),
      'done',
      `Skipped 归一后应视为 skipped，phase 不应回滚到 merge。` +
      `实际 phase: "${phaseMatch[1]}". stop-hook stdout: "${r.stdout}"`
    );
  });

  test('G2: phase="done" + knowledge_extracted="SKIPPED"（全大写）→ stop-hook 不回滚到 merge', () => {
    const dir = makeTempDir('stop-hook-done-skipped-allcaps');
    const { projectRoot, stateFile } = scaffoldAutopilot(dir, {
      phase:   '"done"',
      gate:    '""',
      mode:    '""',
      iteration: '2',
      max_iterations: '30',
      session_id: '',
      knowledge_extracted: '"SKIPPED"',
      brief_file: '""',
      next_task: '""',
    });

    const r = runStopHook(projectRoot);
    assert.equal(r.status, 0, `exit 0 必须，实际: ${r.status}. stderr: ${r.stderr}`);

    const afterContent = readFileSync(stateFile, 'utf8');
    const phaseMatch = afterContent.match(/^phase:\s*"?([^"\n]+)"?/m);
    assert.ok(phaseMatch, `state.md 应包含 phase: 字段`);
    assert.equal(
      phaseMatch[1].trim(),
      'done',
      `SKIPPED 归一后应视为 skipped，phase 不应回滚。实际: "${phaseMatch[1]}". stdout: "${r.stdout}"`
    );
  });

  test('G3: phase="done" + knowledge_extracted="true"（canonical）→ stop-hook 不回滚', () => {
    const dir = makeTempDir('stop-hook-done-true-ke');
    const { projectRoot, stateFile } = scaffoldAutopilot(dir, {
      phase:   '"done"',
      gate:    '""',
      mode:    '""',
      iteration: '2',
      max_iterations: '30',
      session_id: '',
      knowledge_extracted: '"true"',
      brief_file: '""',
      next_task: '""',
    });

    const r = runStopHook(projectRoot);
    assert.equal(r.status, 0, `exit 0 必须，实际: ${r.status}. stderr: ${r.stderr}`);

    const afterContent = readFileSync(stateFile, 'utf8');
    const phaseMatch = afterContent.match(/^phase:\s*"?([^"\n]+)"?/m);
    assert.ok(phaseMatch, `state.md 应包含 phase: 字段`);
    assert.equal(
      phaseMatch[1].trim(),
      'done',
      `knowledge_extracted=true 时 phase 不应回滚。实际: "${phaseMatch[1]}"`
    );
  });

});

// ===========================================================================
// H. 空值不变量回归
// ===========================================================================

describe('H. 空值不变量回归', () => {

  test('H1: normalize_enum_value "" → 空串（函数级不变量）', () => {
    const r = bashSource('result=$(normalize_enum_value ""); printf "%s" "$result"');
    assert.equal(r.status, 0, `bash 失败: ${r.stderr}`);
    assert.equal(r.stdout, '', `空串应输出空串，实际: "${r.stdout}"`);
  });

  test('H2: get_enum_field gate（空字符串 frontmatter）→ 返回空串', () => {
    const dir = makeTempDir('h2-empty-gate');
    const { stateFile } = scaffoldAutopilot(dir, {
      phase:   '"implement"',
      gate:    '""',
      iteration: '1',
      max_iterations: '30',
      session_id: '',
      knowledge_extracted: '""',
    });
    // 注意：必须先 source 再设置 STATE_FILE，lib.sh 顶层会重置 STATE_FILE=""
    const r = spawnSync(
      'bash',
      ['-c', `source "${LIB_SH}"; STATE_FILE="${stateFile}"; result=$(get_enum_field gate); printf "%s" "$result"`],
      { encoding: 'utf8', timeout: 10000 }
    );
    assert.equal(r.status, 0, `bash 失败: ${r.stderr}`);
    assert.equal(r.stdout, '', `空 gate 应返回空串，实际: "${r.stdout}"`);
  });

  test('H3: get_enum_field qa_scope（空字符串 frontmatter）→ 返回空串', () => {
    const dir = makeTempDir('h3-empty-qascope');
    const { stateFile } = scaffoldAutopilot(dir, {
      phase:    '"qa"',
      gate:     '""',
      qa_scope: '""',
      iteration: '1',
      max_iterations: '30',
      session_id: '',
      knowledge_extracted: '""',
    });
    // 注意：必须先 source 再设置 STATE_FILE，lib.sh 顶层会重置 STATE_FILE=""
    const r = spawnSync(
      'bash',
      ['-c', `source "${LIB_SH}"; STATE_FILE="${stateFile}"; result=$(get_enum_field qa_scope); printf "%s" "$result"`],
      { encoding: 'utf8', timeout: 10000 }
    );
    assert.equal(r.status, 0, `bash 失败: ${r.stderr}`);
    assert.equal(r.stdout, '', `空 qa_scope 应返回空串，实际: "${r.stdout}"`);
  });

  test('H4: normalize_enum_value "auto-fix" 幂等', () => {
    const r = bashSource('normalize_enum_value "auto-fix"');
    assert.equal(r.status, 0);
    assert.equal(r.stdout, 'auto-fix', `auto-fix 幂等失败，实际: "${r.stdout}"`);
  });

  test('H5: normalize_enum_value "review-accept" 幂等', () => {
    const r = bashSource('normalize_enum_value "review-accept"');
    assert.equal(r.status, 0);
    assert.equal(r.stdout, 'review-accept', `review-accept 幂等失败，实际: "${r.stdout}"`);
  });

  test('H6: normalize_enum_value "project-qa" 幂等', () => {
    const r = bashSource('normalize_enum_value "project-qa"');
    assert.equal(r.status, 0);
    assert.equal(r.stdout, 'project-qa', `project-qa 幂等失败，实际: "${r.stdout}"`);
  });

  test('H7: stop-hook state 文件不存在时 exit 0（不崩溃）', () => {
    const dir = makeTempDir('h7-no-state');
    // 不创建 active.ptr 或 state.md，stop-hook 应放行
    const r = runStopHook(dir);
    assert.equal(r.status, 0, `无状态文件时 stop-hook 应 exit 0，实际: ${r.status}`);
    // stdout 应为空（放行不输出 JSON）
    assert.equal(
      r.stdout.trim(),
      '',
      `无状态文件时 stdout 应为空，实际: "${r.stdout}"`
    );
  });

});
