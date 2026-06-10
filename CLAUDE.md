# Project Builder

> **Orchestration rule — read first.** The `develop` skill and its four-agent team MUST be invoked from the **root Claude Code session**. Spawned subagents cannot spawn further agents, so nested invocation will fail silently or mid-flow. If you ever find yourself inside a subagent and the user asks for `/develop` (or implementation work), stop and tell them to restart at the root session. The same applies to `/revise-brief` and `/define-use-case` (the latter because it may chain into `/develop`).

This workspace hosts four Claude Code entry points that operate on a **target project folder the user chooses**: the `project-builder` subagent (scaffolds a new project), the `develop` skill (builds features via a small agent team), the `revise-brief` skill (updates an existing brief), and the `define-use-case` skill (captures a single use case as a formalized Markdown file under `<TARGET_DIR>/use-cases/`). Nothing in this workspace is the project itself — it is the tooling that creates and evolves projects.

## Permissions prompt behaviour

Before showing the Step 3a permissions grant prompt (in `develop`, `revise-brief`, or any entry point), check whether the session is running with `--dangerously-skip-permissions`:

```
ps aux | grep "claude.*dangerously-skip-permissions" | grep -v grep
```

If the command returns output, **skip Step 3a entirely** — bypass permissions mode already auto-approves every tool call, so prompting the user to update `.claude/settings.local.json` is redundant. Proceed directly to the next step.

## Hard rules (all entry points)

- Neither entry point may write anywhere inside the folder the current Claude session was launched from (its session working directory). That folder hosts the agent, skills, and team definitions, and is edited by the user directly — never by the spawned agents.
- Everything — including `PROJECT_BRIEF.md` — is written inside the user-supplied target folder.
- `PROJECT_BRIEF.md` is the single source of truth for the target project. Both entry points read it (or produce it), and `develop` refuses to run without one.
- Always resolve the session directory dynamically (e.g., via `pwd`); never hardcode paths, since this workspace may live at different paths on different machines.

## Acquiring a target project's skills

A target project can ship its own skills under `<TARGET_DIR>/.claude/skills/`. Because the Claude session is launched from this workspace (not the target), those project-local skills are not loaded automatically. The **`acquire-project-skills` skill** bridges this: it symlinks each target skill into the user's personal skills folder (`~/.claude/skills/`), which Claude Code watches and hot-reloads, so the project's skills become callable in the current session.

**When it runs.** All four entry points invoke `acquire-project-skills` once `TARGET_DIR` is resolved, before doing their real work (`develop` Step 2d, `define-use-case` Step 2b, `revise-brief` Step 1b; for `project-builder`, the root session runs it when continuing an existing repo that ships skills). It is also user-invocable standalone ("load the skills from project X"). Re-running is idempotent.

**Mechanics.**
- Implementation lives in `.claude/scripts/acquire-project-skills.sh` (link + ledger upsert) and `.claude/scripts/release-project-skills.sh` (unlink + ledger prune + dangling-symlink safety sweep). The skill is a thin wrapper around the acquire script.
- The **ledger** `acquired-project-skills.json` (workspace root, **gitignored**, per-machine) records what was linked, keyed by `(project, session_id)`:
  ```json
  { "acquired-project-skills": [
    { "project": "/abs/path/to/target", "session_id": "<uuid>", "skills": ["/home/<user>/.claude/skills/<name>", ...] }
  ] }
  ```
  Paths are stored absolute (not `~`-prefixed) so the cleanup hook can `rm` them unambiguously. The script tags each entry with `$CLAUDE_CODE_SESSION_ID`, so cleanup is scoped per session even if two sessions run at once.
- **Hooks** (registered in `.claude/settings.json`):
  - `SessionStart` (`hooks/session-start.sh`) ensures `~/.claude/skills/` exists — required, because Claude Code only hot-reloads a personal-skills folder that already existed at session start — and runs `release-project-skills.sh --prune-dangling` to clear orphans left by a previously crashed session.
  - `SessionEnd` (`hooks/session-end.sh`) reads `session_id` from stdin and runs `release-project-skills.sh <session_id>`, removing exactly this session's symlinks and dropping its ledger entries.

**Safety guarantees (enforced by the scripts — do not work around them).**
- Never clobbers an existing entry in `~/.claude/skills/`: a name collision is skipped with a warning, not overwritten.
- Never shadows one of this workspace's own skills: a target skill whose name matches a workspace skill is skipped.
- The release path only ever `rm`s **symlinks** (guarded by a `-L` test); a real file/dir at the same path is left untouched.

**Hot-reload caveat.** Linked skills become callable on the *next turn*, but only if `~/.claude/skills/` existed when the session started. The `SessionStart` hook guarantees this for every session after the tooling is installed; on the first-ever run on a fresh machine the folder may not have existed at start, so a session restart is needed once.

## Entry point 1 — `project-builder` (scaffold)

When the user asks to define, start, plan, or scaffold a new project, **or** when the user asks to clone an existing repo or continue working on an existing project folder:

1. **Ask for and confirm `TARGET_DIR` with the user** (absolute path). Refuse anything inside `SESSION_DIR`. As a default suggestion, offer a sibling of `SESSION_DIR` — i.e., `<parent-of-SESSION_DIR>/<project-name>` (e.g., if `SESSION_DIR` is `/workspace/project-builder`, suggest `/workspace/<project-name>`).
2. **Ensure `TARGET_DIR` exists before spawning the subagent.** If it does not, `mkdir -p <TARGET_DIR>` from the root session (with user approval if prompted). The subagent does NOT hold Bash permissions for paths outside `SESSION_DIR` and will stop and escalate if the folder is missing — that's expected and by design. Creating the folder is the root session's job.
3. **Check for an existing `PROJECT_BRIEF.md` in `TARGET_DIR`.** Before spawning any subagent, check whether `<TARGET_DIR>/PROJECT_BRIEF.md` already exists:
   - **If it exists and is compatible** (has valid YAML frontmatter with `schema_version: 1`): inform the user, show the project name and maturity target from the frontmatter, and ask via `AskUserQuestion` whether to (a) use it as-is and proceed to `develop`, (b) revise one or more sections via `revise-brief`, or (c) re-scaffold from scratch. Do **not** spawn `project-builder` unless the user chooses (c).
   - **If it exists but is missing required fields** (e.g. no frontmatter, missing or unsupported `schema_version`): surface the specific mismatch and ask the user how to proceed (revise or re-scaffold). Do not silently overwrite.
   - **If it does not exist but `TARGET_DIR` already contains files** (e.g., a cloned repo): offer to create one. Before spawning `project-builder`, read the project to extract context — check for `package.json`, `Cargo.toml`, `build.gradle`, `pom.xml`, `pyproject.toml`, `go.mod`, `Makefile`, `Dockerfile`, `docker-compose.*`, `README.md`, `.github/workflows/`, and any other top-level config files. Pass a structured summary of what was found (detected languages, frameworks, build tool, scripts, description from README, CI setup, etc.) to the `project-builder` subagent as pre-populated context, so the define-* skills can skip or pre-fill questions that are already answered by the existing code. Inform the user what was detected before spawning.
   - **If it does not exist and `TARGET_DIR` is empty**: continue to step 4 (normal scaffolding flow with no pre-populated context).
4. **Grant TARGET_DIR-scoped permissions (recommended).** Before spawning, prompt the user via `AskUserQuestion` to add blanket Edit/Write/Read/Bash/git permissions scoped to `<TARGET_DIR>` to `<SESSION_DIR>/.claude/settings.local.json`. Without this, scaffolding accumulates per-bash-command prompts. The exact rule set, the idempotency check, and the JSON-edit procedure are documented in `.claude/skills/develop/SKILL.md` § "Step 3a — Grant TARGET_DIR-scoped permissions"; both entry points use the same routine. Permissions are scoped to the target folder only.
5. **Spawn the `project-builder` subagent via the Agent tool** with:
   - `subagent_type: "project-builder"`
   - `mode: "acceptEdits"` — the agent auto-accepts its own file writes; Bash still prompts for commands not pre-approved in `.claude/settings.local.json`.

The agent always writes/updates `PROJECT_BRIEF.md` in the target folder **before** acting, so its plan is persisted and verifiable.

**Acquire shipped skills.** If `TARGET_DIR` already contains `.claude/skills/` (e.g. an existing repo being continued), the root session invokes `acquire-project-skills` so those skills are usable this session — see § "Acquiring a target project's skills". A brand-new scaffold has none, so this is usually a no-op.

**Bash conventions the subagent follows (documented in `.claude/agents/project-builder.md`):** one `mkdir -p` call per tree, `git -C <TARGET_DIR>` form instead of `cd <TARGET_DIR> && git …`, absolute paths throughout, and no compound `&&`/`;` commands. Low-risk scaffolding Bash verbs (`mkdir`, `git init`, `git branch`, `git remote add`, `git rev-parse`, `git -C …`) are pre-approved in `.claude/settings.local.json` so they do not prompt during a normal scaffold.

**Resume:** if a scaffold is halted mid-flight (e.g., permission denial on a nested command), the subagent supports a resume protocol — just re-invoke it with the same `TARGET_DIR` and it will diff the scaffolding plan against the filesystem and complete only the missing steps.

### Skills invoked by `project-builder`

- `define-overview` — problem, users, value proposition, scope, non-goals, success criteria
- `define-monetization` — business / distribution model, pricing tiers, target market
- `define-technologies` — languages, frameworks, data stores, auth, key libraries (stack-neutral)
- `define-architecture` — platforms, service shape, integrations, data flow
- `define-quality-standards` — linting, testing, security, accessibility, performance budgets
- `define-deployment` — production (cloud, IaC, CI/CD, secrets, observability) and development (local env, containers, seed data)

## Entry point 2 — `develop` (build features)

When the user asks to implement a feature, fix a bug, refactor, or make any code change in an existing target project, invoke the `develop` skill **from the root session**. Do not enter plan mode and do not start exploring manually — the skill replaces that.

This applies to **generic or loosely-phrased requests too** — any ask to implement, build, add, write, fix, debug, refactor, or change a target project's code routes here, not only fully-specified feature requests. Explicit phrasings like "use the agents", "use the team", or "run the dev team" always route here. **If in doubt whether a request warrants the skill, prompt the user** (e.g. "Run the dev-team for this, or handle it directly?") rather than silently proceeding solo.

The skill orchestrates a four-agent team (`analyst`, `challenger`, `developer`, `qa`) with peer review, capped feedback loops, and role-scoped write permissions. Role boundaries are derived from `PROJECT_BRIEF.md` in the target folder — not hardcoded.

When `develop` is triggered **directly** (not chained from a `define-use-case` call), it first offers to formalize a use case before building (`develop` Step 2b): the user can **define a use case first** — which hands off to `define-use-case`, which chains back into `develop` with the saved file — or **go ahead without one** (free-form task, or pick an existing pending/blocked use case). Runs that arrive *from* `define-use-case` (a use-case file is passed in) skip this offer, as do runs invoked with an explicit use-case path.

By default the skill **isolates the run in a fresh git worktree** cut from `TARGET_DIR` on the work branch (`develop` Step 2c), so a concurrent session working in `TARGET_DIR` can't collide on files, index, or branch; the whole team then operates in that worktree (`WORKDIR`). The user can opt out per run ("no worktree" / "work in place"), and it is auto-skipped when the project isn't a git repo. The worktree is left in place until its PR merges (Step 6 offers cleanup).

Must be invoked from the root session: spawned subagents cannot spawn further agents, so nested invocation will fail. If `PROJECT_BRIEF.md` is missing from the target folder, the skill first spawns `project-builder` to generate one, then proceeds.

The runtime team name is `project.name` from the brief; when the run is anchored to a use case it is suffixed with the use case's **unpadded** number — `<project.name>-uc-<N>` (e.g. `yt-dlp-ui-uc-1`, `…-uc-24`) — so concurrent use-case runs never share a team. **Team regeneration is always a complete teardown first:** any time an issue forces regenerating the team (a dead agent, a stale/desynced team), the orchestrator sends `shutdown_request` to every teammate and calls `TeamDelete` before re-creating — it never re-spawns one role into a half-broken team. See `.claude/teams/dev-team/orchestrator.md` § "Team regeneration — always tear down completely first".

### Team definitions (read by the orchestrator, not invoked directly)

- `.claude/teams/dev-team/orchestrator.md` — root-session orchestration instructions
- `.claude/teams/dev-team/analyst.md` / `challenger.md` / `developer.md` / `qa.md` — role definitions

## Entry point 3 — `revise-brief` (evolve the brief)

When the user wants to update one or more sections of an existing `PROJECT_BRIEF.md` without re-scaffolding, invoke the `revise-brief` skill from the root session. It picks the sections to refresh, re-runs the matching `define-*` skills via `project-builder`, and keeps the YAML frontmatter in sync.

## Entry point 4 — `define-use-case` (capture a use case)

When the user wants to document what the project should do — one use case at a time — invoke the `define-use-case` skill from the root session. It collects a free-form description, produces a formalized version (summary, acceptance criteria, pitfalls), runs a clarifying-question loop via `AskUserQuestion`, then saves the result as `<TARGET_DIR>/use-cases/<NN>-<slug>.md` with a zero-padded incremental number. After saving, it offers to define another use case or continue to implementation via `develop`.

The skill never modifies `PROJECT_BRIEF.md`. Use cases live alongside the brief, not inside it.

## `PROJECT_BRIEF.md` schema

Every `PROJECT_BRIEF.md` starts with a YAML frontmatter block that agents read for structured fields. The prose sections below the frontmatter are for humans; the frontmatter is authoritative for machine-read fields.

```yaml
---
schema_version: 1
project:
  name: <string>
  maturity_target: prototype | mvp | production
stack:
  languages: [<string>, ...]
  frameworks: [<string>, ...]
  runtimes: [<string>, ...]
  versions: {<tool>: <string>, ...}   # e.g. {java: "21", gradle: "8.9", spring_boot: "3.3.2"}
  data_stores: [<string>, ...]
build:
  tool: <string>                       # gradle, maven, npm, pnpm, cargo, uv, ...
  commands: {test: <string>, lint: <string>, format: <string>}
paths:
  production: [<glob>, ...]
  test: [<glob>, ...]
  api_boundary: [<glob>, ...]          # optional; for profile-java-server-architecture
test:
  framework: <string>
  levels: [unit, integration, e2e]
  coverage_target: <string>
profiles: [<skill-name>, ...]
deployment:
  provider: <string>
  iac: <string>
  environments: [<string>, ...]
vcs:
  enabled: <bool>                      # whether the target folder should be a git repo
  already_initialized: <bool>          # true if TARGET_DIR was already inside a git work tree before scaffolding
  default_branch: <string>             # e.g. "main"
  remote: <string>                     # origin URL, or null if none yet
use_cases:
  index: <string>                      # relative path from TARGET_DIR to the status ledger, default "USE_CASES.md"
  folder: <string>                     # relative path from TARGET_DIR to the use-case files, default "use-cases/"
---
```

**Ownership (which skill writes which fields):**

| Frontmatter field | Skill / step |
|---|---|
| `project.*` | `define-overview` |
| `stack.*`, `build.*` | `define-technologies` |
| `paths.*` | `define-architecture` |
| `test.*`, `profiles` | `define-quality-standards` |
| `deployment.*` | `define-deployment` |
| `vcs.*` | `project-builder` scaffolding step (not a define-* skill) |
| `use_cases.*` | `define-use-case` (first invocation in a project) |

Agents MUST prefer the frontmatter over prose for any structured read. Prose is for context; the frontmatter is the contract. If a field is missing or contradicts the prose, the agent stops and surfaces the mismatch rather than guessing.

## Use-case ledger (`USE_CASES.md`)

Every target project that has at least one use case also has a **status ledger** at the path given by `use_cases.index` (default `USE_CASES.md`, living at the root of `TARGET_DIR`). It is a single Markdown file with exactly this shape:

```markdown
# Use Cases

Status ledger for use cases under `<use_cases.folder>`. Machine-maintained — the `define-use-case` skill appends rows; the dev-team orchestrator updates the `Status` and `Updated` columns as it works. Do not hand-edit those two columns unless you know why; edit the use-case file or re-run the skill instead.

Statuses:
- `pending` — saved but not yet picked up by the dev-team
- `in-progress` — the dev-team has started analysis
- `done` — implementation and tests completed
- `blocked` — the dev-team escalated (6-round cap hit, user abort, or infeasibility)

| # | File | Title | Status | Updated |
|---|------|-------|--------|---------|
| 01 | [use-cases/01-foo.md](use-cases/01-foo.md) | Foo ingestion | pending | 2026-04-24 |
```

**Write ownership:**

| Part of the ledger | Writer |
|---|---|
| File creation + header + column layout | `define-use-case` (first save in a project) |
| New rows (`#`, `File`, `Title`, initial `Status: pending`, initial `Updated`) | `define-use-case` (every save) |
| `Status` + `Updated` columns on existing rows | dev-team orchestrator (root session during `develop`) |

Role agents (analyst, challenger, developer, qa) MUST NOT write to the ledger. Their scope is the project codebase; ledger mutation is a single-writer responsibility held by the root session during a `develop` run.

If the ledger is missing when the orchestrator needs to update it (e.g., the use-case file was moved in by hand), the orchestrator stops and escalates — it does not silently create or repair the ledger. Ledger creation belongs to `define-use-case`.

## Release notes (`generate-release`)

Whenever a release is cut for a target project (any release tag and its release workflow — a single-track `v*`, or per-component tracks each with their own tag prefix), the release description MUST be produced by the **`generate-release` skill** — never by reusing the previous release's body (that is how stale notes accumulate, e.g. a release repeating the same change for many versions). The skill derives notes solely from the commit / PR / use-case diff since the previous tag of that track, and writes two bullet sections to the GitHub release: **New features** (each bullet ≤ 200 words) and **Bugfixes** (each bullet ≤ 50 words), with every bullet linking to the use case(s) it came from (or its PR/commit when no use case applies). Release tracks and their path scoping are read from the target's `PROJECT_BRIEF.md` (or inferred), never hardcoded in this workspace. It writes only the release *description* — tag creation and the release build stay with the release command / orchestrator. It is also user-invocable standalone to (re)write the notes of an existing release. For multi-track repos, run it once per track being released, each scoped to its own paths.

## Profile skills (opt-in conventions)

Profiles are opinionated skills under `.claude/skills/profile-*/SKILL.md` that encode conventions for a specific stack, tool, or problem area. They are **opt-in per project**: a profile applies only when `PROJECT_BRIEF.md` → `## Profiles` lists its skill name. Profile descriptions explicitly instruct agents not to auto-invoke outside this mechanism.

**Precedence (highest to lowest):**

1. `PROJECT_BRIEF.md` — project-specific standards always win.
2. Active profiles — apply where the brief is silent.
3. Model defaults — fallback when neither speaks.

If an active profile conflicts with the brief, the brief wins and the agent surfaces the conflict rather than choosing silently.

**Current profiles in this workspace:**

- `profile-java-database-access` — DTO projections over entity queries; bulk over iterative; parameterized queries only; Hibernate as JPA implementation.
- `profile-java-server-architecture` — Gradle (latest stable), Spring Boot (latest stable), Java (latest LTS); repositories return DTOs only; internal DTOs never cross the API boundary; strict Controller/Job → Facade → Service → Repository call chain with transactions owned by the facade.
- `profile-java-call-graph-tool` — Provisions the `java-class-call-scanning` bytecode call-graph analyzer for the dev-team. `develop` Step 3b downloads the latest release jar to a per-user cache and writes an MCP server entry to `<TARGET_DIR>/.mcp.json`; agents use the nine query operations (find-callers, find-callees, methods-in-class, methods-at-line, find-field-readers, find-field-writers, impact-of-diff, tests-for-diff, refresh-index) either through MCP tools (when the session loaded the `.mcp.json`) or through the CLI surface against the cached jar.
- `profile-aws-deployment` — AWS as the preferred cloud provider; every AWS-based suggestion must include a cost estimation table (per-service daily / monthly / yearly, with cumulative totals across new and pre-existing services).

## Permissions model

- Normal sessions in this workspace run with `defaultMode: "default"` — no blanket auto-accept. You can freely edit the agent and skill definitions as a normal user of this session; prompts behave as in any Claude Code project.
- Broader permissions apply **only** to the `project-builder` subagent, and only because it is invoked with `mode: "acceptEdits"`. The parent session is unaffected.
- **TARGET_DIR-scoped grant (runtime, opt-in).** Both entry points (`project-builder` Entry Point 1 step 3, and `develop` skill Step 3a) prompt the user once at the start of a run to add blanket Edit/Write/Read/Bash/git permissions scoped to the chosen `TARGET_DIR` to `.claude/settings.local.json`. The grant is per-target and additive; it does not loosen permissions for any other folder. The single source of truth for the rule set, the idempotency check, and the JSON-edit procedure is `.claude/skills/develop/SKILL.md` § "Step 3a". The `revise-brief` and `define-use-case` flows inherit the grant transitively (they spawn `project-builder` or `develop`, which run the routine).
- **Project-specific commands (`<TARGET_DIR>/.claude/allowed-commands.yaml`).** Each target project keeps a YAML ledger of bash command prefixes the dev-team needs (e.g. `cargo`, `dist`, `bats`, `npm test`). The developer agent maintains it; QA may append. The `develop` skill's Step 3a reads the file and merges `Bash(<prefix>:*)` rules into the same one-shot permission prompt as the TARGET_DIR-scoped rules. Format and maintenance protocol are documented in `.claude/teams/dev-team/developer.md` § "Maintaining `.claude/allowed-commands.yaml`".

## Scope today

Structure-only scaffolding, use-case capture (one formalized file per use case under `<TARGET_DIR>/use-cases/`), and feature-development via the dev-team. `define-use-case` chains directly into `develop` with the just-saved file as the implementation target, so the single-use-case-to-implementation flow works end-to-end.

Still pending:
- No batch "implement all pending use cases" mode — each use case is a separate `develop` run. Status tracking makes batch feasible later, but it is not built today.
