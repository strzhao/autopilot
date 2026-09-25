/**
 * TaskStop 终止信号 — Acceptance Tests (v3.73.1 修复)
 *
 * 验证 `has_pending_subagents()` 的**第二类终止信号**：TaskStop 成功停止。
 *
 * 生产事故（raven-cli / fix-im-delivery-confirmation，2026-09-24）：
 *   任务 phase=implement 停在 iteration 1，stop-hook 每轮都判「有后台任务在跑」→
 *   §7.5 静默放行 → autopilot 循环整条死。根因：后台任务被 TaskStop 停掉后
 *   **不产生 <task-id> 完成通知**（harness 只回一条 tool_result
 *   "Successfully stopped task: <id>"），该 id 在启动集里永久悬挂。
 *   实测 CC 2.1.270 全库：显式停掉的 137 个任务里只有 17 个收到过通知。
 *
 * 契约（v3.73.1）：
 *   K1  终止集 = queue-operation enqueue 的 `<task-id>X</task-id>` 完成通知
 *       ∪ tool_result 文本 "Successfully stopped task: X"（**并集**，两者等价）。
 *   K2  终止信号对路径 B（异步 Agent，agentId）与路径 C（后台 Bash，
 *       backgroundTaskId）**同等生效**。
 *   K3  按 id 精确对账：停掉 X 不得闭合 Y（集合差，不是「凡有停止即清空」）。
 *   K4  只认成功字面量。TaskStop 失败文案（"Task not found"，不含 id）不闭合 ——
 *       保守朝 pending（宁可多等，不可漏判导致打断真的在跑的任务）。
 *   K5  两条实现路径同源：jq 精确路径与 jq 失败时的 grep fail-safe 文本路径
 *       必须给出相同判定（fail-safe 的计数对账只扣「停止 id ∩ 异步启动 id」）。
 *   K6  未受影响的既有语义保持：无终止信号 → 仍 pending（exit 0）。
 *
 * 边界与残余风险（留给后续审查，不在本次修复范围）：
 *   - TaskStop 若回 "Task not found"（全库 10/1017 次）且该任务也无完成通知，
 *     id 仍会悬挂 —— 待有实证事故再收（当前无观测到的悬挂样本）。
 *   - 终止信号是字面量匹配，harness 若改文案需同步本条与 stop-hook.sh 注释。
 *
 * Run: node --test plugins/autopilot/scripts/taskstop-terminal-signal.acceptance.test.mjs
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  mkdtempSync, writeFileSync, rmSync, chmodSync, readFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const STOP_HOOK = resolve(__dirname, 'stop-hook.sh');

// ---------------------------------------------------------------------------
// 临时目录 —— 进程退出时统一清理，避免污染 /tmp
// ---------------------------------------------------------------------------
const _tempDirs = [];
process.on('exit', () => {
  for (const d of _tempDirs) {
    try { rmSync(d, { recursive: true, force: true }); } catch { /* ignore */ }
  }
});

function makeTempDir() {
  const d = mkdtempSync(join(tmpdir(), 'taskstop-terminal-'));
  _tempDirs.push(d);
  return d;
}

// ---------------------------------------------------------------------------
// 核心调用：`source stop-hook.sh` 后直接调 has_pending_subagents（黑盒，只看退出码）。
// extraPath 传入时前置到 PATH —— 用于用 jq shim 强制走 fail-safe 文本路径。
// ---------------------------------------------------------------------------
function runHasPending(transcriptPath, { extraPath = null } = {}) {
  return spawnSync(
    'bash',
    ['-c', `source "${STOP_HOOK}"; has_pending_subagents "${transcriptPath}"`],
    {
      encoding: 'utf8',
      timeout: 30000,
      env: extraPath ? { ...process.env, PATH: `${extraPath}:${process.env.PATH}` } : process.env,
    }
  );
}

/** 造一个必定失败的 jq，用来把函数逼进 fail-safe 文本路径（K5）。 */
function makeJqFailureShim() {
  const d = makeTempDir();
  const shim = join(d, 'jq');
  writeFileSync(shim, '#!/bin/sh\nexit 127\n', 'utf8');
  chmodSync(shim, 0o755);
  return d;
}

// ---------------------------------------------------------------------------
// JSONL 构造器 —— 形态对齐真实 transcript（CC 2.1.270）
// ---------------------------------------------------------------------------

/** 后台 Bash 启动痕迹：toolUseResult.backgroundTaskId 非空（路径 C 启动集）。 */
function bgBashLaunch(toolUseId, backgroundTaskId) {
  return JSON.stringify({
    isSidechain: false,
    type: 'user',
    message: {
      role: 'user',
      content: [
        {
          type: 'tool_result',
          tool_use_id: toolUseId,
          content: [
            {
              type: 'text',
              text: `Command did not complete within its 180s timeout and was moved to the background (ID: ${backgroundTaskId}).`,
            },
          ],
        },
      ],
    },
    toolUseResult: { backgroundTaskId },
  });
}

/** 异步 Agent 启动痕迹（路径 B 启动集）：isAsync + async_launched + agentId。 */
function asyncAgentLaunch(toolUseId, agentId) {
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

/**
 * TaskStop 成功停止的 tool_result —— **真实形态**：content 是 JSON 字符串
 * （真实 transcript 里即 `{"message":"Successfully stopped task: <id> (…)"}`），
 * 不是 text block 数组。这条形态差异是本用例存在的理由之一。
 */
function taskStopSuccessString(toolUseId, taskId, cmd = 'pnpm test') {
  return JSON.stringify({
    isSidechain: false,
    type: 'user',
    message: {
      role: 'user',
      content: [
        {
          type: 'tool_result',
          tool_use_id: toolUseId,
          content: JSON.stringify({ message: `Successfully stopped task: ${taskId} (${cmd})` }),
        },
      ],
    },
    toolUseResult: { message: `Successfully stopped task: ${taskId} (${cmd})` },
  });
}

/** TaskStop 成功停止 —— text block 数组形态（另一条 harness 书写路径）。 */
function taskStopSuccessBlocks(toolUseId, taskId) {
  return JSON.stringify({
    isSidechain: false,
    type: 'user',
    message: {
      role: 'user',
      content: [
        {
          type: 'tool_result',
          tool_use_id: toolUseId,
          content: [{ type: 'text', text: `Successfully stopped task: ${taskId} (pnpm test)` }],
        },
      ],
    },
  });
}

/** TaskStop 失败（未含 id 的文案）——K4：不得闭合任何 id。 */
function taskStopNotFound(toolUseId) {
  return JSON.stringify({
    isSidechain: false,
    type: 'user',
    message: {
      role: 'user',
      content: [{ type: 'tool_result', tool_use_id: toolUseId, content: 'Task not found' }],
    },
  });
}

/** 完成通知：queue-operation enqueue + <task-id>X</task-id>。 */
function completionEnqueue(taskId, toolUseId) {
  return JSON.stringify({
    type: 'queue-operation',
    operation: 'enqueue',
    content: `<task-notification>\n<task-id>${taskId}</task-id>\n<tool-use-id>${toolUseId}</tool-use-id>\n<status>completed</status>\n<summary>done</summary>\n</task-notification>`,
  });
}

function writeTranscript(lines, dir, name = 'transcript.jsonl') {
  const p = join(dir, name);
  writeFileSync(p, lines.join('\n') + '\n', 'utf8');
  return p;
}

// ===========================================================================
// TS1 ｜ 主回归 ｜ 后台 Bash 被 TaskStop 停掉（真实字符串形态）、无完成通知
//        → exit 1（修复前 exit 0：id 永久悬挂）
// ===========================================================================
test('TS1: path C + TaskStop success (string content) → exit 1 (no pending)', () => {
  const dir = makeTempDir();
  const transcriptPath = writeTranscript([
    bgBashLaunch('toolu-ts1', 'bts1taskid'),
    taskStopSuccessString('toolu-ts1-stop', 'bts1taskid'),
  ], dir);

  const result = runHasPending(transcriptPath);
  assert.equal(
    result.status,
    1,
    `Expected exit 1 (TaskStop 已终止该后台任务) but got ${result.status}. stderr: ${result.stderr}`
  );
});

// ===========================================================================
// TS2 ｜ 形态覆盖 ｜ 同 TS1，但 tool_result.content 是 text block 数组
//        → exit 1（两条书写路径都要被识别）
// ===========================================================================
test('TS2: path C + TaskStop success (text-block array content) → exit 1', () => {
  const dir = makeTempDir();
  const transcriptPath = writeTranscript([
    bgBashLaunch('toolu-ts2', 'bts2taskid'),
    taskStopSuccessBlocks('toolu-ts2-stop', 'bts2taskid'),
  ], dir);

  const result = runHasPending(transcriptPath);
  assert.equal(
    result.status,
    1,
    `Expected exit 1 (数组形态的停止结果同样闭合) but got ${result.status}. stderr: ${result.stderr}`
  );
});

// ===========================================================================
// TS3 ｜ K3 按 id 精确对账 ｜ 停掉的是**另一个** id → 原任务仍 pending
//        → exit 0（治「凡有停止即清空」的过度闭合）
// ===========================================================================
test('TS3: stopping a different id must not close the launch → exit 0', () => {
  const dir = makeTempDir();
  const transcriptPath = writeTranscript([
    bgBashLaunch('toolu-ts3', 'bts3running'),
    taskStopSuccessString('toolu-ts3-stop', 'bts3other'),
  ], dir);

  const result = runHasPending(transcriptPath);
  assert.equal(
    result.status,
    0,
    `Expected exit 0 (被停的是别的 id，本任务仍在跑) but got ${result.status}. stderr: ${result.stderr}`
  );
});

// ===========================================================================
// TS4 ｜ K6 等待语义不被打通 ｜ 无任何终止信号 → 仍 exit 0
// ===========================================================================
test('TS4: launch without any terminal signal stays pending → exit 0', () => {
  const dir = makeTempDir();
  const transcriptPath = writeTranscript([
    bgBashLaunch('toolu-ts4', 'bts4running'),
  ], dir);

  const result = runHasPending(transcriptPath);
  assert.equal(
    result.status,
    0,
    `Expected exit 0 (无终止信号=仍在跑) but got ${result.status}. stderr: ${result.stderr}`
  );
});

// ===========================================================================
// TS5 ｜ 混合差集 ｜ 两个后台任务，只停其一 → exit 0；补停第二个 → exit 1
//        （差集语义：修复只能扣掉被停的那个，不能整体清空）
// ===========================================================================
test('TS5: partial stop — 2 launches, 1 stopped → exit 0; then 2nd stopped → exit 1', () => {
  const dir = makeTempDir();
  const partial = writeTranscript([
    bgBashLaunch('toolu-ts5a', 'bts5first'),
    bgBashLaunch('toolu-ts5b', 'bts5second'),
    taskStopSuccessString('toolu-ts5a-stop', 'bts5first'),
  ], dir, 'partial.jsonl');

  const r1 = runHasPending(partial);
  assert.equal(
    r1.status,
    0,
    `Expected exit 0 (还剩 bts5second 未终止) but got ${r1.status}. stderr: ${r1.stderr}`
  );

  const both = writeTranscript([
    bgBashLaunch('toolu-ts5a', 'bts5first'),
    bgBashLaunch('toolu-ts5b', 'bts5second'),
    taskStopSuccessString('toolu-ts5a-stop', 'bts5first'),
    taskStopSuccessString('toolu-ts5b-stop', 'bts5second'),
  ], dir, 'both-stopped.jsonl');

  const r2 = runHasPending(both);
  assert.equal(
    r2.status,
    1,
    `Expected exit 1 (两个都已终止) but got ${r2.status}. stderr: ${r2.stderr}`
  );
});

// ===========================================================================
// TS6 ｜ K2 路径 B 同等生效 ｜ 异步 Agent 被停、无完成通知 → exit 1
//        （Agent 的终止同样不发 <task-id> 通知）
// ===========================================================================
test('TS6: path B async Agent stopped via TaskStop → exit 1', () => {
  const dir = makeTempDir();
  const transcriptPath = writeTranscript([
    asyncAgentLaunch('toolu-ts6', 'agentts6'),
    taskStopSuccessString('toolu-ts6-stop', 'agentts6'),
  ], dir);

  const result = runHasPending(transcriptPath);
  assert.equal(
    result.status,
    1,
    `Expected exit 1 (异步 Agent 已被停) but got ${result.status}. stderr: ${result.stderr}`
  );
});

// ===========================================================================
// TS7 ｜ K1 并集语义 ｜ 任务 A 收到完成通知、任务 B 被 TaskStop 停掉
//        → exit 1（两种终止信号都要生效，不能只认一种）
// ===========================================================================
test('TS7: union of terminal signals — notification for A + stop for B → exit 1', () => {
  const dir = makeTempDir();
  const transcriptPath = writeTranscript([
    bgBashLaunch('toolu-ts7a', 'bts7notified'),
    bgBashLaunch('toolu-ts7b', 'bts7stopped'),
    completionEnqueue('bts7notified', 'toolu-ts7a'),
    taskStopSuccessString('toolu-ts7b-stop', 'bts7stopped'),
  ], dir);

  const result = runHasPending(transcriptPath);
  assert.equal(
    result.status,
    1,
    `Expected exit 1 (通知 ∪ 停止 覆盖两个任务) but got ${result.status}. stderr: ${result.stderr}`
  );
});

// ===========================================================================
// TS8 ｜ K4 失败文案不闭合 ｜ 只有 "Task not found"（无 id）→ 仍 exit 0
// ===========================================================================
test('TS8: failed TaskStop ("Task not found") does not close the launch → exit 0', () => {
  const dir = makeTempDir();
  const transcriptPath = writeTranscript([
    bgBashLaunch('toolu-ts8', 'bts8running'),
    taskStopNotFound('toolu-ts8-stop'),
  ], dir);

  const result = runHasPending(transcriptPath);
  assert.equal(
    result.status,
    0,
    `Expected exit 0 (失败文案不闭合，保守朝 pending) but got ${result.status}. stderr: ${result.stderr}`
  );
});

// ===========================================================================
// FS1 ｜ K5 fail-safe 文本路径 ｜ jq 不可用 + TaskStop 停掉 → exit 1
//        （jq 路径与 fail-safe 路径必须同源；shim 让 jq 必定失败）
// ===========================================================================
test('FS1: fail-safe text path — stopped id closes the launch → exit 1', () => {
  const dir = makeTempDir();
  const transcriptPath = writeTranscript([
    bgBashLaunch('toolu-fs1', 'bfs1stopped'),
    taskStopSuccessString('toolu-fs1-stop', 'bfs1stopped'),
  ], dir);
  const shimDir = makeJqFailureShim();

  const result = runHasPending(transcriptPath, { extraPath: shimDir });
  assert.equal(
    result.status,
    1,
    `Expected exit 1 via fail-safe path but got ${result.status}. stderr: ${result.stderr}`
  );
});

// ===========================================================================
// FS2 ｜ K5 反向 ｜ jq 不可用 + 无终止信号 → exit 0（fail-safe 仍会等待）
// ===========================================================================
test('FS2: fail-safe text path — launch without terminal signal stays pending → exit 0', () => {
  const dir = makeTempDir();
  const transcriptPath = writeTranscript([
    bgBashLaunch('toolu-fs2', 'bfs2running'),
  ], dir);
  const shimDir = makeJqFailureShim();

  const result = runHasPending(transcriptPath, { extraPath: shimDir });
  assert.equal(
    result.status,
    0,
    `Expected exit 0 via fail-safe path but got ${result.status}. stderr: ${result.stderr}`
  );
});

// ===========================================================================
// FS3 ｜ K5 计数对账 ｜ jq 不可用 + 异步 Agent 被停 → exit 1
//        （fail-safe 的 launched/completed 计数须扣掉被停的异步 Agent，
//         否则计数差恒 >0 → 同一类静默卡死换个入口复现）
// ===========================================================================
test('FS3: fail-safe counting — stopped async Agent is subtracted → exit 1', () => {
  const dir = makeTempDir();
  const transcriptPath = writeTranscript([
    asyncAgentLaunch('toolu-fs3', 'agentfs3'),
    taskStopSuccessString('toolu-fs3-stop', 'agentfs3'),
  ], dir);
  const shimDir = makeJqFailureShim();

  const result = runHasPending(transcriptPath, { extraPath: shimDir });
  assert.equal(
    result.status,
    1,
    `Expected exit 1 via fail-safe counting but got ${result.status}. stderr: ${result.stderr}`
  );
});

// ===========================================================================
// FS4 ｜ K5 计数不被过度抵消 ｜ jq 不可用 + 后台 Bash 被停、且有另一异步
//        Agent 仍在跑 → 仍 exit 0（后台 Bash 的停止不得扣减异步计数）
// ===========================================================================
test('FS4: fail-safe counting must not over-subtract (bash stop ≠ async stop) → exit 0', () => {
  const dir = makeTempDir();
  const transcriptPath = writeTranscript([
    asyncAgentLaunch('toolu-fs4', 'agentfs4running'),
    bgBashLaunch('toolu-fs4-bash', 'bfs4stopped'),
    taskStopSuccessString('toolu-fs4-stop', 'bfs4stopped'),
  ], dir);
  const shimDir = makeJqFailureShim();

  const result = runHasPending(transcriptPath, { extraPath: shimDir });
  assert.equal(
    result.status,
    0,
    `Expected exit 0 (异步 Agent 仍在跑) but got ${result.status}. stderr: ${result.stderr}`
  );
});

// ===========================================================================
// 前置自检 ｜ 夹具与真实 transcript 的形态假设必须成立，否则上面用例的
//            结论会退化为「测了个不存在的形态」。这里断言 stop-hook 源码里
//            确实出现了停止字面量与 id 捕获（防文案漂移后测试静默失效）。
// ===========================================================================
test('fixture sanity: stop-hook.sh carries the TaskStop literal capture', () => {
  const src = readFileSync(STOP_HOOK, 'utf8');
  assert.ok(
    src.includes('Successfully stopped task: (?<id>[A-Za-z0-9]+)'),
    'stop-hook.sh 必须包含 jq 侧的 TaskStop id 捕获字面量'
  );
  assert.ok(
    src.includes("grep -ao 'Successfully stopped task: [A-Za-z0-9]*'"),
    'stop-hook.sh 必须包含 fail-safe 侧的 TaskStop id 提取字面量'
  );
});
