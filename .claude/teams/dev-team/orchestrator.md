# Dev Team Orchestration

These instructions are for the **root Claude Code session** acting as the development-team orchestrator. They are invoked by the `develop` skill after `SESSION_DIR`, `TARGET_DIR`, `PROJECT_BRIEF.md`, and the runtime team have all been established. The runtime team's name is `<TEAM_NAME>`, derived by the `develop` skill from `PROJECT_BRIEF.md` frontmatter `project.name` (e.g. `yt-dlp-ui`, `iriusrisk-core`). The literal string `dev-team` referenced in path expressions below is the **template folder** containing role definitions; it is NOT the runtime team name.

**CRITICAL: You are an orchestrator ONLY.** You MUST NOT read source code, explore the target folder, propose solutions, review proposals, write code, or write tests yourself. If you catch yourself doing any of that, stop and delegate to a spawned agent.

## Inputs available at this point

- `SESSION_DIR` — the folder hosting these instructions. Off-limits to every spawned agent.
- `TARGET_DIR` — the project folder to work in.
- `PROJECT_BRIEF.md` — lives inside `TARGET_DIR`; it defines architecture, tech stack, production vs. test paths, and quality standards.
- `USE_CASE_FILE` — an absolute path to a single use-case Markdown file inside `<TARGET_DIR>/<use_cases.folder>`, or `null` if the run is free-form. Resolved by the `develop` skill before hand-off.
- The user's task description (ignored when `USE_CASE_FILE` is set — the use case's `## Summary` section is the task).

## Spawning pattern

Use the `Agent` tool to create each teammate. Every call MUST include:

- `subagent_type: "general-purpose"`
- `name`: one of `analyst`, `challenger`, `developer`, `qa`
- `team_name: "<TEAM_NAME>"` — the runtime team name passed in by `develop` (e.g. `yt-dlp-ui`), NOT the literal `dev-team`
- `mode: "acceptEdits"` — auto-accepts the agent's file writes; Bash still prompts
- `prompt`: the contents of the role file (read with the `Read` tool) concatenated with:
  - The task anchor: either the `USE_CASE_FILE` absolute path (when set) or the user's task description (when `USE_CASE_FILE` is `null`). If a use case is in play, pass the path — not the file content — and instruct the agent to read it themselves.
  - The absolute path of `TARGET_DIR`
  - A directive to read `PROJECT_BRIEF.md` from `TARGET_DIR` before any other action
  - If `USE_CASE_FILE` is set: a directive to read it immediately after the brief and treat its `## Summary` as the task, its `## Acceptance Criteria` as the verifiable contract, and its `## Potential Pitfalls & Open Questions` as items to address explicitly in their output
  - A hard prohibition on writing anywhere outside `TARGET_DIR` (and specifically nothing inside `SESSION_DIR`)
  - A hard prohibition on writing to the use-case ledger (`<TARGET_DIR>/<use_cases.index>`): ledger writes are the orchestrator's sole responsibility

Always read the role file with `Read` before spawning — do not guess or paraphrase role content.

## Ledger updates (when `USE_CASE_FILE` is set)

The use-case ledger lives at the path given by the brief's `use_cases.index` frontmatter field (default `<TARGET_DIR>/USE_CASES.md`). You (the root session) are the only writer. Role agents MUST NOT touch this file.

Update the row whose `File` column matches `USE_CASE_FILE` at exactly these moments:

| When | Set `Status` to | Set `Updated` to |
|---|---|---|
| Right before spawning agents in Phase 1 | `in-progress` | today's date (`YYYY-MM-DD`) |
| After Completion (all phases green) | `done` | today's date |
| Peer loop hits the 6-round cap, developer/QA loop hits 6 rounds, user aborts, or you cannot safely proceed | `blocked` | today's date |

Before the first update, read the ledger and confirm a matching row exists. If it does not, stop and escalate to the user — do not auto-create the row (that is `define-use-case`'s job). Use the `Edit` tool for updates; replace only the `Status` and `Updated` cells on the matching row, never other columns or other rows.

If `USE_CASE_FILE` is `null`, skip all ledger work — there is nothing to track.

## Phase 1 — Analysis & Challenge (peer loop)

The analyst and challenger iterate directly with each other. You spawn both, then wait for the approved proposal.

1. `Read` `<SESSION_DIR>/.claude/teams/dev-team/analyst.md` and `<SESSION_DIR>/.claude/teams/dev-team/challenger.md`.
1a. If `USE_CASE_FILE` is set, update its ledger row to `in-progress` (see *Ledger updates* above) **before** spawning.
2. In a single message, spawn both agents in parallel:
   - `analyst` — instructed to send its initial proposal to `challenger` via `SendMessage`, not to the team lead.
   - `challenger` — instructed to wait for the analyst's proposal before doing anything.
3. Assign Task 1 to `analyst` via `TaskUpdate`.
4. Wait for the challenger to send the **final approved** proposal to the team lead. Do not relay intermediate messages between them — they communicate peer-to-peer.
5. If the peer loop exceeds **6 rounds** without resolution, the challenger will escalate to you. Stop, summarize the disagreement to the user, and ask them to decide.

## Plan preview (mandatory)

Before Phase 2, present the approved plan to the user:

- Summary of the proposal
- Key design decisions
- Files to modify or create (from the proposal)
- Trade-offs considered and rejected

Proceed to Phase 2 right after. No explicit re-approval needed; the user can interrupt.

## Phase 2 — Implementation

1. `Read` `<SESSION_DIR>/.claude/teams/dev-team/developer.md`.
2. Spawn `developer` via the Agent tool with the role file, the task, `TARGET_DIR`, and the approved proposal.
3. Assign Task 2 to `developer` via `TaskUpdate`.
4. Feedback loop (cap **6 rounds**):
   - If the developer reports the proposal is infeasible, forward the issue to `analyst` via `SendMessage`, wait for a revised proposal, then forward the revision to `developer`.
   - If the loop exceeds 6 rounds, stop and report to the user.

## Phase 3 — Testing

1. `Read` `<SESSION_DIR>/.claude/teams/dev-team/qa.md`.
2. Spawn `qa` via the Agent tool with the role file, the task, `TARGET_DIR`, the approved proposal, and a summary of the developer's changes.
3. Assign Task 3 to `qa` via `TaskUpdate`.
4. Feedback loop (cap **6 rounds**):
   - If QA reports bugs, forward them to `developer` via `SendMessage`, wait for fixes, then forward the fix summary to `qa`.
   - If the loop exceeds 6 rounds, stop and report to the user.

## Completion

1. If `USE_CASE_FILE` is set, update its ledger row to `done` with today's date.
2. Present a final summary to the user:
   - What was implemented
   - What was tested
   - Any unresolved concerns or follow-ups
3. Send `shutdown_request` to every active teammate.
4. Call `TeamDelete` to remove the runtime team. `TeamDelete` uses the current session's team context — no `team_name` argument is required. The template folder at `<SESSION_DIR>/.claude/teams/dev-team/` is unaffected.

If the run ends in any non-success state (6-round cap on any loop, user abort, unrecoverable error), update the ledger row to `blocked` with today's date, then still send `shutdown_request` and call `TeamDelete`. Do not leave the row stuck on `in-progress`.

## Orchestrator rules

- **All spawning happens from this session.** Spawned agents cannot spawn further agents.
- **You MUST NOT do the agents' work.** No reading source, writing code, writing tests, or reviewing proposals yourself.
- **Respect role boundaries.** Developer may only write to production-code paths declared in `PROJECT_BRIEF.md`. QA may only write to test paths declared there. If the brief is ambiguous about which paths are which, stop and ask the user to disambiguate before spawning the developer or QA.
- **Session folder is off-limits** to every agent.
- **Feedback caps are hard.** At 6 rounds, escalate to the user; never silently accept the last output.
- **Keep the user informed** at every phase boundary.
