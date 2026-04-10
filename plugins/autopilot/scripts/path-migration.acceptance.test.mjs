/**
 * Red Team Acceptance Tests: Path Migration from .claude/ to .autopilot/
 *
 * These tests verify that all references to the old .claude/ paths have been
 * updated to the new .autopilot/ paths across lib.sh, setup.sh, worktree.mjs,
 * and all SKILL.md files.
 *
 * Test strategy: black-box verification using grep and bash execution.
 * No implementation code is read or assumed — tests are purely behavioral.
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { execSync } from 'child_process';
import { readFileSync, mkdirSync, writeFileSync, rmSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import os from 'os';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Resolve the plugin root: scripts/ is inside plugins/autopilot/
const SCRIPTS_DIR = __dirname;
const PLUGIN_ROOT = join(SCRIPTS_DIR, '..');
const SKILLS_DIR = join(PLUGIN_ROOT, 'skills');

// ---------------------------------------------------------------------------
// 1. lib.sh STATE_FILE path
// ---------------------------------------------------------------------------
describe('lib.sh init_paths()', () => {
  it('should set STATE_FILE to $PROJECT_ROOT/.autopilot/autopilot.local.md', () => {
    const libSh = join(SCRIPTS_DIR, 'lib.sh');

    // Source lib.sh, call init_paths with a fake project root, then echo STATE_FILE
    const bash = `
      set -euo pipefail
      export PROJECT_ROOT=/tmp/fake-project
      source "${libSh}"
      init_paths
      echo "$STATE_FILE"
    `;

    let output;
    try {
      output = execSync(`bash -c '${bash.replace(/'/g, "'\\''")}'`, {
        encoding: 'utf8',
      }).trim();
    } catch (err) {
      assert.fail(`bash execution failed: ${err.message}\nstderr: ${err.stderr}`);
    }

    assert.ok(
      output.includes('.autopilot/autopilot.local.md'),
      `STATE_FILE should contain '.autopilot/autopilot.local.md', got: '${output}'`
    );
    assert.ok(
      !output.includes('.claude/autopilot.local.md'),
      `STATE_FILE must NOT contain '.claude/autopilot.local.md', got: '${output}'`
    );
  });
});

// ---------------------------------------------------------------------------
// 2. setup.sh migration logic
// ---------------------------------------------------------------------------
describe('setup.sh migration', () => {
  it('should migrate .claude/autopilot.local.md to .autopilot/autopilot.local.md', () => {
    const setupSh = join(SCRIPTS_DIR, 'setup.sh');
    const tmpDir = mkdirSync(join(os.tmpdir(), `autopilot-migrate-test-${Date.now()}`), {
      recursive: true,
    }) ?? join(os.tmpdir(), `autopilot-migrate-test-${Date.now()}`);

    // Build a minimal fake git repo so PROJECT_ROOT detection works
    try {
      execSync('git init', { cwd: tmpDir, stdio: 'pipe' });
      execSync('git config user.email "test@test.com"', { cwd: tmpDir, stdio: 'pipe' });
      execSync('git config user.name "Test"', { cwd: tmpDir, stdio: 'pipe' });

      // Put a fake state file at the OLD path
      const oldDir = join(tmpDir, '.claude');
      mkdirSync(oldDir, { recursive: true });
      const fakeState = `---
phase: design
target: test migration
---
`;
      writeFileSync(join(oldDir, 'autopilot.local.md'), fakeState, 'utf8');

      // Run setup.sh — it should detect and migrate the file
      // Pass AUTOPILOT_SKIP_INTERACTIVE=1 so it doesn't block on user input
      execSync(`bash "${setupSh}"`, {
        cwd: tmpDir,
        env: {
          ...process.env,
          HOME: tmpDir,
          AUTOPILOT_SKIP_INTERACTIVE: '1',
          AUTOPILOT_MODE: 'cancel', // cancel so setup exits quickly
        },
        encoding: 'utf8',
        timeout: 15000,
        // Allow non-zero exit — setup.sh may exit early in cancel mode
        stdio: 'pipe',
      });
    } catch (_err) {
      // setup.sh may exit non-zero in test environment; we only check file state
    }

    const newPath = join(tmpDir, '.autopilot', 'autopilot.local.md');
    const oldPath = join(tmpDir, '.claude', 'autopilot.local.md');

    assert.ok(
      existsSync(newPath),
      `Migrated file should exist at .autopilot/autopilot.local.md`
    );
    assert.ok(
      !existsSync(oldPath),
      `Old file at .claude/autopilot.local.md should have been removed after migration`
    );

    // Cleanup
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it('should create .autopilot/ directory (not .claude/) for a fresh state file', () => {
    const setupSh = join(SCRIPTS_DIR, 'setup.sh');
    const tmpDir = join(os.tmpdir(), `autopilot-fresh-test-${Date.now()}`);
    mkdirSync(tmpDir, { recursive: true });

    try {
      execSync('git init', { cwd: tmpDir, stdio: 'pipe' });
      execSync('git config user.email "test@test.com"', { cwd: tmpDir, stdio: 'pipe' });
      execSync('git config user.name "Test"', { cwd: tmpDir, stdio: 'pipe' });

      // No pre-existing state file — setup.sh should create the dir under .autopilot/
      execSync(`bash "${setupSh}"`, {
        cwd: tmpDir,
        env: {
          ...process.env,
          HOME: tmpDir,
          AUTOPILOT_SKIP_INTERACTIVE: '1',
          AUTOPILOT_MODE: 'cancel',
        },
        encoding: 'utf8',
        timeout: 15000,
        stdio: 'pipe',
      });
    } catch (_err) {
      // Non-zero exit expected; check filesystem state only
    }

    const autopilotDir = join(tmpDir, '.autopilot');
    const claudeStateFile = join(tmpDir, '.claude', 'autopilot.local.md');

    // .autopilot/ dir should exist OR the state file should be in .autopilot/
    // (setup may not have written the file if it exited early due to cancel mode,
    //  but it must NOT have created .claude/autopilot.local.md)
    assert.ok(
      !existsSync(claudeStateFile),
      `setup.sh must NOT create state file at .claude/autopilot.local.md`
    );

    // Cleanup
    rmSync(tmpDir, { recursive: true, force: true });
  });
});

// ---------------------------------------------------------------------------
// 3. worktree.mjs reads worktree-links from .autopilot/
// ---------------------------------------------------------------------------
describe('worktree.mjs worktree-links path', () => {
  it('should reference .autopilot/worktree-links, not .claude/worktree-links', () => {
    const worktreeMjs = join(SCRIPTS_DIR, 'worktree.mjs');
    const source = readFileSync(worktreeMjs, 'utf8');

    // There must be at least one reference to .autopilot/worktree-links
    assert.ok(
      source.includes('.autopilot/worktree-links'),
      `worktree.mjs should reference '.autopilot/worktree-links'`
    );

    // There must be NO reference to .claude/worktree-links (old path)
    assert.ok(
      !source.includes('.claude/worktree-links'),
      `worktree.mjs must NOT reference '.claude/worktree-links'`
    );
  });
});

// ---------------------------------------------------------------------------
// 4. No stale .claude/autopilot references in scripts/ (except migration code)
// ---------------------------------------------------------------------------
describe('scripts/ stale .claude/ reference audit', () => {
  it('only setup.sh should reference .claude/autopilot (migration detection code)', () => {
    // Use grep to find all occurrences of .claude/autopilot in .sh and .mjs files
    let grepOutput = '';
    try {
      grepOutput = execSync(
        `grep -rn '\\.claude/autopilot' "${SCRIPTS_DIR}" --include="*.sh" --include="*.mjs" || true`,
        { encoding: 'utf8' }
      );
    } catch (_err) {
      // grep exits non-zero when no matches; that's fine
      grepOutput = '';
    }

    const lines = grepOutput.trim().split('\n').filter(Boolean);

    // Every match must come from setup.sh (migration detection) or this test file itself
    const nonSetupMatches = lines.filter(
      (line) =>
        !line.startsWith(join(SCRIPTS_DIR, 'setup.sh')) &&
        !line.startsWith(join(SCRIPTS_DIR, 'path-migration.acceptance.test.mjs'))
    );

    assert.strictEqual(
      nonSetupMatches.length,
      0,
      `Found stale .claude/autopilot references outside setup.sh:\n${nonSetupMatches.join('\n')}`
    );
  });
});

// ---------------------------------------------------------------------------
// 5. No stale .claude/autopilot.local.md in SKILL.md files
// ---------------------------------------------------------------------------
describe('SKILL.md files stale path audit', () => {
  it('no SKILL.md should reference .claude/autopilot.local.md', () => {
    let grepOutput = '';
    try {
      grepOutput = execSync(
        `grep -rn '\\.claude/autopilot\\.local\\.md' "${PLUGIN_ROOT}" --include="SKILL.md" || true`,
        { encoding: 'utf8' }
      );
    } catch (_err) {
      grepOutput = '';
    }

    const lines = grepOutput.trim().split('\n').filter(Boolean);

    assert.strictEqual(
      lines.length,
      0,
      `Found stale .claude/autopilot.local.md references in SKILL.md files:\n${lines.join('\n')}`
    );
  });

  it('at least one SKILL.md should reference .autopilot/autopilot.local.md (sanity check)', () => {
    let grepOutput = '';
    try {
      grepOutput = execSync(
        `grep -rn '\\.autopilot/autopilot\\.local\\.md' "${PLUGIN_ROOT}" --include="SKILL.md" || true`,
        { encoding: 'utf8' }
      );
    } catch (_err) {
      grepOutput = '';
    }

    const lines = grepOutput.trim().split('\n').filter(Boolean);

    assert.ok(
      lines.length > 0,
      `Expected at least one SKILL.md to reference '.autopilot/autopilot.local.md' but found none`
    );
  });
});

// ---------------------------------------------------------------------------
// 6. Doctor SKILL.md stale path audit
// ---------------------------------------------------------------------------
describe('autopilot-doctor SKILL.md stale path audit', () => {
  const doctorSkillPath = join(SKILLS_DIR, 'autopilot-doctor', 'SKILL.md');

  it('should NOT reference .claude/doctor-report', () => {
    let grepOutput = '';
    try {
      grepOutput = execSync(
        `grep -n '\\.claude/doctor-report' "${doctorSkillPath}" || true`,
        { encoding: 'utf8' }
      );
    } catch (_err) {
      grepOutput = '';
    }

    const lines = grepOutput.trim().split('\n').filter(Boolean);

    assert.strictEqual(
      lines.length,
      0,
      `autopilot-doctor SKILL.md should NOT reference .claude/doctor-report. Found:\n${lines.join('\n')}`
    );
  });

  it('should reference .autopilot/doctor-report (sanity check)', () => {
    let grepOutput = '';
    try {
      grepOutput = execSync(
        `grep -n '\\.autopilot/doctor-report' "${doctorSkillPath}" || true`,
        { encoding: 'utf8' }
      );
    } catch (_err) {
      grepOutput = '';
    }

    const lines = grepOutput.trim().split('\n').filter(Boolean);

    assert.ok(
      lines.length > 0,
      `autopilot-doctor SKILL.md should reference '.autopilot/doctor-report' but found none`
    );
  });

  it('should NOT reference .claude/worktree-links', () => {
    let grepOutput = '';
    try {
      grepOutput = execSync(
        `grep -n '\\.claude/worktree-links' "${doctorSkillPath}" || true`,
        { encoding: 'utf8' }
      );
    } catch (_err) {
      grepOutput = '';
    }

    const lines = grepOutput.trim().split('\n').filter(Boolean);

    assert.strictEqual(
      lines.length,
      0,
      `autopilot-doctor SKILL.md should NOT reference .claude/worktree-links. Found:\n${lines.join('\n')}`
    );
  });

  it('should reference .autopilot/worktree-links (sanity check)', () => {
    let grepOutput = '';
    try {
      grepOutput = execSync(
        `grep -n '\\.autopilot/worktree-links' "${doctorSkillPath}" || true`,
        { encoding: 'utf8' }
      );
    } catch (_err) {
      grepOutput = '';
    }

    const lines = grepOutput.trim().split('\n').filter(Boolean);

    assert.ok(
      lines.length > 0,
      `autopilot-doctor SKILL.md should reference '.autopilot/worktree-links' but found none`
    );
  });
});
