---
name: define-architecture
description: Capture the architecture of the project — platforms, service shape (monolith vs. modular vs. services), integrations, data flow, trust boundaries, and multi-tenancy. Use when the project-builder agent is gathering architecture information.
---

# Purpose

Describe the *shape* of the system: what runs where, how the pieces talk to each other, and what crosses trust boundaries.

# Questions to ask (in order)

1. Platforms to support: web, iOS, Android, desktop (macOS/Windows/Linux), CLI, browser extension, server-only, embedded.
2. Service shape: single monolith, modular monolith, a small set of services, or many microservices.
3. Communication between components: HTTP/REST, GraphQL, gRPC, message queue, WebSockets, event bus, file drop.
4. Synchronous vs. asynchronous workloads: long-running jobs, schedulers, background workers?
5. Integrations: external systems to read from or write to.
6. Data flow: a short narrative of how data moves from input → storage → output.
7. Trust boundaries: where does untrusted input enter, where does sensitive data live, and what must never leave the system?
8. Multi-tenancy: not applicable, shared DB with row-level isolation, schema-per-tenant, or deployment-per-tenant.

Use `AskUserQuestion` for multi-choice items (platforms, service shape, multi-tenancy, comm style).

# Solution space to present

- **Platforms**: web only / web + mobile / mobile only / desktop / CLI / mixed. One-line tradeoffs on distribution, update cadence, and platform-specific constraints.
- **Service shape**:
  - *Monolith* — simplest, easiest to evolve early.
  - *Modular monolith* — clean internal boundaries without distributed-system costs.
  - *Services* — justified when teams or scaling domains genuinely diverge.
- **Async infrastructure**: none, in-process queue, managed queue (SQS, Cloud Tasks), broker (RabbitMQ, Kafka, NATS), scheduled jobs (cron, managed scheduler).
- **Multi-tenancy**: not applicable / shared DB row-level / schema-per-tenant / deployment-per-tenant, with isolation and ops tradeoffs.

# Required schema

- `platforms` (list)
- `service_shape` (string)
- `components` (list of `{name, runtime, responsibility}`)
- `communication` (list of `{from, to, protocol}`)
- `async_workloads` (list)
- `integrations` (list)
- `data_flow_narrative` (string)
- `trust_boundaries` (string)
- `multi_tenancy` (string)

# Output

Write to `PROJECT_BRIEF.md` under a `## Architecture` heading. Replace any prior `## Architecture` section when re-run.

# Frontmatter contribution

Update these YAML frontmatter fields (see `CLAUDE.md` for the full schema). Leave every other field untouched:

- `paths.production` — list of glob patterns identifying production-code paths (e.g., `["src/main/**", "src/server/**"]`). The dev-team `developer` agent uses this as its write scope.
- `paths.test` — list of glob patterns identifying test-code paths (e.g., `["src/test/**", "src/integrationTest/**", "tests/**"]`). The dev-team `qa` agent uses this as its write scope.
- `paths.api_boundary` — optional. Glob patterns for the API / controller layer (e.g., `["src/main/java/**/api/**"]`). Populate only if the architecture has a distinct API layer (relevant for `profile-java-server-architecture`).

If the user's answers do not yield unambiguous globs for production and test paths, ask follow-up questions until they do — the dev-team refuses to run without clear role scopes.
