#!/usr/bin/env bash
set -u
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
install="$DIR/../install.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
assert_eq() { if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1";
  else printf 'FAIL - %s\n  exp:[%s]\n  act:[%s]\n' "$1" "$2" "$3"; fail=1; fi; }

export CLAUDE_SETTINGS="$tmp/settings.json"
hookpath="$(cd "$DIR/.." && pwd)/bin/ghostty-title-hook.sh"

bash "$install" >/dev/null
n1=$(jq --arg c "$hookpath" '[.hooks.UserPromptSubmit[]?.hooks[]? | select(.command==$c)] | length' "$CLAUDE_SETTINGS")
assert_eq "registered once" "1" "$n1"

bash "$install" >/dev/null
n2=$(jq --arg c "$hookpath" '[.hooks.UserPromptSubmit[]?.hooks[]? | select(.command==$c)] | length' "$CLAUDE_SETTINGS")
assert_eq "idempotent (still once)" "1" "$n2"

exit $fail
