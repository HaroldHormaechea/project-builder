---
name: revise-brief
description: Update one or more sections of an existing PROJECT_BRIEF.md in a target project folder without re-scaffolding. Lets the user pick which section(s) to refresh (overview, monetization, technologies, architecture, quality-and-profiles, deployment) and delegates to the project-builder subagent to re-run only those define-* skills. Keeps the YAML frontmatter in sync and preserves untouched sections. Use when the target project already has a brief and the user wants to evolve it; use `project-builder` for initial scaffolding or `develop` to build features.
---

# Revise Brief

Entry point for evolving an existing `PROJECT_BRIEF.md` without re-scaffolding or re-running every question. Use this when:

- The tech stack changed and `## Technologies` is stale.
- A new profile was added and `## Profiles` needs updating.
- Deployment plans shifted (new cloud provider, new IaC).
- Architecture paths changed and `paths.*` frontmatter fields need updating.

Do NOT use this skill to scaffold a new project (use `project-builder`) or to build features (use `develop`).

## Preconditions

- Must run from the **root Claude Code session**. Spawned subagents cannot spawn further agents.
- The target folder must already contain a `PROJECT_BRIEF.md`. If not, this skill stops and points the user to `project-builder`.

## Step 1 — Resolve folders

1. Run `pwd` via Bash to get `SESSION_DIR`.
2. Ask the user for the target project folder (`TARGET_DIR`) as an absolute path. Resolve relative paths and confirm.
3. Refuse and re-ask if `TARGET_DIR` equals, contains, or is contained by `SESSION_DIR` (path-segment comparison).
4. Confirm `<TARGET_DIR>/PROJECT_BRIEF.md` exists. If it does not, stop and tell the user to run `project-builder` first.

## Step 2 — Inspect current state

1. Read `PROJECT_BRIEF.md`.
2. Parse the YAML frontmatter at the top. If the frontmatter is missing or lacks `schema_version`, stop and tell the user the brief must be migrated by running `project-builder` against this folder (it will repair the frontmatter on resume).
3. Enumerate the prose sections present (e.g., `## Overview`, `## Monetization`, `## Technologies`, `## Architecture`, `## Quality & Standards`, `## Profiles`, `## Deployment`).

## Step 3 — Ask what to revise

Present the user with a multi-choice menu of sections to refresh. Use `AskUserQuestion` and allow multiple selections:

- `overview` → re-run `define-overview` (updates frontmatter `project.*`)
- `monetization` → re-run `define-monetization`
- `technologies` → re-run `define-technologies` (updates frontmatter `stack.*` and `build.*`)
- `architecture` → re-run `define-architecture` (updates frontmatter `paths.*`)
- `quality-and-profiles` → re-run `define-quality-standards` (updates frontmatter `test.*` and `profiles`, and rewrites both `## Quality & Standards` and `## Profiles` prose sections)
- `deployment` → re-run `define-deployment` (updates frontmatter `deployment.*`)

If the user selects nothing, stop — there's nothing to do.

## Step 4 — Delegate to project-builder in revise mode

Spawn the `project-builder` subagent via the Agent tool:

- `subagent_type: "project-builder"`
- `mode: "acceptEdits"`
- `prompt`: an instruction block containing:
  - The absolute `TARGET_DIR`.
  - An explicit `REVISE_MODE` flag with the ordered list of skills to re-run (exactly what the user selected).
  - A directive: re-run ONLY those skills. Preserve all other prose sections. Preserve all frontmatter fields owned by other skills. Do NOT run the scaffolding step.

## Step 5 — Present the diff

After `project-builder` returns:

1. Read the updated `PROJECT_BRIEF.md`.
2. Show the user a concise summary of what changed (which sections were rewritten, which frontmatter fields were updated). A full textual diff is optional; a section-by-section summary is usually clearer.
3. Ask whether further revisions are needed. If yes, loop to Step 3.

## Constraints

- Never touch `SESSION_DIR`.
- Never rewrite sections the user did not opt to revise.
- Never change `schema_version`.
- Never invoke the scaffolding step — this skill evolves the brief, not the project structure.
- If `project-builder` reports that a requested skill cannot complete (e.g., the user aborted a question), leave the corresponding section untouched and report the state to the user.
