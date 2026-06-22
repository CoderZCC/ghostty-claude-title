#!/usr/bin/env bash
set -u
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook="$DIR/../bin/ghostty-title-hook.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
assert_eq() { if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1";
  else printf 'FAIL - %s\n  exp:[%s]\n  act:[%s]\n' "$1" "$2" "$3"; fail=1; fi; }

marker="$tmp/marker"
cat > "$tmp/worker" <<EOF
#!/usr/bin/env bash
echo ran > "$marker"
EOF
chmod +x "$tmp/worker"
input='{"cwd":"/x","prompt":"hi","transcript_path":""}'

# guard set -> must short-circuit, worker never runs
rm -f "$marker"
GHOSTTY_TITLE_HOOK=1 GT_WORKER_BIN="$tmp/worker" bash "$hook" <<<"$input"
assert_eq "guard short-circuits" "1" "$([ -f "$marker" ] && echo 0 || echo 1)"

# guard unset -> worker is launched (wait briefly for the detached child)
rm -f "$marker"
GT_WORKER_BIN="$tmp/worker" bash "$hook" <<<"$input"
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$marker" ] && break; sleep 0.2; done
assert_eq "no guard launches worker" "ran" "$(cat "$marker" 2>/dev/null)"

exit $fail
