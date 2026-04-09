#!/usr/bin/env node
// Red team acceptance tests for autopilot project mode
// Tests: setup.sh flags, task matching, status/next commands, stop-hook mode, SKILL.md structure

import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const PLUGIN_ROOT = path.resolve(import.meta.dirname, '../..');
const SETUP_SH = path.join(PLUGIN_ROOT, 'scripts', 'setup.sh');
const STOP_HOOK_SH = path.join(PLUGIN_ROOT, 'scripts', 'stop-hook.sh');
const SKILL_MD = path.join(PLUGIN_ROOT, 'skills', 'autopilot', 'SKILL.md');
const PROJECT_SKILL_MD = path.join(PLUGIN_ROOT, 'skills', 'autopilot-project', 'SKILL.md');

function runSetup(args, cwd) {
  try {
    return execSync(`bash "${SETUP_SH}" ${args}`, {
      cwd,
      env: { ...process.env, HOME: os.homedir(), PATH: process.env.PATH },
      encoding: 'utf8',
      timeout: 10000,
    });
  } catch (e) {
    return e.stdout || e.message;
  }
}

function readStateFile(cwd) {
  const stateFile = path.join(cwd, '.claude', 'autopilot.local.md');
  if (!fs.existsSync(stateFile)) return null;
  return fs.readFileSync(stateFile, 'utf8');
}

function getField(content, key) {
  const match = content.match(new RegExp(`^${key}:\\s*"?([^"\\n]*)"?`, 'm'));
  return match ? match[1] : null;
}

describe('autopilot project mode', () => {
  let tmpDir;

  before(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'autopilot-project-test-'));
    // Make it look like a git repo for init_paths
    execSync('git init', { cwd: tmpDir, encoding: 'utf8' });
    execSync('git commit --allow-empty -m "init"', { cwd: tmpDir, encoding: 'utf8' });
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  describe('setup.sh --project flag', () => {
    it('creates state file with mode: project', () => {
      // Clean up any existing state
      const stateDir = path.join(tmpDir, '.claude');
      if (fs.existsSync(path.join(stateDir, 'autopilot.local.md'))) {
        fs.unlinkSync(path.join(stateDir, 'autopilot.local.md'));
      }

      runSetup('--project 测试大型项目', tmpDir);
      const state = readStateFile(tmpDir);
      assert.ok(state, 'state file should be created');
      assert.equal(getField(state, 'mode'), 'project');
      assert.equal(getField(state, 'phase'), 'design');
      assert.equal(getField(state, 'brief_file'), '');
    });
  });

  describe('setup.sh --single flag', () => {
    it('creates state file with mode: single', () => {
      const stateFile = path.join(tmpDir, '.claude', 'autopilot.local.md');
      if (fs.existsSync(stateFile)) fs.unlinkSync(stateFile);

      runSetup('--single 简单修复', tmpDir);
      const state = readStateFile(tmpDir);
      assert.ok(state, 'state file should be created');
      assert.equal(getField(state, 'mode'), 'single');
    });
  });

  describe('setup.sh default mode (empty)', () => {
    it('creates state file with empty mode for auto-detection', () => {
      const stateFile = path.join(tmpDir, '.claude', 'autopilot.local.md');
      if (fs.existsSync(stateFile)) fs.unlinkSync(stateFile);

      runSetup('普通目标描述', tmpDir);
      const state = readStateFile(tmpDir);
      assert.ok(state, 'state file should be created');
      assert.equal(getField(state, 'mode'), '');
    });
  });

  describe('task file natural language matching', () => {
    before(() => {
      // Create project structure
      const tasksDir = path.join(tmpDir, '.autopilot', 'project', 'tasks');
      fs.mkdirSync(tasksDir, { recursive: true });
      fs.writeFileSync(path.join(tmpDir, '.autopilot', 'project', 'dag.yaml'), `project: test
tasks:
  - id: "001-wire-schema"
    title: "定义共享协议包"
    depends_on: []
    status: pending
  - id: "002-db-models"
    title: "新增数据模型"
    depends_on: ["001-wire-schema"]
    status: pending
`);
      fs.writeFileSync(path.join(tasksDir, '001-wire-schema.md'), `---
id: "001-wire-schema"
depends_on: []
---
## 目标
定义 Wire 共享协议包
`);
      fs.writeFileSync(path.join(tasksDir, '002-db-models.md'), `---
id: "002-db-models"
depends_on: ["001-wire-schema"]
---
## 目标
新增数据模型
`);
    });

    it('matches by exact prefix (001-wire)', () => {
      const stateFile = path.join(tmpDir, '.claude', 'autopilot.local.md');
      if (fs.existsSync(stateFile)) fs.unlinkSync(stateFile);

      const output = runSetup('001-wire', tmpDir);
      assert.ok(output.includes('匹配到项目任务'), `expected match hint in output: ${output}`);
      const state = readStateFile(tmpDir);
      assert.ok(state, 'state file should be created');
      const briefFile = getField(state, 'brief_file');
      assert.ok(briefFile && briefFile.includes('001-wire-schema.md'), `brief_file should point to task file, got: ${briefFile}`);
    });

    it('matches by fuzzy substring (wire-schema)', () => {
      const stateFile = path.join(tmpDir, '.claude', 'autopilot.local.md');
      if (fs.existsSync(stateFile)) fs.unlinkSync(stateFile);

      const output = runSetup('wire-schema', tmpDir);
      assert.ok(output.includes('匹配到项目任务'), `expected match hint: ${output}`);
      const state = readStateFile(tmpDir);
      const briefFile = getField(state, 'brief_file');
      assert.ok(briefFile && briefFile.includes('001-wire-schema.md'), `should match wire-schema, got: ${briefFile}`);
    });

    it('does NOT match unrelated goal', () => {
      const stateFile = path.join(tmpDir, '.claude', 'autopilot.local.md');
      if (fs.existsSync(stateFile)) fs.unlinkSync(stateFile);

      const output = runSetup('给登录页加loading状态', tmpDir);
      assert.ok(!output.includes('匹配到项目任务'), 'should NOT match any task file');
      const state = readStateFile(tmpDir);
      assert.equal(getField(state, 'brief_file'), '');
    });

    it('brief mode inlines task content into goal section', () => {
      const stateFile = path.join(tmpDir, '.claude', 'autopilot.local.md');
      if (fs.existsSync(stateFile)) fs.unlinkSync(stateFile);

      runSetup('001-wire', tmpDir);
      const state = readStateFile(tmpDir);
      assert.ok(state.includes('定义 Wire 共享协议包'), 'state should inline brief content');
    });
  });

  describe('status command with project DAG', () => {
    it('shows DAG overview when no active autopilot', () => {
      const stateFile = path.join(tmpDir, '.claude', 'autopilot.local.md');
      if (fs.existsSync(stateFile)) fs.unlinkSync(stateFile);

      const output = runSetup('status', tmpDir);
      assert.ok(output.includes('项目 DAG'), `should show DAG section: ${output}`);
      assert.ok(output.includes('001-wire-schema'), 'should list task 001');
      assert.ok(output.includes('002-db-models'), 'should list task 002');
    });
  });

  describe('next command', () => {
    it('identifies ready tasks (no deps pending)', () => {
      const output = runSetup('next', tmpDir);
      assert.ok(output.includes('001-wire-schema'), `should show task 001 as ready: ${output}`);
      assert.ok(!output.includes('→ /autopilot 002'), 'task 002 should NOT be ready (blocked by 001)');
    });

    it('shows task 002 as ready after 001 is done', () => {
      // Update dag.yaml to mark 001 as done
      const dagFile = path.join(tmpDir, '.autopilot', 'project', 'dag.yaml');
      let dag = fs.readFileSync(dagFile, 'utf8');
      dag = dag.replace(
        /id: "001-wire-schema"\n\s*title: "定义共享协议包"\n\s*depends_on: \[\]\n\s*status: pending/,
        'id: "001-wire-schema"\n    title: "定义共享协议包"\n    depends_on: []\n    status: done'
      );
      fs.writeFileSync(dagFile, dag);

      const output = runSetup('next', tmpDir);
      assert.ok(output.includes('002-db-models'), `should show task 002 as ready: ${output}`);
    });
  });

  describe('stop-hook.sh mode in system message', () => {
    it('includes mode in system message output', () => {
      const content = fs.readFileSync(STOP_HOOK_SH, 'utf8');
      assert.ok(content.includes('MODE=$(get_field "mode"'), 'stop-hook should read mode field');
      assert.ok(content.includes('${MODE:+ | mode: $MODE}'), 'stop-hook should include mode in system message');
    });
  });

  describe('SKILL.md structure', () => {
    it('has step 1.5 mode detection section', () => {
      const content = fs.readFileSync(SKILL_MD, 'utf8');
      assert.ok(content.includes('步骤 1.5. 模式检测与分流'), 'SKILL.md should have step 1.5');
      assert.ok(content.includes('AskUserQuestion'), 'step 1.5 should reference AskUserQuestion');
      assert.ok(content.includes('项目模式 Plan 内容'), 'should have project mode plan template');
    });

    it('has step 6b project mode file creation', () => {
      const content = fs.readFileSync(SKILL_MD, 'utf8');
      assert.ok(content.includes('步骤 6b. 项目模式文件创建'), 'SKILL.md should have step 6b');
      assert.ok(content.includes('dag.yaml'), 'step 6b should mention dag.yaml');
    });

    it('has handoff writing in merge phase', () => {
      const content = fs.readFileSync(SKILL_MD, 'utf8');
      assert.ok(content.includes('1.5. 写入 Handoff（brief 模式）'), 'merge phase should have handoff step');
      assert.ok(content.includes('.handoff.md'), 'should mention handoff file extension');
    });

    it('has mode and brief_file in frontmatter docs', () => {
      const content = fs.readFileSync(SKILL_MD, 'utf8');
      assert.ok(content.includes('mode: ""'), 'frontmatter docs should include mode field');
      assert.ok(content.includes('brief_file: ""'), 'frontmatter docs should include brief_file field');
    });
  });

  describe('autopilot-project SKILL.md', () => {
    it('exists and has correct structure', () => {
      assert.ok(fs.existsSync(PROJECT_SKILL_MD), 'autopilot-project/SKILL.md should exist');
      const content = fs.readFileSync(PROJECT_SKILL_MD, 'utf8');
      assert.ok(content.includes('name: autopilot-project'), 'should have correct skill name');
      assert.ok(content.includes('dag.yaml'), 'should document DAG format');
      assert.ok(content.includes('Handoff'), 'should document handoff format');
      assert.ok(content.includes('/autopilot status'), 'should document status command');
      assert.ok(content.includes('/autopilot next'), 'should document next command');
    });

    it('is under 150 lines (AI Native principle)', () => {
      const content = fs.readFileSync(PROJECT_SKILL_MD, 'utf8');
      const lines = content.split('\n').length;
      assert.ok(lines <= 150, `SKILL.md should be concise (~100 lines), got ${lines}`);
    });
  });
});
