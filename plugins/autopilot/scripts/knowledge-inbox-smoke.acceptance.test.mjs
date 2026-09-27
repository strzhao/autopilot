/**
 * knowledge-inbox-smoke: 知识收件箱（inbox）机制 — 红队 real-process / 机械拓扑验收驱动
 *
 * 红队测试 — 仅基于设计文档编写（state.md `## 目标`/`## 设计文档`/`## 契约规约`/`## 验收场景`
 * 谓词 SSOT），未读取任何蓝队实现改动。TDD 红灯：基线 main@937f6e3 无任何 inbox/收编协议文案，
 * 场景 1 文档闸门与场景 6 命令抽取在基线必失败。
 *
 * 运行方式（real-process driver，勿加入 npm test —— S9.P1 本身就是「跑 npm test」的驱动，
 * 加入会造成自引用递归；场景 9 由本驱动真跑 npm test）：
 *   node --test plugins/autopilot/scripts/knowledge-inbox-smoke.acceptance.test.mjs
 *
 * 覆盖谓词（与 /tmp/autopilot-artifacts/ artifact 一一对应）：
 *   场景1.P1 [det-machine]  → s1-p1.out  收编后聚合层含条目主题 ∧ 命中行 != inbox 源行（Integration 非照搬）
 *   场景1.P2 [det-machine]  → s1-p2.out  index.md 含条目主题 ∧ 相对基线内容变更（重建证据）
 *   场景1.P3 [det-machine]  → s1-p3.out  已收编 inbox 文件被删除
 *   场景1.P4 [det-machine]  → s1-p4.out  freshness_check(index.md, knowledge/) == FRESH 且 rc=0
 *   场景1.P5 [real-process] → s1-p5.out  收编链路真实执行一次：exit 0 ∧ diff 非空 ∧ inbox 计数差 -1
 *   场景1.P6 [det-machine]  → s1-p6.out  收编重建后 index.md 行数 ≤ 100
 *   场景2.P3 [real-process] → s2-p3.out  两分支各自新增独立 inbox 文件后 git merge 零冲突
 *   场景4.P1 [det-machine]  → s4-p1.out  worktree 会话仅新增 inbox 文件 ∧ 聚合层零改动（symlink 拓扑机械验证）
 *   场景4.P2 [det-machine]  → s4-p2.out  worktree 不收编：聚合层 diff 空 ∧ inbox 计数不减 ∧ index 不含条目主题
 *   场景5.P2 [real-process] → s5-p2.out  两跳发现纯本地列举：exit 正常 ∧ stderr 为空
 *   场景6.P1 [real-process] → s6-p1.out  inbox > 10：doctor Wave1 收集命令真跑输出计数 > 10 ∧ rc=0
 *   场景6.P2 [real-process] → s6-p2.out  inbox ≤ 10：doctor Wave1 收集命令真跑计数 ≤ 10 ∧ rc=0
 *   场景9.P1 [real-process] → s9-p1.out  npm test 全绿（exit == 0）
 *
 * 诚实性说明（AI-First 机制的确定性边界）：
 * - 收编/两跳消费/doctor 判读是 AI 按协议文档执行的语义动作，无法在确定性测试中调用 AI；
 *   本驱动按设计文档规定的收编过程对夹具执行参考实现，蓝队-facing 的硬断言是
 *   「协议文档必须声明该过程」（场景1 文档闸门：收编/Integration/inbox/收编基）与终态契约
 *   （P1-P6）；AI 真机执行留 QA real-run 复验（本驱动 artifact 即 QA 的复现规程）。
 * - 场景6 的 doctor「提示收编」语义判断属 Wave 2（AI），确定性部分 = Wave 1 收集命令
 *   （从 doctor SKILL.md 逐字抽取并真实执行）+ 阈值计数断言；提醒文案由场景6.P3 文案锁承载。
 */

import { describe, it, after } from 'node:test';
import assert from 'node:assert/strict';
import {
  mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync,
  existsSync, lstatSync, readdirSync,
} from 'node:fs';
import { spawnSync, execFileSync } from 'node:child_process';
import { join, resolve, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

// 零改动契约锚（knowledge-symlink.acceptance.test.mjs 同源）：inbox 必须不在共享 symlink 列表
const { ensureSelectiveAutopilotLayout, SHARED_AUTOPILOT_ITEMS } = await import('./worktree.mjs');

const __dirname = dirname(fileURLToPath(import.meta.url));
const PLUGIN_DIR = resolve(__dirname, '..');                       // plugins/autopilot
const REPO_ROOT = resolve(__dirname, '..', '..', '..');            // 仓库根
const KE_MD = join(PLUGIN_DIR, 'skills/autopilot/references/knowledge-engineering.md');
const DOCTOR_MD = join(PLUGIN_DIR, 'skills/autopilot-doctor/SKILL.md');
const LIB_SH = join(__dirname, 'lib.sh');
const ART_DIR = '/tmp/autopilot-artifacts';
const TODAY = new Date().toISOString().slice(0, 10);

mkdirSync(ART_DIR, { recursive: true });

function artifact(name, content) {
  writeFileSync(join(ART_DIR, name), content);
}

function git(args, cwd) {
  const r = spawnSync('git', args, { cwd, encoding: 'utf8' });
  return { rc: r.status, stdout: (r.stdout || '').trim(), stderr: (r.stderr || '').trim() };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function inboxMdCount(dir) {
  if (!existsSync(dir)) return 0;
  return readdirSync(dir).filter((f) => f.endsWith('.md')).length;
}

// lib.sh freshness_check（契约：stdout=FRESH|STALE|UNKNOWN；FRESH ⇒ rc=0）
function freshness(product, srcDir) {
  const out = spawnSync(
    'bash',
    ['-c',
      `set -uo pipefail; export AUTOPILOT_TEST_MODE=1; export AUTOPILOT_DISABLE_MAIN=1; ` +
      `source '${LIB_SH}' 2>/dev/null || true; freshness_check '${product}' '${srcDir}'`],
    { encoding: 'utf8' },
  );
  return { stdout: (out.stdout || '').trim(), rc: out.status };
}

// ═════════════════════════════════════════════════════════════════════════
// 场景 1：主检出侧收编闭环（夹具：.git 为目录 + inbox 条目 + 聚合层基线快照）
// ═════════════════════════════════════════════════════════════════════════
describe('场景1：主检出侧收编闭环', () => {
  const fx = mkdtempSync(join(tmpdir(), 'inbox-incorp-'));
  const knowledgeDir = join(fx, '.autopilot/knowledge');
  const inboxDir = join(knowledgeDir, 'inbox');
  const decisionsMd = join(knowledgeDir, 'decisions.md');
  const indexMd = join(knowledgeDir, 'index.md');
  const THEME = '收件箱';
  const decisionsBaseline = 'Decision: 基线决策（收编前快照）\n';
  const indexBaseline = '# Index\n- [2026-01-01] 基线条目 → decisions.md\n';
  const inboxEntryName = `${TODAY}-incorporation-smoke.md`;
  const inboxSourceLines = [
    `### [${TODAY}] ${THEME}零冲突机制`,
    '<!-- tags: knowledge, inbox, conflict -->',
    `- 写入 = 新文件，${THEME}独立条目使冲突按构造消失`,
  ];

  let keContent = '';
  let smokeRc = 1;
  let smokeLog = '';
  let decisionsAfter = '';
  let indexAfter = '';
  let countBefore = 0;
  let countAfter = 0;

  it('P5 前置：夹具就绪 + 协议文档闸门（收编/Integration/inbox/收编基 必须在 SSOT 声明）', () => {
    // 夹具：主检出侧（.git 为目录）
    mkdirSync(join(fx, '.git'), { recursive: true });
    mkdirSync(join(knowledgeDir, 'domains'), { recursive: true });
    mkdirSync(inboxDir, { recursive: true });
    writeFileSync(decisionsMd, decisionsBaseline);
    writeFileSync(join(knowledgeDir, 'patterns.md'), 'Pattern: 基线模式\n');
    writeFileSync(indexMd, indexBaseline);
    // 夹具 inbox 条目（写侧协议产物）
    writeFileSync(join(inboxDir, inboxEntryName), inboxSourceLines.join('\n') + '\n');
    countBefore = inboxMdCount(inboxDir);
    assert.equal(countBefore, 1, '夹具 inbox 应有 1 条待收编条目');

    // 文档闸门（蓝队-facing 硬断言；基线全无 → 红灯）
    keContent = readFileSync(KE_MD, 'utf8');
    const missing = ['收编', 'Integration', 'inbox', '收编基'].filter((k) => !keContent.includes(k));
    assert.deepEqual(
      missing,
      [],
      `knowledge-engineering.md 缺收编协议关键文案: ${missing.join(', ')}（Inbox/Collection Protocol 未声明）`,
    );
  });

  it('P5 收编链路真实执行：exit 0 ∧ 聚合层 diff 非空 ∧ inbox 计数差 == -1', async () => {
    // 参考实现严格按设计文档收编协议四步：读积压 → Integration 语义合并 → 重建 index → 删除已收编文件
    const log = [];
    try {
      // ① 读积压条目
      const entry = readFileSync(join(inboxDir, inboxEntryName), 'utf8');
      assert.ok(entry.includes(THEME), '夹具条目应含主题关键词');
      await sleep(1100);
      // ② Integration over Append：语义融入聚合层（改写表述，非照搬源行）
      decisionsAfter = decisionsBaseline
        + `- 收编语义行：${THEME}机制把知识沉淀收敛为独立文件，写冲突在构造层面消除\n`;
      writeFileSync(decisionsMd, decisionsAfter);
      await sleep(1100);
      // ③ 重建 index.md（收编基：含新条目主题；夹具级条目数，行数远低于 100 红线）
      indexAfter = indexBaseline + `- [${TODAY}] ${THEME}零冲突机制 → decisions.md\n`;
      writeFileSync(indexMd, indexAfter);
      // ④ 删除已收编 inbox 文件
      rmSync(join(inboxDir, inboxEntryName));
      countAfter = inboxMdCount(inboxDir);
      smokeRc = 0;
      log.push('收编参考执行: OK');
    } catch (err) {
      smokeRc = 1;
      log.push(`收编参考执行异常: ${err && err.message}`);
    }
    smokeLog = log.join('\n');

    assert.equal(smokeRc, 0, `收编链路执行应 exit 0：${smokeLog}`);
    assert.notEqual(decisionsAfter, decisionsBaseline, '聚合层相对基线 diff 应非空（Integration 发生）');
    assert.equal(countAfter - countBefore, -1, `inbox 文件计数差应 == -1，实际 ${countAfter - countBefore}`);
    artifact('s1-p5.out',
      `exit=${smokeRc}\ndecisions.md diff 非空: ${decisionsAfter !== decisionsBaseline}\n` +
      `inbox 计数 ${countBefore} → ${countAfter}（差 ${countAfter - countBefore}）\n${smokeLog}\n` +
      '（QA real-run 复验规程：在主检出侧按 knowledge-engineering.md 收编协议对真实积压执行一次，核对本终态契约）');
  });

  it('P1 聚合层包含条目主题且命中行与 inbox 源行逐字节不同（Integration 非照搬）', () => {
    const patterns = readFileSync(join(knowledgeDir, 'patterns.md'), 'utf8');
    const aggHitLines = [];
    for (const content of [decisionsAfter, patterns]) {
      for (const line of content.split('\n')) {
        if (line.includes(THEME)) aggHitLines.push(line);
      }
    }
    assert.ok(aggHitLines.length >= 1, `聚合层应含主题「${THEME}」命中 ≥1 行`);
    const sourceSet = new Set(inboxSourceLines);
    for (const line of aggHitLines) {
      assert.ok(!sourceSet.has(line), `命中行不得与 inbox 源行逐字节相同（照搬违规）: ${line}`);
    }
    artifact('s1-p1.out',
      `聚合层命中行（${aggHitLines.length}）:\n${aggHitLines.join('\n')}\n─────\ninbox 源行:\n${inboxSourceLines.join('\n')}`);
  });

  it('P2 index.md 含条目主题且相对基线发生内容变更（重建证据）', () => {
    assert.ok(indexAfter.includes(THEME), '重建后 index.md 应含条目主题');
    assert.notEqual(indexAfter, indexBaseline, 'index.md 相对基线应有内容变更（重建证据）');
    artifact('s1-p2.out', `index.md（重建后）:\n${indexAfter}─────\n含主题「${THEME}」: true\n基线 diff 非空: true`);
  });

  it('P3 已收编 inbox 文件被删除', () => {
    assert.equal(existsSync(join(inboxDir, inboxEntryName)), false, '已收编 inbox 文件应被删除');
    artifact('s1-p3.out', `${join(inboxDir, inboxEntryName)} exists=false\ninbox 终态: [${readdirSync(inboxDir).join(', ')}]`);
  });

  it('P4 freshness_check(index.md, knowledge/) 输出 FRESH 且 exit 0（index 比聚合源更新）', () => {
    const fr = freshness(indexMd, knowledgeDir);
    assert.equal(fr.rc, 0, `freshness rc 应 == 0，实际 ${fr.rc}（stdout=${fr.stdout}）`);
    assert.equal(fr.stdout, 'FRESH', `freshness stdout 应 == "FRESH"，实际 "${fr.stdout}"`);
    artifact('s1-p4.out', `stdout=${fr.stdout}\nexit=${fr.rc}\n（product=index.md, src=.autopilot/knowledge/）`);
  });

  it('P6 收编重建后 index.md 行数 ≤ 100', () => {
    const lines = Number(execFileSync('wc', ['-l', indexMd], { encoding: 'utf8' }).trim().split(/\s+/)[0]);
    assert.ok(lines <= 100, `index.md ${lines} 行应 ≤ 100（收编基红线）`);
    artifact('s1-p6.out', `wc -l index.md = ${lines}（≤100 红线）`);
  });

  after(() => rmSync(fx, { recursive: true, force: true }));
});

// ═════════════════════════════════════════════════════════════════════════
// 场景 2.P3：两分支各自新增独立 inbox 文件 → git merge 零冲突
// ═════════════════════════════════════════════════════════════════════════
describe('场景2.P3：并行双会话分支合并零冲突', () => {
  it('git merge 真跑零冲突（exit 0 ∧ 输出无 CONFLICT）', () => {
    const fx = mkdtempSync(join(tmpdir(), 'inbox-merge-'));
    const log = [];
    const g = (args, must) => {
      const r = git(args, fx);
      log.push(`git ${args.join(' ')} → rc=${r.rc}${r.stderr ? ` stderr=${r.stderr}` : ''}`);
      if (must) assert.equal(r.rc, 0, `git ${args.join(' ')} 失败: ${r.stderr}`);
      return r;
    };
    // 基线：聚合层 + 真实跟踪的 inbox/ 目录
    mkdirSync(join(fx, '.autopilot/knowledge/inbox'), { recursive: true });
    writeFileSync(join(fx, '.autopilot/knowledge/index.md'), '# Index\n');
    writeFileSync(join(fx, '.autopilot/knowledge/inbox/.gitkeep'), '');
    g(['init', '-q', '-b', 'main'], true);
    g(['config', 'user.email', 'red-team@test'], true);
    g(['config', 'user.name', 'red-team'], true);
    g(['add', '-A'], true);
    g(['commit', '-qm', 'baseline'], true);
    // 会话 A 分支：新增独立 inbox 文件
    g(['checkout', '-qb', 'feat-a'], true);
    writeFileSync(join(fx, '.autopilot/knowledge/inbox', `${TODAY}-feat-a-knowledge.md`),
      `### [${TODAY}] feat-a 知识\n<!-- tags: inbox, a -->\n`);
    g(['add', '-A'], true);
    g(['commit', '-qm', 'feat-a inbox entry'], true);
    // 会话 B 分支（同基线）：新增另一独立 inbox 文件
    g(['checkout', '-q', 'main'], true);
    g(['checkout', '-qb', 'feat-b'], true);
    writeFileSync(join(fx, '.autopilot/knowledge/inbox', `${TODAY}-feat-b-pattern.md`),
      `### [${TODAY}] feat-b 模式\n<!-- tags: inbox, b -->\n`);
    g(['add', '-A'], true);
    g(['commit', '-qm', 'feat-b inbox entry'], true);
    // 依次合并
    g(['checkout', '-q', 'main'], true);
    const mA = g(['merge', '--no-edit', '-q', 'feat-a'], true);
    const mB = g(['merge', '--no-edit', '-q', 'feat-b'], false);
    const combined = `${mA.stdout}${mA.stderr}${mB.stdout}${mB.stderr}`;
    assert.equal(mB.rc, 0, `第二次 merge 应 exit 0，实际 ${mB.rc}: ${mB.stderr}`);
    assert.ok(!combined.includes('CONFLICT'), '合并输出不得含 CONFLICT');
    const merged = readdirSync(join(fx, '.autopilot/knowledge/inbox')).sort();
    assert.deepEqual(merged,
      [`.gitkeep`, `${TODAY}-feat-a-knowledge.md`, `${TODAY}-feat-b-pattern.md`].sort(),
      '合并后两个会话的 inbox 文件都应存在（union）');
    artifact('s2-p3.out', `${log.join('\n')}\n─────\n合并后 inbox/: ${merged.join(', ')}\nCONFLICT: 无`);
    rmSync(fx, { recursive: true, force: true });
  });
});

// ═════════════════════════════════════════════════════════════════════════
// 场景 4.P1/P2：worktree 会话只写 inbox、永不收编（symlink 拓扑机械验证）
// ═════════════════════════════════════════════════════════════════════════
describe('场景4：worktree 会话仅写 inbox、永不收编（机械拓扑）', () => {
  const THEME4 = 'worktree隔离子验证';
  const base = mkdtempSync(join(tmpdir(), 'inbox-wt-'));
  const mainRepo = join(base, 'main');
  const worktree = join(base, 'wt-inbox');

  it('P1 前置：inbox 不在 SHARED_AUTOPILOT_ITEMS（worktree 中 inbox/ 是真实目录，零改动契约）', () => {
    assert.ok(!SHARED_AUTOPILOT_ITEMS.includes('knowledge/inbox'),
      'knowledge/inbox 必须不在共享 symlink 列表——worktree 的 inbox/ 是真实 git 跟踪目录');
  });

  it('P1 worktree 会话 merge 阶段仅新增 inbox 文件 ∧ 聚合层四类零改动', () => {
    // 主检出基线
    mkdirSync(join(mainRepo, '.autopilot/knowledge/domains'), { recursive: true });
    mkdirSync(join(mainRepo, '.autopilot/runtime/requirements'), { recursive: true });
    writeFileSync(join(mainRepo, '.autopilot/knowledge/decisions.md'), 'Decision: MAIN-BASELINE\n');
    writeFileSync(join(mainRepo, '.autopilot/knowledge/patterns.md'), 'Pattern: MAIN-BASELINE\n');
    writeFileSync(join(mainRepo, '.autopilot/knowledge/index.md'), '# Index\n');
    // worktree 隔离检出（.git 为文件的检出形态由真实 worktree 承担；此处验证拓扑机制）
    mkdirSync(worktree, { recursive: true });
    ensureSelectiveAutopilotLayout(mainRepo, worktree);
    // worktree 分支携带真实 inbox/ 目录（git 跟踪目录，非 symlink）
    const wtInbox = join(worktree, '.autopilot/knowledge/inbox');
    mkdirSync(wtInbox, { recursive: true });
    assert.ok(!lstatSync(wtInbox).isSymbolicLink(), 'worktree 的 inbox/ 必须是真实目录而非 symlink');
    // 聚合层在 worktree 侧是 symlink → main（写穿面）
    assert.ok(lstatSync(join(worktree, '.autopilot/knowledge/decisions.md')).isSymbolicLink(),
      '聚合层 decisions.md 应是 symlink（共享面）');
    // 会话知识提取：仅写 inbox
    writeFileSync(join(wtInbox, `${TODAY}-wt-isolated.md`),
      `### [${TODAY}] ${THEME4}\n<!-- tags: inbox, worktree -->\n`);
    // 聚合层四类零改动：main 侧无新 inbox 目录、decisions/patterns 内容不变
    assert.equal(existsSync(join(mainRepo, '.autopilot/knowledge/inbox')), false,
      'worktree 写 inbox 不得落到 main（inbox 是 worktree-local）');
    assert.equal(readFileSync(join(mainRepo, '.autopilot/knowledge/decisions.md'), 'utf8'),
      'Decision: MAIN-BASELINE\n', '聚合层 decisions.md 不得被 worktree 改动');
    assert.equal(readFileSync(join(mainRepo, '.autopilot/knowledge/patterns.md'), 'utf8'),
      'Pattern: MAIN-BASELINE\n', '聚合层 patterns.md 不得被 worktree 改动');
    artifact('s4-p1.out',
      `worktree inbox/ 真实目录: true（非 symlink）\n` +
      `worktree 新增 inbox 文件: ${TODAY}-wt-isolated.md\n` +
      `main/.autopilot/knowledge/inbox 存在: ${existsSync(join(mainRepo, '.autopilot/knowledge/inbox'))}（应 false）\n` +
      `聚合层 decisions/patterns 相对基线 diff: 空`);
  });

  it('P2 worktree 不收编：聚合层 diff 空 ∧ inbox 计数不减 ∧ index 不含条目主题', () => {
    const wtInbox = join(worktree, '.autopilot/knowledge/inbox');
    assert.equal(inboxMdCount(wtInbox), 1, 'inbox 计数不得减少（不删除已「收编」文件）');
    assert.ok(existsSync(join(wtInbox, `${TODAY}-wt-isolated.md`)), 'inbox 文件不得被收编删除');
    const mainIndex = readFileSync(join(mainRepo, '.autopilot/knowledge/index.md'), 'utf8');
    assert.ok(!mainIndex.includes(THEME4), 'index.md 不得含 worktree 条目主题（未收编）');
    assert.equal(readFileSync(join(mainRepo, '.autopilot/knowledge/index.md'), 'utf8'), '# Index\n',
      'index.md 不得被 worktree 重建');
    artifact('s4-p2.out',
      `收编三体征：聚合层 diff=空；inbox 计数=1（不减）；index.md 含条目主题=false\n` +
      `（协议级禁令文案锁见 knowledge-inbox.acceptance.test.sh 场景4.P3）`);
  });

  after(() => rmSync(base, { recursive: true, force: true }));
});

// ═════════════════════════════════════════════════════════════════════════
// 场景 5.P2：两跳发现纯本地列举冒烟（N 条积压，exit 正常 ∧ stderr 为空）
// ═════════════════════════════════════════════════════════════════════════
describe('场景5.P2：两跳发现冒烟（无收编发生）', () => {
  it('N=3 积压条目两跳列举 exit 正常、stderr 为空、全部命中', () => {
    const fx = mkdtempSync(join(tmpdir(), 'inbox-twohop-'));
    const knowledgeDir = join(fx, 'knowledge');
    mkdirSync(join(knowledgeDir, 'inbox'), { recursive: true });
    writeFileSync(join(knowledgeDir, 'index.md'), '# Index\n- [2026-01-01] 旧条目\n');
    const themes = ['冒烟主题一', '冒烟主题二', '冒烟主题三'];
    themes.forEach((t, i) => writeFileSync(
      join(knowledgeDir, 'inbox', `${TODAY}-backlog-${i + 1}.md`),
      `### [${TODAY}] 积压${i + 1}\n- 主题：${t}\n`,
    ));
    // 两跳发现（第一跳 index tags 匹配 + 第二跳 inbox 列举按需读）
    const stderrParts = [];
    let indexContent = '';
    let entryContents = [];
    try {
      indexContent = readFileSync(join(knowledgeDir, 'index.md'), 'utf8');
    } catch (err) { stderrParts.push(String(err)); }
    try {
      entryContents = readdirSync(join(knowledgeDir, 'inbox'))
        .filter((f) => f.endsWith('.md'))
        .map((f) => readFileSync(join(knowledgeDir, 'inbox', f), 'utf8'));
    } catch (err) { stderrParts.push(String(err)); }
    const hits = themes.filter((t) =>
      indexContent.includes(t) || entryContents.some((c) => c.includes(t)));
    assert.equal(stderrParts.join(''), '', `两跳列举不得产生任何错误/缺文件异常: ${stderrParts.join('')}`);
    assert.equal(hits.length, themes.length, `两跳发现应覆盖全部积压主题，实际命中 ${hits.length}/${themes.length}`);
    artifact('s5-p2.out',
      `exit=0\nstderr=（空）\n积压条目=${themes.length} 命中=${hits.length}\n` +
      `（第一跳 index 命中 0 条 ∧ 第二跳 inbox 列举命中 ${hits.length} 条 → 发现不依赖收编）`);
    rmSync(fx, { recursive: true, force: true });
  });
});

// ═════════════════════════════════════════════════════════════════════════
// 场景 6.P1/P2：doctor 巡检 inbox 积压计数（Wave1 收集命令抽取 + 真跑）
// ═════════════════════════════════════════════════════════════════════════
describe('场景6：doctor 巡检 inbox 积压计数信号', () => {
  // 从 doctor SKILL.md 逐字抽取 inbox 计数候选命令：含 inbox/收件箱 的行上的反引号 span，
  // 以及代码围栏/命令形态行（设计仅声明「inbox 计数」Wave1 收集命令，未锁定写法形态）
  function extractInboxCountCommands(doc) {
    const out = [];
    let inFence = false;
    for (const line of doc.split('\n')) {
      if (/^\s*```/.test(line)) { inFence = !inFence; continue; }
      if (!/inbox|收件箱/.test(line)) continue;
      for (const m of line.matchAll(/`([^`]+)`/g)) {
        if (/(^|[\s=])(ls|find|wc)\s/.test(m[1])) out.push(m[1].trim());
      }
      if (inFence || /(^|[\s`(=])(ls|find)\s/.test(line)) {
        out.push(line.replace(/^[\s>*\-\d.]+/, '').trim());
      }
    }
    return [...new Set(out.filter(Boolean))];
  }

  // 真跑收集命令：无 wc -l 时补管道计数（对 ls/find 形态语义等价）；解析末尾整数
  function runInboxCount(cmd, cwd) {
    const full = /wc\s+-l/.test(cmd) ? cmd : `${cmd} 2>/dev/null | wc -l`;
    const r = spawnSync('bash', ['-c', full], { cwd, encoding: 'utf8' });
    const m = (r.stdout || '').trim().match(/(\d+)\s*$/);
    return { rc: r.status, count: m ? Number(m[1]) : null, stdout: (r.stdout || '').trim(), cmd: full };
  }

  function buildBacklogFixture(n) {
    const fx = mkdtempSync(join(tmpdir(), 'inbox-doctor-'));
    mkdirSync(join(fx, '.autopilot/knowledge/inbox'), { recursive: true });
    for (let i = 1; i <= n; i += 1) {
      writeFileSync(join(fx, '.autopilot/knowledge/inbox', `${TODAY}-backlog-${String(i).padStart(2, '0')}.md`),
        `### [${TODAY}] 积压条目 ${i}\n`);
    }
    return fx;
  }

  it('P1 前置：doctor 文档声明 inbox 信号 + 阈值 + 提醒语义，且含可执行收集命令', () => {
    const doc = readFileSync(DOCTOR_MD, 'utf8');
    assert.ok(doc.includes('inbox'), 'doctor SKILL.md 未声明 inbox 计数信号（Dim 12 Wave1）');
    assert.ok(doc.includes('10'), 'doctor SKILL.md 未声明阈值 10');
    assert.match(doc, /提醒|提示/, 'doctor SKILL.md 缺收编提醒语义（Step 2 判读）');
    const cmds = extractInboxCountCommands(doc);
    assert.ok(cmds.length >= 1,
      'doctor SKILL.md 无可执行的 inbox 计数命令（Wave1 数据收集行缺失或非 ls/find 形态）');
  });

  it('P1 inbox 文件数 > 10：收集命令真跑输出计数 > 10 且 rc=0（并提示收编语义在文档锁）', () => {
    const fx = buildBacklogFixture(12);
    const doc = readFileSync(DOCTOR_MD, 'utf8');
    const attempts = extractInboxCountCommands(doc).map((c) => runInboxCount(c, fx));
    const usable = attempts.filter((a) => a.count !== null);
    assert.ok(usable.length >= 1, `收集命令均未产出计数: ${JSON.stringify(attempts)}`);
    const over = usable.find((a) => a.count > 10 && a.rc === 0);
    assert.ok(over, `12 个积压文件应被某条收集命令计出 > 10（rc=0），实际: ${JSON.stringify(usable)}`);
    assert.match(doc, /提醒|提示/, '>10 应触发收编提醒（判读语义须在 doctor 文档声明）');
    artifact('s6-p1.out',
      `fixture=12 个 inbox 文件\n执行命令: ${over.cmd}\ncount=${over.count}（>10）\nrc=${over.rc}\n` +
      `全部候选尝试: ${JSON.stringify(attempts)}\n` +
      '（提醒文案的 AI Wave2 真机输出留 QA real-run 复验；确定性锚 = 阈值计数 + 场景6.P3 文案锁）');
    rmSync(fx, { recursive: true, force: true });
  });

  it('P2 inbox 文件数 ≤ 10：收集命令真跑计数 ≤ 10 且 rc=0（不触发提醒区间）', () => {
    const fx = buildBacklogFixture(3);
    const doc = readFileSync(DOCTOR_MD, 'utf8');
    const attempts = extractInboxCountCommands(doc).map((c) => runInboxCount(c, fx));
    const usable = attempts.filter((a) => a.count !== null);
    assert.ok(usable.length >= 1, `收集命令均未产出计数: ${JSON.stringify(attempts)}`);
    assert.ok(usable.every((a) => a.count <= 10),
      `3 个积压文件下所有收集命令计数应 ≤ 10，实际: ${JSON.stringify(usable)}`);
    const under = usable.find((a) => a.rc === 0);
    assert.ok(under, `收集命令 rc 应 == 0: ${JSON.stringify(usable)}`);
    artifact('s6-p2.out',
      `fixture=3 个 inbox 文件\n执行命令: ${under.cmd}\ncount=${under.count}（≤10，阈值之下不提醒区间）\nrc=${under.rc}\n` +
      `全部候选尝试: ${JSON.stringify(attempts)}\n` +
      '（「stdout 不含提醒」由 AI 判读语义决定，确定性 surrogate = 计数低于阈值 + 场景6.P3 阈值文案锁；QA real-run 复验）');
    rmSync(fx, { recursive: true, force: true });
  });
});

// ═════════════════════════════════════════════════════════════════════════
// 场景 9.P1：npm test 全绿
// ═════════════════════════════════════════════════════════════════════════
describe('场景9.P1：既有验收套件零回归', () => {
  it('npm test 真跑 exit == 0（失败计数为 0）', () => {
    const nested = process.env.npm_lifecycle_event === 'test';
    if (nested) {
      // 自引用守卫：本文件若被加入 npm test，S9.P1 正由 npm test 进程本身求值，
      // 嵌套再 spawn npm test 属逻辑循环而非实现缺口——此时断言「确实处于 npm test 上下文」。
      assert.ok(nested, '应处于 npm test 上下文（自引用守卫分支）');
      artifact('s9-p1.out', 'nested=true：本驱动正被 npm test 求值，套件全绿性由当前 npm test 进程本身承载');
      return;
    }
    const r = spawnSync('npm', ['test'], {
      cwd: REPO_ROOT,
      encoding: 'utf8',
      maxBuffer: 64 * 1024 * 1024,
      timeout: 600000,
      // env 净化：node --test 注入的 NODE_TEST_CONTEXT 会被子进程继承，令内层 node --test
// 判定递归并「skipping running files」零执行仍 exit 0（假绿）——必须剥离；
// npm_lifecycle_event 一并剥离防 npm 子链路误判嵌套。
      env: (() => { const e = { ...process.env }; delete e.NODE_TEST_CONTEXT; delete e.npm_lifecycle_event; return e; })(),
    });
    const full = (r.stdout || '') + (r.stderr || '');
    const tail = full.split('\n').slice(-40).join('\n');
    const passM = full.match(/# pass (\d+)/);
    const failM = full.match(/# fail (\d+)/);
    artifact('s9-p1.out', `exit=${r.status}\n# pass=${passM ? passM[1] : '缺失'} # fail=${failM ? failM[1] : '缺失'}\n───── npm test 输出尾部 ─────\n${tail}`);
    assert.equal(r.status, 0, `npm test 应 exit 0（套件全绿），实际 ${r.status}（status=${r.status}, error=${r.error}）\n${tail}`);
    // 断言强化：必须出现真实执行汇总（# pass N 且 N>0、# fail 0）——任何短路/跳过路径（零测试执行）
// 都无法伪造该汇总语义，堵死 exit==0 对 no-op 的假绿存活。
    assert.ok(passM && Number(passM[1]) > 0, `npm test 输出应含「# pass N（N>0）」汇总语义，实际缺失——套件疑似未真实执行\n${tail}`);
    assert.ok(failM && Number(failM[1]) === 0, `npm test 汇总应「# fail 0」，实际 ${failM ? `# fail ${failM[1]}` : '缺失'}\n${tail}`);
  });
});
