/**
 * Acceptance tests for plan-reviewer sub-agent in autopilot design phase.
 *
 * Red-team verification: tests are written purely from the design document,
 * without reading the blue-team implementation.
 *
 * Design spec:
 *   - New file: references/plan-reviewer-prompt.md (review prompt template)
 *   - Modified: SKILL.md Phase: design (insert step 3 - Plan Review)
 *   - 6 review dimensions + confidence filtering (>=90 BLOCKER, 80-89 suggestion)
 *   - Max 2 review rounds
 *   - Version bump to 2.14.0
 *   - CLAUDE.md updated with plan-review capability
 *
 * Run: node --test tests/plan-reviewer.acceptance.test.mjs
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');

const PROMPT_PATH = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot/references/plan-reviewer-prompt.md'
);
const SKILL_PATH = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot/SKILL.md'
);
const PLUGIN_JSON_PATH = resolve(
  ROOT,
  'plugins/autopilot/.claude-plugin/plugin.json'
);
const MARKETPLACE_PATH = resolve(ROOT, '.claude-plugin/marketplace.json');
const CLAUDE_MD_PATH = resolve(ROOT, 'CLAUDE.md');

// ---------------------------------------------------------------------------
// 1. plan-reviewer-prompt.md structure integrity
// ---------------------------------------------------------------------------
describe('plan-reviewer-prompt.md structure integrity', () => {
  it('file must exist', () => {
    assert.ok(
      existsSync(PROMPT_PATH),
      `plan-reviewer-prompt.md must exist at ${PROMPT_PATH}`
    );
  });

  it('must contain all 6 review dimensions', () => {
    const content = readFileSync(PROMPT_PATH, 'utf-8');
    const dimensions = [
      '需求完整性',
      '技术可行性',
      '任务分解',
      '验证方案',
      '风险',
      '范围控制',
    ];
    for (const dim of dimensions) {
      assert.ok(
        content.includes(dim),
        `plan-reviewer-prompt.md must mention review dimension: "${dim}"`
      );
    }
  });

  it('must contain confidence scoring system with BLOCKER and suggestion thresholds', () => {
    const content = readFileSync(PROMPT_PATH, 'utf-8');
    // Must mention BLOCKER level (91-100 or >=90)
    assert.ok(
      content.includes('BLOCKER'),
      'plan-reviewer-prompt.md must define BLOCKER confidence level'
    );
    // Must mention the scoring ranges
    assert.ok(
      /9[01]/.test(content) || content.includes('90'),
      'plan-reviewer-prompt.md must reference confidence threshold around 90'
    );
    assert.ok(
      /80/.test(content),
      'plan-reviewer-prompt.md must reference confidence threshold 80 for suggestions'
    );
  });

  it('must contain output format template with PASS/FAIL judgment', () => {
    const content = readFileSync(PROMPT_PATH, 'utf-8');
    assert.ok(
      content.includes('PASS') && content.includes('FAIL'),
      'plan-reviewer-prompt.md must include PASS/FAIL judgment in output template'
    );
  });

  it('must contain distrust principle (verify with Glob/Grep/Read)', () => {
    const content = readFileSync(PROMPT_PATH, 'utf-8');
    // Must instruct the reviewer to use read-only tools to verify claims
    const hasVerifyTools =
      content.includes('Glob') ||
      content.includes('Grep') ||
      content.includes('Read');
    assert.ok(
      hasVerifyTools,
      'plan-reviewer-prompt.md must instruct reviewer to use Glob/Grep/Read for verification'
    );
    // Must mention distrust / independent verification concept
    const hasDistrustConcept =
      content.includes('不信任') ||
      content.toLowerCase().includes('distrust') ||
      content.toLowerCase().includes('independent') ||
      content.toLowerCase().includes('verify');
    assert.ok(
      hasDistrustConcept,
      'plan-reviewer-prompt.md must contain distrust/independent-verification principle'
    );
  });

  it('must contain prohibition against editing files', () => {
    const content = readFileSync(PROMPT_PATH, 'utf-8');
    const hasNoEditRule =
      content.includes('不能编辑') ||
      content.includes('禁止编辑') ||
      content.includes('不允许编辑') ||
      content.includes('只读') ||
      content.toLowerCase().includes('read-only') ||
      content.toLowerCase().includes('must not edit') ||
      content.toLowerCase().includes('do not edit') ||
      content.toLowerCase().includes('never edit') ||
      content.toLowerCase().includes('cannot edit');
    assert.ok(
      hasNoEditRule,
      'plan-reviewer-prompt.md must prohibit the reviewer from editing files'
    );
  });
});

// ---------------------------------------------------------------------------
// 2. SKILL.md Phase: design step completeness
// ---------------------------------------------------------------------------
describe('SKILL.md Phase: design step completeness', () => {
  it('Phase: design must contain steps 0 through 6', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');

    // Extract the Phase: design section
    const designMatch = content.match(
      /##\s*Phase:\s*design([\s\S]*?)(?=##\s*Phase:|$)/i
    );
    assert.ok(designMatch, 'SKILL.md must have a "Phase: design" section');
    const designSection = designMatch[1];

    // Check for numbered steps - we expect steps 0,1,2,3,5,6 at minimum
    for (const step of [0, 1, 2, 3, 5, 6]) {
      const stepPattern = new RegExp(
        `(?:步骤|step|Step)\\s*${step}[.:\\s：]`,
        'i'
      );
      assert.ok(
        stepPattern.test(designSection),
        `Phase: design must contain step ${step}`
      );
    }
  });

  it('step 3 title must contain "Plan 审查" or "Plan Review"', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const designMatch = content.match(
      /##\s*Phase:\s*design([\s\S]*?)(?=##\s*Phase:|$)/i
    );
    const designSection = designMatch[1];

    // Find the step 3 line
    const step3Pattern =
      /(?:步骤|step|Step)\s*3[.:\s：].*(?:Plan\s*审查|Plan\s*Review)/i;
    assert.ok(
      step3Pattern.test(designSection),
      'Step 3 title must contain "Plan 审查" or "Plan Review"'
    );
  });

  it('step 3 must contain trigger condition', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const designMatch = content.match(
      /##\s*Phase:\s*design([\s\S]*?)(?=##\s*Phase:|$)/i
    );
    const designSection = designMatch[1];

    // Extract step 3 content (from step 3 heading to next step heading)
    const step3Match = designSection.match(
      /(?:步骤|step|Step)\s*3[.:\s：]([\s\S]*?)(?=(?:步骤|step|Step)\s*[456][.:\s：])/i
    );
    assert.ok(step3Match, 'Step 3 section must be extractable');
    const step3Content = step3Match[1];

    const hasTrigger =
      step3Content.includes('触发') ||
      step3Content.toLowerCase().includes('trigger') ||
      step3Content.toLowerCase().includes('condition') ||
      step3Content.includes('条件');
    assert.ok(hasTrigger, 'Step 3 must describe trigger conditions');
  });

  it('step 3 must contain review round limit (max 2)', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const designMatch = content.match(
      /##\s*Phase:\s*design([\s\S]*?)(?=##\s*Phase:|$)/i
    );
    const designSection = designMatch[1];

    const step3Match = designSection.match(
      /(?:步骤|step|Step)\s*3[.:\s：]([\s\S]*?)(?=(?:步骤|step|Step)\s*[456][.:\s：])/i
    );
    const step3Content = step3Match[1];

    const hasRoundLimit =
      step3Content.includes('2 轮') ||
      step3Content.includes('2轮') ||
      step3Content.includes('两轮') ||
      step3Content.toLowerCase().includes('2 round') ||
      step3Content.toLowerCase().includes('max 2') ||
      step3Content.toLowerCase().includes('maximum 2');
    assert.ok(
      hasRoundLimit,
      'Step 3 must specify max 2 review rounds'
    );
  });

  it('step 3 must contain fallback/degradation strategy', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const designMatch = content.match(
      /##\s*Phase:\s*design([\s\S]*?)(?=##\s*Phase:|$)/i
    );
    const designSection = designMatch[1];

    const step3Match = designSection.match(
      /(?:步骤|step|Step)\s*3[.:\s：]([\s\S]*?)(?=(?:步骤|step|Step)\s*[456][.:\s：])/i
    );
    const step3Content = step3Match[1];

    const hasFallback =
      step3Content.includes('降级') ||
      step3Content.includes('兜底') ||
      step3Content.includes('回退') ||
      step3Content.toLowerCase().includes('fallback') ||
      step3Content.toLowerCase().includes('degrad') ||
      step3Content.toLowerCase().includes('fail');
    assert.ok(
      hasFallback,
      'Step 3 must describe a fallback/degradation strategy'
    );
  });

  it('step 5 must be about requesting approval', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const designMatch = content.match(
      /##\s*Phase:\s*design([\s\S]*?)(?=##\s*Phase:|$)/i
    );
    const designSection = designMatch[1];

    const step5Match = designSection.match(
      /(?:步骤|step|Step)\s*5[.:\s：]([\s\S]*?)(?=(?:步骤|step|Step)\s*6[.:\s：])/i
    );
    assert.ok(step5Match, 'Step 5 section must exist');
    const step5Content = step5Match[0];

    const hasApproval =
      step5Content.includes('审批') ||
      step5Content.includes('批准') ||
      step5Content.toLowerCase().includes('approv');
    assert.ok(
      hasApproval,
      'Step 5 must be about requesting approval'
    );
  });

  it('step 6 must be about post-approval actions', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const designMatch = content.match(
      /##\s*Phase:\s*design([\s\S]*?)(?=##\s*Phase:|$)/i
    );
    const designSection = designMatch[1];

    const step6Match = designSection.match(
      /(?:步骤|step|Step)\s*6[.:\s：]([\s\S]*?)(?=(?:步骤|step|Step)\s*7|##\s|$)/i
    );
    assert.ok(step6Match, 'Step 6 section must exist');
    const step6Content = step6Match[0];

    const hasPostApproval =
      step6Content.includes('审批通过') ||
      step6Content.includes('批准后') ||
      step6Content.toLowerCase().includes('approved') ||
      step6Content.toLowerCase().includes('after approval');
    assert.ok(
      hasPostApproval,
      'Step 6 must be about post-approval actions'
    );
  });
});

// ---------------------------------------------------------------------------
// 3. Version consistency (2.14.0)
// ---------------------------------------------------------------------------
describe('version consistency (v2.14.0)', () => {
  it('plugin.json version must be "2.14.0"', () => {
    const content = readFileSync(PLUGIN_JSON_PATH, 'utf-8');
    const json = JSON.parse(content);
    assert.equal(
      json.version,
      '2.14.0',
      `plugin.json version must be "2.14.0", got "${json.version}"`
    );
  });

  it('marketplace.json autopilot version must be "2.14.0"', () => {
    const content = readFileSync(MARKETPLACE_PATH, 'utf-8');
    const json = JSON.parse(content);
    // Find the autopilot entry in the plugins array
    const autopilot = json.plugins?.find(
      (p) => p.name === 'autopilot' || p.id === 'autopilot'
    );
    assert.ok(autopilot, 'marketplace.json must contain an autopilot plugin entry');
    assert.equal(
      autopilot.version,
      '2.14.0',
      `marketplace.json autopilot version must be "2.14.0", got "${autopilot.version}"`
    );
  });
});

// ---------------------------------------------------------------------------
// 4. CLAUDE.md updates
// ---------------------------------------------------------------------------
describe('CLAUDE.md updates for plan-reviewer', () => {
  it('autopilot description must mention plan review capability', () => {
    const content = readFileSync(CLAUDE_MD_PATH, 'utf-8');
    const hasPlanReview =
      content.includes('设计方案审查') ||
      content.includes('Plan Review') ||
      content.includes('plan-reviewer') ||
      content.includes('设计审查');
    assert.ok(
      hasPlanReview,
      'CLAUDE.md must mention plan review / design review capability for autopilot'
    );
  });

  it('changelog must contain v2.14.0 entry', () => {
    const content = readFileSync(CLAUDE_MD_PATH, 'utf-8');
    assert.ok(
      content.includes('v2.14.0') || content.includes('2.14.0'),
      'CLAUDE.md changelog must contain a v2.14.0 entry'
    );
  });
});
