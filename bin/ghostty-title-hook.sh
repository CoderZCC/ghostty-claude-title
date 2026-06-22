#!/usr/bin/env bash
# Global UserPromptSubmit hook entry. Resolves the real tty (while still
# attached to it), then hands off to a detached background worker and returns
# immediately so Claude is never blocked. GHOSTTY_TITLE_HOOK guards against the
# nested `claude -p` the worker spawns re-triggering this same global hook.
[ -n "${GHOSTTY_TITLE_HOOK:-}" ] && exit 0
set -u
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/../lib/ghostty_title_lib.sh"

worker="${GT_WORKER_BIN:-$DIR/ghostty-title-worker.sh}"
input=$(cat)
ttydev=$(gt_resolve_tty)

GHOSTTY_TITLE_HOOK=1 nohup "$worker" "$ttydev" >/dev/null 2>&1 <<<"$input" &
exit 0
