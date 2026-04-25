# Project Builder

> **Orchestration rule — read first.** The `develop` skill and its four-agent team MUST be invoked from the **root Claude Code session**. Spawned subagents cannot spawn further agents, so nested invocation will fail silently or mid-flow. If you ever find yourself inside a subagent and the user asks for `/develop` (or implementation work), stop and tell them to restart at the root session. The same applies to `/revise-brief` and `/define-use-case` (the latter because it may chain into `/develop`).

This workspace hosts four Claude Code entry points that operate on a **target project folder the user chooses**: the `project-builder` subagent (scaffolds a new project), the `develop` skill (builds features via a small agent team), the `revise-brief` skill (updates an existing brief), and the `define-use-case` skill (captures a single use case as a formalized Markdown file under `<TARGET_DIR>/use-cases/`). Nothing in this workspace is the project itself — it is the tooling that creates and evolves projects.

## Hard rules (all entry points)

- Neither entry point may write anywhere inside the folder the current Claude session was launched from (its session working directory). That folder hosts the agent, skills, and team definitions, and is edited by the user directly — never by the spawned agents.
- Everything — including `PROJECT_BRIEF.md` — is written inside the user-supplied target folder.
- `PROJECT_BRIEF.md` is the single source of truth for the target project. Both entry points read it (or produce it), and `develop` refuses to run without one.
- Always resolve the session directory dynamically (e.g., via `pwd`); never hardcode paths, since this workspace may live at different paths on different machines.

## Entry point 1 — `project-builder` (scaffold)

When the user asks to define, start, plan, or scaffold a new project:

1. **Ask for and confirm `TARGET_DIR` with the user** (absolute path). Refuse anything inside `SESSION_DIR`.
2. **Ensure `TARGET_DIR` exists before spawning the subagent.** If it does not, `mkdir -p <TARGET_DIR>` from the root session (with user approval if prompted). The subagent does NOT hold Bash permissions for paths outside `SESSION_DIR` and will stop and escalate if the folder is missing — that's expected and by design. Creating the folder is the root session's job.
3. **Spawn the `project-builder` subagent via the Agent tool** with:
   - `subagent_type: "project-builder"`
   - `mode: "acceptEdits"` — the agent auto-accepts its own file writes; Bash still prompts for commands not pre-approved in `.claude/settings.local.json`.

The agent always writes/updates `PROJECT_BRIEF.md` in the target folder **before** acting, so its plan is persisted and verifiable.

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

The skill orchestrates a four-agent team (`analyst`, `challenger`, `developer`, `qa`) with peer review, capped feedback loops, and role-scoped write permissions. Role boundaries are derived from `PROJECT_BRIEF.md` in the target folder — not hardcoded.

Must be invoked from the root session: spawned subagents cannot spawn further agents, so nested invocation will fail. If `PROJECT_BRIEF.md` is missing from the target folder, the skill first spawns `project-builder` to generate one, then proceeds.

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
  target_dir: <absolute path>
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
- `profile-aws-deployment` — AWS as the preferred cloud provider; every AWS-based suggestion must include a cost estimation table (per-service daily / monthly / yearly, with cumulative totals across new and pre-existing services).

## Permissions model

- Normal sessions in this workspace run with `defaultMode: "default"` — no blanket auto-accept. You can freely edit the agent and skill definitions as a normal user of this session; prompts behave as in any Claude Code project.
- Broader permissions apply **only** to the `project-builder` subagent, and only because it is invoked with `mode: "acceptEdits"`. The parent session is unaffected.

## Scope today

Structure-only scaffolding, use-case capture (one formalized file per use case under `<TARGET_DIR>/use-cases/`), and feature-development via the dev-team. `define-use-case` chains directly into `develop` with the just-saved file as the implementation target, so the single-use-case-to-implementation flow works end-to-end.

Still pending:
- No batch "implement all pending use cases" mode — each use case is a separate `develop` run. Status tracking makes batch feasible later, but it is not built today.
