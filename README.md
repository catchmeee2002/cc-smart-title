# cc-smart-title

> Auto-rename your [Claude Code](https://docs.anthropic.com/en/docs/claude-code) sessions with AI-generated titles.

**Before:** `claude --resume` shows cryptic session IDs

```
? Pick a session:
  aef83b21  2 hours ago    /home/user/project
  c7d02f19  5 hours ago    /home/user/project
  91ab44e0  yesterday      /home/user/project
```

**After:** Each session gets a meaningful Chinese title

```
? Pick a session:
  重构用户认证模块  2 hours ago    /home/user/project
  修复数据库连接池  5 hours ago    /home/user/project
  添加单元测试覆盖  yesterday      /home/user/project
```

---

## Features

- **Zero-blocking** — The hook exits instantly; all heavy work runs in background
- **Smart throttling** — Only triggers every N tool calls (default: 3), not on every keystroke
- **Atomic writes** — Uses `flock` to safely update `sessions-index.json`
- **Configurable** — Customize throttle rate, title length, prompt, and model via env vars
- **Idempotent install** — Run `install.sh` multiple times without duplicating hooks

## Quick Start

### 1. Clone

```bash
git clone https://github.com/catchmeee2002/cc-smart-title.git
cd cc-smart-title
```

### 2. Set your API key

```bash
# Add to ~/.bashrc or ~/.zshrc
export ANTHROPIC_API_KEY="sk-ant-..."
```

### 3. Install

```bash
bash install.sh
```

That's it! Start a Claude Code session and the title will appear after ~3 tool calls.

### Uninstall

```bash
bash uninstall.sh
```

## How It Works

```
┌──────────────┐     stdin (JSON)     ┌─────────────────────┐
│  Claude Code  │ ──────────────────▶ │  auto-rename-session │
│  PostToolUse  │                     │       (hook)         │
│    Hook       │                     │                      │
└──────────────┘                     │  1. Read session_id   │
                                      │  2. Throttle check    │
                                      │  3. exit 0 (instant)  │
                                      └──────────┬────────────┘
                                                  │ fork &
                                      ┌───────────▼───────────┐
                                      │  Background Process    │
                                      │                        │
                                      │  4. Extract messages   │
                                      │     from transcript    │
                                      │  5. curl Haiku API     │
                                      │     → generate title   │
                                      │  6. flock + jq         │
                                      │     → atomic write     │
                                      │     sessions-index.json│
                                      └────────────────────────┘
```

## Configuration

All settings are via environment variables (set in your shell profile):

| Variable | Default | Description |
|----------|---------|-------------|
| `ANTHROPIC_API_KEY` | *(required)* | Your Anthropic API key |
| `ANTHROPIC_BASE_URL` | `https://api.anthropic.com` | API endpoint |
| `CC_TITLE_THROTTLE` | `3` | Trigger every N tool calls |
| `CC_TITLE_MAX_BYTES` | `33` | Max title length in bytes (~11 Chinese chars) |
| `CC_TITLE_MODEL` | `claude-haiku-4.5` | Model for title generation |
| `CC_TITLE_PROMPT` | *(built-in Chinese)* | Custom prompt for title generation |

## Optional: Status Line Integration

You can display the session title in your terminal status line. Add this snippet to your Claude Code hooks:

```bash
# In your StatusLine hook, read the customTitle from sessions-index.json
# and display it alongside other status info.
```

## Troubleshooting

### Titles not appearing?

1. **Check API key**: Make sure `ANTHROPIC_API_KEY` is set and valid
2. **Check dependencies**: Run `which jq curl flock` — all three must be available
3. **Check hook registration**: Look at `~/.claude/settings.json` for the PostToolUse entry
4. **Debug mode**: Uncomment the `LOG=` line in the script and check `/tmp/cc-rename-debug.log`
5. **Wait for 3 tool calls**: Titles only generate after every 3rd tool call (configurable)

### API errors?

- If using a proxy or custom endpoint, set `ANTHROPIC_BASE_URL`
- The script uses `curl --max-time 10` — check network connectivity

### Title not updating?

- The script uses `flock` for safe concurrent writes
- Check if `~/.claude/projects/*/sessions-index.json` exists and is valid JSON

## Dependencies

- **curl** — HTTP client for API calls
- **jq** — JSON processor for parsing and updating
- **flock** — File locking (part of `util-linux`, pre-installed on most Linux distros)

## License

MIT — see [LICENSE](LICENSE)

## Credits

Built for the [Claude Code](https://docs.anthropic.com/en/docs/claude-code) community.

---

**中文说明**：此工具为 Claude Code 会话自动生成中文标题，让 `claude --resume` 一目了然。安装只需 `bash install.sh`，卸载 `bash uninstall.sh`。
