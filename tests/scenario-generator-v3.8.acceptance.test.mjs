/**
 * Acceptance tests for v3.8.0: 验收场景生成器 + plan-reviewer 交叉校验.
 *
 * Red-team verification: tests are written purely from the design document,
 * without reading the blue-team implementation.
 *
 * Design spec:
 *   1. New file: references/scenario-generator-prompt.md
 *      - Receives ONLY: target description + tech stack (info-isolated)
 *      - Outputs: e2e text scenario list
 *   2. SKILL.md Phase: design step 2 updated:
 *      - Parallel launch of scenario-generator sub-agent alongside Explore agents
 *      - Info isolation: only target description + tech stack, NOT design doc or code
 *   3. SKILL.md Phase: design step 3 updated:
 *      - plan-reviewer receives acceptance scenarios as additional input
 *   4. plan-reviewer-prompt.md updated:
 *      - New input section: 验收场景
 *      - Dim 1 (需求完整性) enhanced: forward coverage check (scenario→task)
 *      - Dim 4 (验证方案覆盖) enhanced: reverse coverage check (task→scenario)
 *      - New output section: 场景覆盖分析
 *   5. Fallback: scenario-generator failure → plan-reviewer uses original flow
 *   6. Three-layer info isolation chain (L1→L2→L3)
 *   7. Version bump to 3.8.0
 *
 * Run: node --test tests/scenario-generator-v3.8.acceptance.test.mjs
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');

const SCENARIO_GENERATOR_PATH = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot/references/scenario-generator-prompt.md'
);
const PLAN_REVIEWER_PATH = resolve(
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
// 1. scenario-generator-prompt.md file existence and structure
// ---------------------------------------------------------------------------
describe('scenario-generator-prompt.md existence and structure', () => {
  it('file must exist at references/scenario-generator-prompt.md', () => {
    assert.ok(
      existsSync(SCENARIO_GENERATOR_PATH),
      `scenario-generator-prompt.md must exist at ${SCENARIO_GENERATOR_PATH}`
    );
  });

  it('must define role as acceptance scenario generator (验收场景生成器 or equivalent)', () => {
    const content = readFileSync(SCENARIO_GENERATOR_PATH, 'utf-8');
    const hasRole =
      content.includes('验收场景') ||
      content.includes('acceptance scenario') ||
      content.includes('场景生成');
    assert.ok(
      hasRole,
      'scenario-generator-prompt.md must define role as acceptance scenario generator'
    );
  });

  it('must accept ONLY target description and tech stack as input (not design doc or code)', () => {
    const content = readFileSync(SCENARIO_GENERATOR_PATH, 'utf-8');
    // Must mention receiving target description
    const hasTarget =
      content.includes('目标描述') ||
      content.includes('目标') ||
      content.toLowerCase().includes('target');
    assert.ok(
      hasTarget,
      'scenario-generator-prompt.md must mention accepting target description as input'
    );
    // Must mention tech stack
    const hasTechStack =
      content.includes('技术栈') ||
      content.toLowerCase().includes('tech stack') ||
      content.toLowerCase().includes('technology');
    assert.ok(
      hasTechStack,
      'scenario-generator-prompt.md must mention accepting tech stack as input'
    );
  });

  it('must explicitly prohibit reading design document or implementation code', () => {
    const content = readFileSync(SCENARIO_GENERATOR_PATH, 'utf-8');
    // Info isolation: must not accept design doc or code
    const hasIsolation =
      content.includes('信息隔离') ||
      content.includes('不能读') ||
      content.includes('禁止读') ||
      content.includes('不接收设计') ||
      content.includes('不接收代码') ||
      content.toLowerCase().includes('isolated') ||
      content.toLowerCase().includes('do not read') ||
      content.toLowerCase().includes('only target') ||
      content.toLowerCase().includes('no design') ||
      content.toLowerCase().includes('no code');
    assert.ok(
      hasIsolation,
      'scenario-generator-prompt.md must explicitly enforce info isolation (no design doc or code access)'
    );
  });

  it('must output e2e text scenario list', () => {
    const content = readFileSync(SCENARIO_GENERATOR_PATH, 'utf-8');
    const hasE2EOutput =
      content.includes('e2e') ||
      content.includes('E2E') ||
      content.includes('端到端') ||
      content.includes('文本用例') ||
      content.includes('场景列表') ||
      content.includes('验收场景列表');
    assert.ok(
      hasE2EOutput,
      'scenario-generator-prompt.md must describe e2e text scenario list as output'
    );
  });

  it('must include an output template or format for scenarios', () => {
    const content = readFileSync(SCENARIO_GENERATOR_PATH, 'utf-8');
    // Should have some structured output (numbered list, template, or format)
    const hasFormat =
      content.includes('##') ||
      /^\d+\./m.test(content) ||
      content.includes('**场景') ||
      content.includes('场景 ') ||
      content.toLowerCase().includes('scenario') ||
      content.includes('输出格式') ||
      content.includes('output');
    assert.ok(
      hasFormat,
      'scenario-generator-prompt.md must include an output template or format for scenarios'
    );
  });
});

// ---------------------------------------------------------------------------
// 2. SKILL.md Phase: design step 2 - parallel scenario generator launch
// ---------------------------------------------------------------------------
describe('SKILL.md Phase: design step 2 parallel scenario generator', () => {
  it('Phase: design must mention scenario generator (验收场景生成器 or scenario-generator)', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const designMatch = content.match(
      /##\s*Phase:\s*design([\s\S]*?)(?=##\s*Phase:|$)/i
    );
    assert.ok(designMatch, 'SKILL.md must have a "Phase: design" section');
    const designSection = designMatch[1];

    const hasScenarioGen =
      designSection.includes('验收场景生成器') ||
      designSection.includes('scenario-generator') ||
      designSection.includes('场景生成');
    assert.ok(
      hasScenarioGen,
      'SKILL.md Phase: design must mention acceptance scenario generator'
    );
  });

  it('step 2 must describe parallel launch of scenario generator alongside Explore agents', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const designMatch = content.match(
      /##\s*Phase:\s*design([\s\S]*?)(?=##\s*Phase:|$)/i
    );
    const designSection = designMatch[1];

    // Extract step 2 content
    const step2Match = designSection.match(
      /(?:步骤|step|Step)\s*2[.:\s：]([\s\S]*?)(?=(?:步骤|step|Step)\s*3[.:\s：])/i
    );
    assert.ok(step2Match, 'Step 2 section must be extractable');
    const step2Content = step2Match[1];

    // Must mention parallel execution
    const hasParallel =
      step2Content.includes('并行') ||
      step2Content.toLowerCase().includes('parallel') ||
      step2Content.includes('同时');
    assert.ok(
      hasParallel,
      'Step 2 must describe parallel launch of scenario generator'
    );
  });

  it('step 2 scenario generator must receive ONLY target description and tech stack (info isolation)', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const designMatch = content.match(
      /##\s*Phase:\s*design([\s\S]*?)(?=##\s*Phase:|$)/i
    );
    const designSection = designMatch[1];

    const step2Match = designSection.match(
      /(?:步骤|step|Step)\s*2[.:\s：]([\s\S]*?)(?=(?:步骤|step|Step)\s*3[.:\s：])/i
    );
    const step2Content = step2Match[1];

    // Info isolation: must restrict inputs to only target + tech stack
    const hasIsolation =
      step2Content.includes('信息隔离') ||
      step2Content.includes('目标描述') ||
      step2Content.includes('仅') ||
      step2Content.toLowerCase().includes('only') ||
      step2Content.toLowerCase().includes('isolated') ||
      step2Content.includes('不含设计') ||
      step2Content.includes('不含代码');
    assert.ok(
      hasIsolation,
      'Step 2 must enforce info isolation for scenario generator (only target description + tech stack)'
    );
  });

  it('step 2 must reference scenario-generator-prompt.md', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const designMatch = content.match(
      /##\s*Phase:\s*design([\s\S]*?)(?=##\s*Phase:|$)/i
    );
    const designSection = designMatch[1];

    const step2Match = designSection.match(
      /(?:步骤|step|Step)\s*2[.:\s：]([\s\S]*?)(?=(?:步骤|step|Step)\s*3[.:\s：])/i
    );
    const step2Content = step2Match[1];

    assert.ok(
      step2Content.includes('scenario-generator-prompt.md'),
      'Step 2 must reference scenario-generator-prompt.md'
    );
  });

  it('step 2 must describe a fallback when scenario generator fails', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const designMatch = content.match(
      /##\s*Phase:\s*design([\s\S]*?)(?=##\s*Phase:|$)/i
    );
    const designSection = designMatch[1];

    const step2Match = designSection.match(
      /(?:步骤|step|Step)\s*2[.:\s：]([\s\S]*?)(?=(?:步骤|step|Step)\s*3[.:\s：])/i
    );
    const step2Content = step2Match[1];

    const hasFallback =
      step2Content.includes('失败') ||
      step2Content.includes('降级') ||
      step2Content.includes('兜底') ||
      step2Content.toLowerCase().includes('fallback') ||
      step2Content.toLowerCase().includes('fail') ||
      step2Content.toLowerCase().includes('degrad');
    assert.ok(
      hasFallback,
      'Step 2 must describe fallback behavior when scenario generator fails'
    );
  });
});

// ---------------------------------------------------------------------------
// 3. SKILL.md Phase: design step 3 - plan-reviewer receives acceptance scenarios
// ---------------------------------------------------------------------------
describe('SKILL.md Phase: design step 3 plan-reviewer with acceptance scenarios', () => {
  it('step 3 must mention passing acceptance scenarios to plan-reviewer', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const designMatch = content.match(
      /##\s*Phase:\s*design([\s\S]*?)(?=##\s*Phase:|$)/i
    );
    const designSection = designMatch[1];

    const step3Match = designSection.match(
      /(?:步骤|step|Step)\s*3[.:\s：]([\s\S]*?)(?=(?:步骤|step|Step)\s*[456][.:\s：])/i
    );
    assert.ok(step3Match, 'Step 3 section must be extractable');
    const step3Content = step3Match[1];

    const hasScenarioPassing =
      step3Content.includes('验收场景') ||
      step3Content.includes('场景列表') ||
      step3Content.includes('scenario') ||
      step3Content.includes('L1') ||
      step3Content.includes('场景生成器');
    assert.ok(
      hasScenarioPassing,
      'Step 3 must mention passing acceptance scenarios from scenario generator to plan-reviewer'
    );
  });

  it('step 3 must describe conditional scenario passing (only when scenario generator succeeded)', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const designMatch = content.match(
      /##\s*Phase:\s*design([\s\S]*?)(?=##\s*Phase:|$)/i
    );
    const designSection = designMatch[1];

    const step3Match = designSection.match(
      /(?:步骤|step|Step)\s*3[.:\s：]([\s\S]*?)(?=(?:步骤|step|Step)\s*[456][.:\s：])/i
    );
    const step3Content = step3Match[1];

    // Must have conditional logic (if scenario-gen succeeded, pass scenarios)
    const hasCondition =
      step3Content.includes('如果') ||
      step3Content.includes('当') ||
      step3Content.includes('成功') ||
      step3Content.toLowerCase().includes('if') ||
      step3Content.toLowerCase().includes('when') ||
      step3Content.includes('有则') ||
      step3Content.includes('存在');
    assert.ok(
      hasCondition,
      'Step 3 must describe conditional scenario passing based on scenario generator result'
    );
  });
});

// ---------------------------------------------------------------------------
// 4. plan-reviewer-prompt.md enhancements for v3.8.0
// ---------------------------------------------------------------------------
describe('plan-reviewer-prompt.md v3.8.0 enhancements', () => {
  it('must have a new input section for acceptance scenarios (验收场景)', () => {
    const content = readFileSync(PLAN_REVIEWER_PATH, 'utf-8');
    const hasScenarioInput =
      content.includes('验收场景') ||
      content.includes('acceptance scenario') ||
      content.includes('场景列表') ||
      content.includes('L1 场景');
    assert.ok(
      hasScenarioInput,
      'plan-reviewer-prompt.md must have an input section for acceptance scenarios (验收场景)'
    );
  });

  it('Dim 1 (需求完整性) must include forward coverage check: scenario → task', () => {
    const content = readFileSync(PLAN_REVIEWER_PATH, 'utf-8');
    // Find the 需求完整性 section
    const dim1Idx = content.indexOf('需求完整性');
    assert.ok(dim1Idx !== -1, 'plan-reviewer-prompt.md must contain 需求完整性');

    const surrounding = content.slice(
      dim1Idx,
      Math.min(content.length, dim1Idx + 500)
    );

    // Must describe forward coverage: each scenario covered by a task
    const hasForwardCoverage =
      surrounding.includes('场景') ||
      surrounding.includes('正向') ||
      surrounding.includes('scenario') ||
      surrounding.includes('覆盖') ||
      surrounding.includes('→ 任务') ||
      surrounding.includes('对应任务');
    assert.ok(
      hasForwardCoverage,
      'Dim 1 (需求完整性) must include forward coverage check (scenario → task mapping)'
    );
  });

  it('Dim 4 (验证方案覆盖) must include reverse coverage check: task → scenario', () => {
    const content = readFileSync(PLAN_REVIEWER_PATH, 'utf-8');
    // Find the 验证方案覆盖 or 验证 section (Dim 4)
    const dim4Idx = content.search(/验证方案覆盖|验证方案|验证覆盖/);
    assert.ok(dim4Idx !== -1, 'plan-reviewer-prompt.md must contain Dim 4 (verification coverage)');

    const surrounding = content.slice(
      dim4Idx,
      Math.min(content.length, dim4Idx + 600)
    );

    // Must describe reverse coverage: each task has corresponding scenario
    const hasReverseCoverage =
      surrounding.includes('场景') ||
      surrounding.includes('反向') ||
      surrounding.includes('scenario') ||
      surrounding.includes('对应') ||
      surrounding.includes('任务 →') ||
      surrounding.includes('任务→') ||
      surrounding.includes('验证');
    assert.ok(
      hasReverseCoverage,
      'Dim 4 (验证方案覆盖) must include reverse coverage check (task → scenario mapping)'
    );
  });

  it('must have a new output section for scenario coverage analysis (场景覆盖分析)', () => {
    const content = readFileSync(PLAN_REVIEWER_PATH, 'utf-8');
    const hasCoverageOutput =
      content.includes('场景覆盖') ||
      content.includes('scenario coverage') ||
      content.includes('覆盖分析') ||
      content.includes('场景分析');
    assert.ok(
      hasCoverageOutput,
      'plan-reviewer-prompt.md must have an output section for scenario coverage analysis (场景覆盖分析)'
    );
  });

  it('must still contain all 6 original review dimensions', () => {
    const content = readFileSync(PLAN_REVIEWER_PATH, 'utf-8');
    const dimensions = [
      '需求完整性',
      '技术可行性',
      '任务分解',
      '验证',
      '风险',
      '范围控制',
    ];
    for (const dim of dimensions) {
      assert.ok(
        content.includes(dim),
        `plan-reviewer-prompt.md must still contain dimension "${dim}" after v3.8.0 enhancement`
      );
    }
  });

  it('must still contain BLOCKER/PASS/FAIL judgment structure', () => {
    const content = readFileSync(PLAN_REVIEWER_PATH, 'utf-8');
    assert.ok(
      content.includes('BLOCKER'),
      'plan-reviewer-prompt.md must retain BLOCKER severity after v3.8.0'
    );
    assert.ok(
      content.includes('PASS') || content.includes('FAIL'),
      'plan-reviewer-prompt.md must retain PASS/FAIL judgment after v3.8.0'
    );
  });

  it('must describe conditional behavior when no acceptance scenarios are provided', () => {
    const content = readFileSync(PLAN_REVIEWER_PATH, 'utf-8');
    // When scenario-generator failed/not available, plan-reviewer should still work
    const hasConditionalBehavior =
      content.includes('如果') ||
      content.includes('没有') ||
      content.includes('为空') ||
      content.includes('无场景') ||
      content.includes('不可用') ||
      content.toLowerCase().includes('if no') ||
      content.toLowerCase().includes('when no') ||
      content.toLowerCase().includes('optional') ||
      content.includes('可选') ||
      content.includes('fallback') ||
      content.includes('降级');
    assert.ok(
      hasConditionalBehavior,
      'plan-reviewer-prompt.md must describe conditional behavior when no acceptance scenarios are provided (fallback)'
    );
  });
});

// ---------------------------------------------------------------------------
// 5. Three-layer info isolation chain verification in design phase
// ---------------------------------------------------------------------------
describe('Three-layer info isolation chain (L1→L2→L3)', () => {
  it('SKILL.md must describe or reference 3-layer info isolation', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    // Look for L1/L2/L3 labels or a description of three-layer isolation
    const hasThreeLayers =
      content.includes('L1') ||
      content.includes('L2') ||
      content.includes('L3') ||
      content.includes('三层') ||
      content.includes('3 层') ||
      content.includes('信息隔离验证链');
    assert.ok(
      hasThreeLayers,
      'SKILL.md must describe or reference the 3-layer info isolation chain (L1/L2/L3)'
    );
  });

  it('scenario-generator-prompt.md represents L1 isolation (only target + tech stack)', () => {
    const content = readFileSync(SCENARIO_GENERATOR_PATH, 'utf-8');
    // L1: most isolated — no design doc, no existing code
    const hasL1Isolation =
      content.includes('目标描述') ||
      content.includes('技术栈') ||
      content.includes('L1') ||
      (content.includes('目标') && content.includes('技术'));
    assert.ok(
      hasL1Isolation,
      'scenario-generator-prompt.md (L1) must only accept target description and tech stack'
    );
  });

  it('plan-reviewer-prompt.md represents L2 (receives design doc + L1 scenarios)', () => {
    const content = readFileSync(PLAN_REVIEWER_PATH, 'utf-8');
    // L2: receives design doc AND the L1-generated scenarios
    const hasDesignDoc =
      content.includes('设计文档') ||
      content.includes('design');
    const hasScenarios =
      content.includes('验收场景') ||
      content.includes('场景');
    assert.ok(
      hasDesignDoc,
      'plan-reviewer-prompt.md (L2) must accept design document'
    );
    assert.ok(
      hasScenarios,
      'plan-reviewer-prompt.md (L2) must accept L1 acceptance scenarios'
    );
  });
});

// ---------------------------------------------------------------------------
// 6. Version consistency (3.8.0)
// ---------------------------------------------------------------------------
describe('version consistency (v3.8.0)', () => {
  it('plugin.json version must be "3.8.0"', () => {
    const content = readFileSync(PLUGIN_JSON_PATH, 'utf-8');
    const json = JSON.parse(content);
    assert.equal(
      json.version,
      '3.8.0',
      `plugin.json version must be "3.8.0", got "${json.version}"`
    );
  });

  it('marketplace.json autopilot version must be "3.8.0"', () => {
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
      '3.8.0',
      `marketplace.json autopilot version must be "3.8.0", got "${autopilot.version}"`
    );
  });

  it('CLAUDE.md must show autopilot as v3.8.0 in plugin list', () => {
    const content = readFileSync(CLAUDE_MD_PATH, 'utf-8');
    assert.ok(
      content.includes('v3.8.0') || content.includes('(3.8.0)'),
      'CLAUDE.md plugin list must reference autopilot version 3.8.0'
    );
  });
});

// ---------------------------------------------------------------------------
// 7. CLAUDE.md changelog for v3.8.0
// ---------------------------------------------------------------------------
describe('CLAUDE.md changelog for v3.8.0', () => {
  it('must contain a changelog entry mentioning v3.8.0', () => {
    const content = readFileSync(CLAUDE_MD_PATH, 'utf-8');
    assert.ok(
      content.includes('3.8.0'),
      'CLAUDE.md changelog must mention version 3.8.0'
    );
  });

  it('v3.8.0 changelog entry must reference scenario generator or acceptance scenarios', () => {
    const content = readFileSync(CLAUDE_MD_PATH, 'utf-8');
    const v380Idx = content.indexOf('3.8.0');
    assert.ok(v380Idx !== -1, 'CLAUDE.md must contain 3.8.0 entry');

    const entryText = content.slice(v380Idx, v380Idx + 600);
    const hasScenarioRef =
      entryText.includes('验收场景') ||
      entryText.includes('场景生成') ||
      entryText.includes('scenario') ||
      entryText.includes('交叉校验') ||
      entryText.includes('plan-reviewer');
    assert.ok(
      hasScenarioRef,
      'v3.8.0 changelog entry must reference scenario generator or acceptance scenario cross-validation'
    );
  });

  it('autopilot description in CLAUDE.md must mention acceptance scenario generation or cross-validation', () => {
    const content = readFileSync(CLAUDE_MD_PATH, 'utf-8');
    // The capability description should be updated
    const hasCapability =
      content.includes('验收场景生成器') ||
      content.includes('场景生成') ||
      content.includes('交叉校验') ||
      content.includes('e2e 文本用例') ||
      content.includes('scenario-generator');
    assert.ok(
      hasCapability,
      'CLAUDE.md autopilot description must mention the new acceptance scenario generation capability'
    );
  });
});

// ---------------------------------------------------------------------------
// 8. Backward compatibility: prior invariants must not be broken
// ---------------------------------------------------------------------------
describe('backward compatibility: prior invariants from v3.7.x preserved', () => {
  it('SKILL.md must still have exactly 5 model: "sonnet" occurrences (may gain +1 for scenario-generator)', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const matches = content.match(/model:\s*["']sonnet["']/g) || [];
    // v3.8.0 adds a 6th sub-agent (scenario-generator), so count is 5 or 6
    assert.ok(
      matches.length >= 5,
      `SKILL.md must have at least 5 occurrences of model: "sonnet", found ${matches.length}`
    );
    assert.ok(
      matches.length <= 7,
      `SKILL.md must not exceed 7 occurrences of model: "sonnet" (unexpected additions), found ${matches.length}`
    );
  });

  it('SKILL.md must still contain Phase: design, implement, qa, auto-fix, merge sections', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const phases = ['design', 'implement', 'qa', 'auto-fix', 'merge'];
    for (const phase of phases) {
      const pattern = new RegExp(`Phase:\\s*${phase}`, 'i');
      assert.ok(
        pattern.test(content),
        `SKILL.md must still contain Phase: ${phase} section`
      );
    }
  });

  it('SKILL.md must still contain 核心铁律 section', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    assert.ok(
      /##[#\s]*核心铁律/.test(content),
      'SKILL.md must retain 核心铁律 section after v3.8.0'
    );
  });

  it('SKILL.md must still contain 防合理化 anti-rationalization content', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    assert.ok(
      content.includes('防合理化'),
      'SKILL.md must retain 防合理化 (anti-rationalization) content'
    );
  });

  it('plan-reviewer step 3 must still have max 2 review rounds limit', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const designMatch = content.match(
      /##\s*Phase:\s*design([\s\S]*?)(?=##\s*Phase:|$)/i
    );
    const designSection = designMatch[1];

    const step3Match = designSection.match(
      /(?:步骤|step|Step)\s*3[.:\s：]([\s\S]*?)(?=(?:步骤|step|Step)\s*[456][.:\s：])/i
    );
    assert.ok(step3Match, 'Step 3 must still exist after v3.8.0');
    const step3Content = step3Match[1];

    const hasRoundLimit =
      step3Content.includes('2 轮') ||
      step3Content.includes('2轮') ||
      step3Content.includes('两轮') ||
      step3Content.toLowerCase().includes('max 2') ||
      step3Content.toLowerCase().includes('maximum 2');
    assert.ok(
      hasRoundLimit,
      'Step 3 must still specify max 2 review rounds (backward compatibility)'
    );
  });

  it('plan-reviewer-prompt.md must still have confidence threshold BLOCKER at 91+', () => {
    const content = readFileSync(PLAN_REVIEWER_PATH, 'utf-8');
    assert.ok(
      /9[1-9]/.test(content) || content.includes('91'),
      'plan-reviewer-prompt.md must retain BLOCKER confidence threshold at 91+ after v3.8.0'
    );
  });

  it('plan-reviewer-prompt.md must still prohibit editing files (read-only)', () => {
    const content = readFileSync(PLAN_REVIEWER_PATH, 'utf-8');
    const hasReadOnly =
      content.includes('不能编辑') ||
      content.includes('禁止编辑') ||
      content.includes('只读') ||
      content.toLowerCase().includes('read-only') ||
      content.toLowerCase().includes('must not edit') ||
      content.toLowerCase().includes('cannot edit') ||
      content.includes('禁止');
    assert.ok(
      hasReadOnly,
      'plan-reviewer-prompt.md must retain read-only prohibition after v3.8.0'
    );
  });
});
