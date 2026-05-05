/**
 * Acceptance tests for knowledge-engineering upgrade (v3.14.0).
 *
 * Red-team verification: tests are written purely from the design document,
 * without reading any blue-team implementation code.
 *
 * Design spec (改动 A / B / C / D + 版本升级):
 *   A. knowledge-engineering.md 新增 ## Anti-Overfitting Principles 章节（5问自检 + 正反例）
 *   B. knowledge-engineering.md 新增 ## Integration over Append 章节 + Extraction Rules 步骤 0
 *   C. autopilot-doctor SKILL.md 新增 Dim 12「知识库健康度」；权重总和 = 1.00；5 检查项；N/A 处理
 *   D. 主 autopilot SKILL.md merge 阶段引用 Anti-Overfitting 和 Integration over Append
 *   版本: plugin.json + marketplace.json + CLAUDE.md 全部更新到 3.14.0
 *
 * Run: node --test tests/knowledge-engineering-upgrade.acceptance.test.mjs
 */

import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');

const KNOWLEDGE_ENG = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot/references/knowledge-engineering.md'
);
const DOCTOR_SKILL = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot-doctor/SKILL.md'
);
const MAIN_SKILL = resolve(
  ROOT,
  'plugins/autopilot/skills/autopilot/SKILL.md'
);
const PLUGIN_JSON = resolve(
  ROOT,
  'plugins/autopilot/.claude-plugin/plugin.json'
);
const MARKETPLACE = resolve(ROOT, '.claude-plugin/marketplace.json');
const CLAUDE_MD = resolve(ROOT, 'CLAUDE.md');

// ---------------------------------------------------------------------------
// 测试 1：knowledge-engineering.md 包含 Anti-Overfitting Principles 章节
// ---------------------------------------------------------------------------
describe('改动 A: Anti-Overfitting Principles 章节', () => {
  it('knowledge-engineering.md 包含 ## Anti-Overfitting Principles 标题', () => {
    const content = readFileSync(KNOWLEDGE_ENG, 'utf-8');
    assert.match(
      content,
      /##\s+Anti-Overfitting Principles/,
      'knowledge-engineering.md 必须包含 ## Anti-Overfitting Principles 章节标题'
    );
  });

  it('Anti-Overfitting 章节包含 ≥3 个 5 问自检关键词', () => {
    const content = readFileSync(KNOWLEDGE_ENG, 'utf-8');

    // 提取 Anti-Overfitting 章节内容（到下一个 ## 为止）
    const sectionMatch = content.match(
      /##\s+Anti-Overfitting Principles([\s\S]*?)(?=\n##\s|$)/
    );
    assert.ok(
      sectionMatch,
      'knowledge-engineering.md 必须包含 Anti-Overfitting Principles 章节，且内容可提取'
    );
    const section = sectionMatch[1];

    // 5 问自检关键词（来自设计文档的典型关键词）
    const keywords = [
      '6 个月',
      '另一个项目',
      '删掉 Evidence',
      '具体数值',
      'Lesson',
    ];
    const found = keywords.filter((kw) => section.includes(kw));
    assert.ok(
      found.length >= 3,
      `Anti-Overfitting 章节应包含 ≥3 个 5 问自检关键词，实际找到 ${found.length} 个（找到：${found.join(', ')}）`
    );
  });
});

// ---------------------------------------------------------------------------
// 测试 2：knowledge-engineering.md 包含 Integration over Append 章节
// ---------------------------------------------------------------------------
describe('改动 B: Integration over Append 章节', () => {
  it('knowledge-engineering.md 包含 ## Integration over Append 标题', () => {
    const content = readFileSync(KNOWLEDGE_ENG, 'utf-8');
    assert.match(
      content,
      /##\s+Integration over Append/,
      'knowledge-engineering.md 必须包含 ## Integration over Append 章节标题'
    );
  });

  it('Integration over Append 章节包含搜索、候选条目、合并关键词', () => {
    const content = readFileSync(KNOWLEDGE_ENG, 'utf-8');

    const sectionMatch = content.match(
      /##\s+Integration over Append([\s\S]*?)(?=\n##\s|$)/
    );
    assert.ok(
      sectionMatch,
      'knowledge-engineering.md 必须包含 Integration over Append 章节，且内容可提取'
    );
    const section = sectionMatch[1];

    // 关键词：搜索已有 / 候选条目（top 3 候选）/ 合并
    const hasSearch =
      section.includes('搜索已有') || section.includes('搜索');
    const hasCandidates =
      section.includes('top 3 候选') ||
      section.includes('候选条目') ||
      section.includes('候选');
    const hasMerge =
      section.includes('合并');

    assert.ok(
      hasSearch,
      'Integration over Append 章节必须包含"搜索已有"或"搜索"关键词'
    );
    assert.ok(
      hasCandidates,
      'Integration over Append 章节必须包含"top 3 候选"或"候选条目"关键词'
    );
    assert.ok(
      hasMerge,
      'Integration over Append 章节必须包含"合并"关键词'
    );
  });
});

// ---------------------------------------------------------------------------
// 测试 3：Extraction Rules > Execution Steps 第一步是步骤 0「搜索已有条目」
// ---------------------------------------------------------------------------
describe('改动 B: Extraction Rules 步骤 0 前置', () => {
  it('Extraction Rules Execution Steps 的第一步是步骤 0（搜索已有条目）', () => {
    const content = readFileSync(KNOWLEDGE_ENG, 'utf-8');

    // 提取 Extraction Rules 章节
    const extractionMatch = content.match(
      /##\s+Extraction Rules?([\s\S]*?)(?=\n##\s|$)/i
    );
    assert.ok(
      extractionMatch,
      'knowledge-engineering.md 必须包含 Extraction Rules 章节'
    );
    const extractionSection = extractionMatch[1];

    // 在 Execution Steps 子章节中找步骤 0
    const stepsMatch = extractionSection.match(
      /###\s+Execution Steps?([\s\S]*?)(?=\n###\s|\n##\s|$)/i
    );
    // 如果没有单独的 Execution Steps 子章节，在整个 Extraction Rules 中查找
    const stepsContent = stepsMatch ? stepsMatch[1] : extractionSection;

    // 步骤 0 必须先于步骤 1 出现
    const step0Idx = stepsContent.search(
      /(?:步骤\s*0|Step\s*0|0[.、:：]\s*(?:搜索|Search))/i
    );
    const step1Idx = stepsContent.search(
      /(?:步骤\s*1|Step\s*1|1[.、:：]\s*)/i
    );

    assert.ok(
      step0Idx !== -1,
      'Extraction Rules Execution Steps 必须包含步骤 0（搜索已有条目）'
    );

    if (step1Idx !== -1) {
      assert.ok(
        step0Idx < step1Idx,
        `步骤 0 必须在步骤 1 之前出现（步骤 0 位置: ${step0Idx}，步骤 1 位置: ${step1Idx}）`
      );
    }

    // 步骤 0 内容应含"搜索"或"search"语义
    const step0ContentMatch = stepsContent.slice(step0Idx).match(
      /(?:步骤\s*0|Step\s*0|0[.、:：][^\n]*)([\s\S]*?)(?=(?:步骤\s*1|Step\s*1|1[.、:：])|$)/i
    );
    if (step0ContentMatch) {
      const step0Content = step0ContentMatch[0];
      const hasSearchIntent =
        step0Content.includes('搜索') ||
        step0Content.toLowerCase().includes('search') ||
        step0Content.includes('检索') ||
        step0Content.includes('查找');
      assert.ok(
        hasSearchIntent,
        '步骤 0 内容必须包含"搜索"/"检索"/"查找"等搜索语义'
      );
    }
  });
});

// ---------------------------------------------------------------------------
// 测试 4：autopilot-doctor SKILL.md 包含 Dim 12 和知识库健康度标题
// ---------------------------------------------------------------------------
describe('改动 C: autopilot-doctor Dim 12 存在性', () => {
  it('autopilot-doctor SKILL.md 包含 Dim 12 字符串', () => {
    const content = readFileSync(DOCTOR_SKILL, 'utf-8');
    assert.ok(
      content.includes('Dim 12'),
      'autopilot-doctor SKILL.md 必须包含 "Dim 12" 字符串'
    );
  });

  it('autopilot-doctor SKILL.md 包含"知识库健康度"标题', () => {
    const content = readFileSync(DOCTOR_SKILL, 'utf-8');
    assert.ok(
      content.includes('知识库健康度'),
      'autopilot-doctor SKILL.md 必须包含 "知识库健康度" 标题（Dim 12 维度名称）'
    );
  });

  it('autopilot-doctor SKILL.md 中 Dim 12 章节是 Wave 2 类型', () => {
    const content = readFileSync(DOCTOR_SKILL, 'utf-8');

    // 提取 Dim 12 章节内容
    const dim12Match = content.match(
      /###\s+Dim\s+12[^\n]*([\s\S]*?)(?=###\s+Dim\s+\d+|##\s|$)/i
    );
    assert.ok(
      dim12Match,
      'autopilot-doctor SKILL.md 必须包含 ### Dim 12 子章节'
    );
    const dim12Content = dim12Match[1];

    // Wave 2 标识
    const isWave2 =
      dim12Content.includes('Wave 2') ||
      dim12Content.includes('wave2') ||
      dim12Content.includes('串行') ||
      dim12Content.includes('AI 判断');
    assert.ok(
      isWave2,
      'Dim 12 章节必须标注为 Wave 2（串行 AI 判断）类型'
    );
  });

  it('Dim 12 章节包含 N/A 处理（满分不计入）', () => {
    const content = readFileSync(DOCTOR_SKILL, 'utf-8');

    const dim12Match = content.match(
      /###\s+Dim\s+12[^\n]*([\s\S]*?)(?=###\s+Dim\s+\d+|##\s|$)/i
    );
    assert.ok(dim12Match, 'Dim 12 章节必须存在');
    const dim12Content = dim12Match[1];

    const hasNA =
      dim12Content.includes('N/A') ||
      dim12Content.includes('满分不计入') ||
      dim12Content.includes('不计入');
    assert.ok(
      hasNA,
      'Dim 12 章节必须包含 N/A 处理说明（满分不计入），与 Dim 11 一致'
    );
  });
});

// ---------------------------------------------------------------------------
// 测试 5：autopilot-doctor SKILL.md 权重表数值之和 = 1.00
// ---------------------------------------------------------------------------
describe('改动 C: autopilot-doctor 权重总和', () => {
  it('所有 Dim 权重之和精确等于 1.00（允许 ±0.001 浮点误差）', () => {
    const content = readFileSync(DOCTOR_SKILL, 'utf-8');

    // 匹配权重表中的数值行，格式如：
    //   | Dim 1: 测试基础设施 | 0.15 |
    //   | Dim 12: 知识库健康度 | 0.05 |
    // 兼容各种空格和格式变体
    const weightPattern =
      /\|\s*Dim\s*\d+[^|]*\|\s*(0\.\d+)\s*\|/g;

    const weights = [];
    let match;
    while ((match = weightPattern.exec(content)) !== null) {
      const w = parseFloat(match[1]);
      if (!isNaN(w)) {
        weights.push(w);
      }
    }

    assert.ok(
      weights.length >= 12,
      `权重表应包含至少 12 个 Dim 条目（Dim 1-12），实际解析到 ${weights.length} 个`
    );

    const sum = weights.reduce((a, b) => a + b, 0);
    const rounded = Math.round(sum * 1000) / 1000; // 保留 3 位小数

    assert.ok(
      Math.abs(rounded - 1.0) <= 0.001,
      `所有 Dim 权重之和必须 = 1.00，实际总和 = ${rounded}（各权重：${weights.join(', ')}）`
    );
  });
});

// ---------------------------------------------------------------------------
// 测试 6：autopilot-doctor Dim 12 章节包含 5 个检查项关键词
// ---------------------------------------------------------------------------
describe('改动 C: Dim 12 章节 5 检查项关键词', () => {
  it('Dim 12 章节包含全部 5 个检查项关键词（过拟合/重复/大小/索引/元信息）', () => {
    const content = readFileSync(DOCTOR_SKILL, 'utf-8');

    const dim12Match = content.match(
      /###\s+Dim\s+12[^\n]*([\s\S]*?)(?=###\s+Dim\s+\d+|##\s|$)/i
    );
    assert.ok(
      dim12Match,
      'autopilot-doctor SKILL.md 必须包含 ### Dim 12 子章节'
    );
    const dim12Content = dim12Match[1];

    const requiredKeywords = ['过拟合', '重复', '大小', '索引', '元信息'];
    const missing = requiredKeywords.filter((kw) => !dim12Content.includes(kw));

    assert.equal(
      missing.length,
      0,
      `Dim 12 章节缺少以下检查项关键词：${missing.join(', ')}（应包含全部：${requiredKeywords.join(', ')}）`
    );
  });
});

// ---------------------------------------------------------------------------
// 测试 7：主 SKILL.md merge 阶段引用 Anti-Overfitting 和 Integration over Append
// ---------------------------------------------------------------------------
describe('改动 D: 主 SKILL.md merge 阶段引用', () => {
  it('主 SKILL.md merge 阶段包含 Anti-Overfitting 引用', () => {
    const content = readFileSync(MAIN_SKILL, 'utf-8');

    // 提取 merge 阶段内容
    const mergeMatch = content.match(
      /##\s*Phase:\s*merge([\s\S]*?)(?=\n##\s*Phase:|$)/i
    );
    assert.ok(
      mergeMatch,
      '主 SKILL.md 必须包含 Phase: merge 章节'
    );
    const mergeSection = mergeMatch[1];

    assert.ok(
      mergeSection.includes('Anti-Overfitting'),
      '主 SKILL.md merge 阶段步骤 2 必须引用 "Anti-Overfitting" 关键词'
    );
  });

  it('主 SKILL.md merge 阶段包含 Integration over Append 引用', () => {
    const content = readFileSync(MAIN_SKILL, 'utf-8');

    const mergeMatch = content.match(
      /##\s*Phase:\s*merge([\s\S]*?)(?=\n##\s*Phase:|$)/i
    );
    assert.ok(
      mergeMatch,
      '主 SKILL.md 必须包含 Phase: merge 章节'
    );
    const mergeSection = mergeMatch[1];

    assert.ok(
      mergeSection.includes('Integration over Append'),
      '主 SKILL.md merge 阶段步骤 2 必须引用 "Integration over Append" 关键词'
    );
  });
});

// ---------------------------------------------------------------------------
// 测试 8：版本一致性（3.14.0）
// ---------------------------------------------------------------------------
describe('版本升级: 3.13.1 → 3.14.0 全文件一致性', () => {
  it('plugins/autopilot/.claude-plugin/plugin.json version = "3.14.0"', () => {
    const content = readFileSync(PLUGIN_JSON, 'utf-8');
    const json = JSON.parse(content);
    assert.equal(
      json.version,
      '3.14.0',
      `plugin.json version 必须为 "3.14.0"，实际为 "${json.version}"`
    );
  });

  it('.claude-plugin/marketplace.json 中 autopilot 条目 version = "3.14.0"', () => {
    const content = readFileSync(MARKETPLACE, 'utf-8');
    const json = JSON.parse(content);
    const autopilot = json.plugins?.find(
      (p) => p.name === 'autopilot' || p.id === 'autopilot'
    );
    assert.ok(
      autopilot,
      'marketplace.json 必须包含 name="autopilot" 的条目'
    );
    assert.equal(
      autopilot.version,
      '3.14.0',
      `marketplace.json autopilot version 必须为 "3.14.0"，实际为 "${autopilot.version}"`
    );
  });

  it('CLAUDE.md 包含 "(v3.14.0)" 字样', () => {
    const content = readFileSync(CLAUDE_MD, 'utf-8');
    assert.ok(
      content.includes('(v3.14.0)'),
      'CLAUDE.md 必须包含 "(v3.14.0)" 字样（autopilot 插件标题版本号）'
    );
  });

  it('CLAUDE.md autopilot 行不残留 "(v3.13.1)" 旧版本号', () => {
    const content = readFileSync(CLAUDE_MD, 'utf-8');
    // 找到包含 autopilot 且含有版本号的行，确保没有 v3.13.1
    const lines = content.split('\n');
    const oldVersionLines = lines.filter(
      (line) =>
        line.includes('autopilot') &&
        line.includes('(v3.13.1)')
    );
    assert.equal(
      oldVersionLines.length,
      0,
      `CLAUDE.md 中不应残留含 "(v3.13.1)" 的 autopilot 行，发现残留行：\n${oldVersionLines.join('\n')}`
    );
  });
});
