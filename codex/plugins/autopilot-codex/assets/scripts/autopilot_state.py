#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

from autopilot_common import (
    append_changelog,
    append_feedback,
    load_template,
    now_iso,
    parse_template,
    read_state,
    state_path_for,
    update_section,
    write_state,
)


ACTIVE_PHASES = {"design", "implement", "qa", "auto-fix", "merge"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Codex autopilot runtime state manager")
    subparsers = parser.add_subparsers(dest="command", required=True)

    start = subparsers.add_parser("start", help="Start a new autopilot workflow")
    start.add_argument("--goal", required=True, help="Workflow goal")
    start.add_argument("--max-iterations", type=int, default=30)
    start.add_argument("--max-retries", type=int, default=3)

    approve = subparsers.add_parser("approve", help="Approve current gate")
    approve.add_argument("--feedback", default="")

    revise = subparsers.add_parser("revise", help="Send revise feedback")
    revise.add_argument("--feedback", required=True)

    subparsers.add_parser("status", help="Show workflow status").add_argument("--json", action="store_true")

    cancel = subparsers.add_parser("cancel", help="Cancel current workflow")
    cancel.add_argument("--reason", default="")

    return parser.parse_args()


def active_state_exists(state_file: Path) -> bool:
    if not state_file.exists():
        return False
    state, _ = read_state(state_file)
    return str(state.get("phase") or "") in ACTIVE_PHASES or str(state.get("gate") or "") != ""


def command_start(args: argparse.Namespace, state_file: Path) -> int:
    if active_state_exists(state_file):
        state, _ = read_state(state_file)
        print(f"❌ 已有活跃的 Codex autopilot（阶段: {state.get('phase', 'unknown')}）。")
        print("   使用 `$autopilot-codex status` 查看状态，或先执行 `$autopilot-codex cancel`。")
        return 0

    if state_file.exists():
        state_file.unlink()

    session_id = os.environ.get("CODEX_SESSION_ID", "")
    template = load_template(args.goal, args.max_iterations, args.max_retries, session_id)
    state, body = parse_template(template)
    body = append_changelog(body, f"启动 Codex autopilot，目标: {args.goal}")
    write_state(state_file, state, body)

    print("🔄 Codex autopilot 已启动。")
    print(f"状态文件: {state_file}")
    print("当前阶段: design")
    return 0
def command_approve(args: argparse.Namespace, state_file: Path) -> int:
    if not state_file.exists():
        print("❌ 当前没有活跃的 Codex autopilot。")
        return 0

    state, body = read_state(state_file)
    gate = str(state.get("gate") or "")
    if gate == "design-approval":
        state["phase"] = "implement"
        state["gate"] = ""
        state["updated_at"] = now_iso()
        body = append_changelog(body, f"用户批准设计，进入实现阶段{format_feedback_suffix(args.feedback)}")
        write_state(state_file, state, body)
        print("✅ 设计审批通过，流程将自动进入 implement 阶段。")
        return 0
    if gate == "review-accept":
        state["phase"] = "merge"
        state["gate"] = ""
        state["updated_at"] = now_iso()
        body = append_changelog(body, f"用户批准验收，进入合并阶段{format_feedback_suffix(args.feedback)}")
        write_state(state_file, state, body)
        print("✅ 验收审批通过，流程将自动进入 merge 阶段。")
        return 0

    print("❌ 当前不在审批门，无需 approve。")
    return 0


def command_revise(args: argparse.Namespace, state_file: Path) -> int:
    if not state_file.exists():
        print("❌ 当前没有活跃的 Codex autopilot。")
        return 0

    state, body = read_state(state_file)
    gate = str(state.get("gate") or "")
    if gate == "design-approval":
        state["phase"] = "design"
        state["gate"] = ""
        state["updated_at"] = now_iso()
        body = append_feedback(body, args.feedback)
        body = append_changelog(body, f"用户要求修改设计: {args.feedback}")
        write_state(state_file, state, body)
        print("🔄 已记录设计反馈，流程将重新进入 design 阶段。")
        return 0
    if gate == "review-accept":
        state["phase"] = "implement"
        state["gate"] = ""
        state["updated_at"] = now_iso()
        body = append_feedback(body, args.feedback)
        body = append_changelog(body, f"用户要求修改实现: {args.feedback}")
        write_state(state_file, state, body)
        print("🔄 已记录验收反馈，流程将重新进入 implement 阶段。")
        return 0

    print("❌ 当前不在审批门，无法 revise。")
    return 0


def command_status(args: argparse.Namespace, state_file: Path) -> int:
    if not state_file.exists():
        payload = {"active": False, "state_file": str(state_file)}
        if args.json:
            print(json.dumps(payload, ensure_ascii=False))
        else:
            print("📋 当前没有活跃的 Codex autopilot。")
        return 0

    state, _ = read_state(state_file)
    payload = {
        "active": str(state.get("phase") or "") in ACTIVE_PHASES or str(state.get("gate") or "") != "",
        "state_file": str(state_file),
        "goal": state.get("goal", ""),
        "phase": state.get("phase", ""),
        "gate": state.get("gate", ""),
        "iteration": state.get("iteration", 0),
        "max_iterations": state.get("max_iterations", 30),
        "retry_count": state.get("retry_count", 0),
        "max_retries": state.get("max_retries", 3),
        "updated_at": state.get("updated_at", ""),
    }
    if args.json:
        print(json.dumps(payload, ensure_ascii=False))
        return 0

    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("  Codex autopilot 状态")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print(f"目标:     {payload['goal']}")
    print(f"阶段:     {payload['phase']}")
    print(f"审批门:   {payload['gate'] or '无'}")
    print(f"迭代:     {payload['iteration']} / {payload['max_iterations']}")
    print(f"重试:     {payload['retry_count']} / {payload['max_retries']}")
    print(f"更新时间: {payload['updated_at']}")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    return 0


def command_cancel(args: argparse.Namespace, state_file: Path) -> int:
    if not state_file.exists():
        print("📋 当前没有活跃的 Codex autopilot。")
        return 0

    state, body = read_state(state_file)
    reason = args.reason or "用户手动取消"
    state["phase"] = "cancelled"
    state["gate"] = ""
    state["updated_at"] = now_iso()
    body = append_feedback(body, reason)
    body = update_section(body, "QA 报告", "已取消，等待 Stop hook 清理状态文件。")
    body = append_changelog(body, f"工作流已取消: {reason}")
    write_state(state_file, state, body)
    print("🛑 Codex autopilot 已标记为 cancelled，当前轮结束后将自动清理状态文件。")
    return 0


def format_feedback_suffix(feedback: str) -> str:
    return f"。反馈: {feedback}" if feedback else ""


def main() -> int:
    args = parse_args()
    state_file = state_path_for()

    if args.command == "start":
        return command_start(args, state_file)
    if args.command == "approve":
        return command_approve(args, state_file)
    if args.command == "revise":
        return command_revise(args, state_file)
    if args.command == "status":
        return command_status(args, state_file)
    if args.command == "cancel":
        return command_cancel(args, state_file)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
