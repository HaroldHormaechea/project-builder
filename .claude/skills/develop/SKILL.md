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

## Step 2b — Resolve the use-case input (optional)

The development team can be anchored to a specific use-case file. Resolve `USE_CASE_FILE` (an absolute path inside `TARGET_DIR`, or `null`) before proceeding:

1. **Invoked via the Skill tool from `define-use-case`**: the caller passes the just-saved file path in the invocation arguments. Use it verbatim, confirm it exists, and skip to Step 3.
2. **Invoked directly by the user without arguments**:
   - Read the frontmatter of `<TARGET_DIR>/PROJECT_BRIEF.md`. If `use_cases.index` resolves to an existing ledger, list the rows whose `Status` is `pending` or `blocked` and offer them to the user via `AskUserQuestion`, plus a "No use case — free-form task" option.
   - If the user picks a use case, set `USE_CASE_FILE` to the absolute path of that file.
   - If the user picks "No use case", set `USE_CASE_FILE = null` and capture the task description from the user as before.
3. **Invoked by the user with an explicit path**: use it verbatim. Confirm it exists and is inside `<TARGET_DIR>/<use_cases.folder>`; refuse otherwise.

If `USE_CASE_FILE` is set, read the file now and use its `## Summary` section as the task description. The file's other sections (acceptance criteria, pitfalls) will be forwarded to the role agents verbatim in Step 5.

## Step 3 — Describe and confirm

Briefly describe the phases (Analysis → Challenge → Plan preview → Implementation → Testing), the 6-round cap on every feedback loop, and that you will show the approved plan to the user before implementation. Ask whether to proceed. If the user prefers direct solo implementation, skip this skill and proceed normally.

## Step 3a — Grant TARGET_DIR-scoped permissions (recommended)

Before spawning agents (which will perform many file writes and bash invocations inside `TARGET_DIR`), prompt the user once to add blanket scoped permissions for that folder to `<SESSION_DIR>/.claude/settings.local.json`. Without this, agent runs accumulate dozens of per-action permission prompts. Permissions are scoped to the target folder only — nothing else on disk is affected.

**Procedure:**

1. Compose the candidate rule set, with `<TARGET_DIR>` substituted to its absolute path (no trailing slash):
   - **a. TARGET_DIR scope (always):**
     - `Edit(//<TARGET_DIR>/**)`
     - `Write(//<TARGET_DIR>/**)`
     - `Read(//<TARGET_DIR>/**)`
     - `Bash(<TARGET_DIR>/:*)` — execute any binary or script under target with any args
     - `Bash(git -C <TARGET_DIR>:*)` — git scoped via the `-C` form (matches the bash convention already enforced by `project-builder.md`)
   - **b. Project commands (loaded from `<TARGET_DIR>/.claude/allowed-commands.yaml` if present):** the file's `commands:` array contains bash command prefixes the dev-team needs (e.g. `cargo`, `dist`, `bats`). Map each entry `<cmd>` to a rule `Bash(<cmd>:*)`. If the file is missing or has no `commands:` key, this set is empty. The developer agent maintains this file across runs (see `.claude/teams/dev-team/developer.md` § "Maintaining `.claude/allowed-commands.yaml`"); QA may also append.

2. Read `<SESSION_DIR>/.claude/settings.local.json` (treat missing-file or missing-keys as `{"permissions":{"allow":[]}}`). Compute the subset of candidate rules NOT already present in `permissions.allow`.

3. If the subset is empty, skip the prompt and proceed to Step 4 — nothing to add.

4. Otherwise, ask the user via `AskUserQuestion`:
   - Question: `Grant the following permissions to <SESSION_DIR>/.claude/settings.local.json for this run? TARGET_DIR-scoped Edit/Write/Read/Bash/git plus project commands declared by the dev team. Avoids per-action prompts.`
   - List the missing rules verbatim in the question body, grouped under "TARGET_DIR scope" and "Project commands", so the user sees exactly what is being added.
   - Options:
     - **Yes — grant all** (Recommended)
     - **No — keep prompting per action**

5. If Yes: append the missing rules to `permissions.allow`, preserving every existing rule. Write the updated JSON back with 2-space indent. Confirm to the user with a one-line summary (`added N rule(s) to .claude/settings.local.json`).

6. If No: proceed without changes. Do not re-prompt within this run.

The step is idempotent: re-running on a project where the rules already exist results in no prompt and no write. To add more commands, the developer agent appends to `<TARGET_DIR>/.claude/allowed-commands.yaml` during the run; the next `/develop` invocation picks them up automatically.

## Step 4 — Derive the team name and create the team + task list

1. Read the YAML frontmatter of `<TARGET_DIR>/PROJECT_BRIEF.md`. The `project.name` field is authoritative — use it verbatim as `TEAM_NAME` (e.g. `yt-dlp-ui`, `iriusrisk-core`). If `project.name` is missing or empty, stop and escalate to the user. Do NOT fall back to a hardcoded default like `dev-team` — that historically caused stale-config collisions across projects.
2. Check whether `~/.claude/teams/<TEAM_NAME>/config.json` already exists. If it does, it is either an active team from a sibling Claude Code session or a stale leftover from a previous unclean run on this project. Read the `description` and `leadSessionId` fields from the config and surface them to the user via `AskUserQuestion`, with options:
   - **Delete and re-create** — only choose if the user confirms the existing team is theirs to discard. Use `Bash` to `rm -rf ~/.claude/teams/<TEAM_NAME> ~/.claude/tasks/<TEAM_NAME>` after explicit user approval.
   - **Abort `develop` run** — bail out cleanly; do not call `TeamCreate`.
   Never silently delete an existing team.
3. Call `TeamCreate` with `team_name: <TEAM_NAME>`. Never skip this.
4. Create three tasks via `TaskCreate` with dependencies:
   - Task 1: *Analysis & Challenge* — unblocked
   - Task 2: *Implementation* — blocked by Task 1
   - Task 3: *Testing* — blocked by Task 2

## Step 5 — Hand off to the orchestrator doc

Use `Read` to load `<SESSION_DIR>/.claude/teams/dev-team/orchestrator.md` and follow it directly. The path stays `dev-team/` because that is the **template folder** containing role definitions — the runtime team name is `<TEAM_NAME>`, not `dev-team`. You (the root session) are the orchestrator. Do not spawn a separate orchestrator agent — spawned agents cannot spawn further agents.

Pass `TEAM_NAME` and `USE_CASE_FILE` (the absolute path, or `null`) into the orchestration. The orchestrator spec explains how to forward `team_name` to each `Agent` spawn and how to update the ledger.

## Step 6 — Tear down

When all phases complete (or on user-requested abort), send `shutdown_request` to every active teammate, then call `TeamDelete` to remove the runtime team (`<TEAM_NAME>`). `TeamDelete` uses the current session's team context — no name argument needed. The template folder at `<SESSION_DIR>/.claude/teams/dev-team/` is unaffected; it is the workspace's role-definition library and is shared across all projects.

## Non-negotiables

- You (the root session) do NOT read source code, write code, propose solutions, review proposals, or write tests yourself. That is the spawned agents' work.
- No agent may write anywhere inside `SESSION_DIR`. It is off-limits to the whole team.
- If any feedback loop exceeds 6 rounds without resolution, stop and escalate to the user — never silently accept the last output.
