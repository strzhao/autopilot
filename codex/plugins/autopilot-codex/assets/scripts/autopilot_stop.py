#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from autopilot_common import append_changelog, now_iso, read_state, state_path_for, write_state


def play_sound() -> None:
    script = Path(__file__).resolve().parent / "play-sound.sh"
    if not script.exists():
        return
    try:
        subprocess.run(["bash", str(script), "stop"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        return


def emit_block(reason: str, system_message: str) -> None:
    payload = {
        "decision": "block",
        "reason": reason,
        "systemMessage": system_message,
    }
    json.dump(payload, sys.stdout, ensure_ascii=False)


def build_phase_prompt(state_path: Path, phase: str, iteration: int) -> str:
    base = (
        f"Active Codex autopilot workflow detected. Read {state_path} and continue phase `{phase}`. "
        "Follow the repository's Autopilot for Codex workflow, keep all runtime state in .codex/, and write evidence back to the state file."
    )
    if phase == "design":
        return (
            f"{base} Load relevant .autopilot context, finish the design document, run the plan reviewer sub-agent, "
            "and stop only when gate=`design-approval`."
        )
    if phase == "implement":
        return (
            f"{base} Before coding, finalize the red-team acceptance criteria. Then launch blue-team and red-team sub-agents in parallel. "
            "Red team must only see the design document. Record any forced downgrade if sub-agents are unavailable."
        )
    if phase == "qa":
        return (
            f"{base} Execute QA in order: Tier 0 red-team acceptance, Tier 1 static checks, Tier 1.5 real user scenarios, "
            "Tier 2 design/code review agents, then Tier 3/4 if needed. If QA fails, update the state file to phase `auto-fix` without modifying red-team tests."
        )
    if phase == "auto-fix":
        return (
            f"{base} Read the latest QA failures first, record root cause and fix evidence, keep red-team tests unchanged, "
            "and rerun only the affected validations. If retries remain, set `qa_scope=selective` and move back to `qa`; otherwise hand control back behind `review-accept`."
        )
    if phase == "merge":
        return (
            f"{base} Prepare the merge summary, invoke `$autopilot-commit-codex` when appropriate, extract durable knowledge if required, and move the workflow to `done` when complete."
        )
    return f"{base} Iteration: {iteration}."


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}

    cwd = payload.get("cwd")
    hook_session = str(payload.get("session_id") or "")
    state_file = state_path_for(cwd)
    if not state_file.exists():
        return 0

    try:
        state, body = read_state(state_file)
    except Exception:
        return 0

    phase = str(state.get("phase") or "")
    gate = str(state.get("gate") or "")
    current_session = str(state.get("session_id") or "")

    if not current_session and hook_session:
        state["session_id"] = hook_session
        state["updated_at"] = now_iso()
        write_state(state_file, state, body)
        current_session = hook_session

    if current_session and hook_session and current_session != hook_session:
        return 0

    if phase in {"done", "cancelled"}:
        play_sound()
        state_file.unlink(missing_ok=True)
        return 0

    if gate:
        play_sound()
        return 0

    try:
        iteration = int(state.get("iteration", 0))
    except Exception:
        iteration = 0
        state["iteration"] = 0

    try:
        max_iterations = int(state.get("max_iterations", 30))
    except Exception:
        max_iterations = 30
        state["max_iterations"] = 30

    if max_iterations > 0 and iteration >= max_iterations:
        body = append_changelog(body, f"达到最大迭代次数 {max_iterations}，工作流被自动取消")
        state["phase"] = "cancelled"
        state["updated_at"] = now_iso()
        write_state(state_file, state, body)
        play_sound()
        state_file.unlink(missing_ok=True)
        return 0

    next_iteration = iteration + 1
    state["iteration"] = next_iteration
    state["updated_at"] = now_iso()
    write_state(state_file, state, body)

    reason = build_phase_prompt(state_file, phase, next_iteration)
    emit_block(reason, f"autopilot iteration {next_iteration} | phase: {phase}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
