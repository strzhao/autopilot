#!/bin/sh
set -eu

SCRIPT_DIR=$(
  CDPATH='' cd -- "$(dirname -- "$0")" && pwd
)
REPO_ROOT=$(
  CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd
)
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

if node "$REPO_ROOT/codex/bin/string-codex-plugin" sync-home-marketplace >/dev/null 2>&1; then
  HOME_MARKETPLACE_STATUS="Synced personal marketplace at ~/.agents/plugins/marketplace.json."
else
  HOME_MARKETPLACE_STATUS="Warning: failed to sync personal marketplace automatically. Run: $REPO_ROOT/codex/bin/string-codex-plugin sync-home-marketplace"
fi

echo "Installed Codex auto shim."
echo "$HOME_MARKETPLACE_STATUS"
echo "Usage stays the same:"
echo "  cd /path/to/repo"
echo "  codex"
echo
echo "Reload shell with:"
echo "  exec zsh"
