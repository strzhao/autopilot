/**
 * Acceptance tests for autopilot sub-agent model assignment optimization (v3.5.2).
 *
 * Red-team verification: tests are written purely from the design document,
 * without reading the blue-team implementation.
 *
 * Design spec:
 *   - 5 sub-agent calls in SKILL.md gain `model: "sonnet"` annotation:
 *     plan-reviewer, blue-team, red-team, design-reviewer, code-quality-reviewer
 *   - New "成本优化" (cost optimization) chapter added to SKILL.md
 *   - Version bumped to 3.5.2 across plugin.json, marketplace.json, CLAUDE.md
 *   - CLAUDE.md changelog contains 2026-03-30 entry for v3.5.2
 *
 * Run: node --test tests/model-assignment.acceptance.test.mjs
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');

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
// 1. SKILL.md: 5 sub-agent calls contain model: "sonnet"
// ---------------------------------------------------------------------------
describe('SKILL.md sub-agent model assignment', () => {
  it('must contain exactly 5 Agent calls annotated with model: "sonnet"', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    // Count occurrences of model: "sonnet" (or model: 'sonnet') near Agent tool call context
    const matches = content.match(/model:\s*["']sonnet["']/g) || [];
    assert.equal(
      matches.length,
      5,
      `SKILL.md must have exactly 5 occurrences of model: "sonnet", found ${matches.length}`
    );
  });

  it('plan-reviewer agent call must include model: "sonnet"', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    // Find the section around plan-reviewer and verify model is specified
    const planReviewerIdx = content.indexOf('plan-reviewer');
    assert.ok(planReviewerIdx !== -1, 'SKILL.md must mention plan-reviewer');

    // Look for model: "sonnet" within a reasonable proximity (2000 chars) of plan-reviewer mention
    const surroundingText = content.slice(
      Math.max(0, planReviewerIdx - 200),
      Math.min(content.length, planReviewerIdx + 2000)
    );
    assert.ok(
      /model:\s*["']sonnet["']/.test(surroundingText),
      'plan-reviewer agent call must include model: "sonnet"'
    );
  });

  it('blue-team agent call must include model: "sonnet"', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    // Find blue-team section (蓝队 or blue-team or blue team)
    const idx = content.search(/蓝队|blue[\s-]team/i);
    assert.ok(idx !== -1, 'SKILL.md must mention blue-team (蓝队)');

    // Look for Agent call with model: "sonnet" near blue-team
    const surroundingText = content.slice(
      Math.max(0, idx - 200),
      Math.min(content.length, idx + 2000)
    );
    assert.ok(
      /model:\s*["']sonnet["']/.test(surroundingText),
      'blue-team agent call must include model: "sonnet"'
    );
  });

  it('red-team agent call must include model: "sonnet"', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    // Find red-team section (红队 or red-team or red team)
    const idx = content.search(/红队|red[\s-]team/i);
    assert.ok(idx !== -1, 'SKILL.md must mention red-team (红队)');

    const surroundingText = content.slice(
      Math.max(0, idx - 200),
      Math.min(content.length, idx + 2000)
    );
    assert.ok(
      /model:\s*["']sonnet["']/.test(surroundingText),
      'red-team agent call must include model: "sonnet"'
    );
  });

  it('design-reviewer agent call must include model: "sonnet"', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const idx = content.indexOf('design-reviewer');
    assert.ok(idx !== -1, 'SKILL.md must mention design-reviewer');

    const surroundingText = content.slice(
      Math.max(0, idx - 200),
      Math.min(content.length, idx + 2000)
    );
    assert.ok(
      /model:\s*["']sonnet["']/.test(surroundingText),
      'design-reviewer agent call must include model: "sonnet"'
    );
  });

  it('code-quality-reviewer agent call must include model: "sonnet"', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const idx = content.indexOf('code-quality-reviewer');
    assert.ok(idx !== -1, 'SKILL.md must mention code-quality-reviewer');

    const surroundingText = content.slice(
      Math.max(0, idx - 200),
      Math.min(content.length, idx + 2000)
    );
    assert.ok(
      /model:\s*["']sonnet["']/.test(surroundingText),
      'code-quality-reviewer agent call must include model: "sonnet"'
    );
  });
});

// ---------------------------------------------------------------------------
// 2. SKILL.md: 成本优化 chapter exists and contains required content
// ---------------------------------------------------------------------------
describe('SKILL.md 成本优化 chapter', () => {
  it('must contain a "成本优化" section heading', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    assert.ok(
      content.includes('成本优化'),
      'SKILL.md must contain a "成本优化" (cost optimization) chapter'
    );
  });

  it('成本优化 section must contain a model tier table', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    // Extract the 成本优化 section
    const sectionMatch = content.match(
      /##[#\s]*成本优化([\s\S]*?)(?=\n##\s|$)/
    );
    assert.ok(
      sectionMatch,
      'SKILL.md must have a "成本优化" section extractable by regex'
    );
    const section = sectionMatch[1];

    // Should contain a Markdown table (| col | col |)
    assert.ok(
      /\|.+\|/.test(section),
      '成本优化 section must contain a model tier table (Markdown table format)'
    );
  });

  it('成本优化 section must mention sonnet as the model for sub-agents', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const sectionMatch = content.match(
      /##[#\s]*成本优化([\s\S]*?)(?=\n##\s|$)/
    );
    const section = sectionMatch[1];
    assert.ok(
      section.includes('sonnet'),
      '成本优化 section must mention "sonnet" as the model for sub-agents'
    );
  });

  it('成本优化 section must describe user override capability', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    const sectionMatch = content.match(
      /##[#\s]*成本优化([\s\S]*?)(?=\n##\s|$)/
    );
    const section = sectionMatch[1];

    // Must mention that users can override the model setting
    const hasOverride =
      section.includes('覆盖') ||
      section.includes('override') ||
      section.includes('自定义') ||
      section.includes('修改') ||
      section.includes('指定');
    assert.ok(
      hasOverride,
      '成本优化 section must describe user override capability for model selection'
    );
  });

  it('成本优化 section must be positioned between core ironclad rules and startup flow', () => {
    const content = readFileSync(SKILL_PATH, 'utf-8');
    // Find the positions of: 核心铁律, 成本优化, 启动流程
    const ironcladsIdx = content.search(/##[#\s]*核心铁律/);
    const costOptIdx = content.search(/##[#\s]*成本优化/);
    const startupIdx = content.search(/##[#\s]*启动流程/);

    assert.ok(ironcladsIdx !== -1, 'SKILL.md must contain 核心铁律 section');
    assert.ok(costOptIdx !== -1, 'SKILL.md must contain 成本优化 section');
    assert.ok(startupIdx !== -1, 'SKILL.md must contain 启动流程 section');

    assert.ok(
      ironcladsIdx < costOptIdx,
      '成本优化 must appear AFTER 核心铁律 in SKILL.md'
    );
    assert.ok(
      costOptIdx < startupIdx,
      '成本优化 must appear BEFORE 启动流程 in SKILL.md'
    );
  });
});

// ---------------------------------------------------------------------------
// 3. Version consistency (3.5.2)
// ---------------------------------------------------------------------------
describe('version consistency (v3.5.2)', () => {
  it('plugin.json version must be "3.5.2"', () => {
    const content = readFileSync(PLUGIN_JSON_PATH, 'utf-8');
    const json = JSON.parse(content);
    assert.equal(
      json.version,
      '3.5.2',
      `plugin.json version must be "3.5.2", got "${json.version}"`
    );
  });

  it('marketplace.json autopilot version must be "3.5.2"', () => {
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
      '3.5.2',
      `marketplace.json autopilot version must be "3.5.2", got "${autopilot.version}"`
    );
  });

  it('CLAUDE.md must show autopilot as v3.5.2 in plugin list', () => {
    const content = readFileSync(CLAUDE_MD_PATH, 'utf-8');
    assert.ok(
      content.includes('v3.5.2') || content.includes('(3.5.2)'),
      'CLAUDE.md plugin list must reference autopilot version 3.5.2'
    );
  });
});

// ---------------------------------------------------------------------------
// 4. CLAUDE.md changelog for v3.5.2
// ---------------------------------------------------------------------------
describe('CLAUDE.md changelog for v3.5.2', () => {
  it('must contain a 2026-03-30 changelog entry', () => {
    const content = readFileSync(CLAUDE_MD_PATH, 'utf-8');
    assert.ok(
      content.includes('2026-03-30'),
      'CLAUDE.md changelog must contain a 2026-03-30 date entry'
    );
  });

  it('must mention v3.5.2 in the changelog', () => {
    const content = readFileSync(CLAUDE_MD_PATH, 'utf-8');
    assert.ok(
      content.includes('3.5.2'),
      'CLAUDE.md changelog must mention version 3.5.2'
    );
  });

  it('2026-03-30 changelog entry must reference model assignment or cost optimization', () => {
    const content = readFileSync(CLAUDE_MD_PATH, 'utf-8');
    // Find the 2026-03-30 section
    const dateIdx = content.indexOf('2026-03-30');
    assert.ok(dateIdx !== -1, 'CLAUDE.md must contain 2026-03-30 entry');

    // Extract text around that date (up to next date section)
    const entryText = content.slice(dateIdx, dateIdx + 800);
    const hasCostOrModel =
      entryText.includes('成本') ||
      entryText.includes('模型') ||
      entryText.includes('model') ||
      entryText.includes('sonnet') ||
      entryText.includes('cost') ||
      entryText.includes('Agent');
    assert.ok(
      hasCostOrModel,
      '2026-03-30 changelog entry must mention model assignment or cost optimization'
    );
  });
});
