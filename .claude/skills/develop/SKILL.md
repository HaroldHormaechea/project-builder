---
name: develop
description: Development workflow using an agent team (Analyst, Challenger, Developer, QA) to implement features, bug fixes, or refactors in a target project folder. Requires a PROJECT_BRIEF.md in the target folder; if missing, invokes project-builder first to generate one. Use BEFORE entering plan mode whenever the user asks for a code change in an external project.
---

# Development Team Workflow

Entry point for any implementation task (new feature, bug fix, refactor, or other code change) in a target project. Replaces plan mode and manual exploration. The workflow is orchestrated by the root session with four specialized agents.

## Preconditions

This skill MUST be invoked from the **root Claude Code session**. Spawned subagents cannot spawn further agents, so nested invocation will fail. If you are already inside a subagent when the user asks for this flow, stop and instruct them to restart at the root session.

## Team composition

| Role | Agent name | May write | Read-only |
|---|---|---|---|
| Analyst | `analyst` | — | yes |
| Challenger | `challenger` | — | yes |
| Developer | `developer` | production-code paths declared in `PROJECT_BRIEF.md` | |
| QA | `qa` | test-code paths declared in `PROJECT_BRIEF.md` | |

Role boundaries are derived from `PROJECT_BRIEF.md` in the target folder — not hardcoded.

## Step 1 — Resolve session and target folders

1. Run `pwd` via Bash to get `SESSION_DIR`. Do not hardcode this path; always resolve it fresh.
2. Ask the user for the target project folder (`TARGET_DIR`) as an absolute path. Resolve relative paths with `cd <path> && pwd` and confirm.
3. Refuse and re-ask if `TARGET_DIR` equals, contains, or is contained by `SESSION_DIR` (path-segment comparison — `/foo/bar` is not a prefix of `/foo/barbaz`).
4. If `TARGET_DIR` does not exist, abort. Offer to scaffold a new project via `project-builder` first.

## Step 2 — Ensure a PROJECT_BRIEF.md

1. Check for `<TARGET_DIR>/PROJECT_BRIEF.md`.
2. **If present**: read it and confirm with the user that it still reflects the current state of the project. Proceed.
3. **If missing**: tell the user the team needs a brief to derive architecture, tech stack, and conventions. Offer to spawn the `project-builder` subagent to generate one. On agreement:
   - Spawn via the Agent tool with `subagent_type: "project-builder"`, `mode: "acceptEdits"`, and a prompt directing it at `TARGET_DIR`.
   - Wait for completion. Confirm `PROJECT_BRIEF.md` now exists in `TARGET_DIR`.
4. If the user declines to produce a brief, stop — `develop` cannot run without one.

## Step 3 — Describe and confirm

Briefly describe the phases (Analysis → Challenge → Plan preview → Implementation → Testing), the 6-round cap on every feedback loop, and that you will show the approved plan to the user before implementation. Ask whether to proceed. If the user prefers direct solo implementation, skip this skill and proceed normally.

## Step 4 — Create the team and task list

1. Call `TeamCreate` with name `dev-team`. Never skip this.
2. Create three tasks via `TaskCreate` with dependencies:
   - Task 1: *Analysis & Challenge* — unblocked
   - Task 2: *Implementation* — blocked by Task 1
   - Task 3: *Testing* — blocked by Task 2

## Step 5 — Hand off to the orchestrator doc

Use `Read` to load `<SESSION_DIR>/.claude/teams/dev-team/orchestrator.md` and follow it directly. You (the root session) are the orchestrator. Do not spawn a separate orchestrator agent — spawned agents cannot spawn further agents.

## Step 6 — Tear down

When all phases complete (or on user-requested abort), send `shutdown_request` to every active teammate, then call `TeamDelete` to remove `dev-team`.

## Non-negotiables

- You (the root session) do NOT read source code, write code, propose solutions, review proposals, or write tests yourself. That is the spawned agents' work.
- No agent may write anywhere inside `SESSION_DIR`. It is off-limits to the whole team.
- If any feedback loop exceeds 6 rounds without resolution, stop and escalate to the user — never silently accept the last output.
