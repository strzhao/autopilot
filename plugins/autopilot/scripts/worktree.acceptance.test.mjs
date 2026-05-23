/**
 * Acceptance tests for worktree.mjs
 *
 * Red-team verification: tests are written purely from the design document,
 * without reading the blue-team implementation.
 *
 * Run: node --test scripts/worktree.acceptance.test.mjs
 */

import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { writeFile, mkdtemp, rm, mkdir, symlink, lstat } from 'node:fs/promises';
import { existsSync, lstatSync, symlinkSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const execFileAsync = promisify(execFile);
const __dirname = dirname(fileURLToPath(import.meta.url));
const SCRIPT = resolve(__dirname, 'worktree.mjs');

// ---------------------------------------------------------------------------
// Dynamic import of the module under test.
// If the module does not exist yet the entire suite will fail-fast with a
// clear message rather than cryptic import errors.
// ---------------------------------------------------------------------------
let sanitizeName, computePort, parseLinksFile, ensureSelectiveAutopilotLayout;

before(async () => {
  try {
    const mod = await import('./worktree.mjs');
    sanitizeName = mod.sanitizeName;
    computePort = mod.computePort;
    parseLinksFile = mod.parseLinksFile;
    ensureSelectiveAutopilotLayout = mod.ensureSelectiveAutopilotLayout;
  } catch (err) {
    // Re-throw with a helpful message so the runner shows why everything skips
    throw new Error(
      `Failed to import worktree.mjs — has the blue-team delivered the module yet?\n${err.message}`
    );
  }
});

// ===========================================================================
// 1. Name sanitisation
// ===========================================================================
describe('sanitizeName', () => {
  it('preserves Chinese characters', () => {
    const result = sanitizeName('功能-测试');
    assert.equal(result, '功能-测试');
  });

  it('replaces spaces with hyphens', () => {
    const result = sanitizeName('my feature');
    assert.equal(result, 'my-feature');
  });

  it('removes emoji', () => {
    const result = sanitizeName('🚀feature');
    assert.equal(result, 'feature');
  });

  it('replaces special characters with hyphens', () => {
    const result = sanitizeName('feat@#$test');
    assert.equal(result, 'feat-test');
  });

  it('collapses consecutive hyphens', () => {
    const result = sanitizeName('a---b');
    assert.equal(result, 'a-b');
  });

  it('strips leading and trailing hyphens', () => {
    // emoji at start becomes hyphen then gets stripped
    const result = sanitizeName('---hello---');
    assert.equal(result, 'hello');
  });

  it('leaves a valid name unchanged', () => {
    const result = sanitizeName('valid-name_1.0');
    assert.equal(result, 'valid-name_1.0');
  });

  it('handles mixed Chinese, Latin, and special characters', () => {
    const result = sanitizeName('feat/中文@emoji🎉test');
    assert.equal(result, 'feat/中文-emoji-test');
  });

  it('handles name that becomes empty after sanitisation', () => {
    // Entirely emoji / special chars — implementation should handle gracefully
    const result = sanitizeName('🚀🎉✨');
    // Could be empty string or throw — at minimum must not crash
    assert.equal(typeof result, 'string');
  });
});

// ===========================================================================
// 2. Deterministic port computation
// ===========================================================================
describe('computePort', () => {
  it('returns a port in range 4001-4999', () => {
    const port = computePort('main');
    assert.ok(port >= 4001, `port ${port} should be >= 4001`);
    assert.ok(port <= 4999, `port ${port} should be <= 4999`);
  });

  it('is deterministic — same input always yields same output', () => {
    const a = computePort('feature-xyz');
    const b = computePort('feature-xyz');
    assert.equal(a, b);
  });

  it('different inputs produce different ports (high probability)', () => {
    const ports = new Set();
    const names = ['alpha', 'bravo', 'charlie', 'delta', 'echo', 'foxtrot'];
    for (const name of names) {
      ports.add(computePort(name));
    }
    // With 6 unique names mapped to 999 slots, collisions are extremely rare.
    // We expect at least 5 unique ports.
    assert.ok(ports.size >= 5, `Expected >=5 unique ports, got ${ports.size}`);
  });

  it('returns an integer', () => {
    const port = computePort('test-branch');
    assert.equal(port, Math.floor(port));
  });

  it('handles long branch names', () => {
    const longName = 'a'.repeat(500);
    const port = computePort(longName);
    assert.ok(port >= 4001 && port <= 4999);
  });
});

// ===========================================================================
// 3. worktree-links file parsing
// ===========================================================================
describe('parseLinksFile', () => {
  let tmpDir;

  before(async () => {
    tmpDir = await mkdtemp(join(tmpdir(), 'wt-test-'));
  });

  it('parses normal lines as link targets', async () => {
    const file = join(tmpDir, 'links1');
    await writeFile(file, '.env.local\n.mcp.json\n');
    const links = await parseLinksFile(file);
    assert.deepEqual(links, ['.env.local', '.mcp.json']);
  });

  it('skips comment lines starting with #', async () => {
    const file = join(tmpDir, 'links2');
    await writeFile(file, '# this is a comment\n.env.local\n');
    const links = await parseLinksFile(file);
    assert.deepEqual(links, ['.env.local']);
  });

  it('skips empty lines', async () => {
    const file = join(tmpDir, 'links3');
    await writeFile(file, '.env\n\n\n.mcp.json\n');
    const links = await parseLinksFile(file);
    assert.deepEqual(links, ['.env', '.mcp.json']);
  });

  it('skips comment lines with leading whitespace', async () => {
    const file = join(tmpDir, 'links4');
    await writeFile(file, '  # indented comment\n.env\n');
    const links = await parseLinksFile(file);
    assert.deepEqual(links, ['.env']);
  });

  it('trims whitespace from entries', async () => {
    const file = join(tmpDir, 'links5');
    await writeFile(file, '  .env.local  \n');
    const links = await parseLinksFile(file);
    assert.deepEqual(links, ['.env.local']);
  });

  it('returns empty array for non-existent file', async () => {
    const links = await parseLinksFile(join(tmpDir, 'does-not-exist'));
    assert.deepEqual(links, []);
  });
});

// ===========================================================================
// 4. Sub-command routing (integration — spawns the script)
// ===========================================================================
describe('sub-command routing', () => {
  it('exits non-zero with no arguments', async () => {
    try {
      await execFileAsync('node', [SCRIPT]);
      assert.fail('Should have exited with non-zero code');
    } catch (err) {
      assert.ok(err.code !== 0, `Expected non-zero exit, got ${err.code}`);
    }
  });

  it('exits non-zero with invalid sub-command', async () => {
    try {
      await execFileAsync('node', [SCRIPT, 'bogus']);
      assert.fail('Should have exited with non-zero code');
    } catch (err) {
      assert.ok(err.code !== 0, `Expected non-zero exit, got ${err.code}`);
      // stderr should contain a useful error message
      assert.ok(
        err.stderr.length > 0,
        'Expected an error message on stderr'
      );
    }
  });
});

// ===========================================================================
// 5. create stdout protocol
//    The create sub-command must write ONLY the worktree absolute path to
//    stdout (single line). All informational/debug output goes to stderr.
//    This test uses a temporary bare repo so it can run without a real project.
// ===========================================================================
describe('create stdout protocol', { skip: !process.env.RUN_INTEGRATION }, () => {
  let tmpDir;
  let bareRepo;

  before(async () => {
    tmpDir = await mkdtemp(join(tmpdir(), 'wt-create-'));
    bareRepo = join(tmpDir, 'repo.git');

    // Set up a bare repo with at least one commit so worktree can be created
    await execFileAsync('git', ['init', '--bare', bareRepo]);
    const clone = join(tmpDir, 'clone');
    await execFileAsync('git', ['clone', bareRepo, clone]);
    await writeFile(join(clone, 'README.md'), '# test');
    await execFileAsync('git', ['add', '.'], { cwd: clone });
    await execFileAsync('git', ['-c', 'user.name=Test', '-c', 'user.email=t@t', 'commit', '-m', 'init'], { cwd: clone });
    await execFileAsync('git', ['push'], { cwd: clone });
  });

  it('stdout contains only one line — the worktree absolute path', async () => {
    const stdinPayload = JSON.stringify({ name: 'test-branch' });
    const { stdout, stderr } = await execFileAsync('node', [SCRIPT, 'create'], {
      cwd: join(tmpDir, 'clone'),
      input: stdinPayload,
      env: { ...process.env, HOME: tmpDir },
    });

    const lines = stdout.trim().split('\n');
    assert.equal(lines.length, 1, `Expected 1 stdout line, got ${lines.length}: ${stdout}`);

    // The single line must be an absolute path
    const outputPath = lines[0].trim();
    assert.ok(
      outputPath.startsWith('/'),
      `stdout should be an absolute path, got: ${outputPath}`
    );

    // stderr may contain logs — that is fine, but stdout must be clean
    // (no assertion on stderr content, only that stdout is clean)
  });
});

// ===========================================================================
// 6. ensureSelectiveAutopilotLayout — tracked-dir 残留 symlink 清理
//
//    设计契约（v3.35 二级分层后）：
//    - SHARED_AUTOPILOT_ITEMS 中含 'runtime/requirements'
//    - 若 dst 是 symlink 且 main 将 .autopilot/runtime/requirements tracked 为目录(dir)
//      → 清除 symlink，改用 git checkout 恢复为真实目录
//    - 幂等；不抛错；exit 0
// ===========================================================================
describe('ensureSelectiveAutopilotLayout — tracked-dir 残留清理', () => {
  // ---------------------------------------------------------------------------
  // Helper: 创建带 .autopilot/runtime/requirements/ 提交的主仓库，返回 { mainRoot }
  // ---------------------------------------------------------------------------
  async function setupMainRepo(tmpDir) {
    const mainRoot = join(tmpDir, 'main');
    mkdirSync(mainRoot, { recursive: true });

    const gitEnv = {
      ...process.env,
      GIT_AUTHOR_NAME: 'Test',
      GIT_AUTHOR_EMAIL: 'test@test',
      GIT_COMMITTER_NAME: 'Test',
      GIT_COMMITTER_EMAIL: 'test@test',
    };

    const runGit = (...args) =>
      execFileAsync('git', args, { cwd: mainRoot, env: gitEnv });

    await runGit('init');
    await runGit('checkout', '-b', 'main');

    // 创建 .autopilot/runtime/requirements/spec.md 并提交 — 形成 tracked dir
    mkdirSync(join(mainRoot, '.autopilot', 'runtime', 'requirements'), { recursive: true });
    writeFileSync(join(mainRoot, '.autopilot', 'runtime', 'requirements', 'spec.md'), '# spec\n');

    await runGit('add', '.');
    await runGit('commit', '-m', 'init with requirements dir');

    return { mainRoot, gitEnv };
  }

  // ---------------------------------------------------------------------------
  // Helper: 在主仓库上创建 git worktree，返回 worktreePath
  // ---------------------------------------------------------------------------
  async function addWorktree(mainRoot, wtName, gitEnv) {
    const worktreePath = join(mainRoot, '..', wtName);
    await execFileAsync(
      'git', ['worktree', 'add', '-b', wtName, worktreePath],
      { cwd: mainRoot, env: gitEnv }
    );
    return worktreePath;
  }

  // -------------------------------------------------------------------------
  // Case A: dst 是 symlink + main tracked-dir + worktree HEAD 含该目录
  //   期望：symlink 被替换为真实目录，且包含 main HEAD 中 requirements/ 的文件
  // -------------------------------------------------------------------------
  it('case A: 残留 symlink 被替换为真实目录（worktree HEAD 含该路径）', async () => {
    assert.ok(
      typeof ensureSelectiveAutopilotLayout === 'function',
      'ensureSelectiveAutopilotLayout 未导出 — 需要蓝队补 export'
    );

    const tmpDir = await mkdtemp(join(tmpdir(), 'wt-tracked-dir-a-'));
    try {
      const { mainRoot, gitEnv } = await setupMainRepo(tmpDir);
      const worktreePath = await addWorktree(mainRoot, 'wt-branch-a', gitEnv);

      // 模拟"早期残留"：worktree 的 .autopilot/runtime/requirements 是指向 main 的 symlink
      const wtAutopilot = join(worktreePath, '.autopilot');
      const wtReq = join(wtAutopilot, 'runtime', 'requirements');
      const mainReq = join(mainRoot, '.autopilot', 'runtime', 'requirements');

      // 确保 .autopilot/runtime 目录存在（worktree 里可能已有或没有）
      mkdirSync(join(wtAutopilot, 'runtime'), { recursive: true });

      // 如果 worktree 里 git checkout 已建出真实目录，先删掉再做 symlink
      if (existsSync(wtReq)) {
        const st = lstatSync(wtReq);
        if (st.isDirectory()) {
          // 暴力清除目录后创建 symlink
          const { rmSync } = await import('node:fs');
          rmSync(wtReq, { recursive: true, force: true });
        } else if (st.isSymbolicLink()) {
          const { unlinkSync } = await import('node:fs');
          unlinkSync(wtReq);
        }
      }
      symlinkSync(mainReq, wtReq);

      // 前置断言：确认此刻确实是 symlink
      const beforeStat = lstatSync(wtReq);
      assert.ok(beforeStat.isSymbolicLink(), 'fixture: runtime/requirements 应为 symlink');

      // 调用被测函数
      ensureSelectiveAutopilotLayout(mainRoot, worktreePath);

      // 后置断言 1：不再是 symlink
      const afterStat = lstatSync(wtReq);
      assert.ok(
        !afterStat.isSymbolicLink(),
        `Case A: requirements 应不再是 symlink，实际 isSymbolicLink=${afterStat.isSymbolicLink()}`
      );

      // 后置断言 2：是真实目录
      assert.ok(
        afterStat.isDirectory(),
        `Case A: requirements 应是真实目录，实际 isDirectory=${afterStat.isDirectory()}`
      );

      // 后置断言 3：包含 main HEAD 中的文件
      assert.ok(
        existsSync(join(wtReq, 'spec.md')),
        'Case A: requirements/ 下应包含 spec.md（来自 main HEAD）'
      );
    } finally {
      await rm(tmpDir, { recursive: true, force: true });
    }
  });

  // -------------------------------------------------------------------------
  // Case B: dst 是 symlink + main tracked-dir + worktree HEAD 不含该路径
  //   构造：worktree 切到一个根本没有 .autopilot/runtime/requirements/ 的旧分支
  //   期望：unlink 执行，git checkout 失败被 catch（不抛错），
  //         最终 dst 不存在（broken state 被清理），函数整体不抛异常
  // -------------------------------------------------------------------------
  it('case B: worktree 旧分支不含 requirements — symlink 被清理，函数不抛错', async () => {
    assert.ok(
      typeof ensureSelectiveAutopilotLayout === 'function',
      'ensureSelectiveAutopilotLayout 未导出 — 需要蓝队补 export'
    );

    const tmpDir = await mkdtemp(join(tmpdir(), 'wt-tracked-dir-b-'));
    try {
      const gitEnv = {
        ...process.env,
        GIT_AUTHOR_NAME: 'Test',
        GIT_AUTHOR_EMAIL: 'test@test',
        GIT_COMMITTER_NAME: 'Test',
        GIT_COMMITTER_EMAIL: 'test@test',
      };

      const mainRoot = join(tmpDir, 'main');
      mkdirSync(mainRoot, { recursive: true });

      const runGit = (...args) =>
        execFileAsync('git', args, { cwd: mainRoot, env: gitEnv });

      // 步骤 1：创建"旧提交"（没有 .autopilot/runtime/requirements/）
      await runGit('init');
      await runGit('checkout', '-b', 'main');
      writeFileSync(join(mainRoot, 'README.md'), '# old\n');
      await runGit('add', '.');
      await runGit('commit', '-m', 'old commit without requirements');

      // 记录旧提交的 SHA，用于创建"旧分支"
      const { stdout: oldSha } = await execFileAsync(
        'git', ['rev-parse', 'HEAD'],
        { cwd: mainRoot, env: gitEnv }
      );

      // 步骤 2：在 main 上添加 runtime/requirements 目录提交
      mkdirSync(join(mainRoot, '.autopilot', 'runtime', 'requirements'), { recursive: true });
      writeFileSync(join(mainRoot, '.autopilot', 'runtime', 'requirements', 'spec.md'), '# spec\n');
      await runGit('add', '.');
      await runGit('commit', '-m', 'add requirements dir');

      // 步骤 3：基于旧提交创建旧分支，并建 worktree（该分支没有 requirements）
      const oldBranch = 'old-branch-no-req';
      await execFileAsync(
        'git', ['branch', oldBranch, oldSha.trim()],
        { cwd: mainRoot, env: gitEnv }
      );

      const worktreePath = join(tmpDir, 'wt-old');
      await execFileAsync(
        'git', ['worktree', 'add', worktreePath, oldBranch],
        { cwd: mainRoot, env: gitEnv }
      );

      // 步骤 4：在 worktree 里手动放置一个残留 symlink
      const wtAutopilot = join(worktreePath, '.autopilot');
      const wtReq = join(wtAutopilot, 'runtime', 'requirements');
      const mainReq = join(mainRoot, '.autopilot', 'runtime', 'requirements');

      mkdirSync(join(wtAutopilot, 'runtime'), { recursive: true });
      if (existsSync(wtReq)) {
        const st = lstatSync(wtReq);
        if (st.isDirectory()) {
          const { rmSync } = await import('node:fs');
          rmSync(wtReq, { recursive: true, force: true });
        } else if (st.isSymbolicLink()) {
          const { unlinkSync } = await import('node:fs');
          unlinkSync(wtReq);
        }
      }
      symlinkSync(mainReq, wtReq);

      // 前置断言
      assert.ok(lstatSync(wtReq).isSymbolicLink(), 'fixture: 应为 symlink');

      // 调用被测函数 — 不应抛错
      let thrown = null;
      try {
        ensureSelectiveAutopilotLayout(mainRoot, worktreePath);
      } catch (err) {
        thrown = err;
      }
      assert.equal(thrown, null, `Case B: 函数不应抛错，实际 thrown: ${thrown}`);

      // 后置断言：symlink 应已被清理（dst 不存在）
      // git checkout 会失败（旧分支无此路径），dst 应不存在
      assert.ok(
        !existsSync(wtReq),
        'Case B: git checkout 失败后 dst 不应存在（broken state 被清理）'
      );
    } finally {
      await rm(tmpDir, { recursive: true, force: true });
    }
  });

  // -------------------------------------------------------------------------
  // Case C: dst 不存在 + main tracked-dir
  //   期望：函数不抛错，不创建任何 symlink，不调 unlink
  // -------------------------------------------------------------------------
  it('case C: dst 不存在时函数不报错，不创建 symlink', async () => {
    assert.ok(
      typeof ensureSelectiveAutopilotLayout === 'function',
      'ensureSelectiveAutopilotLayout 未导出 — 需要蓝队补 export'
    );

    const tmpDir = await mkdtemp(join(tmpdir(), 'wt-tracked-dir-c-'));
    try {
      const { mainRoot, gitEnv } = await setupMainRepo(tmpDir);
      const worktreePath = await addWorktree(mainRoot, 'wt-branch-c', gitEnv);

      const wtReq = join(worktreePath, '.autopilot', 'runtime', 'requirements');

      // 如果 worktree 里 git checkout 已经创建了目录/symlink，先手动删除，
      // 模拟"dst 不存在"的场景
      if (existsSync(wtReq)) {
        const st = lstatSync(wtReq);
        if (st.isDirectory()) {
          const { rmSync } = await import('node:fs');
          rmSync(wtReq, { recursive: true, force: true });
        } else {
          const { unlinkSync } = await import('node:fs');
          unlinkSync(wtReq);
        }
      }
      // 前置断言
      assert.ok(!existsSync(wtReq), 'fixture: dst 应不存在');

      // 调用被测函数
      let thrown = null;
      try {
        ensureSelectiveAutopilotLayout(mainRoot, worktreePath);
      } catch (err) {
        thrown = err;
      }
      assert.equal(thrown, null, `Case C: 函数不应抛错，实际 thrown: ${thrown}`);

      // 后置断言：dst 要么不存在，要么是真实目录（git checkout 恢复）
      // 关键：不能是 symlink
      if (existsSync(wtReq)) {
        const st = lstatSync(wtReq);
        assert.ok(
          !st.isSymbolicLink(),
          'Case C: 若 dst 被创建，应为真实目录而非 symlink'
        );
        assert.ok(st.isDirectory(), 'Case C: 创建的 dst 应是真实目录');
      }
      // 若不存在也合法 — 不创建任何东西
    } finally {
      await rm(tmpDir, { recursive: true, force: true });
    }
  });

  // -------------------------------------------------------------------------
  // Case D: dst 是真实目录（已存在）+ main tracked-dir
  //   期望：函数不抛错，dst 保持原状（仍是真实目录，内容不变）
  // -------------------------------------------------------------------------
  it('case D: dst 已是真实目录时函数不报错，目录内容不变', async () => {
    assert.ok(
      typeof ensureSelectiveAutopilotLayout === 'function',
      'ensureSelectiveAutopilotLayout 未导出 — 需要蓝队补 export'
    );

    const tmpDir = await mkdtemp(join(tmpdir(), 'wt-tracked-dir-d-'));
    try {
      const { mainRoot, gitEnv } = await setupMainRepo(tmpDir);
      const worktreePath = await addWorktree(mainRoot, 'wt-branch-d', gitEnv);

      const wtAutopilot = join(worktreePath, '.autopilot');
      const wtReq = join(wtAutopilot, 'runtime', 'requirements');

      // 确保 dst 是真实目录（不是 symlink）
      // 若 git checkout 已经创建了，直接用；否则手动建
      if (existsSync(wtReq) && lstatSync(wtReq).isSymbolicLink()) {
        const { unlinkSync } = await import('node:fs');
        unlinkSync(wtReq);
        mkdirSync(wtReq, { recursive: true });
      } else if (!existsSync(wtReq)) {
        mkdirSync(wtReq, { recursive: true });
      }

      // 放置一个哨兵文件，用于验证"内容不变"
      const sentinel = join(wtReq, 'worktree-local.md');
      writeFileSync(sentinel, '# worktree local content\n');

      // 前置断言
      assert.ok(!lstatSync(wtReq).isSymbolicLink(), 'fixture: dst 应是真实目录，非 symlink');
      assert.ok(existsSync(sentinel), 'fixture: 哨兵文件应存在');

      // 调用被测函数
      let thrown = null;
      try {
        ensureSelectiveAutopilotLayout(mainRoot, worktreePath);
      } catch (err) {
        thrown = err;
      }
      assert.equal(thrown, null, `Case D: 函数不应抛错，实际 thrown: ${thrown}`);

      // 后置断言 1：dst 仍是真实目录（非 symlink）
      const afterStat = lstatSync(wtReq);
      assert.ok(
        !afterStat.isSymbolicLink(),
        'Case D: dst 应仍为真实目录，不能被转为 symlink'
      );
      assert.ok(afterStat.isDirectory(), 'Case D: dst 应仍是目录');

      // 后置断言 2：哨兵文件内容不变
      assert.ok(
        existsSync(sentinel),
        'Case D: 函数调用后哨兵文件应仍存在（内容未被破坏）'
      );
    } finally {
      await rm(tmpDir, { recursive: true, force: true });
    }
  });
});
