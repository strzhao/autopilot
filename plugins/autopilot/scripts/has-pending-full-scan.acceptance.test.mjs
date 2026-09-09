/**
 * has_pending_subagents full-transcript scan — Acceptance Tests (Red Team)
 *
 * Tests verify the v3.66.x follow-up fix contract for `has_pending_subagents()`
 * in stop-hook.sh. Written purely from the design spec + contract C1-C5 without
 * reading the blue-team implementation (which is being modified concurrently).
 *
 * Contract (verbatim from design doc):
 *   C1  exit 0 = has pending; exit 1 = no pending OR any error degradation.
 *       Degradation must lean fail-safe (prefer false "pending" over a miss).
 *   C2  Path B async Agent = set of agentId where toolUseResult.isAsync==true &&
 *       status=="async_launched"  MINUS  queue-operation enqueue `<task-id>X</task-id>`
 *       notification set. Path C background Bash = non-empty `backgroundTaskId`
 *       set MINUS the same notification set.
 *   C3  Set computation input = FULL transcript (core invariant of this fix):
 *       a launched marker no matter how old (even at file head, >4MB from the
 *       end) must be detected as long as no completion notification exists.
 *   C4  Marker formats: `<task-id>X</task-id>`; `"isAsync":true` /
 *       `"status":"async_launched"` / `agentId`; `backgroundTaskId`.
 *   C5  Caller (stop-hook §7.5) consumes only the exit code.
 *   C6  Existing suites (pending-subagent / stop-hook-pending-gate) stay green.
 *
 * Regression targets:
 *   D1  macOS `wc -c` leading-space made the ">4MB → drop first line" condition
 *       never fire, so jq always choked on the half first line and degraded to
 *       the grep fail-safe. Fix: jq path must succeed on the full read.
 *   D2  Set computation only looked at the last-4MB window; live sidechain
 *       traffic pushed async launch markers out of the window → false negative
 *       → dead-loop re-injection. Fix: compute sets from the FULL transcript.
 *
 * Run: node --test <this-file>
 */

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  mkdtempSync, writeFileSync, appendFileSync, readFileSync,
  rmSync, existsSync, statSync, copyFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

// ---------------------------------------------------------------------------
// Locate stop-hook.sh. This file lives in the acceptance-staging dir during
// red-team review and is later moved to plugins/autopilot/scripts/ next to
// stop-hook.sh — so resolve by walking up to the repo root first, falling
// back to the sibling-location convention used by the existing suites.
// ---------------------------------------------------------------------------
function findStopHook() {
  let dir = __dirname;
  for (let i = 0; i < 15; i++) {
    const candidate = join(dir, 'plugins', 'autopilot', 'scripts', 'stop-hook.sh');
    if (existsSync(candidate)) return candidate;
    const parent = dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return resolve(__dirname, 'stop-hook.sh');
}
const STOP_HOOK = findStopHook();

// ---------------------------------------------------------------------------
// Temporary workspace — cleaned up at process exit.
// ---------------------------------------------------------------------------
const _tempDirs = [];
process.on('exit', () => {
  for (const d of _tempDirs) {
    try { rmSync(d, { recursive: true, force: true }); } catch { /* ignore */ }
  }
});

function makeTempDir() {
  const d = mkdtempSync(join(tmpdir(), 'has-pending-full-scan-'));
  _tempDirs.push(d);
  return d;
}

// ---------------------------------------------------------------------------
// Core helper — invoke `has_pending_subagents` via `source stop-hook.sh`.
// Black-box: relies only on contract C1/C5 (exit code is the only observed
// channel here; stderr is additionally inspected for P2/P3 signals).
// ---------------------------------------------------------------------------
function runHasPending(transcriptPath, timeoutMs = 30000) {
  return spawnSync(
    'bash',
    ['-c', `source "${STOP_HOOK}"; has_pending_subagents "${transcriptPath}"`],
    { encoding: 'utf8', timeout: timeoutMs }
  );
}

// ---------------------------------------------------------------------------
// Constants for the >4MB window-blind fixtures (C3).
// ---------------------------------------------------------------------------
const WINDOW = 4 * 1024 * 1024;          // 4 MiB tail window from the old design
// Half-written first JSON line (no closure) — simulates a transcript whose
// first line got cut (what `tail -c 4M` used to hand to jq mid-file).
const TRUNCATED_FIRST_LINE = '{"parentUuid":"abc';
// ~4KB filler line; contains NONE of the marker substrings (isAsync /
// async_launched / agentId / backgroundTaskId / task-id / status).
function fillerLine(seq) {
  return JSON.stringify({ type: 'progress', seq, pad: 'f'.repeat(4000) });
}
const FILLER_COUNT = 1300; // 1300 × ~4.04KB ≈ 5.25MB of traffic after the marker

// ---------------------------------------------------------------------------
// JSONL builders — shapes mirror pending-subagent.acceptance.test.mjs.
// ---------------------------------------------------------------------------

/** Main-thread assistant message calling an Agent/Task tool. */
function mainThreadAgentToolUse(id, toolName = 'Agent') {
  return JSON.stringify({
    isSidechain: false,
    type: 'assistant',
    message: {
      role: 'assistant',
      content: [
        { type: 'tool_use', id, name: toolName, input: { prompt: 'do some work', options: {} } },
      ],
    },
  });
}

/** Async Agent launch tool_result — toolUseResult.isAsync==true marks it (C2/C4). */
function asyncLaunchedToolResult(toolUseId, agentId) {
  return JSON.stringify({
    isSidechain: false,
    type: 'user',
    message: {
      role: 'user',
      content: [
        {
          type: 'tool_result',
          tool_use_id: toolUseId,
          content: [{ type: 'text', text: `Async agent launched successfully.\nagentId: ${agentId}` }],
        },
      ],
    },
    toolUseResult: { isAsync: true, status: 'async_launched', agentId },
  });
}

/** Background Bash launch tool_result — non-empty `backgroundTaskId` marks it (C2/C4). */
function bgBashLaunchToolResult(toolUseId, backgroundTaskId) {
  return JSON.stringify({
    isSidechain: false,
    type: 'user',
    message: {
      role: 'user',
      content: [
        {
          type: 'tool_result',
          tool_use_id: toolUseId,
          content: [{ type: 'text', text: 'Command running in background' }],
        },
      ],
    },
    toolUseResult: { backgroundTaskId },
  });
}

/** Completion notification — queue-operation enqueue with <task-id>X</task-id> (C2/C4). */
function asyncCompletionEnqueue(taskId, toolUseId) {
  return JSON.stringify({
    type: 'queue-operation',
    operation: 'enqueue',
    content: `<task-notification>\n<task-id>${taskId}</task-id>\n<tool-use-id>${toolUseId}</tool-use-id>\n<status>completed</status>\n<summary>done</summary>\n</task-notification>`,
  });
}

// ---------------------------------------------------------------------------
// Fixture writers
// ---------------------------------------------------------------------------

/**
 * P1/P2 shared fixture (D1+D2 regression):
 *   line 1      = truncated half JSON
 *   line 2      = async launched marker (FRONT of file)
 *   line 3..end = ~5.25MB of marker-free filler traffic
 * ⇒ the launched marker sits >4MB away from the file end (outside the old
 *   tail window) and no completion notification exists anywhere.
 * Hard preconditions (size, marker distance) are asserted, not assumed.
 */
function writeWindowBlindFixture(dir) {
  const agentId = 'agent-fullscan-p1';
  const toolUseId = 'toolu-fullscan-p1';
  const lines = [
    TRUNCATED_FIRST_LINE,
    mainThreadAgentToolUse(toolUseId),
    asyncLaunchedToolResult(toolUseId, agentId),
  ];
  for (let i = 0; i < FILLER_COUNT; i++) lines.push(fillerLine(i));

  const p = join(dir, 'window-blind.jsonl');
  writeFileSync(p, lines.join('\n') + '\n', 'utf8');
  assertMarkerBeyondWindow(p, agentId);
  return p;
}

/**
 * Reverse fixture (P3): launched marker + its matching completion enqueue BOTH
 * in the file head, followed by >4MB filler. Legal transcript (all lines valid
 * JSON). Per C3 the whole set computation (launched set AND notification set)
 * must read the full transcript — so the old notification must still cancel
 * the old launch even though both are outside the tail window.
 */
function writeOffsetPairFixture(dir) {
  const agentId = 'agent-fullscan-p3';
  const toolUseId = 'toolu-fullscan-p3';
  const lines = [
    mainThreadAgentToolUse(toolUseId),
    asyncLaunchedToolResult(toolUseId, agentId),
    asyncCompletionEnqueue(agentId, toolUseId),
  ];
  for (let i = 0; i < FILLER_COUNT; i++) lines.push(fillerLine(i));

  const p = join(dir, 'offset-pair.jsonl');
  writeFileSync(p, lines.join('\n') + '\n', 'utf8');
  assertMarkerBeyondWindow(p, agentId);
  return p;
}

/** Path C fixture: backgroundTaskId launch in the head, >4MB filler after. */
function writeBgBashFixture(dir, withNotification) {
  const bgTaskId = 'bash-fullscan-e2';
  const toolUseId = 'toolu-fullscan-e2';
  const lines = [
    mainThreadAgentToolUse(toolUseId, 'Bash'),
    bgBashLaunchToolResult(toolUseId, bgTaskId),
  ];
  if (withNotification) lines.push(asyncCompletionEnqueue(bgTaskId, toolUseId));
  for (let i = 0; i < FILLER_COUNT; i++) lines.push(fillerLine(i));

  const p = join(dir, `bg-bash-${withNotification ? 'done' : 'pending'}.jsonl`);
  writeFileSync(p, lines.join('\n') + '\n', 'utf8');
  assertMarkerBeyondWindow(p, bgTaskId);
  return p;
}

/** Hard precondition: file >4MB AND the marker token sits >4MB from the end. */
function assertMarkerBeyondWindow(transcriptPath, uniqueToken) {
  const buf = readFileSync(transcriptPath);
  assert.ok(
    buf.length > WINDOW,
    `precondition: fixture must be >4MB (${WINDOW} bytes), got ${buf.length}`
  );
  const off = buf.indexOf(Buffer.from(uniqueToken, 'utf8'));
  assert.notEqual(off, -1, `precondition: marker token "${uniqueToken}" must exist in fixture`);
  const distFromEnd = buf.length - off;
  assert.ok(
    distFromEnd > WINDOW,
    `precondition: marker must be >4MB from file end (outside old tail window), ` +
    `got ${distFromEnd} bytes`
  );
}

// ===========================================================================
// P1 ｜ 窗口盲区回归（D2）｜ >4MB transcript, async launched marker only in the
// head (>4MB from end), no completion notification → rc=0 (pending detected).
// The old windowed set computation returned 1 here (marker outside window).
// ===========================================================================
test('P1: window-blind regression — async launched marker >4MB from end, no notification → exit 0', { timeout: 60000 }, () => {
  const dir = makeTempDir();
  const transcriptPath = writeWindowBlindFixture(dir);

  const result = runHasPending(transcriptPath);
  assert.equal(
    result.status,
    0,
    `Expected exit 0 (pending detected from full transcript scan) but got ${result.status}. ` +
    `stderr: ${result.stderr}`
  );
});

// ===========================================================================
// P2 ｜ macOS wc 空格回归（D1）｜ same fixture — the jq path (not the grep
// fail-safe) must succeed despite the truncated half first line.
// assert: stderr 含「jq 检测出」且不含「fail-safe」.
// ===========================================================================
test('P2: macOS wc-space regression — jq success path, not fail-safe (stderr signal)', { timeout: 60000 }, () => {
  const dir = makeTempDir();
  const transcriptPath = writeWindowBlindFixture(dir);

  const result = runHasPending(transcriptPath);
  assert.ok(
    result.stderr.includes('jq 检测出'),
    `Expected stderr to contain "jq 检测出" (jq path succeeded) but stderr was: ${result.stderr}`
  );
  assert.ok(
    !result.stderr.includes('fail-safe'),
    `Expected stderr NOT to contain "fail-safe" (must not degrade to grep fallback) but stderr was: ${result.stderr}`
  );
});

// ===========================================================================
// P3 ｜ 反向 no-pending ｜ launched + matching completion notification, both
// >4MB from end (C3 applies to the whole set computation, notification set
// included) → rc=1 and stderr has no fail-safe (jq path succeeded).
// ===========================================================================
test('P3: reverse no-pending — launched marker cancelled by completion notification → exit 1, no fail-safe', { timeout: 60000 }, () => {
  const dir = makeTempDir();
  const transcriptPath = writeOffsetPairFixture(dir);

  const result = runHasPending(transcriptPath);
  assert.equal(
    result.status,
    1,
    `Expected exit 1 (completion notification cancels launch) but got ${result.status}. ` +
    `stderr: ${result.stderr}`
  );
  assert.ok(
    !result.stderr.includes('fail-safe'),
    `Expected stderr NOT to contain "fail-safe" (jq path must succeed) but stderr was: ${result.stderr}`
  );
});

// ===========================================================================
// P4 ｜ 真实产物真值 ｜ copy the real >4MB transcript, append a fresh agentId
// async_launched line (guaranteed pending — no completion notification for it,
// and the copy is detached from the live session) → rc=0.
// ===========================================================================
const REAL_TRANSCRIPT = '/Users/stringzhao/.claude/projects/-Users-stringzhao-workspace-martin/f86ca374-43cd-45b3-a912-36b6cc64895c.jsonl';

test('P4: real-transcript truth — real >4MB transcript + appended fresh async launch → exit 0', { timeout: 60000 }, () => {
  assert.ok(existsSync(REAL_TRANSCRIPT), `precondition: real transcript must exist: ${REAL_TRANSCRIPT}`);
  const { size } = statSync(REAL_TRANSCRIPT);
  assert.ok(size > WINDOW, `precondition: real transcript must be >4MB, got ${size} bytes`);

  const dir = makeTempDir();
  const copyPath = join(dir, 'real-transcript-copy.jsonl');
  copyFileSync(REAL_TRANSCRIPT, copyPath);

  // Ensure the appended line starts on its own line even if the copy does not
  // end with a trailing newline.
  const fdBuf = readFileSync(copyPath);
  if (fdBuf.length > 0 && fdBuf[fdBuf.length - 1] !== 0x0a) {
    appendFileSync(copyPath, '\n', 'utf8');
  }

  const freshAgentId = 'rt-real-truth-agent';
  const freshToolUseId = 'toolu-rt-real-truth-001';
  const injected = [
    mainThreadAgentToolUse(freshToolUseId),
    asyncLaunchedToolResult(freshToolUseId, freshAgentId),
  ].join('\n') + '\n';
  appendFileSync(copyPath, injected, 'utf8');

  // Precondition: the fresh agentId appears exactly once (no stray completion
  // notification for it anywhere in the real transcript).
  const occurrences = readFileSync(copyPath, 'utf8').split(freshAgentId).length - 1;
  assert.equal(
    occurrences,
    2,
    `precondition: fresh agentId must appear exactly twice (launch line: text + field), got ${occurrences}`
  );

  const result = runHasPending(copyPath, 60000);
  assert.equal(
    result.status,
    0,
    `Expected exit 0 (fresh async launch pending in real transcript) but got ${result.status}. ` +
    `stderr: ${result.stderr}`
  );
});

// ===========================================================================
// 边界补充 E1 ｜ 错误降级方向 ｜ transcript path does not exist → exit 1 (C1).
// ===========================================================================
test('E1: degradation — non-existent transcript path → exit 1', () => {
  const nonExistentPath = join(tmpdir(), 'has-pending-full-scan-does-not-exist-9999.jsonl');
  assert.ok(!existsSync(nonExistentPath), 'precondition: file must not exist');

  const result = runHasPending(nonExistentPath);
  assert.equal(
    result.status,
    1,
    `Expected exit 1 for non-existent path but got ${result.status}. stderr: ${result.stderr}`
  );
});

// ===========================================================================
// 边界补充 E2 ｜ 路径 C 全量检出 ｜ backgroundTaskId launch marker >4MB from
// end, no notification → rc=0 (Path C must be computed from the full
// transcript too, not just the tail window).
// ===========================================================================
test('E2: path C full scan — backgroundTaskId marker >4MB from end, no notification → exit 0', { timeout: 60000 }, () => {
  const dir = makeTempDir();
  const transcriptPath = writeBgBashFixture(dir, false);

  const result = runHasPending(transcriptPath);
  assert.equal(
    result.status,
    0,
    `Expected exit 0 (background Bash still running) but got ${result.status}. ` +
    `stderr: ${result.stderr}`
  );
});

// ===========================================================================
// 边界补充 E3 ｜ 路径 C 对冲 ｜ backgroundTaskId launch + matching completion
// notification, both >4MB from end → rc=1.
// ===========================================================================
test('E3: path C offset pair — backgroundTaskId cancelled by notification, both >4MB from end → exit 1', { timeout: 60000 }, () => {
  const dir = makeTempDir();
  const transcriptPath = writeBgBashFixture(dir, true);

  const result = runHasPending(transcriptPath);
  assert.equal(
    result.status,
    1,
    `Expected exit 1 (background task completed via notification) but got ${result.status}. ` +
    `stderr: ${result.stderr}`
  );
});
