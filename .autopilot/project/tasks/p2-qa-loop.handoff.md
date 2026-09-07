---
id: p2-qa-loop
status: done
---

# p2-qa-loop.handoff — QA 回炉治理（v3.64.0）

## 实现摘要
两项改动落地：① auto-fix 批量修复纪律——SKILL.md §3 重构两段式骨架 + auto-fix-phase.md §3 完整两段式（阶段一全部失败项观察/假设/验证 + 共同上游根因；阶段二统一修复 → 一轮跑齐验证），旧表述「立即运行对应检查命令」全仓清零 ② 蓝队自检复用——lib.sh `tree_sig`（sha256，diff HEAD ∪ untracked 去重，排除模式收紧防 latest.ts 类误伤）、blue-team-prompt 清单 C3 格式、SKILL.md 合流段写区域（首行 tree_sig）+ Tier 1 三条件沿用 + auto-fix 触及测试文件作废区域 + state-file-guide 登记 + anti-rationalization 反向条目。SKILL.md 491→478 净减 13。QA 全绿：红队 19/19、npm 80/80、run-all 41/41、谓词 16/16、qa-reviewer 0 Critical；**沿用机制本任务内闭环 dogfood 成立**（sig 0372a32c… 合流前后一致）。

## 文件变更
修改 13（lib.sh +37 / SKILL.md / 5 references / 版本 4 处 / 测试 2 个），无增删文件。详见本任务 commit。

## 下游须知（T3 必读）
- **新行号基线**：SKILL.md 478 / auto-fix-phase.md 91 / state-file-guide.md 83 / blue-team-prompt.md 41；lib.sh 尾部新增 tree_sig（lib.sh:761-792，**T3 的 load_state 重构注意与其共存**——load_state 动 frontmatter 读取、tree_sig 动 git 内容，无交集）
- **lib.sh 已 +37 行**：T3 load_state 重构时的 lib.sh 行号全部漂移，锚点以 grep 为准
- **stop-hook 零改动**（本任务未触 stop-hook.sh）——T3 的 43 处 get_field/get_enum_field 现状与调研时一致
- **p0-qa-dedup 场景 8 已动态化**：T3 bump 3.65.0 时 p0/p2 两测试的动态版本断言都不会假红（p2 测试另有 >= 3.64.0 数值兜底）
- **dogfood 观察留档**：knowledge patterns.md [2026-09-07] 自适用盲区——本任务自身漏写 context.md；T3 记得在 design 步骤 1 写 context.md（对自身也要走机制）

## 偏差说明
蓝队 3 项设计偏差（tree_sig 排除模式加中段目录超集变体 / 旧字面清零外延到 changelog 引用 / 术语对齐 2 处）——QA Section A/B/C/D 复核全部合规且契约语义不变，非实质偏差。qa-reviewer 3 个 Low 建议（裸名测试文件签名缝隙 / tree_sig 参数注释 / anti-rationalization 条目落位）不阻塞，留后续专项。
