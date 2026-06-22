#!/usr/bin/env bash
# Pure helpers for ghostty-claude-title. No side effects; safe to source in tests.

# Print the last <count> user message texts from a Claude Code transcript
# (JSONL). String content is used as-is; array content keeps only .text parts.
gt_extract_recent_user_messages() {
  local transcript="$1" count="${2:-3}"
  [ -f "$transcript" ] || return 0
  jq -r '
    select(.type=="user")
    | .message.content
    | if type=="string" then .
      elif type=="array" then (map(select(.type=="text").text) | join(" "))
      else empty end
  ' "$transcript" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -n "$count"
}

# Collapse whitespace, trim, truncate to 40 chars. Print result.
gt_sanitize_title() {
  local raw="$1"
  raw=$(printf '%s' "$raw" | tr '\n' ' ' | tr -s ' ')
  raw="${raw#"${raw%%[![:space:]]*}"}"   # ltrim
  raw="${raw%"${raw##*[![:space:]]}"}"   # rtrim
  printf '%s' "$raw" | cut -c1-40
}

# Resolve the real controlling-tty device path. Optional arg overrides the
# `ps` lookup (for tests). Falls back to /dev/tty when unknown.
gt_resolve_tty() {
  local t="${1-__UNSET__}"
  [ "$t" = "__UNSET__" ] && t=$(ps -o tty= -p $$ 2>/dev/null | tr -d ' ')
  case "$t" in
    ""|"?"|"??") printf '/dev/tty' ;;
    /dev/*)      printf '%s' "$t" ;;
    *)           printf '/dev/%s' "$t" ;;
  esac
}
