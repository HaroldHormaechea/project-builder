# Dev Team Orchestration

These instructions are for the **root Claude Code session** acting as the development-team orchestrator. They are invoked by the `develop` skill after `SESSION_DIR`, `TARGET_DIR`, `PROJECT_BRIEF.md`, and the runtime team have all been established. The runtime team's name is `<TEAM_NAME>`, derived by the `develop` skill from `PROJECT_BRIEF.md` frontmatter `project.name` (e.g. `yt-dlp-ui`, `iriusrisk-core`). When the run is anchored to a use case, `develop` suffixes the name with the use case's unpadded number — `<project.name>-uc-<N>` (e.g. `yt-dlp-ui-uc-1`, `iriusrisk-core-uc-24`) — so concurrent use-case runs on one project never share a team. Use whatever `develop` passed you verbatim; do not re-derive it. The literal string `dev-team` referenced in path expressions below is the **template folder** containing role definitions; it is NOT the runtime team name.

**CRITICAL: You are an orchestrator ONLY.** You MUST NOT read source code, explore the target folder, propose solutions, review proposals, write code, or write tests yourself. If you catch yourself doing any of that, stop and delegate to a spawned agent.

## Inputs available at this point

- `SESSION_DIR` — the folder hosting these instructions. Off-limits to every spawned agent.
- `TARGET_DIR` — the project folder to work in. When `develop` isolated the run in a git worktree (the default), this is the **worktree path** (`WORKDIR`) with the work branch already checked out; every read, write, build, test, and git operation happens here. It is the user's original checkout only when worktree isolation was skipped.
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
  - If `profile-java-call-graph-tool` is active and `develop` Step 3b ran: the absolute path of the cached jar as `JAVA_CALL_GRAPH_JAR`, with a note that the agent should use the MCP tools prefixed `mcp__java-class-call-scanning__` when present and fall back to the CLI surface against `JAVA_CALL_GRAPH_JAR` otherwise — see the profile SKILL.md for per-role usage

Always read the role file with `Read` before spawning — do not guess or paraphrase role content.

## Team regeneration — always tear down completely first

Any time an issue forces you to regenerate the team — a dead/unrecoverable agent (see *Liveness protocol*), a desynced or corrupted team, crossed inboxes that won't clear, or any situation where re-spawning a single role is not enough — you MUST tear the **entire** team down before recreating it. Never re-spawn one role into a half-broken team: partial regeneration leaves stale teammates, orphaned tasks, and crossed inboxes — the exact silent-stall failure mode this protocol exists to prevent. A clean slate is mandatory.

**Full teardown + recreate routine:**

1. **Tear down completely.** Send `shutdown_request` to **every** active teammate (analyst, challenger, developer, qa — whichever currently exist) and wait for them to drain. Then call `TeamDelete` to remove the runtime team `<TEAM_NAME>`; this clears all teammate state and the task list.
2. **Recreate the team.** `TeamCreate` with `team_name: <TEAM_NAME>` (the same name `develop` passed you — including any `-uc-<N>` suffix), then recreate the three tasks with the same dependencies as `develop` Step 4 (Task 1 *Analysis & Challenge* unblocked; Task 2 *Implementation* blocked by 1; Task 3 *Testing* blocked by 2).
3. **Re-spawn from the interrupted phase**, not blindly from Phase 1:
   - **Phase 1** → re-spawn fresh `analyst` + `challenger`, restart the peer loop from scratch with the same `USE_CASE_FILE` / task description. Discard any partial proposal. The 6-round peer cap resets.
   - **Phase 2** → re-spawn a fresh `developer` with the same approved proposal and a one-line note that this is a restart after a team regeneration. The 6-round developer cap resets.
   - **Phase 3** → re-spawn a fresh `qa` with the same approved proposal and developer change summary. The 6-round QA cap resets.

Count regenerations per role across the run. On the **second** forced regeneration of the same role, do not regenerate again — stop, set the ledger row to `blocked`, run step 1 (full teardown), and escalate to the user.

## Liveness protocol — idle nudge and restart

Spawned agents can go idle silently after receiving a message they should have acted on (an observed wake-up failure mode). To protect the run from indefinite stalls, apply this protocol to **every** spawned agent across all phases — Phase 1 peer loop (analyst, challenger), Phase 2 developer loop, Phase 3 QA loop.

You measure time using the wall-clock timestamps on the `idle_notification` messages that the harness routes to your inbox. Do not run `sleep` commands to gate this — messages and idle notifications arrive asynchronously, so you can do other work and react when notifications land.

For every message you send that requires a substantive reply (initial proposal hand-off, revision request, bug report, fix-back, etc.):

1. **Within 5 minutes of message delivery** the agent should produce a substantive response — a `SendMessage` carrying the expected content (proposal, verdict, changes summary, test summary, fix summary). An `idle_notification` alone does NOT count as a substantive reply.
2. **At the 5-minute mark with no substantive reply**: send a **nudge** to the agent via `SendMessage`. Phrase it as a direct prod, name the message they should be acting on (timestamp it if useful), and ask them to proceed. Reset the 5-minute window from the moment the nudge is delivered.
3. **At the 10-minute mark (5 minutes after the nudge) still no substantive reply**: declare the agent **dead** and recover by running the **full teardown + recreate routine** (see *Team regeneration — always tear down completely first*), resuming from the phase that was interrupted (Phase 1 → re-spawn analyst + challenger; Phase 2 → re-spawn developer; Phase 3 → re-spawn qa). Do **not** surgically re-spawn just the dead role into the surviving team — tear the **whole** team down first, then recreate it. The 6-round cap for the resumed phase resets.
4. If a forced regeneration recurs **twice in the same run** for the same role, stop. Set the ledger row to `blocked`, run the full teardown (`shutdown_request` to every active teammate, then `TeamDelete`), and escalate to the user — repeated liveness failure points at a systemic issue, not a flake.

This protocol applies to all `SendMessage` exchanges. Spawn-time hand-offs count too — the moment you spawn an agent and assign their initial task, the 5/10-minute clock starts on whatever first substantive action you expect from them (typically the analyst's initial proposal or the developer's change summary).

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

## Pre-implementation — Branching

**If `develop` already isolated this run in a worktree** (it passed `WORKDIR` as your `TARGET_DIR` and told you the work branch is already created and checked out), the branch already exists here — set `WORK_BRANCH` to the current branch (`git -C <TARGET_DIR> rev-parse --abbrev-ref HEAD`) and **SKIP the rest of this section**. You cannot check out the default branch inside a worktree anyway. Run the steps below ONLY when working in place (no worktree).

Before spawning the developer in Phase 2, put the work on its own branch. New code MUST NOT land directly on the project's default branch.

1. Read the `vcs` block from `<TARGET_DIR>/PROJECT_BRIEF.md` frontmatter. If `vcs.enabled` is `false` or the field is missing, skip this step entirely — there is no git repo to branch in.
2. Derive `WORK_BRANCH`:
   - When `USE_CASE_FILE` is set: take the filename stem (e.g. `01-foo` from `01-foo.md`) and prefix with `feat/uc-` → `feat/uc-01-foo`.
   - Otherwise: derive a short kebab-case slug from the task description (lowercase, `[a-z0-9-]`, ≤40 chars) and prefix with `feat/` → e.g. `feat/cache-eviction-fix`.
   - If `git -C <TARGET_DIR> rev-parse --verify <branch>` succeeds (branch already exists), append `-2`, `-3`, … until unique.
3. Switch to the project's default branch and sync it with origin before cutting the work branch — the local default branch may be stale (e.g., another sibling branch was just merged on the remote), and a stale base means the work branch starts from old code:
   - `git -C <TARGET_DIR> checkout <vcs.default_branch>`
   - **If `vcs.remote` is set** (non-null, indicating an origin exists):
     - `git -C <TARGET_DIR> fetch origin`
     - `git -C <TARGET_DIR> merge --ff-only origin/<vcs.default_branch>`
     - If the fast-forward fails because the local default branch has diverged from origin (local commits not yet on remote, or non-linear history), STOP and surface the error to the user. Do NOT rebase, reset, force-pull, or otherwise rewrite history — the user's local commits are theirs to manage. Resume after they reconcile.
   - `git -C <TARGET_DIR> checkout -b <WORK_BRANCH>`
4. If any of the commands above fail (dirty working tree blocking checkout, missing default branch, fetch error, fast-forward refusal, etc.), stop and surface the error to the user. Do not try to clean up the tree yourself — the user's uncommitted state is theirs to manage.

Hold `WORK_BRANCH` in mind for the Completion phase. Do not switch branches during Phase 2 or Phase 3 — every developer/QA round happens on `WORK_BRANCH`.

## Phase 2 — Implementation

1. `Read` `<SESSION_DIR>/.claude/teams/dev-team/developer.md`.
2. Spawn `developer` via the Agent tool with the role file, the task, `TARGET_DIR`, and the approved proposal.
3. Assign Task 2 to `developer` via `TaskUpdate`.
4. Feedback loop (cap **6 rounds**):
   - If the developer reports the proposal is infeasible, forward the issue to `analyst` via `SendMessage`, wait for a revised proposal, then forward the revision to `developer`.
   - If the loop exceeds 6 rounds, stop and report to the user.
5. **Handle checkpoint requests from the developer.** See *Handling milestone checkpoints* below for the protocol. Default policy is *commit and push*; the user can opt out at run-time.

## Phase 3 — Testing

1. `Read` `<SESSION_DIR>/.claude/teams/dev-team/qa.md`.
2. Spawn `qa` via the Agent tool with the role file, the task, `TARGET_DIR`, the approved proposal, and a summary of the developer's changes.
3. Assign Task 3 to `qa` via `TaskUpdate`.
4. Feedback loop (cap **6 rounds**):
   - If QA reports bugs, forward them to `developer` via `SendMessage`, wait for fixes, then forward the fix summary to `qa`.
   - If the loop exceeds 6 rounds, stop and report to the user.
5. **Handle checkpoint requests from QA** (and any from the developer during a fix-back round). Same protocol as Phase 2 — see *Handling milestone checkpoints* below.

## Handling milestone checkpoints

The developer and QA request commits at natural milestones via the `CHECKPOINT_REQUEST` protocol documented in `.claude/teams/dev-team/developer.md` § "Milestone checkpoints" and `.claude/teams/dev-team/qa.md`. While they wait for your reply they pause — so respond promptly, even when the answer is "skip".

**Run-level policy.** Decide at the start of Phase 2 (or earlier — see *Run-level checkpoint policy* below) whether intermediate commits are on for this run:

- **`on`** (default): commit + push every checkpoint.
- **`off`**: never commit intermediate work; everything lands in the Completion-phase commit.
- **`ask`**: prompt the user via `AskUserQuestion` the first time a checkpoint arrives, then remember their choice for the rest of the run.

If the user gave an explicit directive at run-start ("commit as you go", "no intermediate commits", "don't push until done"), use it. Otherwise default to `on`.

**On every incoming `CHECKPOINT_REQUEST` message:**

1. Parse the request: subject (line 2), optional body, file list.
2. **Verify the tree is in a sane state** with `git -C <TARGET_DIR> status --short`. If the status is empty, the agent is confused — reply `CHECKPOINT_DEFERRED` with "nothing staged or modified; keep working until you actually have changes to commit". If untracked/staged files are visible that are outside the agent's declared scope (developer touching test paths, QA touching production code, anyone touching `<SESSION_DIR>` — which should be impossible but verify), reply `CHECKPOINT_BLOCKED` with the offending paths and tell them to stop.
3. **Apply the policy:**
   - Policy `off` → reply `CHECKPOINT_SKIPPED` immediately with a one-line acknowledgement. Do nothing on git.
   - Policy `on` → proceed to step 4.
   - Policy `ask` (first checkpoint of the run only) → run `AskUserQuestion` with options "Yes — commit at each milestone" / "No — single commit at the end" / "Ask again later". Persist the answer as the run-level policy. Then act on the new policy.
4. **Commit and push:**
   1. `git -C <TARGET_DIR> add -A` (or stage only the files the agent listed — for a strict policy, stage by path; for the default policy, `-A` is fine since the agent has been instructed to pause work).
   2. `git -C <TARGET_DIR> commit -m "<subject>"` using the agent's proposed subject, with a HEREDOC body if they provided one. Match the repo's commit-message style (no AI footers, no `Co-Authored-By: Claude …` — strip if present).
   3. `git -C <TARGET_DIR> push origin <WORK_BRANCH>`.
   4. On a hook failure during commit, capture the hook output, abort the commit (do NOT `--no-verify`), and reply `CHECKPOINT_BLOCKED` with the hook's message — the agent fixes it and re-requests. Never amend a successful commit.
   5. On a push failure that isn't a hook (network blip, rejected non-fast-forward), reply `CHECKPOINT_BLOCKED` with the error. Do NOT force-push. Investigate before retrying.
5. **Reply** `CHECKPOINT_COMMITTED` to the requesting agent with the new commit's short SHA, so they can resume. The reply is what unblocks them — never forget this step.

**Liveness consideration.** A checkpoint reply is an expected substantive response to a `CHECKPOINT_REQUEST`. If you take longer than the liveness window (5 min nudge, 10 min restart) to reply, you risk the agent being declared dead even though it is correctly paused. Treat checkpoint replies as high-priority; don't queue them behind unrelated work.

**Run-level checkpoint policy.** When spawning the developer in Phase 2, you may surface the policy in the spawn prompt for the user's awareness, but the agent does not need to know it — the agent always requests; only your reply changes. If you defaulted to `on`, mention it in the plan preview so the user can override before implementation starts.

## Completion

1. If `USE_CASE_FILE` is set, update its ledger row to `done` with today's date.
2. **Ship the work** (only when `vcs.enabled` is `true`; otherwise skip this entire step):
   1. Inspect what's still uncommitted: `git -C <TARGET_DIR> status --short`. With intermediate-commit policy `on` (default), most or all of the work is already committed and pushed via checkpoints — only the last slice (post-QA fix-back, untracked docs) typically remains. With policy `off`, *all* the dev-team's work is uncommitted and lands in one commit here.
   2. If there are uncommitted changes, stage them and create a final commit on `WORK_BRANCH`. Match the repo's existing commit style — check `git -C <TARGET_DIR> log --oneline -20` for tone. Use a HEREDOC for multi-line messages. Never `--amend`, never `--no-verify`, never bypass hooks. If the working tree is already clean (everything was committed mid-run via checkpoints), skip the commit step.
   3. Push the branch: `git -C <TARGET_DIR> push -u origin <WORK_BRANCH>` (idempotent — if intermediate checkpoints already pushed, this just no-ops or pushes the final commit on top).
   4. **If the project is on GitHub** — `vcs.remote` contains `github.com` and `gh --version` succeeds — open a pull request:
      - Inspect recent PRs with `gh pr list --limit 5` (run with `cwd: <TARGET_DIR>`) to follow the repo's title/body conventions.
      - Run `gh pr create --base <vcs.default_branch> --head <WORK_BRANCH> --title "<short>" --body "<summary>"` from `<TARGET_DIR>`. Title under 70 chars; body summarizes what was implemented and what was tested. Use a HEREDOC for the body.
      - Print the PR URL to the user.
      - **NEVER merge the PR.** Do not run `gh pr merge`. Do not pass `--auto`, `--squash`, `--rebase`, `--merge`, or any other flag that closes or auto-merges. Merging requires explicit per-PR authorization from the user — wait for them to ask.
   5. **If the project is git-tracked but not on GitHub**: stop after the push. Report the pushed branch name to the user and let them open a PR / MR themselves on whatever forge they use.
3. Present a final summary to the user:
   - What was implemented
   - What was tested
   - The branch name and PR URL (if applicable)
   - Any unresolved concerns or follow-ups
4. Send `shutdown_request` to every active teammate.
5. Call `TeamDelete` to remove the runtime team. `TeamDelete` uses the current session's team context — no `team_name` argument is required. The template folder at `<SESSION_DIR>/.claude/teams/dev-team/` is unaffected.

If the run ends in any non-success state (6-round cap on any loop, user abort, unrecoverable error), update the ledger row to `blocked` with today's date, then still send `shutdown_request` and call `TeamDelete`. Do not leave the row stuck on `in-progress`. Do not push or open a PR for a blocked run — the work is incomplete by definition.

## Orchestrator rules

- **All spawning happens from this session.** Spawned agents cannot spawn further agents.
- **You MUST NOT do the agents' work.** No reading source, writing code, writing tests, or reviewing proposals yourself.
- **Respect role boundaries.** Developer may only write to production-code paths declared in `PROJECT_BRIEF.md`. QA may only write to test paths declared there. If the brief is ambiguous about which paths are which, stop and ask the user to disambiguate before spawning the developer or QA.
- **Session folder is off-limits** to every agent.
- **Feedback caps are hard.** At 6 rounds, escalate to the user; never silently accept the last output.
- **Keep the user informed** at every phase boundary.
