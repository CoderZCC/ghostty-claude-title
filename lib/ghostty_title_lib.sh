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

# Print the FIRST non-empty user message text — the conversation's anchor task,
# which stays stable while later messages drift. Same content rules as above.
gt_extract_first_user_message() {
  local transcript="$1"
  [ -f "$transcript" ] || return 0
  jq -r '
    select(.type=="user")
    | .message.content
    | if type=="string" then .
      elif type=="array" then (map(select(.type=="text").text) | join(" "))
      else empty end
  ' "$transcript" 2>/dev/null | grep -v '^[[:space:]]*$' | head -n 1
}

# Per-session cache dir for the last title and prompt counter, so the worker can
# keep a stable title and throttle haiku calls. Overridable via GT_STATE_DIR.
gt_state_dir() {
  printf '%s' "${GT_STATE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/ghostty-claude-title}"
}

# Resolve the real controlling-tty device path. The hook is spawned detached
# from the terminal (its own tty is ??), so we walk the parent chain until we
# hit an ancestor that owns a real tty (the `claude`/shell process on the
# Ghostty pts). Optional arg overrides the lookup for tests. Falls back to
# /dev/tty when nothing is found.
gt_resolve_tty() {
  local t pid
  if [ "${1-__UNSET__}" != "__UNSET__" ]; then
    t="$1"
  else
    pid=$$
    t=""
    while [ -n "$pid" ] && [ "$pid" != "0" ] && [ "$pid" != "1" ]; do
      t=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
      case "$t" in
        ""|"?"|"??") ;;          # detached: keep walking up
        *) break ;;              # found a real tty
      esac
      pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    done
  fi
  case "$t" in
    ""|"?"|"??") printf '/dev/tty' ;;
    /dev/*)      printf '%s' "$t" ;;
    *)           printf '/dev/%s' "$t" ;;
  esac
}
