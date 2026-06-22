# Ghostty Claude Title Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 每次在 Claude Code 提交 prompt 时，后台用 haiku 概括当前对话主题，把 `目录名: 主题` 写进当前 Ghostty tab 标题。

**Architecture:** 一个全局 `UserPromptSubmit` hook（`bin/ghostty-title-hook.sh`）解析真实 tty 设备并把活儿丢给已脱离的后台 worker（`bin/ghostty-title-worker.sh`），worker 调 `claude -p --model haiku` 算标题、用 OSC 2 写设备文件。纯逻辑（抽 transcript、清洗标题、解析 tty）抽到 `lib/ghostty_title_lib.sh` 便于单测。

**Tech Stack:** bash、jq、`claude` CLI、Ghostty（OSC 2 标题序列）。

## Global Constraints

- 脚本与注释一律英文且极简；跟用户对话用中文。
- Commit 格式 `<type>: <description>`，type ∈ `feat|fix|refactor|docs|style|test|chore|perf`，message 全英文。
- 运行期外部依赖仅 `jq` + `claude`；不引入其他依赖。
- 递归守卫：任何会被全局 hook 再次触发的 `claude` 调用都必须先被 `GHOSTTY_TITLE_HOOK` 环境变量短路。
- 失败即静默：haiku 失败/空结果/写 tty 失败时不写半成品标题，保留原样。
- 标题主题为中文、最多 6 字、无标点；`目录名: 主题` 拼接。

---

### Task 1: 纯逻辑库 `lib/ghostty_title_lib.sh`

**Files:**
- Create: `lib/ghostty_title_lib.sh`
- Create: `tests/fixtures/transcript.jsonl`
- Test: `tests/lib_test.sh`

**Interfaces:**
- Produces:
  - `gt_extract_recent_user_messages <transcript_path> <count>` → stdout 打印末尾 `count` 条 user 文本，每条一行；文件不存在则无输出。
  - `gt_sanitize_title <raw>` → stdout 打印清洗后的标题（换行/连续空格折叠成单空格、去首尾空白、截断到 40 字符）。
  - `gt_resolve_tty [tty_name]` → stdout 打印设备路径；空/`?`/`??` → `/dev/tty`，`ttysNNN` → `/dev/ttysNNN`，已是 `/dev/*` 原样返回。

- [ ] **Step 1: 写测试 fixture**

Create `tests/fixtures/transcript.jsonl`（每行一条 JSONL 记录，含 user/assistant 混合，user 既有 string content 也有 array content）：

```jsonl
{"type":"user","message":{"role":"user","content":"第一条 帮我看登录"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"好的"}]}}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"第二条 改下加密"}]}}
{"type":"user","message":{"role":"user","content":"第三条 跑测试"}}
{"type":"user","message":{"role":"user","content":"第四条 提交代码"}}
```

- [ ] **Step 2: 写失败测试**

Create `tests/lib_test.sh`:

```bash
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
```

- [ ] **Step 3: 跑测试确认失败**

Run: `bash tests/lib_test.sh`
Expected: FAIL —— `gt_extract_recent_user_messages: command not found`（lib 还没写）。

- [ ] **Step 4: 写实现**

Create `lib/ghostty_title_lib.sh`:

```bash
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
```

- [ ] **Step 5: 跑测试确认通过**

Run: `bash tests/lib_test.sh`
Expected: 所有行 `ok`，退出码 0。

- [ ] **Step 6: Commit**

```bash
git add lib/ghostty_title_lib.sh tests/lib_test.sh tests/fixtures/transcript.jsonl
git commit -m "feat: add pure helpers for transcript extraction and title sanitize"
```

---

### Task 2: 后台 worker `bin/ghostty-title-worker.sh`

**Files:**
- Create: `bin/ghostty-title-worker.sh`
- Test: `tests/worker_test.sh`

**Interfaces:**
- Consumes: `gt_extract_recent_user_messages`, `gt_sanitize_title`（Task 1）。
- Produces: 可执行 worker，签名 `ghostty-title-worker.sh <ttydev>`，stdin 收 hook JSON；把 `\033]2;<dir>: <topic>\007` 写到 `<ttydev>`。通过环境变量 `GT_CLAUDE_BIN`（默认 `claude`）可注入假命令供测试。

- [ ] **Step 1: 写失败测试**

Create `tests/worker_test.sh`（用假 `claude` 输出固定主题，把 ttydev 指向一个临时文件，断言写入的字节序列正确；并验证 `claude` 失败时不写文件）：

```bash
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tests/worker_test.sh`
Expected: FAIL —— worker 不存在 / 无输出。

- [ ] **Step 3: 写实现**

Create `bin/ghostty-title-worker.sh`:

```bash
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
```

- [ ] **Step 4: 跑测试确认通过**

Run: `bash tests/worker_test.sh`
Expected: 两行 `ok`，退出码 0。

- [ ] **Step 5: Commit**

```bash
chmod +x bin/ghostty-title-worker.sh
git add bin/ghostty-title-worker.sh tests/worker_test.sh
git commit -m "feat: add background worker that writes OSC title via haiku"
```

---

### Task 3: hook 入口 + 递归守卫 `bin/ghostty-title-hook.sh`

**Files:**
- Create: `bin/ghostty-title-hook.sh`
- Test: `tests/hook_test.sh`

**Interfaces:**
- Consumes: `gt_resolve_tty`（Task 1）、worker（Task 2）。
- Produces: 可执行 hook 入口，stdin 收 hook JSON；`GHOSTTY_TITLE_HOOK` 非空时立即 `exit 0` 不做任何事；否则解析 tty 并带 `GHOSTTY_TITLE_HOOK=1` 后台启动 worker，立即返回。

- [ ] **Step 1: 写失败测试**

Create `tests/hook_test.sh`（核心断言递归守卫：守卫置位时 hook 不得启动 worker。用 `GT_WORKER_BIN` 注入一个会写 marker 的假 worker）：

```bash
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tests/hook_test.sh`
Expected: FAIL —— hook 不存在。

- [ ] **Step 3: 写实现**

Create `bin/ghostty-title-hook.sh`:

```bash
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
```

- [ ] **Step 4: 跑测试确认通过**

Run: `bash tests/hook_test.sh`
Expected: 两行 `ok`，退出码 0。

- [ ] **Step 5: Commit**

```bash
chmod +x bin/ghostty-title-hook.sh
git add bin/ghostty-title-hook.sh tests/hook_test.sh
git commit -m "feat: add hook entry with recursion guard and tty resolution"
```

---

### Task 4: 安装脚本 `install.sh`

**Files:**
- Create: `install.sh`
- Test: `tests/install_test.sh`

**Interfaces:**
- Produces: `install.sh`，幂等地把 hook 命令注册进 `${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}` 的 `.hooks.UserPromptSubmit`；缺 `jq`/`claude` 时报错。`CLAUDE_SETTINGS` 环境变量可覆盖目标文件（供测试）。

- [ ] **Step 1: 写失败测试**

Create `tests/install_test.sh`（指向临时 settings，断言注册一次、再跑不重复）：

```bash
#!/usr/bin/env bash
set -u
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
install="$DIR/../install.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0
assert_eq() { if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1";
  else printf 'FAIL - %s\n  exp:[%s]\n  act:[%s]\n' "$1" "$2" "$3"; fail=1; fi; }

export CLAUDE_SETTINGS="$tmp/settings.json"
hookpath="$(cd "$DIR/.." && pwd)/bin/ghostty-title-hook.sh"

bash "$install" >/dev/null
n1=$(jq --arg c "$hookpath" '[.hooks.UserPromptSubmit[]?.hooks[]? | select(.command==$c)] | length' "$CLAUDE_SETTINGS")
assert_eq "registered once" "1" "$n1"

bash "$install" >/dev/null
n2=$(jq --arg c "$hookpath" '[.hooks.UserPromptSubmit[]?.hooks[]? | select(.command==$c)] | length' "$CLAUDE_SETTINGS")
assert_eq "idempotent (still once)" "1" "$n2"

exit $fail
```

- [ ] **Step 2: 跑测试确认失败**

Run: `bash tests/install_test.sh`
Expected: FAIL —— install.sh 不存在。

- [ ] **Step 3: 写实现**

Create `install.sh`:

```bash
#!/usr/bin/env bash
# Register the UserPromptSubmit hook in Claude Code settings (idempotent).
set -eu
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
settings="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"

command -v jq >/dev/null     || { echo "error: jq not found; install jq first" >&2; exit 1; }
command -v claude >/dev/null || echo "warning: claude CLI not on PATH; hook will no-op until it is" >&2

chmod +x "$REPO/bin/ghostty-title-hook.sh" "$REPO/bin/ghostty-title-worker.sh"
hookcmd="$REPO/bin/ghostty-title-hook.sh"

mkdir -p "$(dirname "$settings")"
[ -f "$settings" ] || echo '{}' > "$settings"

tmp=$(mktemp)
jq --arg cmd "$hookcmd" '
  .hooks //= {} |
  .hooks.UserPromptSubmit //= [] |
  if any(.hooks.UserPromptSubmit[]?.hooks[]?; .command==$cmd)
  then .
  else .hooks.UserPromptSubmit += [{"hooks":[{"type":"command","command":$cmd}]}]
  end
' "$settings" > "$tmp" && mv "$tmp" "$settings"

echo "installed: UserPromptSubmit -> $hookcmd"
echo "settings:  $settings"
```

- [ ] **Step 4: 跑测试确认通过**

Run: `bash tests/install_test.sh`
Expected: 两行 `ok`，退出码 0。

- [ ] **Step 5: Commit**

```bash
chmod +x install.sh
git add install.sh tests/install_test.sh
git commit -m "feat: add idempotent installer for the UserPromptSubmit hook"
```

---

### Task 5: 测试入口、README 与手动验收

**Files:**
- Create: `tests/run.sh`
- Modify: `README.md`

**Interfaces:**
- Produces: `tests/run.sh` 跑全部 `*_test.sh` 并在任一失败时非零退出；README 写清安装/卸载/工作方式。

- [ ] **Step 1: 写 `tests/run.sh`**

```bash
#!/usr/bin/env bash
# Run every *_test.sh under tests/. Non-zero exit if any fails.
set -u
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
rc=0
for t in "$DIR"/*_test.sh; do
  echo "== $(basename "$t") =="
  bash "$t" || rc=1
done
exit $rc
```

- [ ] **Step 2: 跑全套测试**

Run: `bash tests/run.sh`
Expected: 四个 test 文件全部 `ok`，退出码 0。

- [ ] **Step 3: 写 README**

Overwrite `README.md`:

```markdown
# ghostty-claude-title

每次在 Claude Code 提交 prompt 时，后台用 haiku 概括当前对话主题，把
`目录名: 主题` 写进当前 Ghostty tab 的标题。多窗口同时 coding 时一眼分清
哪个窗口在干嘛。

## 依赖
- `jq`、`claude` CLI、Ghostty。

## 安装
```sh
./install.sh
```
把 `UserPromptSubmit` hook 注册进 `~/.claude/settings.json`（幂等）。
新开的 Claude Code 会话即生效。

## 卸载
编辑 `~/.claude/settings.json`，删掉 `.hooks.UserPromptSubmit` 里
command 指向本仓库 `bin/ghostty-title-hook.sh` 的那一条。

## 工作方式
`UserPromptSubmit` → `bin/ghostty-title-hook.sh`（解析真实 tty、后台启动
worker、秒退）→ `bin/ghostty-title-worker.sh`（读最近 3 条 user 消息 +
当前 prompt，调 `claude -p --model haiku` 出主题，OSC 2 写 tab 标题）。
递归由 `GHOSTTY_TITLE_HOOK` 环境变量守卫。

## 测试
```sh
bash tests/run.sh
```

设计文档见 `docs/superpowers/specs/` 与 `docs/superpowers/plans/`。
```

- [ ] **Step 4: 手动真机验收**

1. `./install.sh`。
2. 在 Ghostty 开两个 tab，分别 `cd` 到不同目录各跑 `claude`。
3. 在 tab A 发「帮我看登录加密」，在 tab B 发「写周报」。
4. 等 2~4s，肉眼确认：tab A 标题形如 `<dirA>: 登录加密`，tab B 形如
   `<dirB>: 周报`，两个互不串台。
5. 在同一会话换话题再发一条，确认标题随之更新。

- [ ] **Step 5: Commit**

```bash
chmod +x tests/run.sh
git add tests/run.sh README.md
git commit -m "chore: add test runner and usage README"
```

---

## Self-Review

**Spec coverage:** §3 数据流 → Task 1/2/3；§4.1 hook → Task 3；§4.2 worker →
Task 2；§4.3 install → Task 4；§5 递归守卫 → Task 3（含专门测试）；§6
tty 解析 → Task 1 `gt_resolve_tty` + Task 3 用它；§7 失败即静默 → Task 2
（claude 失败不写）；§8 测试策略 → Task 1/2/3/4 各测 + Task 5 手动验收。无缺口。

**Placeholder scan:** 无 TBD/TODO，所有 code step 给了完整代码。

**Type consistency:** `gt_extract_recent_user_messages` / `gt_sanitize_title` /
`gt_resolve_tty` 三个函数名在 Task 1 定义、Task 2/3 引用一致；worker 签名
`<ttydev>` 在 Task 2 定义、Task 3 启动时一致；`GHOSTTY_TITLE_HOOK` /
`GT_CLAUDE_BIN` / `GT_WORKER_BIN` / `CLAUDE_SETTINGS` 注入变量名前后一致。
