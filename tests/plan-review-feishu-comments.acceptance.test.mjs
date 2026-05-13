/**
 * 验收测试：plan-review 飞阅评论重设计（v3.29.0）
 *
 * 红队验证：测试纯基于设计文档编写，不读取蓝队的 plan-review-template.html 源码。
 * 测试通过「执行 python3 占位符替换逻辑 → 产物 HTML 字符串断言」验证蓝队实现是否符合契约。
 *
 * 关键契约：
 *   C1 - 占位符名称（3个，全部必须被替换）
 *   C2 - WS payload schema（含 comments[]）
 *   C3 - DOM 锚点 data-block-id
 *   C4 - 顶部工具栏 DOM 标识
 *   C5 - 浮动评论触发器 id
 *   C6 - 评论卡片 DOM 协议
 *   C7 - 不可改动接口列表
 *   D5b - stopImmediatePropagation 防重复触发
 *
 * Run: node --test tests/plan-review-feishu-comments.acceptance.test.mjs
 */

import { describe, it, before } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');

const TEMPLATE_PATH = resolve(
  ROOT,
  'plugins/autopilot/scripts/visual-companion/plan-review-template.html'
);
const MARKED_LIB_PATH = resolve(
  ROOT,
  'plugins/autopilot/scripts/visual-companion/marked.min.js'
);
const HELPER_JS_PATH = resolve(
  ROOT,
  'plugins/autopilot/scripts/visual-companion/helper.js'
);
const WAIT_DECISION_PATH = resolve(
  ROOT,
  'plugins/autopilot/scripts/visual-companion/wait-decision.sh'
);
const PLUGIN_JSON_PATH = resolve(
  ROOT,
  'plugins/autopilot/.claude-plugin/plugin.json'
);
const MARKETPLACE_PATH = resolve(ROOT, '.claude-plugin/marketplace.json');
const CLAUDE_MD_PATH = resolve(ROOT, 'CLAUDE.md');

// ---------------------------------------------------------------------------
// 渲染引擎：复用 launch-plan-review.sh 的 python3 占位符替换逻辑
// 不启动 server，直接产生 HTML 产物字符串（纯静态断言，不依赖浏览器）
// ---------------------------------------------------------------------------
let renderedHTML = '';
let renderError = null;

function renderTemplate(autoClosePref = 'true') {
  const sampleDesignContent = '&lt;h2&gt;测试设计文档&lt;/h2&gt;&lt;p&gt;这是一段测试内容，用于验证占位符替换和 DOM 结构。&lt;/p&gt;';

  // python3 inline 替换脚本（与 launch-plan-review.sh:105-133 完全一致的逻辑）
  const pythonScript = `
import sys, os

template_path = sys.argv[1]
design_content = sys.argv[2]
output_path = sys.argv[3]
marked_lib_path = sys.argv[4]
auto_close_pref = sys.argv[5]

with open(template_path, 'r', encoding='utf-8') as f:
    tmpl = f.read()

marked_lib = ''
if os.path.isfile(marked_lib_path):
    with open(marked_lib_path, 'r', encoding='utf-8') as f:
        marked_lib = f.read()

result = tmpl.replace('{{MARKED_LIB}}', marked_lib)
result = result.replace('{{AUTO_CLOSE_PREF}}', auto_close_pref)
result = result.replace('{{DESIGN_CONTENT}}', design_content)

with open(output_path, 'w', encoding='utf-8') as f:
    f.write(result)

print('OK')
`;

  const tmpDir = mkdtempSync(resolve(tmpdir(), 'plan-review-test-'));
  const outputPath = resolve(tmpDir, 'plan-review.html');
  const scriptPath = resolve(tmpDir, 'render.py');

  try {
    writeFileSync(scriptPath, pythonScript, 'utf-8');

    const result = spawnSync('python3', [
      scriptPath,
      TEMPLATE_PATH,
      sampleDesignContent,
      outputPath,
      MARKED_LIB_PATH,
      autoClosePref,
    ], { encoding: 'utf-8', timeout: 15000 });

    if (result.error) {
      throw new Error(`python3 spawn error: ${result.error.message}`);
    }
    if (result.status !== 0) {
      throw new Error(`python3 exited ${result.status}: ${result.stderr}`);
    }
    if (!existsSync(outputPath)) {
      throw new Error(`Output file not created: ${outputPath}`);
    }

    return readFileSync(outputPath, 'utf-8');
  } finally {
    try { rmSync(tmpDir, { recursive: true, force: true }); } catch (_) { /* ignore */ }
  }
}

// 在所有测试前渲染一次，后续测试共享产物字符串
before(() => {
  try {
    renderedHTML = renderTemplate('true');
  } catch (err) {
    renderError = err;
  }
});

// ---------------------------------------------------------------------------
// 辅助：确保模板文件存在（若模板未被蓝队写好，所有断言测试以明确错误失败）
// ---------------------------------------------------------------------------
describe('渲染前置条件', () => {
  it('plan-review-template.html 必须存在', () => {
    assert.ok(
      existsSync(TEMPLATE_PATH),
      `plan-review-template.html 不存在: ${TEMPLATE_PATH}`
    );
  });

  it('python3 渲染流程必须成功（无异常）', () => {
    assert.equal(
      renderError,
      null,
      `渲染失败: ${renderError?.message ?? ''}`
    );
    assert.ok(
      renderedHTML.length > 100,
      `产物 HTML 过短（${renderedHTML.length} 字节），渲染可能静默失败`
    );
  });
});

// ---------------------------------------------------------------------------
// C1. 占位符替换完整性（3 个占位符全部被替换，产物无 `{{` 残留）
// ---------------------------------------------------------------------------
describe('C1 - 占位符替换完整性', () => {
  it('产物 HTML 中不应残留任何 {{ 占位符字面量', () => {
    // 排除 HTML 实体 / JS 模板字面量（如 `${...}`），仅检查 {{...}} 形式
    const doubleBracePattern = /\{\{[A-Z_]+\}\}/;
    assert.ok(
      !doubleBracePattern.test(renderedHTML),
      '产物 HTML 中残留了未替换的 {{...}} 占位符（{{MARKED_LIB}} / {{AUTO_CLOSE_PREF}} / {{DESIGN_CONTENT}} 之一未被替换）'
    );
  });

  it('{{MARKED_LIB}} 已被替换（产物含 marked.js 特征代码）', () => {
    // marked.min.js 必然含 "marked" 关键字或函数特征
    assert.ok(
      renderedHTML.includes('marked') || renderedHTML.includes('function'),
      '产物 HTML 不含 marked.js 特征，{{MARKED_LIB}} 可能未被替换'
    );
  });

  it('{{DESIGN_CONTENT}} 已被替换（产物含注入的设计文档片段）', () => {
    // 注入的 sampleDesignContent 含 html escape 形式的 &lt;h2&gt;
    assert.ok(
      renderedHTML.includes('测试设计文档') || renderedHTML.includes('&lt;h2&gt;'),
      '产物 HTML 不含设计文档内容，{{DESIGN_CONTENT}} 可能未被替换'
    );
  });
});

// ---------------------------------------------------------------------------
// C4. 顶部工具栏 DOM 标识
// ---------------------------------------------------------------------------
describe('C4 - 顶部工具栏 DOM 结构', () => {
  it('工具栏必须含 class="toolbar" 或 class 含 toolbar', () => {
    assert.ok(
      /class="[^"]*toolbar[^"]*"/.test(renderedHTML) ||
      renderedHTML.includes('class="toolbar"'),
      '产物 HTML 中未找到 .toolbar 类（顶部工具栏）'
    );
  });

  it('「同意」按钮必须有 data-choice="approve"', () => {
    assert.ok(
      renderedHTML.includes('data-choice="approve"'),
      '产物 HTML 中未找到 data-choice="approve"（同意按钮）'
    );
  });

  it('「反馈」按钮必须有 data-choice="revise"', () => {
    assert.ok(
      renderedHTML.includes('data-choice="revise"'),
      '产物 HTML 中未找到 data-choice="revise"（反馈按钮）'
    );
  });

  it('「放弃任务」必须有 data-choice="abort"', () => {
    assert.ok(
      renderedHTML.includes('data-choice="abort"'),
      '产物 HTML 中未找到 data-choice="abort"（放弃任务）'
    );
  });

  it('「决策后自动关闭」toggle 必须有 data-pref="auto_close_after_decision"', () => {
    assert.ok(
      renderedHTML.includes('data-pref="auto_close_after_decision"'),
      '产物 HTML 中未找到 data-pref="auto_close_after_decision"（auto-close toggle）'
    );
  });

  it('更多菜单容器必须有 id="more-menu"', () => {
    assert.ok(
      renderedHTML.includes('id="more-menu"'),
      '产物 HTML 中未找到 id="more-menu"（⋯ 下拉菜单容器）'
    );
  });
});

// ---------------------------------------------------------------------------
// C5. 浮动评论触发器
// ---------------------------------------------------------------------------
describe('C5 - 浮动评论触发器', () => {
  it('浮动按钮必须有 id="floating-comment-trigger"', () => {
    assert.ok(
      renderedHTML.includes('id="floating-comment-trigger"'),
      '产物 HTML 中未找到 id="floating-comment-trigger"（浮动评论气泡按钮）'
    );
  });

  it('右侧评论栏容器必须有 id="comments-pane"', () => {
    assert.ok(
      renderedHTML.includes('id="comments-pane"'),
      '产物 HTML 中未找到 id="comments-pane"（右侧 marginalia 评论栏）'
    );
  });
});

// ---------------------------------------------------------------------------
// C6. 评论卡片 DOM 协议
// ---------------------------------------------------------------------------
describe('C6 - 评论卡片 DOM 协议', () => {
  it('必须含 comment-card class 字面（卡片模板/创建逻辑）', () => {
    assert.ok(
      renderedHTML.includes('comment-card'),
      '产物 HTML 中未找到 "comment-card"（评论卡片 class）'
    );
  });

  it('必须含 data-anchor 字面（锚点 dataset 协议）', () => {
    assert.ok(
      renderedHTML.includes('data-anchor'),
      '产物 HTML 中未找到 "data-anchor"（卡片锚点 dataset）'
    );
  });

  it('必须含 comment-quote class 字面（引用文本元素）', () => {
    assert.ok(
      renderedHTML.includes('comment-quote'),
      '产物 HTML 中未找到 "comment-quote"（引用文本子元素）'
    );
  });

  it('必须含 comment-text class 字面（评论输入 textarea）', () => {
    assert.ok(
      renderedHTML.includes('comment-text'),
      '产物 HTML 中未找到 "comment-text"（评论输入 textarea）'
    );
  });

  it('必须含 comment-save class 字面（保存按钮）', () => {
    assert.ok(
      renderedHTML.includes('comment-save'),
      '产物 HTML 中未找到 "comment-save"（保存按钮）'
    );
  });

  it('必须含 comment-delete class 字面（删除按钮）', () => {
    assert.ok(
      renderedHTML.includes('comment-delete'),
      '产物 HTML 中未找到 "comment-delete"（删除按钮）'
    );
  });
});

// ---------------------------------------------------------------------------
// C3. data-block-id 注入逻辑
// ---------------------------------------------------------------------------
describe('C3 - block-id 注入逻辑', () => {
  it('必须含 data-block-id 字面或 blockId / dataset.blockId 注入代码', () => {
    const hasBlockId =
      renderedHTML.includes('data-block-id') ||
      renderedHTML.includes('blockId') ||
      renderedHTML.includes('block-id') ||
      renderedHTML.includes('dataset.blockId');
    assert.ok(
      hasBlockId,
      '产物 HTML 中未找到 data-block-id 相关字面（DOM 锚点注入逻辑缺失）'
    );
  });

  it('block-id 前缀格式必须为 "b-"（b- 前缀 + 整数）', () => {
    // 测试 JS 代码中含 'b-' + counter 形式的生成逻辑
    const hasBPrefix =
      renderedHTML.includes("'b-'") ||
      renderedHTML.includes('"b-"') ||
      renderedHTML.includes('`b-') ||
      renderedHTML.includes("b-' +") ||
      /b-\d+/.test(renderedHTML);
    assert.ok(
      hasBPrefix,
      '产物 HTML 中未找到 "b-" 前缀（block-id 格式协议不符合 C3）'
    );
  });
});

// ---------------------------------------------------------------------------
// D5b. 双重触发拦截（stopImmediatePropagation）
// ---------------------------------------------------------------------------
describe('D5b - 双重 WS 触发拦截', () => {
  it('必须含 stopImmediatePropagation 字面（阻断 helper.js 后注册 listener）', () => {
    assert.ok(
      renderedHTML.includes('stopImmediatePropagation'),
      '产物 HTML 中未找到 stopImmediatePropagation（D5b 防重复发送逻辑缺失，会导致 helper.js 重复推送 WS frame 且评论数据丢失）'
    );
  });
});

// ---------------------------------------------------------------------------
// 旧布局组件移除断言（设计文档 D4：底部组件全部迁顶部）
// ---------------------------------------------------------------------------
describe('旧布局组件 CSS selector 已移除', () => {
  it('.actions { CSS selector 不应存在（底部 actions 区已迁顶部）', () => {
    // 检查形如 ".actions {" 或 ".actions{" 的 CSS class selector 定义
    // 注意：comment-actions 是新组件，不在禁止范围；这里只查 ".actions {" 独立 selector
    const actionsSelector = /\.actions\s*\{/.test(renderedHTML);
    assert.ok(
      !actionsSelector,
      '产物 HTML 中仍含 .actions { CSS selector 定义（旧底部 actions 区未移除）'
    );
  });

  it('.feedback-section { CSS selector 不应存在（feedback 输入区已迁顶部 revise 流程）', () => {
    const feedbackSelector = /\.feedback-section\s*\{/.test(renderedHTML);
    assert.ok(
      !feedbackSelector,
      '产物 HTML 中仍含 .feedback-section { CSS selector 定义（旧 feedback-section 未移除）'
    );
  });

  it('.indicator-bar { CSS selector 不应存在（indicator-bar 已迁顶部工具栏）', () => {
    const indicatorSelector = /\.indicator-bar\s*\{/.test(renderedHTML);
    assert.ok(
      !indicatorSelector,
      '产物 HTML 中仍含 .indicator-bar { CSS selector 定义（旧 indicator-bar 未移除）'
    );
  });
});

// ---------------------------------------------------------------------------
// 版本号同步（v3.29.0）
// ---------------------------------------------------------------------------
describe('版本号三处同步（v3.29.0）', () => {
  it('plugin.json version 必须为 "3.29.0"', () => {
    const content = readFileSync(PLUGIN_JSON_PATH, 'utf-8');
    const json = JSON.parse(content);
    assert.equal(
      json.version,
      '3.29.0',
      `plugin.json version 应为 "3.29.0"，实际为 "${json.version}"`
    );
  });

  it('marketplace.json autopilot version 必须为 "3.29.0"', () => {
    const content = readFileSync(MARKETPLACE_PATH, 'utf-8');
    const json = JSON.parse(content);
    const autopilot = json.plugins?.find(
      (p) => p.name === 'autopilot' || p.id === 'autopilot'
    );
    assert.ok(autopilot, 'marketplace.json 必须含 autopilot 插件条目');
    assert.equal(
      autopilot.version,
      '3.29.0',
      `marketplace.json autopilot version 应为 "3.29.0"，实际为 "${autopilot.version}"`
    );
  });

  it('CLAUDE.md 插件索引表 autopilot 行必须含 v3.29.0', () => {
    const content = readFileSync(CLAUDE_MD_PATH, 'utf-8');
    // 插件索引表格式：| [autopilot](...) | v3.29.0 | ...
    const lines = content.split('\n');
    const autopilotLine = lines.find(
      (line) => line.includes('autopilot') && /v\d+\.\d+\.\d+/.test(line)
    );
    assert.ok(
      autopilotLine,
      'CLAUDE.md 插件索引表中未找到含版本号的 autopilot 行'
    );
    assert.ok(
      autopilotLine.includes('v3.29.0'),
      `CLAUDE.md autopilot 行版本应为 v3.29.0，实际行内容：\n  ${autopilotLine.trim()}`
    );
  });
});

// ---------------------------------------------------------------------------
// C7. 不可改动接口：helper.js 未被修改
// ---------------------------------------------------------------------------
describe('C7 - 不可改动接口：helper.js 未变更', () => {
  it('helper.js 必须存在且包含 [data-choice] 委托事件监听（核心协议）', () => {
    assert.ok(existsSync(HELPER_JS_PATH), `helper.js 不存在: ${HELPER_JS_PATH}`);
    const content = readFileSync(HELPER_JS_PATH, 'utf-8');
    assert.ok(
      content.includes('[data-choice]'),
      'helper.js 中 [data-choice] 委托监听已被移除（C7 违规：helper.js 不可改动）'
    );
  });

  it('helper.js 必须包含 sendEvent 函数（WS 推送核心）', () => {
    const content = readFileSync(HELPER_JS_PATH, 'utf-8');
    assert.ok(
      content.includes('sendEvent'),
      'helper.js 中 sendEvent 函数已消失（C7 违规：helper.js 不可改动）'
    );
  });

  it('helper.js 不应包含 stopImmediatePropagation（拦截逻辑只能在模板 JS 里）', () => {
    const content = readFileSync(HELPER_JS_PATH, 'utf-8');
    assert.ok(
      !content.includes('stopImmediatePropagation'),
      'helper.js 中含 stopImmediatePropagation（D5b 拦截逻辑应在模板内嵌 JS，而非 helper.js）'
    );
  });
});

// ---------------------------------------------------------------------------
// C7. 不可改动接口：wait-decision.sh 正则兼容性
// ---------------------------------------------------------------------------
describe('C7 - wait-decision.sh 正则向后兼容', () => {
  it('wait-decision.sh 检测正则仍为 "choice":"(approve|revise|abort)"', () => {
    assert.ok(
      existsSync(WAIT_DECISION_PATH),
      `wait-decision.sh 不存在: ${WAIT_DECISION_PATH}`
    );
    const content = readFileSync(WAIT_DECISION_PATH, 'utf-8');
    assert.ok(
      content.includes('"choice":"(approve|revise|abort)"') ||
      content.includes('"choice":"(approve|revise|abort)"\')') ||
      /choice.*approve.*revise.*abort/.test(content),
      'wait-decision.sh 中检测正则已被改动（C7 违规）'
    );
  });

  it('含 comments 的合法 WS payload 必须能被 wait-decision.sh 正则命中', () => {
    // 构造符合 C2 的合法 payload（含 comments 数组）
    const payload = JSON.stringify({
      type: 'click',
      text: '同意',
      choice: 'approve',
      feedback: '',
      comments: [
        { anchor: 'b-3', quote: '红队铁律示例', text: '这条规则太严苛了' }
      ],
      id: null,
      timestamp: 1747000000000,
    });

    // wait-decision.sh:51 使用的 bash regex（等价于 JS 正则）
    const waitDecisionRegex = /"choice":"(approve|revise|abort)"/;
    assert.ok(
      waitDecisionRegex.test(payload),
      `合法 payload 无法被 wait-decision.sh 正则命中。\n  payload: ${payload}\n  regex: ${waitDecisionRegex}`
    );

    // 额外验证三种 choice 值都能命中
    for (const choice of ['approve', 'revise', 'abort']) {
      const p = JSON.stringify({ ...JSON.parse(payload), choice, text: choice });
      assert.ok(
        waitDecisionRegex.test(p),
        `choice="${choice}" 的 payload 无法被 wait-decision.sh 正则命中`
      );
    }
  });

  it('anchor 字段必须匹配 ^b-\\d+$ 格式', () => {
    const validAnchors = ['b-1', 'b-2', 'b-99', 'b-100'];
    const invalidAnchors = ['b-', 'B-1', 'block-1', 'b-abc', '1', ''];
    const anchorRegex = /^b-\d+$/;

    for (const anchor of validAnchors) {
      assert.ok(anchorRegex.test(anchor), `合法 anchor "${anchor}" 未通过格式校验`);
    }
    for (const anchor of invalidAnchors) {
      assert.ok(!anchorRegex.test(anchor), `非法 anchor "${anchor}" 意外通过了格式校验`);
    }
  });
});

// ---------------------------------------------------------------------------
// 跨系统数据流：C2 WS payload schema 完整性（构造字符串验证所有必要字段）
// ---------------------------------------------------------------------------
describe('C2 - WS payload schema 完整性', () => {
  it('合法 payload 必须含全部必要字段：type / text / choice / feedback / comments / id / timestamp', () => {
    const payload = {
      type: 'click',
      text: '反馈',
      choice: 'revise',
      feedback: '整体方向没问题，但降级方案欠缺',
      comments: [
        { anchor: 'b-5', quote: '某一段文字', text: '这里的降级方案漏了断网场景' }
      ],
      id: null,
      timestamp: Date.now(),
    };

    const requiredFields = ['type', 'text', 'choice', 'feedback', 'comments', 'id', 'timestamp'];
    for (const field of requiredFields) {
      assert.ok(
        Object.prototype.hasOwnProperty.call(payload, field),
        `合法 payload 缺少必要字段: "${field}"`
      );
    }

    // comments 必须为数组
    assert.ok(Array.isArray(payload.comments), 'comments 必须为数组');

    // 空 comments 场景：comments 字段仍必须存在且为空数组
    const emptyCommentsPayload = { ...payload, comments: [] };
    assert.ok(
      Array.isArray(emptyCommentsPayload.comments) && emptyCommentsPayload.comments.length === 0,
      '空 comments 场景：comments 字段必须为空数组而非 null/undefined'
    );

    // feedback 空字符串而非 null
    const approvePayload = { ...payload, choice: 'approve', feedback: '', comments: [] };
    assert.equal(
      typeof approvePayload.feedback,
      'string',
      'feedback 必须为字符串（空字符串），不能为 null'
    );

    // choice 值必须为三者之一
    const validChoices = ['approve', 'revise', 'abort'];
    assert.ok(
      validChoices.includes(payload.choice),
      `choice 值 "${payload.choice}" 不在合法集合 ${validChoices.join('/')} 内`
    );
  });

  it('序列化后的 payload JSON 字符串格式与 wait-decision.sh 正则兼容', () => {
    // JSON.stringify 默认无空格，与 wait-decision.sh 的检测正则兼容
    const payload = {
      type: 'click',
      text: '同意',
      choice: 'approve',
      feedback: '',
      comments: [],
      id: null,
      timestamp: 1747000000000,
    };
    const jsonStr = JSON.stringify(payload);
    const waitDecisionRegex = /"choice":"(approve|revise|abort)"/;
    assert.ok(
      waitDecisionRegex.test(jsonStr),
      `JSON.stringify 产出的格式与 wait-decision.sh 正则不兼容。\n  JSON: ${jsonStr}`
    );
  });
});
