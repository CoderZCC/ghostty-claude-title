#!/usr/bin/env bash
# Behavior tests for the pure helpers. No external side effects.
set -u
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/../lib/ghostty_title_lib.sh"

fail=0
assert_eq() { # $1 desc, $2 expected, $3 actual
  if [ "$2" = "$3" ]; then
    printf 'ok   - %s\n' "$1"
  else
    printf 'FAIL - %s\n      expected: [%s]\n      actual:   [%s]\n' "$1" "$2" "$3"
    fail=1
  fi
}

# extract: last 3 user messages, array-content flattened to text
got=$(gt_extract_recent_user_messages "$DIR/fixtures/transcript.jsonl" 3)
want=$'第二条 改下加密\n第三条 跑测试\n第四条 提交代码'
assert_eq "extract last 3 user texts" "$want" "$got"

# extract: missing file -> empty
got=$(gt_extract_recent_user_messages "$DIR/fixtures/nope.jsonl" 3)
assert_eq "extract missing file empty" "" "$got"

# extract first: the anchor task, stays stable while later messages drift
got=$(gt_extract_first_user_message "$DIR/fixtures/transcript.jsonl")
assert_eq "extract first user text" "第一条 帮我看登录" "$got"

# state dir: GT_STATE_DIR overrides
got=$(GT_STATE_DIR=/tmp/gt-x gt_state_dir)
assert_eq "state dir override" "/tmp/gt-x" "$got"

# sanitize: collapse newlines/spaces, trim
got=$(gt_sanitize_title $'  联系人\n  cutover  ')
assert_eq "sanitize collapse+trim" "联系人 cutover" "$got"

# sanitize: truncate to 40 chars
long=$(printf 'a%.0s' {1..60})
got=$(gt_sanitize_title "$long")
assert_eq "sanitize truncate len" "40" "$(printf '%s' "$got" | wc -c | tr -d ' ')"

# resolve_tty
assert_eq "resolve plain name" "/dev/ttys003" "$(gt_resolve_tty ttys003)"
assert_eq "resolve unknown ??"  "/dev/tty"     "$(gt_resolve_tty '??')"
assert_eq "resolve empty"       "/dev/tty"     "$(gt_resolve_tty '')"
assert_eq "resolve already dev" "/dev/ttys9"   "$(gt_resolve_tty /dev/ttys9)"

exit $fail
