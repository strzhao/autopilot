# string-claude-code-plugin Codex auto shim
#
# Install once globally, then continue using plain `codex`.
# When the current working directory is inside a git repo that contains
# repo-local Codex markers, this shim injects the needed overrides.

codex() {
  emulate -L zsh
  setopt local_options no_aliases

  if [[ -n "${CODEX_SHIM_DISABLE:-}" ]]; then
    command codex "$@"
    return $?
  fi

  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    command codex "$@"
    return $?
  }

  local extra=()

  if [[ -f "$repo_root/.codex/hooks.json" ]]; then
    extra+=(-c 'features.codex_hooks=true')
  fi

  if [[ -f "$repo_root/.agents.md" ]]; then
    extra+=(-c "model_instructions_file=\"$repo_root/.agents.md\"")
  fi

  command codex "${extra[@]}" "$@"
}
