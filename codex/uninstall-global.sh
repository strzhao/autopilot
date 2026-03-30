#!/bin/sh
set -eu

SHIM_TARGET="$HOME/.config/codex/auto-shim.zsh"
ZSHRC="$HOME/.zshrc"
START_MARKER="# >>> string-claude-code-plugin codex shim >>>"
END_MARKER="# <<< string-claude-code-plugin codex shim <<<"

rm -f "$SHIM_TARGET"

if [ -f "$ZSHRC" ] && grep -Fq "$START_MARKER" "$ZSHRC"; then
  tmp_file=$(mktemp)
  awk -v start="$START_MARKER" -v end="$END_MARKER" '
    $0 == start { skip = 1; next }
    $0 == end { skip = 0; next }
    skip != 1 { print }
  ' "$ZSHRC" > "$tmp_file"
  mv "$tmp_file" "$ZSHRC"
fi

echo "Uninstalled Codex auto shim."
echo "Reload shell with:"
echo "  exec zsh"
