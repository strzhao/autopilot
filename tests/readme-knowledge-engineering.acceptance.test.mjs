/**
 * Acceptance tests for README.md knowledge engineering line addition.
 *
 * Red-team verification: tests are written purely from the design document,
 * without reading the blue-team implementation.
 *
 * Design spec:
 *   In README.md's autopilot core features list, after the line containing
 *   "防合理化表格 + 成功需要证据原则", there must be a new line:
 *   "  - 知识工程：自动积累项目决策和调试教训"
 *
 * Run: node --test tests/readme-knowledge-engineering.acceptance.test.mjs
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const README_PATH = resolve(__dirname, '..', 'README.md');

describe('README.md knowledge engineering entry', () => {
  let lines;

  it('README.md exists and is readable', async () => {
    const content = await readFile(README_PATH, 'utf-8');
    lines = content.split('\n');
    assert.ok(lines.length > 0, 'README.md should not be empty');
  });

  it('contains the knowledge engineering line in the autopilot section', async () => {
    const content = await readFile(README_PATH, 'utf-8');
    lines = content.split('\n');

    const knowledgeLine = lines.find(
      (line) => line.includes('知识工程') && line.includes('自动积累项目决策和调试教训')
    );
    assert.ok(
      knowledgeLine !== undefined,
      'README.md must contain a line with "知识工程：自动积累项目决策和调试教训"'
    );
  });

  it('the knowledge engineering line is a bullet point in the core features list', async () => {
    const content = await readFile(README_PATH, 'utf-8');
    lines = content.split('\n');

    const knowledgeLine = lines.find(
      (line) => line.includes('知识工程') && line.includes('自动积累项目决策和调试教训')
    );
    assert.ok(knowledgeLine, 'Knowledge engineering line must exist');
    assert.match(
      knowledgeLine.trim(),
      /^- /,
      'The line must be a markdown bullet point (starting with "- ")'
    );
  });

  it('the knowledge engineering line appears after the anti-rationalization line', async () => {
    const content = await readFile(README_PATH, 'utf-8');
    lines = content.split('\n');

    const antiRationalIdx = lines.findIndex((line) =>
      line.includes('防合理化表格') && line.includes('成功需要证据原则')
    );
    assert.ok(
      antiRationalIdx !== -1,
      'README.md must contain the anti-rationalization line ("防合理化表格 + 成功需要证据原则")'
    );

    const knowledgeIdx = lines.findIndex(
      (line) => line.includes('知识工程') && line.includes('自动积累项目决策和调试教训')
    );
    assert.ok(
      knowledgeIdx !== -1,
      'README.md must contain the knowledge engineering line'
    );

    assert.ok(
      knowledgeIdx > antiRationalIdx,
      `Knowledge engineering line (line ${knowledgeIdx + 1}) must appear after ` +
        `the anti-rationalization line (line ${antiRationalIdx + 1})`
    );
  });

  it('the knowledge engineering line is within the autopilot core features block', async () => {
    const content = await readFile(README_PATH, 'utf-8');
    lines = content.split('\n');

    const knowledgeIdx = lines.findIndex(
      (line) => line.includes('知识工程') && line.includes('自动积累项目决策和调试教训')
    );
    assert.ok(knowledgeIdx !== -1, 'Knowledge engineering line must exist');

    // Look backwards from the knowledge line to find the "核心特性" header
    let foundCoreFeatures = false;
    for (let i = knowledgeIdx - 1; i >= 0; i--) {
      if (lines[i].includes('核心特性')) {
        foundCoreFeatures = true;
        break;
      }
      // If we hit a section separator (---) or a new plugin heading before
      // finding 核心特性, the line is in the wrong section
      if (lines[i].trim() === '---' || /^#{1,3}\s/.test(lines[i].trim())) {
        break;
      }
    }
    assert.ok(
      foundCoreFeatures,
      'The knowledge engineering line must be inside the "核心特性" block of autopilot'
    );
  });
});
