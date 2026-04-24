#!/bin/bash
# SessionStart hook for the project-builder workspace.
# Output on stdout is injected as additional context for the model.
cat <<'EOF'
[project-builder workspace reminder]

This workspace is tooling that creates and evolves OTHER projects; it is not a project itself. All work happens in a user-supplied TARGET_DIR. The workspace folder (SESSION_DIR) is off-limits to every spawned agent.

Four entry points:
  - project-builder subagent — scaffolds a new project. Writes PROJECT_BRIEF.md in TARGET_DIR.
  - develop skill — builds features via a 4-agent team (analyst, challenger, developer, qa).
  - revise-brief skill — updates sections of an existing PROJECT_BRIEF.md without re-scaffolding.
  - define-use-case skill — captures one formalized use case (summary, acceptance criteria, pitfalls) as an incrementally-numbered MD file in TARGET_DIR/use-cases/, then offers to chain into develop.

Hard orchestration rule: develop, revise-brief, and define-use-case MUST be invoked from the ROOT session. Spawned subagents cannot spawn further agents, so nested invocation fails. If you are already inside a subagent when the user asks for implementation, brief-revision, or use-case work, stop and tell them to restart at the root session.

Profiles are opt-in via PROJECT_BRIEF.md's frontmatter `profiles:` list (and its `## Profiles` prose section). Agents read the YAML frontmatter for structured fields (paths, stack, versions, profiles) — the prose is for humans only.
EOF
