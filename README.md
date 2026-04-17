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

- **Instant first-prompt title** — A dedicated `UserPromptSubmit` hook generates a title within seconds of the user's very first message, so `/resume` and the status bar are never blank
- **Late-stage refiner** — A `PostToolUse` hook continues to refine the title as the conversation evolves (default: every 10 tool calls)
- **Dual-write** — Titles appear in both `claude --resume` list and status bar
- **Zero-blocking** — Hooks exit instantly; all heavy work runs in background
- **Smart pre-filtering** — Strips slash commands, mode-switch phrases, and `<system-reminder>` blocks from the first prompt before sending to the model
- **Robust extraction** — Handles both string and array content types in transcripts
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

That's it! Start a Claude Code session — a title appears within seconds of your first message (via `UserPromptSubmit` hook), and is automatically refined as the conversation progresses (via `PostToolUse` hook, every 10 tool calls).

### Uninstall

```bash
bash uninstall.sh
```

## How It Works

Two hooks work together as a two-layer system:

| Layer | Hook type | When it fires | Purpose |
|-------|-----------|---------------|---------|
| L1 | `UserPromptSubmit` (`auto-title-on-first-prompt.sh`) | Once per session, on the first user prompt | Instant title so `/resume` is never blank |
| L2 | `PostToolUse` (`auto-rename-session.sh`) | Every N tool calls (default 10) | Late-stage refinement based on the full conversation |

Both hooks share the same zero-blocking design:

```
┌──────────────┐     stdin (JSON)     ┌─────────────────────┐
│  Claude Code │ ──────────────────▶  │   hook script       │
│  Hook event  │                      │                     │
└──────────────┘                      │  1. Read payload    │
                                      │  2. Dedupe/throttle │
                                      │  3. exit 0 (instant)│
                                      └──────────┬──────────┘
                                                 │ fork &
                                      ┌──────────▼──────────┐
                                      │  Background process │
                                      │                     │
                                      │  4. Filter / extract│
                                      │  5. curl Haiku API  │
                                      │     → generate title│
                                      │  6. Dual-write:     │
                                      │     → JSONL transcr.│
                                      │       (for /resume) │
                                      │     → sessions-index│
                                      │       (for statusbr)│
                                      └─────────────────────┘
```

The later write wins, so the L2 refiner naturally overrides the L1 first-prompt title once the conversation has enough context.

## Configuration

All settings are via environment variables (set in your shell profile):

| Variable | Default | Description |
|----------|---------|-------------|
| `ANTHROPIC_API_KEY` | *(required)* | Your Anthropic API key |
| `ANTHROPIC_BASE_URL` | `https://api.anthropic.com` | API endpoint |
| `CC_TITLE_THROTTLE` | `10` | (L2 hook) trigger every N tool calls for refinement |
| `CC_TITLE_MAX_BYTES` | `60` | Max title length in bytes (~20 Chinese chars) |
| `CC_TITLE_MODEL` | `claude-haiku-4.5` | Model for title generation (shared by both hooks) |
| `CC_TITLE_PROMPT` | *(built-in Chinese)* | (L2) user prompt for refinement |
| `CC_TITLE_SYSTEM` | *(built-in Chinese)* | (L2) system prompt |
| `CC_FIRST_TITLE_PROMPT` | *(built-in Chinese)* | (L1) user prompt for the first-prompt title |
| `CC_FIRST_TITLE_SYSTEM` | *(built-in Chinese)* | (L1) system prompt |
| `CC_FIRST_TITLE_PROMPT_CHARS` | `500` | (L1) truncate the first prompt to this many chars before sending |

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

### Title not showing in `/resume`?

- The script appends a `custom-title` entry to the JSONL transcript file
- Check if your Claude Code version supports `custom-title` entries (v2.1+)

### API errors?

- If using a proxy or custom endpoint, set `ANTHROPIC_BASE_URL`
- The script uses `curl --max-time 10` — check network connectivity

### Title not updating?

- The script uses `flock` for safe concurrent writes
- Check if `~/.claude/projects/*/sessions-index.json` exists and is valid JSON
- The script auto-creates `sessions-index.json` if the project directory exists

### Title appears/disappears intermittently?

- Fixed in v0.2.0: now uses `dirname "$TRANSCRIPT"` to locate project directory instead of slug calculation, eliminating path mismatch issues

## Dependencies

- **curl** — HTTP client for API calls
- **jq** — JSON processor for parsing and updating
- **flock** — File locking (part of `util-linux`, pre-installed on most Linux distros)
- **perl** — Used by the first-prompt hook to strip multi-line `<system-reminder>` / `<command-name>` blocks from user input

## License

MIT — see [LICENSE](LICENSE)

## Credits

Built for the [Claude Code](https://docs.anthropic.com/en/docs/claude-code) community.

---

**中文说明**：此工具为 Claude Code 会话自动生成中文标题，让 `claude --resume` 一目了然。安装只需 `bash install.sh`，卸载 `bash uninstall.sh`。
