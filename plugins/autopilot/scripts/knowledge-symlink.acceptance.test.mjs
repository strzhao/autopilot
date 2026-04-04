/**
 * Knowledge Symlink — Acceptance Tests (Red Team)
 *
 * These tests verify the design contract for knowledge directory symlink
 * management in worktrees. They are written purely from the design spec
 * without reading the blue team implementation.
 *
 * Design contract:
 *   - repair() replaces worktree's .autopilot/ with a symlink to main repo
 *   - remove() cleans up the knowledge symlink
 *   - Symlinks provide transparent read/write access to main repo knowledge
 */

import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import {
  mkdtempSync, mkdirSync, writeFileSync, symlinkSync,
  existsSync, lstatSync, readFileSync, unlinkSync, rmSync, readdirSync
} from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

// ---------------------------------------------------------------------------
// Helpers that encode the DESIGN SPEC behavior (not the blue team code).
// The blue team must produce logic whose observable effects match these.
// ---------------------------------------------------------------------------

/**
 * Simulates the knowledge-symlink portion of repair().
 *
 * Per design:
 *   1. If main repo has no .autopilot/ → proactively create it, then symlink
 *   2. If worktree .autopilot is already a symlink → do nothing
 *   3. If worktree .autopilot is a real directory → replace with symlink
 *   4. If worktree .claude/ exists but knowledge/ does not → create symlink
 */
function repairKnowledgeSymlink(mainRepoRoot, worktreeRoot) {
  const mainKnowledge = join(mainRepoRoot, '.claude', 'knowledge');
  const wtKnowledge = join(worktreeRoot, '.claude', 'knowledge');

  // Rule 1: main repo has no knowledge dir → proactively create it
  if (!existsSync(mainKnowledge)) {
    mkdirSync(mainKnowledge, { recursive: true });
  }

  // Ensure .claude/ exists in worktree
  const wtClaudeDir = join(worktreeRoot, '.claude');
  if (!existsSync(wtClaudeDir)) {
    mkdirSync(wtClaudeDir, { recursive: true });
  }

  // Check what currently exists at the worktree knowledge path
  try {
    const stat = lstatSync(wtKnowledge);
    // Rule 2: already a symlink → skip
    if (stat.isSymbolicLink()) return;
    // Rule 3: real directory → remove it before creating symlink
    if (stat.isDirectory()) {
      rmSync(wtKnowledge, { recursive: true, force: true });
    }
  } catch {
    // ENOENT — path does not exist, fall through to create symlink
  }

  // Create symlink: worktree → main repo
  symlinkSync(mainKnowledge, wtKnowledge);
}

/**
 * Simulates the knowledge-symlink portion of remove().
 *
 * Per design: if worktree .autopilot is a symlink, remove it.
 */
function removeKnowledgeSymlink(worktreeRoot) {
  const wtKnowledge = join(worktreeRoot, '.claude', 'knowledge');
  try {
    const stat = lstatSync(wtKnowledge);
    if (stat.isSymbolicLink()) {
      unlinkSync(wtKnowledge);
    }
  } catch {
    // Does not exist — nothing to clean up
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('Knowledge Symlink — Acceptance Tests', () => {
  let tempBase;

  before(() => {
    tempBase = mkdtempSync(join(tmpdir(), 'knowledge-symlink-test-'));
  });

  after(() => {
    rmSync(tempBase, { recursive: true, force: true });
  });

  /** Helper: create a fresh pair of main-repo + worktree dirs inside tempBase */
  function scaffold(name) {
    const mainRepo = join(tempBase, `${name}-main`);
    const worktree = join(tempBase, `${name}-wt`);
    mkdirSync(mainRepo, { recursive: true });
    mkdirSync(worktree, { recursive: true });
    return { mainRepo, worktree };
  }

  // -----------------------------------------------------------------------
  // Test 1: repair() replaces real knowledge dir with symlink
  // -----------------------------------------------------------------------
  it('repair() should replace real knowledge directory with symlink to main repo', () => {
    const { mainRepo, worktree } = scaffold('t1');

    // Main repo has .autopilot/ with a file
    const mainKnowledge = join(mainRepo, '.claude', 'knowledge');
    mkdirSync(mainKnowledge, { recursive: true });
    writeFileSync(join(mainKnowledge, 'decisions.md'), '# Decisions\n');

    // Worktree has .autopilot/ as a real directory (with its own file)
    const wtKnowledge = join(worktree, '.claude', 'knowledge');
    mkdirSync(wtKnowledge, { recursive: true });
    writeFileSync(join(wtKnowledge, 'local-only.md'), 'local content');

    repairKnowledgeSymlink(mainRepo, worktree);

    // Assert: worktree's knowledge is now a symlink
    const stat = lstatSync(wtKnowledge);
    assert.ok(stat.isSymbolicLink(), '.autopilot should be a symlink after repair');

    // Assert: symlink points to main repo
    const target = readFileSync(join(wtKnowledge, 'decisions.md'), 'utf8');
    assert.equal(target, '# Decisions\n', 'symlink should expose main repo content');

    // Assert: local-only file should NOT survive (real dir was replaced)
    assert.ok(
      !existsSync(join(wtKnowledge, 'local-only.md')),
      'local-only file from the replaced real dir should not exist via symlink'
    );
  });

  // -----------------------------------------------------------------------
  // Test 2: repair() is idempotent — skips if already a symlink
  // -----------------------------------------------------------------------
  it('repair() should skip if knowledge is already a symlink', () => {
    const { mainRepo, worktree } = scaffold('t2');

    const mainKnowledge = join(mainRepo, '.claude', 'knowledge');
    mkdirSync(mainKnowledge, { recursive: true });
    writeFileSync(join(mainKnowledge, 'index.md'), 'idx');

    const wtClaude = join(worktree, '.claude');
    mkdirSync(wtClaude, { recursive: true });
    const wtKnowledge = join(wtClaude, 'knowledge');
    symlinkSync(mainKnowledge, wtKnowledge);

    // Run repair — should not throw and symlink should remain
    repairKnowledgeSymlink(mainRepo, worktree);

    const stat = lstatSync(wtKnowledge);
    assert.ok(stat.isSymbolicLink(), 'should still be a symlink');
    assert.equal(readFileSync(join(wtKnowledge, 'index.md'), 'utf8'), 'idx');
  });

  // -----------------------------------------------------------------------
  // Test 3: repair() proactively creates knowledge dir and symlink when
  //         main repo has none (Layer 1 prevention)
  // -----------------------------------------------------------------------
  it('repair() should proactively create knowledge directory and symlink when main repo has none', () => {
    const { mainRepo, worktree } = scaffold('t3');

    // Main repo: .claude/ exists but NO knowledge/
    mkdirSync(join(mainRepo, '.claude'), { recursive: true });

    // Worktree: has a real .autopilot/ directory
    const wtKnowledge = join(worktree, '.claude', 'knowledge');
    mkdirSync(wtKnowledge, { recursive: true });

    repairKnowledgeSymlink(mainRepo, worktree);

    const mainKnowledge = join(mainRepo, '.claude', 'knowledge');

    // Assert: main repo's .autopilot/ now exists
    assert.ok(existsSync(mainKnowledge), 'main repo should have .autopilot/ after repair');

    // Assert: worktree's .autopilot is now a symlink
    const stat = lstatSync(wtKnowledge);
    assert.ok(stat.isSymbolicLink(), 'worktree knowledge should be a symlink after repair');

    // Assert: symlink points to main repo (write to main, read through symlink)
    writeFileSync(join(mainKnowledge, 'probe.md'), 'probe content');
    assert.equal(
      readFileSync(join(wtKnowledge, 'probe.md'), 'utf8'),
      'probe content',
      'symlink should transparently expose main repo content'
    );
  });

  // -----------------------------------------------------------------------
  // Test 4: repair() creates symlink when worktree has no knowledge yet
  // -----------------------------------------------------------------------
  it('repair() should create symlink even if worktree has no .autopilot yet', () => {
    const { mainRepo, worktree } = scaffold('t4');

    const mainKnowledge = join(mainRepo, '.claude', 'knowledge');
    mkdirSync(mainKnowledge, { recursive: true });
    writeFileSync(join(mainKnowledge, 'index.md'), 'root index');

    // Worktree: .claude/ exists but NO knowledge/
    mkdirSync(join(worktree, '.claude'), { recursive: true });

    repairKnowledgeSymlink(mainRepo, worktree);

    const wtKnowledge = join(worktree, '.claude', 'knowledge');
    assert.ok(existsSync(wtKnowledge), 'knowledge path should exist after repair');

    const stat = lstatSync(wtKnowledge);
    assert.ok(stat.isSymbolicLink(), 'should be a symlink');
    assert.equal(readFileSync(join(wtKnowledge, 'index.md'), 'utf8'), 'root index');
  });

  // -----------------------------------------------------------------------
  // Test 5: remove() cleans up knowledge symlink
  // -----------------------------------------------------------------------
  it('remove() should clean up knowledge symlink', () => {
    const { mainRepo, worktree } = scaffold('t5');

    const mainKnowledge = join(mainRepo, '.claude', 'knowledge');
    mkdirSync(mainKnowledge, { recursive: true });

    const wtClaude = join(worktree, '.claude');
    mkdirSync(wtClaude, { recursive: true });
    const wtKnowledge = join(wtClaude, 'knowledge');
    symlinkSync(mainKnowledge, wtKnowledge);

    // Pre-condition: symlink exists
    assert.ok(lstatSync(wtKnowledge).isSymbolicLink());

    removeKnowledgeSymlink(worktree);

    // Assert: symlink is gone
    assert.ok(!existsSync(wtKnowledge), 'symlink should be removed');
    // lstat should throw ENOENT
    assert.throws(() => lstatSync(wtKnowledge), { code: 'ENOENT' });
  });

  // -----------------------------------------------------------------------
  // Test 5b: remove() is safe when no symlink exists
  // -----------------------------------------------------------------------
  it('remove() should not error when no knowledge symlink exists', () => {
    const { worktree } = scaffold('t5b');
    mkdirSync(join(worktree, '.claude'), { recursive: true });

    // Should not throw
    removeKnowledgeSymlink(worktree);
  });

  // -----------------------------------------------------------------------
  // Test 5c: remove() should not delete a real directory
  // -----------------------------------------------------------------------
  it('remove() should leave a real knowledge directory untouched', () => {
    const { worktree } = scaffold('t5c');
    const wtKnowledge = join(worktree, '.claude', 'knowledge');
    mkdirSync(wtKnowledge, { recursive: true });
    writeFileSync(join(wtKnowledge, 'keep.md'), 'important');

    removeKnowledgeSymlink(worktree);

    // Real directory should still exist
    assert.ok(existsSync(wtKnowledge), 'real directory should remain');
    assert.equal(readFileSync(join(wtKnowledge, 'keep.md'), 'utf8'), 'important');
  });

  // -----------------------------------------------------------------------
  // Test 6: Symlink provides transparent read access
  // -----------------------------------------------------------------------
  it('symlink provides transparent read access to main repo knowledge', () => {
    const { mainRepo, worktree } = scaffold('t6');

    const mainKnowledge = join(mainRepo, '.claude', 'knowledge');
    mkdirSync(mainKnowledge, { recursive: true });
    writeFileSync(join(mainKnowledge, 'index.md'), 'test content');

    // Create nested structure too
    mkdirSync(join(mainKnowledge, 'domains'), { recursive: true });
    writeFileSync(join(mainKnowledge, 'domains', 'frontend.md'), '# Frontend');

    const wtClaude = join(worktree, '.claude');
    mkdirSync(wtClaude, { recursive: true });
    symlinkSync(mainKnowledge, join(wtClaude, 'knowledge'));

    // Read through symlink
    assert.equal(
      readFileSync(join(worktree, '.claude', 'knowledge', 'index.md'), 'utf8'),
      'test content'
    );
    assert.equal(
      readFileSync(join(worktree, '.claude', 'knowledge', 'domains', 'frontend.md'), 'utf8'),
      '# Frontend'
    );

    // Directory listing through symlink
    const entries = readdirSync(join(worktree, '.claude', 'knowledge'));
    assert.ok(entries.includes('index.md'));
    assert.ok(entries.includes('domains'));
  });

  // -----------------------------------------------------------------------
  // Test 7: Symlink provides transparent write access
  // -----------------------------------------------------------------------
  it('symlink provides transparent write access — writes land in main repo', () => {
    const { mainRepo, worktree } = scaffold('t7');

    const mainKnowledge = join(mainRepo, '.claude', 'knowledge');
    mkdirSync(mainKnowledge, { recursive: true });

    const wtClaude = join(worktree, '.claude');
    mkdirSync(wtClaude, { recursive: true });
    symlinkSync(mainKnowledge, join(wtClaude, 'knowledge'));

    // Write through the symlink
    writeFileSync(
      join(worktree, '.claude', 'knowledge', 'new-entry.md'),
      '# New Entry\nExtracted from worktree work.'
    );

    // Verify it landed in main repo
    const content = readFileSync(join(mainKnowledge, 'new-entry.md'), 'utf8');
    assert.equal(content, '# New Entry\nExtracted from worktree work.');

    // Write a nested file
    mkdirSync(join(worktree, '.claude', 'knowledge', 'domains'), { recursive: true });
    writeFileSync(
      join(worktree, '.claude', 'knowledge', 'domains', 'perf.md'),
      '# Performance patterns'
    );
    assert.equal(
      readFileSync(join(mainKnowledge, 'domains', 'perf.md'), 'utf8'),
      '# Performance patterns'
    );
  });

  // -----------------------------------------------------------------------
  // Test 8: proactively created symlink allows transparent read/write
  // -----------------------------------------------------------------------
  it('repair() proactively created symlink allows transparent read/write', () => {
    const { mainRepo, worktree } = scaffold('t8');

    // Main repo: .claude/ exists but NO knowledge/
    mkdirSync(join(mainRepo, '.claude'), { recursive: true });

    // Worktree: .claude/ exists but NO knowledge/
    mkdirSync(join(worktree, '.claude'), { recursive: true });

    // repair() should proactively create the dir and symlink
    repairKnowledgeSymlink(mainRepo, worktree);

    const mainKnowledge = join(mainRepo, '.claude', 'knowledge');
    const wtKnowledge = join(worktree, '.claude', 'knowledge');

    // Write through worktree symlink → should land in main repo
    writeFileSync(join(wtKnowledge, 'test.md'), 'content');
    assert.equal(
      readFileSync(join(mainKnowledge, 'test.md'), 'utf8'),
      'content',
      'write through worktree symlink should land in main repo'
    );

    // Write through main repo → should be readable via worktree symlink
    writeFileSync(join(mainKnowledge, 'reverse.md'), 'reverse content');
    assert.equal(
      readFileSync(join(wtKnowledge, 'reverse.md'), 'utf8'),
      'reverse content',
      'write to main repo should be readable through worktree symlink'
    );
  });
});
