---
name: profile-java-database-access
description: Opt-in profile. Opinionated Java database-access conventions — DTO projections over entity queries, bulk retrieval over iterative round-trips, parameterized queries only (never string concatenation), and Hibernate as the JPA implementation. Only invoke when PROJECT_BRIEF.md's `## Profiles` section lists this skill by name. Do NOT auto-invoke on arbitrary Java or database-related work.
---

# Profile — Java Database Access

Opinionated conventions for Java projects using JPA for database access. Apply these rules only when `PROJECT_BRIEF.md` → `## Profiles` lists `profile-java-database-access`.

## Precedence

`PROJECT_BRIEF.md` > this profile > model defaults. If the brief contradicts any rule below, follow the brief and surface the conflict to the user. If the brief is silent, this profile is authoritative.

## Rules

### 1. DTO projections, not entity queries

Fetch the shape the caller needs, not the whole entity.

- Use JPQL constructor expressions: `SELECT new com.example.FooDto(f.id, f.name) FROM FooEntity f`.
- Or use Spring Data interface / class projections on repository methods.
- Or use the Criteria API with explicit `.multiselect(...)` returning a DTO, not an entity.
- Repository methods should declare DTO return types (or projection interfaces) whenever the caller does not need a managed, mutable entity.
- **Entities MUST NOT leave the repository layer.** Convert at the repository boundary.
- Entity-returning queries are permitted only when the caller genuinely needs a managed, mutable entity in the same transaction (update-and-save flows). Document why in a short comment on those methods.

### 2. Bulk retrieval over iterative round-trips

One query returning many rows beats N queries each returning one.

- Use `IN` clauses with `findAllById(Collection<ID>)`, or explicit JPQL `WHERE id IN :ids`.
- For lazy collections or associations that will be iterated, use `JOIN FETCH` or `@BatchSize` to prevent N+1. On entities with multiple collections, watch for Cartesian explosion — paginate before fetching, or fetch each collection separately.
- Batch writes: prefer `saveAll`, `deleteAllById`, JDBC batch (`JdbcTemplate.batchUpdate`) over per-row calls inside loops.
- Large result sets: use `Stream<T>` with a sensible fetch size, or pagination — never fire a query per iteration.
- Pattern recognition: any code shaped like `for (X x : xs) { repo.findSomething(x.getId()); }` is a red flag. Replace with one `findAllBy...(ids)` plus an in-memory join (e.g., to a `Map<Id, Row>`).

### 3. Parameterized queries only — never string-append

**Under no circumstances** compose SQL or JPQL by concatenating, `String.format`-ing, or otherwise splicing values into the query text. This rule is absolute.

Apply it to every query surface:

- JPA `@Query` annotations — use `:name` or `?1` placeholders.
- `EntityManager.createQuery` / `createNativeQuery` — bind with `setParameter(...)`.
- Criteria API — parameters are bound by construction.
- `JdbcTemplate` / `NamedParameterJdbcTemplate` — use `?` or `:name` placeholders; never interpolate into the SQL string.
- QueryDSL, jOOQ, and similar query builders — use their parameter-binding APIs.

Rationale:

- **Security.** Parameter binding is the only reliable defense against SQL injection.
- **Performance.** Parameterized queries let the database cache execution plans.

For **dynamic query shapes** (varying `WHERE` clauses, sort columns, pagination), use Criteria, Specifications, QueryDSL, or a builder — not string fragments. If a column name or table identifier genuinely must vary at runtime, source it from a fixed whitelist (enum or explicit mapping) — never from user input.

When editing code that already violates this rule, flag it to the analyst / team lead rather than leaving it in place or silently propagating the pattern to new code.

### 4. Hibernate as the JPA implementation

JPA is the API; this profile mandates Hibernate as the implementation.

- Gradle/Maven: depend on `org.hibernate.orm:hibernate-core`, or rely on `spring-boot-starter-data-jpa` which uses Hibernate by default. Do not swap in EclipseLink, OpenJPA, or DataNucleus.
- Hibernate-specific features are fair game: `@BatchSize`, `@Type`, `@Formula`, `@SQLInsert`, `StatelessSession`, `Session` unwrapping via `entityManager.unwrap(Session.class)`.
- Prefer `jakarta.persistence.*` annotations where a JPA equivalent exists; drop to `org.hibernate.annotations.*` only when JPA does not cover the need.

## How each role applies this profile

- **Analyst** — propose DTO projections, bulk operations, and parameter binding as the default shape of any data-access work. Any proposal step that reads full entities unnecessarily, iterates queries, or composes SQL by string-building must be flagged or rewritten before you send the proposal.
- **Challenger** — reject proposals that violate any of the four rules unless the brief explicitly overrides. Treat violations as **Critical** (rule 3, parameterized queries) or **Major** (rules 1, 2, 4).
- **Developer** — write code conforming to all four rules. If the approved proposal violates a rule, stop and send a clarifying message to the team lead instead of silently violating. If the brief overrides a rule, follow the brief and note it in your implementation notes.
- **QA** — at the repository layer, cover the bulk paths, DTO-return signatures, and parameter-bound queries. Do not author tests that would lock in entity-return semantics, single-row iteration, or string-built queries — those tests would cement violations.

## Non-goals

This profile does not cover:

- Schema design, naming, or migration-tool conventions (those belong in the brief or a dedicated profile).
- Transaction boundaries and isolation levels (service-layer concern, out of scope here).
- Caching, second-level cache, or read-replica routing (separate concerns).
- Non-JPA data stores (NoSQL, search, vector, blob) — this profile applies to JPA-backed relational access only.
