#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# cc-smart-title: auto-rename-session.sh — PostToolUse hook
#
# Automatically generates a short Chinese title for each Claude Code
# session using the Haiku model, and writes it to sessions-index.json
# so `claude --resume` shows meaningful names.
#
# Design:
#   - The hook itself only reads stdin + throttle check, exits immediately
#   - Heavy work (extract messages → curl API → write JSON) runs in background
#   - Calls Anthropic API directly via curl (no claude CLI, avoids locks)
#
# Install: chmod +x, then add to settings.json hooks.PostToolUse
# Uninstall: rm this file, remove the hook entry from settings.json
# Dependencies: curl, jq, flock
# ─────────────────────────────────────────────────────────────────
set -euo pipefail
cleanup() { exit 0; }
trap cleanup EXIT ERR

# ===================== Configurable Parameters =====================
# How often to trigger (every N tool calls). Lower = more frequent renames.
THROTTLE_EVERY="${CC_TITLE_THROTTLE:-3}"
# Max bytes for generated title (UTF-8 Chinese chars are ~3 bytes each).
MAX_TITLE_BYTES="${CC_TITLE_MAX_BYTES:-33}"
# Prompt template for title generation.
TITLE_PROMPT="${CC_TITLE_PROMPT:-用10个中文字以内总结以下对话的主题，只输出标题，不加引号不加标点：}"
# Haiku model to use.
HAIKU_MODEL="${CC_TITLE_MODEL:-claude-haiku-4.5}"
# API endpoint.
API_URL="${ANTHROPIC_BASE_URL:-https://api.anthropic.com}"
# API key — REQUIRED. Set ANTHROPIC_API_KEY in your environment.
API_KEY="${ANTHROPIC_API_KEY:-}"
# ===================================================================

# === 1. Read stdin JSON (hook input) ===
INPUT="$(cat)"
SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty')"
TRANSCRIPT="$(echo "$INPUT" | jq -r '.transcript_path // empty')"
CWD="$(echo "$INPUT" | jq -r '.cwd // empty')"
[[ -z "$SESSION_ID" || -z "$TRANSCRIPT" || -z "$CWD" ]] && exit 0

# === 2. Throttle: trigger once every N tool calls ===
COUNT_FILE="/tmp/cc-rename-${SESSION_ID}.count"
COUNT=0
[[ -f "$COUNT_FILE" ]] && COUNT="$(cat "$COUNT_FILE" 2>/dev/null || echo 0)"
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNT_FILE"
(( COUNT % THROTTLE_EVERY != 0 )) && exit 0

# === 3. Fork background subprocess — hook returns immediately ===
CLAUDE_DIR="${HOME}/.claude"

(
  # --- Background: extract messages → curl haiku → write JSON ---

  # 3a. Extract recent user messages from transcript
  [[ ! -f "$TRANSCRIPT" ]] && exit 0
  MESSAGES="$(grep '"type":"user"' "$TRANSCRIPT" 2>/dev/null \
    | jq -r '
        select(.isMeta != true)
        | .message.content
        | select(type == "string")
        | select(startswith("<") | not)
      ' 2>/dev/null \
    | grep -v '^\s*$' \
    | tail -n 5 \
    | head -c 2000)"
  [[ -z "$MESSAGES" ]] && exit 0

  # 3b. Call Haiku API to generate title
  ESCAPED_MSG="$(echo "$MESSAGES" | jq -Rs '.')"
  REQUEST_BODY="$(jq -n \
    --arg model "$HAIKU_MODEL" \
    --argjson msg "$ESCAPED_MSG" \
    --arg prompt "$TITLE_PROMPT" \
    '{model: $model, max_tokens: 50,
      messages: [{role: "user",
        content: ($prompt + "\n\n" + $msg)}]}')"

  TITLE="$(curl -s --max-time 10 "${API_URL}/v1/messages" \
    -H "Content-Type: application/json" \
    -H "x-api-key: ${API_KEY}" \
    -H "anthropic-version: 2023-06-01" \
    -d "$REQUEST_BODY" 2>/dev/null \
    | jq -r '.content[0].text // empty' \
    | tr -d '\n' \
    | head -c "$MAX_TITLE_BYTES")" || true
  # Strip surrounding quotes and whitespace
  TITLE="$(echo "$TITLE" | sed 's/^["'"'"']*//;s/["'"'"']*$//;s/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "$TITLE" ]] && exit 0

  # 3c. Derive project slug → locate sessions-index.json
  SLUG="$(echo "$CWD" | sed 's|^/||; s|/|-|g; s|\.|-|g; s|_|-|g; s|^|-|')"
  INDEX_FILE="${CLAUDE_DIR}/projects/${SLUG}/sessions-index.json"
  if [[ ! -f "$INDEX_FILE" ]]; then
    # Fallback: search all project dirs for matching session
    for DIR in "${CLAUDE_DIR}/projects/"*/; do
      CANDIDATE="${DIR}sessions-index.json"
      if [[ -f "$CANDIDATE" ]] && jq -e \
        --arg sid "$SESSION_ID" \
        '.entries[]? | select(.sessionId == $sid)' \
        "$CANDIDATE" >/dev/null 2>&1; then
        INDEX_FILE="$CANDIDATE"; break
      fi
    done
  fi
  # Auto-create sessions-index.json if project dir exists but file doesn't
  if [[ ! -f "$INDEX_FILE" ]]; then
    PROJECT_DIR="${CLAUDE_DIR}/projects/${SLUG}"
    if [[ -d "$PROJECT_DIR" ]]; then
      echo '{"entries":[]}' > "${PROJECT_DIR}/sessions-index.json"
      INDEX_FILE="${PROJECT_DIR}/sessions-index.json"
    else
      exit 0
    fi
  fi

  # 3d. Atomic update customTitle with flock
  LOCK_FILE="${INDEX_FILE}.lock"
  (
    flock -w 5 200 || exit 0
    cp "$INDEX_FILE" "${INDEX_FILE}.bak" 2>/dev/null || true
    TMP_FILE="$(mktemp "${INDEX_FILE}.tmp.XXXXXX")"
    jq --arg sid "$SESSION_ID" --arg title "$TITLE" \
       --arg fpath "$TRANSCRIPT" --arg ppath "$CWD" '
      if (.entries | map(select(.sessionId == $sid)) | length) > 0 then
        .entries = [.entries[]? | if .sessionId == $sid then .customTitle = $title else . end]
      else
        .entries += [{"sessionId": $sid, "fullPath": $fpath, "customTitle": $title, "projectPath": $ppath}]
      end
    ' "$INDEX_FILE" > "$TMP_FILE" 2>/dev/null
    if jq empty "$TMP_FILE" 2>/dev/null; then
      mv "$TMP_FILE" "$INDEX_FILE"
    else
      rm -f "$TMP_FILE"
    fi
  ) 200>"$LOCK_FILE"
) &>/dev/null &
disown

exit 0
