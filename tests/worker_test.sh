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

# Isolate per-session state so tests never touch the real ~/.cache.
export GT_STATE_DIR="$tmp/state"

ttyfile="$tmp/ttyout"; : > "$ttyfile"
GT_CLAUDE_BIN="$tmp/claude" bash "$worker" "$ttyfile" <<<"$input"
got=$(cat "$ttyfile")
want=$'\033]2;mxcore-proposal: 联系人 cutover\007'
assert_eq "writes OSC title to ttydev" "$want" "$got"

# claude fails on a fresh session -> nothing written
cat > "$tmp/claude_fail" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$tmp/claude_fail"
ttyfile2="$tmp/ttyout2"; : > "$ttyfile2"
GT_CLAUDE_BIN="$tmp/claude_fail" bash "$worker" "$ttyfile2" <<<"$input"
assert_eq "no write when claude fails" "" "$(cat "$ttyfile2")"

# Throttled turn: cached title is rewritten WITHOUT invoking claude.
sess=$(jq -nc --arg cwd "/Users/ccz/Desktop/test/mxcore-proposal" \
  --arg p "继续" --arg tp "$DIR/fixtures/transcript.jsonl" --arg s "sess1" \
  '{cwd:$cwd, prompt:$p, transcript_path:$tp, session_id:$s}')
mkdir -p "$GT_STATE_DIR"
printf '登录加密' > "$GT_STATE_DIR/sess1.title"
printf '3' > "$GT_STATE_DIR/sess1.count"   # next=4, >warmup, 4%5!=0 -> skip
cat > "$tmp/claude_marker" <<EOF
#!/usr/bin/env bash
touch "$tmp/called"
echo 新主题
EOF
chmod +x "$tmp/claude_marker"
ttyfile3="$tmp/ttyout3"; : > "$ttyfile3"
GT_CLAUDE_BIN="$tmp/claude_marker" bash "$worker" "$ttyfile3" <<<"$sess"
assert_eq "throttled turn reuses cached title" \
  $'\033]2;mxcore-proposal: 登录加密\007' "$(cat "$ttyfile3")"
assert_eq "throttled turn skips claude call" "no" \
  "$([ -e "$tmp/called" ] && echo yes || echo no)"

exit $fail
