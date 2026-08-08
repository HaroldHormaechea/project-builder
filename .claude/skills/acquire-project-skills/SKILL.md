---
name: acquire-project-skills
description: Make a target project's own skills usable in the current session. Reads <TARGET_DIR>/.claude/skills/, symlinks each skill into ~/.claude/skills/ (so Claude Code hot-reloads them on the next turn), and records them in acquired-project-skills.json so the SessionEnd hook can remove them on exit. Invoke this at the START of working in any TARGET_DIR that ships its own .claude/skills/ — including from the project-builder, develop, revise-brief, and define-use-case entry points — or run it standalone to pull in one project's skills. Skips (never clobbers) any name already present in ~/.claude/skills/ or any name that matches a workspace skill.
---

# Acquire Project Skills

Target projects can carry their own skills under `<TARGET_DIR>/.claude/skills/`. Because this Claude session is launched from the **project-builder workspace** (not the target), those project-local skills are not loaded automatically. This skill bridges that gap: it symlinks them into the user's personal skills folder (`~/.claude/skills/`), which Claude Code watches and hot-reloads, so the target's skills become callable in this session without a restart.

Every symlink is logged in `<SESSION_DIR>/acquired-project-skills.json` (gitignored), keyed by `(project, session_id)`. The `SessionEnd` hook removes exactly this session's links on exit; nothing leaks into the next session.

## When to run

- At the **start of work** on a TARGET_DIR — the `project-builder`, `develop`, `revise-brief`, and `define-use-case` entry points should invoke this once `TARGET_DIR` is resolved, before doing their real work, so any project-shipped skills are available.
- **Standalone**, when the user asks to "use / load / pull in the skills from project X."
- Re-running it is safe and idempotent: an already-correct link is left in place; nothing is duplicated.

A freshly scaffolded project usually has no `.claude/skills/` yet — in that case this is a no-op and you can move on.

## Step 1 — Resolve folders

1. Run `pwd` via Bash to confirm `SESSION_DIR` (the workspace; this is where the script and ledger live).
2. Determine `TARGET_DIR` (absolute path):
   - If an invoking entry point already resolved and confirmed a `TARGET_DIR`, reuse it — do **not** re-ask.
   - Otherwise ask the user for it, resolve relative paths with `cd <path> && pwd`, and confirm.
3. Refuse if `TARGET_DIR` equals, contains, or is contained by `SESSION_DIR` (path-segment comparison — `/foo/bar` is not a prefix of `/foo/barbaz`). The workspace's own skills are already loaded; never link them.

## Step 2 — Run the acquire script

Run the workspace script, passing the resolved target:

```
"$SESSION_DIR/.claude/scripts/acquire-project-skills.sh" "<TARGET_DIR>"
```

The script does all the work safely:

- Finds every `<TARGET_DIR>/.claude/skills/*/SKILL.md`.
- Symlinks each skill dir to `~/.claude/skills/<name>`, **skipping** (with a warning, never clobbering) any name that already exists there or that matches one of this workspace's own skills.
- Upserts the `(project, session_id)` entry in `acquired-project-skills.json`.
- Prints a report of what was linked and what was skipped.

It uses `$CLAUDE_CODE_SESSION_ID` to tag the ledger entry, so cleanup is scoped to this session.

## Step 3 — Relay the result

Report to the user, concisely:

- Which skills were linked (now usable this session).
- Which were skipped and why (name collision in `~/.claude/skills/`, or would shadow a workspace skill).
- **Hot-reload caveat:** linked skills become callable on the **next turn** — but only if `~/.claude/skills/` already existed when this session started. The `SessionStart` hook creates it, so this holds for any session started after this tooling was installed. If `~/.claude/skills/` did not exist at session start (first-ever run on a machine), tell the user the links are in place but a **session restart** is needed for Claude Code to pick them up.

Then continue with whatever work prompted the acquisition.

## Cleanup (automatic — do not do this by hand)

- The **`SessionEnd` hook** runs `release-project-skills.sh <session_id>` on exit: it removes this session's symlinks (only ever symlinks — a real file/dir at the same path is left untouched) and drops the ledger entries.
- The **`SessionStart` hook** runs `release-project-skills.sh --prune-dangling`: a safety sweep that clears orphan symlinks / stale ledger entries left by a previous session that was killed before its `SessionEnd` could fire.

You normally never invoke the release script directly. Do so only if the user explicitly asks to drop acquired skills mid-session.

## Constraints

- Never write anywhere inside `SESSION_DIR` (the script writes only to `~/.claude/skills/` and the gitignored ledger at `SESSION_DIR/acquired-project-skills.json`, which is allowed).
- Never delete a real (non-symlink) entry from `~/.claude/skills/` — the script enforces this; do not work around it.
- Do not hand-edit `acquired-project-skills.json`; let the scripts and hooks own it.
