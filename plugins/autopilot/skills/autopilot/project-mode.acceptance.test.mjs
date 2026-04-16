#!/usr/bin/env node
// Red team acceptance tests for autopilot project mode
// Tests: setup.sh flags, task matching, status/next commands, stop-hook mode,
//        SKILL.md structure, auto-chain, project-qa, lib.sh shared functions

import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const PLUGIN_ROOT = path.resolve(import.meta.dirname, '../..');
const SETUP_SH = path.join(PLUGIN_ROOT, 'scripts', 'setup.sh');
const STOP_HOOK_SH = path.join(PLUGIN_ROOT, 'scripts', 'stop-hook.sh');
const LIB_SH = path.join(PLUGIN_ROOT, 'scripts', 'lib.sh');
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

function runStopHook(cwd, stdinJson) {
  try {
    return execSync(`echo '${stdinJson}' | bash "${STOP_HOOK_SH}"`, {
      cwd,
      env: { ...process.env, HOME: os.homedir(), PATH: process.env.PATH },
      encoding: 'utf8',
      timeout: 10000,
    });
  } catch (e) {
    return e.stdout || e.message;
  }
}

function runLibFunc(funcName, args, cwd) {
  const script = `source "${LIB_SH}" && init_paths "${cwd}" && ${funcName} ${args}`;
  try {
    return execSync(`bash -c '${script}'`, {
      cwd,
      env: { ...process.env, HOME: os.homedir(), PATH: process.env.PATH },
      encoding: 'utf8',
      timeout: 10000,
    }).trim();
  } catch (e) {
    return (e.stdout || '').trim();
  }
}

function readStateFile(cwd) {
  // New: read from active pointer → requirements dir
  const activeFile = path.join(cwd, '.autopilot', 'active');
  if (fs.existsSync(activeFile)) {
    const slug = fs.readFileSync(activeFile, 'utf8').trim();
    const stateFile = path.join(cwd, '.autopilot', 'requirements', slug, 'state.md');
    if (fs.existsSync(stateFile)) return fs.readFileSync(stateFile, 'utf8');
  }
  // Fallback: old path for backward compat tests
  const oldStateFile = path.join(cwd, '.autopilot', 'autopilot.local.md');
  if (fs.existsSync(oldStateFile)) return fs.readFileSync(oldStateFile, 'utf8');
  return null;
}

function getField(content, key) {
  const match = content.match(new RegExp(`^${key}:\\s*"?([^"\\n]*)"?`, 'm'));
  return match ? match[1] : null;
}

function cleanState(tmpDir) {
  // Remove active pointer + any requirements dirs + old state file
  const activeFile = path.join(tmpDir, '.autopilot', 'active');
  if (fs.existsSync(activeFile)) fs.unlinkSync(activeFile);
  const reqDir = path.join(tmpDir, '.autopilot', 'requirements');
  if (fs.existsSync(reqDir)) fs.rmSync(reqDir, { recursive: true, force: true });
  const oldStateFile = path.join(tmpDir, '.autopilot', 'autopilot.local.md');
  if (fs.existsSync(oldStateFile)) fs.unlinkSync(oldStateFile);
}

function isActive(tmpDir) {
  return fs.existsSync(path.join(tmpDir, '.autopilot', 'active'));
}

describe('autopilot project mode', () => {
  let tmpDir;

  before(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'autopilot-project-test-'));
    execSync('git init', { cwd: tmpDir, encoding: 'utf8' });
    execSync('git commit --allow-empty -m "init"', { cwd: tmpDir, encoding: 'utf8' });
  });

  after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  describe('setup.sh --project flag', () => {
    it('creates state file with mode: project', () => {
      cleanState(tmpDir);
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
      cleanState(tmpDir);
      runSetup('--single 简单修复', tmpDir);
      const state = readStateFile(tmpDir);
      assert.ok(state, 'state file should be created');
      assert.equal(getField(state, 'mode'), 'single');
    });
  });

  describe('setup.sh default mode (empty)', () => {
    it('creates state file with empty mode for auto-detection', () => {
      cleanState(tmpDir);
      runSetup('普通目标描述', tmpDir);
      const state = readStateFile(tmpDir);
      assert.ok(state, 'state file should be created');
      assert.equal(getField(state, 'mode'), '');
    });
  });

  describe('new frontmatter fields', () => {
    it('state file includes next_task field', () => {
      cleanState(tmpDir);
      runSetup('普通目标', tmpDir);
      const state = readStateFile(tmpDir);
      assert.ok(state, 'state file should be created');
      assert.equal(getField(state, 'next_task'), '');
    });

    it('state file includes auto_approve field', () => {
      cleanState(tmpDir);
      runSetup('普通目标', tmpDir);
      const state = readStateFile(tmpDir);
      assert.equal(getField(state, 'auto_approve'), 'false');
    });

    it('state file includes plan_mode field', () => {
      cleanState(tmpDir);
      runSetup('普通目标', tmpDir);
      const state = readStateFile(tmpDir);
      assert.equal(getField(state, 'plan_mode'), '');
    });

    it('--deep flag sets plan_mode to deep', () => {
      cleanState(tmpDir);
      runSetup('--deep 深度设计任务', tmpDir);
      const state = readStateFile(tmpDir);
      assert.equal(getField(state, 'plan_mode'), 'deep');
    });

    it('state file includes task_dir field', () => {
      cleanState(tmpDir);
      runSetup('普通目标', tmpDir);
      const state = readStateFile(tmpDir);
      const taskDir = getField(state, 'task_dir');
      assert.ok(taskDir && taskDir.includes('.autopilot/requirements/'), `task_dir should point to requirements dir, got: ${taskDir}`);
    });
  });

  describe('requirements folder management', () => {
    it('creates active pointer file', () => {
      cleanState(tmpDir);
      runSetup('测试需求管理', tmpDir);
      assert.ok(isActive(tmpDir), 'active pointer should exist');
    });

    it('creates requirements dir with slug', () => {
      cleanState(tmpDir);
      runSetup('测试需求管理', tmpDir);
      const slug = fs.readFileSync(path.join(tmpDir, '.autopilot', 'active'), 'utf8').trim();
      assert.ok(slug.length > 0, 'slug should not be empty');
      const reqDir = path.join(tmpDir, '.autopilot', 'requirements', slug);
      assert.ok(fs.existsSync(reqDir), `requirements dir should exist: ${reqDir}`);
    });

    it('state file lives inside requirements dir', () => {
      cleanState(tmpDir);
      runSetup('测试状态位置', tmpDir);
      const slug = fs.readFileSync(path.join(tmpDir, '.autopilot', 'active'), 'utf8').trim();
      const stateFile = path.join(tmpDir, '.autopilot', 'requirements', slug, 'state.md');
      assert.ok(fs.existsSync(stateFile), `state file should be at: ${stateFile}`);
    });

    it('cancel removes active pointer but preserves requirements folder', () => {
      cleanState(tmpDir);
      runSetup('取消测试', tmpDir);
      const slug = fs.readFileSync(path.join(tmpDir, '.autopilot', 'active'), 'utf8').trim();
      runSetup('cancel', tmpDir);
      assert.ok(!isActive(tmpDir), 'active pointer should be removed after cancel');
      const reqDir = path.join(tmpDir, '.autopilot', 'requirements', slug);
      assert.ok(fs.existsSync(reqDir), 'requirements dir should be preserved after cancel');
    });
  });

  describe('task file natural language matching', () => {
    before(() => {
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
      cleanState(tmpDir);
      const output = runSetup('001-wire', tmpDir);
      assert.ok(output.includes('匹配到项目任务'), `expected match hint in output: ${output}`);
      const state = readStateFile(tmpDir);
      assert.ok(state, 'state file should be created');
      const briefFile = getField(state, 'brief_file');
      assert.ok(briefFile && briefFile.includes('001-wire-schema.md'), `brief_file should point to task file, got: ${briefFile}`);
    });

    it('matches by fuzzy substring (wire-schema)', () => {
      cleanState(tmpDir);
      const output = runSetup('wire-schema', tmpDir);
      assert.ok(output.includes('匹配到项目任务'), `expected match hint: ${output}`);
      const state = readStateFile(tmpDir);
      const briefFile = getField(state, 'brief_file');
      assert.ok(briefFile && briefFile.includes('001-wire-schema.md'), `should match wire-schema, got: ${briefFile}`);
    });

    it('does NOT match unrelated goal', () => {
      cleanState(tmpDir);
      const output = runSetup('给登录页加loading状态', tmpDir);
      assert.ok(!output.includes('匹配到项目任务'), 'should NOT match any task file');
      const state = readStateFile(tmpDir);
      assert.equal(getField(state, 'brief_file'), '');
    });

    it('brief mode inlines task content into goal section', () => {
      cleanState(tmpDir);
      runSetup('001-wire', tmpDir);
      const state = readStateFile(tmpDir);
      assert.ok(state.includes('定义 Wire 共享协议包'), 'state should inline brief content');
    });
  });

  describe('status command with project DAG', () => {
    it('shows DAG overview when no active autopilot', () => {
      cleanState(tmpDir);
      const output = runSetup('status', tmpDir);
      assert.ok(output.includes('项目 DAG'), `should show DAG section: ${output}`);
      assert.ok(output.includes('001-wire-schema'), 'should list task 001');
      assert.ok(output.includes('002-db-models'), 'should list task 002');
    });
  });

  describe('next command auto-start', () => {
    before(() => {
      // Reset dag to have 001 pending
      const dagFile = path.join(tmpDir, '.autopilot', 'project', 'dag.yaml');
      fs.writeFileSync(dagFile, `project: test
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
    });

    it('creates state file for first ready task', () => {
      cleanState(tmpDir);
      const output = runSetup('next', tmpDir);
      assert.ok(output.includes('自动选择'), `should auto-select: ${output}`);
      const state = readStateFile(tmpDir);
      assert.ok(state, 'state file should be created');
      const briefFile = getField(state, 'brief_file');
      assert.ok(briefFile && briefFile.includes('001-wire-schema.md'), `should start task 001, got: ${briefFile}`);
    });

    it('reports ALL_DONE when all tasks done', () => {
      cleanState(tmpDir);
      const dagFile = path.join(tmpDir, '.autopilot', 'project', 'dag.yaml');
      fs.writeFileSync(dagFile, `project: test
tasks:
  - id: "001-wire-schema"
    title: "定义共享协议包"
    depends_on: []
    status: done
  - id: "002-db-models"
    title: "新增数据模型"
    depends_on: ["001-wire-schema"]
    status: done
`);
      const output = runSetup('next', tmpDir);
      assert.ok(output.includes('所有任务已完成'), `should report all done: ${output}`);
    });

    it('shows task 002 as ready after 001 is done', () => {
      cleanState(tmpDir);
      const dagFile = path.join(tmpDir, '.autopilot', 'project', 'dag.yaml');
      fs.writeFileSync(dagFile, `project: test
tasks:
  - id: "001-wire-schema"
    title: "定义共享协议包"
    depends_on: []
    status: done
  - id: "002-db-models"
    title: "新增数据模型"
    depends_on: ["001-wire-schema"]
    status: pending
`);
      const output = runSetup('next', tmpDir);
      assert.ok(output.includes('自动选择'), `should auto-select: ${output}`);
      const state = readStateFile(tmpDir);
      const briefFile = getField(state, 'brief_file');
      assert.ok(briefFile && briefFile.includes('002-db-models.md'), `should start task 002, got: ${briefFile}`);
    });
  });

  describe('lib.sh get_first_ready_task', () => {
    it('returns first ready task ID', () => {
      const dagFile = path.join(tmpDir, '.autopilot', 'project', 'dag.yaml');
      fs.writeFileSync(dagFile, `project: test
tasks:
  - id: "001-wire-schema"
    title: "Task 1"
    depends_on: []
    status: pending
  - id: "002-db-models"
    title: "Task 2"
    depends_on: ["001-wire-schema"]
    status: pending
`);
      const result = runLibFunc('get_first_ready_task', `"${dagFile}"`, tmpDir);
      assert.equal(result, '001-wire-schema');
    });

    it('returns ALL_DONE when all done', () => {
      const dagFile = path.join(tmpDir, '.autopilot', 'project', 'dag.yaml');
      fs.writeFileSync(dagFile, `project: test
tasks:
  - id: "001-wire-schema"
    title: "Task 1"
    depends_on: []
    status: done
  - id: "002-db-models"
    title: "Task 2"
    depends_on: ["001-wire-schema"]
    status: done
`);
      const result = runLibFunc('get_first_ready_task', `"${dagFile}"`, tmpDir);
      assert.equal(result, 'ALL_DONE');
    });

    it('returns empty when all blocked', () => {
      const dagFile = path.join(tmpDir, '.autopilot', 'project', 'dag.yaml');
      fs.writeFileSync(dagFile, `project: test
tasks:
  - id: "001-wire-schema"
    title: "Task 1"
    depends_on: []
    status: in_progress
  - id: "002-db-models"
    title: "Task 2"
    depends_on: ["001-wire-schema"]
    status: pending
`);
      const result = runLibFunc('get_first_ready_task', `"${dagFile}"`, tmpDir);
      assert.equal(result, '');
    });
  });

  describe('stop-hook auto-chain', () => {
    it('creates new state file when next_task is set', () => {
      // Prepare: state file with phase=done and next_task (using old path for backward compat)
      const stateDir = path.join(tmpDir, '.autopilot');
      cleanState(tmpDir);
      fs.mkdirSync(stateDir, { recursive: true });
      fs.writeFileSync(path.join(stateDir, 'autopilot.local.md'), `---
active: true
phase: "done"
gate: ""
iteration: 5
max_iterations: 30
max_retries: 3
retry_count: 0
mode: "single"
plan_mode: ""
brief_file: "/some/path/001-wire-schema.md"
next_task: "002-db-models"
auto_approve: false
knowledge_extracted: "skipped"
task_dir: ""
session_id: test-session
started_at: "2026-01-01T00:00:00Z"
---
## 变更日志
`);
      // Prepare dag and task files
      const dagFile = path.join(stateDir, 'project', 'dag.yaml');
      const tasksDir = path.join(stateDir, 'project', 'tasks');
      fs.mkdirSync(tasksDir, { recursive: true });
      fs.writeFileSync(dagFile, `project: test
tasks:
  - id: "002-db-models"
    title: "Task 2"
    depends_on: []
    status: pending
`);
      fs.writeFileSync(path.join(tasksDir, '002-db-models.md'), `---
id: "002-db-models"
depends_on: []
---
## 目标
新增数据模型
`);

      const stdinJson = `{"cwd":"${tmpDir}","session_id":"test-session"}`;
      const output = runStopHook(tmpDir, stdinJson);
      // Should output block JSON
      assert.ok(output.includes('"decision"'), `should output block JSON: ${output}`);
      assert.ok(output.includes('"block"'), `should be a block decision: ${output}`);
      // Check new state file
      const state = readStateFile(tmpDir);
      assert.ok(state, 'new state file should exist');
      assert.equal(getField(state, 'phase'), 'design');
      assert.equal(getField(state, 'auto_approve'), 'true');
      assert.ok(state.includes('002-db-models'), 'should reference new task');
    });

    it('does not auto-chain in single-task mode (no DAG)', () => {
      const stateDir = path.join(tmpDir, '.autopilot');
      // Remove project dir to simulate no DAG
      fs.rmSync(path.join(stateDir, 'project'), { recursive: true, force: true });
      // Write old-style state file for backward compat (stop-hook handles both)
      cleanState(tmpDir);
      fs.mkdirSync(stateDir, { recursive: true });
      fs.writeFileSync(path.join(stateDir, 'autopilot.local.md'), `---
active: true
phase: "done"
gate: ""
iteration: 5
max_iterations: 30
max_retries: 3
retry_count: 0
mode: "single"
plan_mode: ""
brief_file: ""
next_task: ""
auto_approve: false
knowledge_extracted: "skipped"
task_dir: ""
session_id: test-session
started_at: "2026-01-01T00:00:00Z"
---
## 变更日志
`);

      const stdinJson = `{"cwd":"${tmpDir}","session_id":"test-session"}`;
      const output = runStopHook(tmpDir, stdinJson);
      // Should NOT output block JSON (exit 0 = no output or non-JSON)
      assert.ok(!output.includes('"block"'), `should not block: ${output}`);
    });
  });

  describe('stop-hook project-qa completion', () => {
    it('cleans up project-qa without chaining', () => {
      const stateDir = path.join(tmpDir, '.autopilot');
      cleanState(tmpDir);
      fs.mkdirSync(stateDir, { recursive: true });
      fs.writeFileSync(path.join(stateDir, 'autopilot.local.md'), `---
active: true
phase: "done"
gate: ""
iteration: 3
max_iterations: 10
max_retries: 2
retry_count: 0
mode: "project-qa"
plan_mode: ""
brief_file: ""
next_task: ""
auto_approve: true
knowledge_extracted: "skipped"
task_dir: ""
session_id: test-session
started_at: "2026-01-01T00:00:00Z"
---
## 变更日志
`);

      const stdinJson = `{"cwd":"${tmpDir}","session_id":"test-session"}`;
      const output = runStopHook(tmpDir, stdinJson);
      assert.ok(!output.includes('"block"'), `project-qa done should not block: ${output}`);
    });
  });

  describe('stop-hook triggers project QA when all tasks done', () => {
    it('creates project-qa state when brief_file set and all done', () => {
      const stateDir = path.join(tmpDir, '.autopilot');
      const projectDir = path.join(stateDir, 'project');
      const tasksDir = path.join(projectDir, 'tasks');
      cleanState(tmpDir);
      fs.mkdirSync(tasksDir, { recursive: true });

      // All tasks done
      fs.writeFileSync(path.join(projectDir, 'dag.yaml'), `project: test
tasks:
  - id: "001-wire-schema"
    title: "Task 1"
    depends_on: []
    status: done
  - id: "002-db-models"
    title: "Task 2"
    depends_on: ["001-wire-schema"]
    status: done
`);
      fs.writeFileSync(path.join(projectDir, 'design.md'), `# Architecture\nSome design content`);

      fs.writeFileSync(path.join(stateDir, 'autopilot.local.md'), `---
active: true
phase: "done"
gate: ""
iteration: 5
max_iterations: 30
max_retries: 3
retry_count: 0
mode: "single"
plan_mode: ""
brief_file: "/some/path/002-db-models.md"
next_task: ""
auto_approve: true
knowledge_extracted: "skipped"
task_dir: ""
session_id: test-session
started_at: "2026-01-01T00:00:00Z"
---
## 变更日志
`);

      const stdinJson = `{"cwd":"${tmpDir}","session_id":"test-session"}`;
      const output = runStopHook(tmpDir, stdinJson);
      assert.ok(output.includes('"block"'), `should block for project QA: ${output}`);
      // New state should be in requirements dir via active pointer
      const state = readStateFile(tmpDir);
      assert.ok(state, 'project-qa state file should exist');
      assert.equal(getField(state, 'mode'), 'project-qa');
      assert.equal(getField(state, 'phase'), 'qa');
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
    it('is under 550 lines', () => {
      const content = fs.readFileSync(SKILL_MD, 'utf8');
      const lines = content.split('\n').length;
      assert.ok(lines <= 550, `SKILL.md should be under 550 lines, got ${lines}`);
    });

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

    it('has reference pointers for each phase', () => {
      const content = fs.readFileSync(SKILL_MD, 'utf8');
      assert.ok(content.includes('references/implement-phase.md'), 'should reference implement phase');
      assert.ok(content.includes('references/qa-phase.md'), 'should reference qa phase');
      assert.ok(content.includes('references/auto-fix-phase.md'), 'should reference auto-fix phase');
      assert.ok(content.includes('references/merge-phase.md'), 'should reference merge phase');
    });

    it('has auto-chain and auto-approve sections', () => {
      const content = fs.readFileSync(SKILL_MD, 'utf8');
      assert.ok(content.includes('next_task'), 'should document next_task field');
      assert.ok(content.includes('auto_approve'), 'should document auto_approve field');
      assert.ok(content.includes('Auto-Approve'), 'should have Auto-Approve section');
    });

    it('documents project-qa mode', () => {
      const content = fs.readFileSync(SKILL_MD, 'utf8');
      assert.ok(content.includes('project-qa'), 'should mention project-qa mode');
    });

    it('has mode and brief_file in frontmatter docs', () => {
      const content = fs.readFileSync(SKILL_MD, 'utf8');
      assert.ok(content.includes('mode: ""'), 'frontmatter docs should include mode field');
      assert.ok(content.includes('brief_file: ""'), 'frontmatter docs should include brief_file field');
      assert.ok(content.includes('plan_mode: ""'), 'frontmatter docs should include plan_mode field');
      assert.ok(content.includes('task_dir: ""'), 'frontmatter docs should include task_dir field');
    });

    it('has deep design mode section', () => {
      const content = fs.readFileSync(SKILL_MD, 'utf8');
      assert.ok(content.includes('Deep Design'), 'SKILL.md should have Deep Design section');
      assert.ok(content.includes('deep-design-guide.md'), 'should reference deep design guide');
      assert.ok(content.includes('visual-companion-guide.md'), 'should reference visual companion guide');
    });

    it('has artifact archiving in merge phase', () => {
      const content = fs.readFileSync(SKILL_MD, 'utf8');
      assert.ok(content.includes('产出物归档'), 'merge phase should have artifact archiving');
      assert.ok(content.includes('TASK_DIR'), 'should reference TASK_DIR');
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

    it('documents auto-chain mechanism', () => {
      const content = fs.readFileSync(PROJECT_SKILL_MD, 'utf8');
      assert.ok(content.includes('Auto-Chain'), 'should have Auto-Chain section');
      assert.ok(content.includes('next_task'), 'should mention next_task field');
      assert.ok(content.includes('auto_approve'), 'should mention auto_approve');
    });

    it('documents automatic orchestration principle', () => {
      const content = fs.readFileSync(PROJECT_SKILL_MD, 'utf8');
      assert.ok(content.includes('自动编排'), 'should have automatic orchestration principle');
    });
  });
});
