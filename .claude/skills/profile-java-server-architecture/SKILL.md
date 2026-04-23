---
name: profile-java-server-architecture
description: Opt-in profile. Opinionated Java server-side architecture conventions — Gradle on its latest stable version, latest stable Spring Boot, latest Java LTS, repositories return DTOs (never JPA entities) to upper layers, internal DTOs stay internal (API layer has its own request/response DTOs), and a strict Controller/Job → Facade → Service → Repository call chain with transactions owned by the facade. Only invoke when PROJECT_BRIEF.md's `## Profiles` section lists this skill by name. Do NOT auto-invoke on arbitrary Java or Spring work.
---

# Profile — Java Server Architecture

Opinionated conventions for Java server-side projects (typically Spring Boot backends). Apply only when `PROJECT_BRIEF.md` → `## Profiles` lists `profile-java-server-architecture`.

## Precedence

`PROJECT_BRIEF.md` > this profile > model defaults. If the brief pins specific versions or contradicts any rule below, follow the brief and surface the conflict. If the brief is silent, this profile is authoritative.

## Rules

### 1. Build: Gradle, latest stable

- Build tool is **Gradle**. No Maven, no mixed builds.
- Use the **latest stable Gradle release** at scaffold time. Pin it in `gradle/wrapper/gradle-wrapper.properties`.
- Prefer the **Kotlin DSL** (`build.gradle.kts`) for new projects for better IDE support. Groovy DSL is acceptable only when maintaining existing Groovy build scripts.
- Use a **Gradle version catalog** (`gradle/libs.versions.toml`) to centralize dependency versions — no hand-pinning scattered across `build.gradle.kts`.
- Ship the **Gradle Wrapper** (`./gradlew`) with the project. Never require a system-installed Gradle.

### 2. Spring Boot: latest stable

- Use the **latest stable Spring Boot release** at scaffold time.
- Declare the Spring Boot plugin in `build.gradle.kts`; let its BOM manage transitive versions. Do not hand-pin versions of libraries Spring Boot already manages.
- Use Spring Boot autoconfiguration and conventions — do not duplicate what a starter already provides.
- Prefer `spring-boot-starter-*` modules over raw `spring-*` dependencies.

### 3. Java: latest LTS

- Target the **latest Java LTS** at scaffold time. Non-LTS JDKs are not acceptable for production projects — their security support window is too short.
- Configure the Gradle toolchain so the build is reproducible across machines:
  ```
  java {
      toolchain {
          languageVersion = JavaLanguageVersion.of(<N>)
      }
  }
  ```
- Use modern language features where they improve clarity: records for immutable data carriers, pattern matching for `instanceof` and `switch`, text blocks, sealed types for closed hierarchies.

### 4. Repositories return DTOs, not JPA entities

Repositories MUST return DTOs (or projection interfaces) to upper layers. `@Entity` classes **never leave the repository package**.

- Read methods return a DTO, a projection interface, or a collection of either.
- Write methods accept DTOs (or primitive parameters), perform entity mapping internally, and return DTOs — or nothing — on the way out.
- Enforce structurally with an **ArchUnit** rule (or equivalent): entity classes must not be referenced outside the repository package.
- If `profile-java-database-access` is also active, both profiles reinforce this rule — they do not conflict.

### 5. Internal DTOs stay internal — the API layer owns its own DTOs

DTOs passed between service/domain layers MUST NOT be used as REST request or response bodies. The API layer has its own request and response DTOs, and a mapper at the controller boundary.

- Internal DTOs live in a service/domain package (e.g., `com.example.foo.service.dto`).
- API DTOs live in an API package (`com.example.foo.api.dto` or a dedicated module).
- Controllers — or a dedicated mapper invoked at the controller boundary — translate between API DTOs and internal DTOs. Hand-written mappers or MapStruct are both acceptable; pick one per project and stick with it.
- Never put API-shaping annotations (`@Schema`, `@JsonProperty`, `@JsonIgnore`, `@JsonInclude`) on internal DTOs. If you are reaching for those on an internal type, you are using the wrong type.
- Enforce structurally with an **ArchUnit** rule: controller/REST packages must not reference internal DTO types as request or response parameters.

Rationale:

- **API stability** — internal model evolution must not break API contracts.
- **Information hiding** — prevents accidental leakage of internal fields (audit metadata, internal ids, implementation concerns).
- **Versioning** — API DTOs can be versioned (`v1`, `v2`) without rippling changes through the service layer.

### 6. Layered architecture: Controller / Job → Facade → Service → Repository

The application follows a strict layered call pattern. Every layer has a single allowed caller set.

**Entry points — Controllers and Jobs**

- **Controllers** handle HTTP transport, authentication/authorization checks, and request-DTO validation.
- **Jobs** are any non-HTTP entry point: scheduled tasks (`@Scheduled`), message/event listeners (Kafka, SQS, RabbitMQ), queue consumers, startup runners, webhooks.
- Controllers and jobs MUST call **facades** only — never services, never repositories.

**Facades — use-case orchestration and the transaction boundary**

- Facades coordinate use-case-level operations. `@Transactional` is declared **at the facade method level** — facades own the transaction boundary.
- A facade method may call other **facades** and/or **services of its own domain**.
- Facades MUST NOT call repositories directly.
- **Cross-domain operations** (work that touches data or actions belonging to more than one domain) are orchestrated via **facade-to-facade** calls. A facade never reaches into another domain's services.
- **Same-domain operations** (work confined to the facade's own domain) may call the services of that domain directly — no intermediate facade required.

**Services — domain-operation implementers**

- A service operates on **one main entity / domain**. It implements the domain operations that facades compose into use cases.
- Services call repositories and may call **other services within the same domain**.
- Services MUST NOT declare `@Transactional`. If a service operation needs a new or different transaction, that is a signal to move the boundary — escalate to the facade rather than annotating the service.
- Services MUST NOT be called by controllers or jobs.

**Repositories — persistence only**

- Repositories hold the persistence-layer calls and return DTOs / projection interfaces per rule 4.
- Repositories are called only by services.

**Transaction propagation**

- `@Transactional` on a facade method uses Spring's default propagation (`REQUIRED`). Nested facade calls and service calls participate in the caller's transaction.
- Declare `readOnly = true` on facade methods that never write — it lets Hibernate and the JDBC driver skip dirty-checking and enables query-only optimizations.
- Do not use `REQUIRES_NEW` casually; it breaks the caller's atomicity. Reserve it for explicit cases (audit trail writes that must survive a rollback) and document why on the annotated method.

**Structural enforcement (ArchUnit or equivalent)**

- Controllers and jobs may depend only on facades. They must not import service or repository types.
- Facades may not depend on repositories.
- `@Transactional` may appear only on facade-layer types or methods.
- Services may not be called from controller / job / `rest` / `api` packages.

**Rationale**

- The **facade layer is the use-case boundary** ("do this user intent") and therefore the right transaction boundary.
- The **service layer is the domain-operation boundary** ("perform this operation on this entity"). Splitting them prevents controllers from accumulating coordination logic and keeps services reusable across use cases.
- The same-domain shortcut (facade → services directly) avoids wrapper facades that add no value for single-domain operations; the cross-domain rule prevents accidental coupling between domains.

## Version discovery procedure (mandatory)

When this profile is first applied (typically during scaffolding, or when the brief's `stack.versions` is missing a required version), the agent MUST look up current versions via `WebFetch` — **not** from training data.

Use these sources:

- **Gradle latest stable** — `WebFetch https://services.gradle.org/versions/current`. The response is JSON; extract the `version` field.
- **Spring Boot latest stable** — `WebFetch https://api.spring.io/projects/spring-boot/releases`. Pick the latest entry whose `current` is `true` or whose version matches the stable pattern (no `-SNAPSHOT`, no `-M`/`-RC` suffixes).
- **Java latest LTS** — `WebFetch https://endoflife.date/api/java.json`. Pick the latest entry where `lts` is `true` and support is still active (`eol` date in the future or missing).

Record each fetched version in `PROJECT_BRIEF.md` → frontmatter `stack.versions` (e.g., `{java: "21", gradle: "8.14.2", spring_boot: "3.3.2"}`) AND in the `## Technologies` prose section. Also record the fetch date alongside the prose so the decision is auditable.

If `WebFetch` is not available in the agent's tool set, or every source fetch fails, the agent MUST stop and ask the user for the versions. Do NOT guess from training data and do NOT invent a date — this rule is non-negotiable.

## Version handling on subsequent runs

"Latest" is a **scaffold-time decision**, not a runtime mandate.

1. On later `develop` runs, the versions recorded in `stack.versions` take precedence. The word "latest" in this profile is not a trigger to upgrade mid-feature.
2. Upgrades are an explicit, scoped project — never a side effect of unrelated feature work.

If the brief's `stack.versions` is missing the relevant tools when `develop` runs, the analyst must stop and run the version-discovery procedure above (or ask the user) before any implementation work proceeds.

## How each role applies this profile

- **Analyst** — propose repository-returns-DTO shapes, separate API vs internal DTOs, mapper placement, and layer-compliant call chains (Controller/Job → Facade → Service → Repository). For cross-domain work, explicitly route via facade-to-facade. Do not propose mid-feature Gradle / Spring Boot / Java upgrades.
- **Challenger** — severity guide:
  - **Critical**: controller or job calling a repository directly; facade calling a repository directly; `@Transactional` declared on a service or repository; deviation from the brief's pinned Gradle / Spring Boot / Java versions; proposal mixing in Maven or a non-LTS JDK.
  - **Major**: controller or job calling a service directly (bypasses the facade); cross-domain work done via facade → other-domain's service (should be facade-to-facade); entity leak past the repository package; internal DTO reused as an API request/response.
- **Developer** — implement to all rules. For each new endpoint, create its API DTOs in the API package and place the mapper at the controller boundary. Declare `@Transactional` only on facade methods; mark read-only where applicable. Add or update the ArchUnit rule when introducing a new package that should be covered by a layering constraint.
- **QA** — test controllers through API DTOs (`MockMvc`, `WebTestClient`). Test facades as the transaction boundary (integration tests that assert commit/rollback behavior). Test services with their main-entity scope using internal DTOs. If `profile-java-database-access` is also active, ensure repository-layer tests assert DTO return shapes. Do not cross layer boundaries in test code.

## Non-goals

- Detailed coding style (formatter, imports, naming conventions) — belongs in the brief or a style-specific profile.
- Testing framework choice (JUnit vs. Spock) — follow the brief.
- Database-access rules (N+1 avoidance, parameterized queries, Hibernate as provider) — see `profile-java-database-access`.
- Observability, deployment, and secrets management — captured by `define-deployment` at scaffold time.
- Frontend concerns — this profile covers server-side only.
