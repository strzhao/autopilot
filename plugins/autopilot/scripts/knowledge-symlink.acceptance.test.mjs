/**
 * Selective .autopilot Layout — Acceptance Tests
 *
 * 设计契约：
 *   1. worktree 的 .autopilot/ 是"选择性 symlink"布局：
 *      - sessions/ 是 worktree-local 真实目录（提交到 worktree 分支）
 *      - 共享项（decisions.md、patterns.md、project/、requirements/ 等）symlink → 主仓库
 *      - 主仓库无对应共享项时跳过该 symlink（不创建 broken link）
 *   2. 旧版迁移：当 worktree 里 .autopilot 是全量 symlink 时，把 main 里
 *      sessions/<worktree-name>/ 移回 worktree，再重建为选择性布局。
 *   3. 幂等：重复运行不破坏现有正确状态；指错的 symlink 自动修正。
 *   4. remove() 兼容性：能清理新模式下的多个 symlink，也能清理旧版全量 symlink。
 *
 * 直接引入 worktree.mjs 中导出的 `ensureSelectiveAutopilotLayout` 与
 * `SHARED_AUTOPILOT_ITEMS`，验证实际实现而非 simulator。
 */

import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import {
  mkdtempSync, mkdirSync, writeFileSync, symlinkSync,
  existsSync, lstatSync, readFileSync, rmSync, realpathSync, readdirSync,
} from 'node:fs';
import { join, basename } from 'node:path';
import { tmpdir } from 'node:os';

const { ensureSelectiveAutopilotLayout, SHARED_AUTOPILOT_ITEMS } = await import('./worktree.mjs');

// ---------------------------------------------------------------------------
// 帮助函数
// ---------------------------------------------------------------------------

let tempBase;

before(() => {
  tempBase = mkdtempSync(join(tmpdir(), 'selective-autopilot-test-'));
});

after(() => {
  rmSync(tempBase, { recursive: true, force: true });
});

/** 建一对 main + worktree 目录 */
function scaffold(name) {
  const mainRepo = join(tempBase, `${name}-main`);
  const worktree = join(tempBase, `${name}-wt-${name}`);
  mkdirSync(mainRepo, { recursive: true });
  mkdirSync(worktree, { recursive: true });
  return { mainRepo, worktree };
}

/** 在 main/.autopilot/ 创建若干文件/目录 */
function seedMainKnowledge(mainRepo, items) {
  const apDir = join(mainRepo, '.autopilot');
  mkdirSync(apDir, { recursive: true });
  for (const [name, content] of Object.entries(items)) {
    const target = join(apDir, name);
    if (content === '__DIR__') {
      mkdirSync(target, { recursive: true });
    } else {
      writeFileSync(target, content);
    }
  }
}

// ===========================================================================
// 1. 基础布局：fresh worktree
// ===========================================================================
describe('基础布局：fresh worktree', () => {
  it('在 main 共享项齐全时，worktree 的 .autopilot 是真实目录，共享项是 symlink，sessions/ 是真实目录', () => {
    const { mainRepo, worktree } = scaffold('basic');
    seedMainKnowledge(mainRepo, {
      'decisions.md': '# Decisions\n',
      'patterns.md': '# Patterns\n',
      'index.md': '# Index\n',
      'domains': '__DIR__',
      'project': '__DIR__',
      'requirements': '__DIR__',
    });

    ensureSelectiveAutopilotLayout(mainRepo, worktree);

    const apDst = join(worktree, '.autopilot');
    // .autopilot 整体应是真实目录
    assert.ok(!lstatSync(apDst).isSymbolicLink(), '.autopilot 应是真实目录而非 symlink');
    assert.ok(lstatSync(apDst).isDirectory(), '.autopilot 应是目录');

    // sessions/ 是真实目录
    const sessionsDir = join(apDst, 'sessions');
    assert.ok(existsSync(sessionsDir), 'sessions/ 应被创建');
    assert.ok(!lstatSync(sessionsDir).isSymbolicLink(), 'sessions/ 应是真实目录');
    assert.ok(lstatSync(sessionsDir).isDirectory(), 'sessions/ 应是目录');

    // 共享项是 symlink → 主仓库
    for (const item of ['decisions.md', 'patterns.md', 'index.md', 'domains', 'project', 'requirements']) {
      const link = join(apDst, item);
      assert.ok(lstatSync(link).isSymbolicLink(), `.autopilot/${item} 应是 symlink`);
      const linkTarget = realpathSync(link);
      const expectedTarget = realpathSync(join(mainRepo, '.autopilot', item));
      assert.equal(linkTarget, expectedTarget, `${item} 应指向 main/.autopilot/${item}`);
    }
  });

  it('main 共享项不存在时跳过该 symlink（不创建 broken link）', () => {
    const { mainRepo, worktree } = scaffold('partial');
    // main 只有 decisions.md，没有 patterns.md / project/
    seedMainKnowledge(mainRepo, { 'decisions.md': '# D\n' });

    ensureSelectiveAutopilotLayout(mainRepo, worktree);

    const apDst = join(worktree, '.autopilot');
    assert.ok(lstatSync(join(apDst, 'decisions.md')).isSymbolicLink(), 'decisions.md 应是 symlink');
    assert.ok(!existsSync(join(apDst, 'patterns.md')), 'main 没有的项不应在 worktree 创建 broken symlink');
    assert.ok(!existsSync(join(apDst, 'project')), 'project/ 不存在时不应创建');
  });

  it('main 仓库完全没有 .autopilot 时，预创建 main/.autopilot 并把 worktree 的 sessions/ 设为真实目录', () => {
    const { mainRepo, worktree } = scaffold('no-main');
    // main 完全没有 .autopilot

    ensureSelectiveAutopilotLayout(mainRepo, worktree);

    assert.ok(existsSync(join(mainRepo, '.autopilot')), 'main/.autopilot 应被预创建');
    assert.ok(existsSync(join(worktree, '.autopilot', 'sessions')), 'worktree/.autopilot/sessions 应被创建');
    assert.ok(!lstatSync(join(worktree, '.autopilot')).isSymbolicLink(), '.autopilot 不应是 symlink');
  });
});

// ===========================================================================
// 2. 旧版迁移：全量 symlink → 选择性布局
// ===========================================================================
describe('旧版迁移', () => {
  it('worktree/.autopilot 是全量 symlink + main 里有本 worktree 的 sessions → 自动迁移并重建', () => {
    const { mainRepo, worktree } = scaffold('legacy');
    const wtName = basename(worktree); // ensureSelectiveAutopilotLayout 用 basename(worktreePath) 推 sessions 目录名
    seedMainKnowledge(mainRepo, {
      'decisions.md': '# D\n',
      'patterns.md': '# P\n',
    });
    // 模拟旧版：worktree/.autopilot 是全量 symlink → main/.autopilot
    symlinkSync(join(mainRepo, '.autopilot'), join(worktree, '.autopilot'));

    // 模拟旧版下 main 里堆积的 sessions/<wtName>/...（实际通过 symlink 写入也会落到这里）
    const mainSessionDir = join(mainRepo, '.autopilot', 'sessions', wtName);
    mkdirSync(mainSessionDir, { recursive: true });
    writeFileSync(join(mainSessionDir, 'active'), 'pointer\n');
    mkdirSync(join(mainSessionDir, 'requirements', 'task-001'), { recursive: true });
    writeFileSync(join(mainSessionDir, 'requirements', 'task-001', 'state.md'), '# state\n');

    ensureSelectiveAutopilotLayout(mainRepo, worktree);

    const apDst = join(worktree, '.autopilot');
    // .autopilot 不再是 symlink
    assert.ok(!lstatSync(apDst).isSymbolicLink(), '.autopilot 应是真实目录');

    // sessions 已迁回 worktree
    const wtSessionDir = join(apDst, 'sessions', wtName);
    assert.ok(existsSync(wtSessionDir), `sessions/${wtName}/ 应已迁回 worktree`);
    assert.equal(
      readFileSync(join(wtSessionDir, 'active'), 'utf8'),
      'pointer\n',
      'sessions/<name>/active 内容应保留'
    );
    assert.equal(
      readFileSync(join(wtSessionDir, 'requirements', 'task-001', 'state.md'), 'utf8'),
      '# state\n',
      '嵌套文件应迁移完整'
    );

    // main 里同名 sessions 目录应已被移除
    assert.ok(!existsSync(mainSessionDir), `main 里的 sessions/${wtName}/ 应在迁移后被移除`);

    // 共享项重建为 symlink
    assert.ok(lstatSync(join(apDst, 'decisions.md')).isSymbolicLink(), 'decisions.md 重建为 symlink');
  });

  it('worktree/.autopilot 是全量 symlink 但 main 里没有本 worktree 的 sessions → 直接重建（不报错）', () => {
    const { mainRepo, worktree } = scaffold('legacy-empty');
    seedMainKnowledge(mainRepo, { 'decisions.md': 'D' });
    symlinkSync(join(mainRepo, '.autopilot'), join(worktree, '.autopilot'));

    // 不创建 main/.autopilot/sessions/<wtName>/

    ensureSelectiveAutopilotLayout(mainRepo, worktree);

    const apDst = join(worktree, '.autopilot');
    assert.ok(!lstatSync(apDst).isSymbolicLink(), '.autopilot 应是真实目录');
    assert.ok(existsSync(join(apDst, 'sessions')), 'sessions/ 应被创建');
    assert.ok(lstatSync(join(apDst, 'decisions.md')).isSymbolicLink(), 'decisions.md 重建为 symlink');
  });
});

// ===========================================================================
// 3. 真实文件替换：worktree 分支 checkout 出真实文件 → 改 symlink
//    保护策略：内容一致 → 静默替换；不一致 / 目录 → rename 到 conflict 备份
// ===========================================================================
describe('真实文件替换为 symlink（带冲突保护）', () => {
  it('真实 decisions.md 内容与 main 一致 → 静默替换为 symlink，无备份产物', () => {
    const { mainRepo, worktree } = scaffold('replace-equal');
    seedMainKnowledge(mainRepo, { 'decisions.md': 'same content\n' });
    mkdirSync(join(worktree, '.autopilot'), { recursive: true });
    writeFileSync(join(worktree, '.autopilot', 'decisions.md'), 'same content\n');

    ensureSelectiveAutopilotLayout(mainRepo, worktree);

    const link = join(worktree, '.autopilot', 'decisions.md');
    assert.ok(lstatSync(link).isSymbolicLink(), 'decisions.md 应是 symlink');
    assert.equal(readFileSync(link, 'utf8'), 'same content\n');

    const backups = readdirSync(worktree).filter(f => f.startsWith('.autopilot-conflict-'));
    assert.equal(backups.length, 0, '内容一致不应留下 conflict 备份');
  });

  it('真实 decisions.md 内容与 main 不同 → rename 到备份文件，symlink 仍建立', () => {
    const { mainRepo, worktree } = scaffold('replace-conflict');
    seedMainKnowledge(mainRepo, { 'decisions.md': 'main version\n' });
    mkdirSync(join(worktree, '.autopilot'), { recursive: true });
    writeFileSync(join(worktree, '.autopilot', 'decisions.md'), 'worktree branch version\n');

    ensureSelectiveAutopilotLayout(mainRepo, worktree);

    const link = join(worktree, '.autopilot', 'decisions.md');
    assert.ok(lstatSync(link).isSymbolicLink(), 'decisions.md 应是 symlink');
    assert.equal(
      readFileSync(link, 'utf8'),
      'main version\n',
      '通过 symlink 读到 main 内容'
    );

    const backups = readdirSync(worktree).filter(f =>
      f.startsWith('.autopilot-conflict-decisions.md-')
    );
    assert.equal(backups.length, 1, '不一致内容必须备份到 .autopilot-conflict-* 文件');
    assert.equal(
      readFileSync(join(worktree, backups[0]), 'utf8'),
      'worktree branch version\n',
      '备份文件保留原 worktree 内容供手动合并'
    );
  });

  it('真实目录（如 project/）→ 一律 rename 到备份目录，symlink 建立', () => {
    const { mainRepo, worktree } = scaffold('replace-dir');
    seedMainKnowledge(mainRepo, { 'project': '__DIR__' });
    writeFileSync(join(mainRepo, '.autopilot', 'project', 'shared.md'), 'shared\n');
    mkdirSync(join(worktree, '.autopilot', 'project'), { recursive: true });
    writeFileSync(join(worktree, '.autopilot', 'project', 'local-only.md'), 'local\n');

    ensureSelectiveAutopilotLayout(mainRepo, worktree);

    const link = join(worktree, '.autopilot', 'project');
    assert.ok(lstatSync(link).isSymbolicLink(), 'project/ 应是 symlink');
    assert.ok(existsSync(join(link, 'shared.md')), '通过 symlink 应能看到 main 的 shared.md');

    const backups = readdirSync(worktree).filter(f =>
      f.startsWith('.autopilot-conflict-project-')
    );
    assert.equal(backups.length, 1, '真实目录必须备份');
    assert.equal(
      readFileSync(join(worktree, backups[0], 'local-only.md'), 'utf8'),
      'local\n',
      '备份目录保留 worktree 原有文件'
    );
  });

  it('多次冲突不互相覆盖（timestamp 隔离）', async () => {
    const { mainRepo, worktree } = scaffold('replace-multi');
    seedMainKnowledge(mainRepo, { 'decisions.md': 'm1\n' });
    mkdirSync(join(worktree, '.autopilot'), { recursive: true });
    writeFileSync(join(worktree, '.autopilot', 'decisions.md'), 'wt-v1\n');

    ensureSelectiveAutopilotLayout(mainRepo, worktree);

    // 第一次备份产生
    let backups = readdirSync(worktree).filter(f =>
      f.startsWith('.autopilot-conflict-decisions.md-')
    );
    assert.equal(backups.length, 1);

    // 模拟第二次冲突：删 symlink、重写真实文件、等待 timestamp 变化、再跑
    rmSync(join(worktree, '.autopilot', 'decisions.md'));
    writeFileSync(join(worktree, '.autopilot', 'decisions.md'), 'wt-v2\n');
    await new Promise(r => setTimeout(r, 5));

    ensureSelectiveAutopilotLayout(mainRepo, worktree);

    backups = readdirSync(worktree).filter(f =>
      f.startsWith('.autopilot-conflict-decisions.md-')
    );
    assert.equal(backups.length, 2, '第二次冲突应另存为新备份');
    const contents = backups.map(b => readFileSync(join(worktree, b), 'utf8')).sort();
    assert.deepEqual(contents, ['wt-v1\n', 'wt-v2\n'], '两次备份内容互不覆盖');
  });
});

// ===========================================================================
// 4. 幂等性
// ===========================================================================
describe('幂等性', () => {
  it('重复运行不改变正确状态', () => {
    const { mainRepo, worktree } = scaffold('idempotent');
    seedMainKnowledge(mainRepo, {
      'decisions.md': 'd',
      'project': '__DIR__',
    });

    ensureSelectiveAutopilotLayout(mainRepo, worktree);
    const firstStat = lstatSync(join(worktree, '.autopilot', 'decisions.md'));

    // 第二次运行
    ensureSelectiveAutopilotLayout(mainRepo, worktree);
    const secondStat = lstatSync(join(worktree, '.autopilot', 'decisions.md'));

    assert.ok(firstStat.isSymbolicLink());
    assert.ok(secondStat.isSymbolicLink());
  });

  it('保留 sessions/ 中已有的 worktree-local 文件', () => {
    const { mainRepo, worktree } = scaffold('preserve-sessions');
    seedMainKnowledge(mainRepo, { 'decisions.md': 'd' });
    ensureSelectiveAutopilotLayout(mainRepo, worktree);

    // 在 worktree 的 sessions/ 写一个文件
    const sessFile = join(worktree, '.autopilot', 'sessions', 'feature-a', 'active');
    mkdirSync(join(worktree, '.autopilot', 'sessions', 'feature-a'), { recursive: true });
    writeFileSync(sessFile, 'pointer\n');

    // 再次运行 repair
    ensureSelectiveAutopilotLayout(mainRepo, worktree);

    assert.ok(existsSync(sessFile), 'sessions/feature-a/active 应被保留');
    assert.equal(readFileSync(sessFile, 'utf8'), 'pointer\n');
  });
});

// ===========================================================================
// 5. 写入隔离验证
// ===========================================================================
describe('写入隔离验证', () => {
  it('通过 worktree symlink 写入共享项 → 落到 main', () => {
    const { mainRepo, worktree } = scaffold('write-shared');
    seedMainKnowledge(mainRepo, { 'decisions.md': '' });
    ensureSelectiveAutopilotLayout(mainRepo, worktree);

    writeFileSync(join(worktree, '.autopilot', 'decisions.md'), 'new from worktree\n');
    assert.equal(
      readFileSync(join(mainRepo, '.autopilot', 'decisions.md'), 'utf8'),
      'new from worktree\n',
      '通过 worktree symlink 写入应落到 main'
    );
  });

  it('在 worktree 的 sessions/ 写入 → 不影响 main', () => {
    const { mainRepo, worktree } = scaffold('write-sessions');
    seedMainKnowledge(mainRepo, {});
    ensureSelectiveAutopilotLayout(mainRepo, worktree);

    const wtName = basename(worktree);
    mkdirSync(join(worktree, '.autopilot', 'sessions', wtName), { recursive: true });
    writeFileSync(
      join(worktree, '.autopilot', 'sessions', wtName, 'active'),
      'pointer\n'
    );

    // main 里 sessions/<wtName>/ 不应被创建
    assert.ok(
      !existsSync(join(mainRepo, '.autopilot', 'sessions', wtName)),
      'sessions 写入应隔离在 worktree 内，不应在 main 出现'
    );
  });
});

// ===========================================================================
// 6. SHARED_AUTOPILOT_ITEMS 导出契约
// ===========================================================================
describe('SHARED_AUTOPILOT_ITEMS 导出契约', () => {
  it('包含核心知识文件', () => {
    assert.ok(SHARED_AUTOPILOT_ITEMS.includes('decisions.md'));
    assert.ok(SHARED_AUTOPILOT_ITEMS.includes('patterns.md'));
    assert.ok(SHARED_AUTOPILOT_ITEMS.includes('index.md'));
    assert.ok(SHARED_AUTOPILOT_ITEMS.includes('domains'));
  });

  it('包含项目级共享项', () => {
    assert.ok(SHARED_AUTOPILOT_ITEMS.includes('project'));
    assert.ok(SHARED_AUTOPILOT_ITEMS.includes('requirements'));
  });

  it('不包含 sessions（sessions 是 worktree-local）', () => {
    assert.ok(
      !SHARED_AUTOPILOT_ITEMS.includes('sessions'),
      'sessions 必须不在共享列表里——它是 worktree-local'
    );
  });
});
