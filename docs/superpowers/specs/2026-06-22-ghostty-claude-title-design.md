# Ghostty 标题随 Claude 对话更新 — 设计

> 一个独立小工具，与 mxcore 仓库无关。用 Claude Code 的 `UserPromptSubmit`
> hook，每次提交 prompt 时在后台用 haiku 概括当前对话主题，把
> `目录名: 主题` 写进当前 Ghostty tab 的标题，解决「开很多窗口同时 coding、
> 认不出哪个窗口在干嘛」的问题。

## 1. 目标与非目标

**目标**
- 多个 Ghostty 窗口/tab 各跑一个 Claude Code 会话时，每个 tab 标题能反映
  「在哪个目录、在做什么」。
- 标题随话题漂移自动更新，无需手动改。
- 安装一次（全局 hook），对所有项目、所有窗口生效。

**非目标**
- 不做 Ghostty 之外终端的适配（OSC 2 是通用的，但只在 Ghostty 上验证）。
- 不做 GUI/配置面板，纯脚本 + 一行 settings.json。
- 不持久化历史标题、不做统计。

## 2. 关键决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 标题文字来源 | LLM 实时总结对话 | 最准、能随话题漂移；接受少量 token + 异步延迟 |
| 触发时机 | `UserPromptSubmit` | 你提交时更新；在后台跑，不阻塞输入 |
| 标题格式 | `目录名: 主题` | 多窗口不同仓时一眼区分项目 |
| 上下文量 | 最近 3 条 user 消息 + 当前 prompt | 短 prompt（「继续」）也能从上下文推出主题 |
| 模型调用 | `claude -p --model haiku` | 复用订阅鉴权，无需单独 API key |
| 写入方式 | OSC 2 → 显式 tty 设备路径 | 后台 worker 不依赖控制终端也能写对窗口 |
| 安装位置 | 独立仓库 `~/Desktop/test/ghostty-claude-title/` | 不污染 mxcore 仓；hook 脚本路径指向这里 |

## 3. 架构

一个全局 hook（注册在 `~/.claude/settings.json` 的 `UserPromptSubmit`）→
调用本仓库的 `bin/ghostty-title-hook.sh`。该脚本立即 fork 一个**已脱离的后台
worker** 并 `exit 0`，主 hook 不阻塞 Claude；worker 异步算标题并写终端。

```
Claude Code (UserPromptSubmit)
  │  stdin: JSON { prompt, transcript_path, cwd, ... }
  ▼
ghostty-title-hook.sh          ← 前台、有控制终端
  │  1. 递归守卫：若 $GHOSTTY_TITLE_HOOK 非空则 exit 0
  │  2. 读 stdin 全文 input
  │  3. 解析真实 tty：ps -o tty= -p $$  →  /dev/ttysNNN
  │  4. nohup 启动 worker（带 GHOSTTY_TITLE_HOOK=1），传 input + ttydev
  │  5. exit 0   ← Claude 立即继续
  ▼ (后台、已脱离)
ghostty-title-worker.sh ttydev
     1. 从 input 取 prompt / transcript_path / cwd
     2. 从 transcript JSONL 抽最近 3 条 user 文本
     3. ctx = 最近3条 + 当前 prompt
     4. topic = claude -p --model haiku "<总结指令>\n\n$ctx"
     5. dir = basename(cwd)
     6. printf '\033]2;%s\007' "$dir: $topic" > "$ttydev"
```

## 4. 组件

### 4.1 `bin/ghostty-title-hook.sh`（前台 hook 入口）
**做什么**：递归守卫 + 解析 tty + 把真正的活儿丢后台，自己秒退。
**为什么不直接干活**：`UserPromptSubmit` 会阻塞 Claude 处理你的 prompt，
haiku 调用 2~4s，同步会给每次发言加可感延迟。

要点：
- `[ -n "$GHOSTTY_TITLE_HOOK" ] && exit 0` —— 见 §5 递归。
- `input=$(cat)` 一次读完 stdin（JSON）。
- tty 解析：`t=$(ps -o tty= -p $$ | tr -d ' '); ttydev="/dev/$t"`；
  解析失败（`??`/空）则回退 `/dev/tty`（可能失败，静默忽略）。
- 后台启动：`GHOSTTY_TITLE_HOOK=1 nohup worker.sh "$ttydev" <<<"$input" >/dev/null 2>&1 &`
- `exit 0`。

### 4.2 `bin/ghostty-title-worker.sh`（后台 worker）
**做什么**：算主题并写 Ghostty 标题。
**依赖**：`jq`（解析 hook JSON 与 transcript JSONL）、`claude` CLI。

要点：
- 入参 `$1 = ttydev`；stdin = hook JSON。
- `cwd`、`prompt`、`transcript_path` 用 `jq -r` 取。
- 最近 3 条 user 消息：transcript 是 JSONL，每行一条记录，
  筛 `.type=="user"` 且 `.message.content` 为文本的，取末尾 3 条文本。
- 主题指令（中文，要求只输出 3~6 字、不带标点/解释）：
  `用最多 6 个字概括下面对话正在做的事，只输出主题本身，不要标点、不要解释。`
- 调用见下方「关键修正」——指令进 `--system-prompt`、上下文进 positional
  prompt；失败或空则不写标题，直接退出（保持原标题，不写垃圾）。

> ⚠️ **关键修正**（2026-06-22 真机实证）：`claude -p` 不是单次补全，而是
> **带工具的 agent harness**。直接 `claude -p "总结…"` 在真实项目目录里会
> 加载该项目 CLAUDE.md、动用 Bash/Read 去探索代码、画出整页流程图，**耗时
> 近 3 分钟**，真正的主题被埋在末尾。必须把它锁成无状态、无工具的纯总结器：
> ```
> claude -p --model haiku \
>   --setting-sources '' --strict-mcp-config \
>   --allowedTools '' \
>   --disallowedTools 'Bash,Read,Edit,Write,Glob,Grep,WebFetch,WebSearch,Task,TodoWrite' \
>   --system-prompt '你是终端标题生成器。只输出最多 6 个中文字…不要使用任何工具。' \
>   "$ctx"
> ```
> 实测：禁工具后输出干净的「登录推送加密」，耗时 ~17s（异步、不阻塞）。
> 附带收益：`--setting-sources ''` 让嵌套 claude 不加载任何 settings，
> **本就不会再触发本 hook**——§5 的环境变量守卫退化为第二层保险。
- 清洗：去掉换行、首尾空白，截断到合理长度（如 40 字）防止超长。
- 写入：`printf '\033]2;%s\007' "$dir: $topic" > "$ttydev"`。

### 4.3 安装：`~/.claude/settings.json`
在 `hooks.UserPromptSubmit` 增加一条 matcher，command 指向
`bin/ghostty-title-hook.sh` 的绝对路径。安装脚本 `install.sh` 负责幂等地
合并这条配置（用 jq），并 `chmod +x` 两个脚本。

## 5. 递归守卫（核心坑）

该 hook 是**全局**的，作用于所有 `claude` 调用——包括 worker 第 4 步自己
spawn 的 `claude -p`。那个 headless claude 同样会触发 `UserPromptSubmit`
→ 又调 worker → 又 spawn `claude -p` → **无限递归**。

解法（双层）：① §4.2 的 `claude -p --setting-sources ''` 让嵌套 claude
不加载 user/project/local 任何 settings，本就不会发现这个全局 hook；
② 即便如此，worker spawn 时其进程环境已带 `GHOSTTY_TITLE_HOOK=1`（由 §4.1
启动 worker 时设置并继承），任何被触发的 hook 在 §4.1 第 1 步即 `exit 0`
短路。两层任一成立即可阻断递归。

## 6. 后台存活 vs. 写对窗口（核心坑）

矛盾：worker 要在 hook 退出后继续活（否则 Claude 可能回收 hook 进程组），
倾向 `setsid`/`nohup` 脱离；但 `setsid` 会丢掉**控制终端**，`/dev/tty`
这个「魔法设备」随之失效，写不进那个 tab。

解法：在**前台 hook**（仍持有控制终端）里用 `ps -o tty= -p $$` 解析出
**真实设备路径** `/dev/ttysNNN`，作为参数传给后台 worker。worker 写的是一个
**具体设备文件**，不要求自己持有控制终端，因此 `nohup &` 脱离后仍能精确写到
原来的 Ghostty tab。

## 7. 已知边界与权衡

- **成本**：每条消息一次 haiku 调用。可接受（短、便宜、异步）。本版不做节流。
- **shell-integration 回写**：Claude 退出回到 shell 后，Ghostty 的
  shell-integration 可能把标题重置回 cwd/命令名。无妨——下次进 Claude 又会更新。
- **Ghostty `title` 配置**：若用户在 Ghostty config 里写死了 `title =`，会
  覆盖 OSC 标题。属用户配置，不在本工具处理范围。
- **依赖 `jq`**：worker 需要 `jq`；install.sh 检测缺失则报错提示安装。
- **首条 prompt**：transcript 此时可能很短/为空，退化为「仅当前 prompt」，
  仍能出主题。
- **失败即静默**：haiku 失败/超时/空结果时不写标题，保留原样，绝不写半成品。

## 8. 测试策略

纯 shell 工具，重点测**行为**而非接线：
- transcript 抽取：构造一个 JSONL fixture，断言抽出的就是末尾 3 条 user 文本。
- 标题清洗：喂含换行/超长/标点的模型输出，断言写出的字符串被正确清洗截断。
- 递归守卫：设 `GHOSTTY_TITLE_HOOK=1` 跑 hook，断言立即 exit 0、不 spawn。
- tty 解析回退：模拟 `ps` 返回 `??`，断言回退到 `/dev/tty`。
- 端到端（手动验收）：在 Ghostty 真机开两个 tab、不同目录各跑 Claude，
  发不同主题的 prompt，肉眼确认两个 tab 标题各自正确、互不串台。

OSC 写终端、`claude -p` 真实调用等副作用部分用手动验收兜底，不强求自动化。
