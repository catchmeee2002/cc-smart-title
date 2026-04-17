#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# cc-smart-title uninstaller
#
# - Removes auto-rename-session.sh + auto-title-on-first-prompt.sh from ~/.claude/scripts/
# - Removes the PostToolUse + UserPromptSubmit hook entries from ~/.claude/settings.json
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; exit 1; }

CLAUDE_DIR="${HOME}/.claude"
DEST_SCRIPT="${CLAUDE_DIR}/scripts/auto-rename-session.sh"
DEST_FIRST_SCRIPT="${CLAUDE_DIR}/scripts/auto-title-on-first-prompt.sh"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"

# ── Remove scripts ──
for f in "$DEST_SCRIPT" "$DEST_FIRST_SCRIPT"; do
  if [[ -f "$f" ]]; then
    rm -f "$f"
    info "Removed ${f}"
  else
    warn "Script not found at ${f} — skipping"
  fi
done

# ── Remove hook from settings.json ──
if [[ -f "$SETTINGS_FILE" ]] && command -v jq >/dev/null 2>&1; then
  HOOK_COUNT=$(jq -r \
    '.hooks.PostToolUse // [] | map(select(.command | test("auto-rename-session"))) | length' \
    "$SETTINGS_FILE" 2>/dev/null || echo "0")

  if [[ "$HOOK_COUNT" != "0" ]]; then
    TMP_FILE="$(mktemp)"
    jq '
      .hooks.PostToolUse = [
        (.hooks.PostToolUse // [])[]
        | select(.command | test("auto-rename-session") | not)
      ]
      | if (.hooks.PostToolUse | length) == 0 then del(.hooks.PostToolUse) else . end
      | if (.hooks | length) == 0 then del(.hooks) else . end
    ' "$SETTINGS_FILE" > "$TMP_FILE"

    if jq empty "$TMP_FILE" 2>/dev/null; then
      mv "$TMP_FILE" "$SETTINGS_FILE"
      info "PostToolUse hook removed from ${SETTINGS_FILE}"
    else
      rm -f "$TMP_FILE"
      error "Failed to update settings.json"
    fi
  else
    warn "No matching PostToolUse hook found in settings.json — skipping"
  fi

  # Remove UserPromptSubmit first-prompt hook
  FIRST_COUNT=$(jq -r \
    '[.hooks.UserPromptSubmit[]?.hooks[]? | select(.command | test("auto-title-on-first-prompt"))] | length' \
    "$SETTINGS_FILE" 2>/dev/null || echo "0")

  if [[ "$FIRST_COUNT" != "0" ]]; then
    TMP_FILE="$(mktemp)"
    jq '
      .hooks.UserPromptSubmit = [
        (.hooks.UserPromptSubmit // [])[]
        | .hooks = [(.hooks // [])[] | select(.command | test("auto-title-on-first-prompt") | not)]
        | select((.hooks | length) > 0)
      ]
      | if (.hooks.UserPromptSubmit | length) == 0 then del(.hooks.UserPromptSubmit) else . end
      | if (.hooks | length) == 0 then del(.hooks) else . end
    ' "$SETTINGS_FILE" > "$TMP_FILE"

    if jq empty "$TMP_FILE" 2>/dev/null; then
      mv "$TMP_FILE" "$SETTINGS_FILE"
      info "UserPromptSubmit hook removed from ${SETTINGS_FILE}"
    else
      rm -f "$TMP_FILE"
      error "Failed to update settings.json"
    fi
  else
    warn "No matching UserPromptSubmit hook found in settings.json — skipping"
  fi
else
  warn "settings.json not found or jq not available — skipping hook removal"
fi

# ── Clean up temp files ──
rm -f /tmp/cc-rename-*.count /tmp/cc-first-prompt-*.done 2>/dev/null || true
info "Cleaned up temp files"

echo ""
info "Uninstall complete!"
