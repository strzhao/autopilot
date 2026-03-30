#!/usr/bin/env python3

import json
import sys


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0

    prompt = str(payload.get("prompt") or "")
    normalized = prompt.lower()
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

    if notes:
        print("\n".join(notes))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
