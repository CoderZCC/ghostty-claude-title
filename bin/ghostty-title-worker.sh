#!/usr/bin/env bash
# Background worker: summarize the current conversation and write the Ghostty
# tab title to the given tty device. Stdin = UserPromptSubmit hook JSON.
set -u
ttydev="${1:?ttydev required}"
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$DIR/../lib/ghostty_title_lib.sh"

claude_bin="${GT_CLAUDE_BIN:-claude}"
input=$(cat)
cwd=$(printf '%s' "$input" | jq -r '.cwd // ""')
prompt=$(printf '%s' "$input" | jq -r '.prompt // ""')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // ""')

recent=$(gt_extract_recent_user_messages "$transcript" 3)
ctx=$(printf '%s\n%s' "$recent" "$prompt")
instr='用最多 6 个字概括下面对话正在做的事，只输出主题本身，不要标点、不要解释。'

topic=$("$claude_bin" -p --model haiku "$instr"$'\n\n'"$ctx" 2>/dev/null) || exit 0
topic=$(gt_sanitize_title "$topic")
[ -n "$topic" ] || exit 0

dir=$(basename "$cwd")
printf '\033]2;%s\007' "$dir: $topic" > "$ttydev" 2>/dev/null || true
