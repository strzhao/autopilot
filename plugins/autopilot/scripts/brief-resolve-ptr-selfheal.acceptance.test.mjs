/**
 * brief 三级解析 + 指针自愈 + 释放点闭集 — Real-Process Acceptance Tests（红队）
 * ============================================================================
 * 任务：20261018-开始实现（state.md ## 验收场景 冻结谓词的代码化）
 *
 * 验收依据：仅 state.md `## 目标` / `## 设计文档` / `## 验收场景`（红队信息隔离，
 * 未读 lib.sh / stop-hook.sh / setup.sh 任何实现内容）。
 *
 * 被测契约（设计文档四组件）：
 *   组件 1  lib.sh resolve_task_file(dag_file, task_id)：brief 三级解析
 *           ①绝对路径原样 → ②$PROJECT_ROOT/.autopilot/project/<brief> →
 *           ③$PROJECT_ROOT/<brief> → 全未命中返回空串；空 brief 回退
 *           .autopilot/project/tasks/<id>.md（v3.54.0 兼容）
 *   组件 2  stop-hook Case 0.5/Case 1 brief 未命中 → block 自修 JSON（reason 含
 *           brief/next_task 实值 + 修复指引 + 逃生口），【禁止】rm active 指针
 *   组件 3  init_paths 指针自愈（缺失/空/悬空 → 扫同基目录 active:true ∧
 *           phase!=done 候选，mtime 最新，重建 ptr + 可见化；不跨界收养）+
 *           7 处释放点 rm 前先 set_field active:false 落盘
 *   组件 4  brief-auto-approve AC-P3 夹具补三字段（e2e_status/leftover_critical/
 *           unexecuted_core_paths）后全绿
 *
 * 场景 → 用例映射（谓词编号 = state.md ## 验收场景）：
 *   S01  三级解析第 1 级（绝对路径）        → T01（P1 Case0.5态/P2 Case1态/P3/P4 反证）
 *   S02  第 2 级 .autopilot/project/<b>    → T02
 *   S03  第 3 级 $PROJECT_ROOT/<b>         → T03
 *   S04  Case 0.5 未命中 block 自修        → T04（+FIXTURE_BIND 注记）
 *   S05  Case 1 未命中 block 自修          → T05（无 brief 字段形态，④回退也未命中）
 *   S06  指针缺失自愈 + 可见化             → T06
 *   S07  空/悬空指针自愈                   → T07
 *   S08  多候选取 mtime 最新（双向换位）   → T08
 *   S09  无合格候选不重建                  → T09
 *   S10  有效指针幂等不改写                → T10
 *   S11  释放点 active:false 落盘（P1-P8） → T11
 *   S12  AC-P3 夹具三字段 + 全绿           → T12（P1 fs-grep 在配套 .sh）
 *   S13  全量基线绿 / 新增行为用例在位     → T12 备注（P1/P2 在配套 .sh）
 *   S14  §7 max_iterations 终止不复活      → T14
 *   S15  cancel 显式取消不被自愈撤销       → T15
 *   S16  worktree 拓扑自愈 + 不跨界        → T16
 *
 * 驱动：node:child_process spawnSync(bash stop-hook.sh / setup.sh, stdin=stop 事件
 * JSON, cwd=$SANDBOX)——mktemp 沙箱仓，每用例独立。artifact 目录
 * /tmp/autopilot-artifacts/（可用 AUTOPILOT_ARTIFACT_DIR 覆盖），每谓词落
 * s<NN>-p<M>.out 与冻结谓词 artifact 名对齐，供 QA 求值回放。
 *
 * 夹具校准记录（黑盒探针，2026-10-18）：
 *   - Case 1 auto-chain 入口实测打通：state(phase=done, knowledge_extracted=true,
 *     next_task=<下一任务 id>) + dag(当前任务 done, 下一任务 pending) → 命中推进 /
 *     未命中 block 自修（指针保留）。
 *   - project-qa 完成（:562）= 全项目集成 QA 链：ALL_DONE → hook 启动 QA 任务
 *     （ptr 重指不自毁）→ QA 任务完成 → 释放（active:false + ptr 删）。S11-P5/P6
 *     按全链两跑驱动。
 *   - :610 FIRST_READY 空（dag 全 in-progress/blocked）→ 纯释放分支，S11-P7 单跑驱动。
 *   - FIXTURE_BIND(QA)：Case 0.5 专态（project-design-complete 时刻）的黑盒触发夹具
 *     未独立探明——S01/S02/S03-P1 以同一 resolve 契约的 auto-chain 可达入口承载
 *     （组件 1 下沉为同一函数），断言保持硬；冻结场景预告「触发夹具与 slug 名由 QA
 *     求值时绑定」，如 QA 有 Case 0.5 专态夹具可替换 builder，断言不变。
 *
 * Run: node --test plugins/autopilot/scripts/brief-resolve-ptr-selfheal.acceptance.test.mjs
 * 退出码：有任一断言失败 → 非零（node:test 默认）。
 * 当前基线：蓝队并行落地中，红绿分布以实测为准（2026-10-18 实测 20/20 绿；
 * 配套 .sh 的 S13-P1 全量套件红 = 套件既有成员失败，归属见红队报告）。
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  mkdtempSync, writeFileSync, readFileSync, mkdirSync, rmSync,
  existsSync, utimesSync, readdirSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// ---------------------------------------------------------------------------
// 定位插件 scripts 目录（staging / target 双位置通用：向上找 .git）
// ---------------------------------------------------------------------------
const __dirname = dirname(fileURLToPath(import.meta.url));
function findScriptsDir() {
  let dir = __dirname;
  while (dir && dir !== '/') {
    if (existsSync(join(dir, '.git'))) {
      return join(dir, 'plugins', 'autopilot', 'scripts');
    }
    dir = dirname(dir);
  }
  throw new Error('cannot locate repo root (.git) from ' + __dirname);
}
const SCRIPTS_DIR = findScriptsDir();
const STOP_HOOK = join(SCRIPTS_DIR, 'stop-hook.sh');
const SETUP_SH = join(SCRIPTS_DIR, 'setup.sh');
const BRIEF_AA_TEST = join(SCRIPTS_DIR, 'brief-auto-approve.acceptance.test.sh');

// ---------------------------------------------------------------------------
// artifact 目录（冻结场景约定：/tmp/autopilot-artifacts/）
// ---------------------------------------------------------------------------
const ART_DIR = process.env.AUTOPILOT_ARTIFACT_DIR || '/tmp/autopilot-artifacts';
function writeArtifact(name, content) {
  try {
    mkdirSync(ART_DIR, { recursive: true });
    writeFileSync(join(ART_DIR, name), String(content), 'utf8');
  } catch { /* artifact 落盘失败不影响断言 */ }
}

// ---------------------------------------------------------------------------
// 临时目录管理
// ---------------------------------------------------------------------------
const _tempDirs = [];
process.on('exit', () => {
  for (const d of _tempDirs) {
    try { rmSync(d, { recursive: true, force: true }); } catch { /* ignore */ }
  }
});
function makeTempDir(tag) {
  const d = mkdtempSync(join(tmpdir(), `ptr-selfheal-${tag}-`));
  _tempDirs.push(d);
  return d;
}

// ---------------------------------------------------------------------------
// 沙箱仓构造
// ---------------------------------------------------------------------------
const SID = 's1'; // 全套固定 session id，与 state.md frontmatter 匹配

function initRepo(dir) {
  const r = spawnSync('git', ['init', '-q', '-b', 'main'], { cwd: dir });
  assert.equal(r.status, 0, `git init failed: ${r.stderr}`);
  spawnSync('git', ['config', 'user.email', 't@t'], { cwd: dir });
  spawnSync('git', ['config', 'user.name', 'T'], { cwd: dir });
}

/** 写 state.md（字段集 = create_brief_state_file 实测生成形态） */
function writeState(repo, slug, ov = {}) {
  const o = {
    active: 'true', phase: 'implement', gate: '', iteration: 3,
    max_iterations: 30, max_retries: 3, retry_count: 0, mode: 'single',
    plan_mode: '', brief_file: '', next_task: '', auto_approve: 'true',
    knowledge_extracted: '', task_dir: join(repo, '.autopilot', 'runtime', 'requirements', slug),
    session_id: SID, started_at: '2026-10-18T00:00:00Z',
    contract_required: 'false', html_review: 'false', ...ov,
  };
  const dir = join(repo, '.autopilot', 'runtime', 'requirements', slug);
  mkdirSync(dir, { recursive: true });
  const fm = Object.entries(o).map(([k, v]) => `${k}: "${v}"`).join('\n');
  writeFileSync(join(dir, 'state.md'), `---\n${fm}\n---\n\n## 目标\nfixture ${slug}\n`);
  return join(dir, 'state.md');
}

function stateFile(repo, slug) {
  return join(repo, '.autopilot', 'runtime', 'requirements', slug, 'state.md');
}
function ptrPath(repo) {
  return join(repo, '.autopilot', 'runtime', 'active.ptr');
}
function writePtr(repo, slug) {
  mkdirSync(dirname(ptrPath(repo)), { recursive: true });
  writeFileSync(ptrPath(repo), slug, 'utf8');
}
function readPtr(repo) {
  // trim：自愈重建写入的 ptr 可能带尾部换行（冻结谓词语义 = 内容 contains slug）
  return readFileSync(ptrPath(repo), 'utf8').trim();
}
function ptrExists(repo) {
  return existsSync(ptrPath(repo));
}
/** worktree 会话形态的 ptr / requirements 基目录 */
function wtSessionsDir(repo, wtName) {
  return join(repo, '.autopilot', 'runtime', 'sessions', wtName);
}
function wtPtr(repo, wtName) {
  return join(wtSessionsDir(repo, wtName), 'active.ptr');
}
function wtStateFile(repo, wtName, slug) {
  return join(wtSessionsDir(repo, wtName), 'requirements', slug, 'state.md');
}
function writeWtState(wtRoot, wtName, slug, ov = {}) {
  const dir = join(wtRoot, '.autopilot', 'runtime', 'sessions', wtName, 'requirements', slug);
  mkdirSync(dir, { recursive: true });
  const o = {
    active: 'true', phase: 'implement', gate: '', iteration: 3,
    max_iterations: 30, max_retries: 3, retry_count: 0, mode: 'single',
    plan_mode: '', brief_file: '', next_task: '', auto_approve: 'true',
    knowledge_extracted: '', task_dir: dir, session_id: SID,
    started_at: '2026-10-18T00:00:00Z', contract_required: 'false',
    html_review: 'false', ...ov,
  };
  const fm = Object.entries(o).map(([k, v]) => `${k}: "${v}"`).join('\n');
  writeFileSync(join(dir, 'state.md'), `---\n${fm}\n---\n\n## 目标\nwt fixture ${slug}\n`);
  return join(dir, 'state.md');
}

function writeDag(repo, yaml) {
  const d = join(repo, '.autopilot', 'project');
  mkdirSync(join(d, 'tasks'), { recursive: true });
  writeFileSync(join(d, 'dag.yaml'), yaml);
  return join(d, 'dag.yaml');
}

/** frontmatter 取首键（容忍重复键，strip 引号）——与 load_state/get_field 契约同容错 */
function fmGet(file, field) {
  if (!existsSync(file)) return null;
  const m = readFileSync(file, 'utf8')
    .split('\n')
    .find((l) => l.startsWith(`${field}:`));
  if (m === undefined) return null;
  return m.slice(field.length + 1).trim().replace(/^"(.*)"$/, '$1');
}

// transcript：commit-agent 已完成（pending-gate B 同款形态，过 §7.5 pending 门）
function completedTranscript(dir) {
  const p = join(dir, 't-done.jsonl');
  const lines = [
    JSON.stringify({
      isSidechain: false, type: 'assistant',
      message: { role: 'assistant', content: [{ type: 'tool_use', id: 'toolu_mc_001', name: 'Agent', input: { prompt: 'commit', options: {} } }] },
    }),
    JSON.stringify({
      isSidechain: false, type: 'user',
      message: { role: 'user', content: [{ type: 'tool_result', tool_use_id: 'toolu_mc_001', content: [{ type: 'text', text: 'Async agent launched successfully.\nagentId: agent-commit-abc' }] }] },
      toolUseResult: { isAsync: true, status: 'async_launched', agentId: 'agent-commit-abc' },
    }),
    JSON.stringify({
      type: 'queue-operation', operation: 'enqueue',
      content: '<task-notification>\n<task-id>agent-commit-abc</task-id>\n<tool-use-id>toolu_mc_001</tool-use-id>\n<status>completed</status>\n<summary>done</summary>\n</task-notification>',
    }),
  ];
  writeFileSync(p, lines.join('\n') + '\n');
  return p;
}
function emptyTranscript(dir) {
  const p = join(dir, 't-empty.jsonl');
  writeFileSync(p, '');
  return p;
}

// ---------------------------------------------------------------------------
// 核心驱动：spawn stop-hook.sh / setup.sh
// ---------------------------------------------------------------------------
function runHook(cwd, artifact, transcriptPath) {
  const tp = transcriptPath || emptyTranscript(cwd);
  const r = spawnSync(
    'bash',
    [STOP_HOOK],
    {
      cwd,
      input: JSON.stringify({ session_id: SID, transcript_path: tp, cwd }),
      encoding: 'utf8',
      timeout: 30000,
    }
  );
  if (artifact) {
    writeArtifact(artifact, `exit=${r.status}\n--- stdout ---\n${r.stdout}\n--- stderr ---\n${r.stderr}`);
  }
  return r;
}

function runSetup(args, cwd, artifact) {
  const r = spawnSync('bash', [SETUP_SH, ...args], { cwd, encoding: 'utf8', timeout: 120000 });
  if (artifact) {
    writeArtifact(artifact, `exit=${r.status}\n--- stdout ---\n${r.stdout}\n--- stderr ---\n${r.stderr}`);
  }
  return r;
}

/** 从 stdout 提取首个 JSON 对象；空/非 JSON → null */
function parseHookJson(stdout) {
  const t = (stdout || '').trim();
  if (!t) return null;
  try { return JSON.parse(t); } catch { /* fallthrough */ }
  const s = t.indexOf('{');
  const e = t.lastIndexOf('}');
  if (s >= 0 && e > s) {
    try { return JSON.parse(t.slice(s, e + 1)); } catch { return null; }
  }
  return null;
}

function ctx(r) {
  return `exit=${r.status} stdout=${(r.stdout || '').slice(0, 400)} stderr=${(r.stderr || '').slice(0, 400)}`;
}

// ===========================================================================
// Case 1 auto-chain 夹具（黑盒校准打通的唯一 brief 查找真实入口）：
//   state(当前任务, phase=done, knowledge_extracted=true, next_task=T5) +
//   dag(T4 done → T5 pending, brief=<形态变体>) + ptr→T4 + commit 完成 transcript
// 返回 { repo, briefAbs }
// ===========================================================================
function makeAutoChainFixture(tag, briefYamlValue, briefFileTargets) {
  const repo = makeTempDir(tag);
  initRepo(repo);
  const tdir = join(repo, '.autopilot', 'project', 'tasks');
  mkdirSync(tdir, { recursive: true });
  writeFileSync(join(tdir, 'T4.md'), '---\nid: T4\ndepends_on: []\n---\n# T4\n');
  for (const [rel, content] of Object.entries(briefFileTargets || {})) {
    const p = join(repo, rel);
    mkdirSync(dirname(p), { recursive: true });
    writeFileSync(p, content);
  }
  const dagTasks = [
    'tasks:',
    '  - id: T4',
    '    title: current done task',
    '    status: done',
    '    depends_on: []',
    '  - id: T5',
    '    title: next task',
  ];
  if (briefYamlValue !== null) {
    dagTasks.push(`    brief: ${briefYamlValue}`);
  }
  dagTasks.push('    status: pending', '    depends_on: [T4]');
  writeDag(repo, dagTasks.join('\n') + '\n');
  writeState(repo, 'T4', {
    phase: 'done', knowledge_extracted: 'true', next_task: 'T5',
    mode: 'single', contract_required: 'true',
    brief_file: join(tdir, 'T4.md'),
  });
  writePtr(repo, 'T4');
  return repo;
}

/** 命中共通断言：exit 0 + stdout 合法 JSON + 非 brief-not-found block + 推进发生 */
function assertAutoChainHit(r, repo, label, artifact) {
  assert.equal(r.status, 0, `${label}: hook 应 exit 0，实际 ${ctx(r)}`);
  const json = parseHookJson(r.stdout);
  assert.ok(json, `${label}: stdout 应为合法 JSON，实际 ${ctx(r)}`);
  const isBriefNotFoundBlock =
    json && json.decision === 'block' && /未解析到|brief-not-found|auto-chain 中断/.test(json.reason || '');
  assert.ok(!isBriefNotFoundBlock, `${label}: 不应出现 brief-not-found block，实际 reason=${(json && json.reason || '').slice(0, 200)}`);
  // Mutation-kill（No-op）：未推进的 no-op 实现同样能输出非 miss JSON——
  // 加推进副作用断言：ptr 必须切到含 T5 的新任务
  assert.ok(ptrExists(repo), `${label}: 推进后 active.ptr 应存在，实际已丢失 ${ctx(r)}`);
  assert.match(readPtr(repo), /T5/, `${label}: ptr 应切到 T5 新任务，实际 '${readPtr(repo)}'`);
  const reqs = join(repo, '.autopilot', 'runtime', 'requirements');
  const reqList = existsSync(reqs) ? readdirSync(reqs) : [];
  assert.ok(
    reqList.some((n) => n.includes('T5')),
    `${label}: 推进应创建 T5 新任务目录，实际 requirements/=${JSON.stringify(reqList)}`
  );
  if (artifact) writeArtifact(artifact, ctx(r));
}

// ===========================================================================
// T01 ｜ 场景 1 ｜ brief 三级解析第 1 级：绝对路径原样命中
// ===========================================================================
test('S01: brief 绝对路径命中（第 1 级）', () => {
  // P1 [real-process] Case 0.5 态 → 命中第 1 级，exit==0 且 stdout 为 JSON 且非 brief-not-found block
  // FIXTURE_BIND(QA)：Case 0.5 专态（project-design-complete 时刻）触发夹具由 QA 求值时绑定；
  // 此处以已打通的 auto-chain brief 查找入口承载同一 resolve 契约（组件 1 下沉为同一函数），
  // 断言保持硬：红 = 夹具未绑定或蓝队未实现。
  {
    const briefAbs = join(makeTempDir('s01p1-brief'), 'm1x.md');
    writeFileSync(briefAbs, '# abs brief content\n');
    const repo = makeAutoChainFixture('s01p1', briefAbs, {});
    const r = runHook(repo, 's01-p1.out', completedTranscript(repo));
    assertAutoChainHit(r, repo, 'S01-P1(绝对路径)', 's01-p1.out');
  }

  // P2 [real-process] 同输入 Case 1 态 → 命中正常输出
  {
    const briefAbs = join(makeTempDir('s01p2-brief'), 'm1x.md');
    writeFileSync(briefAbs, '# abs brief content\n');
    const repo = makeAutoChainFixture('s01p2', briefAbs, {});
    const r = runHook(repo, 's01-p2.out', completedTranscript(repo));
    assertAutoChainHit(r, repo, 'S01-P2(Case1态绝对路径)', 's01-p2.out');

    // P3 [det-machine] P2 结束后 active.ptr 仍存在
    assert.ok(ptrExists(repo), 'S01-P3: P2 结束后 active.ptr 必须仍存在（命中路径不得自毁）');
  }

  // P4 [real-process] 反证：绝对路径文件移走后重跑 → brief-not-found block
  {
    const briefAbs = join(makeTempDir('s01p4-brief'), 'm1x.md');
    writeFileSync(briefAbs, '# abs brief content\n');
    const repo = makeAutoChainFixture('s01p4', briefAbs, {});
    rmSync(briefAbs); // 移走绝对路径文件 → 三级全未命中
    const r = runHook(repo, 's01-p4.out', completedTranscript(repo));
    assert.equal(r.status, 0, `S01-P4: 应 exit 0，实际 ${ctx(r)}`);
    const json = parseHookJson(r.stdout);
    assert.ok(json, `S01-P4: stdout 应为合法 JSON block，实际 ${ctx(r)}`);
    assert.equal(json.decision, 'block', `S01-P4: 反证应出现 decision=block，实际 ${JSON.stringify(json).slice(0, 200)}`);
    assert.ok(typeof json.reason === 'string' && json.reason.length > 0, 'S01-P4: block reason 非空');
  }
});

// ===========================================================================
// T02 ｜ 场景 2 ｜ 第 2 级 $PROJECT_ROOT/.autopilot/project/<brief> 命中
// ===========================================================================
test('S02: brief 相对名仅存于 .autopilot/project/ 下（第 2 级）', () => {
  // P1 [real-process] Case 0.5 态（FIXTURE_BIND(QA) 同 T01-P1）
  {
    const repo = makeAutoChainFixture('s02p1', 'proj-only-brief.md', {
      '.autopilot/project/proj-only-brief.md': '# proj-only brief\n',
    });
    const r = runHook(repo, 's02-p1.out', completedTranscript(repo));
    assertAutoChainHit(r, repo, 'S02-P1(第2级)', 's02-p1.out');
  }

  // P2 [real-process] Case 1 态命中第 2 级
  {
    const repo = makeAutoChainFixture('s02p2', 'proj-only-brief.md', {
      '.autopilot/project/proj-only-brief.md': '# proj-only brief\n',
    });
    const r = runHook(repo, 's02-p2.out', completedTranscript(repo));
    assertAutoChainHit(r, repo, 'S02-P2(第2级)', 's02-p2.out');

    // P3 [det-machine] active.ptr 保持存在
    assert.ok(ptrExists(repo), 'S02-P3: active.ptr 应保持存在');
  }
});

// ===========================================================================
// T03 ｜ 场景 3 ｜ 第 3 级回落 $PROJECT_ROOT/<brief> 命中（相对名仅存于仓根）
// ===========================================================================
test('S03: brief 相对名仅存于仓根（第 3 级）', () => {
  // P1 [real-process] Case 0.5 态（FIXTURE_BIND(QA) 同 T01-P1）
  {
    const repo = makeAutoChainFixture('s03p1', 'root-only-brief.md', {
      'root-only-brief.md': '# root-only brief\n',
    });
    const r = runHook(repo, 's03-p1.out', completedTranscript(repo));
    assertAutoChainHit(r, repo, 'S03-P1(第3级)', 's03-p1.out');
  }

  // P2 [real-process] Case 1 态命中第 3 级
  {
    const repo = makeAutoChainFixture('s03p2', 'root-only-brief.md', {
      'root-only-brief.md': '# root-only brief\n',
    });
    const r = runHook(repo, 's03-p2.out', completedTranscript(repo));
    assertAutoChainHit(r, repo, 'S03-P2(第3级)', 's03-p2.out');

    // P3 [det-machine] active.ptr 保持存在
    assert.ok(ptrExists(repo), 'S03-P3: active.ptr 应保持存在');
  }
});

// ===========================================================================
// T04 ｜ 场景 4 ｜ brief 三级全未命中：block 自修，禁止自毁
// ===========================================================================
test('S04: brief 全未命中 → block 自修（moonwell 短形态缺失，禁止自毁）', () => {
  // 夹具：T5 brief=tasks/m4-absent.md 短形态（harmony-space 事故形态），全盘无此文件
  const repo = makeAutoChainFixture('s04', 'tasks/m4-absent.md', {});
  const r = runHook(repo, 's04-p1.out', completedTranscript(repo));

  // P1 [real-process] exit==0 且 stdout JSON decision=="block" 且 reason 非空
  assert.equal(r.status, 0, `S04-P1: 应 exit 0，实际 ${ctx(r)}`);
  const json = parseHookJson(r.stdout);
  assert.ok(json, `S04-P1: stdout 应为合法 JSON，实际 ${ctx(r)}`);
  assert.equal(json.decision, 'block', `S04-P1: decision 应为 block，实际 ${JSON.stringify(json).slice(0, 200)}`);
  assert.ok(typeof json.reason === 'string' && json.reason.length > 0, 'S04-P1: reason 非空');

  // P2 [det-machine] reason 含自修要素：contains "brief" && contains "next_task"（修复指引+逃生口）
  assert.match(json.reason, /brief/, 'S04-P2: reason 应含 brief（报 brief 原值实态）');
  assert.match(json.reason, /next_task/, 'S04-P2: reason 应含 next_task（报 next_task 实值 + 逃生口指引）');

  // P3 [det-machine] block 发生时 active.ptr 保持存在（negate：旧 rm 自毁不得发生）
  assert.ok(ptrExists(repo), `S04-P3: block 自修时 active.ptr 必须保留（旧 rm 自毁禁止），实际指针已丢失 ${ctx(r)}`);
  assert.equal(readPtr(repo), 'T4', `S04-P3: 指针应仍指向原任务 T4，实际 '${readPtr(repo)}'`);
});

// ===========================================================================
// T05 ｜ 场景 5 ｜ Case 1 分支 brief 未命中：同款 block 自修
//（无 brief 字段形态 → ④回退 .autopilot/project/tasks/T5.md 也未命中）
// ===========================================================================
test('S05: Case 1 无 brief 字段且回退未命中 → 同款 block 自修', () => {
  const repo = makeAutoChainFixture('s05', null, {}); // T5 无 brief 字段
  const r = runHook(repo, 's05-p1.out', completedTranscript(repo));

  // P1 [real-process] exit==0 block JSON reason 非空
  assert.equal(r.status, 0, `S05-P1: 应 exit 0，实际 ${ctx(r)}`);
  const json = parseHookJson(r.stdout);
  assert.ok(json, `S05-P1: stdout 应为合法 JSON，实际 ${ctx(r)}`);
  assert.equal(json.decision, 'block', `S05-P1: decision 应为 block，实际 ${JSON.stringify(json).slice(0, 200)}`);
  assert.ok(typeof json.reason === 'string' && json.reason.length > 0, 'S05-P1: reason 非空');

  // P2 [det-machine] reason 要素：contains "brief" && contains "next_task"
  assert.match(json.reason, /brief/, 'S05-P2: reason 应含 brief');
  assert.match(json.reason, /next_task/, 'S05-P2: reason 应含 next_task');

  // P3 [det-machine] 指针保留
  assert.ok(ptrExists(repo), `S05-P3: active.ptr 必须保留，实际丢失 ${ctx(r)}`);
  assert.equal(readPtr(repo), 'T4', `S05-P3: 指针应仍指向 T4，实际 '${readPtr(repo)}'`);
});

// ===========================================================================
// T06 ｜ 场景 6 ｜ 指针缺失自愈重建 + 可见化（唯一合格候选 slugA）
// ===========================================================================
test('S06: ptr 缺失 → 自愈重建指向唯一合格候选 + 事件可见', () => {
  const repo = makeTempDir('s06');
  initRepo(repo);
  const sf = writeState(repo, 'autoheal-a', { phase: 'implement', active: 'true' });
  assert.ok(existsSync(sf));
  // ptr 不存在（不写 active.ptr）

  const r = runHook(repo, 's06-p2.out');

  // P1 [det-machine] ptr 重建且内容 contains slugA
  assert.ok(ptrExists(repo), `S06-P1: active.ptr 应被自愈重建，实际不存在 ${ctx(r)}`);
  assert.equal(readPtr(repo), 'autoheal-a', `S06-P1: ptr 应重建为 autoheal-a，实际 '${readPtr(repo)}'`);

  // P2 [real-process] 自愈事件可见：stdout JSON systemMessage 非空 或 stderr 非空
  const json = parseHookJson(r.stdout);
  const sysMsg = json && json.systemMessage ? String(json.systemMessage) : '';
  const visible = sysMsg.length > 0 || (r.stderr || '').trim().length > 0;
  assert.ok(visible, `S06-P2: 自愈事件应可见（systemMessage 或 stderr 非空），实际 ${ctx(r)}`);
  // 设计文本锚（防普通 iteration systemMessage 顶替自愈报警的 no-op 突变存活）：
  // 可见化文案 = 「指针丢失已自愈，接管 <slug>」族 → 必须含 自愈/接管 字样
  assert.match(
    sysMsg + (r.stderr || ''),
    /自愈|接管/,
    `S06-P2+: 可见化应含「自愈/接管」字样（设计文本锚），实际 systemMessage='${sysMsg.slice(0, 120)}' stderr='${(r.stderr || '').slice(0, 120)}'`
  );

  // P3 [real-process] 自愈后 hook 继续产出合法决策 JSON 而非静默退出
  assert.equal(r.status, 0, `S06-P3: 应 exit 0，实际 ${ctx(r)}`);
  assert.ok(json, `S06-P3: 自愈后应产出合法决策 JSON 而非静默，实际 stdout=${(r.stdout || '').slice(0, 200)}`);
});

// ===========================================================================
// T07 ｜ 场景 7 ｜ 指针空/悬空自愈（A：0 字节 → slugC；B：悬空 → slugD）
// ===========================================================================
test('S07: ptr 空/悬空 → 自愈重建', () => {
  // A：ptr 0 字节 + 合格候选 slugC
  {
    const repo = makeTempDir('s07a');
    initRepo(repo);
    writeState(repo, 'autoheal-c', { phase: 'implement' });
    mkdirSync(dirname(ptrPath(repo)), { recursive: true });
    writeFileSync(ptrPath(repo), '', 'utf8'); // 0 字节
    const r = runHook(repo, 's07-p1.out');
    assert.equal(readPtr(repo), 'autoheal-c', `S07-P1: 0 字节 ptr 应重建为 autoheal-c，实际 '${readPtr(repo)}' ${ctx(r)}`);
  }

  // B：ptr 悬空（指向不存在目录）+ 合格候选 slugD
  {
    const repo = makeTempDir('s07b');
    initRepo(repo);
    writeState(repo, 'autoheal-d', { phase: 'implement' });
    writePtr(repo, 'ghost-dangling-slug'); // requirements/ghost-dangling-slug/ 不存在
    const r = runHook(repo, 's07-p2.out');
    assert.equal(readPtr(repo), 'autoheal-d', `S07-P2: 悬空 ptr 应重建为 autoheal-d，实际 '${readPtr(repo)}' ${ctx(r)}`);
    assert.ok(!readPtr(repo).includes('ghost'), 'S07-P2: 重建后不得再含悬空引用');

    // P3 [real-process] 任一重建事件可见（systemMessage 或 stderr）
    const json = parseHookJson(r.stdout);
    const sysMsg = json && json.systemMessage ? String(json.systemMessage) : '';
    const visible = sysMsg.length > 0 || (r.stderr || '').trim().length > 0;
    assert.ok(visible, `S07-P3: 重建事件应可见，实际 ${ctx(r)}`);
    assert.match(sysMsg + (r.stderr || ''), /自愈|接管/, 'S07-P3+: 可见化应含「自愈/接管」字样（设计文本锚）');
  }
});

// ===========================================================================
// T08 ｜ 场景 8 ｜ 多候选取 mtime 最新（双向换位）
// ===========================================================================
test('S08: 多合格候选取 mtime 最新，mtime 反转则改指', () => {
  const repo = makeTempDir('s08');
  initRepo(repo);
  const sfA = writeState(repo, 'cand-a', { phase: 'implement' });
  const sfB = writeState(repo, 'cand-b', { phase: 'implement' });
  const now = Date.now();
  // P1: slugB mtime 较新 → ptr contains slugB 且 contains slugA==false
  utimesSync(sfB, new Date(now + 5000), new Date(now + 5000));
  utimesSync(sfA, new Date(now), new Date(now));
  let r = runHook(repo, 's08-p1.out');
  assert.ok(ptrExists(repo), `S08-P1: 应自愈重建 ptr，实际不存在 ${ctx(r)}`);
  assert.match(readPtr(repo), /cand-b/, `S08-P1: mtime 较新的 cand-b 应当选，实际 '${readPtr(repo)}'`);
  assert.ok(!readPtr(repo).includes('cand-a'), `S08-P1: 不得指向较旧 cand-a，实际 '${readPtr(repo)}'`);

  // P2 [real-process] touch 反转 mtime 重跑 → 改指 slugA
  //（重跑 = 再次模拟指针丢失：删 ptr 后反转 mtime，触发新一轮自愈）
  rmSync(ptrPath(repo));
  utimesSync(sfA, new Date(now + 15000), new Date(now + 15000));
  utimesSync(sfB, new Date(now + 5000), new Date(now + 5000));
  r = runHook(repo, 's08-p2.out');
  assert.ok(ptrExists(repo), `S08-P2: 反转后应重建 ptr，实际不存在 ${ctx(r)}`);
  assert.match(readPtr(repo), /cand-a/, `S08-P2: mtime 反转后应改指 cand-a，实际 '${readPtr(repo)}'`);
  assert.ok(!readPtr(repo).includes('cand-b'), `S08-P2: 不得再指 cand-b，实际 '${readPtr(repo)}'`);
});

// ===========================================================================
// T09 ｜ 场景 9 ｜ 无合格候选不重建（仅 active:false / phase:done）
// ===========================================================================
test('S09: 仅 done/inactive 候选 → ptr 保持不存在，无推进指令', () => {
  const repo = makeTempDir('s09');
  initRepo(repo);
  writeState(repo, 'done-cand', { phase: 'done', active: 'true', knowledge_extracted: 'true' });
  writeState(repo, 'inactive-cand', { phase: 'implement', active: 'false' });
  // ptr 不存在

  const r = runHook(repo, 's09-p2.out');

  // P1 [det-machine] ptr 保持不存在（negate：指向 done/inactive 的重建不得发生）
  assert.ok(!ptrExists(repo), `S09-P1: 无合格候选时不得重建 ptr，实际内容 '${ptrExists(repo) ? readPtr(repo) : '<absent>'}' ${ctx(r)}`);

  // P2 [real-process] stdout 不含任何 done 任务 slug 的推进指令
  assert.ok(!(r.stdout || '').includes('done-cand'), `S09-P2: stdout 不得含 done 任务推进指令，实际 ${ctx(r)}`);
  assert.ok(!(r.stdout || '').includes('inactive-cand'), `S09-P2: stdout 不得含 inactive 任务推进指令，实际 ${ctx(r)}`);
});

// ===========================================================================
// T10 ｜ 场景 10 ｜ 有效指针幂等不改写
// ===========================================================================
test('S10: 有效指针跑后内容 before==after（negate：重写不得发生）', () => {
  const repo = makeTempDir('s10');
  initRepo(repo);
  writeState(repo, 'valid-ptr-a', { phase: 'implement' });
  writePtr(repo, 'valid-ptr-a');
  const before = readPtr(repo);

  const r = runHook(repo, 's10-p1.out');

  assert.ok(ptrExists(repo), `S10-P1: 有效指针不得被删，实际丢失 ${ctx(r)}`);
  const after = readPtr(repo);
  assert.equal(after, before, `S10-P1: 有效指针内容必须幂等 before='${before}' after='${after}'`);
});

// ===========================================================================
// T11 ｜ 场景 11 ｜ done 释放多路径先置 active:false 再删指针
// ===========================================================================
test('S11-P1/P2: Case 2 else 释放（project 推进无 next_task）→ active:false + ptr 删', () => {
  // 夹具（黑盒校准 J2）：mode=project + phase=done + ke=true + dag(T4 done → T5 pending
  // brief 在) + next_task 空 → 走 else 释放而非推进
  const repo = makeTempDir('s11p1');
  initRepo(repo);
  const tdir = join(repo, '.autopilot', 'project', 'tasks');
  mkdirSync(tdir, { recursive: true });
  writeFileSync(join(tdir, 'T4.md'), '---\nid: T4\ndepends_on: []\n---\n# T4\n');
  writeFileSync(join(tdir, 'T5.md'), '---\nid: T5\ndepends_on: [T4]\n---\n# T5\n');
  writeDag(repo, [
    'tasks:',
    '  - id: T4',
    '    title: done task',
    '    status: done',
    '    depends_on: []',
    '  - id: T5',
    '    title: pending task',
    '    status: pending',
    '    depends_on: [T4]',
  ].join('\n') + '\n');
  writeState(repo, 'T4', {
    phase: 'done', knowledge_extracted: 'true', mode: 'project', next_task: '',
    brief_file: join(tdir, 'T4.md'), contract_required: 'false',
  });
  writePtr(repo, 'T4');

  const r = runHook(repo, 's11-p1.out', completedTranscript(repo));

  // P1 [real-process] 释放点正常完成输出（exit==0；stdout 非空时必须为合法 JSON）
  // CONTRACT_AMBIGUOUS: 冻结谓词「exit==0 stdout JSON」与释放点历史静默形态（exit 0 空
  // stdout）存在口径差——设计文档对释放点未声明新增输出要求，故此处硬断言取
  // 「exit==0 ∧ (stdout 空 ∨ 合法 JSON)」，绝不放行非 JSON 噪声输出。
  assert.equal(r.status, 0, `S11-P1: 释放点应 exit 0，实际 ${ctx(r)}`);
  if ((r.stdout || '').trim().length > 0) {
    assert.ok(parseHookJson(r.stdout), `S11-P1: stdout 非空时必须为合法 JSON，实际 ${ctx(r)}`);
  }

  // P2 [det-machine] 释放后 state.md active=="false" 且 active.ptr 不存在
  assert.equal(fmGet(stateFile(repo, 'T4'), 'active'), 'false',
    `S11-P2: 释放前必须先落盘 active:false，实际 '${fmGet(stateFile(repo, 'T4'), 'active')}' ${ctx(r)}`);
  assert.ok(!ptrExists(repo), `S11-P2: 释放后 active.ptr 应不存在，实际 '${ptrExists(repo) ? readPtr(repo) : '<absent>'}'`);
});

test('S11-P3/P4: Case 3 单任务完成释放 → active:false + ptr 删', () => {
  // 夹具（黑盒校准 D1）：无 dag + mode=single + phase=done + ke=true
  const repo = makeTempDir('s11p3');
  initRepo(repo);
  writeState(repo, 'solo-done', {
    phase: 'done', knowledge_extracted: 'true', mode: 'single', next_task: '',
  });
  writePtr(repo, 'solo-done');

  const r = runHook(repo, 's11-p3.out', completedTranscript(repo));

  assert.equal(r.status, 0, `S11-P3: 应 exit 0，实际 ${ctx(r)}`);
  if ((r.stdout || '').trim().length > 0) {
    assert.ok(parseHookJson(r.stdout), `S11-P3: stdout 非空时必须为合法 JSON，实际 ${ctx(r)}`);
  }
  assert.equal(fmGet(stateFile(repo, 'solo-done'), 'active'), 'false',
    `S11-P4: 单任务完成释放必须落盘 active:false，实际 '${fmGet(stateFile(repo, 'solo-done'), 'active')}'`);
  assert.ok(!ptrExists(repo), 'S11-P4: 释放后 active.ptr 应不存在');
});

test('S11-P5/P6: project-qa 完成释放（全项目QA 完成链）→ active:false + ptr 删', () => {
  // 夹具（黑盒校准 K1 全链）：项目模式全任务 done → stop-hook 启动全项目 QA 任务
  //（ptr 重指，不得自毁）→ QA 任务完成 → 释放（QA state active:false + ptr 删）。
  // 「project-qa 完成」= 全项目集成 QA 验证任务完成时刻。
  const repo = makeTempDir('s11p5');
  initRepo(repo);
  const tdir = join(repo, '.autopilot', 'project', 'tasks');
  mkdirSync(tdir, { recursive: true });
  writeFileSync(join(tdir, 'T1.md'), '---\nid: T1\ndepends_on: []\n---\n# T1\n');
  writeDag(repo, [
    'tasks:',
    '  - id: T1',
    '    title: last done task',
    '    status: done',
    '    depends_on: []',
  ].join('\n') + '\n');
  writeState(repo, 'T1', {
    phase: 'done', knowledge_extracted: 'true', mode: 'project', next_task: '',
    brief_file: join(tdir, 'T1.md'),
  });
  writePtr(repo, 'T1');

  // 第一跑：触发全项目 QA 启动
  const r1 = runHook(repo, 's11-p5.out', completedTranscript(repo));
  assert.equal(r1.status, 0, `S11-P5: 第一跑应 exit 0，实际 ${ctx(r1)}`);
  assert.ok(ptrExists(repo), `S11-P5: ALL_DONE 后 ptr 应重指全项目 QA 任务（不得自毁），实际丢失 ${ctx(r1)}`);
  const qaSlug = readPtr(repo);
  assert.ok(/QA/.test(qaSlug), `S11-P5: ptr 应指向全项目 QA 任务，实际 '${qaSlug}'`);
  const qaState = stateFile(repo, qaSlug);
  assert.ok(existsSync(qaState), `S11-P5: QA 任务 state 应已创建: ${qaState}`);

  // 第二跑：QA 任务完成 → 释放
  let qaFm = readFileSync(qaState, 'utf8');
  qaFm = qaFm.replace(/^phase:.*$/m, 'phase: "done"')
    .replace(/^knowledge_extracted:.*$/m, 'knowledge_extracted: "true"');
  writeFileSync(qaState, qaFm);
  const r2 = runHook(repo, 's11-p5.out', completedTranscript(repo));

  assert.equal(r2.status, 0, `S11-P5: 第二跑应 exit 0，实际 ${ctx(r2)}`);
  if ((r2.stdout || '').trim().length > 0) {
    assert.ok(parseHookJson(r2.stdout), `S11-P5: stdout 非空时必须为合法 JSON，实际 ${ctx(r2)}`);
  }
  // P6 [det-machine] 释放后 state.md active=="false" 且 active.ptr 不存在
  assert.equal(fmGet(qaState, 'active'), 'false',
    `S11-P6: project-qa 完成释放必须先落盘 active:false，实际 '${fmGet(qaState, 'active')}' ${ctx(r2)}`);
  assert.ok(!ptrExists(repo), `S11-P6: 释放后 active.ptr 应不存在，实际 '${ptrExists(repo) ? readPtr(repo) : '<absent>'}'`);
});

test('S11-P7: Case 0.5 外层 else（:610，FIRST_READY 空）释放 → active:false + ptr 删', () => {
  // 夹具（黑盒校准 K2）：mode=project + phase=done + ke=true + dag 全部 in-progress
  //（FIRST_READY 空，非 ALL_DONE → 不触发全项目 QA 启动，走纯释放分支）
  const repo = makeTempDir('s11p7');
  initRepo(repo);
  const tdir = join(repo, '.autopilot', 'project', 'tasks');
  mkdirSync(tdir, { recursive: true });
  writeFileSync(join(tdir, 'T1.md'), '---\nid: T1\ndepends_on: []\n---\n# T1\n');
  writeDag(repo, [
    'tasks:',
    '  - id: T1',
    '    title: stuck in progress',
    '    status: in-progress',
    '    depends_on: []',
  ].join('\n') + '\n');
  writeState(repo, 'T1', {
    phase: 'done', knowledge_extracted: 'true', mode: 'project', next_task: '',
    brief_file: join(tdir, 'T1.md'),
  });
  writePtr(repo, 'T1');

  const r = runHook(repo, 's11-p7.out', completedTranscript(repo));

  assert.equal(fmGet(stateFile(repo, 'T1'), 'active'), 'false',
    `S11-P7: :610 释放必须落盘 active:false，实际 '${fmGet(stateFile(repo, 'T1'), 'active')}' ${ctx(r)}`);
  assert.ok(!ptrExists(repo), `S11-P7: 释放后 active.ptr 应不存在，实际 '${ptrExists(repo) ? readPtr(repo) : '<absent>'}'`);
});

test('S11-P8: setup.sh init 清 done 残留（:374）→ 旧 state active:false + ptr 换新', () => {
  const repo = makeTempDir('s11p8');
  initRepo(repo);
  spawnSync('git', ['add', '-A'], { cwd: repo });
  spawnSync('git', ['commit', '-qm', 'init'], { cwd: repo });
  // done 残留任务 + 指针
  writeState(repo, 'done-leftover', {
    phase: 'done', knowledge_extracted: 'true', active: 'true',
  });
  writePtr(repo, 'done-leftover');

  const r = runSetup(['--single', '--fast', 'p8swap'], repo, 's11-p8.out');

  assert.equal(r.status, 0, `S11-P8: setup.sh init 应 exit 0，实际 ${ctx(r)}`);
  assert.equal(fmGet(stateFile(repo, 'done-leftover'), 'active'), 'false',
    `S11-P8: done 残留 state.md 必须落盘 active:false，实际 '${fmGet(stateFile(repo, 'done-leftover'), 'active')}'`);
  assert.ok(ptrExists(repo), 'S11-P8: active.ptr 应存在（被新任务指针替换）');
  const newPtr = readPtr(repo);
  assert.notEqual(newPtr, 'done-leftover', `S11-P8: ptr 必须被新任务替换，实际仍指 '${newPtr}'`);
  assert.match(newPtr, /p8swap/, `S11-P8: 新指针应指向新任务（含 p8swap），实际 '${newPtr}'`);
});

// ===========================================================================
// T12 ｜ 场景 12 ｜ AC-P3 夹具三字段补齐 + brief-auto-approve 全绿（P2）
//（P1 fs-grep 在配套 brief-resolve-ptr-selfheal-contract.acceptance.test.sh）
// ===========================================================================
test('S12-P2: brief-auto-approve 全量真跑 exit==0 含 PASS 无 FAIL', () => {
  const r = spawnSync('bash', [BRIEF_AA_TEST], { encoding: 'utf8', timeout: 120000 });
  writeArtifact('s12-p2.out', `exit=${r.status}\n--- stdout ---\n${r.stdout}\n--- stderr ---\n${r.stderr}`);
  assert.equal(r.status, 0, `S12-P2: brief-auto-approve 应全绿 exit 0，实际 exit=${r.status}\nstdout=${(r.stdout || '').slice(0, 600)}\nstderr=${(r.stderr || '').slice(0, 300)}`);
  assert.match(r.stdout, /PASS/, 'S12-P2: 输出应含 PASS');
  // 谓词「无 FAIL」语义 = 无断言级失败行 + 汇总计数 FAIL: 0
  //（`PASS: N    FAIL: 0` 为既有测试汇总格式，非失败标记）
  assert.doesNotMatch(r.stdout, /\n  FAIL  /, `S12-P2: 不得出现断言级 FAIL 行，实际 ${(r.stdout || '').slice(0, 600)}`);
  assert.match(r.stdout, /FAIL:\s*0/, `S12-P2: 汇总计数必须 FAIL: 0，实际 tail=${(r.stdout || '').slice(-200)}`);
});

// ===========================================================================
// T14 ｜ 场景 14 ｜ §7 max_iterations 终止不复活（安全阀不被自愈架空）
// ===========================================================================
test('S14: iteration>=max 触发 §7 终止 → active:false 落盘 + ptr 删 + 不复活', () => {
  const repo = makeTempDir('s14');
  initRepo(repo);
  writeState(repo, 'maxedit-task', {
    phase: 'implement', iteration: '30', max_iterations: '30', active: 'true',
  });
  writePtr(repo, 'maxedit-task');

  // P1 [det-machine] §7 触发 → state.md active=="false" 且 active.ptr 不存在
  const r1 = runHook(repo, 's14-p1.out');
  assert.equal(fmGet(stateFile(repo, 'maxedit-task'), 'active'), 'false',
    `S14-P1: §7 终止必须落盘 active:false（否则自愈会收养→秒杀架空安全阀），实际 '${fmGet(stateFile(repo, 'maxedit-task'), 'active')}' ${ctx(r1)}`);
  assert.ok(!ptrExists(repo), `S14-P1: §7 终止后 ptr 应不存在，实际 '${ptrExists(repo) ? readPtr(repo) : '<absent>'}'`);

  // P2 [real-process] 随后再跑 stop-hook → ptr 不重建 且 stdout 不含该任务推进指令
  const r2 = runHook(repo, 's14-p2.out');
  assert.ok(!ptrExists(repo), `S14-P2: 终止后自愈不得收养重建 ptr（negate：收养→秒杀循环），实际 '${ptrExists(repo) ? readPtr(repo) : '<absent>'}' ${ctx(r2)}`);
  assert.ok(!(r2.stdout || '').includes('maxedit-task'), `S14-P2: stdout 不得含该任务推进指令，实际 ${ctx(r2)}`);
});

// ===========================================================================
// T15 ｜ 场景 15 ｜ setup.sh cancel 显式取消不被自愈撤销
// ===========================================================================
test('S15: cancel → active:false 落盘 + ptr 删 + Stop 不复活', () => {
  const repo = makeTempDir('s15');
  initRepo(repo);
  writeState(repo, 'cancelled-task', { phase: 'implement', active: 'true' });
  writePtr(repo, 'cancelled-task');

  // P1 [det-machine] cancel 后 state.md active=="false" 且 active.ptr 不存在
  const rc = runSetup(['cancel'], repo, 's15-p1.out');
  assert.equal(rc.status, 0, `S15-P1: setup.sh cancel 应 exit 0，实际 ${ctx(rc)}`);
  assert.equal(fmGet(stateFile(repo, 'cancelled-task'), 'active'), 'false',
    `S15-P1: cancel 必须落盘 active:false（不落盘则被下次 Stop 静默撤销），实际 '${fmGet(stateFile(repo, 'cancelled-task'), 'active')}' ${ctx(rc)}`);
  assert.ok(!ptrExists(repo), `S15-P1: cancel 后 active.ptr 应不存在，实际 '${ptrExists(repo) ? readPtr(repo) : '<absent>'}'`);

  // P2 [real-process] cancel 后再跑 stop-hook → ptr 不重建（negate：静默撤销禁止）
  const r2 = runHook(repo, 's15-p2.out');
  assert.ok(!ptrExists(repo), `S15-P2: cancel 后 Stop 不得复活指针，实际 '${ptrExists(repo) ? readPtr(repo) : '<absent>'}' ${ctx(r2)}`);
  assert.ok(!(r2.stdout || '').includes('cancelled-task'), `S15-P2: stdout 不得含该任务推进指令，实际 ${ctx(r2)}`);
});

// ===========================================================================
// T16 ｜ 场景 16 ｜ worktree 拓扑自愈（同基目录 + 不跨界，双向）
// ===========================================================================
function makeWorktreeFixture(tag) {
  const mainRepo = makeTempDir(tag + '-main');
  initRepo(mainRepo);
  writeFileSync(join(mainRepo, 'f.txt'), 'x\n');
  spawnSync('git', ['add', '-A'], { cwd: mainRepo });
  spawnSync('git', ['commit', '-qm', 'init'], { cwd: mainRepo });
  const wt = join(mainRepo, 'wt-one');
  const r = spawnSync('git', ['worktree', 'add', wt, '-b', 'wt-one', '-q'], { cwd: mainRepo });
  assert.equal(r.status, 0, `git worktree add failed: ${r.stderr}`);
  return { mainRepo, wt };
}

test('S16-P1: worktree 删 ptr → 同基目录候选自愈重建', () => {
  const { mainRepo, wt } = makeWorktreeFixture('s16p1');
  // 主仓也放一个 active:true 任务（跨_BASE 噪声，验证同基目录语义）
  writeState(mainRepo, 'main-slug', { phase: 'implement' });
  writePtr(mainRepo, 'main-slug');
  // worktree 会话形态：sessions/<wt>/requirements/<slug> + sessions/<wt>/active.ptr
  writeWtState(wt, 'wt-one', 'wt-slug', { phase: 'implement' });
  mkdirSync(dirname(wtPtr(wt, 'wt-one')), { recursive: true });
  writeFileSync(wtPtr(wt, 'wt-one'), 'wt-slug');
  rmSync(wtPtr(wt, 'wt-one')); // 删 ptr → 触发自愈

  const r = runHook(wt, 's16-p1.out');

  assert.ok(existsSync(wtPtr(wt, 'wt-one')), `S16-P1: sessions/wt-one/active.ptr 应被自愈重建，实际不存在 ${ctx(r)}`);
  assert.equal(readFileSync(wtPtr(wt, 'wt-one'), 'utf8').trim(), 'wt-slug',
    `S16-P1: 应重建指向同基目录候选 wt-slug，实际 '${readFileSync(wtPtr(wt, 'wt-one'), 'utf8').trim()}'`);
});

test('S16-P2: 不跨界——worktree 不收养主仓任务，主仓不收养 worktree 任务（双向）', () => {
  // (a) worktree 不收养主仓 runtime/requirements/ 下 active:true 任务
  {
    const { mainRepo, wt } = makeWorktreeFixture('s16p2a');
    // 主仓合格任务（对 worktree 会话而言 = 跨界噪声）
    writeState(mainRepo, 'main-active', { phase: 'implement' });
    writePtr(mainRepo, 'main-active');
    // worktree 会话基目录只有不合格候选（done）
    writeWtState(wt, 'wt-one', 'wt-done-only', { phase: 'done', knowledge_extracted: 'true' });
    rmSync(wtPtr(wt, 'wt-one'), { force: true }); // 本就没有，防御式确保

    const r = runHook(wt, 's16-p2.out');

    const rebuilt = existsSync(wtPtr(wt, 'wt-one')) ? readFileSync(wtPtr(wt, 'wt-one'), 'utf8') : null;
    assert.ok(
      rebuilt === null || !rebuilt.includes('main-active'),
      `S16-P2a: worktree 会话不得收养主仓任务 main-active，实际 ptr='${rebuilt}' ${ctx(r)}`
    );
    assert.equal(
      existsSync(wtPtr(wt, 'wt-one')) && readFileSync(wtPtr(wt, 'wt-one'), 'utf8') === 'main-active',
      false,
      'S16-P2a: sessions ptr 指向 main-active = 跨界收养发生（禁止）'
    );
    // 主仓自己的指针不受波及
    assert.equal(readPtr(mainRepo), 'main-active', 'S16-P2a: 主仓指针不得被 worktree 会话的 hook 运行波及');
  }

  // (b) 主仓不收养 worktree 会话任务（反之亦然）
  {
    const { mainRepo, wt } = makeWorktreeFixture('s16p2b');
    // 主仓基目录只有不合格候选（done）
    writeState(mainRepo, 'main-done-only', { phase: 'done', knowledge_extracted: 'true' });
    // worktree 会话有合格任务且 ptr 完好（对主仓 = 跨界噪声）
    writeWtState(wt, 'wt-one', 'wt-active', { phase: 'implement' });
    mkdirSync(dirname(wtPtr(wt, 'wt-one')), { recursive: true });
    writeFileSync(wtPtr(wt, 'wt-one'), 'wt-active');
    // 主仓 ptr 删除 → 触发主仓侧自愈扫描
    rmSync(ptrPath(mainRepo), { force: true });

    const r = runHook(mainRepo, 's16-p2.out');

    const rebuilt = ptrExists(mainRepo) ? readPtr(mainRepo) : null;
    assert.ok(
      rebuilt === null || !rebuilt.includes('wt-active'),
      `S16-P2b: 主仓不得收养 worktree 会话任务 wt-active，实际 ptr='${rebuilt}' ${ctx(r)}`
    );
  }
});
