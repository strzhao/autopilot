/**
 * Pending Sub-agent Detection — Acceptance Tests (Red Team)
 *
 * Tests verify the design contract for `has_pending_subagents()` in stop-hook.sh.
 * Written purely from the design spec without reading the blue-team implementation.
 *
 * Design contract:
 *   - has_pending_subagents(transcript_path) exits 0  = has pending sub-agents (silence stop-hook)
 *   - has_pending_subagents(transcript_path) exits 1  = no pending / any error (run stop-hook normally)
 *   - Only main-thread tool_use (isSidechain==false or null) lines are counted as agent calls
 *   - A call is "pending" when its .id has no matching tool_result .tool_use_id in the transcript
 *   - Error cases always degrade gracefully to exit 1 (no false positives)
 *
 * Run: node --test plugins/autopilot/scripts/pending-subagent.acceptance.test.mjs
 */

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  mkdtempSync, writeFileSync, mkdirSync, rmSync, existsSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const STOP_HOOK = resolve(__dirname, 'stop-hook.sh');

// ---------------------------------------------------------------------------
// Temporary workspace — all created temp dirs are collected and removed at
// process exit so we don't litter /tmp on CI runners.
// ---------------------------------------------------------------------------
const _tempDirs = [];
process.on('exit', () => {
  for (const d of _tempDirs) {
    try { rmSync(d, { recursive: true, force: true }); } catch { /* ignore */ }
  }
});

function makeTempDir() {
  const d = mkdtempSync(join(tmpdir(), 'pending-subagent-'));
  _tempDirs.push(d);
  return d;
}

// ---------------------------------------------------------------------------
// Core helper — invoke `has_pending_subagents` via `source stop-hook.sh`.
// Returns the spawnSync result so callers can inspect .status, .stdout, .stderr.
// ---------------------------------------------------------------------------
function runHasPending(transcriptPath) {
  return spawnSync(
    'bash',
    ['-c', `source "${STOP_HOOK}"; has_pending_subagents "${transcriptPath}"`],
    { encoding: 'utf8', timeout: 10000 }
  );
}

// ---------------------------------------------------------------------------
// JSONL builders — each helper returns one line of JSONL (no trailing newline).
// Keep the shapes as close to the "Transcript JSONL 真实结构" spec as possible.
// ---------------------------------------------------------------------------

/** Main-thread assistant message that calls an Agent/Task tool. */
function mainThreadAgentToolUse(id, toolName = 'Agent') {
  return JSON.stringify({
    isSidechain: false,
    type: 'assistant',
    message: {
      role: 'assistant',
      content: [
        {
          type: 'tool_use',
          id,
          name: toolName,
          input: { prompt: 'do some work', options: {} },
        },
      ],
    },
  });
}

/** Main-thread user message with tool_result for a prior tool_use. */
function mainThreadToolResult(toolUseId) {
  return JSON.stringify({
    isSidechain: false,
    type: 'user',
    message: {
      role: 'user',
      content: [
        {
          type: 'tool_result',
          tool_use_id: toolUseId,
          content: [{ type: 'text', text: 'done' }],
        },
      ],
    },
  });
}

/** Sidechain (sub-agent internal) assistant message calling Agent tool. */
function sidechainAgentToolUse(id, toolName = 'Agent') {
  return JSON.stringify({
    isSidechain: true,
    type: 'assistant',
    message: {
      role: 'assistant',
      content: [
        {
          type: 'tool_use',
          id,
          name: toolName,
          input: { prompt: 'inner work', options: {} },
        },
      ],
    },
  });
}

/** Sidechain tool_result. */
function sidechainToolResult(toolUseId) {
  return JSON.stringify({
    isSidechain: true,
    type: 'user',
    message: {
      role: 'user',
      content: [
        {
          type: 'tool_result',
          tool_use_id: toolUseId,
          content: [{ type: 'text', text: 'sidechain done' }],
        },
      ],
    },
  });
}

/** Write lines to a tmp file, return the file path. */
function writeTranscript(lines, dir) {
  const p = join(dir, 'transcript.jsonl');
  writeFileSync(p, lines.join('\n') + '\n', 'utf8');
  return p;
}

// ===========================================================================
// VC1: 主线程 Agent pending（tool_use 无对应 tool_result）→ 退出码 0
// ===========================================================================
test('VC1: main-thread Agent tool_use without tool_result → exit 0 (pending)', () => {
  const dir = makeTempDir();
  const transcriptPath = writeTranscript([
    mainThreadAgentToolUse('call_test_pending_001'),
    // No matching tool_result — this call is still pending
  ], dir);

  const result = runHasPending(transcriptPath);
  assert.equal(
    result.status,
    0,
    `Expected exit 0 (pending detected) but got ${result.status}. stderr: ${result.stderr}`
  );
});

// ===========================================================================
// VC2: 主线程 Agent 已完成（有匹配的 tool_use_id）→ 退出码 1
// ===========================================================================
test('VC2: main-thread Agent tool_use with matching tool_result → exit 1 (completed)', () => {
  const dir = makeTempDir();
  const transcriptPath = writeTranscript([
    mainThreadAgentToolUse('call_test_complete_001'),
    mainThreadToolResult('call_test_complete_001'),
  ], dir);

  const result = runHasPending(transcriptPath);
  assert.equal(
    result.status,
    1,
    `Expected exit 1 (no pending) but got ${result.status}. stderr: ${result.stderr}`
  );
});

// ===========================================================================
// VC3: 多个主线程 Agent，部分 pending → 退出码 0
// ===========================================================================
test('VC3: multiple main-thread Agents, some pending → exit 0', () => {
  const dir = makeTempDir();
  const transcriptPath = writeTranscript([
    mainThreadAgentToolUse('call_multi_001'),
    mainThreadAgentToolUse('call_multi_002'),
    mainThreadToolResult('call_multi_001'), // first completes
    // call_multi_002 has no result → still pending
  ], dir);

  const result = runHasPending(transcriptPath);
  assert.equal(
    result.status,
    0,
    `Expected exit 0 (at least one pending) but got ${result.status}. stderr: ${result.stderr}`
  );
});

// ===========================================================================
// VC4: 仅 sidechain Agent pending（主线程 Agent 已完成）→ 退出码 1（不误判主线程）
// ===========================================================================
test('VC4: only sidechain Agent pending, main-thread completed → exit 1 (no false positive)', () => {
  const dir = makeTempDir();
  const transcriptPath = writeTranscript([
    mainThreadAgentToolUse('call_main_done_001'),
    mainThreadToolResult('call_main_done_001'),     // main-thread call completed
    sidechainAgentToolUse('call_sidechain_001'),   // sidechain call, no result
    // sidechain pending must NOT trigger exit 0
  ], dir);

  const result = runHasPending(transcriptPath);
  assert.equal(
    result.status,
    1,
    `Expected exit 1 (sidechain pending must not be counted) but got ${result.status}. stderr: ${result.stderr}`
  );
});

// ===========================================================================
// VC5: 空字符串 transcript_path → 退出码 1（降级）
// ===========================================================================
test('VC5: empty string transcript_path → exit 1 (graceful degradation)', () => {
  const result = runHasPending('');
  assert.equal(
    result.status,
    1,
    `Expected exit 1 for empty path but got ${result.status}. stderr: ${result.stderr}`
  );
});

// ===========================================================================
// VC6: 不存在的 transcript 文件路径 → 退出码 1（降级）
// ===========================================================================
test('VC6: non-existent transcript file path → exit 1 (graceful degradation)', () => {
  const nonExistentPath = '/tmp/definitely-does-not-exist-pending-subagent-test-9999.jsonl';
  assert.ok(!existsSync(nonExistentPath), 'precondition: file must not exist');

  const result = runHasPending(nonExistentPath);
  assert.equal(
    result.status,
    1,
    `Expected exit 1 for non-existent path but got ${result.status}. stderr: ${result.stderr}`
  );
});

// ===========================================================================
// VC7: 损坏的 JSONL（最后一行是随机字节 / "INVALID DATA"）→ 退出码 1（降级）
// ===========================================================================
test('VC7: corrupted JSONL (last line is "INVALID DATA") → exit 1 (graceful degradation)', () => {
  const dir = makeTempDir();
  const p = join(dir, 'corrupted.jsonl');
  // Mix a valid line with clearly invalid JSON to confirm jq failure degrades cleanly
  writeFileSync(
    p,
    mainThreadAgentToolUse('call_corrupt_001') + '\n' +
    '"INVALID DATA"\n' +
    'not valid json at all }{}\n',
    'utf8'
  );

  const result = runHasPending(p);
  assert.equal(
    result.status,
    1,
    `Expected exit 1 for corrupted JSONL but got ${result.status}. stderr: ${result.stderr}`
  );
});

// ===========================================================================
// VC8: tool_result 类型也叫 Task（不应被当成 tool_use）→ 不影响 pending 计数
//
// A line whose .message.content[] has type=="tool_result" and name=="Task"
// must not be mistaken for a tool_use that adds to set A.
// Specifically: if there is a real pending main-thread Agent tool_use whose id
// matches a tool_result's .tool_use_id, the call is completed and exit should
// be 1.  But if the jq expression accidentally treats a tool_result line as a
// tool_use (because it also references "Task"), it would incorrectly inflate
// set A and produce a false pending.
// ===========================================================================
test('VC8: tool_result with name-like content does not inflate pending set → exit 1', () => {
  const dir = makeTempDir();

  // A completed main-thread Agent call
  const toolUseId = 'call_vc8_agent_001';

  // Craft a tool_result that has a content array mentioning "Task" in its text
  // but is still a tool_result type (not a tool_use).
  const trickyToolResult = JSON.stringify({
    isSidechain: false,
    type: 'user',
    message: {
      role: 'user',
      content: [
        {
          type: 'tool_result',
          tool_use_id: toolUseId,
          // Content text deliberately contains "Task" to trip naive parsers
          content: [{ type: 'text', text: 'Task completed successfully' }],
        },
      ],
    },
  });

  const transcriptPath = writeTranscript([
    mainThreadAgentToolUse(toolUseId),
    trickyToolResult,
  ], dir);

  const result = runHasPending(transcriptPath);
  assert.equal(
    result.status,
    1,
    `Expected exit 1 (completed call, tool_result must not inflate pending set) but got ${result.status}. stderr: ${result.stderr}`
  );
});

// ---------------------------------------------------------------------------
// statSync is needed for VC9 — import at module level.
// ---------------------------------------------------------------------------
import { statSync } from 'node:fs';

// ===========================================================================
// VC9: 性能：在 5MB transcript 上运行总耗时 < 2s（全部完成，期望 exit 1）
// ===========================================================================
test('VC9: performance — 5 MB transcript with all agents completed → exit 1 within 2s', { timeout: 10000 }, () => {
  const dir = makeTempDir();

  // Generate enough JSONL to exceed 5 MB.
  // Empirically each pair (tool_use + tool_result) is ~360 bytes (not 500),
  // so 15000 pairs gives ~5.1 MB safety margin above the 5 MB threshold.
  const lines = [];
  const PAIRS = 15000;
  for (let i = 0; i < PAIRS; i++) {
    const id = `call_perf_${String(i).padStart(6, '0')}`;
    lines.push(mainThreadAgentToolUse(id));
    lines.push(mainThreadToolResult(id));
  }

  const transcriptPath = writeTranscript(lines, dir);

  // Verify the file is actually >= 5 MB
  const { size } = statSync(transcriptPath);
  assert.ok(size >= 5 * 1024 * 1024, `transcript must be >= 5 MB, got ${size} bytes`);

  const start = Date.now();
  const result = runHasPending(transcriptPath);
  const elapsed = Date.now() - start;

  // All calls are completed → should return 1 (no pending)
  assert.equal(
    result.status,
    1,
    `Expected exit 1 (all completed) but got ${result.status}. stderr: ${result.stderr}`
  );

  assert.ok(
    elapsed < 2000,
    `Expected < 2000ms but took ${elapsed}ms (may need tail-based optimization)`
  );
});

// ===========================================================================
// Extra: verify the BASH_SOURCE guard exists (red-team structural check)
// The design doc states the function must be placed before L142 BASH_SOURCE
// guard so that `source stop-hook.sh` loads it without running hook logic.
// We validate this by confirming `source stop-hook.sh; declare -f
// has_pending_subagents` succeeds and prints a non-empty definition.
// ===========================================================================
test('structural: source stop-hook.sh exports has_pending_subagents function', () => {
  const result = spawnSync(
    'bash',
    ['-c', `source "${STOP_HOOK}"; declare -f has_pending_subagents`],
    { encoding: 'utf8', timeout: 5000 }
  );

  assert.equal(
    result.status,
    0,
    `source + declare -f failed (exit ${result.status}). ` +
    `Has has_pending_subagents been defined before the BASH_SOURCE guard? stderr: ${result.stderr}`
  );

  assert.ok(
    result.stdout.includes('has_pending_subagents'),
    `declare -f output does not contain "has_pending_subagents". stdout: ${result.stdout}`
  );
});
