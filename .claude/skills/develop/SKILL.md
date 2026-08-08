---
name: develop
description: Development workflow using an agent team (Analyst, Challenger, Developer, QA) to implement features, bug fixes, or refactors in a target project folder. Requires a PROJECT_BRIEF.md in the target folder; if missing, invokes project-builder first to generate one. Use BEFORE entering plan mode whenever the user asks for a code change in an external project. MUST be invoked whenever the user asks — even generically — to implement, build, add, fix, refactor, or "use the agents" / "use the team" on a target project, not only for fully detailed requests. If in doubt whether a request warrants this skill, prompt the user rather than silently proceeding solo.
---

# Development Team Workflow

Entry point for any implementation task (new feature, bug fix, refactor, or other code change) in a target project. Replaces plan mode and manual exploration. The workflow is orchestrated by the root session with four specialized agents.

## When to invoke

Invoke this skill — do not implement solo — whenever the user asks for code work on a target project, **including generic or loosely-phrased requests**. Triggers are not limited to detailed feature specs; they include:

- Any request to **implement, build, add, write, fix, debug, refactor, or change** code in a target project, however briefly worded.
- Explicit requests to **"use the agents"**, "use the team", "run the dev team", "have the agents do it", or similar — these always route here.

**If in doubt, prompt the user** (e.g. "Want me to run the dev-team for this, or handle it directly?") rather than silently proceeding solo. Default toward invoking the skill when the request plausibly involves changing a target project's code.

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
2. Ask the user for the target project folder (`TARGET_DIR`) as an absolute path. Derive a default suggestion by computing the parent of `SESSION_DIR` and appending a project-name placeholder: `<parent-of-SESSION_DIR>/<project-name>` (e.g., `/workspace/my-project` when `SESSION_DIR` is `/workspace/project-builder`). Present this default explicitly. Resolve relative paths with `cd <path> && pwd` and confirm.
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

1. **Invoked via the Skill tool from `define-use-case`**: the caller passes the just-saved file path in the invocation arguments. Use it verbatim, confirm it exists, and skip to Step 3. The use case was *just* defined, so do **not** run the "define a use case first?" offer below.
2. **Invoked directly by the user without arguments**:
   - **Offer to define a use case first.** Because this run did **not** originate from a `define-use-case` call, ask the user via `AskUserQuestion` before resolving anything else:
     - Question: `This run didn't come from a use-case definition. Define a use case first, or go straight to implementation?`
     - Options:
       - **Define a use case first** — formalize the work as a use case before building. Choose this when the task is non-trivial or under-specified and would benefit from acceptance criteria.
       - **Go ahead without one** — proceed straight to implementation as a free-form task (or pick an existing pending/blocked use case below).
     - If the user picks **Define a use case first**: invoke the `define-use-case` skill via the `Skill` tool, passing the resolved `TARGET_DIR`. That skill captures and saves the use case, then (via its Step 7 "Continue to implementation") chains back into `develop` with the saved file as the use-case argument — which lands in branch 1 above and skips this offer. **Hand off and stop the current `develop` flow here**; the chained invocation continues from Step 2c onward. Do not also run the free-form resolution below.
     - If the user picks **Go ahead without one**: continue with the resolution below.
   - Read the frontmatter of `<TARGET_DIR>/PROJECT_BRIEF.md`. If `use_cases.index` resolves to an existing ledger, list the rows whose `Status` is `pending` or `blocked` and offer them to the user via `AskUserQuestion`, plus a "No use case — free-form task" option.
   - If the user picks a use case, set `USE_CASE_FILE` to the absolute path of that file.
   - If the user picks "No use case", set `USE_CASE_FILE = null` and capture the task description from the user as before.
3. **Invoked by the user with an explicit path**: use it verbatim. Confirm it exists and is inside `<TARGET_DIR>/<use_cases.folder>`; refuse otherwise. The user pointed at an existing use case, so skip the "define a use case first?" offer.

If `USE_CASE_FILE` is set, read the file now and use its `## Summary` section as the task description. The file's other sections (acceptance criteria, pitfalls) will be forwarded to the role agents verbatim in Step 5.

## Step 2c — Isolate the run in a fresh git worktree (default)

By **default**, `develop` runs the whole team inside a **new git worktree** cut from `TARGET_DIR` on the work branch — never in `TARGET_DIR`'s own checkout. This isolates the run so a second Claude session (or the user) working in `TARGET_DIR` at the same time cannot collide on files, the index, or the branch. Define `WORKDIR` — the run's effective working folder — and use it in **every** later step (2d, 3a, 3b, 4, 5, the orchestrator's phases, Completion) wherever those steps say `TARGET_DIR` as the place to read, write, build, test, or run git. `WORKDIR` equals `TARGET_DIR` only when worktree isolation is skipped (below). The brief, use-case files, and ledger all live inside `WORKDIR` because a worktree is a full checkout.

**Skip worktree creation (work in place, `WORKDIR = TARGET_DIR`) only when:**
- `PROJECT_BRIEF.md` frontmatter `vcs.enabled` is `false` or absent — there is no git repo to branch.
- The user asked to avoid it this run — e.g. "no worktree", "work in place", "use the existing folder", "don't isolate". Honor an explicit opt-out; do not re-prompt.
- `TARGET_DIR` is already a dedicated, non-default-branch worktree the user pointed you at for this work (`git -C <TARGET_DIR> rev-parse --is-inside-work-tree` is true and its checked-out branch is not `vcs.default_branch`). The isolation already exists — reuse it as `WORKDIR`.

**Create the worktree (default path):**
1. Derive `WORK_BRANCH` exactly as the orchestrator's *Pre-implementation — Branching* section does: use-case stem → `feat/uc-<stem>`; else a ≤40-char kebab slug of the task → `feat/<slug>`; append `-2`, `-3`… until `git -C <TARGET_DIR> rev-parse --verify <branch>` fails (unique).
2. Choose `WORKDIR` as a sibling of `TARGET_DIR`: `<parent-of-TARGET_DIR>/<basename-of-TARGET_DIR>-<branch-leaf>`, where `<branch-leaf>` is the segment of `WORK_BRANCH` after the last `/`. Refuse any path that equals, contains, or sits inside `SESSION_DIR`; pick another sibling name on collision.
3. Sync the base and add the worktree on the new branch:
   - When `vcs.remote` is set: `git -C <TARGET_DIR> fetch origin`; base = `origin/<vcs.default_branch>`.
   - Otherwise base = local `<vcs.default_branch>`.
   - `git -C <TARGET_DIR> worktree add <WORKDIR> -b <WORK_BRANCH> <base>`.
   - If a worktree for this branch/path already exists (a re-run), reuse it (`git -C <TARGET_DIR> worktree list` to detect) rather than failing — this keeps re-runs idempotent.
4. The work branch is now **already created and checked out** in `WORKDIR`. Record this for Step 5 so the orchestrator SKIPS cutting a branch in *Pre-implementation — Branching* (you cannot check out the default branch inside a worktree anyway).
5. Inform the user in one line: the run is isolated in `<WORKDIR>` on `<WORK_BRANCH>`; `TARGET_DIR` is left untouched; the worktree stays until the PR is merged (Step 6 offers cleanup).

## Step 2d — Acquire the target project's skills

If `<WORKDIR>/.claude/skills/` exists, invoke the `acquire-project-skills` skill via the `Skill` tool, passing the resolved `WORKDIR`, so any skills the project ships become usable in this session. It symlinks them into `~/.claude/skills/`, records them in the gitignored ledger, and the `SessionEnd` hook removes them on exit. Skip silently if the folder is absent (most freshly scaffolded projects have none). See CLAUDE.md § "Acquiring a target project's skills".

## Step 2e — Resolve the implementation-plan artifact and offer recovery

Every run persists the analyst↔challenger **approved proposal** to a single Markdown file — the **implementation plan** — which becomes the fixed source of truth for what the developer and QA build, and the recovery anchor if the run is interrupted (Claude quota exhausted, session terminated mid-flight). Resolve its deterministic path `PLAN_FILE` now, before creating the team. The orchestrator writes it (Step 5 / `orchestrator.md` § "Implementation plan artifact"); `develop` only resolves the path and decides whether to resume.

1. **Derive `PLAN_FILE`** (an absolute path inside `WORKDIR`):
   - **When `USE_CASE_FILE` is set**: under a `plans/` subfolder of the brief's `use_cases.folder` (frontmatter, default `use-cases/`), named after the use-case filename stem → `<WORKDIR>/<use_cases.folder>/plans/<stem>.md` (e.g. `…/use-cases/plans/01-foo.md`). The plan sits beside the use case it implements.
   - **When `USE_CASE_FILE` is `null`** (free-form): `<WORKDIR>/.dev-team/plans/<leaf>.md`, where `<leaf>` is the segment of `WORK_BRANCH` (Step 2c) after the last `/`. When no work branch exists (vcs disabled / worktree skipped on a non-repo), derive `<leaf>` as a ≤40-char kebab slug of the task description — the same slug logic used for branch derivation.
2. **Check whether `PLAN_FILE` already exists.** Because the orchestrator only writes it *after* the challenger approves, its presence means a previously-approved plan for this exact use case / branch survived a prior, interrupted run.
   - **If it exists**: read it, show the user its header (the use case / branch it covers and the date it was approved) plus a one-line summary, then ask via `AskUserQuestion`:
     - Question: `An approved implementation plan already exists for this work at <PLAN_FILE>. Resume from it, or regenerate it from scratch?`
     - Options:
       - **Resume from the saved plan** (Recommended) — skip the analyst/challenger phase entirely and implement the persisted plan. Recovers partial work after an interrupted run.
       - **Regenerate from scratch** — re-run the analyst/challenger loop; the freshly approved plan overwrites the file.
     - On **Resume**: set `RESUME_FROM_PLAN = true`. On **Regenerate**: set `RESUME_FROM_PLAN = false`.
   - **If it does not exist**: set `RESUME_FROM_PLAN = false`. The orchestrator creates `PLAN_FILE` after Phase 1.

The plan file lives inside `WORKDIR`, so it is staged, committed, and pushed with the rest of the work (it travels with the PR) — see `orchestrator.md` § "Implementation plan artifact".

## Step 3 — Describe and confirm

Briefly describe the phases (Analysis → Challenge → Plan preview → Implementation → Testing), the 6-round cap on every feedback loop, and that you will show the approved plan to the user before implementation. Mention that the approved plan is persisted to `PLAN_FILE` (Step 2e) as a recoverable source of truth committed with the work, and — when resuming from an existing plan — that the analyst/challenger phase is skipped. Also note that the run is isolated in a fresh git worktree by default (Step 2c) — `TARGET_DIR` is left untouched — and that they can ask to work in place instead. Ask whether to proceed. If the user prefers direct solo implementation, skip this skill and proceed normally.

## Step 3a — Grant TARGET_DIR-scoped permissions (recommended)

Before spawning agents (which will perform many file writes and bash invocations inside `WORKDIR`), first invoke the `check-permissions-mode` skill via the `Skill` tool.

If it reports bypass permissions is **ON**, **skip this entire step** — bypass permissions mode auto-approves every tool call, so adding rules to `settings.local.json` is unnecessary. Proceed directly to Step 4.

**Scope to `WORKDIR`.** Everywhere `<TARGET_DIR>` appears in the rules below, substitute `WORKDIR` (the worktree from Step 2c) — that is where the agents actually write and run git. When isolation was skipped, `WORKDIR` = `TARGET_DIR` and the rules are unchanged.

Otherwise, prompt the user once to add blanket scoped permissions for that folder to `<SESSION_DIR>/.claude/settings.local.json`. Without this, agent runs accumulate dozens of per-action permission prompts. Permissions are scoped to the target folder only — nothing else on disk is affected.

**Procedure:**

1. Compose the candidate rule set, with `<TARGET_DIR>` substituted to its absolute path (no trailing slash):
   - **a. TARGET_DIR scope (always):**
     - `Edit(//<TARGET_DIR>/**)`
     - `Write(//<TARGET_DIR>/**)`
     - `Read(//<TARGET_DIR>/**)`
     - `Bash(<TARGET_DIR>/:*)` — execute any binary or script under target with any args
     - `Bash(git -C <TARGET_DIR>:*)` — git scoped via the `-C` form (matches the bash convention already enforced by `project-builder.md`)
     - `Bash(gh pr create:*)` — open a PR at Completion when the remote is GitHub
     - `Bash(gh pr view:*)`, `Bash(gh pr list:*)` — read-only PR inspection (style-match recent PRs, surface the new PR URL)
     - `Bash(gh auth status:*)` — verify gh is authenticated before attempting `pr create`
     - Note the deliberate omissions: `gh pr merge`, `gh pr close`, and `gh pr edit` are NOT included. Merging or closing a PR requires explicit per-PR user authorization (see `.claude/teams/dev-team/orchestrator.md` § "Completion").
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

## Step 3b — Provision the Java call-graph tool (when profile is active)

Skip this step entirely unless `PROJECT_BRIEF.md` → frontmatter `profiles` list contains `profile-java-call-graph-tool`. The full contract this step honours is in `.claude/skills/profile-java-call-graph-tool/SKILL.md` — read it once before running the procedure below.

When the profile IS active, run the following before Step 4. **All paths, builds, and the `.mcp.json` in this step are under `WORKDIR` (the worktree from Step 2c), not the original `TARGET_DIR`** — substitute `WORKDIR` for `TARGET_DIR` throughout:

1. **Resolve cache directory.** Pick the per-OS path:
   - Linux / Unix: `${XDG_CACHE_HOME:-$HOME/.cache}/project-builder/java-class-call-scanning/`
   - macOS: `$HOME/Library/Caches/project-builder/java-class-call-scanning/`
   - Windows: `%LOCALAPPDATA%\project-builder\java-class-call-scanning\`

2. **Resolve the latest release.** `WebFetch https://api.github.com/repos/HaroldHormaechea/java-class-call-scanning/releases?per_page=1`. Parse the first entry's `tag_name` (e.g. `v0.1.1`) and the asset whose `name` is `java-class-call-scanning.jar` — its `browser_download_url` is the file to fetch. Do NOT use `/releases/latest` — every release today is marked `prerelease: true` and `/latest` excludes those (currently 404s).

3. **Ensure the jar is cached.** Target path: `<cache-dir>/<tag-name>/java-class-call-scanning.jar`. If it exists and has non-zero size, reuse it. Otherwise `mkdir -p <cache-dir>/<tag-name>` and download via `curl -fsSL -o <target-path> <browser_download_url>`. On failure: surface the error to the user, fall back to the most recent already-cached version if any, otherwise stop and ask the user to resolve connectivity.

4. **Resolve TARGET_DIR's compiled-classes and source paths.** Read `PROJECT_BRIEF.md` frontmatter:
   - If the brief has a `tooling.java_call_graph` block with `classpath` and `src` lists, use those verbatim (interpret each entry as relative to `TARGET_DIR`).
   - Otherwise, infer from `build.tool`:
     - `gradle` → classpath `build/classes/java/main`, `build/classes/java/test`; src `src/main/java`, `src/test/java`
     - `maven` → classpath `target/classes`, `target/test-classes`; src `src/main/java`, `src/test/java`
     - any other value → stop and escalate to the user; do not guess.

5. **Build the project so the daemon has bytecode to scan.** Use the brief's declared build for compile-only output:
   - `gradle` → `./gradlew build -x test` from `TARGET_DIR`
   - `maven` → `mvn -DskipTests test-compile` from `TARGET_DIR`
   If the brief defines `tooling.java_call_graph.build`, use that command verbatim instead. If the build fails, surface the failure and stop — this is not a tool problem to mask.

6. **Verify the inferred classpath paths exist** under `TARGET_DIR` after the build. If any do not, stop and escalate — the brief's build.tool likely does not match the actual project layout.

7. **Write or update `<TARGET_DIR>/.mcp.json`.** Add a `mcpServers.java-class-call-scanning` entry with the exact shape documented in `profile-java-call-graph-tool/SKILL.md` § "MCP server registration", filling in the cached jar's absolute path and the resolved classpath/src absolute paths. If the file does not exist, create it with `{"mcpServers": {...}}`. If it exists and already has a `java-class-call-scanning` entry that matches the resolved paths, leave it untouched. If it has a `java-class-call-scanning` entry with different paths, surface the conflict to the user and stop — do not silently overwrite.

8. **Inform the user about the session-restart caveat — concrete wording.** Emit a short note to the user, with these three points called out explicitly so they can act on them:

   > Provisioned `java-class-call-scanning` <tag> at `<cached-jar-path>` and wrote the MCP entry to `<TARGET_DIR>/.mcp.json`.
   >
   > **This run uses the CLI fallback** — Claude Code loads MCP servers at session start, so the new entry is not live in the current session. Role agents will invoke the same nine operations against the cached jar over bash/TCP; results are identical to the MCP path, just one extra subprocess per query.
   >
   > **The MCP path will be ready on your next session.** If you'd prefer MCP tools for subsequent `/develop` runs (cleaner tool-use traces, no per-query bash hop), start a fresh Claude Code session inside `<TARGET_DIR>` — the entry in `.mcp.json` is loaded automatically. Current run continues as-is; no restart needed now.

   Then surface the cached jar's absolute path so the orchestrator and spawned agents have it.

9. **Forward the cached jar path to the orchestrator.** Hold the absolute path of the cached jar as `JAVA_CALL_GRAPH_JAR`. The orchestrator (Step 5) will include it in each agent's spawn prompt so the agents know where to find the binary when falling back to CLI mode.

## Step 4 — Derive the team name and create the team + task list

1. Read the YAML frontmatter of `<WORKDIR>/PROJECT_BRIEF.md`. The `project.name` field is authoritative — use it as the team-name base (e.g. `yt-dlp-ui`, `iriusrisk-core`). If `project.name` is missing or empty, stop and escalate to the user. Do NOT fall back to a hardcoded default like `dev-team` — that historically caused stale-config collisions across projects. Then derive `TEAM_NAME`:
   - **If `USE_CASE_FILE` is set**, suffix the base with the use case's number, **unpadded**: take the numeric prefix of the use-case filename stem (e.g. `01` from `01-foo.md`, `24` from `24-bar.md`), strip leading zeros, and append `-uc-<N>` → `TEAM_NAME = <project.name>-uc-<N>` (e.g. `yt-dlp-ui-uc-1`, `iriusrisk-core-uc-24`). This keeps concurrent use-case runs on the same project from sharing — and colliding on — one team.
   - **If `USE_CASE_FILE` is `null`** (free-form task), `TEAM_NAME = <project.name>` with no suffix.
2. Check whether `~/.claude/teams/<TEAM_NAME>/config.json` already exists. If it does, it is either an active team from a sibling Claude Code session or a stale leftover from a previous unclean run on this project. Read the `description` and `leadSessionId` fields from the config and surface them to the user via `AskUserQuestion`, with options:
   - **Tear down and re-create** — only choose if the user confirms the existing team is theirs to discard. Tear it down **completely** first: send `shutdown_request` to any teammate still registered under it, then use `Bash` to `rm -rf ~/.claude/teams/<TEAM_NAME> ~/.claude/tasks/<TEAM_NAME>` after explicit user approval. Only then proceed to `TeamCreate`. Never re-create on top of a partially-present team — a clean slate is mandatory (see `.claude/teams/dev-team/orchestrator.md` § "Team regeneration — always tear down completely first").
   - **Abort `develop` run** — bail out cleanly; do not call `TeamCreate`.
   Never silently delete an existing team.
3. Call `TeamCreate` with `team_name: <TEAM_NAME>`. Never skip this.
4. Create three tasks via `TaskCreate` with dependencies:
   - Task 1: *Analysis & Challenge* — unblocked
   - Task 2: *Implementation* — blocked by Task 1
   - Task 3: *Testing* — blocked by Task 2

## Step 5 — Hand off to the orchestrator doc

Use `Read` to load `<SESSION_DIR>/.claude/teams/dev-team/orchestrator.md` and follow it directly. The path stays `dev-team/` because that is the **template folder** containing role definitions — the runtime team name is `<TEAM_NAME>`, not `dev-team`. You (the root session) are the orchestrator. Do not spawn a separate orchestrator agent — spawned agents cannot spawn further agents.

Pass `TEAM_NAME`, `USE_CASE_FILE` (the absolute path, or `null`), `WORKDIR`, `PLAN_FILE` (the implementation-plan path from Step 2e), and `RESUME_FROM_PLAN` (boolean) into the orchestration. **The orchestrator uses `WORKDIR` as its `TARGET_DIR`** — every read, write, build, test, ledger update, agent spawn path, and git operation happens in `WORKDIR`. When `RESUME_FROM_PLAN` is true, the orchestrator skips the analyst/challenger phase and implements the plan already saved at `PLAN_FILE`. If Step 2c created a worktree, also tell the orchestrator the work branch `<WORK_BRANCH>` is **already created and checked out** in `WORKDIR`, so it MUST skip the in-place branch-cut in its *Pre-implementation — Branching* section. The orchestrator spec explains how to forward `team_name` to each `Agent` spawn and how to update the ledger.

## Step 6 — Tear down

When all phases complete (or on user-requested abort), send `shutdown_request` to every active teammate, then call `TeamDelete` to remove the runtime team (`<TEAM_NAME>`). `TeamDelete` uses the current session's team context — no name argument needed. The template folder at `<SESSION_DIR>/.claude/teams/dev-team/` is unaffected; it is the workspace's role-definition library and is shared across all projects.

**Worktree cleanup (when Step 2c created one).** Leave the worktree in place until its branch is no longer needed — the open PR depends on the pushed branch, and the user may want to inspect or iterate locally before merge. Never remove it before Completion has pushed the branch. After the PR is open, tell the user the worktree exists at `<WORKDIR>` on `<WORK_BRANCH>` and offer to remove it (`git -C <TARGET_DIR> worktree remove <WORKDIR>` — add `--force` if it holds untracked build artifacts — then `git -C <TARGET_DIR> worktree prune`). Default to keeping it until the user confirms the PR is merged; never delete the branch itself (the PR needs it). On a blocked/aborted run, keep the worktree so the user can inspect the partial work.

## Non-negotiables

- You (the root session) do NOT read source code, write code, propose solutions, review proposals, or write tests yourself. That is the spawned agents' work.
- No agent may write anywhere inside `SESSION_DIR`. It is off-limits to the whole team.
- If any feedback loop exceeds 6 rounds without resolution, stop and escalate to the user — never silently accept the last output.
