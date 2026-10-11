<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/brand/banner-dark.svg" />
    <img src="assets/brand/banner-light.svg" alt="autopilot — Self-driving loops for AI coding" width="92%" />
  </picture>

  <p><strong>A state-machine loop engine that takes a coding agent from goal to merged PR.</strong><br/>
  You stay in the captain's seat — not the cockpit.</p>

  <p>
    <a href="https://github.com/strzhao/autopilot/stargazers"><img src="https://img.shields.io/github/stars/strzhao/autopilot?style=flat-square&color=0D9488" alt="Stars" /></a>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/strzhao/autopilot?style=flat-square&color=16233A" alt="MIT License" /></a>
    <img src="https://img.shields.io/badge/version-v3.77.1-FF5A36?style=flat-square" alt="v3.77.1" />
    <img src="https://img.shields.io/badge/Claude%20Code-plugin-16233A?style=flat-square" alt="Claude Code plugin" />
    <img src="https://img.shields.io/badge/Codex-plugin-16233A?style=flat-square" alt="Codex plugin" />
  </p>

  <sub><a href="#why-autopilot-exists">Why</a> · <a href="#the-loop">The loop</a> · <a href="#an-aviation-operating-system-for-agents">Aviation OS</a> · <a href="#four-systems-aboard">Systems</a> · <a href="#the-toolkit">Toolkit</a> · <a href="#install">Install</a></sub>

  **English** | [简体中文](README.zh-CN.md)
</div>

---

## Why autopilot exists

AI coding agents fail in a predictable way: **they look done long before they are done.** "I checked" is not a check. 864 tests green while the input box doesn't work. A screenshot copied seven times to fake seven pieces of evidence. (These are real incidents from autopilot's own development — every mechanism in this plugin exists because one of them happened.)

The industry's answer so far is the *dumb loop* — replay the same prompt until the TODO list clears. It works until it doesn't: a loop with no memory of its phase, no gates, and no black box is just donating tokens to your API provider.

**autopilot is a loop with a flight management system.** Every iteration reads a persistent state file and knows exactly which phase it's in, which instruction to inject next, which gate failed, and what evidence is missing. Gates block the loop until evidence passes; evidence moves the loop forward; nobody has to watch.

## The loop

```text
          ┌─────────────────────────────────────────────────┐
          ▼                                                 │
  goal → design → implement → qa ──→ auto-fix ──→ merge → done
           │            │          │                          │
           ▼            ▼          ▼                          ▼
      ✋ you approve  red/blue   predicate gate          auto-chain
      the flight      teams      ∀ PASS ∧ 0 critical     next task
      plan            coding     (or back to auto-fix)   (evidence-based)
           ▲                                                     │
           └────────────── ✋ you clear the landing ─────────────┘
```

By default you intervene **exactly twice**: approve the flight plan (design review), clear the landing (final acceptance). Everything in between is the loop's job — and when every gate passes on evidence, you can delegate the gates too (`auto_approve` in project mode, or a `--headless` mode with deterministic, greppable audit trails for CI).

## An aviation operating system for agents

Commercial aviation is the safest way to travel — not because pilots are smarter than everyone else, but because of the operating system around them. autopilot ports that system to AI coding:

| Aviation | autopilot |
|---|---|
| Autopilot flying the cruise | Stop-hook loop engine (a 1,279-line state machine that blocks/re-injects/advances every turn) |
| Flight plan & waypoints | 6-phase state machine with two human gates |
| Cross-checked crew (pilot flying / pilot monitoring) | Red/blue adversarial implementation |
| Dispatch release criteria | Predicate gate: **∀ predicates PASS ∧ 0 critical** |
| Black box + post-flight debrief | Knowledge engineering: auto-extracted decisions & lessons |
| Preflight inspection | `doctor`: 14-dimension airworthiness scan |
| Captain's override | Human gates on design & acceptance — yours to hold, or to delegate to evidence-gated auto-approve |

## Four systems aboard

**1 · Phase orchestration.** fast/standard adapts per task (decided *after* codebase probes, not blind). Project mode chains whole tasks as a DAG with ≤500-word handoffs — no shared session state. Auto-chain is evidence-based, not counter-based: a task that went through auto-fix and converged all-green does *not* stop the chain.

**2 · Adversarial production.** The red team writes acceptance tests from the design document alone; the blue team implements from the plan alone. The isolation is enforced by machinery, not etiquette: section-level read whitelists, path-based agent handoffs, a physical staging area, and sha256 tamper locks. "Never touch red tests" is a deterministic hook, not a plea.

**3 · Evidence-gated acceptance.** Five defense layers in three waves: parallel commands (red tests, types, lint, unit, build) → real-scenario smoke (curl the API, click the page) → independent AI review. The merge gate is a formula, not a vibe: **every predicate PASS ∧ 0 critical**. A PASS without an artifact is mechanically graded FAIL. When mutation/coverage tooling exists, the bar is mutation ≥60% and coverage 80/70 — Meta (FSE 2025) measured mutation-targeted tests killing 32% of mutants vs 5.3% for coverage-targeted ones, and ~50% of LLM-written tests kill zero.

**4 · Knowledge engineering.** Every merge extracts decisions and lessons into a conflict-free inbox (one file per task on the write side — merge conflicts disappear *by construction*), consumed two-hops at design time, with anti-overfitting review and 180-day staleness checks. Your next task starts smarter.

## The toolkit

| Skill | What it does |
|---|---|
| `/autopilot <goal>` | The full loop: goal → merged |
| `/autopilot commit` | Context-aware smart commit — skips re-optimization on QA-verified code, quizzes you on design trade-offs (not syntax) |
| `/autopilot doctor` | 14-dimension airworthiness scan, S–F grades, and a compatibility matrix telling you exactly which autopilot features will degrade on your project — and why |
| `/autopilot next` (project mode) | Pick the next ready task in the DAG; each task is a full loop |
| brainstorm (built into design) | One-question-at-a-time requirement exploration; never re-asks what your knowledge base already answered |

## By the numbers

**146 versions** in 6.5 months (peak: 8 in one day) · **33,583 lines** of executable shell/Node · **90+ acceptance suites**, ~500 assertions · **15-row** feature×dimension compatibility matrix · **every** defensive mechanism traceable to a real incident.

## Install

**Claude Code**

```bash
/plugin marketplace add https://github.com/strzhao/autopilot.git
```

Then install **autopilot** from the marketplace. Manual alternative: clone the repo and run `/install plugins/autopilot`.

**Codex CLI**

```bash
git clone https://github.com/strzhao/autopilot.git && cd autopilot && codex
```

Inside Codex: `/plugins` → **String Codex Plugins** → install **Autopilot for Codex**.

## Built with itself

autopilot is developed on autopilot — v3.68/v3.69 shipped inside its own loop, with the system grading its own homework. 379 commits, 84% co-authored with Claude. One human, a fleet of AIs, and a black box that remembers all of it.

## License & contact

MIT © String Zhao ([stringzhao@foxmail.com](mailto:stringzhao@foxmail.com)) · ecosystem plugins: [writer-skill](plugins/writer-skill/) · [npm-toolkit](plugins/npm-toolkit/) · [summarizer](plugins/summarizer/) · [task-notifier](plugins/task-notifier/)
