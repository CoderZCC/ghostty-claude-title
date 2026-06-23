# ghostty-claude-title

> 多窗口开一堆 Ghostty 跑 Claude Code，老忘了哪个窗口在干嘛？
> 这个小工具每次你提交 prompt 时，后台用 haiku 概括当前对话主题，把
> **`目录名: 主题`** 写进当前 Ghostty tab 的标题，一眼分清每个窗口。

效果：tab 标题自动变成 `mxcore-proposal: 登录推送加密`、`blue_app: 周报` 这样。

---

## 一、前提

| 依赖 | 检查命令 | 没有怎么办 |
|---|---|---|
| Ghostty 终端 | — | 仅在 Ghostty 上验证；其他终端理论上支持 OSC 2 但未测 |
| `claude` CLI | `command -v claude` | 你既然在用 Claude Code 就有 |
| `jq` | `command -v jq` | `brew install jq` |

> 标题用的是你**自己的 Claude 订阅**调 `claude -p --model haiku`，无需额外 API key。
> 标题倾向**保持稳定**，只在任务明显切换时才换；haiku 调用经过节流（开局定题、
> 之后每几条复查一次），约 **15~20s 后台**出标题——异步，不阻塞你打字。

## 二、安装

```sh
# 1. 解压到任意目录（路径随意，install 会自适应）
tar -xzf ghostty-claude-title.tar.gz
cd ghostty-claude-title

# 2. 一键安装
./install.sh
```

`install.sh` 会把一个 `UserPromptSubmit` hook 幂等地注册进
`~/.claude/settings.json`（保留你已有的其它 hook，不覆盖）。

## 三、验证生效

1. **新开一个 Ghostty tab**（重要：当前已开的窗口不生效，hook 在会话启动时读取）。
2. `cd` 到任意项目目录，跑 `claude`。
3. 随便发一条消息，等约 15~20s。
4. 看 tab 标题是否变成 `<目录名>: <主题>`。

确认注册成功：

```sh
jq '.hooks.UserPromptSubmit' ~/.claude/settings.json
# 应能看到一条 command 指向 .../ghostty-title-hook.sh
```

## 四、卸载

```sh
./uninstall.sh
```

只删本工具那条 hook，保留你其它 hook。或手动编辑
`~/.claude/settings.json` 删掉 command 含 `ghostty-title-hook.sh` 的那条。

## 五、标题没变？排查

| 现象 | 原因 | 处理 |
|---|---|---|
| 当前窗口标题不变 | hook 只对**新开**的会话生效 | 新开 tab 再试 |
| 完全不变 | Ghostty config 里写死了 `title = ...` | 删掉那行 config |
| 短暂变了又被改回 | Ghostty shell-integration 在 Claude 退出后重置标题 | 正常，下次进 Claude 又会更新 |
| 一直不变 | `jq`/`claude` 不在 PATH | `command -v jq claude` 自查 |
| 想看后台到底报什么 | — | 临时把 `bin/ghostty-title-worker.sh` 里 `2>/dev/null` 去掉，写 tty 那行换成写日志文件调试 |

> 设计上**失败即静默**：haiku 失败/超时/空结果时不写半成品标题，保留原样。

## 六、工作原理（给好奇的人）

```
你提交 prompt
  └─ UserPromptSubmit hook: bin/ghostty-title-hook.sh
        ├─ 沿父进程链上溯解析出真实 tty（/dev/ttysNNN）
        ├─ 后台启动 worker（带 GHOSTTY_TITLE_HOOK=1 守卫递归），自己秒退
        └─ ↓ Claude 不被阻塞
     bin/ghostty-title-worker.sh
        ├─ 按 session_id 读缓存的上次标题与提交计数
        ├─ 节流：开局前 2 条定题，之后每 5 条才复查一次；跳过的轮次
        │   直接把缓存标题写回 tty（切 tab 回来也不丢），不调 haiku
        ├─ 重算时喂「首要任务(首条 prompt) + 最近对话 + 当前消息」+ 上次标题
        ├─ claude -p --model haiku（锁成无状态、无工具的纯总结器）
        │   ├─ 同一主题 → 原样沿用旧标题（不抖动）
        │   └─ 任务明显切换 → 给新的 6 字主题
        └─ OSC 2 写 tab 标题：printf '\033]2;目录: 主题\007' > /dev/ttysNNN
```

> **为什么这样设计**：早期版本每条消息都用「最近 3 条」重算，标题会跟着
> 局部话题漂移、跳来跳去，反而记不住这个窗口在干嘛。现在标题锚定在会话的
> **首要任务**上并倾向保持稳定，只在任务真正切换时才换——一眼分清窗口用途。
> 缓存落在 `~/.cache/ghostty-claude-title/`（每会话一份 `.title` + `.count`）。

两个真机踩过的坑（已修，写在 `docs/superpowers/specs/` 里）：
- `claude -p` 是带工具的 agent，裸调会探索代码跑 3 分钟——必须用
  `--setting-sources '' --strict-mcp-config --allowedTools '' --system-prompt …` 锁死。
- Claude Code 把 hook 从终端剥离（`$$` 的 tty 是 `??`），真 tty 挂在祖先
  `claude` 进程上——所以要**上溯父进程链**找 tty，不能只看自己。

## 七、自测

```sh
bash tests/run.sh   # 全绿即 OK
```

## 调参

- 标题语言/字数：改 `bin/ghostty-title-worker.sh` 里的 `sys` system prompt。
- 上下文条数：同文件 `gt_extract_recent_user_messages "$transcript" 3` 的 `3`。
- 更新频率：环境变量 `GT_WARMUP`（开局快速定题的条数，默认 2）、
  `GT_RECOMPUTE_EVERY`（之后每几条复查一次换题，默认 5）。调大 = 更稳更省。
- 触发时机：现在是每次提交（`UserPromptSubmit`）。想改成回答后触发可换成
  `Stop` hook（自行在 settings.json 调整）。
