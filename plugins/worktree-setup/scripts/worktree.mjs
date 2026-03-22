#!/usr/bin/env node
// worktree.mjs — Claude Code worktree-setup plugin
// Unified entry: create / remove / repair
import { execSync, execFileSync } from 'child_process';
import { readFileSync, existsSync, mkdirSync, symlinkSync, lstatSync, unlinkSync, readdirSync, writeFileSync, realpathSync, rmSync } from 'fs';
import { join, basename, dirname, resolve } from 'path';
import { fileURLToPath } from 'url';

const log = (msg) => process.stderr.write(msg + '\n');

// Shell-safe: uses execFileSync (array args) to avoid injection
function git(...args) {
  return execFileSync('git', args, { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }).trim();
}

function gitSilent(...args) {
  try { return git(...args); } catch { return ''; }
}

function readStdin() {
  let raw;
  try {
    raw = readFileSync(0, 'utf8');
  } catch (e) {
    throw new Error(`无法读取 stdin: ${e.message}`);
  }
  try {
    return JSON.parse(raw);
  } catch (e) {
    throw new Error(`stdin 不是合法 JSON: ${e.message}`);
  }
}

function repoRoot(cwd) {
  // For worktrees, --show-toplevel returns the worktree root, not the main repo.
  // Use GIT_COMMON_DIR-based approach to always find the main repo root.
  try {
    const toplevel = git('-C', cwd, 'rev-parse', '--show-toplevel');
    // Check if this is a linked worktree by looking at .git (file, not dir)
    const dotGit = join(toplevel, '.git');
    try {
      const stat = lstatSync(dotGit);
      if (stat.isFile()) {
        // This is a worktree — .git is a file pointing to the main repo's .git/worktrees/<name>
        // Use --git-common-dir to find the real repo's .git, then go up one level
        const commonDir = git('-C', cwd, 'rev-parse', '--git-common-dir');
        const resolved = resolve(toplevel, commonDir);
        return dirname(resolved); // .git dir → parent = repo root
      }
    } catch { /* .git doesn't exist or can't stat — just return toplevel */ }
    return toplevel;
  } catch {
    return git('rev-parse', '--show-toplevel');
  }
}

// ─── Name sanitize ───
export function sanitizeName(raw) {
  return raw
    .replace(/\s/g, '-')
    .replace(/[^a-zA-Z0-9\u4e00-\u9fff._/-]/g, '-')
    .replace(/-{2,}/g, '-')
    .replace(/^-/, '')
    .replace(/-$/, '');
}

// ─── Deterministic port: hash(branch) → 4001-4999 ───
export function computePort(branch) {
  let h = 0;
  for (let i = 0; i < branch.length; i++) h = (h * 31 + branch.charCodeAt(i)) >>> 0;
  return 4001 + (h % 999);
}

// ─── Parse worktree-links file ───
export function parseLinksFile(filepath) {
  if (!existsSync(filepath)) return [];
  return readFileSync(filepath, 'utf8')
    .split('\n')
    .filter(line => line.trim() && !/^\s*#/.test(line))
    .map(line => line.trim());
}

// ─── REPAIR ───
function repair(worktreePath) {
  const root = repoRoot(worktreePath);
  log(`→ 修复 worktree: ${worktreePath}`);

  const linksFile = join(root, '.claude', 'worktree-links');
  const links = parseLinksFile(linksFile);

  if (links.length > 0) {
    log('→ 按 .claude/worktree-links 创建符号链接...');
    for (const file of links) {
      const src = join(root, file);
      const dst = join(worktreePath, file);
      const srcExists = existsSync(src);
      let dstExists = false;
      let dstIsLink = false;
      try { dstIsLink = lstatSync(dst).isSymbolicLink(); dstExists = true; } catch { /* not found */ }
      if (!dstExists) dstExists = existsSync(dst);

      if (srcExists && !dstExists) {
        const dir = dirname(dst);
        if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
        symlinkSync(src, dst);
        log(`   ✓ 链接: ${file}`);
      } else if (dstIsLink) {
        log(`   — 已存在: ${file}`);
      } else if (!srcExists) {
        log(`   ⚠ 跳过（源文件不存在）: ${file}`);
      } else {
        log(`   — 已存在: ${file}`);
      }
    }
  } else {
    log('→ 无 .claude/worktree-links，自动链接 .env* 文件...');
    try {
      const entries = readdirSync(root).filter(f => f.startsWith('.env'));
      for (const file of entries) {
        const src = join(root, file);
        const dst = join(worktreePath, file);
        try {
          if (!lstatSync(src).isFile()) continue;
        } catch { continue; }
        if (!existsSync(dst)) {
          symlinkSync(src, dst);
          log(`   ✓ ${file}（自动）`);
        }
      }
    } catch { /* no .env files */ }
  }

  // ─── Knowledge directory symlink (always-link) ───
  // Knowledge is conceptually shared across all worktrees
  const knowledgeSrc = join(root, '.claude', 'knowledge');
  const knowledgeDst = join(worktreePath, '.claude', 'knowledge');
  if (existsSync(knowledgeSrc)) {
    try {
      const stat = lstatSync(knowledgeDst);
      if (stat.isSymbolicLink()) {
        log('   — .claude/knowledge 已是符号链接');
      } else if (stat.isDirectory()) {
        // Replace git-checked-out copy with symlink to main repo
        log('→ 替换 .claude/knowledge 为符号链接（指向主仓库）...');
        rmSync(knowledgeDst, { recursive: true, force: true });
        symlinkSync(knowledgeSrc, knowledgeDst);
        log('   ✓ .claude/knowledge → 主仓库');
      }
    } catch (e) {
      // knowledgeDst doesn't exist — check if parent dir exists and create symlink
      if (e.code === 'ENOENT') {
        const dir = dirname(knowledgeDst);
        if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
        symlinkSync(knowledgeSrc, knowledgeDst);
        log('   ✓ .claude/knowledge → 主仓库');
      } else {
        log(`   ⚠ 无法检查 .claude/knowledge: ${e.message}`);
      }
    }
  }

  // Install dependencies
  const nodeModules = join(worktreePath, 'node_modules');
  if (!existsSync(nodeModules)) {
    log('→ 安装依赖（自动识别包管理器）...');
    const execOpts = { cwd: worktreePath, stdio: ['pipe', 'pipe', 'inherit'] };
    try {
      if (existsSync(join(worktreePath, 'pnpm-lock.yaml'))) {
        execSync('pnpm install', execOpts);
      } else if (existsSync(join(worktreePath, 'yarn.lock'))) {
        execSync('yarn install', execOpts);
      } else {
        execSync('npm install', execOpts);
      }
    } catch (e) {
      log(`   ⚠ 依赖安装失败: ${e.message}`);
    }
  } else {
    log('→ node_modules 已存在，跳过安装');
  }

  // Prisma generate
  if (existsSync(join(worktreePath, 'prisma'))) {
    log('→ 检测到 prisma 目录，执行 prisma generate...');
    try {
      execSync('npx prisma generate', { cwd: worktreePath, stdio: ['pipe', 'pipe', 'inherit'] });
    } catch (e) {
      log(`   ⚠ prisma generate 失败: ${e.message}`);
    }
  }

  log('✅ 修复完成');
}

// ─── CREATE ───
function create() {
  const input = readStdin();
  log(`→ stdin: ${JSON.stringify({ name: input.name, cwd: input.cwd, hook_event_name: input.hook_event_name })}`);
  if (!input.name) throw new Error('stdin JSON 缺少 name 字段');
  const name = sanitizeName(input.name);
  if (!name) throw new Error(`名称清洗后为空: ${JSON.stringify(input.name)}`);

  // Use cwd from stdin (Claude Code passes it), fallback to process.cwd()
  const cwd = input.cwd || process.cwd();
  const root = repoRoot(cwd);
  const worktreePath = join(root, '.claude', 'worktrees', name);
  const branch = `worktree-${name}`;

  log(`→ 创建 worktree: ${name} (分支: ${branch}, root: ${root})`);

  // If worktree path already exists, skip creation and just repair
  if (existsSync(worktreePath)) {
    log(`→ worktree 路径已存在，跳过创建，直接修复`);
  } else {
    // Clean up stale branch if it exists (from previous failed attempts)
    const staleBranch = gitSilent('-C', root, 'rev-parse', '--verify', `refs/heads/${branch}`);
    if (staleBranch) {
      log(`→ 清理残留分支: ${branch}`);
      gitSilent('-C', root, 'branch', '-D', branch);
    }

    // Detect default branch from origin
    let created = false;
    const hasOrigin = gitSilent('-C', root, 'remote', 'show', 'origin');
    if (hasOrigin) {
      const headLine = hasOrigin.split('\n').find(l => l.includes('HEAD branch:'));
      const defaultBranch = headLine ? headLine.replace(/.*HEAD branch:\s*/, '').trim() : '';
      if (defaultBranch) {
        try {
          git('-C', root, 'fetch', 'origin', defaultBranch);
          git('-C', root, 'worktree', 'add', worktreePath, '-b', branch, `origin/${defaultBranch}`);
          created = true;
        } catch (e) {
          log(`   ⚠ 基于 origin/${defaultBranch} 创建失败: ${e.message}`);
        }
      }
    }

    if (!created) {
      log('→ 无 origin remote 或无法检测默认分支，基于当前 HEAD 创建');
      git('-C', root, 'worktree', 'add', worktreePath, '-b', branch, 'HEAD');
    }
  }

  // Repair: symlinks + deps
  repair(worktreePath);

  // Deterministic port
  const port = computePort(branch);
  log(`→ 分配端口: ${port}`);
  writeFileSync(
    join(worktreePath, 'local-config.json'),
    JSON.stringify({ server: { devPort: port, hostname: 'localhost', enableHttps: false } }) + '\n'
  );

  log(`✅ Worktree 就绪，dev 端口: ${port}`);
  process.stdout.write(worktreePath); // Only stdout — Claude reads this
}

// ─── REMOVE ───
function remove() {
  const input = readStdin();
  const worktreePath = input.worktree_path;
  if (!worktreePath) throw new Error('stdin JSON 缺少 worktree_path 字段');
  log(`→ 清理 worktree: ${worktreePath}`);

  const cwd = input.cwd || process.cwd();
  const root = repoRoot(cwd);
  const linksFile = join(root, '.claude', 'worktree-links');
  const links = parseLinksFile(linksFile);

  // Remove symlinks first (avoid git worktree remove error on tracked files)
  if (links.length > 0) {
    for (const file of links) {
      const dst = join(worktreePath, file);
      try {
        if (lstatSync(dst).isSymbolicLink()) {
          unlinkSync(dst);
          log(`   ✓ 移除符号链接: ${file}`);
        }
      } catch { /* not a symlink or doesn't exist */ }
    }
  } else {
    // Fallback: scan .env*
    try {
      const entries = readdirSync(worktreePath).filter(f => f.startsWith('.env'));
      for (const file of entries) {
        const dst = join(worktreePath, file);
        try {
          if (lstatSync(dst).isSymbolicLink()) {
            unlinkSync(dst);
          }
        } catch { /* ignore */ }
      }
    } catch { /* dir may not exist */ }
  }

  // Clean up .claude/knowledge symlink
  const knowledgePath = join(worktreePath, '.claude', 'knowledge');
  try {
    if (lstatSync(knowledgePath).isSymbolicLink()) {
      unlinkSync(knowledgePath);
      log('   ✓ 移除符号链接: .claude/knowledge');
    }
  } catch { /* not a symlink or doesn't exist */ }

  // Remove local-config.json
  const configPath = join(worktreePath, 'local-config.json');
  if (existsSync(configPath)) unlinkSync(configPath);

  // Get branch name before removing worktree
  const branch = gitSilent('-C', worktreePath, 'rev-parse', '--abbrev-ref', 'HEAD');

  // Remove worktree
  git('worktree', 'remove', '--force', worktreePath);

  // Delete branch (unless main/HEAD)
  if (branch && branch !== 'main' && branch !== 'HEAD') {
    try {
      git('branch', '-D', branch);
      log(`   ✓ 分支已删除: ${branch}`);
    } catch { /* branch may not exist */ }
  }

  log('✅ 清理完成');
}

// ─── Main (only when run directly, not when imported) ───
// Use realpathSync to resolve symlinks — .claude/plugins/ may be a symlink to .claude/.shared-plugins/
const __filename = realpathSync(fileURLToPath(import.meta.url));
const argv1Real = process.argv[1] ? realpathSync(resolve(process.argv[1])) : '';
if (argv1Real === __filename) {
  const subcmd = process.argv[2];

  try {
    switch (subcmd) {
      case 'create':
        create();
        break;
      case 'remove':
        remove();
        break;
      case 'repair':
        repair(process.argv[3] || process.cwd());
        break;
      default:
        log(`用法: node worktree.mjs <create|remove|repair> [worktree_path]`);
        process.exit(1);
    }
  } catch (e) {
    log(`❌ 错误: ${e.message}`);
    process.exit(1);
  }
}
