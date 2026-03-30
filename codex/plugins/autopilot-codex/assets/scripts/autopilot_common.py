#!/usr/bin/env python3

from __future__ import annotations

import json
import re
import subprocess
from collections import OrderedDict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


FRONTMATTER_KEYS = [
    "runtime",
    "state_version",
    "phase",
    "gate",
    "iteration",
    "max_iterations",
    "retry_count",
    "max_retries",
    "session_id",
    "qa_scope",
    "started_at",
    "updated_at",
    "goal",
]

SECTION_TITLES = [
    "目标",
    "设计文档",
    "实现计划",
    "验证方案",
    "红队验收测试",
    "QA 报告",
    "用户反馈",
    "变更日志",
]

SECTION_RE = re.compile(r"(?ms)^## (?P<title>[^\n]+)\n(?P<body>.*?)(?=^## |\Z)")


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def resolve_project_root(cwd: str | None = None) -> Path:
    target = Path(cwd or ".").resolve()
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=target,
            check=True,
            capture_output=True,
            text=True,
        )
    except Exception:
        return target
    return Path(result.stdout.strip() or target)


def state_path_for(cwd: str | None = None) -> Path:
    return resolve_project_root(cwd) / ".codex" / "autopilot.local.md"


def parse_scalar(raw: str) -> Any:
    value = raw.strip()
    if value == "":
        return ""
    if value.startswith('"') and value.endswith('"'):
        try:
            return json.loads(value)
        except json.JSONDecodeError:
            return value[1:-1]
    if re.fullmatch(r"-?\d+", value):
        return int(value)
    if value in {"true", "false"}:
        return value == "true"
    return value


def format_scalar(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    return json.dumps("" if value is None else str(value), ensure_ascii=False)


def parse_frontmatter(markdown: str) -> tuple[OrderedDict[str, Any], str]:
    if not markdown.startswith("---\n"):
        raise ValueError("missing frontmatter")

    parts = markdown.split("---\n", 2)
    if len(parts) < 3:
        raise ValueError("unterminated frontmatter")

    _, raw_frontmatter, body = parts
    state: OrderedDict[str, Any] = OrderedDict()
    for line in raw_frontmatter.splitlines():
        if not line.strip() or ":" not in line:
            continue
        key, raw_value = line.split(":", 1)
        state[key.strip()] = parse_scalar(raw_value)

    return state, body.lstrip("\n")


def parse_template(template: str) -> tuple[OrderedDict[str, Any], str]:
    state, body = parse_frontmatter(template)
    return ensure_default_state(state), body


def dump_markdown(state: OrderedDict[str, Any], body: str) -> str:
    lines = ["---"]
    for key in FRONTMATTER_KEYS:
        if key in state:
            lines.append(f"{key}: {format_scalar(state[key])}")
    for key, value in state.items():
        if key not in FRONTMATTER_KEYS:
            lines.append(f"{key}: {format_scalar(value)}")
    lines.append("---")
    lines.append("")
    lines.append(body.rstrip() + "\n")
    return "\n".join(lines)


def read_state(path: Path) -> tuple[OrderedDict[str, Any], str]:
    state, body = parse_frontmatter(path.read_text(encoding="utf-8"))
    return ensure_default_state(state), body


def write_state(path: Path, state: OrderedDict[str, Any], body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(dump_markdown(ensure_default_state(state), body), encoding="utf-8")


def ensure_default_state(state: OrderedDict[str, Any]) -> OrderedDict[str, Any]:
    defaults: OrderedDict[str, Any] = OrderedDict(
        [
            ("runtime", "codex"),
            ("state_version", 1),
            ("phase", "design"),
            ("gate", ""),
            ("iteration", 0),
            ("max_iterations", 30),
            ("retry_count", 0),
            ("max_retries", 3),
            ("session_id", ""),
            ("qa_scope", ""),
            ("started_at", now_iso()),
            ("updated_at", now_iso()),
            ("goal", ""),
        ]
    )
    merged = OrderedDict(defaults)
    for key, value in state.items():
        merged[key] = value
    return merged


def load_sections(body: str) -> list[tuple[str, str]]:
    sections = [(match.group("title"), match.group("body").strip("\n")) for match in SECTION_RE.finditer(body)]
    if sections:
        return sections
    return [(title, "") for title in SECTION_TITLES]


def render_sections(sections: list[tuple[str, str]]) -> str:
    rendered: list[str] = []
    for title, content in sections:
        normalized = content.rstrip()
        rendered.append(f"## {title}\n\n{normalized}\n")
    return "\n".join(rendered).rstrip() + "\n"


def update_section(body: str, title: str, content: str) -> str:
    sections = load_sections(body)
    updated = False
    next_sections: list[tuple[str, str]] = []

    for current_title, current_content in sections:
        if current_title == title:
            next_sections.append((current_title, content.strip()))
            updated = True
        else:
            next_sections.append((current_title, current_content))

    if not updated:
        next_sections.append((title, content.strip()))

    return render_sections(next_sections)


def append_to_section(body: str, title: str, entry: str) -> str:
    sections = load_sections(body)
    next_sections: list[tuple[str, str]] = []
    updated = False

    for current_title, current_content in sections:
        if current_title != title:
            next_sections.append((current_title, current_content))
            continue

        new_content = current_content.rstrip()
        if new_content:
            new_content = f"{new_content}\n{entry}"
        else:
            new_content = entry
        next_sections.append((current_title, new_content))
        updated = True

    if not updated:
        next_sections.append((title, entry))

    return render_sections(next_sections)


def append_changelog(body: str, message: str) -> str:
    return append_to_section(body, "变更日志", f"- [{now_iso()}] {message}")


def append_feedback(body: str, message: str) -> str:
    return append_to_section(body, "用户反馈", f"- [{now_iso()}] {message}")


def resolve_template_path() -> Path:
    script_dir = Path(__file__).resolve().parent
    plugin_root = script_dir.parent.parent
    return plugin_root / "skills" / "autopilot-codex" / "assets" / "autopilot-state-template.md"


def load_template(goal: str, max_iterations: int, max_retries: int, session_id: str = "") -> str:
    content = resolve_template_path().read_text(encoding="utf-8")
    timestamp = now_iso()
    replacements = {
        "<GOAL>": goal,
        "<ISO_TIMESTAMP>": timestamp,
        "<MAX_ITERATIONS>": str(max_iterations),
        "<MAX_RETRIES>": str(max_retries),
        "<SESSION_ID>": session_id,
    }
    for placeholder, value in replacements.items():
        content = content.replace(placeholder, value)
    return content
