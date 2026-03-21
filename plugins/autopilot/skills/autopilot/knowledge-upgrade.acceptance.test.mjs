/**
 * Acceptance tests for the knowledge engineering upgrade:
 * "两文件平面存储" → "索引驱动 + 领域分区 + 智能检索" 分层知识系统
 *
 * Red-team verification: tests are written purely from the design document,
 * without reading the blue-team implementation changes.
 *
 * Run: node --test plugins/autopilot/skills/autopilot/knowledge-upgrade.acceptance.test.mjs
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const KNOWLEDGE_REF = resolve(__dirname, 'references/knowledge-engineering.md');
const SKILL_MD = resolve(__dirname, 'SKILL.md');

// Helper: read file content
async function readContent(path) {
  return readFile(path, 'utf-8');
}

// ===========================================================================
// 1. knowledge-engineering.md — 目录结构升级
// ===========================================================================
describe('knowledge-engineering.md: 三层目录结构', () => {
  let content;

  it('should load knowledge-engineering.md', async () => {
    content = await readContent(KNOWLEDGE_REF);
    assert.ok(content.length > 0, 'File should not be empty');
  });

  it('should document index.md in the directory structure', async () => {
    content ??= await readContent(KNOWLEDGE_REF);
    assert.ok(
      content.includes('index.md'),
      'Directory structure must include index.md as the index layer'
    );
  });

  it('should document domains/ directory in the structure', async () => {
    content ??= await readContent(KNOWLEDGE_REF);
    assert.ok(
      content.includes('domains/'),
      'Directory structure must include domains/ for domain partitioning'
    );
  });

  it('should retain decisions.md in the structure (backward compat)', async () => {
    content ??= await readContent(KNOWLEDGE_REF);
    assert.ok(
      content.includes('decisions.md'),
      'Directory structure must still include decisions.md for backward compatibility'
    );
  });

  it('should retain patterns.md in the structure (backward compat)', async () => {
    content ??= await readContent(KNOWLEDGE_REF);
    assert.ok(
      content.includes('patterns.md'),
      'Directory structure must still include patterns.md for backward compatibility'
    );
  });
});

// ===========================================================================
// 2. knowledge-engineering.md — Index 索引文件格式
// ===========================================================================
describe('knowledge-engineering.md: Index file specification', () => {
  let content;

  it('should describe the index.md format with entry metadata', async () => {
    content = await readContent(KNOWLEDGE_REF);
    // Index entries need: date, title, tags, location pointer
    assert.ok(
      content.includes('tags') && content.includes('index.md'),
      'Index format must describe tags and index.md'
    );
  });

  it('should show index entries pointing to target files with →', async () => {
    content ??= await readContent(KNOWLEDGE_REF);
    // Design specifies: → decisions.md, → patterns.md, → domains/xxx.md
    assert.ok(
      /→\s*\S+\.md/.test(content),
      'Index entries must use → pointer notation to reference target files'
    );
  });

  it('should describe Domain Knowledge section in index', async () => {
    content ??= await readContent(KNOWLEDGE_REF);
    assert.ok(
      /[Dd]omain/i.test(content) && content.includes('domains/'),
      'Index must document Domain Knowledge entries pointing to domains/ files'
    );
  });
});

// ===========================================================================
// 3. knowledge-engineering.md — 条目格式增强 (tags)
// ===========================================================================
describe('knowledge-engineering.md: Entry tag format', () => {
  let content;

  it('should specify HTML comment tag format for entries', async () => {
    content = await readContent(KNOWLEDGE_REF);
    // Design: <!-- tags: tag1, tag2 -->
    assert.ok(
      content.includes('<!-- tags:') || content.includes('<!-- tags :'),
      'Must specify <!-- tags: tag1, tag2 --> HTML comment format for entry tagging'
    );
  });
});

// ===========================================================================
// 4. knowledge-engineering.md — 两阶段消费 (Design Phase)
// ===========================================================================
describe('knowledge-engineering.md: Two-phase consumption', () => {
  let content;

  it('should describe Phase 1 reading index.md with keyword matching', async () => {
    content = await readContent(KNOWLEDGE_REF);
    // Phase 1: read index.md → keyword match tags
    assert.ok(
      /[Pp]hase\s*1/i.test(content) && content.includes('index.md'),
      'Must describe Phase 1: read index.md with keyword matching'
    );
  });

  it('should specify Phase 1 time budget (≤5s)', async () => {
    content ??= await readContent(KNOWLEDGE_REF);
    assert.ok(
      content.includes('5') && /秒|s\b/i.test(content),
      'Phase 1 must specify a ≤5s time budget'
    );
  });

  it('should describe Phase 2 loading matched files on demand', async () => {
    content ??= await readContent(KNOWLEDGE_REF);
    assert.ok(
      /[Pp]hase\s*2/i.test(content),
      'Must describe Phase 2: on-demand file loading'
    );
  });

  it('should limit Phase 2 to at most 3 files', async () => {
    content ??= await readContent(KNOWLEDGE_REF);
    assert.ok(
      content.includes('3'),
      'Phase 2 must specify a maximum of 3 files to load'
    );
  });

  it('should specify Phase 2 time budget (≤10s)', async () => {
    content ??= await readContent(KNOWLEDGE_REF);
    assert.ok(
      content.includes('10') && /秒|s\b/i.test(content),
      'Phase 2 must specify a ≤10s time budget'
    );
  });

  it('should describe fallback when index.md does not exist', async () => {
    content ??= await readContent(KNOWLEDGE_REF);
    // Fallback: no index.md → full load (original behavior)
    assert.ok(
      /[Ff]allback/i.test(content) || /回退|降级|兼容/.test(content),
      'Must describe fallback behavior when index.md is absent'
    );
  });
});

// ===========================================================================
// 5. knowledge-engineering.md — 提取增强 (Merge Phase)
// ===========================================================================
describe('knowledge-engineering.md: Extraction enhancements', () => {
  let content;

  it('should describe auto-generating tags during extraction', async () => {
    content = await readContent(KNOWLEDGE_REF);
    assert.ok(
      /tag/i.test(content) && (/自动|auto|生成|generat/i.test(content) || content.includes('tags')),
      'Must describe auto-generating tags when extracting knowledge'
    );
  });

  it('should describe syncing index.md during extraction', async () => {
    content ??= await readContent(KNOWLEDGE_REF);
    // When extracting, must also update index.md
    assert.ok(
      content.includes('index.md') && (/同步|sync|更新|update|追加|append/i.test(content)),
      'Must describe syncing/updating index.md when new entries are extracted'
    );
  });

  it('should support domain partitioning in domains/', async () => {
    content ??= await readContent(KNOWLEDGE_REF);
    assert.ok(
      content.includes('domains/') && /领域|domain|分区|partition/i.test(content),
      'Must describe domain partitioning support under domains/'
    );
  });

  it('should recommend migration when global files exceed threshold', async () => {
    content ??= await readContent(KNOWLEDGE_REF);
    // >100 lines triggers migration suggestion
    assert.ok(
      content.includes('100') && /迁移|migrat|建议|suggest|拆分/i.test(content),
      'Must describe migration recommendation when global files exceed 100 lines'
    );
  });
});

// ===========================================================================
// 6. knowledge-engineering.md — 向后兼容
// ===========================================================================
describe('knowledge-engineering.md: Backward compatibility', () => {
  let content;

  it('should explicitly state fallback when index.md is absent', async () => {
    content = await readContent(KNOWLEDGE_REF);
    assert.ok(
      /index\.md.*不存在|无\s*index|[Nn]o\s*index|without\s*index|缺少.*index/i.test(content) ||
      (/[Ff]allback/i.test(content) && content.includes('index.md')),
      'Must explicitly state behavior when index.md does not exist'
    );
  });

  it('should explicitly state fallback when domains/ is absent', async () => {
    content ??= await readContent(KNOWLEDGE_REF);
    assert.ok(
      /domains.*不存在|无\s*domains|[Nn]o\s*domains|without\s*domains|缺少.*domains/i.test(content) ||
      (/[Ff]allback/i.test(content) && content.includes('domains')),
      'Must explicitly state behavior when domains/ directory does not exist'
    );
  });
});

// ===========================================================================
// 7. SKILL.md — Design 阶段知识消费更新
// ===========================================================================
describe('SKILL.md: Design phase knowledge consumption', () => {
  let content;

  it('should load SKILL.md', async () => {
    content = await readContent(SKILL_MD);
    assert.ok(content.length > 0, 'SKILL.md should not be empty');
  });

  it('should reference index.md in design phase knowledge loading', async () => {
    content ??= await readContent(SKILL_MD);
    assert.ok(
      content.includes('index.md'),
      'Design phase knowledge loading must reference index.md for indexed retrieval'
    );
  });

  it('should describe two-phase consumption in knowledge loading section', async () => {
    content ??= await readContent(SKILL_MD);
    // The design phase knowledge section should mention phased loading
    const knowledgeSection = extractSection(content, '知识上下文加载');
    assert.ok(
      knowledgeSection !== null,
      'SKILL.md must have a knowledge context loading section'
    );
    assert.ok(
      /index|索引|Phase\s*1|阶段.*1|两阶段|分阶段/i.test(knowledgeSection),
      'Knowledge loading section must describe indexed/phased retrieval'
    );
  });

  it('should maintain fallback to full load when no index exists', async () => {
    content ??= await readContent(SKILL_MD);
    // Must retain fallback behavior description
    assert.ok(
      /不存在.*跳过|fallback|回退|降级|兼容/i.test(content),
      'SKILL.md must maintain fallback behavior description'
    );
  });
});

// ===========================================================================
// 8. SKILL.md — Merge 阶段知识提取更新
// ===========================================================================
describe('SKILL.md: Merge phase knowledge extraction', () => {
  let content;

  it('should reference tags in merge phase extraction', async () => {
    content = await readContent(SKILL_MD);
    const mergeSection = extractSection(content, '知识提取与沉淀') ?? extractSection(content, 'merge');
    assert.ok(
      mergeSection !== null,
      'SKILL.md must have a merge phase knowledge extraction section'
    );
    assert.ok(
      /tag|标签/i.test(mergeSection),
      'Merge phase must mention tag generation for extracted entries'
    );
  });

  it('should reference index.md sync in merge phase', async () => {
    content ??= await readContent(SKILL_MD);
    const mergeSection = extractSection(content, '知识提取与沉淀') ??
      extractSection(content, 'merge') ??
      content;
    assert.ok(
      mergeSection.includes('index.md') || mergeSection.includes('索引'),
      'Merge phase must mention syncing index.md when extracting knowledge'
    );
  });

  it('should reference domain partitioning in merge phase', async () => {
    content ??= await readContent(SKILL_MD);
    const mergeSection = extractSection(content, '知识提取与沉淀') ??
      extractSection(content, 'merge') ??
      content;
    assert.ok(
      /domain|领域|分区/i.test(mergeSection),
      'Merge phase must mention domain partitioning support'
    );
  });
});

// ===========================================================================
// 9. SKILL.md — 知识文件说明区域更新
// ===========================================================================
describe('SKILL.md: Knowledge file documentation section', () => {
  let content;

  it('should document index.md in knowledge file description', async () => {
    content = await readContent(SKILL_MD);
    // The knowledge files section (around line 515-516 originally) should mention index.md
    const knowledgeDocSection = extractSection(content, '知识文件') ?? content;
    assert.ok(
      knowledgeDocSection.includes('index.md') || knowledgeDocSection.includes('索引'),
      'Knowledge file documentation must mention index.md'
    );
  });

  it('should document domains/ in knowledge file description', async () => {
    content ??= await readContent(SKILL_MD);
    const knowledgeDocSection = extractSection(content, '知识文件') ?? content;
    assert.ok(
      knowledgeDocSection.includes('domains') || knowledgeDocSection.includes('领域'),
      'Knowledge file documentation must mention domains/ directory'
    );
  });
});

// ===========================================================================
// 10. Structural integrity — no regressions
// ===========================================================================
describe('Structural integrity: no regressions in SKILL.md', () => {
  let content;

  it('should still contain all original phases', async () => {
    content = await readContent(SKILL_MD);
    const requiredPhases = ['design', 'implement', 'qa', 'auto-fix', 'merge'];
    for (const phase of requiredPhases) {
      assert.ok(
        content.includes(`Phase: ${phase}`) || content.includes(`phase: "${phase}"`),
        `SKILL.md must still contain ${phase} phase`
      );
    }
  });

  it('should still contain core iron rules', async () => {
    content ??= await readContent(SKILL_MD);
    assert.ok(content.includes('核心铁律'), 'Must retain core iron rules section');
    assert.ok(content.includes('成功需要证据'), 'Must retain "success needs evidence" rule');
    assert.ok(content.includes('假设需要证据'), 'Must retain "assumptions need evidence" rule');
  });

  it('should still contain red team rules', async () => {
    content ??= await readContent(SKILL_MD);
    assert.ok(
      content.includes('绝对不允许修改红队验收测试'),
      'Must retain red team test immutability rule'
    );
  });

  it('should still reference knowledge-engineering.md', async () => {
    content ??= await readContent(SKILL_MD);
    assert.ok(
      content.includes('knowledge-engineering.md'),
      'Must still reference knowledge-engineering.md'
    );
  });

  it('should still contain frontmatter update warnings', async () => {
    content ??= await readContent(SKILL_MD);
    assert.ok(
      content.includes('绝对不要用 Write 工具重写整个状态文件'),
      'Must retain frontmatter update warning'
    );
  });
});

// ===========================================================================
// 11. Structural integrity — no regressions in knowledge-engineering.md
// ===========================================================================
describe('Structural integrity: no regressions in knowledge-engineering.md', () => {
  let content;

  it('should still contain Decision Log entry format', async () => {
    content = await readContent(KNOWLEDGE_REF);
    assert.ok(
      content.includes('Decision') || content.includes('决策'),
      'Must retain decision log entry format'
    );
    assert.ok(
      content.includes('Background') || content.includes('背景'),
      'Decision format must include Background field'
    );
  });

  it('should still contain Pattern/Lesson entry format', async () => {
    content ??= await readContent(KNOWLEDGE_REF);
    assert.ok(
      content.includes('Pattern') || content.includes('模式') || content.includes('Lesson'),
      'Must retain pattern/lesson entry format'
    );
    assert.ok(
      content.includes('Evidence') || content.includes('证据'),
      'Pattern format must include Evidence field'
    );
  });

  it('should still contain "Record a Decision When" rules', async () => {
    content ??= await readContent(KNOWLEDGE_REF);
    assert.ok(
      /Record a Decision When|记录.*决策.*条件/i.test(content),
      'Must retain decision recording criteria'
    );
  });

  it('should still contain "Do NOT Record" rules', async () => {
    content ??= await readContent(KNOWLEDGE_REF);
    assert.ok(
      /Do NOT Record|不.*记录/i.test(content),
      'Must retain "do not record" exclusion rules'
    );
  });

  it('should still contain size management rules', async () => {
    content ??= await readContent(KNOWLEDGE_REF);
    assert.ok(
      /[Ss]ize|大小|行数|150/i.test(content),
      'Must retain size management rules'
    );
  });

  it('should still contain time limit for extraction', async () => {
    content ??= await readContent(KNOWLEDGE_REF);
    assert.ok(
      content.includes('2') && /分钟|minute/i.test(content),
      'Must retain 2-minute time limit for knowledge extraction'
    );
  });
});

// ===========================================================================
// Helpers
// ===========================================================================

/**
 * Extract a section from markdown content by heading keyword.
 * Returns content from the matching heading to the next heading of same or higher level.
 */
function extractSection(content, keyword) {
  const lines = content.split('\n');
  let capturing = false;
  let captureLevel = 0;
  let result = [];

  for (const line of lines) {
    const headingMatch = line.match(/^(#{1,6})\s+(.+)/);
    if (headingMatch) {
      const level = headingMatch[1].length;
      const title = headingMatch[2];
      if (capturing) {
        if (level <= captureLevel) break;
      }
      if (!capturing && title.includes(keyword)) {
        capturing = true;
        captureLevel = level;
      }
    }
    if (capturing) {
      result.push(line);
    }
  }

  return result.length > 0 ? result.join('\n') : null;
}
