# QA 报告模板

QA 报告在对话中产出供用户直接看（v3.37+ 不再持久化到 state.md，仅 frontmatter 写 gate/phase）：

```markdown
### QA 轮次 N (时间戳)

**Tier 0: 红队验收测试**
✅ user-avatar-upload.acceptance.test.ts: 3 passed (2.5s)
❌ image-crop.acceptance.test.ts: 1 failed — "裁剪后尺寸应为 200x200"

**Tier 1: 基础验证**
✅ 类型检查: 通过 (2.1s) | ✅ ESLint: 通过 (1.3s)
✅ 单元测试: 5 passed (3.5s) | ❌ 构建: 失败 — Module not found

**Tier 1.5: 谓词求值**（每行 = 一条预注册谓词的三元组）
| 谓词 | EARS 摘要 | artifact | 判定 |
|------|----------|----------|------|
| P1 [det-machine] | When 上传, shall 返回 avatar_url | `curl POST` 输出 HTTP 200 + `avatar_url` 字段 | ✅ PASS |
| P2 [real-process] | When 下载, shall 返回图片 | `curl /api/avatar/123` → HTTP 500 | ❌ FAIL |

**Tier 2a/2b: 审查**
✅ 设计符合性 | ⚠️ 安全: 1 低风险 | ✅ 边界处理

**Tier 3.5: 性能保障验证**（条件性）
✅ P1 Lighthouse: performance 94 (预算 ≥90 通过)
⚠️ P2 Playwright 性能: 跳过 (无性能断言文件)
✅ P3 Bundle Size: main.js 142KB < 200KB

**总结**: 通过 5 | 警告 1 | 失败 1 → 需修复: 构建失败

### 失败 Tier 清单
- Tier 0: image-crop.acceptance.test.ts — "裁剪后尺寸应为 200x200"
- Tier 1(构建): Module not found
- Tier 1.5: P2「下载」 — HTTP 500（谓词 FAIL）
```

## Tier 5 渲染规则

`tier5_status`（stop-hook §8.5.3 + lib.sh 产出，4 值 na/skipped/pass/fail）决定 Tier 5 栏渲染：
- `na` / `skipped` / `pass` / `fail` 的文案与阈值口径见 `references/quantitative-metrics.md` §5/§6/§7
- `na` 文案由 stop-hook §8.5.3 通过 systemMessage 注入，QA 报告原样渲染（不得含「PASS/绿灯/通过」字样）

---

## Tier 1.5 报告格式强制

每条谓词的 `artifact` 列**必须**是真实存在的命令输出 / 截图 / AX dump / 日志路径。以下为错误示范：

```markdown
# ❌ 错误：描述性文字代替 artifact
**Tier 1.5: 谓词求值**
（需启动 dev server 后在浏览器中验证，已通过 jest 验证 API 行为正确性）

# ❌ 错误：只有结论没有 artifact —— 无 artifact 的 PASS 自动判 FAIL
| P1 | ... | 已验证通过 | ✅ PASS |
```
