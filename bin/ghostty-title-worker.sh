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
sys='你是终端标题生成器。只输出最多 6 个中文字概括用户对话主题，不要标点、不要解释、不要任何多余文字、不要使用任何工具。'

# `claude -p` is an agentic harness: with tools + project CLAUDE.md it will
# explore the repo and ramble for minutes. Force a single stateless completion:
# no settings (also stops this global hook re-firing), no MCP, no tools.
topic=$("$claude_bin" -p --model haiku \
  --setting-sources '' --strict-mcp-config \
  --allowedTools '' \
  --disallowedTools 'Bash,Read,Edit,Write,Glob,Grep,WebFetch,WebSearch,Task,TodoWrite' \
  --system-prompt "$sys" \
  "$ctx" 2>/dev/null) || exit 0
topic=$(gt_sanitize_title "$topic")
[ -n "$topic" ] || exit 0

dir=$(basename "$cwd")
printf '\033]2;%s\007' "$dir: $topic" > "$ttydev" 2>/dev/null || true
