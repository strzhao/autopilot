/**
 * Stop Hook Pending Gate — 跨阶段 pending 门控集成测试（Red Team）
 *
 * 验收依据：设计契约（不读取 §7.5 实现细节）
 *
 * 核心契约：
 *   - 任何 phase（design/implement/qa/auto-fix/merge）下，只要 transcript 中存在
 *     pending sub-agent，stop-hook 必须「静默等待」：exit 0 且 stdout 不输出
 *     任何 block JSON（不注入 prompt）。
 *   - phase=merge + 后台异步 commit-agent（async_launched 无 completed）→ 必须静默。
 *     这是本次根治的「近似死循环」场景（flag-asymmetry 历史 bug，2026-05-26）。
 *   - phase=merge + 无 pending → 正常注入：stdout 含 "decision":"block" 且
 *     reason 中含 "commit-agent"。
 *   - 错误降级：检测函数遇任何错误降级为「无 pending」（不产生假阳性静默）。
 *
 * 测试驱动方式：端到端驱动整个 stop-hook.sh（非 source 单函数测试），
 * 通过 stdin 传入 {cwd, session_id, transcript_path} JSON，观察 stdout / exit code。
 *
 * Run: node --test plugins/autopilot/scripts/stop-hook-pending-gate.acceptance.test.mjs
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync, execSync } from 'node:child_process';
import {
  mkdtempSync, writeFileSync, mkdirSync, rmSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const STOP_HOOK = resolve(__dirname, 'stop-hook.sh');

// ---------------------------------------------------------------------------
// 临时目录管理 — 退出时自动清理，避免污染 CI 环境
// ---------------------------------------------------------------------------
const _tempDirs = [];
process.on('exit', () => {
  for (const d of _tempDirs) {
    try { rmSync(d, { recursive: true, force: true }); } catch { /* ignore */ }
  }
});

function makeTempDir() {
  const d = mkdtempSync(join(tmpdir(), 'stop-hook-pending-gate-'));
  _tempDirs.push(d);
  return d;
}

// ---------------------------------------------------------------------------
// JSONL builders — 复用 pending-subagent.acceptance.test.mjs 风格
// ---------------------------------------------------------------------------

/** 主线程 Agent/Task tool_use（isSidechain=false）*/
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

/** 主线程同步 tool_result（对应某个 tool_use_id）*/
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

/**
 * 异步 Agent 启动 tool_result —
 * toolUseResult.isAsync==true && status=="async_launched"
 * 路径 A（同步检测）会认为它已完成，路径 B（异步检测）才能识别它仍在跑。
 */
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

/** 异步 Agent 完成通知 — queue-operation enqueue 含 <task-id>agentId</task-id> */
function asyncCompletionEnqueue(agentId, toolUseId) {
  return JSON.stringify({
    type: 'queue-operation',
    operation: 'enqueue',
    content: `<task-notification>\n<task-id>${agentId}</task-id>\n<tool-use-id>${toolUseId}</tool-use-id>\n<status>completed</status>\n<summary>Agent done</summary>\n</task-notification>`,
  });
}

/** 写 JSONL 到指定目录，返回文件绝对路径 */
function writeTranscript(lines, dir, filename = 't.jsonl') {
  const p = join(dir, filename);
  writeFileSync(p, lines.join('\n') + '\n', 'utf8');
  return p;
}

// ---------------------------------------------------------------------------
// 临时 git repo 构造辅助
//
// stop-hook.sh 通过 `git rev-parse --show-toplevel` 定位 PROJECT_ROOT，
// 所以 cwd 必须在一个合法的 git 仓库中。
// ---------------------------------------------------------------------------

/**
 * 在 tmpDir 内初始化 git repo，创建 autopilot 目录结构，
 * 写入 active.ptr 和 state.md，返回 { tmpDir, slug, sessionId, statePath }。
 *
 * @param {object} opts
 * @param {string} opts.phase        - state.md frontmatter phase 值
 * @param {string} [opts.sessionId]  - 如不传则自动生成
 */
function setupTestRepo({ phase, sessionId }) {
  const tmpDir = makeTempDir();
  const sid = sessionId || `test-session-${Date.now()}`;
  const slug = `test-task-${phase}`;

  // 初始化 git repo（确保 git rev-parse --show-toplevel 能正确解析）
  execSync('git init -q', { cwd: tmpDir });
  execSync('git config user.email "test@test.com"', { cwd: tmpDir });
  execSync('git config user.name "Test"', { cwd: tmpDir });

  // 构造目录结构
  const runtimeDir = join(tmpDir, '.autopilot', 'runtime');
  const requirementsDir = join(runtimeDir, 'requirements', slug);
  mkdirSync(requirementsDir, { recursive: true });

  // active.ptr → slug
  writeFileSync(join(runtimeDir, 'active.ptr'), slug, 'utf8');

  // state.md — 合法 frontmatter（session_id 与 stdin 匹配，gate 为空）
  const stateContent = [
    '---',
    `phase: ${phase}`,
    `gate: ""`,
    `iteration: 6`,
    `max_iterations: 30`,
    `max_retries: 3`,
    `retry_count: 0`,
    `session_id: ${sid}`,
    `mode: single`,
    `knowledge_extracted: ""`,
    '---',
    '',
    '## 任务描述',
    '',
    `这是 phase=${phase} 的测试任务。`,
    '',
  ].join('\n');
  writeFileSync(join(requirementsDir, 'state.md'), stateContent, 'utf8');

  return { tmpDir, slug, sessionId: sid, statePath: join(requirementsDir, 'state.md') };
}

// ---------------------------------------------------------------------------
// 核心测试驱动函数 — 通过 stdin 驱动完整 stop-hook.sh
// ---------------------------------------------------------------------------

/**
 * 驱动 stop-hook.sh，捕获 stdout / exit code / stderr。
 *
 * @param {string} cwd           - git 仓库根目录（tmpDir）
 * @param {string} sessionId     - 与 state.md 中 session_id 一致
 * @param {string} transcriptPath - JSONL 文件绝对路径
 */
function runStopHook(cwd, sessionId, transcriptPath) {
  const input = JSON.stringify({ cwd, session_id: sessionId, transcript_path: transcriptPath });
  return spawnSync(
    'bash',
    [STOP_HOOK],
    {
      input,
      encoding: 'utf8',
      timeout: 15000,
    }
  );
}

// ===========================================================================
// 用例 A: phase=merge + pending 异步 commit-agent → 静默
//
// 契约点：merge 阶段后台异步 commit-agent（async_launched，无 completed）
//   必须让 stop-hook 静默等待（exit 0，stdout 不含任何 block JSON）。
//   这是本次根治的「近似死循环」场景的核心回归测试。
// ===========================================================================
test('A: phase=merge + pending async commit-agent → 静默（无 block JSON）', () => {
  const { tmpDir, sessionId } = setupTestRepo({ phase: 'merge' });

  const transcriptPath = writeTranscript([
    // 主线程启动 commit-agent（run_in_background=true）
    mainThreadAgentToolUse('toolu_merge_commit_001'),
    // 立即返回的 async launched tool_result（Path A 认为完成，Path B 识别为仍运行中）
    asyncLaunchedToolResult('toolu_merge_commit_001', 'agent-commit-abc123'),
    // !! 关键：无对应 queue-operation enqueue — commit-agent 仍在后台跑
  ], tmpDir);

  const result = runStopHook(tmpDir, sessionId, transcriptPath);

  // 静默等待：不输出任何 block JSON
  assert.ok(
    !result.stdout.includes('"decision"'),
    `[A] stdout 不应含 "decision"，实际 stdout: ${result.stdout}\nstderr: ${result.stderr}`
  );
  assert.ok(
    !result.stdout.includes('"block"'),
    `[A] stdout 不应含 "block"，实际 stdout: ${result.stdout}\nstderr: ${result.stderr}`
  );
  assert.ok(
    !result.stdout.includes('commit-agent'),
    `[A] stdout 不应含 "commit-agent"（即未注入 merge prompt），实际 stdout: ${result.stdout}\nstderr: ${result.stderr}`
  );
});

// ===========================================================================
// 用例 B: phase=merge + 无 pending → 正常注入 commit-agent prompt
//
// 契约点（反向契约）：无 pending 时 stop-hook 维持正常注入行为 ——
//   phase=merge 时 stdout 必须含 "decision":"block" 且 reason 含 "commit-agent"。
// ===========================================================================
test('B: phase=merge + 无 pending（transcript 含 completed enqueue）→ 正常注入含 commit-agent 的 block JSON', () => {
  const { tmpDir, sessionId } = setupTestRepo({ phase: 'merge' });

  const transcriptPath = writeTranscript([
    // 异步 commit-agent — 已完成（有 completed enqueue）
    mainThreadAgentToolUse('toolu_merge_done_001'),
    asyncLaunchedToolResult('toolu_merge_done_001', 'agent-done-xyz'),
    asyncCompletionEnqueue('agent-done-xyz', 'toolu_merge_done_001'),
    // 无其他 pending agent
  ], tmpDir);

  const result = runStopHook(tmpDir, sessionId, transcriptPath);

  // 正常注入：stdout 必须含 decision:block 且 reason 含 commit-agent
  assert.ok(
    result.stdout.includes('"decision"'),
    `[B] stdout 应含 "decision"，实际 stdout: ${result.stdout}\nstderr: ${result.stderr}`
  );
  assert.ok(
    result.stdout.includes('"block"'),
    `[B] stdout 应含 "block"，实际 stdout: ${result.stdout}\nstderr: ${result.stderr}`
  );
  assert.ok(
    result.stdout.includes('commit-agent'),
    `[B] stdout 的 reason 中应含 "commit-agent"，实际 stdout: ${result.stdout}\nstderr: ${result.stderr}`
  );
});

// ===========================================================================
// 用例 C: phase=qa + pending sub-agent → 静默
//
// 契约点（泛化验证）：pending 门控必须在 merge 以外的阶段同样生效，
//   防止 flag-asymmetry（仅修单点、其他阶段留同类漏洞）。
//   qa 阶段 qa-reviewer sub-agent 后台运行期间 stop-hook 必须静默。
// ===========================================================================
test('C: phase=qa + pending async sub-agent（qa-reviewer）→ 静默（无 block JSON）', () => {
  const { tmpDir, sessionId } = setupTestRepo({ phase: 'qa' });

  const transcriptPath = writeTranscript([
    // qa 阶段启动了 qa-reviewer（run_in_background=true）
    mainThreadAgentToolUse('toolu_qa_reviewer_001'),
    asyncLaunchedToolResult('toolu_qa_reviewer_001', 'agent-qa-reviewer-bcd456'),
    // 无 completed enqueue — qa-reviewer 仍在后台
  ], tmpDir);

  const result = runStopHook(tmpDir, sessionId, transcriptPath);

  assert.ok(
    !result.stdout.includes('"decision"'),
    `[C] stdout 不应含 "decision"（qa 阶段有 pending 应静默），实际 stdout: ${result.stdout}\nstderr: ${result.stderr}`
  );
  assert.ok(
    !result.stdout.includes('"block"'),
    `[C] stdout 不应含 "block"，实际 stdout: ${result.stdout}\nstderr: ${result.stderr}`
  );
});

// ===========================================================================
// 用例 D: phase=implement + pending sync sub-agent → 静默（回归保护）
//
// 契约点（既有行为保护）：implement 阶段蓝队/红队 sub-agent pending 时
//   stop-hook 应静默等待，不注入 prompt。本用例确保新修复未破坏既有行为。
//   使用同步路径 A（主线程 tool_use 无 tool_result）场景。
// ===========================================================================
test('D: phase=implement + pending sync sub-agent（蓝队）→ 静默（回归保护）', () => {
  const { tmpDir, sessionId } = setupTestRepo({ phase: 'implement' });

  const transcriptPath = writeTranscript([
    // 主线程启动蓝队 sub-agent（同步路径 A：有 tool_use，无 tool_result）
    mainThreadAgentToolUse('toolu_blue_team_001'),
    // !! 关键：无对应 tool_result — 蓝队仍在运行中
  ], tmpDir);

  const result = runStopHook(tmpDir, sessionId, transcriptPath);

  assert.ok(
    !result.stdout.includes('"decision"'),
    `[D] stdout 不应含 "decision"（implement 阶段蓝队 pending 应静默），实际 stdout: ${result.stdout}\nstderr: ${result.stderr}`
  );
  assert.ok(
    !result.stdout.includes('"block"'),
    `[D] stdout 不应含 "block"，实际 stdout: ${result.stdout}\nstderr: ${result.stderr}`
  );
});
