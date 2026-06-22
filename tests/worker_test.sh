#!/usr/bin/env bash
set -u
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
worker="$DIR/../bin/ghostty-title-worker.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
assert_eq() { if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1";
  else printf 'FAIL - %s\n  exp:[%s]\n  act:[%s]\n' "$1" "$2" "$3"; fail=1; fi; }

# fake claude that echoes a fixed topic
cat > "$tmp/claude" <<'EOF'
#!/usr/bin/env bash
echo "联系人 cutover"
EOF
chmod +x "$tmp/claude"

input=$(jq -nc --arg cwd "/Users/ccz/Desktop/test/mxcore-proposal" \
  --arg p "改下加密" --arg tp "$DIR/fixtures/transcript.jsonl" \
  '{cwd:$cwd, prompt:$p, transcript_path:$tp}')

ttyfile="$tmp/ttyout"; : > "$ttyfile"
GT_CLAUDE_BIN="$tmp/claude" bash "$worker" "$ttyfile" <<<"$input"
got=$(cat "$ttyfile")
want=$'\033]2;mxcore-proposal: 联系人 cutover\007'
assert_eq "writes OSC title to ttydev" "$want" "$got"

# claude fails -> nothing written
cat > "$tmp/claude_fail" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$tmp/claude_fail"
ttyfile2="$tmp/ttyout2"; : > "$ttyfile2"
GT_CLAUDE_BIN="$tmp/claude_fail" bash "$worker" "$ttyfile2" <<<"$input"
assert_eq "no write when claude fails" "" "$(cat "$ttyfile2")"

exit $fail
