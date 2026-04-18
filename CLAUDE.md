# cc-smart-title — AI Collaboration Guide

> Read this before touching code. It explains *why* things are the way they are.

## What this project does

Auto-generates short Chinese titles for Claude Code sessions, visible in `claude --resume` and optional status-bar integrations.

## Architecture: two-layer hook system

| Layer | Script | Claude Code hook | Fires | Purpose |
|-------|--------|------------------|-------|---------|
| L1 | `auto-title-on-first-prompt.sh` | `UserPromptSubmit` | Once per session, on the first user prompt | Instant title (no wait for tool calls) |
| L2 | `auto-rename-session.sh` | `PostToolUse` | Every N tool calls (default 10) | Late-stage refinement based on full conversation |

Both hooks dual-write:
1. Append a `{"type":"custom-title","customTitle":"...","sessionId":"..."}` entry to the session JSONL transcript — consumed by Claude Code's `/resume` list
2. Atomically update `customTitle` in `~/.claude/projects/<project>/sessions-index.json` — consumed by external status-bar integrations

The later write wins. L2 naturally overrides L1 once the conversation has more context.

## Core design principles (do not violate)

1. **Zero-blocking hooks.** The hook body only reads stdin, does dedupe/throttle, then `exit 0`. All heavy work (filtering, curl, JSON writes) runs inside a `( ... ) &>/dev/null & disown` background subprocess.
2. **Silent failure.** If the LLM call fails for any reason (network, proxy down, auth error), the script `exit 0` silently — never surfaces errors that would interfere with the user's input flow. L2 retries on the next tool call.
3. **Never call `claude -p`.** Claude Code's CLI holds a single-instance lock; invoking it from inside a hook deadlocks. Always call the Anthropic Messages API directly via `curl`.
4. **Atomic JSON writes.** Use `flock` + `mktemp` + `jq empty` validation + `mv`. Never write the target file in-place.
5. **Locate project dir via `dirname "$TRANSCRIPT"`.** Do NOT compute slugs from `cwd` — Claude Code's slug algorithm has edge cases (`_` vs `-`) that cause mismatches. The transcript path already points to the correct project dir.

## Configuration contract

All tunables are environment variables with built-in defaults:

- Shared (both hooks): `ANTHROPIC_API_KEY`, `ANTHROPIC_BASE_URL`, `CC_TITLE_MODEL`, `CC_TITLE_MAX_BYTES`
- L2 only: `CC_TITLE_THROTTLE`, `CC_TITLE_PROMPT`, `CC_TITLE_SYSTEM`
- L1 only: `CC_FIRST_TITLE_PROMPT`, `CC_FIRST_TITLE_SYSTEM`, `CC_FIRST_TITLE_PROMPT_CHARS`

When adding a new tunable: pick a `CC_TITLE_*` or `CC_FIRST_TITLE_*` prefix, document it in `README.md#Configuration`, and keep a sensible default so zero-config installs still work.

## Pre-filter rules (L1 only)

The first user prompt is cleaned before being sent to Haiku. Order matters:

1. Pre-truncate to 2000 bytes — ReDoS safeguard before running regex
2. `perl -0777` strips multi-line XML-style blocks: `<system-reminder>`, `<command-name>`, `<session-start-hook>`, `<local-command-stdout>`, `<local-command-stderr>`
3. Same `perl` pass also strips Chinese "enter/switch mode" phrases using `\S{1,60}?` (handles up to ~20 Chinese chars in byte mode)
4. `sed` strips leading slash commands: `^[[:space:]]*/[a-z][a-z0-9:_-]*`
5. Trim whitespace, truncate to `CC_FIRST_TITLE_PROMPT_CHARS` (default 500)
6. If empty after filtering → silent exit (L2 will still run)

When adding a new filter step: test it in isolation with `printf '%s' "<input>" | perl/sed ...` before integrating.

## Change discipline

| If you touch... | You must also update... |
|-----------------|-------------------------|
| `auto-rename-session.sh` or `auto-title-on-first-prompt.sh` | `README.md` if the tunable surface or behavior changes |
| Either hook's JSON-write logic | Both — they share the dual-write pattern; keep them consistent |
| `install.sh` | `uninstall.sh` — they are inverses |
| Dependencies (adding `perl`, `flock`, etc.) | `install.sh`'s dependency check + `README.md#Dependencies` |

## Commit format

```
type(scope): [cr_id_skip] Capitalized description
```

- `type`: `feat` / `fix` / `refactor` / `chore` / `docs` / `test`
- `scope`: `core` (hook scripts), `prompt` (prompt text), `installer` (install/uninstall), `docs` (README/CLAUDE.md)
- Description: English, capitalized, imperative (e.g. "Add UserPromptSubmit hook", not "Added" or "add")

Multi-line bodies are welcome — use HEREDOC to preserve formatting.

## Verification checklist before committing

- [ ] `bash -n` on every modified shell script
- [ ] `jq empty` on any generated JSON examples
- [ ] At least one concrete filter/extract input run through the pipeline to confirm expected output
- [ ] `README.md` reflects the new behavior if user-visible

## Known edge cases (don't re-fix these)

- **Claude Code's `/resume` list** reads `custom-title` entries from the JSONL. Older CC versions (pre-v2.1) may not support this entry type.
- **TUI top-right title reads `agent-name`, not `custom-title`, and only on session load.** The two hooks write both `custom-title` (for `/resume`) and `agent-name` (for the top-right teal label) — same entries Claude Code writes when you run `/rename`. However the top-right label is **only refreshed when CC starts a session or on `--resume`**, not while running. Confirmed by empirical testing: appending `agent-name` entries mid-session does not trigger UI refresh, even after minutes. Workarounds via POSIX signals (`SIGWINCH`/`SIGUSR1`/`SIGHUP`) were rejected because they require same-namespace process access and break across Docker/user-namespace boundaries (which is a common deployment shape for CC). Net effect: new sessions get their top-right title on **next `--resume`**; interim experience relies on the status-bar integration and the `/resume` list, which both update promptly.
- **`sessions-index.json` may be missing** for some projects — the hooks auto-create it with `{"entries":[]}` when the project dir exists.
- **Active sessions may not yet be indexed** — CC sometimes delays writing index entries until session end. The hooks append a minimal entry in that case; CC's later writes preserve `customTitle`.
- **`duration_ms` resets on compaction** may confuse external watermark trackers (not this project's concern, but worth knowing if you build status-bar integrations).

## Out of scope

- Non-Chinese title generation (trivially possible by overriding `CC_TITLE_SYSTEM` / `CC_FIRST_TITLE_SYSTEM` — but the defaults stay Chinese)
- GUI installers, package-manager distribution (keep it a single-clone-and-install-sh project)
- Title history / undo (by design: later write wins, no versioning)

## Downstream consumption pattern

This repo is designed to be the **single source of truth** when consumed via symlink:

```
~/.claude/scripts/auto-rename-session.sh  ->  /path/to/cc-smart-title/auto-rename-session.sh
~/.claude/scripts/auto-title-on-first-prompt.sh  ->  /path/to/cc-smart-title/auto-title-on-first-prompt.sh
```

When a downstream user wires it this way:
- Editing here automatically flows downstream — no copy-paste, no diff drift
- Their private project's `CLAUDE.md` should reference this repo upstream so future AI sessions on either side know about the link
- Any change to the **ENV contract** (renaming/removing `CC_TITLE_*` vars) is a breaking change for downstream symlink users — bump it loudly in the commit message and `README.md`

---

For the user-facing explanation, see [README.md](README.md).
