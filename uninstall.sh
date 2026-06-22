#!/usr/bin/env bash
# Remove the ghostty-claude-title UserPromptSubmit hook from Claude Code
# settings. Other hooks are left untouched. Idempotent.
set -eu
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
settings="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
hookcmd="$REPO/bin/ghostty-title-hook.sh"

command -v jq >/dev/null || { echo "error: jq not found" >&2; exit 1; }
[ -f "$settings" ] || { echo "nothing to do: $settings not found"; exit 0; }

tmp=$(mktemp)
jq --arg cmd "$hookcmd" '
  if .hooks.UserPromptSubmit
  then .hooks.UserPromptSubmit |= map(select(.hooks | any(.command==$cmd) | not))
  else . end
' "$settings" > "$tmp" && mv "$tmp" "$settings"

echo "uninstalled: removed $hookcmd from $settings"
