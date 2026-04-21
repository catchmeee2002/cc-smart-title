#!/bin/bash
#
# statusline-title.sh — Display cc-smart-title session titles in the status bar
#
# A minimal statusLine hook that shows the AI-generated session title
# alongside basic session info (model, directory, session ID).
#
# Adaptive layout: automatically adjusts to terminal width
#   Wide  (≥100 cols): single line with all info
#   Narrow (<100 cols): two lines, title on its own line
#
# Usage: Add to settings.json as a statusLine command hook.
# See README.md for installation instructions.
#

C_RESET='\033[0m'
C_DIM='\033[38;5;245m'
C_ACCENT='\033[38;5;74m'  # blue accent

input=$(cat)

# Extract fields in a single jq call
IFS=$'\t' read -r model dir session_id transcript_path project_dir cwd \
    <<< "$(echo "$input" | jq -r '[
  (.model.display_name // .model.id // "?"),
  (.cwd // "" | split("/") | last // "?"),
  (.session_id // ""),
  (.transcript_path // ""),
  (.workspace.project_dir // ""),
  (.cwd // "")
] | @tsv')"

# ── Look up session title from sessions-index.json ───────────────────
session_title=""
if [[ -n "$session_id" ]]; then
    # Prefer transcript_path to locate the project directory (consistent
    # with auto-rename-session.sh), fall back to slug calculation.
    index_file=""
    if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
        index_file="$(dirname "$transcript_path")/sessions-index.json"
    fi
    if [[ -z "$index_file" || ! -f "$index_file" ]]; then
        title_cwd="${project_dir:-$cwd}"
        if [[ -n "$title_cwd" ]]; then
            slug=$(echo "$title_cwd" | sed 's|^/||; s|/|-|g; s|\.|-|g; s|_|-|g; s|^|-|')
            index_file="${HOME}/.claude/projects/${slug}/sessions-index.json"
        fi
    fi
    if [[ -n "$index_file" && -f "$index_file" ]]; then
        session_title=$(jq -r --arg sid "$session_id" \
            '[.entries[] | select(.sessionId == $sid)][0].customTitle // empty' \
            "$index_file" 2>/dev/null)
    fi
fi

# ── Adaptive output ──────────────────────────────────────────────────
term_width=$(tput cols 2>/dev/null || echo 120)
sid_short="${session_id:0:8}"

if [[ $term_width -ge 100 ]]; then
    # Wide: single line
    line="${C_ACCENT}${model}${C_DIM} | ${dir}"
    [[ -n "$sid_short" ]] && line+=" | 🆔${sid_short}"
    [[ -n "$session_title" ]] && line+=" | 📝${session_title}"
    line+="${C_RESET}"
    printf '%b\n' "$line"
else
    # Narrow: two lines
    line1="${C_ACCENT}${model}${C_DIM} | ${dir}"
    [[ -n "$sid_short" ]] && line1+=" | 🆔${sid_short}"
    line1+="${C_RESET}"

    printf '%b\n' "$line1"
    if [[ -n "$session_title" ]]; then
        printf '%b\n' "${C_ACCENT}📝${session_title}${C_RESET}"
    fi
fi
