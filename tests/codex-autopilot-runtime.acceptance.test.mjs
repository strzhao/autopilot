/**
 * Acceptance tests for Codex autopilot runtime parity.
 *
 * Scope:
 *   - official/repo-local Stop hook wiring
 *   - Claude vs Codex comparison doc
 *   - state manager lifecycle (`start/approve/revise/status/cancel`)
 *   - Stop hook block/resume behavior and cleanup
 *
 * Run:
 *   node --test tests/codex-autopilot-runtime.acceptance.test.mjs
 */

import { after, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');

const OFFICIAL_HOOKS_PATH = resolve(
  ROOT,
  'codex/plugins/autopilot-codex/hooks.json'
);
const REPO_HOOKS_PATH = resolve(ROOT, '.codex/hooks.json');
const COMPARISON_DOC_PATH = resolve(
  ROOT,
  'codex/docs/claude-vs-codex-autopilot.md'
);
const STATE_SCRIPT = resolve(
  ROOT,
  'codex/plugins/autopilot-codex/assets/scripts/autopilot_state.py'
);
const STOP_SCRIPT = resolve(
  ROOT,
  'codex/plugins/autopilot-codex/assets/scripts/autopilot_stop.py'
);

const TEMP_DIRS = [];

after(() => {
  for (const dir of TEMP_DIRS) {
    rmSync(dir, { recursive: true, force: true });
  }
});

function run(command, args, { cwd, env, input } = {}) {
  const result = spawnSync(command, args, {
    cwd,
    env: { ...process.env, ...env },
    input,
    encoding: 'utf-8',
  });

  assert.equal(
    result.status,
    0,
    `${command} ${args.join(' ')} must exit 0\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`
  );

  return result;
}

function makeTempGitRepo() {
  const repo = mkdtempSync(join(tmpdir(), 'codex-autopilot-'));
  TEMP_DIRS.push(repo);
  run('git', ['init', '-q'], { cwd: repo });
  return repo;
}

function statePath(repo) {
  return resolve(repo, '.codex/autopilot.local.md');
}

function readState(repo) {
  return readFileSync(statePath(repo), 'utf-8');
}

function setStateField(repo, field, value) {
  const path = statePath(repo);
  const pattern = new RegExp(`^${field}:.*$`, 'm');
  const content = readFileSync(path, 'utf-8');
  assert.ok(pattern.test(content), `state file must contain frontmatter field ${field}`);
  writeFileSync(path, content.replace(pattern, `${field}: ${value}`), 'utf-8');
}

function startWorkflow(
  repo,
  { goal = 'Ship Codex parity', maxIterations = 7, maxRetries = 2, sessionId = '' } = {}
) {
  return run(
    'python3',
    [
      STATE_SCRIPT,
      'start',
      '--goal',
      goal,
      '--max-iterations',
      String(maxIterations),
      '--max-retries',
      String(maxRetries),
    ],
    {
      cwd: repo,
      env: sessionId ? { CODEX_SESSION_ID: sessionId } : undefined,
    }
  );
}

function statusJson(repo) {
  const result = run('python3', [STATE_SCRIPT, 'status', '--json'], { cwd: repo });
  return JSON.parse(result.stdout.trim());
}

describe('Codex autopilot hook wiring and docs', () => {
  it('official plugin hooks.json must wire Stop to autopilot_stop.py', () => {
    const hooks = JSON.parse(readFileSync(OFFICIAL_HOOKS_PATH, 'utf-8'));
    const stopCommand =
      hooks.hooks?.Stop?.[0]?.hooks?.[0]?.command;
    assert.equal(
      stopCommand,
      'python3 ./assets/scripts/autopilot_stop.py'
    );
  });

  it('repo-local .codex/hooks.json must include a Stop hook for the Codex runtime', () => {
    const hooks = JSON.parse(readFileSync(REPO_HOOKS_PATH, 'utf-8'));
    const stopCommand =
      hooks.hooks?.Stop?.[0]?.hooks?.[0]?.command ?? '';
    assert.ok(
      stopCommand.includes('codex/plugins/autopilot-codex/assets/scripts/autopilot_stop.py'),
      'repo-local Stop hook must point at the Codex autopilot stop runtime'
    );
  });

  it('comparison doc must describe phased parity including red/blue, auto-fix, and review gates', () => {
    assert.ok(existsSync(COMPARISON_DOC_PATH), 'comparison doc must exist');
    const doc = readFileSync(COMPARISON_DOC_PATH, 'utf-8');
    for (const term of [
      '原始 Claude autopilot',
      '当前 Codex autopilot',
      '蓝队/红队',
      'Auto-fix',
      'design-approval',
      'review-accept',
    ]) {
      assert.ok(
        doc.includes(term),
        `comparison doc must mention "${term}"`
      );
    }
  });
});

describe('Codex autopilot state manager lifecycle', () => {
  it('start must create .codex/autopilot.local.md with Codex runtime frontmatter and sections', () => {
    const repo = makeTempGitRepo();
    const result = startWorkflow(repo, {
      goal: 'Rebuild autopilot parity',
      maxIterations: 11,
      maxRetries: 4,
      sessionId: 'session-start-1',
    });

    assert.ok(result.stdout.includes('Codex autopilot 已启动'));
    assert.ok(existsSync(statePath(repo)), 'state file must be created');

    const state = readState(repo);
    for (const snippet of [
      'runtime: "codex"',
      'phase: "design"',
      'gate: ""',
      'max_iterations: 11',
      'max_retries: 4',
      'session_id: "session-start-1"',
      'goal: "Rebuild autopilot parity"',
      '## 目标',
      '## 设计文档',
      '## 实现计划',
      '## 验证方案',
      '## 红队验收测试',
      '## QA 报告',
      '## 用户反馈',
      '## 变更日志',
    ]) {
      assert.ok(state.includes(snippet), `state file must include "${snippet}"`);
    }
  });

  it('status --json must report active workflows, including phase=auto-fix', () => {
    const repo = makeTempGitRepo();
    startWorkflow(repo);

    const designStatus = statusJson(repo);
    assert.equal(designStatus.active, true);
    assert.equal(designStatus.phase, 'design');

    setStateField(repo, 'phase', '"auto-fix"');
    const autoFixStatus = statusJson(repo);
    assert.equal(autoFixStatus.active, true);
    assert.equal(autoFixStatus.phase, 'auto-fix');
  });

  it('approve must advance design-approval to implement and review-accept to merge', () => {
    const repo = makeTempGitRepo();
    startWorkflow(repo);

    setStateField(repo, 'gate', '"design-approval"');
    run('python3', [STATE_SCRIPT, 'approve', '--feedback', 'looks good'], { cwd: repo });
    let state = readState(repo);
    assert.ok(state.includes('phase: "implement"'));
    assert.ok(state.includes('gate: ""'));
    assert.ok(state.includes('用户批准设计，进入实现阶段。反馈: looks good'));

    setStateField(repo, 'phase', '"qa"');
    setStateField(repo, 'gate', '"review-accept"');
    run('python3', [STATE_SCRIPT, 'approve'], { cwd: repo });
    state = readState(repo);
    assert.ok(state.includes('phase: "merge"'));
    assert.ok(state.includes('gate: ""'));
    assert.ok(state.includes('用户批准验收，进入合并阶段'));
  });

  it('revise must route review-accept back to implement and append feedback', () => {
    const repo = makeTempGitRepo();
    startWorkflow(repo);

    setStateField(repo, 'phase', '"qa"');
    setStateField(repo, 'gate', '"review-accept"');
    run('python3', [STATE_SCRIPT, 'revise', '--feedback', '补上真实场景验证'], { cwd: repo });

    const state = readState(repo);
    assert.ok(state.includes('phase: "implement"'));
    assert.ok(state.includes('gate: ""'));
    assert.ok(state.includes('补上真实场景验证'));
  });

  it('cancel must mark the workflow cancelled and leave cleanup to Stop hook', () => {
    const repo = makeTempGitRepo();
    startWorkflow(repo);

    run('python3', [STATE_SCRIPT, 'cancel', '--reason', 'user aborted'], { cwd: repo });

    const state = readState(repo);
    assert.ok(state.includes('phase: "cancelled"'));
    assert.ok(state.includes('已取消，等待 Stop hook 清理状态文件。'));
    assert.ok(state.includes('工作流已取消: user aborted'));
  });
});

describe('Codex autopilot Stop runtime', () => {
  it('must block active non-gated phases, claim session_id, and increment iteration', () => {
    const repo = makeTempGitRepo();
    startWorkflow(repo, { goal: 'Drive design loop' });

    const hookInput = JSON.stringify({ cwd: repo, session_id: 'hook-session-1' });
    const result = run('python3', [STOP_SCRIPT], { cwd: repo, input: hookInput });
    const payload = JSON.parse(result.stdout.trim());

    assert.equal(payload.decision, 'block');
    assert.ok(payload.reason.includes('continue phase `design`'));
    assert.ok(payload.reason.includes('plan reviewer sub-agent'));
    assert.ok(payload.systemMessage.includes('autopilot iteration 1 | phase: design'));

    const state = readState(repo);
    assert.ok(state.includes('iteration: 1'));
    assert.ok(state.includes('session_id: "hook-session-1"'));
  });

  it('must emit auto-fix specific guidance when phase=auto-fix', () => {
    const repo = makeTempGitRepo();
    startWorkflow(repo);
    setStateField(repo, 'phase', '"auto-fix"');

    const result = run('python3', [STOP_SCRIPT], {
      cwd: repo,
      input: JSON.stringify({ cwd: repo, session_id: 'hook-session-2' }),
    });
    const payload = JSON.parse(result.stdout.trim());

    assert.equal(payload.decision, 'block');
    assert.ok(payload.reason.includes('continue phase `auto-fix`'));
    assert.ok(payload.reason.includes('qa_scope=selective'));
    assert.ok(payload.reason.includes('review-accept'));
  });

  it('must pass through without blocking when a gate is active', () => {
    const repo = makeTempGitRepo();
    startWorkflow(repo);
    setStateField(repo, 'gate', '"design-approval"');

    const result = run('python3', [STOP_SCRIPT], {
      cwd: repo,
      input: JSON.stringify({ cwd: repo, session_id: 'hook-session-3' }),
    });

    assert.equal(result.stdout.trim(), '');
    assert.ok(existsSync(statePath(repo)), 'state file must remain while waiting for approval');
    assert.ok(readState(repo).includes('gate: "design-approval"'));
  });

  it('must clean up done and cancelled workflows', () => {
    const doneRepo = makeTempGitRepo();
    startWorkflow(doneRepo);
    setStateField(doneRepo, 'phase', '"done"');

    run('python3', [STOP_SCRIPT], {
      cwd: doneRepo,
      input: JSON.stringify({ cwd: doneRepo, session_id: 'hook-session-4' }),
    });
    assert.equal(existsSync(statePath(doneRepo)), false);

    const cancelledRepo = makeTempGitRepo();
    startWorkflow(cancelledRepo);
    setStateField(cancelledRepo, 'phase', '"cancelled"');

    run('python3', [STOP_SCRIPT], {
      cwd: cancelledRepo,
      input: JSON.stringify({ cwd: cancelledRepo, session_id: 'hook-session-5' }),
    });
    assert.equal(existsSync(statePath(cancelledRepo)), false);
  });
});
