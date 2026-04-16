#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# cc-smart-title uninstaller
#
# - Removes auto-rename-session.sh from ~/.claude/scripts/
# - Removes the PostToolUse hook entry from ~/.claude/settings.json
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
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"

# ── Remove script ──
if [[ -f "$DEST_SCRIPT" ]]; then
  rm -f "$DEST_SCRIPT"
  info "Removed ${DEST_SCRIPT}"
else
  warn "Script not found at ${DEST_SCRIPT} — skipping"
fi

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
      info "Hook removed from ${SETTINGS_FILE}"
    else
      rm -f "$TMP_FILE"
      error "Failed to update settings.json"
    fi
  else
    warn "No matching hook found in settings.json — skipping"
  fi
else
  warn "settings.json not found or jq not available — skipping hook removal"
fi

# ── Clean up temp files ──
rm -f /tmp/cc-rename-*.count 2>/dev/null || true
info "Cleaned up temp files"

echo ""
info "Uninstall complete!"
