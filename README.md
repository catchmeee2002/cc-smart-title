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
- **Main-thread distillation (v0.3+)** — The `PostToolUse` refiner maintains a cumulative summary (`summaries/<sid>.txt`) and derives the title from it. Titles stay anchored to the conversation's main thread instead of drifting with the latest topic
- **Triple-write** — Titles appear in (1) `claude --resume` list via `custom-title`, (2) status bar via `sessions-index.json`, and (3) the native TUI top-right title via `agent-name` — the same entry type Claude Code writes when you run `/rename`. Note: `agent-name` is read on session load, so a running session won't see the new title until next `--resume`; see [Known limitations](#known-limitations)
- **Zero-blocking** — Hooks exit instantly; all heavy work runs in background
- **Smart pre-filtering** — Strips slash commands, mode-switch phrases, and `<system-reminder>` blocks from the first prompt before sending to the model
- **Robust extraction** — Handles both string and array content types in transcripts
- **Graceful degradation** — Malformed JSON / empty fields / API errors leave the old summary and title untouched
- **Atomic writes** — Uses `flock` to safely update `sessions-index.json`; `tmp + mv` for summary files
- **Orphan GC** — Every 50 triggers, summary files with no matching transcript (and mtime > 7 days) are removed
- **Configurable** — Customize throttle rate, title length, summary bytes, prompts, and model via env vars
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

Two hooks work together as a two-layer system, with a shared on-disk cumulative summary for main-thread continuity:

| Layer | Hook type | When it fires | Purpose |
|-------|-----------|---------------|---------|
| L1 | `UserPromptSubmit` (`auto-title-on-first-prompt.sh`) | Once per session, on the first user prompt | Instant title + **seed** the initial summary with the cleaned first prompt |
| L2 | `PostToolUse` (`auto-rename-session.sh`) | Every N tool calls (default 10) | **Distill** the main thread: feed {old_summary + new messages} to Haiku, get JSON `{summary, title}`, persist both |

Per-session state lives in the Claude Code project directory:

```
~/.claude/projects/<slug>/
  ├── <sid>.jsonl              # Claude Code native transcript
  ├── sessions-index.json      # updated customTitle (status bar)
  └── summaries/<sid>.txt      # cumulative main-thread summary (≤800 chars)
```

L2 flow (background subprocess, zero-blocking):

```
┌──────────────┐     stdin (JSON)     ┌──────────────────────┐
│  Claude Code │ ──────────────────▶  │   hook script        │
│  Hook event  │                      │  1. Read payload     │
└──────────────┘                      │  2. Throttle + GC    │
                                      │  3. exit 0 (instant) │
                                      └──────────┬───────────┘
                                                 │ fork &
                                      ┌──────────▼───────────┐
                                      │  Background process  │
                                      │  a. Read old summary │
                                      │  b. Extract recent   │
                                      │     user messages    │
                                      │  c. Haiku (JSON):    │
                                      │     {summary, title} │
                                      │  d. Atomic write     │
                                      │     new summary      │
                                      │  e. Dual-write title:│
                                      │     → JSONL transcr. │
                                      │     → sessions-index │
                                      └──────────────────────┘
```

If Haiku fails or returns malformed JSON, the old summary and title are preserved — the UI never flickers to an empty state.

## Configuration

All settings are via environment variables (set in your shell profile):

| Variable | Default | Description |
|----------|---------|-------------|
| `ANTHROPIC_API_KEY` | *(required)* | Your Anthropic API key |
| `ANTHROPIC_BASE_URL` | `https://api.anthropic.com` | API endpoint |
| `CC_TITLE_THROTTLE` | `10` | (L2) trigger main-thread distillation every N tool calls |
| `CC_TITLE_MAX_BYTES` | `60` | Max title length in bytes (~20 Chinese chars) |
| `CC_TITLE_MODEL` | `claude-haiku-4.5` | Model for title generation (shared by both hooks) |
| `CC_SUMMARY_MAX_BYTES` | `800` | (L1+L2) max size of `summaries/<sid>.txt` |
| `CC_SUMMARY_MAX_TOKENS` | `400` | (L2) `max_tokens` for the JSON `{summary, title}` call |
| `CC_SUMMARY_SYSTEM` | *(built-in Chinese)* | (L2) system prompt for main-thread distillation |
| `CC_SUMMARY_GC_EVERY` | `50` | (L2) run orphan summary GC every N triggers (set to `0` to disable GC entirely) |
| `CC_SUMMARY_GC_DAYS` | `7` | (L2) GC deletes summaries whose `.jsonl` is missing and mtime is older than N days (uses `find -mtime +N`, i.e. ≥ N+1 full days ago) |
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
- **Terminal width matters.** The status bar renders inside `<Text wrap="truncate">` (CC source `StatusLine.tsx:314`). When the terminal window is too narrow, multi-line status bar output (line 1: model/dir/git/context, line 2: copilot/session-id/title) gets truncated — the second line simply disappears. Widen your terminal window to see all status bar content

## Known limitations

- **TUI top-right title is only refreshed on session load.** Claude Code reads `agent-name` JSONL entries when it starts up or does `claude --resume`, not while running. So for a **running session**, the top-right teal title will only appear (or update) after you quit and resume — not in real time. Workarounds we evaluated: POSIX signals (`SIGWINCH`/`SIGUSR1`/`SIGHUP`) require same-namespace process access and break across Docker/user-namespace boundaries, so they're not portable. If you need a mid-session refresh, run `/rename <new title>` manually. The `/resume` list and status-bar title do update promptly because they read from disk on demand.

- **TUI header title and status-bar title may differ during a session.** Root cause (confirmed via CC source v2.1.79): The TUI header separator (`── title ──`, rendered by `REPL.tsx:1135`) reads from CC's **in-memory cache** `Project.currentSessionTitle` (via `getCurrentSessionTitle()` in `sessionStorage.ts:2739`). The status bar `📝` reads from `sessions-index.json` (via `context-bar.sh`). Since `auto-rename-session.sh` is an external hook process, it can write to JSONL and `sessions-index.json` (disk), but **cannot update CC's in-memory cache** — only internal functions like `saveCustomTitle()` can do that. The TUI header falls through its priority chain (`sessionTitle → agentTitle → haikuTitle → 'Claude Code'`) and ends up showing CC's built-in Haiku-generated title (from `generateSessionTitle()`) instead of the auto-rename title. This inconsistency resolves on next `--resume` when `restoreSessionMetadata()` loads `customTitle` from the JSONL tail into the in-memory cache.

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
