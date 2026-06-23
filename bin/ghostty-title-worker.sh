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

session=$(printf '%s' "$input" | jq -r '.session_id // ""')
dir=$(basename "$cwd")
write_title() { printf '\033]2;%s\007' "$1" > "$ttydev" 2>/dev/null || true; }

# Per-session state: a stable cached title + a prompt counter to throttle calls.
key="${session:-$(basename "$ttydev")}"
statedir=$(gt_state_dir)
mkdir -p "$statedir" 2>/dev/null || true
countf="$statedir/$key.count"
titlef="$statedir/$key.title"
prev=$(cat "$titlef" 2>/dev/null || true)
count=$(cat "$countf" 2>/dev/null || echo 0)
count=$((count + 1))
printf '%s' "$count" > "$countf" 2>/dev/null || true

# Throttle: nail down the title in the first ${GT_WARMUP} prompts, then only
# re-check every ${GT_RECOMPUTE_EVERY} prompts. On skipped turns just rewrite the
# cached title (a tab switch can clear it) so the window stays labeled — no haiku.
warmup="${GT_WARMUP:-2}"
every="${GT_RECOMPUTE_EVERY:-5}"
if [ "$count" -gt "$warmup" ] && [ $((count % every)) -ne 0 ]; then
  [ -n "$prev" ] && write_title "$dir: $prev"
  exit 0
fi

first=$(gt_extract_first_user_message "$transcript")
recent=$(gt_extract_recent_user_messages "$transcript" 3)
ctx=$(printf '首要任务: %s\n最近对话: %s\n当前消息: %s' "$first" "$recent" "$prompt")

# Bias toward stability: feed the current title back and only switch when the
# task genuinely changed, so the label reflects "what this window is for".
if [ -n "$prev" ]; then
  sys="你是终端标题生成器。当前标题是「$prev」。判断下面对话是否仍属于这个主题：若仍是同一任务，原样只输出「$prev」；只有任务明显切换时，才输出最多 6 个中文字的新主题。只输出标题本身，不要标点、不要解释、不要任何多余文字、不要使用任何工具。"
else
  sys='你是终端标题生成器。只输出最多 6 个中文字概括用户整段对话的核心任务，不要标点、不要解释、不要任何多余文字、不要使用任何工具。'
fi

# `claude -p` is an agentic harness: with tools + project CLAUDE.md it will
# explore the repo and ramble for minutes. Force a single stateless completion:
# no settings (also stops this global hook re-firing), no MCP, no tools.
topic=$("$claude_bin" -p --model haiku \
  --setting-sources '' --strict-mcp-config \
  --allowedTools '' \
  --disallowedTools 'Bash,Read,Edit,Write,Glob,Grep,WebFetch,WebSearch,Task,TodoWrite' \
  --system-prompt "$sys" \
  "$ctx" 2>/dev/null) || { [ -n "$prev" ] && write_title "$dir: $prev"; exit 0; }
topic=$(gt_sanitize_title "$topic")
# On empty output keep the previous title rather than blanking the tab.
[ -n "$topic" ] || { [ -n "$prev" ] && write_title "$dir: $prev"; exit 0; }

printf '%s' "$topic" > "$titlef" 2>/dev/null || true
write_title "$dir: $topic"
