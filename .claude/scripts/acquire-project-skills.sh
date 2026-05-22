#!/usr/bin/env bash
#
# acquire-project-skills.sh <TARGET_DIR>
#
# Symlinks every skill found under <TARGET_DIR>/.claude/skills/ into the user's
# personal skills folder (~/.claude/skills/) so those project-local skills become
# available in the CURRENT Claude Code session (hot-reload picks them up on the
# next turn, provided ~/.claude/skills/ already existed at session start).
#
# Each acquired symlink is recorded in <SESSION_DIR>/acquired-project-skills.json,
# keyed by (project, session_id), so the SessionEnd hook can remove exactly the
# links this session created. See .claude/scripts/release-project-skills.sh.
#
# Safety rules:
#   - Never clobbers an existing entry in ~/.claude/skills/ (skip + warn).
#   - Never shadows one of THIS workspace's own skills (skip + warn).
#   - Refuses a TARGET_DIR equal to or inside SESSION_DIR (workspace is off-limits).
#
# Output: a human-readable report on stdout. Exit non-zero only on hard errors
# (bad args, missing target); collisions are warnings, not failures.

set -euo pipefail

# --- resolve locations -------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SESSION_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"   # .claude/scripts -> SESSION_DIR
SKILLS_HOME="$HOME/.claude/skills"
LEDGER="$SESSION_DIR/acquired-project-skills.json"
SESSION_ID="${CLAUDE_CODE_SESSION_ID:-unknown-$(date +%s)}"

die() { printf 'acquire-project-skills: %s\n' "$*" >&2; exit 1; }

# --- validate target ---------------------------------------------------------
[ "$#" -eq 1 ] || die "usage: acquire-project-skills.sh <TARGET_DIR>"
RAW_TARGET="$1"
[ -d "$RAW_TARGET" ] || die "TARGET_DIR does not exist or is not a directory: $RAW_TARGET"
TARGET_DIR="$(cd -- "$RAW_TARGET" && pwd)"

# Hard rule: the workspace folder is off-limits — refuse if TARGET_DIR equals,
# is inside, or is an ancestor of SESSION_DIR (path-segment comparison via the
# trailing-slash trick, so /foo/bar is not treated as a prefix of /foo/barbaz).
case "$TARGET_DIR/" in "$SESSION_DIR/"*)
  die "refusing: TARGET_DIR is the workspace session dir or inside it: $TARGET_DIR" ;;
esac
case "$SESSION_DIR/" in "$TARGET_DIR/"*)
  die "refusing: TARGET_DIR is an ancestor of the workspace session dir: $TARGET_DIR" ;;
esac

SRC_SKILLS_DIR="$TARGET_DIR/.claude/skills"
if [ ! -d "$SRC_SKILLS_DIR" ]; then
  printf 'No .claude/skills/ directory in target project — nothing to acquire.\n'
  printf '  target: %s\n' "$TARGET_DIR"
  exit 0
fi

mkdir -p "$SKILLS_HOME"

# --- ensure ledger exists ----------------------------------------------------
if [ ! -f "$LEDGER" ]; then
  printf '{"acquired-project-skills": []}\n' > "$LEDGER"
fi

# --- walk the target's skills ------------------------------------------------
linked=()        # absolute symlink paths created or already-correct this run
linked_names=()
skipped_collision=()
skipped_workspace=()

shopt -s nullglob
found_any=0
for skill_md in "$SRC_SKILLS_DIR"/*/SKILL.md; do
  found_any=1
  src_dir="$(dirname -- "$skill_md")"
  name="$(basename -- "$src_dir")"
  dest="$SKILLS_HOME/$name"

  # Never shadow one of THIS workspace's own skills.
  if [ -e "$SESSION_DIR/.claude/skills/$name" ]; then
    skipped_workspace+=("$name")
    continue
  fi

  if [ -L "$dest" ]; then
    # Already a symlink. Idempotent if it points where we want; otherwise a clash.
    existing="$(readlink -f -- "$dest" 2>/dev/null || true)"
    if [ "$existing" = "$src_dir" ]; then
      linked+=("$dest"); linked_names+=("$name")   # already linked by us — keep recorded
    else
      skipped_collision+=("$name")
    fi
    continue
  fi

  if [ -e "$dest" ]; then
    # A real file/dir already owns this name — never clobber.
    skipped_collision+=("$name")
    continue
  fi

  ln -s -- "$src_dir" "$dest"
  linked+=("$dest"); linked_names+=("$name")
done
shopt -u nullglob

if [ "$found_any" -eq 0 ]; then
  printf 'No skills (no */SKILL.md) found under %s — nothing to acquire.\n' "$SRC_SKILLS_DIR"
  exit 0
fi

# --- update the ledger -------------------------------------------------------
if [ "${#linked[@]}" -gt 0 ]; then
  skills_json="$(printf '%s\n' "${linked[@]}" | jq -R . | jq -s 'unique')"
  tmp="$(mktemp "${LEDGER}.XXXXXX")"
  jq \
    --arg proj "$TARGET_DIR" \
    --arg sid "$SESSION_ID" \
    --argjson newskills "$skills_json" '
    .["acquired-project-skills"] |= (
      if any(.[]; .project == $proj and .session_id == $sid)
      then map(
             if .project == $proj and .session_id == $sid
             then .skills = ((.skills + $newskills) | unique)
             else . end)
      else . + [{project: $proj, session_id: $sid, skills: $newskills}]
      end
    )' "$LEDGER" > "$tmp" && mv -- "$tmp" "$LEDGER"
fi

# --- report ------------------------------------------------------------------
printf 'Acquired project skills from: %s\n' "$TARGET_DIR"
printf '  session: %s\n' "$SESSION_ID"
if [ "${#linked_names[@]}" -gt 0 ]; then
  printf '  linked (%d): %s\n' "${#linked_names[@]}" "$(printf '%s, ' "${linked_names[@]}" | sed 's/, $//')"
else
  printf '  linked: none\n'
fi
[ "${#skipped_collision[@]}" -gt 0 ] && \
  printf '  skipped — name already in ~/.claude/skills (%d): %s\n' \
    "${#skipped_collision[@]}" "$(printf '%s, ' "${skipped_collision[@]}" | sed 's/, $//')"
[ "${#skipped_workspace[@]}" -gt 0 ] && \
  printf '  skipped — would shadow a workspace skill (%d): %s\n' \
    "${#skipped_workspace[@]}" "$(printf '%s, ' "${skipped_workspace[@]}" | sed 's/, $//')"
printf '  ledger:  %s\n' "$LEDGER"
printf 'Note: skills hot-reload on the next turn only if ~/.claude/skills existed at session start.\n'
exit 0
