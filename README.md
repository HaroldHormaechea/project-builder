# project-builder

A Claude Code workspace that scaffolds and evolves other software projects. Not a framework or a library — a set of subagents, skills, and team definitions that a Claude Code session exposes when it runs inside this folder.

## What it does

Three entry points, all operating on a **target folder you choose** — this repository itself is off-limits to the spawned agents:

- **`project-builder` subagent** — runs a deterministic interview (overview, monetization, technologies, architecture, quality standards, deployment), writes a `PROJECT_BRIEF.md` with a YAML frontmatter contract, then scaffolds the project structure.
- **`develop` skill** — orchestrates a four-agent team (analyst, challenger, developer, QA) with peer review and role-scoped writes to implement features against an existing project.
- **`revise-brief` skill** — updates one or more sections of an existing brief without re-scaffolding.

Stack-neutral by default. Stack- or tool-specific conventions live in opt-in **profile skills** under `.claude/skills/profile-*`, activated per project by listing them in `PROJECT_BRIEF.md` → `profiles:`.

## Requirements

- macOS or Linux
- [Claude Code](https://claude.com/claude-code) installed and authenticated
- Git

## Quick start

```bash
git clone git@github.com:HaroldHormaechea/project-builder.git
cd project-builder
claude
```

Then, from the Claude Code session:

- Scaffold a new project — ask Claude to "scaffold a new project in `/absolute/path/to/target`". The `project-builder` subagent takes over.
- Build a feature in an existing project that has a `PROJECT_BRIEF.md` — run `/develop` and point it at your target folder.
- Refresh sections of an outdated brief — run `/revise-brief`.

The authoritative rules (orchestration constraints, frontmatter schema, profile precedence) live in `CLAUDE.md` and are auto-loaded by Claude every session.

## Profiles included

- `profile-java-database-access` — DTO projections over entity queries, bulk over iterative, parameterized queries only, Hibernate as the JPA implementation.
- `profile-java-server-architecture` — Gradle, Spring Boot, and Java LTS versions fetched at scaffold time; repositories return DTOs only; internal DTOs never leak to the API boundary; strict Controller/Job → Facade → Service → Repository call chain with the transaction owned by the facade.
- `profile-aws-deployment` — AWS as the preferred provider. Every AWS-based suggestion must include a cost table with per-service daily / monthly / yearly figures and cumulative totals across new and pre-existing services. Prices are fetched at runtime: Vantage first for EC2, RDS, and ElastiCache; official AWS pricing pages as fallback.

To add a profile, drop a `SKILL.md` under `.claude/skills/profile-<name>/` with a description that explicitly says "only invoke when listed in `PROJECT_BRIEF.md`'s profiles list", then list it in a project's brief to activate it.

## Project layout

```
CLAUDE.md                                   Authoritative rules loaded by Claude at session start
README.md                                   This file
.gitignore
.claude/
  settings.json                             Session defaults and SessionStart hook
  hooks/session-start.sh                    Reminder injected into the model's context each session
  agents/project-builder.md                 Scaffolding subagent definition
  skills/
    define-overview/                        Scaffold interview — overview
    define-monetization/                    Scaffold interview — monetization
    define-technologies/                    Scaffold interview — tech stack
    define-architecture/                    Scaffold interview — architecture
    define-quality-standards/               Scaffold interview — quality, testing, profiles opt-in
    define-deployment/                      Scaffold interview — prod and dev deployment
    develop/                                Dev-team entry point
    revise-brief/                           Brief-evolution entry point
    write-readme/                           README generation skill for scaffolded projects
    profile-java-database-access/           Opt-in profile
    profile-java-server-architecture/       Opt-in profile
    profile-aws-deployment/                 Opt-in profile
  teams/dev-team/
    orchestrator.md                         Root-session orchestration instructions
    analyst.md / challenger.md / developer.md / qa.md
```

## Known limitations

- **Plaintext brief.** Role agents parse Markdown section headings by match. A renamed or reordered section can be missed. The YAML frontmatter hardens the structured reads, but prose sections remain loosely parsed.
- **No recovery semantics.** If a spawned agent crashes, times out, or exhausts its context mid-phase, the orchestrator does not recover. The user has to restart the run.
- **Profile proliferation.** Each profile's description is visible in every agent's context. Adding many profiles over time will grow context noise; there is no pruning strategy today.
- **Spawned agents cannot spawn further agents.** All skills in this workspace must be invoked from the root Claude Code session, never from within a subagent. The SessionStart hook reinforces this every session.
- **No batch use-case mode.** Each use case is a separate `develop` run. Status is tracked in `USE_CASES.md`, but there is no "implement all pending" driver today.

## License

Not yet licensed.
