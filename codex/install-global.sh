#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SHIM_SOURCE="$REPO_ROOT/codex/shim.zsh"
SHIM_TARGET="$HOME/.config/codex/auto-shim.zsh"
ZSHRC="$HOME/.zshrc"
START_MARKER="# >>> string-claude-code-plugin codex shim >>>"
END_MARKER="# <<< string-claude-code-plugin codex shim <<<"

mkdir -p "$HOME/.config/codex"
ln -sfn "$SHIM_SOURCE" "$SHIM_TARGET"

if [ ! -f "$ZSHRC" ]; then
  : > "$ZSHRC"
fi

if ! grep -Fq "$START_MARKER" "$ZSHRC"; then
  cat >> "$ZSHRC" <<EOF

$START_MARKER
[[ -f "\$HOME/.config/codex/auto-shim.zsh" ]] && source "\$HOME/.config/codex/auto-shim.zsh"
$END_MARKER
EOF
fi

echo "Installed Codex auto shim."
echo "Usage stays the same:"
echo "  cd /path/to/repo"
echo "  codex"
echo
echo "Reload shell with:"
echo "  exec zsh"
