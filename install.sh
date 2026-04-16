#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# cc-smart-title installer
#
# - Copies auto-rename-session.sh to ~/.claude/scripts/
# - Injects PostToolUse hook into ~/.claude/settings.json via jq
# - Idempotent: safe to run multiple times
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; exit 1; }

# ── Check dependencies ──
for cmd in jq curl flock; do
  command -v "$cmd" >/dev/null 2>&1 || error "Missing dependency: $cmd. Please install it first."
done

# ── Paths ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="${SCRIPT_DIR}/auto-rename-session.sh"
CLAUDE_DIR="${HOME}/.claude"
DEST_DIR="${CLAUDE_DIR}/scripts"
DEST_SCRIPT="${DEST_DIR}/auto-rename-session.sh"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
HOOK_COMMAND="${DEST_SCRIPT}"

[[ ! -f "$SOURCE_SCRIPT" ]] && error "auto-rename-session.sh not found in ${SCRIPT_DIR}"

# ── Copy script ──
mkdir -p "$DEST_DIR"
cp "$SOURCE_SCRIPT" "$DEST_SCRIPT"
chmod +x "$DEST_SCRIPT"
info "Script copied to ${DEST_SCRIPT}"

# ── Inject hook into settings.json ──
# Create settings.json if it doesn't exist
if [[ ! -f "$SETTINGS_FILE" ]]; then
  echo '{}' > "$SETTINGS_FILE"
  info "Created ${SETTINGS_FILE}"
fi

# Build the hook entry
HOOK_ENTRY='{"type":"command","command":"'"${HOOK_COMMAND}"'"}'

# Check if hook already exists (idempotent)
ALREADY_EXISTS=$(jq -r \
  --arg cmd "$HOOK_COMMAND" \
  '.hooks.PostToolUse // [] | map(select(.command == $cmd)) | length' \
  "$SETTINGS_FILE" 2>/dev/null || echo "0")

if [[ "$ALREADY_EXISTS" != "0" ]]; then
  warn "Hook already registered in settings.json — skipping"
else
  # Merge hook into settings.json without overwriting existing hooks
  TMP_FILE="$(mktemp)"
  jq --argjson entry "$HOOK_ENTRY" '
    .hooks = (.hooks // {}) |
    .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [$entry])
  ' "$SETTINGS_FILE" > "$TMP_FILE"

  if jq empty "$TMP_FILE" 2>/dev/null; then
    mv "$TMP_FILE" "$SETTINGS_FILE"
    info "Hook added to ${SETTINGS_FILE}"
  else
    rm -f "$TMP_FILE"
    error "Failed to update settings.json — JSON validation failed"
  fi
fi

# ── Check API key ──
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo ""
  warn "ANTHROPIC_API_KEY is not set!"
  echo "  The hook needs an API key to call Claude Haiku."
  echo "  Add to your shell profile (~/.bashrc or ~/.zshrc):"
  echo ""
  echo "    export ANTHROPIC_API_KEY=\"sk-ant-...\""
  echo ""
fi

echo ""
info "Installation complete! The hook will auto-rename sessions on next tool use."
echo "  Run 'claude' and start chatting — titles appear after ~3 tool calls."
