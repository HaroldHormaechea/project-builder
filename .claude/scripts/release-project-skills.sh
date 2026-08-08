#!/usr/bin/env bash
#
# release-project-skills.sh <SESSION_ID>
# release-project-skills.sh --prune-dangling
#
# Removes the personal-skill symlinks that acquire-project-skills.sh created, and
# keeps the ledger (<SESSION_DIR>/acquired-project-skills.json) in sync.
#
# Mode 1 — release a session (called by the SessionEnd hook):
#   Removes every symlink recorded for entries whose session_id matches <SESSION_ID>,
#   then drops those entries from the ledger. Only ever removes SYMLINKS (guarded by
#   a -L test) — a real file/dir that happens to share the path is left untouched.
#   Always finishes with the dangling-link safety sweep below.
#
# Mode 2 — --prune-dangling (called by the SessionStart hook):
#   Runs only the safety sweep: deletes broken symlinks under ~/.claude/skills/
#   (target gone) and prunes ledger skill paths / entries that no longer exist.
#   This recovers orphans left behind when a previous session was killed before its
#   SessionEnd hook could run. It never touches links whose target still exists, so
#   it is safe to run while other sessions are live.
#
# Output: a short report on stderr (so a SessionStart caller can keep stdout clean).

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SESSION_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SKILLS_HOME="$HOME/.claude/skills"
LEDGER="$SESSION_DIR/acquired-project-skills.json"

log() { printf 'release-project-skills: %s\n' "$*" >&2; }

MODE="session"
SESSION_ID=""
case "${1:-}" in
  "")               log "usage: release-project-skills.sh <SESSION_ID> | --prune-dangling"; exit 2 ;;
  --prune-dangling) MODE="prune" ;;
  *)                SESSION_ID="$1" ;;
esac

# --- Mode 1: remove this session's recorded symlinks + ledger entries --------
if [ "$MODE" = "session" ] && [ -f "$LEDGER" ]; then
  removed=0; kept_real=0
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ -L "$path" ]; then
      rm -f -- "$path" && removed=$((removed + 1))
    elif [ -e "$path" ]; then
      log "left real (non-symlink) path in place: $path"
      kept_real=$((kept_real + 1))
    fi
  done < <(jq -r --arg sid "$SESSION_ID" \
            '.["acquired-project-skills"][] | select(.session_id == $sid) | .skills[]' \
            "$LEDGER" 2>/dev/null || true)

  tmp="$(mktemp "${LEDGER}.XXXXXX")"
  jq --arg sid "$SESSION_ID" \
     '.["acquired-project-skills"] |= map(select(.session_id != $sid))' \
     "$LEDGER" > "$tmp" && mv -- "$tmp" "$LEDGER"
  log "session $SESSION_ID: removed $removed symlink(s), left $kept_real real path(s)."
fi

# --- Safety sweep: broken symlinks + stale ledger paths (both modes) ---------
swept=0
if [ -d "$SKILLS_HOME" ]; then
  shopt -s nullglob
  for e in "$SKILLS_HOME"/*; do
    # Broken symlink: is a symlink (-L) but its target is gone (! -e).
    if [ -L "$e" ] && [ ! -e "$e" ]; then
      rm -f -- "$e" && swept=$((swept + 1))
    fi
  done
  shopt -u nullglob
fi

# Prune ledger: drop skill paths that no longer exist, then drop empty entries.
if [ -f "$LEDGER" ]; then
  keep="$(jq -r '.["acquired-project-skills"][].skills[]' "$LEDGER" 2>/dev/null \
          | sort -u \
          | while IFS= read -r p; do [ -n "$p" ] && { [ -e "$p" ] || [ -L "$p" ]; } && printf '%s\n' "$p"; done \
          | jq -R . | jq -s .)"
  tmp="$(mktemp "${LEDGER}.XXXXXX")"
  jq --argjson keep "${keep:-[]}" '
    .["acquired-project-skills"] |= (
      map(.skills |= map(select(. as $p | $keep | index($p))))
      | map(select((.skills | length) > 0))
    )' "$LEDGER" > "$tmp" && mv -- "$tmp" "$LEDGER"
fi

[ "$swept" -gt 0 ] && log "swept $swept dangling symlink(s) from $SKILLS_HOME."
exit 0
