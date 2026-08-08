---
name: profile-java-call-graph-tool
description: Opt-in profile. Provisions the java-class-call-scanning bytecode call-graph analyzer (https://github.com/HaroldHormaechea/java-class-call-scanning) for use by the dev-team agents on a Java project. Downloads the latest release jar to a per-user cache, registers the daemon as an MCP stdio server scoped to TARGET_DIR, and documents per-role usage of the nine query operations (find-callers, find-callees, methods-in-class, methods-at-line, find-field-readers, find-field-writers, impact-of-diff, tests-for-diff, refresh-index). Only invoke when PROJECT_BRIEF.md's `## Profiles` section lists this skill by name. Do NOT auto-invoke on arbitrary Java work.
---

# Profile — Java Call-Graph Tool

Provisions `java-class-call-scanning` for the dev-team. The tool is a bytecode-level call-graph and diff-impact analyzer for Java projects (compiled `.class`, JARs, WARs). When this profile is active, the dev-team agents gain access to nine call-graph and diff-impact operations — either through MCP tools (preferred) or through bash CLI invocations against a cached jar (fallback).

Apply only when `PROJECT_BRIEF.md` → `## Profiles` lists `profile-java-call-graph-tool`.

## Precedence

`PROJECT_BRIEF.md` > this profile > model defaults. If the brief overrides any rule below, follow the brief and surface the conflict. If the brief is silent, this profile is authoritative.

## What the tool provides

Upstream: https://github.com/HaroldHormaechea/java-class-call-scanning

The same fat jar runs three ways:

1. **One-shot CLI** — `java -jar java-class-call-scanning.jar --compiled <paths> --diff <file> --export-format json` for a complete impact report on a Git diff.
2. **Daemon TCP CLI** — a long-lived process scoped to a project (classpath + sources); query subcommands talk to it over a loopback port.
3. **Daemon MCP stdio server** — the same daemon advertises its nine operations as MCP tools. Server identifies itself as `java-class-call-scanning`.

The nine operations:

| Operation              | Purpose                                                                                 |
|------------------------|-----------------------------------------------------------------------------------------|
| `refresh-index`        | Re-scan the daemon's launch scope and atomically swap the index.                        |
| `find-callers`         | BFS over the call graph from a method FQN, returning callers (default depth unbounded). |
| `find-callees`         | BFS over the call graph from a method FQN, returning callees (default depth 3).         |
| `methods-in-class`     | List methods declared on a dotted class FQN.                                            |
| `methods-at-line`      | Methods whose `LineNumberTable` covers a given `(source_file, line)`.                   |
| `find-field-readers`   | Methods that READ a given field FQN (JVM-descriptor form).                              |
| `find-field-writers`   | Methods that WRITE a given field FQN (JVM-descriptor form).                             |
| `impact-of-diff`       | Parse a unified diff and emit the `impactedTrees` payload (full caller hierarchies).    |
| `tests-for-diff`       | Flat list of impacted tests `{fqn, type, displayName, root_change}` for a unified diff. |

FQN format:
- Methods: `pkg.Cls#name(Ldesc;)Ret` (e.g. `org.example.Foo#bar(Ljava/lang/String;)V`).
- Fields: `pkg.Cls#name:Ldesc;` (e.g. `org.example.Foo#count:I`).
- `<init>` and `<clinit>` are queryable by their reserved names.

The tool reads only — it never executes the analyzed code, never instruments it, and never makes network calls. It only requires the project's compiled `.class` files (and optional source roots for better diff matching).

## Provisioning model

The `develop` skill handles provisioning automatically when this profile is active. The dev-team agents do NOT download or register the tool themselves — that is the orchestrator's job, run once at the start of every `develop` invocation. See `.claude/skills/develop/SKILL.md` § "Step 3b — Provision the Java call-graph tool" for the exact procedure. Below is the contract that step honours, so agents and reviewers know what to expect.

### Cache location

The jar is cached **per-user**, shared across every TARGET_DIR on this machine:

```
$XDG_CACHE_HOME/project-builder/java-class-call-scanning/<release-tag>/java-class-call-scanning.jar
```

Falls back to `~/.cache/project-builder/java-class-call-scanning/<release-tag>/` when `XDG_CACHE_HOME` is unset. Each release tag (`v0.1.0`, `v0.1.1`, …) lives in its own folder so multiple versions coexist; cleanup is a future concern.

On macOS use `~/Library/Caches/project-builder/java-class-call-scanning/<release-tag>/`. On Windows use `%LOCALAPPDATA%\project-builder\java-class-call-scanning\<release-tag>\`.

### Release resolution

"Latest" means the most recent entry from `GET https://api.github.com/repos/HaroldHormaechea/java-class-call-scanning/releases?per_page=1` — including pre-releases, since today every published release is marked `prerelease: true`. The orchestrator MUST NOT use `/releases/latest` (which excludes pre-releases and currently 404s).

If the jar for that tag is already cached, the download step is skipped. If the network fetch fails (DNS error, GitHub down, rate-limit), the orchestrator surfaces the error to the user and falls back to the most recent cached version (if any). If no version is cached and the fetch fails, the orchestrator stops and asks the user to resolve connectivity — it does NOT continue without the tool.

### MCP server registration

The orchestrator writes a `<TARGET_DIR>/.mcp.json` entry naming the server `java-class-call-scanning` with this shape (paths interpolated):

```json
{
  "mcpServers": {
    "java-class-call-scanning": {
      "command": "java",
      "args": [
        "-jar",
        "<cached-jar-absolute-path>",
        "daemon",
        "start",
        "--foreground",
        "--classpath", "<TARGET_DIR>/<compiled-main-classes>",
        "--classpath", "<TARGET_DIR>/<compiled-test-classes>",
        "--src", "<TARGET_DIR>/<src-main-java>",
        "--src", "<TARGET_DIR>/<src-test-java>"
      ]
    }
  }
}
```

Compiled-class paths are inferred from `PROJECT_BRIEF.md` → `build.tool`:

| Build tool | Main classes path        | Test classes path             |
|------------|--------------------------|-------------------------------|
| `gradle`   | `build/classes/java/main` | `build/classes/java/test`     |
| `maven`    | `target/classes`          | `target/test-classes`         |

For multi-module projects (or non-standard layouts), the brief MUST override these via a `tooling.java_call_graph.classpath` and `tooling.java_call_graph.src` list in the YAML frontmatter; the orchestrator uses those verbatim when present and stops with an escalation message when the inferred defaults do not exist on disk.

If `<TARGET_DIR>/.mcp.json` already exists with the same key, it is preserved unchanged. If a conflicting entry exists, the orchestrator surfaces the conflict rather than overwriting.

### Build precondition

The daemon scans compiled bytecode — it has nothing to do if the project hasn't been built. The orchestrator runs a build before starting the daemon (`./gradlew build -x test` for Gradle, `mvn -DskipTests test-compile` for Maven). If the build fails, that is a build problem, not a tool problem — the orchestrator surfaces the failure and stops.

For projects with non-standard build invocations, the brief's `build.commands.test` (or a new `tooling.java_call_graph.build` command) overrides.

### Session lifecycle

Because Claude Code MCP servers are loaded at session start, an MCP entry written by `develop` mid-session does NOT inject tools into the currently-running session. The intended flow:

1. **First `develop` run on a project — CLI fallback in use.** `develop` Step 3b writes the `.mcp.json` and tells the user explicitly that the current run uses the CLI fallback (the bash/TCP surface against the cached jar). Role agents invoke the same nine operations; results are identical, the only cost is one extra subprocess per query. The user does NOT need to restart for the current run to complete successfully.
2. **Subsequent runs — MCP path ready, restart optional.** Once `.mcp.json` exists in `TARGET_DIR`, any Claude Code session opened from `TARGET_DIR` loads the MCP server automatically. The user can restart their session inside `TARGET_DIR` whenever convenient (cleaner tool-use traces, no per-query bash hop). The CLI fallback continues to work in sessions that did not load the MCP entry — both paths coexist.

The user-facing note that `develop` Step 3b emits says exactly this: "this run uses the fallback; next session inside `TARGET_DIR` will have MCP ready if you choose to restart." Per-role guidance below covers both paths.

## How each role applies this profile

Every role agent's first step is to detect whether the MCP tools are available:

- If the agent's tool inventory lists tools prefixed `mcp__java-class-call-scanning__` (e.g. `mcp__java-class-call-scanning__find-callers`), use the MCP path.
- Otherwise, use the CLI fallback: invoke the same operations via `java -jar <cached-jar> <operation> --project <TARGET_DIR> ...`. The orchestrator surfaces the cached-jar absolute path to each agent in its spawn prompt; agents do NOT download the jar themselves.

### Analyst

- Before drafting a proposal that touches existing code, run `methods-in-class` or `find-callers` on the methods you plan to change to understand the blast radius. Cite the operation name and the result count in your **Risks & Considerations** section (e.g. "find-callers on `Foo#bar` returned 12 callers, of which 4 are in test code — covered by the proposal").
- For diff-driven tasks (refactor existing behaviour, fix a regression), run `impact-of-diff` against the pending diff to inventory affected methods and their transitive callers before partitioning the work in **Files Affected**.
- Do NOT run `refresh-index` unless the build has just changed underneath the daemon — the orchestrator handles the initial index.

### Challenger

- Treat any "this change is local / doesn't affect anything else" claim in the proposal as testable. Run `find-callers` (or `impact-of-diff` if a diff already exists) to verify. A claim contradicted by the tool is **Critical** — the proposal is built on a false premise.
- When a proposal asserts test coverage, run `tests-for-diff` to confirm the named tests actually transitively cover the changed methods. Missing transitive coverage is **Major** at minimum.
- Tool errors (daemon not running, build missing, jar not cached) are NOT a reason to skip the check. Flag them to the team lead so the orchestrator can repair the environment, then re-evaluate.

### Developer

- After writing your changes, run `impact-of-diff` against the staged changes (or against `git diff`) to inventory the transitive callers you have just touched. Add this inventory to **Implementation Notes** when it surfaces non-obvious dependents (e.g. callers in modules you did not anticipate).
- Use `find-field-readers` / `find-field-writers` before changing a non-private field's type or visibility — the daemon catches accidental external dependents the IDE may miss across module boundaries.
- Do not modify the daemon's lifecycle (no `daemon stop`, no jar replacement). Treat the daemon as a read-only fixture.

### QA

- For every PR-like change in scope, run `tests-for-diff` to obtain the set of impacted tests. This is the primary input for what to verify.
  - If `tests-for-diff` returns an empty set on a change that touches production code, that is itself a finding — report it as **Issues Found** (likely missing test coverage on the changed code path, not a daemon bug).
  - If `tests-for-diff` returns tests the developer did NOT update or run locally, those tests must pass before QA approves.
- Cross-check `tests-for-diff` against the use-case `## Acceptance Criteria` (when a use case is in play). A criterion not covered by any impacted test is a coverage gap.

## CLI fallback — exact invocations

When the MCP tools are unavailable, use these bash invocations. `<JAR>` is the absolute jar path supplied by the orchestrator; `<TARGET_DIR>` is the project's absolute path.

```bash
# One-shot diff impact (no daemon required)
git diff main...HEAD | java -jar <JAR> \
    --compiled <TARGET_DIR>/<compiled-main-classes> \
    --compiled <TARGET_DIR>/<compiled-test-classes> \
    --sources <TARGET_DIR>/src/main/java \
    --diff-stdin --export-format json

# Query the running daemon — find callers of a method
java -jar <JAR> find-callers --project <TARGET_DIR> --method 'org.example.Foo#bar()V'

# Query the running daemon — tests impacted by the current diff
git diff main...HEAD | java -jar <JAR> tests-for-diff --project <TARGET_DIR> --diff-stdin

# Force an index refresh (e.g. after rebuilding the target)
java -jar <JAR> refresh-index --project <TARGET_DIR>
```

All query subcommands return JSON on stdout. On error, stdout/stderr carry a `{"error": "...", "kind": "<bad-request|not-found|...>"}` envelope and the exit code is non-zero.

## Non-goals

This profile does NOT cover:

- **Reflection-based or runtime-resolved call sites.** The upstream tool is bytecode-static; reflection, `MethodHandle`, dynamic proxies, and CHA/RTA-style virtual-dispatch resolution are out of scope. Do not claim coverage the tool cannot provide.
- **Coverage measurement.** The tool tells you which tests *could* exercise changed methods. It does not tell you whether those tests pass or what line coverage they produce.
- **Non-JVM languages.** Kotlin, Scala, and Groovy compile to JVM bytecode and are partially supported by ASM, but the test detectors only recognise JUnit 5 (Java annotations) and Spock (Groovy specifications). Other JVM languages may work but are not validated.
- **Database, HTTP, deployment conventions.** Use `profile-java-database-access`, `profile-java-server-architecture`, and `profile-aws-deployment` for those concerns.
- **Build-tool configuration.** The profile assumes the project is buildable with the brief's declared `build.tool`. It does not fix broken builds.
