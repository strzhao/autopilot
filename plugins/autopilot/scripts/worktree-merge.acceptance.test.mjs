import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(__dirname, '../../..');
const autopilotRoot = resolve(projectRoot, 'plugins/autopilot');

describe('worktree-setup 合并到 autopilot 验收测试', () => {

  // ─── 1. 文件迁移完整性 ───
  describe('文件迁移完整性', () => {
    it('worktree.mjs 存在于 autopilot/scripts/', () => {
      assert.ok(
        existsSync(resolve(autopilotRoot, 'scripts/worktree.mjs')),
        'scripts/worktree.mjs 应存在'
      );
    });

    it('worktree.test.mjs 存在于 autopilot/scripts/', () => {
      assert.ok(
        existsSync(resolve(autopilotRoot, 'scripts/worktree.test.mjs')),
        'scripts/worktree.test.mjs 应存在'
      );
    });

    it('worktree-merge.acceptance.test.mjs 存在于 autopilot/scripts/', () => {
      assert.ok(
        existsSync(resolve(autopilotRoot, 'scripts/worktree-merge.acceptance.test.mjs')),
        'scripts/worktree-merge.acceptance.test.mjs 应存在（即本文件）'
      );
    });

    it('repair SKILL.md 存在于 autopilot/skills/worktree-repair/', () => {
      assert.ok(
        existsSync(resolve(autopilotRoot, 'skills/worktree-repair/SKILL.md')),
        'skills/worktree-repair/SKILL.md 应存在'
      );
    });
  });

  // ─── 2. 旧目录清理 ───
  describe('旧目录清理', () => {
    it('plugins/worktree-setup/ 目录不存在', () => {
      assert.ok(
        !existsSync(resolve(projectRoot, 'plugins/worktree-setup')),
        'plugins/worktree-setup/ 应已被删除'
      );
    });
  });

  // ─── 3. hooks.json 正确性 ───
  describe('hooks.json 正确性', () => {
    let hooksConfig;

    it('hooks.json 可解析', () => {
      const raw = readFileSync(resolve(autopilotRoot, 'hooks/hooks.json'), 'utf8');
      hooksConfig = JSON.parse(raw);
      assert.ok(hooksConfig.hooks, 'hooks.json 应包含 hooks 字段');
    });

    it('包含 Stop hook 类型', () => {
      assert.ok(hooksConfig.hooks.Stop, 'hooks.json 应包含 Stop hook');
    });

    it('包含 WorktreeCreate hook 类型', () => {
      assert.ok(hooksConfig.hooks.WorktreeCreate, 'hooks.json 应包含 WorktreeCreate hook');
    });

    it('包含 WorktreeRemove hook 类型', () => {
      assert.ok(hooksConfig.hooks.WorktreeRemove, 'hooks.json 应包含 WorktreeRemove hook');
    });
  });

  // ─── 4. WorktreeCreate hook 配置 ───
  describe('WorktreeCreate hook 配置', () => {
    let createHooks;

    it('WorktreeCreate hook 存在且为数组', () => {
      const raw = readFileSync(resolve(autopilotRoot, 'hooks/hooks.json'), 'utf8');
      const config = JSON.parse(raw);
      createHooks = config.hooks.WorktreeCreate;
      assert.ok(Array.isArray(createHooks), 'WorktreeCreate 应为数组');
      assert.ok(createHooks.length > 0, 'WorktreeCreate 应至少有一个条目');
    });

    it('timeout 为 300', () => {
      const entry = createHooks[0];
      const hook = entry.hooks ? entry.hooks[0] : entry;
      assert.equal(hook.timeout, 300, 'WorktreeCreate timeout 应为 300');
    });

    it('命令包含 worktree.mjs create', () => {
      const entry = createHooks[0];
      const hook = entry.hooks ? entry.hooks[0] : entry;
      assert.ok(
        hook.command.includes('worktree.mjs') && hook.command.includes('create'),
        `WorktreeCreate 命令应包含 "worktree.mjs" 和 "create"，实际: ${hook.command}`
      );
    });
  });

  // ─── 5. WorktreeRemove hook 配置 ───
  describe('WorktreeRemove hook 配置', () => {
    let removeHooks;

    it('WorktreeRemove hook 存在且为数组', () => {
      const raw = readFileSync(resolve(autopilotRoot, 'hooks/hooks.json'), 'utf8');
      const config = JSON.parse(raw);
      removeHooks = config.hooks.WorktreeRemove;
      assert.ok(Array.isArray(removeHooks), 'WorktreeRemove 应为数组');
      assert.ok(removeHooks.length > 0, 'WorktreeRemove 应至少有一个条目');
    });

    it('timeout 为 60', () => {
      const entry = removeHooks[0];
      const hook = entry.hooks ? entry.hooks[0] : entry;
      assert.equal(hook.timeout, 60, 'WorktreeRemove timeout 应为 60');
    });

    it('命令包含 worktree.mjs remove', () => {
      const entry = removeHooks[0];
      const hook = entry.hooks ? entry.hooks[0] : entry;
      assert.ok(
        hook.command.includes('worktree.mjs') && hook.command.includes('remove'),
        `WorktreeRemove 命令应包含 "worktree.mjs" 和 "remove"，实际: ${hook.command}`
      );
    });
  });

  // ─── 6. plugin.json 版本 ───
  describe('plugin.json 版本', () => {
    it('version 为 "3.0.0"', () => {
      const raw = readFileSync(resolve(autopilotRoot, '.claude-plugin/plugin.json'), 'utf8');
      const plugin = JSON.parse(raw);
      assert.equal(plugin.version, '3.0.0', 'autopilot plugin.json version 应为 3.0.0');
    });
  });

  // ─── 7. repair SKILL.md frontmatter ───
  describe('repair SKILL.md', () => {
    it('frontmatter name 为 "worktree-repair"', () => {
      const content = readFileSync(
        resolve(autopilotRoot, 'skills/worktree-repair/SKILL.md'),
        'utf8'
      );
      // 匹配 YAML frontmatter 中的 name 字段
      const nameMatch = content.match(/^---[\s\S]*?name:\s*(.+?)[\s]*$/m);
      assert.ok(nameMatch, 'SKILL.md 应包含 name frontmatter');
      assert.equal(
        nameMatch[1].trim().replace(/^["']|["']$/g, ''),
        'worktree-repair',
        'SKILL.md name 应为 worktree-repair'
      );
    });
  });

  // ─── 8. marketplace.json ───
  describe('marketplace.json', () => {
    let marketplace;

    it('marketplace.json 可解析', () => {
      const raw = readFileSync(resolve(projectRoot, '.claude-plugin/marketplace.json'), 'utf8');
      marketplace = JSON.parse(raw);
      assert.ok(marketplace.plugins || marketplace, 'marketplace.json 应可解析');
    });

    it('无 worktree-setup 条目', () => {
      const plugins = marketplace.plugins || marketplace;
      const names = Array.isArray(plugins)
        ? plugins.map(p => p.name || p.id)
        : Object.keys(plugins);
      assert.ok(
        !names.some(n => n === 'worktree-setup'),
        'marketplace.json 不应包含 worktree-setup 条目'
      );
    });

    it('autopilot version 为 "3.0.0"', () => {
      const plugins = marketplace.plugins || marketplace;
      const autopilot = Array.isArray(plugins)
        ? plugins.find(p => (p.name || p.id) === 'autopilot')
        : plugins.autopilot;
      assert.ok(autopilot, 'marketplace.json 应包含 autopilot 条目');
      assert.equal(
        autopilot.version,
        '3.0.0',
        'marketplace.json 中 autopilot version 应为 3.0.0'
      );
    });
  });

  // ─── 9. doctor SKILL.md 权重 ───
  describe('doctor SKILL.md 权重', () => {
    let doctorContent;

    it('doctor SKILL.md 可读取', () => {
      doctorContent = readFileSync(
        resolve(autopilotRoot, 'skills/autopilot-doctor/SKILL.md'),
        'utf8'
      );
      assert.ok(doctorContent.length > 0, 'doctor SKILL.md 应有内容');
    });

    it('Dim 8 权重包含 0.08', () => {
      // 查找 Dim 8 相关区域中的 0.08
      // Dim 8 通常是 Git Hooks / Git 相关维度
      assert.ok(
        doctorContent.includes('0.08'),
        'doctor SKILL.md 应包含权重 0.08（Dim 8）'
      );
    });

    it('Dim 9 权重包含 0.02', () => {
      assert.ok(
        doctorContent.includes('0.02'),
        'doctor SKILL.md 应包含权重 0.02（Dim 9）'
      );
    });
  });

  // ─── 10. doctor SKILL.md worktree 检查 ───
  describe('doctor SKILL.md worktree 检查', () => {
    it('包含 worktree 相关检查内容', () => {
      const content = readFileSync(
        resolve(autopilotRoot, 'skills/autopilot-doctor/SKILL.md'),
        'utf8'
      );
      const lowerContent = content.toLowerCase();
      assert.ok(
        lowerContent.includes('worktree'),
        'doctor SKILL.md 应包含 worktree 相关检查'
      );
    });
  });

  // ─── 11. doctor --fix worktree 修复方案 ───
  describe('doctor --fix worktree 修复方案', () => {
    it('包含 worktree-links 或 worktree repair 修复方案', () => {
      const content = readFileSync(
        resolve(autopilotRoot, 'skills/autopilot-doctor/SKILL.md'),
        'utf8'
      );
      const hasWorktreeLinks = content.includes('worktree-links');
      const hasWorktreeRepair = content.includes('worktree repair') ||
        content.includes('worktree-repair');
      assert.ok(
        hasWorktreeLinks || hasWorktreeRepair,
        'doctor SKILL.md --fix 部分应包含 worktree-links 或 worktree repair 修复方案'
      );
    });
  });

  // ─── 12. knowledge-engineering.md 引用更新 ───
  describe('knowledge-engineering.md 引用更新', () => {
    it('不包含 "by worktree-setup"', () => {
      const content = readFileSync(
        resolve(autopilotRoot, 'references/knowledge-engineering.md'),
        'utf8'
      );
      assert.ok(
        !content.includes('by worktree-setup'),
        'knowledge-engineering.md 不应包含 "by worktree-setup"（旧引用应已更新）'
      );
    });
  });

  // ─── 13. package.json test script 路径 ───
  describe('package.json test script', () => {
    it('测试路径引用 autopilot 而非 worktree-setup', () => {
      const raw = readFileSync(resolve(projectRoot, 'package.json'), 'utf8');
      const pkg = JSON.parse(raw);
      const testScript = pkg.scripts && pkg.scripts.test;
      assert.ok(testScript, 'package.json 应有 test script');
      assert.ok(
        !testScript.includes('worktree-setup'),
        `test script 不应引用 worktree-setup，实际: ${testScript}`
      );
      assert.ok(
        testScript.includes('autopilot'),
        `test script 应引用 autopilot 路径，实际: ${testScript}`
      );
    });
  });
});
