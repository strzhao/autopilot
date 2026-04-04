/**
 * Acceptance tests for autopilot Tier 1.5 execution enforcement + SKILL.md slimdown.
 *
 * Red-team verification: tests are written purely from the design document,
 * without reading the blue-team implementation.
 *
 * Design spec:
 *   - Improvement 1: SKILL.md Tier 1.5 scenario count check in result judgment
 *   - Improvement 2: stop-hook.sh QA prompt injection for Tier 1.5 completeness
 *   - Improvement 3: red-team-prompt.md cross-system data flow testing
 *   - Improvement 4: blue-team-prompt.md endpoint existence verification
 *   - Slimdown 1: QA report template externalized to references/qa-report-template.md
 *   - Slimdown 2: Completion report template externalized to references/completion-report-template.md
 *   - Constraint: SKILL.md final line count <= 650
 *   - Knowledge: patterns.md + index.md updated with Tier 1.5 lesson
 *
 * Run: node --test tests/tier15-enforcement-slimdown.acceptance.test.mjs
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');

const SKILL_PATH = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot/SKILL.md'
);
const STOP_HOOK_PATH = resolve(
  ROOT,
  'plugins/autopilot/scripts/stop-hook.sh'
);
const RED_TEAM_PATH = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot/references/red-team-prompt.md'
);
const BLUE_TEAM_PATH = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot/references/blue-team-prompt.md'
);
const QA_REPORT_TEMPLATE_PATH = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot/references/qa-report-template.md'
);
const COMPLETION_REPORT_TEMPLATE_PATH = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot/references/completion-report-template.md'
);
const PATTERNS_PATH = resolve(ROOT, '.autopilot/patterns.md');
const INDEX_PATH = resolve(ROOT, '.autopilot/index.md');

// ---------------------------------------------------------------------------
// 1. SKILL.md Tier 1.5 scenario count check (Improvement 1)
// ---------------------------------------------------------------------------
describe('Improvement 1: SKILL.md Tier 1.5 scenario count check', () => {
  it('result judgment section must mention scenario count matching/verification', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    // Must contain concept of scenario count check/match
    const hasScenarioCountCheck =
      content.includes('场景计数') ||
      content.includes('场景数') ||
      content.includes('scenario count') ||
      (content.includes('场景') && content.includes('计数'));
    assert.ok(
      hasScenarioCountCheck,
      'SKILL.md must contain scenario count matching/verification in result judgment'
    );
  });

  it('result judgment must contain format check as prerequisite', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const hasFormatCheck =
      content.includes('格式检查') ||
      content.includes('format check') ||
      content.includes('格式校验');
    assert.ok(
      hasFormatCheck,
      'SKILL.md result judgment must include format check step'
    );
  });

  it('anti-rationalization table must contain "场景 1" partial execution entry', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    // The anti-rationalization table must guard against "scenario 1 already verified core flow"
    const hasScenario1Entry =
      content.includes('场景 1') ||
      content.includes('场景1') ||
      content.includes('scenario 1');
    assert.ok(
      hasScenario1Entry,
      'Anti-rationalization table must contain entry about "场景 1 已验证了核心流程"'
    );
  });

  it('must reference little-bee-cli lesson', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const hasLittleBee =
      content.includes('little-bee-cli') ||
      content.includes('little-bee');
    assert.ok(
      hasLittleBee,
      'SKILL.md must reference little-bee-cli lesson for Tier 1.5 enforcement'
    );
  });
});

// ---------------------------------------------------------------------------
// 2. stop-hook.sh QA prompt injection (Improvement 2)
// ---------------------------------------------------------------------------
describe('Improvement 2: stop-hook.sh QA prompt injection for Tier 1.5', () => {
  it('stop-hook.sh must exist', () => {
    assert.ok(
      existsSync(STOP_HOOK_PATH),
      `stop-hook.sh must exist at ${STOP_HOOK_PATH}`
    );
  });

  it('stop-hook.sh must handle phase=="qa" with Tier 1.5 completeness reminder', () => {
    const content = readFileSync(STOP_HOOK_PATH, 'utf-8');
    // Must have a qa phase handler
    const hasQaPhase =
      content.includes('"qa"') || content.includes("'qa'") || content.includes('qa)');
    assert.ok(hasQaPhase, 'stop-hook.sh must handle qa phase');

    // Must contain Tier 1.5 reference in the qa section
    const hasTier15 =
      content.includes('Tier 1.5') ||
      content.includes('tier 1.5') ||
      content.includes('Tier1.5');
    assert.ok(
      hasTier15,
      'stop-hook.sh must contain Tier 1.5 completeness reminder in QA prompt'
    );
  });

  it('QA prompt must require full execution with "每一个" or equivalent', () => {
    const content = readFileSync(STOP_HOOK_PATH, 'utf-8');
    const hasFullExecution =
      content.includes('每一个') ||
      content.includes('每个') ||
      content.includes('全部') ||
      content.includes('所有场景') ||
      content.includes('all scenario') ||
      content.includes('every scenario') ||
      content.includes('全量');
    assert.ok(
      hasFullExecution,
      'stop-hook.sh QA prompt must require full execution of all scenarios'
    );
  });
});

// ---------------------------------------------------------------------------
// 3. red-team-prompt.md cross-system data flow testing (Improvement 3)
// ---------------------------------------------------------------------------
describe('Improvement 3: red-team-prompt.md cross-system data flow', () => {
  it('red-team-prompt.md must exist', () => {
    assert.ok(
      existsSync(RED_TEAM_PATH),
      `red-team-prompt.md must exist at ${RED_TEAM_PATH}`
    );
  });

  it('must contain cross-system data flow verification rule', () => {
    const content = readFileSync(RED_TEAM_PATH, 'utf-8');
    const hasCrossSystem =
      content.includes('跨系统') ||
      content.includes('cross-system') ||
      content.includes('数据流') ||
      content.includes('data flow') ||
      content.includes('端到端') ||
      content.includes('end-to-end');
    assert.ok(
      hasCrossSystem,
      'red-team-prompt.md must contain cross-system data flow verification work rule'
    );
  });
});

// ---------------------------------------------------------------------------
// 4. blue-team-prompt.md endpoint existence verification (Improvement 4)
// ---------------------------------------------------------------------------
describe('Improvement 4: blue-team-prompt.md endpoint existence verification', () => {
  it('blue-team-prompt.md must exist', () => {
    assert.ok(
      existsSync(BLUE_TEAM_PATH),
      `blue-team-prompt.md must exist at ${BLUE_TEAM_PATH}`
    );
  });

  it('must contain endpoint existence verification rule', () => {
    const content = readFileSync(BLUE_TEAM_PATH, 'utf-8');
    const hasEndpointVerification =
      content.includes('端点') ||
      content.includes('endpoint') ||
      content.includes('API') ||
      content.includes('路由') ||
      content.includes('route');
    const hasExistence =
      content.includes('存在性') ||
      content.includes('existence') ||
      content.includes('存在') ||
      content.includes('exist') ||
      content.includes('验证');
    assert.ok(
      hasEndpointVerification && hasExistence,
      'blue-team-prompt.md must contain endpoint existence verification work rule'
    );
  });
});

// ---------------------------------------------------------------------------
// 5. QA report template externalized (Slimdown 1)
// ---------------------------------------------------------------------------
describe('Slimdown 1: QA report template externalized', () => {
  it('references/qa-report-template.md must exist', () => {
    assert.ok(
      existsSync(QA_REPORT_TEMPLATE_PATH),
      `qa-report-template.md must exist at ${QA_REPORT_TEMPLATE_PATH}`
    );
  });

  it('qa-report-template.md must contain complete QA report format', () => {
    const content = readFileSync(QA_REPORT_TEMPLATE_PATH, 'utf-8');
    // Must contain key QA report sections
    const hasTierSections =
      content.includes('Tier 0') ||
      content.includes('Tier 1') ||
      content.includes('红队') ||
      content.includes('red team');
    assert.ok(
      hasTierSections,
      'qa-report-template.md must contain tier-based QA sections'
    );

    const hasResultFormat =
      content.includes('PASS') || content.includes('FAIL') || content.includes('通过') || content.includes('失败');
    assert.ok(
      hasResultFormat,
      'qa-report-template.md must contain PASS/FAIL result format'
    );
  });

  it('SKILL.md 产出报告 section must reference qa-report-template.md, not inline full template', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    // Must reference the external file
    const hasReference =
      content.includes('qa-report-template.md') ||
      content.includes('qa-report-template');
    assert.ok(
      hasReference,
      'SKILL.md 产出報告 section must reference qa-report-template.md'
    );
  });
});

// ---------------------------------------------------------------------------
// 6. Completion report template externalized (Slimdown 2)
// ---------------------------------------------------------------------------
describe('Slimdown 2: Completion report template externalized', () => {
  it('references/completion-report-template.md must exist', () => {
    assert.ok(
      existsSync(COMPLETION_REPORT_TEMPLATE_PATH),
      `completion-report-template.md must exist at ${COMPLETION_REPORT_TEMPLATE_PATH}`
    );
  });

  it('completion-report-template.md must contain 6 report blocks', () => {
    const content = readFileSync(COMPLETION_REPORT_TEMPLATE_PATH, 'utf-8');
    // Count heading-level sections (## or ###)
    const headings = content.match(/^#{1,3}\s+.+$/gm) || [];
    assert.ok(
      headings.length >= 6,
      `completion-report-template.md must contain at least 6 report blocks/sections, found ${headings.length}`
    );
  });

  it('SKILL.md Phase: merge step 3 must reference completion-report-template.md', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    // Extract Phase: merge section
    const mergeMatch = content.match(
      /##\s*Phase:\s*merge([\s\S]*?)(?=##\s*Phase:|$)/i
    );
    assert.ok(mergeMatch, 'SKILL.md must have a "Phase: merge" section');
    const mergeSection = mergeMatch[1];

    const hasReference =
      mergeSection.includes('completion-report-template.md') ||
      mergeSection.includes('completion-report-template');
    assert.ok(
      hasReference,
      'Phase: merge must reference completion-report-template.md'
    );
  });
});

// ---------------------------------------------------------------------------
// 7. SKILL.md line count constraint
// ---------------------------------------------------------------------------
describe('SKILL.md line count constraint', () => {
  it('SKILL.md must have <= 650 lines', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const lineCount = content.split('\n').length;
    assert.ok(
      lineCount <= 650,
      `SKILL.md must have <= 650 lines, currently has ${lineCount} lines`
    );
  });
});

// ---------------------------------------------------------------------------
// 8. Knowledge updates
// ---------------------------------------------------------------------------
describe('Knowledge updates for Tier 1.5 lesson', () => {
  it('patterns.md must contain Tier 1.5 partial execution lesson', () => {
    const content = readFileSync(PATTERNS_PATH, 'utf-8');
    const hasTier15Lesson =
      content.includes('Tier 1.5') ||
      content.includes('场景部分执行') ||
      content.includes('partial execution') ||
      (content.includes('场景') && content.includes('部分'));
    assert.ok(
      hasTier15Lesson,
      'patterns.md must contain a lesson about Tier 1.5 scenario partial execution'
    );
  });

  it('index.md must contain corresponding index entry', () => {
    const content = readFileSync(INDEX_PATH, 'utf-8');
    const hasIndexEntry =
      content.includes('Tier 1.5') ||
      content.includes('场景部分执行') ||
      content.includes('partial execution') ||
      content.includes('tier-15') ||
      content.includes('场景计数');
    assert.ok(
      hasIndexEntry,
      'index.md must contain an index entry for the Tier 1.5 lesson'
    );
  });
});
