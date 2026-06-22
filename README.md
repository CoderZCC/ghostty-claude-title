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
