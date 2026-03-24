/**
 * Acceptance tests for worktree.mjs
 *
 * Red-team verification: tests are written purely from the design document,
 * without reading the blue-team implementation.
 *
 * Run: node --test scripts/worktree.acceptance.test.mjs
 */

import { describe, it, before } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { writeFile, mkdtemp, rm, mkdir } from 'node:fs/promises';
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
let sanitizeName, computePort, parseLinksFile;

before(async () => {
  try {
    const mod = await import('./worktree.mjs');
    sanitizeName = mod.sanitizeName;
    computePort = mod.computePort;
    parseLinksFile = mod.parseLinksFile;
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
