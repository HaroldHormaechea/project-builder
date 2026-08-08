#!/bin/bash
# SessionStart hook for the project-builder workspace.
#
# Two responsibilities:
#   1. Housekeeping (stderr only): ensure ~/.claude/skills exists so that project
#      skills symlinked into it at runtime hot-reload within the session, and prune
#      any orphan symlinks / stale ledger entries left by a previously crashed
#      session. See .claude/scripts/{acquire,release}-project-skills.sh.
#   2. Context (stdout): the workspace reminder text, injected for the model.
#
# IMPORTANT: only the reminder may go to stdout — stdout is injected as context.

SESSION_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Personal skills folder must exist at session start for live skill detection to
# watch it; mkdir is idempotent and harmless if it already exists.
mkdir -p "$HOME/.claude/skills" 2>/dev/null || true

# Crash recovery: drop dangling skill symlinks and stale ledger paths. Only touches
# orphans (target gone), so it is safe even if other sessions are live.
RELEASE="$SESSION_DIR/scripts/release-project-skills.sh"
[ -x "$RELEASE" ] && "$RELEASE" --prune-dangling 1>&2 2>/dev/null || true

cat <<'EOF'
[project-builder workspace reminder]

This workspace is tooling that creates and evolves OTHER projects; it is not a project itself. All work happens in a user-supplied TARGET_DIR. The workspace folder (SESSION_DIR) is off-limits to every spawned agent.

Four entry points:
  - project-builder subagent — scaffolds a new project. Writes PROJECT_BRIEF.md in TARGET_DIR.
  - develop skill — builds features via a 4-agent team (analyst, challenger, developer, qa).
  - revise-brief skill — updates sections of an existing PROJECT_BRIEF.md without re-scaffolding.
  - define-use-case skill — captures one formalized use case (summary, acceptance criteria, pitfalls) as an incrementally-numbered MD file in TARGET_DIR/use-cases/, then offers to chain into develop.

Hard orchestration rule: develop, revise-brief, and define-use-case MUST be invoked from the ROOT session. Spawned subagents cannot spawn further agents, so nested invocation fails. If you are already inside a subagent when the user asks for implementation, brief-revision, or use-case work, stop and tell them to restart at the root session.

When you start working in a TARGET_DIR that has its own .claude/skills/, invoke the acquire-project-skills skill first: it symlinks those project skills into ~/.claude/skills/ so they are usable in this session, records them in acquired-project-skills.json, and the SessionEnd hook removes them on exit.

Profiles are opt-in via PROJECT_BRIEF.md's frontmatter `profiles:` list (and its `## Profiles` prose section). Agents read the YAML frontmatter for structured fields (paths, stack, versions, profiles) — the prose is for humans only.
EOF
