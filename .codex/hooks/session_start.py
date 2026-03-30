#!/usr/bin/env python3

import json
import os
import sys


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}

    repo_root = payload.get("cwd") or os.getcwd()

    message = "\n".join(
        [
            "This repository ships a repo-local Codex compatibility layer.",
            "Use .codex/AGENTS.md plus the project fallback .agents.md as the Codex instruction sources.",
            "Prefer repo skills $autopilot-codex, $autopilot-commit-codex, and $autopilot-doctor-codex for Codex-native workflows.",
            "Keep Codex runtime state under .codex/ and treat .claude/knowledge/ as read-only shared knowledge.",
            "Do not recreate the historical plugin-sync or bridge/watch-based Codex integration patterns.",
            f"Session cwd: {repo_root}",
        ]
    )

    print(message)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
