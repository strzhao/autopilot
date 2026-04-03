/**
 * Acceptance tests for autopilot token optimization (v3.6.0).
 *
 * Red-team verification: tests are written purely from the design document,
 * without reading the blue-team implementation.
 *
 * Design spec:
 *   5 optimization items:
 *   1. Sub-agent prompt templates slimmed (4 files)
 *   2. Explore agent guidance enhanced in SKILL.md
 *   3. SKILL.md content compressed (anti-rationalization table, lessons, templates, code blocks, comments)
 *   4. Wave 1.5 dev server operation guidance added
 *   5. State-file operation guidance added (new file: references/state-file-guide.md)
 *
 * Key invariants that must NOT be lost:
 *   1. SKILL.md has >= 17 critical constraint terms
 *   2. SKILL.md has exactly 5 model: "sonnet" injection points
 *   3. All Phase routing logic intact
 *   4. All anti-rationalization tables preserved (may be compressed)
 *   5. plan-reviewer 6 review dimensions all present
 *   6. design-reviewer core review logic preserved
 *   7. code-quality-reviewer Pass 1/Pass 2 structure preserved
 *   8. references/state-file-guide.md must exist
 *   9. SKILL.md Explore agent guidance includes "1-2 个"
 *  10. SKILL.md Wave 1.5 includes dev server startup specification
 *  11. Version number 3.6.0 consistency
 *
 * Target line counts after optimization:
 *   - SKILL.md: < 580 lines (currently 658)
 *   - plan-reviewer-prompt.md: <= 85 lines (currently 126)
 *   - design-reviewer-prompt.md: <= 75 lines (currently 111)
 *   - code-quality-reviewer-prompt.md (merged with review-checklist.md): <= 125 lines (currently 130+136=266)
 *   - knowledge-engineering.md: <= 155 lines (currently 230)
 *
 * Run: node --test tests/token-optimization.acceptance.test.mjs
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
const PLAN_REVIEWER_PATH = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot/references/plan-reviewer-prompt.md'
);
const DESIGN_REVIEWER_PATH = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot/references/design-reviewer-prompt.md'
);
const CODE_QUALITY_REVIEWER_PATH = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot/references/code-quality-reviewer-prompt.md'
);
const REVIEW_CHECKLIST_PATH = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot/references/review-checklist.md'
);
const KNOWLEDGE_ENG_PATH = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot/references/knowledge-engineering.md'
);
const STATE_FILE_GUIDE_PATH = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot/references/state-file-guide.md'
);
const PLUGIN_JSON_PATH = resolve(
  ROOT,
  'plugins/autopilot/.claude-plugin/plugin.json'
);
const MARKETPLACE_PATH = resolve(ROOT, '.claude-plugin/marketplace.json');
const CLAUDE_MD_PATH = resolve(ROOT, 'CLAUDE.md');

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------
function countLines(filePath) {
  const content = readFileSync(filePath, 'utf-8');
  return content.split('\n').length;
}

// ---------------------------------------------------------------------------
// 1. Line count constraints
// ---------------------------------------------------------------------------
describe('line count constraints after token optimization', () => {
  it('SKILL.md must be < 580 lines (currently 658)', () => {
    const lines = countLines(SKILL_PATH);
    assert.ok(
      lines < 580,
      `SKILL.md must be < 580 lines after optimization, got ${lines}`
    );
  });

  it('plan-reviewer-prompt.md must be <= 85 lines (currently 126)', () => {
    const lines = countLines(PLAN_REVIEWER_PATH);
    assert.ok(
      lines <= 85,
      `plan-reviewer-prompt.md must be <= 85 lines after optimization, got ${lines}`
    );
  });

  it('design-reviewer-prompt.md must be <= 75 lines (currently 111)', () => {
    const lines = countLines(DESIGN_REVIEWER_PATH);
    assert.ok(
      lines <= 75,
      `design-reviewer-prompt.md must be <= 75 lines after optimization, got ${lines}`
    );
  });

  it('code-quality-reviewer-prompt.md must be <= 125 lines after merging review-checklist (currently combined 266)', () => {
    // Design doc says: code-quality-reviewer-prompt.md 130 + review-checklist.md 136 → merged <= 125
    // This means the checklist content is absorbed into the reviewer prompt, or both are reduced
    // We check the combined outcome: either merged file <= 125 or merged total <= 125
    const reviewerLines = countLines(CODE_QUALITY_REVIEWER_PATH);
    // If review-checklist.md still exists separately, check combined
    if (existsSync(REVIEW_CHECKLIST_PATH)) {
      const checklistLines = countLines(REVIEW_CHECKLIST_PATH);
      const combined = reviewerLines + checklistLines;
      assert.ok(
        combined <= 125,
        `code-quality-reviewer-prompt.md (${reviewerLines}) + review-checklist.md (${checklistLines}) combined must be <= 125 lines, got ${combined}`
      );
    } else {
      // review-checklist.md was merged into reviewer prompt
      assert.ok(
        reviewerLines <= 125,
        `code-quality-reviewer-prompt.md (merged) must be <= 125 lines, got ${reviewerLines}`
      );
    }
  });

  it('knowledge-engineering.md must be <= 155 lines (currently 230)', () => {
    const lines = countLines(KNOWLEDGE_ENG_PATH);
    assert.ok(
      lines <= 155,
      `knowledge-engineering.md must be <= 155 lines after optimization, got ${lines}`
    );
  });
});

// ---------------------------------------------------------------------------
// 2. Invariant 1: SKILL.md critical constraint terms (>= 17)
// ---------------------------------------------------------------------------
describe('SKILL.md critical constraint terms preserved', () => {
  it('must contain at least 17 occurrences of critical constraint keywords', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const constraintTerms = [
      '防合理化',
      '铁律',
      '教训',
      '不允许',
      '绝对不能',
      '绝对禁止',
    ];
    let totalCount = 0;
    const termCounts = {};
    for (const term of constraintTerms) {
      const matches = content.split(term).length - 1;
      termCounts[term] = matches;
      totalCount += matches;
    }
    assert.ok(
      totalCount >= 17,
      `SKILL.md must have >= 17 total occurrences of critical constraint terms, got ${totalCount}. Breakdown: ${JSON.stringify(termCounts)}`
    );
  });

  it('must still contain "防合理化" at least once', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    assert.ok(
      content.includes('防合理化'),
      'SKILL.md must still contain "防合理化" (anti-rationalization) term'
    );
  });

  it('must still contain "铁律" at least twice (core ironclad rules)', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const count = content.split('铁律').length - 1;
    assert.ok(
      count >= 2,
      `SKILL.md must contain "铁律" at least 2 times, got ${count}`
    );
  });

  it('must still contain "绝对" (absolute prohibition) terms', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const hasAbsolute =
      content.includes('绝对不能') || content.includes('绝对禁止');
    assert.ok(
      hasAbsolute,
      'SKILL.md must still contain absolute prohibition terms (绝对不能/绝对禁止)'
    );
  });
});

// ---------------------------------------------------------------------------
// 3. Invariant 2: SKILL.md has exactly 5 model: "sonnet" injection points
// ---------------------------------------------------------------------------
describe('SKILL.md model: "sonnet" injection points preserved', () => {
  it('must contain exactly 5 occurrences of model: "sonnet"', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const matches = content.match(/model:\s*["']sonnet["']/g) || [];
    assert.equal(
      matches.length,
      5,
      `SKILL.md must have exactly 5 occurrences of model: "sonnet", found ${matches.length}`
    );
  });
});

// ---------------------------------------------------------------------------
// 4. Invariant 3: All Phase routing logic intact
// ---------------------------------------------------------------------------
describe('SKILL.md Phase routing logic completeness', () => {
  const phases = ['design', 'implement', 'qa', 'auto-fix', 'merge'];

  for (const phase of phases) {
    it(`Phase: ${phase} section must exist`, () => {
      const content = readFileSync(SKILL_PATH, 'utf-8');
      const pattern = new RegExp(`Phase:\\s*${phase}`, 'i');
      assert.ok(
        pattern.test(content),
        `SKILL.md must contain Phase: ${phase} section`
      );
    });
  }

  it('startup flow (启动流程) must describe how to route to each phase', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    // Startup section should mention reading state file and routing
    const startupMatch = content.match(
      /##[#\s]*启动流程([\s\S]*?)(?=\n##\s|$)/
    );
    assert.ok(startupMatch, 'SKILL.md must have a 启动流程 section');
    const startupSection = startupMatch[1];
    // Must mention state file
    const hasStateFile =
      startupSection.includes('autopilot.md') ||
      startupSection.includes('state') ||
      startupSection.includes('状态');
    assert.ok(
      hasStateFile,
      '启动流程 section must reference the state file for routing decisions'
    );
  });
});

// ---------------------------------------------------------------------------
// 5. Invariant 4: Anti-rationalization tables preserved (can be compressed)
// ---------------------------------------------------------------------------
describe('SKILL.md anti-rationalization tables preserved', () => {
  it('must contain at least one anti-rationalization table (Markdown table format near 防合理化)', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const antiRationIdx = content.indexOf('防合理化');
    assert.ok(
      antiRationIdx !== -1,
      'SKILL.md must contain 防合理化 section'
    );
    // Look for a Markdown table within 2000 chars of the term
    const surrounding = content.slice(
      Math.max(0, antiRationIdx - 100),
      Math.min(content.length, antiRationIdx + 2000)
    );
    assert.ok(
      /\|.+\|/.test(surrounding),
      'SKILL.md must contain an anti-rationalization table (Markdown table format) near 防合理化'
    );
  });

  it('anti-rationalization content must include "借口" or "理由" examples', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const hasExamples =
      content.includes('借口') || content.includes('理由');
    assert.ok(
      hasExamples,
      'SKILL.md must contain "借口" or "理由" examples in anti-rationalization content'
    );
  });
});

// ---------------------------------------------------------------------------
// 6. Invariant 5: plan-reviewer 6 review dimensions all present
// ---------------------------------------------------------------------------
describe('plan-reviewer-prompt.md 6 review dimensions preserved', () => {
  const dimensions = [
    '需求完整性',
    '技术可行性',
    '任务分解',
    '验证',
    '风险',
    '范围控制',
  ];

  for (const dim of dimensions) {
    it(`must contain dimension: "${dim}"`, () => {
      const content = readFileSync(PLAN_REVIEWER_PATH, 'utf-8');
      assert.ok(
        content.includes(dim),
        `plan-reviewer-prompt.md must still contain dimension "${dim}" after optimization`
      );
    });
  }

  it('must still contain BLOCKER/PASS/FAIL judgment structure', () => {
    const content = readFileSync(PLAN_REVIEWER_PATH, 'utf-8');
    assert.ok(
      content.includes('BLOCKER'),
      'plan-reviewer-prompt.md must retain BLOCKER severity level'
    );
    assert.ok(
      content.includes('PASS') || content.includes('FAIL'),
      'plan-reviewer-prompt.md must retain PASS/FAIL judgment'
    );
  });
});

// ---------------------------------------------------------------------------
// 7. Invariant 6: design-reviewer core review logic preserved
// ---------------------------------------------------------------------------
describe('design-reviewer-prompt.md core logic preserved', () => {
  it('file must exist', () => {
    assert.ok(
      existsSync(DESIGN_REVIEWER_PATH),
      `design-reviewer-prompt.md must exist at ${DESIGN_REVIEWER_PATH}`
    );
  });

  it('must retain design conformance review goal', () => {
    const content = readFileSync(DESIGN_REVIEWER_PATH, 'utf-8');
    const hasConformance =
      content.includes('设计符合') ||
      content.includes('设计方案') ||
      content.includes('design') ||
      content.includes('符合性');
    assert.ok(
      hasConformance,
      'design-reviewer-prompt.md must retain design conformance review purpose'
    );
  });

  it('must retain verdict summary section (总结 or equivalent)', () => {
    const content = readFileSync(DESIGN_REVIEWER_PATH, 'utf-8');
    const hasVerdict =
      content.includes('总结') ||
      content.includes('PASS') ||
      content.includes('FAIL') ||
      content.includes('通过') ||
      content.includes('设计符合') ||
      content.includes('符合');
    assert.ok(
      hasVerdict,
      'design-reviewer-prompt.md must retain verdict/summary section'
    );
  });

  it('must retain independent verification principle (不信任/独立验证)', () => {
    const content = readFileSync(DESIGN_REVIEWER_PATH, 'utf-8');
    const hasDistrust =
      content.includes('不信任') ||
      content.includes('独立验证') ||
      content.toLowerCase().includes('independent') ||
      content.toLowerCase().includes('distrust');
    assert.ok(
      hasDistrust,
      'design-reviewer-prompt.md must retain independent verification / distrust principle (core logic)'
    );
  });

  it('must retain output format with requirement verification table', () => {
    const content = readFileSync(DESIGN_REVIEWER_PATH, 'utf-8');
    // Must have some tabular output format for requirement verification
    const hasTable = /\|.+\|/.test(content);
    assert.ok(
      hasTable,
      'design-reviewer-prompt.md must retain a requirement verification table in output format'
    );
  });
});

// ---------------------------------------------------------------------------
// 8. Invariant 7: code-quality-reviewer Pass 1/Pass 2 structure preserved
// ---------------------------------------------------------------------------
describe('code-quality-reviewer-prompt.md Pass 1/Pass 2 structure preserved', () => {
  it('file must exist', () => {
    assert.ok(
      existsSync(CODE_QUALITY_REVIEWER_PATH),
      `code-quality-reviewer-prompt.md must exist at ${CODE_QUALITY_REVIEWER_PATH}`
    );
  });

  it('must retain Pass 1 and Pass 2 check structure', () => {
    const content = readFileSync(CODE_QUALITY_REVIEWER_PATH, 'utf-8');
    const hasPass1 =
      content.includes('Pass 1') ||
      content.includes('Pass1') ||
      content.includes('第一遍') ||
      content.includes('pass 1');
    const hasPass2 =
      content.includes('Pass 2') ||
      content.includes('Pass2') ||
      content.includes('第二遍') ||
      content.includes('pass 2');
    assert.ok(
      hasPass1,
      'code-quality-reviewer-prompt.md must retain Pass 1 check structure'
    );
    assert.ok(
      hasPass2,
      'code-quality-reviewer-prompt.md must retain Pass 2 check structure'
    );
  });

  it('must retain confidence threshold for filtering false positives', () => {
    const content = readFileSync(CODE_QUALITY_REVIEWER_PATH, 'utf-8');
    assert.ok(
      content.includes('80'),
      'code-quality-reviewer-prompt.md must retain confidence threshold of 80 for filtering false positives'
    );
  });

  it('must retain prohibition against editing files', () => {
    const content = readFileSync(CODE_QUALITY_REVIEWER_PATH, 'utf-8');
    const hasReadOnly =
      content.includes('不能编辑') ||
      content.includes('禁止编辑') ||
      content.includes('只读') ||
      content.toLowerCase().includes('read-only') ||
      content.toLowerCase().includes('must not edit') ||
      content.toLowerCase().includes('do not edit') ||
      content.toLowerCase().includes('cannot edit');
    assert.ok(
      hasReadOnly,
      'code-quality-reviewer-prompt.md must retain read-only / no-editing constraint'
    );
  });
});

// ---------------------------------------------------------------------------
// 9. Invariant 8: references/state-file-guide.md must exist
// ---------------------------------------------------------------------------
describe('state-file-guide.md existence', () => {
  it('references/state-file-guide.md must exist as a new file', () => {
    assert.ok(
      existsSync(STATE_FILE_GUIDE_PATH),
      `references/state-file-guide.md must exist at ${STATE_FILE_GUIDE_PATH}`
    );
  });

  it('state-file-guide.md must describe state file fields', () => {
    const content = readFileSync(STATE_FILE_GUIDE_PATH, 'utf-8');
    // Must describe at least phase, iteration fields
    const hasPhase =
      content.includes('phase') || content.includes('阶段');
    const hasIteration =
      content.includes('iteration') || content.includes('迭代');
    assert.ok(
      hasPhase,
      'state-file-guide.md must describe the "phase" field'
    );
    assert.ok(
      hasIteration,
      'state-file-guide.md must describe the "iteration" field'
    );
  });

  it('state-file-guide.md must include instructions for updating the state file', () => {
    const content = readFileSync(STATE_FILE_GUIDE_PATH, 'utf-8');
    const hasUpdateInstruction =
      content.includes('更新') ||
      content.includes('修改') ||
      content.toLowerCase().includes('update') ||
      content.toLowerCase().includes('write');
    assert.ok(
      hasUpdateInstruction,
      'state-file-guide.md must include instructions for updating the state file'
    );
  });
});

// ---------------------------------------------------------------------------
// 10. Invariant 9: SKILL.md Explore agent guidance includes "1-2 个"
// ---------------------------------------------------------------------------
describe('SKILL.md Explore agent guidance', () => {
  it('must contain Explore agent section or reference', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const hasExplore =
      content.includes('Explore') || content.includes('explore');
    assert.ok(
      hasExplore,
      'SKILL.md must contain Explore agent reference or section'
    );
  });

  it('Explore agent guidance must include "1-2 个" quantity suggestion', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    // Find Explore section and check for quantity guidance
    const exploreIdx = content.indexOf('Explore');
    assert.ok(exploreIdx !== -1, 'SKILL.md must mention Explore');
    const surrounding = content.slice(
      Math.max(0, exploreIdx - 200),
      Math.min(content.length, exploreIdx + 1500)
    );
    assert.ok(
      surrounding.includes('1-2 个') || surrounding.includes('1-2个'),
      'SKILL.md Explore agent guidance must include "1-2 个" quantity recommendation'
    );
  });
});

// ---------------------------------------------------------------------------
// 11. Invariant 10: SKILL.md Wave 1.5 includes dev server startup specification
// ---------------------------------------------------------------------------
describe('SKILL.md Wave 1.5 dev server startup specification', () => {
  it('must contain Wave 1.5 section or reference', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const hasWave15 =
      content.includes('Wave 1.5') || content.includes('wave 1.5');
    assert.ok(
      hasWave15,
      'SKILL.md must contain Wave 1.5 section'
    );
  });

  it('Wave 1.5 must include dev server startup specification', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const wave15Idx = content.indexOf('Wave 1.5');
    assert.ok(wave15Idx !== -1, 'SKILL.md must contain Wave 1.5');
    const surrounding = content.slice(
      Math.max(0, wave15Idx - 100),
      Math.min(content.length, wave15Idx + 2000)
    );
    const hasDevServer =
      surrounding.includes('dev server') ||
      surrounding.includes('dev-server') ||
      surrounding.includes('开发服务器') ||
      surrounding.includes('npm run dev') ||
      surrounding.includes('start') ||
      surrounding.includes('启动');
    assert.ok(
      hasDevServer,
      'SKILL.md Wave 1.5 must include dev server startup specification'
    );
  });
});

// ---------------------------------------------------------------------------
// 12. Invariant 11: Version 3.6.0 consistency
// ---------------------------------------------------------------------------
describe('version consistency (v3.6.0)', () => {
  it('plugin.json version must be "3.6.0"', () => {
    const content = readFileSync(PLUGIN_JSON_PATH, 'utf-8');
    const json = JSON.parse(content);
    assert.equal(
      json.version,
      '3.6.0',
      `plugin.json version must be "3.6.0", got "${json.version}"`
    );
  });

  it('marketplace.json autopilot version must be "3.6.0"', () => {
    const content = readFileSync(MARKETPLACE_PATH, 'utf-8');
    const json = JSON.parse(content);
    const autopilot = json.plugins?.find(
      (p) => p.name === 'autopilot' || p.id === 'autopilot'
    );
    assert.ok(
      autopilot,
      'marketplace.json must contain an autopilot plugin entry'
    );
    assert.equal(
      autopilot.version,
      '3.6.0',
      `marketplace.json autopilot version must be "3.6.0", got "${autopilot.version}"`
    );
  });

  it('CLAUDE.md must reference autopilot version 3.6.0', () => {
    const content = readFileSync(CLAUDE_MD_PATH, 'utf-8');
    assert.ok(
      content.includes('3.6.0'),
      'CLAUDE.md must reference autopilot version 3.6.0'
    );
  });
});

// ---------------------------------------------------------------------------
// 13. knowledge-engineering.md essential content preserved
// ---------------------------------------------------------------------------
describe('knowledge-engineering.md essential content preserved after compression', () => {
  it('file must still exist', () => {
    assert.ok(
      existsSync(KNOWLEDGE_ENG_PATH),
      `knowledge-engineering.md must still exist at ${KNOWLEDGE_ENG_PATH}`
    );
  });

  it('must retain decisions.md and patterns.md file references', () => {
    const content = readFileSync(KNOWLEDGE_ENG_PATH, 'utf-8');
    assert.ok(
      content.includes('decisions.md'),
      'knowledge-engineering.md must retain reference to decisions.md'
    );
    assert.ok(
      content.includes('patterns.md'),
      'knowledge-engineering.md must retain reference to patterns.md'
    );
  });

  it('must retain design phase consumption guidance', () => {
    const content = readFileSync(KNOWLEDGE_ENG_PATH, 'utf-8');
    const hasDesignPhase =
      content.includes('design') ||
      content.includes('设计阶段') ||
      content.includes('消费');
    assert.ok(
      hasDesignPhase,
      'knowledge-engineering.md must retain design phase knowledge consumption guidance'
    );
  });

  it('must retain merge phase extraction guidance', () => {
    const content = readFileSync(KNOWLEDGE_ENG_PATH, 'utf-8');
    const hasMergePhase =
      content.includes('merge') ||
      content.includes('合并阶段') ||
      content.includes('提取');
    assert.ok(
      hasMergePhase,
      'knowledge-engineering.md must retain merge phase knowledge extraction guidance'
    );
  });

  it('must retain single-file line limit constraint (<=150 lines)', () => {
    const content = readFileSync(KNOWLEDGE_ENG_PATH, 'utf-8');
    assert.ok(
      content.includes('150'),
      'knowledge-engineering.md must retain the <=150 lines per file constraint'
    );
  });
});

// ---------------------------------------------------------------------------
// 14. SKILL.md overall structural integrity
// ---------------------------------------------------------------------------
describe('SKILL.md overall structural integrity after compression', () => {
  it('must still contain 核心铁律 section', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    assert.ok(
      /##[#\s]*核心铁律/.test(content),
      'SKILL.md must retain 核心铁律 (core ironclad rules) section'
    );
  });

  it('must still contain 成本优化 section from v3.5.2', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    assert.ok(
      content.includes('成本优化'),
      'SKILL.md must retain 成本优化 (cost optimization) section from v3.5.2'
    );
  });

  it('must still contain 启动流程 section', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    assert.ok(
      /##[#\s]*启动流程/.test(content),
      'SKILL.md must retain 启动流程 (startup flow) section'
    );
  });

  it('must retain red-team and blue-team contrast principle', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const hasRedTeam =
      content.includes('红队') || content.toLowerCase().includes('red-team');
    const hasBlueTeam =
      content.includes('蓝队') || content.toLowerCase().includes('blue-team');
    assert.ok(hasRedTeam, 'SKILL.md must retain red-team (红队) reference');
    assert.ok(hasBlueTeam, 'SKILL.md must retain blue-team (蓝队) reference');
  });

  it('must retain auto-fix retry limit (max 3)', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const hasRetryLimit =
      content.includes('3 次') ||
      content.includes('3次') ||
      content.includes('三次') ||
      content.includes('max 3') ||
      content.includes('maximum 3');
    assert.ok(
      hasRetryLimit,
      'SKILL.md must retain auto-fix retry limit (max 3 times)'
    );
  });

  it('must not expand beyond 580 lines (line ceiling check)', () => {
    const lines = countLines(SKILL_PATH);
    // Asserting from the other direction: definitely not above 580
    assert.ok(
      lines < 580,
      `SKILL.md must stay below 580 lines, currently at ${lines}`
    );
  });
});
