#!/usr/bin/env node
// worktree.mjs — autopilot worktree module
// Unified entry: create / remove / repair
import { execSync, execFileSync } from 'child_process';
import { readFileSync, existsSync, mkdirSync, symlinkSync, lstatSync, unlinkSync, readdirSync, writeFileSync, realpathSync, rmSync, renameSync } from 'fs';
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

// ─── Selective .autopilot layout ───
// 仅这些项以 symlink → 主仓库共享；其余（含 sessions/）皆 worktree-local 真实文件。
// 顺序：常用 → 不常用，便于 log 阅读。
export const SHARED_AUTOPILOT_ITEMS = [
  'decisions.md',
  'patterns.md',
  'index.md',
  'domains',
  'project',
  'requirements',
  'doctor-report.md',
  'worktree-links',
  'active',
  'autopilot.local.md',
];

// 把 worktree 的 .autopilot 配置成"选择性 symlink"布局：
//   .autopilot/                  ← 真实目录
//   .autopilot/sessions/<name>/  ← 真实目录（worktree-local，提交到 worktree 分支）
//   .autopilot/<shared item>     ← symlink → 主仓库 .autopilot/<shared item>
//
// 旧版兼容：如果 .autopilot 整体是全量 symlink，先把 main 里属于本 worktree 的
// sessions 子目录暂存到 worktree 内，重建后再放回 sessions/<name>/。
export function ensureSelectiveAutopilotLayout(mainRoot, worktreePath) {
  const apSrc = join(mainRoot, '.autopilot');
  const apDst = join(worktreePath, '.autopilot');

  if (!existsSync(apSrc)) {
    log('→ 主仓库无 .autopilot，预创建...');
    mkdirSync(apSrc, { recursive: true });
  }

  let dstStat = null;
  try { dstStat = lstatSync(apDst); } catch { /* not exists */ }

  // 旧版迁移：worktree/.autopilot 是全量 symlink
  let stashedSessions = null;
  if (dstStat?.isSymbolicLink()) {
    const wtName = basename(worktreePath);
    const mainWtSession = join(apSrc, 'sessions', wtName);
    if (existsSync(mainWtSession)) {
      stashedSessions = join(worktreePath, `.autopilot-sessions-stash-${process.pid}`);
      log(`→ 迁移 main/.autopilot/sessions/${wtName}/ → worktree（暂存到 ${basename(stashedSessions)}）`);
      try {
        renameSync(mainWtSession, stashedSessions);
      } catch (e) {
        log(`   ⚠ 暂存失败，跳过迁移: ${e.message}`);
        stashedSessions = null;
      }
    }
    log('→ 移除旧版 .autopilot 全量 symlink，重建为真实目录');
    unlinkSync(apDst);
    dstStat = null;
  }

  if (!existsSync(apDst)) mkdirSync(apDst, { recursive: true });

  // 共享项：替换为 symlink → 主仓库
  for (const item of SHARED_AUTOPILOT_ITEMS) {
    const src = join(apSrc, item);
    const dst = join(apDst, item);
    if (!existsSync(src)) continue; // main 没这一项就跳过

    let s = null;
    try { s = lstatSync(dst); } catch { /* not exists */ }

    if (s?.isSymbolicLink()) {
      // 已是 symlink — 检查是否指对了
      let needsFix = false;
      try {
        if (realpathSync(dst) !== realpathSync(src)) needsFix = true;
      } catch { needsFix = true; /* broken symlink */ }
      if (!needsFix) continue;
      unlinkSync(dst);
    } else if (s) {
      // 真实文件/目录（来自分支 checkout）— 保护：内容一致才静默替换，否则 rename 到备份
      let canDiscard = false;
      if (s.isFile()) {
        try {
          const dstBuf = readFileSync(dst);
          const srcBuf = readFileSync(src);
          canDiscard = dstBuf.equals(srcBuf);
        } catch { /* 比对失败按冲突处理 */ }
      }

      if (canDiscard) {
        log(`→ .autopilot/${item}（与主仓库内容一致）替换为符号链接`);
        rmSync(dst, { recursive: true, force: true });
      } else {
        const ts = Date.now();
        const conflictName = `.autopilot-conflict-${item.replace(/\//g, '-')}-${ts}`;
        const conflictPath = join(worktreePath, conflictName);
        log(`   ⚠ .autopilot/${item} 是真实文件/目录（与主仓库不一致或为目录）`);
        log(`     备份到 ${conflictName}，再建立 symlink。请手动 diff/合并`);
        try {
          renameSync(dst, conflictPath);
        } catch (e) {
          log(`   ⚠ 备份失败 (${e.message})；保留原状，跳过此项 symlink`);
          continue;
        }
      }
    }
    symlinkSync(src, dst);
    log(`   ✓ .autopilot/${item} → 主仓库`);
  }

  // sessions/ 必须是 worktree-local 真实目录
  const sessionsDir = join(apDst, 'sessions');
  let sessStat = null;
  try { sessStat = lstatSync(sessionsDir); } catch { /* not exists */ }
  if (sessStat?.isSymbolicLink()) {
    log('→ sessions/ 是 symlink，移除（应为 worktree-local 真实目录）');
    unlinkSync(sessionsDir);
  }
  if (!existsSync(sessionsDir)) mkdirSync(sessionsDir, { recursive: true });

  // 还原暂存的 sessions
  if (stashedSessions && existsSync(stashedSessions)) {
    const wtName = basename(worktreePath);
    const finalSession = join(sessionsDir, wtName);
    if (existsSync(finalSession)) {
      log(`   ⚠ sessions/${wtName}/ 已存在，stash 保留在 ${stashedSessions}（请手动合并）`);
    } else {
      try {
        renameSync(stashedSessions, finalSession);
        log(`   ✓ 还原 sessions/${wtName}/ 到 worktree`);
      } catch (e) {
        log(`   ⚠ 还原 sessions 失败: ${e.message}（stash 保留在 ${stashedSessions}）`);
      }
    }
  }
}

// ─── Write local-config.json (idempotent, worktree-only) ───
// 仅当 worktreePath 是 worktree（.git 是文件）且 local-config.json 不存在时写入
function writeLocalConfig(worktreePath) {
  const dotGit = join(worktreePath, '.git');
  let isWorktree = false;
  try { isWorktree = lstatSync(dotGit).isFile(); } catch { /* not worktree */ }
  if (!isWorktree) return;

  const configPath = join(worktreePath, 'local-config.json');
  if (existsSync(configPath)) {
    log('→ local-config.json 已存在，跳过');
    return;
  }

  const branch = gitSilent('-C', worktreePath, 'rev-parse', '--abbrev-ref', 'HEAD');
  if (!branch || branch === 'HEAD') {
    log('   ⚠ 无法获取 worktree 分支名，跳过 local-config.json');
    return;
  }
  const port = computePort(branch);
  writeFileSync(
    configPath,
    JSON.stringify({ server: { devPort: port, hostname: 'localhost', enableHttps: false } }) + '\n'
  );
  log(`→ 写入 local-config.json (端口: ${port})`);
}

// ─── REPAIR ───
function repair(worktreePath) {
  const root = repoRoot(worktreePath);
  log(`→ 修复 worktree: ${worktreePath}`);

  const linksFile = join(root, '.autopilot', 'worktree-links');
  const links = parseLinksFile(linksFile);

  if (links.length > 0) {
    log('→ 按 .autopilot/worktree-links 创建符号链接...');
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
    log('→ 无 .autopilot/worktree-links，自动链接 .env* 文件...');
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

  // ─── Selective .autopilot symlinks ───
  // sessions/ 是 worktree-local；knowledge/project/requirements 等共享项 symlink → main
  ensureSelectiveAutopilotLayout(root, worktreePath);

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

  // local-config.json (dev 端口) — 幂等写入，仅当 worktree 且文件不存在
  writeLocalConfig(worktreePath);

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

  // Repair: symlinks + deps + local-config.json（幂等，含端口分配）
  repair(worktreePath);

  log('✅ Worktree 就绪');
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
  const linksFile = join(root, '.autopilot', 'worktree-links');
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

  // Clean up .autopilot symlinks
  // 新模式：.autopilot 是真实目录，里面每个 SHARED_AUTOPILOT_ITEMS 是 symlink；逐个 unlink。
  // 旧模式（兼容）：.autopilot 整体是 symlink。
  const apDst = join(worktreePath, '.autopilot');
  let apIsLink = false;
  try { apIsLink = lstatSync(apDst).isSymbolicLink(); } catch { /* not exists */ }

  if (apIsLink) {
    unlinkSync(apDst);
    log('   ✓ 移除符号链接: .autopilot（旧版全量 symlink）');
  } else if (existsSync(apDst)) {
    for (const item of SHARED_AUTOPILOT_ITEMS) {
      const link = join(apDst, item);
      try {
        if (lstatSync(link).isSymbolicLink()) {
          unlinkSync(link);
          log(`   ✓ 移除符号链接: .autopilot/${item}`);
        }
      } catch { /* not symlink or missing */ }
    }
  }

  // 旧模式遗留：main/.autopilot/sessions/<name>/ 清理
  // 新模式下 sessions 已经在 worktree 里，这条不会触发；保留作为旧版兼容。
  const worktreeName = basename(worktreePath);
  const legacyMainSession = join(root, '.autopilot', 'sessions', worktreeName);
  if (existsSync(legacyMainSession)) {
    try {
      rmSync(legacyMainSession, { recursive: true, force: true });
      log(`   ✓ 清理旧版 main/.autopilot/sessions/${worktreeName}/`);
    } catch (e) {
      log(`   ⚠ 无法清理: ${e.message}`);
    }
  }

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
