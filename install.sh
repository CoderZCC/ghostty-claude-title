#!/usr/bin/env bash
# Register the UserPromptSubmit hook in Claude Code settings (idempotent).
set -eu
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
settings="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"

command -v jq >/dev/null     || { echo "error: jq not found; install jq first" >&2; exit 1; }
command -v claude >/dev/null || echo "warning: claude CLI not on PATH; hook will no-op until it is" >&2

chmod +x "$REPO/bin/ghostty-title-hook.sh" "$REPO/bin/ghostty-title-worker.sh"
hookcmd="$REPO/bin/ghostty-title-hook.sh"

mkdir -p "$(dirname "$settings")"
[ -f "$settings" ] || echo '{}' > "$settings"

tmp=$(mktemp)
jq --arg cmd "$hookcmd" '
  .hooks //= {} |
  .hooks.UserPromptSubmit //= [] |
  if any(.hooks.UserPromptSubmit[]?.hooks[]?; .command==$cmd)
  then .
  else .hooks.UserPromptSubmit += [{"hooks":[{"type":"command","command":$cmd}]}]
  end
' "$settings" > "$tmp" && mv "$tmp" "$settings"

echo "installed: UserPromptSubmit -> $hookcmd"
echo "settings:  $settings"
