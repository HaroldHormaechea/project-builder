---
name: define-use-case
description: Capture a single use case for a target project. Collects a free-form description from the user, produces a formalized version (summary, acceptance criteria, pitfalls), runs a clarifying-question loop, and saves the result as an incrementally-numbered Markdown file in the target project's `use-cases/` folder. After saving, offers to define another use case or continue to implementation via the `develop` skill. Use when the user wants to document what the project should do, before or instead of jumping into implementation.
---

# Define Use Case

Entry point for adding a single use case to a target project. The skill is deterministic: one use case per invocation, no batching. Run it again to add another.

## Preconditions

- Must run from the **root Claude Code session** so the follow-up can hand off to `develop` without nested spawning.
- The target folder must already contain a `PROJECT_BRIEF.md`. If it does not, stop and point the user at `project-builder` — use cases without a project context are not useful.

## Step 1 — Resolve folders

1. Run `pwd` via Bash to get `SESSION_DIR`.
2. Ask the user for the target project folder (`TARGET_DIR`) as an absolute path. Resolve relative paths with `cd <path> && pwd` and confirm.
3. Refuse and re-ask if `TARGET_DIR` equals, contains, or is contained by `SESSION_DIR` (path-segment comparison — `/foo/bar` is not a prefix of `/foo/barbaz`).
4. Confirm `<TARGET_DIR>/PROJECT_BRIEF.md` exists. If it does not, stop and tell the user to run `project-builder` first.

## Step 2 — Load project context

Read `<TARGET_DIR>/PROJECT_BRIEF.md`. You need this as background so the formalized use case stays consistent with the project's stack, architecture, and stated non-goals.

The only writes this skill performs on the brief are scoped to the `use_cases` frontmatter block (path bookkeeping) and a single `## Use Cases` prose paragraph pointing at the ledger — both handled in Step 6b. No other section, and no other frontmatter field, may be touched.

## Step 3 — Collect the raw description

Ask the user in free text to describe the use case, **as thoroughly as they consider appropriate**. No structure is imposed. Make clear:

- They can include goals, actors, triggers, flows, edge cases, data, anything they want.
- Length is their call. Short is fine; long is fine.
- They can paste multiple paragraphs.

Capture the response verbatim — you will embed it unchanged in the final file under `## Original Description`.

## Step 4 — Produce the formalized draft

Transform the raw description into a formalized version with exactly these three sections (in this order):

### 1. Summary
A dense prose paragraph (roughly 3–8 sentences). Enough detail that an implementer reading only this summary can judge feasibility, scope, and which parts of the system it touches. Do not pad. Do not invent facts the user did not state — if something is unknown, that belongs in Pitfalls, not here.

### 2. Acceptance Criteria
A numbered list of **testable** conditions. Each item must be independently verifiable — something QA could write a test against, or a reviewer could check. Prefer observable behavior over implementation detail. Aim for completeness, not minimalism: if a criterion is missing, the implementation can satisfy the rest and still be wrong.

### 3. Potential Pitfalls & Open Questions
A bulleted list of ambiguities, missing inputs, edge cases the user did not cover, assumptions you had to make while drafting the Summary, risks to the stated non-goals, and anything that would bite the dev-team later. Label each bullet as one of: **Ambiguity**, **Missing input**, **Edge case**, **Assumption**, or **Risk**. This list drives Step 5.

Present the draft to the user in the chat. Do not write to disk yet.

## Step 5 — Clarifying-question loop

From the Pitfalls list, select up to **five** of the highest-leverage items (ones that would most change the Summary or Acceptance Criteria if answered) and ask them via `AskUserQuestion`, batched in one call where possible. Prefer multi-choice options grounded in the project's stack and architecture. When a free-text answer is genuinely needed, make the question single and scoped.

After the user answers:

1. Regenerate the full formalized version (Summary, Acceptance Criteria, Pitfalls) incorporating the answers. Move resolved pitfalls out of the list; leave unresolved ones with a short note on why they remain open.
2. Show the updated draft to the user.
3. Ask: **happy to save**, **another round of clarifications**, or **discard this use case**.
   - Save → Step 6.
   - Another round → Step 5 again. Cap the loop at **four** clarification rounds; on the fifth, stop and tell the user the use case is still unsettled and may not be worth saving as-is.
   - Discard → stop, do not write anything.

## Step 6 — Save the use case

1. Ensure `<TARGET_DIR>/use-cases/` exists. Create it with `mkdir -p` if missing.
2. List existing `*.md` files in that folder and compute the next incremental number: zero-padded to two digits (`01`, `02`, …, `99`). If a gap exists (e.g., `01`, `03`), still pick `max + 1` — never reuse a number.
3. Derive a brief kebab-case slug from the use case title (3–6 words, lowercase, hyphen-separated, ASCII only). Ask the user to confirm the slug before writing.
4. Write the file at `<TARGET_DIR>/use-cases/<NN>-<slug>.md` with this structure:

   ```markdown
   # Use Case <NN>: <Human-readable title>

   ## Summary
   <summary paragraph>

   ## Acceptance Criteria
   1. ...
   2. ...

   ## Potential Pitfalls & Open Questions
   - **<Label>** — ...

   ## Original Description
   <verbatim user-provided text>

   ## Clarifications
   - Q: <question text>
     A: <user's answer>
   ```

   Omit the `Potential Pitfalls & Open Questions` section only if the final draft has zero open items. Omit `Clarifications` only if the user went straight to save without a clarification round.

5. Confirm the file path back to the user.

## Step 6b — Update the status ledger

The ledger (`<TARGET_DIR>/USE_CASES.md`, or whatever path `use_cases.index` in the brief names) is the single source of truth for use-case status. You create and maintain it; the dev-team orchestrator updates the `Status` and `Updated` columns later.

1. Read `<TARGET_DIR>/PROJECT_BRIEF.md` and check the frontmatter `use_cases` block:
   - If `use_cases.index` is missing or null, set it to `USE_CASES.md`.
   - If `use_cases.folder` is missing or null, set it to `use-cases/`.
   - Write the updated frontmatter back, preserving all other fields exactly.
2. If `<TARGET_DIR>/USE_CASES.md` does not exist, create it with the canonical header and an empty table (columns `# | File | Title | Status | Updated`). The header, the status legend, and the "Machine-maintained" warning line documented in `CLAUDE.md` are required verbatim — do not paraphrase.
3. Append a new row for the use case just saved:
   - `#` — the zero-padded number (same as the filename prefix)
   - `File` — a Markdown link `[use-cases/<NN>-<slug>.md](use-cases/<NN>-<slug>.md)` (relative path from `TARGET_DIR`)
   - `Title` — the human-readable title
   - `Status` — `pending`
   - `Updated` — today's date (`YYYY-MM-DD`)
4. If the brief does not yet contain a prose reference to the ledger, append a short `## Use Cases` section (or insert it before `## Scaffolding Plan` if that exists) with one sentence pointing at the ledger, e.g. *"Use cases are captured individually under `use-cases/` and indexed in `USE_CASES.md`."* Add this only once; if the section already exists, leave it alone.

Never edit the `Status` or `Updated` columns on rows that already exist — those belong to the orchestrator.

## Step 7 — Next action

Use `AskUserQuestion` with three options:

- **Define another use case** → loop back to Step 3 (keep the same `TARGET_DIR`; do not re-resolve).
- **Continue to implementation with the dev-team** → invoke the `develop` skill via the `Skill` tool. Pass along the path of the just-saved use case file so `develop` can use it as the implementation target.
- **Stop** → end the session cleanly. Summarize what was saved.

## Constraints

- Never write anywhere inside `SESSION_DIR`.
- Never modify `PROJECT_BRIEF.md` from this skill.
- Never reuse an existing use-case number or filename — if a collision would occur, pick the next free number.
- One use case per file. Do not bundle related use cases into a single file to "save work" — the dev-team reads one file at a time.
- If the user's raw description is extremely short (e.g., one sentence), still run the full formalization and clarification loop rather than guessing the rest. The clarification round is the mechanism for filling gaps.
