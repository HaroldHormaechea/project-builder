#!/usr/bin/env bash
#
# SessionEnd hook for the project-builder workspace.
#
# Removes the personal-skill symlinks that this session acquired from target
# projects (see .claude/scripts/acquire-project-skills.sh) and prunes the ledger.
# The session_id arrives as JSON on stdin; we match the ledger on it so a
# concurrent session's links are left intact.
#
# SessionEnd is not guaranteed to fire on a hard kill, so cleanup is also belt-
# and-braces: the release script always runs a dangling-symlink sweep, and the
# SessionStart hook prunes orphans left by a previous crash.

set -euo pipefail

HOOK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SESSION_DIR="$(cd -- "$HOOK_DIR/.." && pwd)"   # .claude/hooks -> .claude -> SESSION_DIR
RELEASE="$SESSION_DIR/scripts/release-project-skills.sh"

# Hook payload is JSON on stdin; fall back to the env var if jq/stdin is unavailable.
input="$(cat || true)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -n "$session_id" ] || session_id="${CLAUDE_CODE_SESSION_ID:-}"

if [ -z "$session_id" ]; then
  # No id to match on — still run the dangling sweep so nothing leaks.
  [ -x "$RELEASE" ] && "$RELEASE" --prune-dangling || true
  exit 0
fi

[ -x "$RELEASE" ] && "$RELEASE" "$session_id" || true
exit 0
