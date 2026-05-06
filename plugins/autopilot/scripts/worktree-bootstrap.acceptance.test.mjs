/**
 * Acceptance tests for worktree-bootstrap.sh
 *
 * Red-team verification: tests are written purely from the design document
 * (HANDOFF-worktree-sessionstart-fallback.md), without reading the blue-team
 * implementation.
 *
 * Design contract reference:
 *   - Script: plugins/autopilot/scripts/worktree-bootstrap.sh
 *   - Triggered by SessionStart hook in plugin hooks.json
 *   - Input: JSON via stdin {session_id, cwd, hook_event_name, ...}
 *   - Output: stderr only; stdout is always empty
 *   - Exit code: always 0 (never blocks session startup)
 *
 * Run: node --test plugins/autopilot/scripts/worktree-bootstrap.acceptance.test.mjs
 */

import { describe, it, after } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import {
  mkdtemp, rm, mkdir, writeFile, symlink, readFile,
} from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const execFileAsync = promisify(execFile);
const __dirname = dirname(fileURLToPath(import.meta.url));
const SCRIPT = resolve(__dirname, 'worktree-bootstrap.sh');

// ---------------------------------------------------------------------------
// Helper: 调用 worktree-bootstrap.sh，传入 stdin JSON payload
// 返回 { exitCode, stdout, stderr }
// ---------------------------------------------------------------------------
async function runBootstrap({ cwdPayload, env = {} } = {}) {
  const stdinJson = cwdPayload !== undefined
    ? JSON.stringify({ session_id: 'test-session', cwd: cwdPayload, hook_event_name: 'SessionStart' })
    : '';

  return new Promise((resolve_) => {
    const child = execFile(
      'bash',
      [SCRIPT],
      {
        env: { ...process.env, ...env },
        // We do NOT set cwd here intentionally — tests inject cwd via JSON payload
      },
      (err, stdout, stderr) => {
        resolve_({
          exitCode: err ? err.code ?? 1 : 0,
          stdout,
          stderr,
        });
      }
    );

    if (stdinJson) {
      child.stdin.write(stdinJson);
    }
    child.stdin.end();
  });
}

// ---------------------------------------------------------------------------
// Helper: 建临时目录（每个测试独立），测试完毕后清理
// ---------------------------------------------------------------------------
async function makeTempDir(prefix) {
  return mkdtemp(join(tmpdir(), `wt-bootstrap-${prefix}-`));
}

// ---------------------------------------------------------------------------
// 跟踪所有建的临时目录，统一在 after() 清理
// ---------------------------------------------------------------------------
const tempDirs = [];
after(async () => {
  await Promise.all(tempDirs.map((d) => rm(d, { recursive: true, force: true })));
});

// ===========================================================================
// 场景 1：主仓库 session（.git 是目录）
// 期望：exit 0，stderr 无 [autopilot] 输出
// ===========================================================================
describe('场景 1：主仓库 session — .git 是目录', () => {
  it('exit 0 且 stderr 无 [autopilot] 输出', async () => {
    const tmpDir = await makeTempDir('main');
    tempDirs.push(tmpDir);

    // 模拟主仓库：.git 是目录（而非文件）
    await mkdir(join(tmpDir, '.git'), { recursive: true });

    // CLAUDE_PLUGIN_ROOT 指向插件目录（场景 1 不会到达 repair 步骤，随意即可）
    const result = await runBootstrap({
      cwdPayload: tmpDir,
      env: { CLAUDE_PLUGIN_ROOT: dirname(__dirname) },
    });

    // 验证 1：exit code 必须是 0
    assert.equal(result.exitCode, 0, `期望 exit 0，实际 exit ${result.exitCode}`);

    // 验证 2：stdout 永远为空
    assert.equal(result.stdout, '', `stdout 必须为空，实际: ${result.stdout}`);

    // 验证 3：stderr 不含 [autopilot] 输出
    assert.ok(
      !result.stderr.includes('[autopilot]'),
      `主仓库场景 stderr 不应有 [autopilot] 输出，实际: ${result.stderr}`
    );
  });
});

// ===========================================================================
// 场景 2：已配好的 worktree（.git 是文件 + .autopilot 是 symlink + node_modules 存在）
// 期望：exit 0，stderr 无 [autopilot] 输出（幂等 silent exit）
// ===========================================================================
describe('场景 2：已配好 worktree — silent exit', () => {
  it('exit 0 且 stderr 无 [autopilot] 输出', async () => {
    const tmpDir = await makeTempDir('configured');
    tempDirs.push(tmpDir);

    // 模拟 worktree：.git 是文件（worktree 的标志）
    await writeFile(join(tmpDir, '.git'), 'gitdir: /some/main/repo/.git/worktrees/configured');

    // 模拟 .autopilot 是 symlink（目标目录不必真实存在，symlink 存在即可）
    // 建一个真实目标避免 broken symlink 引发问题
    const fakeAutopilotTarget = join(tmpDir, '_autopilot_target');
    await mkdir(fakeAutopilotTarget, { recursive: true });
    await symlink(fakeAutopilotTarget, join(tmpDir, '.autopilot'));

    // 模拟 node_modules 存在
    await mkdir(join(tmpDir, 'node_modules'), { recursive: true });

    const result = await runBootstrap({
      cwdPayload: tmpDir,
      env: { CLAUDE_PLUGIN_ROOT: dirname(__dirname) },
    });

    // 验证 1：exit 0
    assert.equal(result.exitCode, 0, `期望 exit 0，实际 exit ${result.exitCode}`);

    // 验证 2：stdout 永远为空
    assert.equal(result.stdout, '', `stdout 必须为空，实际: ${result.stdout}`);

    // 验证 3：stderr 无 [autopilot] 输出（幂等，不重复 repair）
    assert.ok(
      !result.stderr.includes('[autopilot]'),
      `已配好 worktree 场景 stderr 不应有 [autopilot] 输出，实际: ${result.stderr}`
    );
  });
});

// ===========================================================================
// 场景 3：裸 worktree（.git 是文件，但无 .autopilot symlink 或无 node_modules）
// 期望：exit 0，stderr 含 [autopilot] worktree 检测到未配置，调用 repair 子进程
// ===========================================================================
describe('场景 3：裸 worktree — 触发 repair', () => {
  it('exit 0，stderr 含检测到未配置，mock repair 被调用', async () => {
    const tmpDir = await makeTempDir('bare-wt');
    tempDirs.push(tmpDir);

    // 模拟 worktree：.git 是文件
    await writeFile(join(tmpDir, '.git'), 'gitdir: /some/main/repo/.git/worktrees/bare');

    // 无 .autopilot，无 node_modules → 裸 worktree

    // 建立 mock CLAUDE_PLUGIN_ROOT，里面放一个 fake worktree.mjs
    // mock 记录调用参数到 calllog 文件，然后 exit 0
    const mockPluginRoot = await makeTempDir('mock-plugin');
    tempDirs.push(mockPluginRoot);
    const mockScriptsDir = join(mockPluginRoot, 'scripts');
    await mkdir(mockScriptsDir, { recursive: true });

    const callLogFile = join(mockPluginRoot, 'repair-called.log');
    const mockWorktreeMjs = join(mockScriptsDir, 'worktree.mjs');

    // fake worktree.mjs（ES module）：把调用参数写入 calllog，然后正常退出
    await writeFile(mockWorktreeMjs, `import { writeFileSync } from 'fs';
const args = process.argv.slice(2);
writeFileSync(${JSON.stringify(callLogFile)}, args.join(' '), 'utf8');
process.exit(0);
`);

    const result = await runBootstrap({
      cwdPayload: tmpDir,
      env: { CLAUDE_PLUGIN_ROOT: mockPluginRoot },
    });

    // 验证 1：exit 0（即使 repair 成功，脚本本身也必须 exit 0）
    assert.equal(result.exitCode, 0, `期望 exit 0，实际 exit ${result.exitCode}`);

    // 验证 2：stdout 永远为空
    assert.equal(result.stdout, '', `stdout 必须为空，实际: ${result.stdout}`);

    // 验证 3：stderr 必须含 [autopilot] worktree 检测到未配置
    assert.ok(
      result.stderr.includes('[autopilot]') && result.stderr.includes('未配置'),
      `裸 worktree 场景 stderr 应含 "[autopilot]...未配置"，实际: ${result.stderr}`
    );

    // 验证 4：mock repair 被调用（calllog 文件存在）
    assert.ok(
      existsSync(callLogFile),
      `repair 子进程应被调用，mock calllog 文件应存在: ${callLogFile}`
    );

    // 验证 5：repair 调用参数应包含 "repair" 子命令和 cwd 路径
    const callLog = await readFile(callLogFile, 'utf8');
    assert.ok(
      callLog.includes('repair'),
      `repair 调用参数应包含 "repair"，实际: ${callLog}`
    );
    assert.ok(
      callLog.includes(tmpDir),
      `repair 调用参数应包含 cwd 路径 ${tmpDir}，实际: ${callLog}`
    );
  });

  it('已有 .autopilot 目录但无 node_modules 时也触发 repair', async () => {
    const tmpDir = await makeTempDir('bare-no-nm');
    tempDirs.push(tmpDir);

    // worktree：.git 是文件
    await writeFile(join(tmpDir, '.git'), 'gitdir: /some/main/repo/.git/worktrees/bare2');

    // .autopilot 是真实目录（而非 symlink）→ 未配好
    await mkdir(join(tmpDir, '.autopilot'), { recursive: true });
    // 无 node_modules

    const mockPluginRoot = await makeTempDir('mock-plugin-2');
    tempDirs.push(mockPluginRoot);
    const mockScriptsDir = join(mockPluginRoot, 'scripts');
    await mkdir(mockScriptsDir, { recursive: true });

    const callLogFile = join(mockPluginRoot, 'repair-called.log');
    await writeFile(join(mockScriptsDir, 'worktree.mjs'), `import { writeFileSync } from 'fs';
writeFileSync(${JSON.stringify(callLogFile)}, process.argv.slice(2).join(' '), 'utf8');
process.exit(0);
`);

    const result = await runBootstrap({
      cwdPayload: tmpDir,
      env: { CLAUDE_PLUGIN_ROOT: mockPluginRoot },
    });

    assert.equal(result.exitCode, 0);
    assert.equal(result.stdout, '');
    assert.ok(
      result.stderr.includes('[autopilot]'),
      `有 .autopilot 目录但无 node_modules 时应触发 repair，stderr: ${result.stderr}`
    );
    assert.ok(existsSync(callLogFile), 'repair mock 应被调用');
  });
});

// ===========================================================================
// 场景 4：裸 worktree + repair 失败（worktree.mjs 返回非 0）
// 期望：exit 0（不阻断 session），stderr 含 [autopilot] 和 "repair 失败"
// ===========================================================================
describe('场景 4：裸 worktree + repair 失败 — exit 0 不阻断', () => {
  it('repair 失败时 exit 0，stderr 含 repair 失败提示', async () => {
    const tmpDir = await makeTempDir('repair-fail');
    tempDirs.push(tmpDir);

    // 模拟裸 worktree
    await writeFile(join(tmpDir, '.git'), 'gitdir: /some/main/repo/.git/worktrees/fail-wt');
    // 无 .autopilot symlink，无 node_modules

    // 建立 mock CLAUDE_PLUGIN_ROOT，fake worktree.mjs 故意 exit 1
    const mockPluginRoot = await makeTempDir('mock-plugin-fail');
    tempDirs.push(mockPluginRoot);
    const mockScriptsDir = join(mockPluginRoot, 'scripts');
    await mkdir(mockScriptsDir, { recursive: true });

    const callLogFile = join(mockPluginRoot, 'repair-called.log');
    await writeFile(join(mockScriptsDir, 'worktree.mjs'), `import { writeFileSync } from 'fs';
// 记录调用，然后模拟失败
writeFileSync(${JSON.stringify(callLogFile)}, process.argv.slice(2).join(' '), 'utf8');
process.exit(1);  // 模拟 repair 失败
`);

    const result = await runBootstrap({
      cwdPayload: tmpDir,
      env: { CLAUDE_PLUGIN_ROOT: mockPluginRoot },
    });

    // 验证 1：即使 repair 失败，脚本本身必须 exit 0（不阻断 session）
    assert.equal(
      result.exitCode,
      0,
      `repair 失败时脚本仍必须 exit 0，实际 exit ${result.exitCode}`
    );

    // 验证 2：stdout 永远为空
    assert.equal(result.stdout, '', `stdout 必须为空，实际: ${result.stdout}`);

    // 验证 3：stderr 含检测到未配置的提示
    assert.ok(
      result.stderr.includes('[autopilot]'),
      `stderr 应含 [autopilot] 前缀，实际: ${result.stderr}`
    );

    // 验证 4：stderr 含 repair 失败的提示
    assert.ok(
      result.stderr.includes('repair') && (
        result.stderr.includes('失败') || result.stderr.includes('fail') || result.stderr.includes('error')
      ),
      `stderr 应含 repair 失败相关提示，实际: ${result.stderr}`
    );

    // 验证 5：mock repair 确实被调用了（不是从未触发）
    assert.ok(
      existsSync(callLogFile),
      `即使 repair 失败，mock 也应被调用过，calllog: ${callLogFile}`
    );
  });
});

// ===========================================================================
// 场景 5：非法 stdin JSON
// 期望：exit 0，fallback 到 pwd 判断（不崩溃）
// ===========================================================================
describe('场景 5：非法 stdin JSON — 优雅降级', () => {
  it('JSON 解析失败时 exit 0，不崩溃（fallback 到 pwd）', async () => {
    // 非法 JSON 时，脚本 fallback 到 pwd，我们在主仓库目录运行（.git 是目录），
    // 期望是 silent exit（和场景 1 相同结果）。
    const tmpDir = await makeTempDir('invalid-json-main');
    tempDirs.push(tmpDir);

    // 建主仓库结构
    await mkdir(join(tmpDir, '.git'), { recursive: true });

    const result = await new Promise((resolve_) => {
      const child = execFile(
        'bash',
        [SCRIPT],
        {
          env: {
            ...process.env,
            CLAUDE_PLUGIN_ROOT: dirname(__dirname),
          },
          cwd: tmpDir, // 设置 cwd 为主仓库目录，以便 fallback 到 pwd 时正确判定
        },
        (err, stdout, stderr) => {
          resolve_({
            exitCode: err ? err.code ?? 1 : 0,
            stdout,
            stderr,
          });
        }
      );

      // 写入非法 JSON
      child.stdin.write('{garbage: this is not valid json}');
      child.stdin.end();
    });

    // 验证 1：exit 0（即使 JSON 解析失败也不崩溃）
    assert.equal(
      result.exitCode,
      0,
      `非法 JSON 时脚本必须 exit 0，实际 exit ${result.exitCode}`
    );

    // 验证 2：stdout 永远为空
    assert.equal(result.stdout, '', `stdout 必须为空，实际: ${result.stdout}`);

    // 验证 3：不抛出未处理异常（exit 0 已经隐含这一点，但再显式断言 stderr 无 "Traceback" 类错误）
    // bash 脚本不会有 Traceback，但确保没有 node 未处理异常痕迹
    assert.ok(
      !result.stderr.includes('SyntaxError') || result.exitCode === 0,
      `JSON 解析错误应被静默处理，不影响 exit code，stderr: ${result.stderr}`
    );
  });

  it('stdin 为空时 exit 0，fallback 到 pwd', async () => {
    const tmpDir = await makeTempDir('empty-stdin-main');
    tempDirs.push(tmpDir);

    // 主仓库目录（.git 是目录）
    await mkdir(join(tmpDir, '.git'), { recursive: true });

    const result = await new Promise((resolve_) => {
      const child = execFile(
        'bash',
        [SCRIPT],
        {
          env: {
            ...process.env,
            CLAUDE_PLUGIN_ROOT: dirname(__dirname),
          },
          cwd: tmpDir,
        },
        (err, stdout, stderr) => {
          resolve_({
            exitCode: err ? err.code ?? 1 : 0,
            stdout,
            stderr,
          });
        }
      );

      // 空 stdin：直接关闭
      child.stdin.end();
    });

    // 验证：exit 0，不崩溃
    assert.equal(
      result.exitCode,
      0,
      `空 stdin 时脚本必须 exit 0，实际 exit ${result.exitCode}`
    );
    assert.equal(result.stdout, '', `stdout 必须为空，实际: ${result.stdout}`);
  });
});

// ===========================================================================
// 附加约束验证：stdout 永远为空（跨场景共用断言的补充说明性测试）
// ===========================================================================
describe('输出协议：stdout 永远为空', () => {
  it('主仓库场景 stdout 为空', async () => {
    const tmpDir = await makeTempDir('stdout-main');
    tempDirs.push(tmpDir);
    await mkdir(join(tmpDir, '.git'), { recursive: true });

    const result = await runBootstrap({
      cwdPayload: tmpDir,
      env: { CLAUDE_PLUGIN_ROOT: dirname(__dirname) },
    });

    assert.equal(result.stdout, '', 'SessionStart hook stdout 必须永远为空（主仓库场景）');
  });

  it('裸 worktree 场景 stdout 也为空', async () => {
    const tmpDir = await makeTempDir('stdout-bare');
    tempDirs.push(tmpDir);
    await writeFile(join(tmpDir, '.git'), 'gitdir: /some/.git/worktrees/x');

    // 用真实 plugin root，repair 大概率失败但不影响 stdout 断言
    const mockPluginRoot = await makeTempDir('mock-plugin-stdout');
    tempDirs.push(mockPluginRoot);
    const mockScriptsDir = join(mockPluginRoot, 'scripts');
    await mkdir(mockScriptsDir, { recursive: true });
    // fake worktree.mjs 输出一些内容到 stdout —— 验证脚本是否正确重定向
    await writeFile(join(mockScriptsDir, 'worktree.mjs'), `process.stdout.write('should-not-leak-to-parent-stdout\\n');
process.exit(0);
`);

    const result = await runBootstrap({
      cwdPayload: tmpDir,
      env: { CLAUDE_PLUGIN_ROOT: mockPluginRoot },
    });

    // 关键：即使 repair 子进程写 stdout，父脚本不应让它泄漏
    assert.equal(
      result.stdout,
      '',
      `裸 worktree 场景：repair 子进程的 stdout 不应泄漏到父脚本 stdout，实际: ${result.stdout}`
    );
  });
});
