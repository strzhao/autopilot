/**
 * ux-exploration channel 扩员 + UI 视觉质量全链路 验收测试（红队 T7）
 *
 * 红队验证：仅基于设计文档（state.md `## 目标` / `## 设计文档` / `## 验收场景`）编写，
 * 未读取蓝队本次改动内容；守卫函数调用范式（函数名 / 退出码 / 信号串）全部取自
 * 设计文档 `## 契约规约` 逐字字面量与任务起点前既有的五守卫 .sh 测试范式。
 *
 * 覆盖验收场景（SSOT = state.md `## 验收场景`，逐谓词映射）：
 *   场景1.P1 [det-machine]  lib.sh 合法集含 ux-exploration 字面量        → M3 组
 *   场景1.P2 [real-process] ux-exploration 合规谓词行 → channels rc0     → M3 组
 *   场景1.P3 [real-process] ux-exploration artifact 齐备 → coverage rc0  → M3 组
 *   场景2.P1~P3 [det-machine] visual-companion-guide.md 全保真/冻结锚点  → M1 组
 *   场景3.P1~P3 [det-machine] state-file-guide.md 视觉规格节锚点         → M2 组
 *   场景4.P1~P3 [det-machine] scenario-generator 双形态 + stop-hook 同步 → 场景4 组
 *   场景5.P1  [det-machine]  blue-team-prompt 冻结锚实现指引             → 场景5 组
 *   场景6.P1  [det-machine]  tests 树锚定 ux-exploration 守卫与负例      → T7 测试树锚点
 *   场景6.P2  [real-process] npm test 全量 exit=0：由本文件经 package.json
 *             挂接进 `npm test` + 五守卫 .sh 子进程组成件覆盖；「npm test 套
 *             npm test」为无限递归不可文件内编码，全量执行归 QA 求值时绑定
 *   场景7.P1/P2  ux-visial 非法 channel 拦截（rc2 + 信号串 + 字面量）     → T7 负例回归
 *   场景8.P1  [real-process] ux-exploration 缺 artifact → coverage rc2   → M3 组
 *   场景8.P2  [real-process] artifact 不存在/空文件 → artifacts rc2      → T7 负例回归
 *   场景8.P3  [real-process] node-script+网络关键字 → driver rc2         → T7 负例回归
 *   场景9.P1  [det-machine]  主 SKILL.md 相对 HEAD 零新增行              → T7 工程守恒
 *   场景9.P2  [real-process] shellcheck 全树 -S warning 零告警           → T7 工程守恒
 *
 * 执行时机说明：M1/M2/场景4/场景5/M3 各组的断言目标文件是蓝队交付物（uncommitted
 * in-flight），按编排器约束这些断言正常写成硬断言（绝不 skip / 绝不 try-catch 吞错），
 * 执行时机归 QA/合流后；T7 前缀各组任务起点即绿，任何时候都必须全绿。
 *
 * 反 tautological 设计（Mutation-Survival）：
 *   - 每个正向 rc0 断言必有配对负例（ux-visial rc2 / coverage gap rc2 / driver rc2），
 *     kill「守卫恒 rc0」与「守卫恒 rc2 + 信号串恒输出」双向 no-op mutation
 *   - 空文件（size=0）与不存在文件分别断 PRED-ARTIFACT-MISSING，kill 边界 mutation
 *   - 内容锚点用「改动前基线为 0 的新 token」（anchor-compare / ux-exploration /
 *     视觉规格）计数断言，蓝队不落地则必红
 *
 * Run: node --test tests/ux-exploration-channel.acceptance.test.mjs
 */

import { describe, it, after } from 'node:test';
import assert from 'node:assert/strict';
import {
  readFileSync,
  writeFileSync,
  existsSync,
  mkdtempSync,
  rmSync,
  readdirSync,
} from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import os from 'node:os';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');

const LIB_SH = resolve(ROOT, 'plugins/autopilot/scripts/lib.sh');
const STOP_HOOK_SH = resolve(ROOT, 'plugins/autopilot/scripts/stop-hook.sh');
const ACCEPTANCE_DIR = resolve(ROOT, 'plugins/autopilot/tests/acceptance');
const VISUAL_COMPANION_GUIDE = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot-brainstorm/references/visual-companion-guide.md'
);
const STATE_FILE_GUIDE = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot/references/state-file-guide.md'
);
const SCENARIO_GENERATOR = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot/references/scenario-generator-prompt.md'
);
const BLUE_TEAM_PROMPT = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot/references/blue-team-prompt.md'
);
const SKILL_MD = resolve(ROOT, 'plugins/autopilot/skills/autopilot/SKILL.md');

// 五守卫既有 .sh 测试（契约规约「回归测试闭集」，扩员后必须全绿不回归）。
// 顺序 = 编排器 T7 指定顺序。
const FIVE_GUARD_SH = [
  'predicate-channel-guard.acceptance.test.sh',
  'pred-coverage-guard.acceptance.test.sh',
  'predicate-driver-guard.acceptance.test.sh',
  'predicate-artifact-uniqueness-guard.acceptance.test.sh',
  'predicate-coverage.acceptance.test.sh',
];

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

const TMP_ROOT = mkdtempSync(join(os.tmpdir(), 't7-ux-exploration-'));
after(() => rmSync(TMP_ROOT, { recursive: true, force: true }));

/** 写 mock state.md（## 验收场景 区域 + fullwidth ｜ 谓词行，范式照搬五守卫 .sh） */
function writeMockState(name, scenarioLines) {
  const p = join(TMP_ROOT, name);
  writeFileSync(
    p,
    `---
active: true
phase: "qa"
gate: ""
iteration: 1
max_iterations: 30
max_retries: 3
retry_count: 0
task_dir: ""
session_id: "t7-ux-exploration"
started_at: "2026-10-18T00:00:00Z"
contract_required: false
html_review: false
---

## 目标
t7 ux-exploration channel acceptance fixture

## 验收场景

${scenarioLines.join('\n')}
`,
    'utf-8'
  );
  return p;
}

/**
 * 子进程 source lib.sh 后调用指定守卫函数（范式照搬
 * predicate-channel-guard.acceptance.test.sh:invoke_validate_channels：
 * AUTOPILOT_TEST_MODE + AUTOPILOT_DISABLE_MAIN 抑制副作用，subshell 隔离）。
 * 返回 { rc, stdout }；断言值只依据设计文档契约：rc0=合规 / rc1=no-op / rc2=违规。
 */
function runLibGuardFn(fnName, stateFile) {
  const script = [
    'set -uo pipefail',
    'export AUTOPILOT_TEST_MODE=1',
    'export AUTOPILOT_DISABLE_MAIN=1',
    `source '${LIB_SH}' 2>/dev/null || true`,
    `${fnName} '${stateFile}'`,
  ].join('\n');
  const r = spawnSync('bash', ['-c', script], { encoding: 'utf-8' });
  return { rc: r.status, stdout: (r.stdout || '').trim() };
}

/** 谓词行 fixture（fullwidth ｜ 分隔，格式见 scenario-generator-prompt.md 谓词协议） */
const PRED_UX_EXPLORATION_LEGAL =
  '- **t7.uxchan-legal [ux-exploration]** 探索走查实现产物产出发现清单 ｜ observe: 发现清单 Critical 计数 ｜ assert: Critical == 0 ｜ driver: playwright:app ｜ artifact: /tmp/autopilot-artifacts/t7-uxchan-legal.out';
const PRED_UX_VISIAL_ILLEGAL =
  '- **t7.uxvisial-illegal [ux-visial]** 视觉走查对照 ｜ observe: 差异清单 ｜ assert: 差异 == 0 ｜ driver: playwright:app ｜ artifact: /tmp/autopilot-artifacts/t7-uxvisial.out';
const PRED_UX_EXPLORATION_NO_ARTIFACT =
  '- **t7.uxcov-gap [ux-exploration]** 探索走查 ｜ observe: 发现清单 ｜ assert: Critical == 0 ｜ driver: playwright:app';
const PRED_UX_EXPLORATION_WITH_ARTIFACT =
  '- **t7.uxcov-ok [ux-exploration]** 探索走查 ｜ observe: 发现清单 ｜ assert: Critical == 0 ｜ driver: playwright:app ｜ artifact: /tmp/autopilot-artifacts/t7-uxcov-ok.out';
const PRED_NODE_SCRIPT_NETWORK =
  '- **t7.drv-net [real-process]** node-script 驱动 curl 探测外部接口 ｜ observe: 子进程 stdout ｜ assert: exit == 0 ｜ driver: node-script:curl-probe ｜ artifact: /tmp/autopilot-artifacts/t7-drv.out';
const PRED_NODE_SCRIPT_CLEAN =
  '- **t7.drv-clean [real-process]** 子进程 exit code 观测 ｜ observe: 子进程 exit code ｜ assert: exit == 0 ｜ driver: node-script:lib-fn ｜ artifact: /tmp/autopilot-artifacts/t7-drv-clean.out';

// ---------------------------------------------------------------------------
// T7 执行面挂接：五守卫 .sh 子进程回归（场景6.P2 组成件）
// 任务起点即绿；扩员后「既有五守卫测试全绿不回归」是契约规约硬条款。
// ---------------------------------------------------------------------------
describe('T7 执行面挂接：五守卫 .sh 子进程回归（场景6.P2 组成件）', () => {
  for (const name of FIVE_GUARD_SH) {
    it(`五守卫回归：${name} 子进程 exit=0`, () => {
      const p = resolve(ACCEPTANCE_DIR, name);
      assert.ok(existsSync(p), `守卫测试文件必须存在: ${p}`);
      const r = spawnSync('bash', [p], { encoding: 'utf-8', cwd: ROOT });
      assert.strictEqual(
        r.status,
        0,
        `${name} 期望 exit=0，实际 ${r.status}\n` +
          `stdout 尾部: ${(r.stdout || '').slice(-600)}\n` +
          `stderr 尾部: ${(r.stderr || '').slice(-400)}`
      );
    });
  }
});

// ---------------------------------------------------------------------------
// T7 守卫黑盒负例回归（场景7/8，任务起点即绿）
// 配对说明：本组全部负例与 M3 组正向 rc0 断言互为反例，
// kill「信号串恒输出 / 恒 rc2 / 恒 rc0」三类 mutation。
// ---------------------------------------------------------------------------
describe('T7 守卫黑盒负例回归（场景7/8，任务起点即绿）', () => {
  it('场景7.P1 [real-process] ux-visial 非法 channel → validate_predicate_channels rc2', () => {
    const state = writeMockState('s7p1.md', [PRED_UX_VISIAL_ILLEGAL]);
    const { rc } = runLibGuardFn('validate_predicate_channels', state);
    assert.strictEqual(
      rc,
      2,
      `合法集外 channel（ux-visial）必须被拒，期望 rc=2，实际 rc=${rc}`
    );
  });

  it('场景7.P2 [det-machine] 拒绝输出含 PRED-CHANNEL-ILLEGAL 与 ux-visial 字面量', () => {
    const state = writeMockState('s7p2.md', [PRED_UX_VISIAL_ILLEGAL]);
    const { stdout } = runLibGuardFn('validate_predicate_channels', state);
    assert.ok(
      stdout.includes('PRED-CHANNEL-ILLEGAL'),
      `stdout 必须含违规信号串 PRED-CHANNEL-ILLEGAL，实际='${stdout}'`
    );
    assert.ok(
      stdout.includes('ux-visial'),
      `stdout 必须含非法 channel 字面量 ux-visial（错误可定位），实际='${stdout}'`
    );
  });

  it('场景8.P2a [real-process] ux-exploration artifact 指向不存在文件 → validate_predicate_artifacts rc2 + PRED-ARTIFACT-MISSING', () => {
    const missing = join(TMP_ROOT, 't7-art-missing.out');
    const state = writeMockState('s8p2a.md', [
      PRED_UX_EXPLORATION_WITH_ARTIFACT.replace(
        '/tmp/autopilot-artifacts/t7-uxcov-ok.out',
        missing
      ),
    ]);
    const { rc, stdout } = runLibGuardFn('validate_predicate_artifacts', state);
    assert.strictEqual(
      rc,
      2,
      `artifact 不存在必须判不满足，期望 rc=2，实际 rc=${rc}，stdout='${stdout}'`
    );
    assert.ok(
      stdout.includes('PRED-ARTIFACT-MISSING'),
      `stdout 必须含 PRED-ARTIFACT-MISSING，实际='${stdout}'`
    );
  });

  it('场景8.P2b [real-process] artifact 为空文件（size=0）→ validate_predicate_artifacts rc2 + PRED-ARTIFACT-MISSING', () => {
    const empty = join(TMP_ROOT, 't7-art-empty.out');
    writeFileSync(empty, '', 'utf-8'); // 边界：存在但 0 字节
    const state = writeMockState('s8p2b.md', [
      PRED_UX_EXPLORATION_WITH_ARTIFACT.replace(
        '/tmp/autopilot-artifacts/t7-uxcov-ok.out',
        empty
      ),
    ]);
    const { rc, stdout } = runLibGuardFn('validate_predicate_artifacts', state);
    assert.strictEqual(
      rc,
      2,
      `空文件 artifact 必须判不满足（非空校验边界），期望 rc=2，实际 rc=${rc}`
    );
    assert.ok(
      stdout.includes('PRED-ARTIFACT-MISSING'),
      `空文件也必须输出 PRED-ARTIFACT-MISSING，实际='${stdout}'`
    );
  });

  it('场景8.P3 [real-process] node-script 驱动网络类目标（fixture 含 curl）→ validate_predicate_driver rc2 + PRED-DRIVER-VIOLATION', () => {
    const state = writeMockState('s8p3.md', [PRED_NODE_SCRIPT_NETWORK]);
    const { rc, stdout } = runLibGuardFn('validate_predicate_driver', state);
    assert.strictEqual(
      rc,
      2,
      `node-script + 网络关键字必须被反向判定拒绝，期望 rc=2，实际 rc=${rc}`
    );
    assert.ok(
      stdout.includes('PRED-DRIVER-VIOLATION'),
      `stdout 必须含 PRED-DRIVER-VIOLATION，实际='${stdout}'`
    );
  });

  it('场景8.P3 反例 [real-process] node-script 无网络关键字 → validate_predicate_driver rc0（kill 恒违规 mutation）', () => {
    const state = writeMockState('s8p3-clean.md', [PRED_NODE_SCRIPT_CLEAN]);
    const { rc, stdout } = runLibGuardFn('validate_predicate_driver', state);
    assert.strictEqual(
      rc,
      0,
      `无网络关键字的 node-script 必须放行（反向判定集闭集外不误伤），期望 rc=0，实际 rc=${rc}，stdout='${stdout}'`
    );
  });
});

// ---------------------------------------------------------------------------
// M3 ux-exploration channel 扩员（场景1 / 场景8.P1）
// TDD 红灯组：M3 未落地时本组必红；执行时机归 QA/合流后。
// 期望值全部来自设计文档契约：合法集 + ux-exploration（只扩不缩）、
// coverage artifact 强制集 + ux-exploration（同 visual-residue 口径）。
// ---------------------------------------------------------------------------
describe('M3 ux-exploration channel 扩员（场景1/8.P1，QA 时机执行）', () => {
  it('场景1.P1 [det-machine] lib.sh 全文含 ux-exploration 字面量（match_count >= 1）', () => {
    const content = readFileSync(LIB_SH, 'utf-8');
    const count = content.split('ux-exploration').length - 1;
    assert.ok(
      count >= 1,
      `lib.sh 合法集必须含 ux-exploration 字面量（channel 枚举闭集扩员），实际命中=${count}`
    );
  });

  it('场景1.P2 [real-process] ux-exploration 合规谓词行（driver/artifact 齐备）→ validate_predicate_channels rc0', () => {
    const state = writeMockState('s1p2.md', [PRED_UX_EXPLORATION_LEGAL]);
    const { rc, stdout } = runLibGuardFn('validate_predicate_channels', state);
    assert.strictEqual(
      rc,
      0,
      `ux-exploration 合法 channel 必须放行，期望 rc=0，实际 rc=${rc}，stdout='${stdout}'`
    );
    assert.ok(
      !stdout.includes('PRED-CHANNEL-ILLEGAL'),
      `合法 channel 不得输出 PRED-CHANNEL-ILLEGAL（反例守恒），实际='${stdout}'`
    );
  });

  it('场景1.P3 [real-process] ux-exploration 谓词 artifact 字段齐备 → validate_predicate_coverage rc0', () => {
    const state = writeMockState('s1p3.md', [PRED_UX_EXPLORATION_WITH_ARTIFACT]);
    const { rc, stdout } = runLibGuardFn('validate_predicate_coverage', state);
    assert.strictEqual(
      rc,
      0,
      `ux-exploration artifact 齐备时 coverage 必须放行，期望 rc=0，实际 rc=${rc}，stdout='${stdout}'`
    );
  });

  it('场景8.P1 [real-process] ux-exploration 谓词缺 artifact 字段 → validate_predicate_coverage rc2 + PRED-COVERAGE-GAP', () => {
    const state = writeMockState('s8p1.md', [PRED_UX_EXPLORATION_NO_ARTIFACT]);
    const { rc, stdout } = runLibGuardFn('validate_predicate_coverage', state);
    assert.strictEqual(
      rc,
      2,
      `ux-exploration 缺 artifact 必须被 coverage 拒绝（同 visual-residue 口径），期望 rc=2，实际 rc=${rc}`
    );
    assert.ok(
      stdout.includes('PRED-COVERAGE-GAP'),
      `stdout 必须含 PRED-COVERAGE-GAP，实际='${stdout}'`
    );
  });
});

// ---------------------------------------------------------------------------
// M1 全保真 mockup 规范 + design anchor 冻结协议（场景2）
// 断言目标 = 蓝队交付物 visual-companion-guide.md；只断言设计文档契约要求的
// 内容存在；执行时机归 QA/合流后。缺文件/缺关键词 = 硬失败（红灯）。
// ---------------------------------------------------------------------------
describe('M1 全保真 mockup 规范与冻结协议内容锚点（场景2，QA 时机执行）', () => {
  it('场景2.P1 [det-machine] mockup 规范同时锚定 真实tokens/真实数据/真实设备框 三类语义（keyword_hits >= 3）', () => {
    const content = readFileSync(VISUAL_COMPANION_GUIDE, 'utf-8');
    const classes = [
      { name: '真实 tokens', hit: /tokens/i.test(content) },
      {
        name: '真实数据',
        hit:
          content.includes('seed') ||
          content.includes('接口样例') ||
          content.includes('禁编造'),
      },
      {
        name: '真实设备框',
        hit:
          content.includes('设备框') ||
          content.includes('状态栏') ||
          content.includes('导航栏') ||
          content.includes('手势条'),
      },
    ];
    const hits = classes.filter((c) => c.hit).length;
    const missed = classes.filter((c) => !c.hit).map((c) => c.name);
    assert.ok(
      hits >= 3,
      `全保真规范必须同时锚定三类语义（真实tokens/真实数据/真实设备框），命中=${hits}/3，缺失=[${missed.join(', ')}]`
    );
  });

  it('场景2.P2 [det-machine] 冻结协议锚定 用户确认 前置与 冻结后唯一视觉锚 语义（keyword_hits >= 2）', () => {
    const content = readFileSync(VISUAL_COMPANION_GUIDE, 'utf-8');
    const keywords = ['确认', '冻结', '唯一'];
    const hits = keywords.filter((k) => content.includes(k)).length;
    assert.ok(
      hits >= 2,
      `冻结协议必须锚定「用户确认 + 唯一视觉锚」语义（确认/冻结/唯一 命中 >= 2），命中=${hits}/3`
    );
  });

  it('场景2.P3 [det-machine] 冻结产物落盘约定锚定 design-anchor 目录语义（match_count >= 1）', () => {
    const content = readFileSync(VISUAL_COMPANION_GUIDE, 'utf-8');
    const count = content.split('design-anchor').length - 1;
    assert.ok(
      count >= 1,
      `冻结产物必须落盘 $TASK_DIR/design-anchor/（目录语义锚定），实际命中=${count}`
    );
  });
});

// ---------------------------------------------------------------------------
// M2 视觉规格传递通道（场景3）
// 断言目标 = 蓝队交付物 state-file-guide.md；执行时机归 QA/合流后。
// ---------------------------------------------------------------------------
describe('M2 设计文档「视觉规格」可选节锚点（场景3，QA 时机执行）', () => {
  it('场景3.P1 [det-machine] 设计文档模板含「视觉规格」节标题（match_count >= 1）', () => {
    const content = readFileSync(STATE_FILE_GUIDE, 'utf-8');
    const count = content.split('视觉规格').length - 1;
    assert.ok(
      count >= 1,
      `state-file-guide.md 设计文档模板必须含「视觉规格」节标题，实际命中=${count}`
    );
  });

  it('场景3.P2 [det-machine] 节内容同时锚定 锚图路径/逐屏规格/冻结声明 三要素（keyword_hits >= 3）', () => {
    const content = readFileSync(STATE_FILE_GUIDE, 'utf-8');
    const elements = [
      { name: '锚图路径', hit: content.includes('design-anchor') || content.includes('锚图路径') },
      { name: '逐屏规格', hit: content.includes('逐屏') },
      { name: '冻结声明', hit: content.includes('冻结') },
    ];
    const hits = elements.filter((e) => e.hit).length;
    const missed = elements.filter((e) => !e.hit).map((e) => e.name);
    assert.ok(
      hits >= 3,
      `视觉规格节必须同时锚定三要素（锚图路径/逐屏规格/冻结声明），命中=${hits}/3，缺失=[${missed.join(', ')}]`
    );
  });

  it('场景3.P3 [det-machine] 视觉规格节声明为可选并锚定 UI 交付物条件（keyword_hits >= 2）', () => {
    const content = readFileSync(STATE_FILE_GUIDE, 'utf-8');
    const keywords = ['可选', 'UI'];
    const hits = keywords.filter((k) => content.includes(k)).length;
    assert.ok(
      hits >= 2,
      `视觉规格节必须声明为可选（无 UI 交付物时省略），可选/UI 条件命中=${hits}/2`
    );
  });
});

// ---------------------------------------------------------------------------
// 场景4 QA 双形态谓词锚点 + stop-hook §5.7 同步（蓝队交付物，QA 时机执行）
// 场景4.P3 是防半 no-op 关键断言：只改注释不动 :869/:882 运行时文案时必红。
// ---------------------------------------------------------------------------
describe('场景4 QA 双形态锚点与 stop-hook §5.7 同步（QA 时机执行）', () => {
  it('场景4.P1 [det-machine] scenario-generator-prompt.md 锚定 anchor-compare 形态（match_count >= 2）', () => {
    const content = readFileSync(SCENARIO_GENERATOR, 'utf-8');
    const count = content.split('anchor-compare').length - 1;
    assert.ok(
      count >= 2,
      `anchor-compare 形态必须被锚定且非单处提及（改动前基线命中=0），实际命中=${count}`
    );
  });

  it('场景4.P2 [det-machine] exploration 形态六项 UX 启发式（空态/加载态/错误态/反馈/一致性/边界）逐项可命中（keyword_hits >= 6）', () => {
    const content = readFileSync(SCENARIO_GENERATOR, 'utf-8');
    const heuristics = ['空态', '加载态', '错误态', '反馈', '一致性', '边界'];
    const hits = heuristics.filter((k) => content.includes(k)).length;
    const missed = heuristics.filter((k) => !content.includes(k));
    assert.ok(
      hits >= 6,
      `六项 UX 启发式必须逐项可命中，命中=${hits}/6，缺失=[${missed.join(', ')}]`
    );
  });

  it('场景4.P3 [det-machine] stop-hook.sh 注释与运行时 reason 文案多处同步 ux-exploration（match_count >= 3，防半 no-op）', () => {
    const content = readFileSync(STOP_HOOK_SH, 'utf-8');
    const count = content.split('ux-exploration').length - 1;
    assert.ok(
      count >= 3,
      `stop-hook.sh 必须 §5.7(c) 合法集字符串 + §5.7(d) reason 文案 + 注释多处含 ux-exploration（防只改注释不动运行时文案），实际命中=${count}`
    );
  });
});

// ---------------------------------------------------------------------------
// 场景5 blue-team-prompt 按冻结锚实现指引锚点（蓝队交付物，QA 时机执行）
// ---------------------------------------------------------------------------
describe('场景5 blue-team-prompt 冻结锚实现指引锚点（QA 时机执行）', () => {
  it('场景5.P1 [det-machine] 蓝队实现指引同时锚定「视觉规格」引用与按冻结锚实现语义（keyword_hits >= 2）', () => {
    const content = readFileSync(BLUE_TEAM_PROMPT, 'utf-8');
    const keywords = ['视觉规格', '锚', '冻结'];
    const hits = keywords.filter((k) => content.includes(k)).length;
    assert.ok(
      hits >= 2,
      `blue-team-prompt.md 必须锚定「含视觉规格节时按冻结锚逐屏实现」指引（视觉规格/锚/冻结 命中 >= 2），命中=${hits}/3`
    );
  });
});

// ---------------------------------------------------------------------------
// T7 测试树锚点（场景6.P1）+ T7 工程硬约束守恒（场景9）——任务起点即绿
// ---------------------------------------------------------------------------
describe('T7 测试树锚点（场景6.P1）', () => {
  function walkAcceptanceTests(dir) {
    const out = [];
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      const p = resolve(dir, e.name);
      if (e.isDirectory()) out.push(...walkAcceptanceTests(p));
      else if (e.name.endsWith('.acceptance.test.mjs')) out.push(p);
    }
    return out;
  }

  it('场景6.P1 [det-machine] tests 树 *.acceptance.test.mjs 锚定 ux-exploration 守卫行为与 ux-visial 非法负例（match_count >= 1）', () => {
    const files = walkAcceptanceTests(resolve(ROOT, 'tests'));
    assert.ok(files.length >= 1, 'tests 树必须存在 .acceptance.test.mjs 文件');
    const uxFiles = files.filter((f) =>
      readFileSync(f, 'utf-8').includes('ux-exploration')
    );
    const illegalFiles = files.filter((f) =>
      readFileSync(f, 'utf-8').includes('ux-visial')
    );
    assert.ok(
      uxFiles.length >= 1,
      'tests 树必须至少 1 个 .acceptance.test.mjs 锚定 ux-exploration 守卫行为'
    );
    assert.ok(
      illegalFiles.length >= 1,
      'tests 树必须至少 1 个 .acceptance.test.mjs 锚定 ux-visial 非法 channel 负例'
    );
  });
});

describe('T7 工程硬约束守恒（场景9，任务起点即绿）', () => {
  it('场景9.P1 [det-machine] 主 SKILL.md 相对 HEAD 基线零新增行（added_lines == 0）', () => {
    const r = spawnSync(
      'git',
      ['diff', 'HEAD', '--numstat', '--', 'plugins/autopilot/skills/autopilot/SKILL.md'],
      { encoding: 'utf-8', cwd: ROOT }
    );
    const line = (r.stdout || '').trim();
    const added = line ? parseInt(line.split('\t')[0], 10) : 0;
    assert.ok(
      Number.isFinite(added) && added === 0,
      `主 SKILL.md 零新增行是本目标硬约束（行数不能新增只能减少），git diff HEAD --numstat 首列=${line || '(无 diff)'}`
    );
  });

  it('场景9.P2 [real-process] shellcheck -S warning 扫描全 plugins 树零告警（exit == 0）', () => {
    const r = spawnSync(
      'bash',
      ['-c', 'find plugins -name "*.sh" -not -path "*/.git/*" -print0 | xargs -0 shellcheck -S warning'],
      { encoding: 'utf-8', cwd: ROOT }
    );
    assert.strictEqual(
      r.status,
      0,
      `全树 shellcheck -S warning 必须零告警（CI 门禁对齐），实际 exit=${r.status}` +
        (r.status === 127 || r.error
          ? `（127/error=环境缺 shellcheck 二进制——CI Unit Tests job 须与 lint job 同源安装，见 ci.yml）`
          : r.status === 123
            ? `（123=xargs 聚合：至少一个文件有告警，明细见下方 stdout；常见根因=shellcheck 版本分叉，须与 lint job 同源）`
            : '') +
        `\nstdout 尾部（shellcheck 告警明细）: ${(r.stdout || '').slice(-1500)}` +
        `\nstderr 尾部: ${(r.stderr || '').slice(-500)}`
    );
  });
});
