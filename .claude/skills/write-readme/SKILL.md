---
name: write-readme
description: Generate or update a README.md in a target project folder. Reads PROJECT_BRIEF.md for context and produces a concise, honest README that avoids common LLM-writing pitfalls (marketing adjectives, empty badges, fake quick-start commands, emoji clutter, premature roadmap sections). Use during scaffolding once PROJECT_BRIEF.md is complete, or standalone to refresh an existing README.
---

# Write README

Produce a `README.md` in `TARGET_DIR` that an engineer arriving at the repository would actually find useful. The README serves humans landing on the repo page; it is not a duplicate of `PROJECT_BRIEF.md` (the machine contract) or of any internal documentation.

## Preconditions

- `TARGET_DIR` must contain a `PROJECT_BRIEF.md`. If not, stop and ask the user to run `project-builder` first.
- Never write inside `SESSION_DIR`.
- Never generate a README for the `project-builder` workspace itself; that workspace's README is maintained by hand.

## Step 1 — Read the brief

1. Read `PROJECT_BRIEF.md`.
2. Parse the YAML frontmatter — structured facts: `project.name`, `stack.languages`, `stack.versions`, `build.tool`, `build.commands`, `profiles`, `deployment.provider`.
3. Read the `## Overview` section for the problem, users, and value proposition.
4. Read `## Architecture` and `## Deployment` for the shape of a realistic quick-start.

## Step 2 — Ask about audience, visibility, and license

Via `AskUserQuestion`:

- **Audience**: contributors (developers modifying the code) / users (consuming the output) / both.
- **Visibility**: public or private repo. Private repos can skip license and contributing boilerplate.
- **License**: open-source license name (`MIT`, `Apache-2.0`, etc.), `Proprietary`, or `Not yet licensed`.

## Step 3 — Draft against the fixed skeleton

Use this skeleton verbatim. No additional top-level sections without a concrete reason.

```markdown
# <project.name>

<One sentence, no adjectives. The problem statement from the brief, compressed.>

## What it does

<Two to four sentences or a short bulleted list. Factual. Name the capabilities that actually exist, nothing aspirational.>

## Requirements

<Concrete: OS, language version from `stack.versions`, build tool from `build.tool`, account types for any external service. Don't invent versions.>

## Quick start

<Exact commands to clone, install, test, and run. Every command must be runnable as-written against a fresh clone. Use `build.commands.test` and related fields verbatim. If commands don't yet exist, say so in one sentence instead of inventing them.>

## Project layout

<Short tree of top-level entries that actually exist on disk. Do NOT invent folders.>

## Known limitations

<Honest list. Include the brief's non-goals and anything obviously missing (no tests yet, single region, stubs not implemented, etc.). Never write "no known issues".>

## License

<One line: the license name, or "Not yet licensed".>
```

## Anti-fluff rules (non-negotiable)

Every draft must pass all of these. If any section violates a rule, regenerate that section before writing the file.

1. **No marketing adjectives.** Banned words include: *seamlessly*, *effortlessly*, *revolutionary*, *powerful*, *cutting-edge*, *leverage*, *empower*, *robust*, *battle-tested*. "Production-ready" is banned unless the brief's `project.maturity_target` is literally `production`.
2. **No fake badges.** No CI, coverage, license, downloads, or community badges unless the corresponding artifact actually exists in the repo. A broken or empty badge is worse than no badge.
3. **No emoji.** Not in headings, not in lists, nowhere. They add no information and harm scanability.
4. **No table of contents** for short READMEs. The skeleton above is not long enough to need one.
5. **No "Why X?" comparison section.** If the project has a differentiator worth stating, put one line in the intro. Do not write a sales page.
6. **No fabricated commands.** Every command in Quick start must be runnable as-written. If an empty scaffold has no runnable commands yet, state that explicitly in one sentence.
7. **No "Coming soon" / roadmap section** unless the user explicitly asks for one. READMEs describe what is, not what might be.
8. **No Contributing / Code of Conduct section** unless `CONTRIBUTING.md` / `CODE_OF_CONDUCT.md` exist in the repo. Empty sections are noise.
9. **No AI attribution in the README.** If the user wants AI attribution, it belongs in commit messages — not in the header, not in a "Built with" line.
10. **No screenshot placeholders.** Include a real screenshot or omit the section. Never `[screenshot placeholder]`.
11. **No "Getting started is easy!"-style transitions.** Skip the transition, show the commands.
12. **Honest limitations are mandatory.** Every README this skill produces includes a "Known limitations" section with at least one real current gap. "No known issues" is not acceptable in a fresh scaffold.

## Step 4 — Review and write

1. Check the draft against every anti-fluff rule. Regenerate any violating section.
2. Cap total length at ~150 lines. If over, trim Project layout or fold Known limitations into the intro paragraph — never shrink honesty to make room.
3. Write to `<TARGET_DIR>/README.md`. If a README already exists and the user did not ask to overwrite, read it, merge conservatively, and report the differences before overwriting.
4. Report what was written with a short bullet summary — do not repeat the full text back.

## When to use which entry point

- **During scaffolding**: `project-builder` may invoke this skill as part of its scaffolding plan once `PROJECT_BRIEF.md` is complete.
- **Standalone**: invoke directly to refresh a stale README on an existing project that already has a brief.
