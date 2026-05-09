/**
 * Acceptance tests for TDD quality improvements (v3.23.0).
 *
 * Red-team verification: written purely from the design document.
 * The blue-team implementation files are NOT read by this test to verify
 * content logic — only specific required strings and positional relationships
 * are asserted via fs.readFileSync + .includes / indexOf line-number comparison.
 *
 * Design spec (state.md §设计文档 + §验收场景):
 *   - Change 1: red-team-prompt.md  → add "## ⚠️ 测试质量铁律（必读）" section
 *               between "## ⚠️ 铁律" and "## 目标"
 *   - Change 2: merge-phase.md      → add "## 2.5. CI 验证（条件触发）" section
 *               between "## 2. Auto-Chain 评估" and "## 3. 知識提取與沉澱"
 *   - Change 3: qa-reviewer-prompt.md → add "### Section C: 红队验收测试质量审查"
 *               between "### Section B:" and "## 输出格式"
 *   - Change 4: anti-rationalization.md → add "## implement 阶段（红队 Agent 视角）"
 *               between "## implement 阶段" and "## qa Tier 1.5"
 *   - Change 5: version bump to v3.23.0 across plugin.json / marketplace.json / CLAUDE.md
 *
 * Scenes covered:
 *   Scene 1 — red-team-prompt.md: 铁律段存在 + 关键词 + 出现在 ## 目标 之前
 *   Scene 3 — merge-phase.md: 2.5 + CI 验证 + gh run watch + headSha + auto-fix 路径
 *   Scene 4 — merge-phase.md: 不含"CI 失败时跳过/忽略" + 含正确 auto-fix 映射
 *   Scene 5 — qa-reviewer-prompt.md: Section C + 3 类反模式标题
 *   Scene 7 — anti-rationalization.md: 新段位置正确（implement → 红队段 → qa Tier 1.5）
 *   Scene V — 版本号同步: plugin.json + marketplace.json + CLAUDE.md 均含 3.23.0
 *
 * Run: node --test tests/tdd-quality-improvements.acceptance.test.mjs
 *
 * ⚠️ 红队铁律自检 (写入规则，不可放松):
 *   - 0 个 if/else 包裹断言
 *   - 0 个 try/catch 吞断言
 *   - 全部硬断言 assert.*；蓝队未改完时测试应 fail（TDD 红灯是正确信号）
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');

const RED_TEAM_PATH = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot/references/red-team-prompt.md'
);
const MERGE_PHASE_PATH = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot/references/merge-phase.md'
);
const QA_REVIEWER_PATH = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot/references/qa-reviewer-prompt.md'
);
const ANTI_RATIONALIZATION_PATH = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot/references/anti-rationalization.md'
);
const PLUGIN_JSON_PATH = resolve(
  ROOT,
  'plugins/autopilot/.claude-plugin/plugin.json'
);
const MARKETPLACE_PATH = resolve(ROOT, '.claude-plugin/marketplace.json');
const CLAUDE_MD_PATH = resolve(ROOT, 'CLAUDE.md');

// ---------------------------------------------------------------------------
// Helper: 将文件内容按行切分，返回 [line1, line2, ...] (1-indexed via idx+1)
// ---------------------------------------------------------------------------
function linesOf(content) {
  return content.split('\n');
}

// 返回第一次匹配某个字符串的行号（1-indexed），未找到返回 -1
function firstLineOf(lines, needle) {
  const idx = lines.findIndex((l) => l.includes(needle));
  return idx === -1 ? -1 : idx + 1;
}

// ---------------------------------------------------------------------------
// Scene 1 — red-team-prompt.md: 测试质量铁律段存在 + 关键词 + 位置在 ## 目标 之前
// ---------------------------------------------------------------------------
describe('Scene 1: red-team-prompt.md 铁律段存在且位置正确', () => {
  it('Scene 1a: 文件包含 "测试质量铁律" 字符串', () => {
    const content = readFileSync(RED_TEAM_PATH, 'utf-8');
    assert.ok(
      content.includes('测试质量铁律'),
      'red-team-prompt.md 必须包含 "测试质量铁律" 字符串（改动 1 铁律段标题）'
    );
  });

  it('Scene 1b: 文件包含 "宽容跳过" 字符串', () => {
    const content = readFileSync(RED_TEAM_PATH, 'utf-8');
    assert.ok(
      content.includes('宽容跳过'),
      'red-team-prompt.md 必须包含 "宽容跳过" 字符串（铁律段核心关键词）'
    );
  });

  it('Scene 1c: 文件包含 "console.warn" 字符串（明确列出禁止模式）', () => {
    const content = readFileSync(RED_TEAM_PATH, 'utf-8');
    assert.ok(
      content.includes('console.warn'),
      'red-team-prompt.md 必须包含 "console.warn" 字符串（禁止用 warn 替代 assert 的铁律）'
    );
  });

  it('Scene 1d: 文件包含 "强断言" 字符串（要求硬断言的正面规则）', () => {
    const content = readFileSync(RED_TEAM_PATH, 'utf-8');
    assert.ok(
      content.includes('强断言'),
      'red-team-prompt.md 必须包含 "强断言" 字符串（铁律正面规则描述）'
    );
  });

  it('Scene 1e: 铁律段（## ⚠️ 测试质量铁律）出现在 ## 目标 之前（行号比较）', () => {
    const content = readFileSync(RED_TEAM_PATH, 'utf-8');
    const lines = linesOf(content);

    const ironLawLine = firstLineOf(lines, '测试质量铁律');
    const targetLine = firstLineOf(lines, '## 目标');

    assert.notStrictEqual(
      ironLawLine,
      -1,
      'red-team-prompt.md 中未找到 "测试质量铁律" 段（蓝队可能尚未添加，TDD 红灯）'
    );
    assert.notStrictEqual(
      targetLine,
      -1,
      'red-team-prompt.md 中未找到 "## 目标" 标题（文件结构异常）'
    );
    assert.ok(
      ironLawLine < targetLine,
      `铁律段（行 ${ironLawLine}）必须出现在 "## 目标"（行 ${targetLine}）之前，当前顺序错误`
    );
  });
});

// ---------------------------------------------------------------------------
// Scene 3 — merge-phase.md: 2.5 CI 验证 + gh run watch + headSha + auto-fix 路径
// ---------------------------------------------------------------------------
describe('Scene 3: merge-phase.md 包含 CI 验证步骤关键内容', () => {
  it('Scene 3a: 文件包含 "2.5" 字符串（新步骤编号）', () => {
    const content = readFileSync(MERGE_PHASE_PATH, 'utf-8');
    assert.ok(
      content.includes('2.5'),
      'merge-phase.md 必须包含 "2.5" 字符串（改动 2 新步骤编号）'
    );
  });

  it('Scene 3b: 文件包含 "CI 验证" 字符串', () => {
    const content = readFileSync(MERGE_PHASE_PATH, 'utf-8');
    assert.ok(
      content.includes('CI 验证'),
      'merge-phase.md 必须包含 "CI 验证" 字符串（步骤 2.5 标题关键词）'
    );
  });

  it('Scene 3c: 文件包含 "gh run watch" 字符串（CI 等待命令）', () => {
    const content = readFileSync(MERGE_PHASE_PATH, 'utf-8');
    assert.ok(
      content.includes('gh run watch'),
      'merge-phase.md 必须包含 "gh run watch" 字符串（CI 等待的核心命令）'
    );
  });

  it('Scene 3d: 文件包含 "headSha" 字符串（精确匹配 commit 的关键字段）', () => {
    const content = readFileSync(MERGE_PHASE_PATH, 'utf-8');
    assert.ok(
      content.includes('headSha'),
      'merge-phase.md 必须包含 "headSha" 字符串（gh run list JSON 字段，用于精确匹配本次 HEAD commit）'
    );
  });

  it('Scene 3e: 文件包含 "auto-fix" 字符串（CI 失败时切换 phase 的目标）', () => {
    const content = readFileSync(MERGE_PHASE_PATH, 'utf-8');
    assert.ok(
      content.includes('auto-fix'),
      'merge-phase.md 必须包含 "auto-fix" 字符串（CI 失败后 phase 切换到 auto-fix 的路径）'
    );
  });
});

// ---------------------------------------------------------------------------
// Scene 4 — merge-phase.md: 不含"CI 失败时跳过/忽略" + 含正确 auto-fix 映射
// ---------------------------------------------------------------------------
describe('Scene 4: merge-phase.md CI 失败路径正确，无跳过/忽略描述', () => {
  it('Scene 4a: 文件不包含 "CI 失败时跳过" 字符串', () => {
    const content = readFileSync(MERGE_PHASE_PATH, 'utf-8');
    assert.ok(
      !content.includes('CI 失败时跳过'),
      'merge-phase.md 不得包含 "CI 失败时跳过"（设计要求 CI 失败必须切 auto-fix，不能跳过）'
    );
  });

  it('Scene 4b: 文件不包含 "CI 失败时忽略" 字符串', () => {
    const content = readFileSync(MERGE_PHASE_PATH, 'utf-8');
    assert.ok(
      !content.includes('CI 失败时忽略'),
      'merge-phase.md 不得包含 "CI 失败时忽略"（设计要求 CI 失败不能忽略）'
    );
  });

  it('Scene 4c: 文件同时包含 "auto-fix" 和 "phase" 字符串（phase 切换映射存在）', () => {
    const content = readFileSync(MERGE_PHASE_PATH, 'utf-8');
    assert.ok(
      content.includes('auto-fix') && content.includes('phase'),
      'merge-phase.md 必须同时包含 "auto-fix" 和 "phase" 字符串（CI 失败的 phase 切换逻辑）'
    );
  });

  it('Scene 4d: 文件包含 "qa_scope" 字符串（CI 失败时 selective QA 设置）', () => {
    const content = readFileSync(MERGE_PHASE_PATH, 'utf-8');
    assert.ok(
      content.includes('qa_scope'),
      'merge-phase.md 必须包含 "qa_scope" 字符串（CI 失败时设置 qa_scope: selective 的设计要求）'
    );
  });
});

// ---------------------------------------------------------------------------
// Scene 5 — qa-reviewer-prompt.md: Section C + 3 类反模式标题
// ---------------------------------------------------------------------------
describe('Scene 5: qa-reviewer-prompt.md 含 Section C 及 3 类反模式检查', () => {
  it('Scene 5a: 文件包含 "Section C" 字符串', () => {
    const content = readFileSync(QA_REVIEWER_PATH, 'utf-8');
    assert.ok(
      content.includes('Section C'),
      'qa-reviewer-prompt.md 必须包含 "Section C" 字符串（改动 3 新增审查段标题）'
    );
  });

  it('Scene 5b: 文件包含 "红队验收测试质量" 字符串', () => {
    const content = readFileSync(QA_REVIEWER_PATH, 'utf-8');
    assert.ok(
      content.includes('红队验收测试质量'),
      'qa-reviewer-prompt.md 必须包含 "红队验收测试质量" 字符串（Section C 完整标题关键词）'
    );
  });

  it('Scene 5c: 文件包含反模式类型 "宽容跳过" 字符串', () => {
    const content = readFileSync(QA_REVIEWER_PATH, 'utf-8');
    assert.ok(
      content.includes('宽容跳过'),
      'qa-reviewer-prompt.md 必须包含 "宽容跳过" 字符串（Section C 第 1 类反模式）'
    );
  });

  it('Scene 5d: 文件包含反模式类型 "缺失断言" 字符串', () => {
    const content = readFileSync(QA_REVIEWER_PATH, 'utf-8');
    assert.ok(
      content.includes('缺失断言'),
      'qa-reviewer-prompt.md 必须包含 "缺失断言" 字符串（Section C 第 2 类反模式）'
    );
  });

  it('Scene 5e: 文件包含反模式类型 "粒度过粗" 字符串', () => {
    const content = readFileSync(QA_REVIEWER_PATH, 'utf-8');
    assert.ok(
      content.includes('粒度过粗'),
      'qa-reviewer-prompt.md 必须包含 "粒度过粗" 字符串（Section C 第 3 类反模式）'
    );
  });

  it('Scene 5f: 文件包含 "BLOCKER" 字符串（Section C 阻塞判决机制）', () => {
    const content = readFileSync(QA_REVIEWER_PATH, 'utf-8');
    assert.ok(
      content.includes('BLOCKER'),
      'qa-reviewer-prompt.md 必须包含 "BLOCKER" 字符串（Section C 将宽容跳过等定性为阻塞问题）'
    );
  });
});

// ---------------------------------------------------------------------------
// Scene 7 — anti-rationalization.md: 红队段位置正确
//   implement 阶段段 < 红队 Agent 视角段 < qa Tier 1.5 段（行号递增）
// ---------------------------------------------------------------------------
describe('Scene 7: anti-rationalization.md 红队段位置正确', () => {
  it('Scene 7a: 文件包含 "implement 阶段（红队 Agent 视角）" 字符串', () => {
    const content = readFileSync(ANTI_RATIONALIZATION_PATH, 'utf-8');
    assert.ok(
      content.includes('implement 阶段（红队 Agent 视角）'),
      'anti-rationalization.md 必须包含 "implement 阶段（红队 Agent 视角）" 字符串（改动 4 新增段标题）'
    );
  });

  it('Scene 7b: 文件包含 "蓝队还没产出" 或 "容错空间" 字符串（红队合理化示例）', () => {
    const content = readFileSync(ANTI_RATIONALIZATION_PATH, 'utf-8');
    assert.ok(
      content.includes('蓝队还没产出') || content.includes('容错空间'),
      'anti-rationalization.md 必须包含红队合理化借口示例（"蓝队还没产出" 或 "容错空间"）'
    );
  });

  it('Scene 7c: 红队 Agent 视角段位于 implement 阶段段之后（行号比较）', () => {
    const content = readFileSync(ANTI_RATIONALIZATION_PATH, 'utf-8');
    const lines = linesOf(content);

    // 找 "## implement 阶段" 的行（精确匹配不带括号后缀的原始段）
    const implementLine = lines.findIndex(
      (l) => l.trim() === '## implement 阶段'
    );
    // 找新段 "## implement 阶段（红队 Agent 视角）"
    const redTeamLine = lines.findIndex((l) =>
      l.includes('implement 阶段（红队 Agent 视角）')
    );

    assert.notStrictEqual(
      implementLine,
      -1,
      'anti-rationalization.md 中未找到 "## implement 阶段" 原始段（文件结构异常）'
    );
    assert.notStrictEqual(
      redTeamLine,
      -1,
      'anti-rationalization.md 中未找到 "implement 阶段（红队 Agent 视角）" 新段（蓝队可能尚未添加，TDD 红灯）'
    );
    assert.ok(
      implementLine < redTeamLine,
      `原始 implement 段（行 ${implementLine + 1}）必须出现在红队 Agent 视角段（行 ${redTeamLine + 1}）之前`
    );
  });

  it('Scene 7d: 红队 Agent 视角段位于 qa Tier 1.5 段之前（行号比较）', () => {
    const content = readFileSync(ANTI_RATIONALIZATION_PATH, 'utf-8');
    const lines = linesOf(content);

    const redTeamLine = lines.findIndex((l) =>
      l.includes('implement 阶段（红队 Agent 视角）')
    );
    // 找 "## qa Tier 1.5" 段
    const qaTierLine = lines.findIndex((l) => l.includes('qa Tier 1.5'));

    assert.notStrictEqual(
      redTeamLine,
      -1,
      'anti-rationalization.md 中未找到 "implement 阶段（红队 Agent 视角）" 新段（蓝队可能尚未添加，TDD 红灯）'
    );
    assert.notStrictEqual(
      qaTierLine,
      -1,
      'anti-rationalization.md 中未找到 "## qa Tier 1.5" 段（文件结构异常）'
    );
    assert.ok(
      redTeamLine < qaTierLine,
      `红队 Agent 视角段（行 ${redTeamLine + 1}）必须出现在 "qa Tier 1.5"（行 ${qaTierLine + 1}）之前`
    );
  });
});

// ---------------------------------------------------------------------------
// Scene V — 版本号同步: plugin.json + marketplace.json + CLAUDE.md 均含 3.23.0
// ---------------------------------------------------------------------------
describe('Scene V: 版本号同步至 v3.23.0', () => {
  const TARGET_VERSION = '3.23.0';

  it('Scene V-a: plugin.json 包含 "3.23.0" 版本号', () => {
    const content = readFileSync(PLUGIN_JSON_PATH, 'utf-8');
    assert.ok(
      content.includes(TARGET_VERSION),
      `plugins/autopilot/.claude-plugin/plugin.json 必须包含 "${TARGET_VERSION}"（蓝队 T5 版本同步）`
    );
  });

  it('Scene V-b: plugin.json 的 version 字段精确等于 3.23.0', () => {
    const pluginData = JSON.parse(readFileSync(PLUGIN_JSON_PATH, 'utf-8'));
    assert.strictEqual(
      pluginData.version,
      TARGET_VERSION,
      `plugin.json .version 字段必须精确等于 "${TARGET_VERSION}"，当前为 "${pluginData.version}"`
    );
  });

  it('Scene V-c: marketplace.json 中 autopilot 条目版本为 3.23.0', () => {
    const raw = readFileSync(MARKETPLACE_PATH, 'utf-8');
    const data = JSON.parse(raw);
    // marketplace.json 可能是数组，也可能是 { plugins: [...] }
    const plugins = Array.isArray(data) ? data : data.plugins ?? [];
    const entry = plugins.find((p) => p.name === 'autopilot');

    assert.ok(
      entry !== undefined,
      `.claude-plugin/marketplace.json 中必须存在 name="autopilot" 的条目`
    );
    assert.strictEqual(
      entry.version,
      TARGET_VERSION,
      `marketplace.json autopilot 条目 version 必须为 "${TARGET_VERSION}"，当前为 "${entry.version}"`
    );
  });

  it('Scene V-d: CLAUDE.md 插件索引表 autopilot 行包含 "3.23.0"', () => {
    const content = readFileSync(CLAUDE_MD_PATH, 'utf-8');
    // CLAUDE.md 插件索引表中 autopilot 行应含版本号（v3.23.0 或 3.23.0）
    const lines = linesOf(content);
    const autopilotIndexLine = lines.find(
      (l) => l.includes('autopilot') && l.includes(TARGET_VERSION)
    );
    assert.ok(
      autopilotIndexLine !== undefined,
      `CLAUDE.md 插件索引表中必须有包含 "autopilot" 且含 "${TARGET_VERSION}" 的行（蓝队 T5 要求同步索引表）`
    );
  });

  it('Scene V-e: plugin.json 与 marketplace.json 中 autopilot 版本完全一致', () => {
    const pluginData = JSON.parse(readFileSync(PLUGIN_JSON_PATH, 'utf-8'));
    const raw = readFileSync(MARKETPLACE_PATH, 'utf-8');
    const data = JSON.parse(raw);
    const plugins = Array.isArray(data) ? data : data.plugins ?? [];
    const entry = plugins.find((p) => p.name === 'autopilot');

    assert.ok(
      entry !== undefined,
      'marketplace.json 中必须存在 autopilot 条目（已在 V-c 验证，此处防止 undefined 污染后续比较）'
    );
    assert.strictEqual(
      pluginData.version,
      entry.version,
      `plugin.json（${pluginData.version}）与 marketplace.json（${entry.version}）版本不一致，必须完全同步`
    );
  });
});
