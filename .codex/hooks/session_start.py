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


def read_active_state(repo_root: str) -> str | None:
    state_path = os.path.join(repo_root, ".codex", "autopilot.local.md")
    try:
        with open(state_path, "r", encoding="utf-8") as handle:
            content = handle.read()
    except Exception:
        return None

    phase = re.search(r'^phase:\s*"?([^"\n]+)"?', content, re.MULTILINE)
    gate = re.search(r'^gate:\s*"?([^"\n]*)"?', content, re.MULTILINE)
    if not phase:
        return None
    return f"Active Codex autopilot: phase={phase.group(1)}, gate={gate.group(1) if gate else '' or 'none'}."


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}

    repo_root = resolve_repo_root(payload.get("cwd") or os.getcwd())

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

    active_state = read_active_state(repo_root)
    if active_state:
        message = f"{message}\n{active_state}"

    print(message)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
