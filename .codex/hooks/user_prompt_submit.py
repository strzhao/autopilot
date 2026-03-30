#!/usr/bin/env python3

import json
import os
import re
import subprocess
import sys


def resolve_repo_root(cwd: str) -> str:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=cwd,
            check=True,
            capture_output=True,
            text=True,
        )
        return result.stdout.strip() or cwd
    except Exception:
        return cwd


def load_active_state(cwd: str | None) -> tuple[str, str] | None:
    if not cwd:
        return None

    repo_root = resolve_repo_root(cwd)
    state_path = os.path.join(repo_root, ".codex", "autopilot.local.md")
    if not os.path.exists(state_path):
        return None

    try:
        content = open(state_path, "r", encoding="utf-8").read()
    except Exception:
        return None

    phase = re.search(r'^phase:\s*"?([^"\n]+)"?', content, re.MULTILINE)
    gate = re.search(r'^gate:\s*"?([^"\n]*)"?', content, re.MULTILINE)
    if not phase:
        return None
    return phase.group(1), gate.group(1) if gate else ""


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0

    prompt = str(payload.get("prompt") or "")
    normalized = prompt.lower()
    active_state = load_active_state(str(payload.get("cwd") or ""))
    notes = []

    if "/autopilot commit" in normalized or "autopilot commit" in normalized:
        notes.append(
            "In Codex, use the explicit repo skill `$autopilot-commit-codex` instead of Claude-style `/autopilot commit`."
        )
    elif "/autopilot doctor" in normalized or "autopilot doctor" in normalized:
        notes.append(
            "In Codex, use the explicit repo skill `$autopilot-doctor-codex` instead of Claude-style `/autopilot doctor`."
        )
    elif "/autopilot" in normalized or "autopilot" in normalized:
        notes.append(
            "In Codex, use the explicit repo skill `$autopilot-codex` for the repo's autopilot workflow."
        )

    if "plugin-sync" in normalized or "codex-sync" in normalized or "bridge" in normalized:
        notes.append(
            "Prefer the repo-local Codex layer under `.codex/AGENTS.md`, `.agents.md`, `.agents/skills`, and `.codex/hooks.json`; do not restore the old symlink-sync or custom bridge design."
        )

    if active_state:
        phase, gate = active_state
        if normalized.strip() in {"approve", "status", "cancel"} or normalized.strip().startswith("revise "):
            notes.append(
                f"An active Codex autopilot workflow is present (phase={phase}, gate={gate or 'none'}). Treat this as a control command for `$autopilot-codex`."
            )
        elif "/autopilot" in normalized or "autopilot" in normalized:
            notes.append(
                f"An active Codex autopilot workflow is present (phase={phase}, gate={gate or 'none'}). Continue it via `$autopilot-codex` instead of starting an unrelated implementation path."
            )

    if notes:
        print("\n".join(notes))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
