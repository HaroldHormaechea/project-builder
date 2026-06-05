---
name: generate-release
description: Generate a proper GitHub release description for a target project from the ACTUAL changes since the previous release tag — never by copying the prior release's notes. Produces a bullet-pointed "New features" section (each feature bullet up to 200 words) and a "Bugfixes" section (each bugfix bullet at most 50 words), with every bullet linking to the use case(s) it came from, then writes it to the release. Use whenever a release is cut for a target project (any release tag — a single `vX.Y.Z`, or per-component tags like `<component>-vX.Y.Z`), or standalone to (re)write the notes of an existing release.
---

# Generate Release

Write release notes that describe **what actually changed in this release**, derived from the commit / PR / use-case diff since the previous tag. This skill exists to kill a specific failure mode: release bodies that are copied forward release after release, so the notes keep "talking about the same crypto change for ages" while the real changes go undocumented. Every line you emit must be traceable to a change in *this* tag's range.

The output has exactly two sections, each a **bullet list**:

- `## New features` — one bullet per feature; **each** bullet up to **200 words**.
- `## Bugfixes` — one bullet per fix; **each** bullet at most **50 words**.

The word caps are **per individual bullet**, not per section. Every bullet **links to the use case(s) it came from** wherever a use case exists.

## Hard rules (the whole point of this skill)

1. **Never read, copy, or paraphrase the previous release's notes/body.** Do not run `gh release view <prev> --json body`. Generate solely from the code/commit diff in this release's range. If you find yourself reusing a sentence from an older release, that is the exact bug this skill prevents — stop and re-derive from the diff.
2. **Every bullet traces to a change in the range.** No carried-over items, no boilerplate, no aspirational/roadmap entries.
3. **No fabrication.** If a section has nothing in the range, write the explicit empty marker (below) — never invent content to fill space.
4. **Respect the per-bullet word caps.** Each individual feature bullet ≤ 200 words; each individual bugfix bullet ≤ 50 words. The caps are per bullet, not per section. Count each bullet's words and tighten any that overflow.
5. **Link each bullet to its use case(s).** Where a change maps to one or more use cases, end the bullet with a link to each (see Step 4 for the link form). A change with no use case links its PR / commit instead.
6. **This skill writes the release *description* only.** It never creates tags, pushes, or triggers a release build. Tag creation stays with the release command / orchestrator.

## Preconditions

- `TARGET_DIR` is the target project's git repo. Resolve `SESSION_DIR` with `pwd`; never write anything inside `SESSION_DIR` — this skill only edits a GitHub release on the target's remote and reads the target's history.
- The repo has a GitHub remote and `gh` is authenticated (`gh auth status`). If not, stop and tell the user.
- You know (or can resolve) the release tag these notes are for — call it `T_new`.

## Step 1 — Resolve the track and the tag range

1. **`T_new`** — the tag this release is for (e.g. `v1.4.0`, or a per-component tag like `<component>-v2.3.0`). If the user didn't give it, list recent tags (`git -C <TARGET_DIR> tag --sort=-creatordate | head`) and pick / confirm the one being released. `T_new` may already be tagged, or you may be writing notes just before tagging — both are fine.

2. **Track** — some repos ship multiple release tracks, each with its own tag prefix (e.g. `<component>-vX.Y.Z`). Derive the track from `T_new`'s prefix (the part before the `-v` / trailing version). The track scopes which changes belong in these notes, so a release for one component never lists another component's work:
   - If `PROJECT_BRIEF.md` frontmatter declares release tracks (a `release.tracks` mapping of prefix → paths), use that verbatim — it is the authoritative source.
   - Else, if the prefix names a top-level directory or build module in the repo, scope the change set to that path.
   - Otherwise (a plain `vX.Y.Z` tag, single-component repo, or an unrecognized prefix), the track is the whole repo — no path scoping.

3. **`T_prev`** — the previous release tag *of the same track*: `git -C <TARGET_DIR> tag --list '<prefix>-v*' --sort=-v:refname` and take the newest entry that is not `T_new`. If there is no earlier track tag, this is the **first release** of the track — use the repo's first commit as the base and label it accordingly.

4. **Range** — `T_prev..T_new` if `T_new` is already tagged, else `T_prev..HEAD` (the commit being released, usually `origin/<default-branch>`). If the range is empty (`T_new` points at the same commit as `T_prev`), STOP and tell the user there are no changes to release — do not write notes.

## Step 2 — Gather the actual changes (scoped to the track)

Pull from several sources and reconcile them; richer than raw commit subjects:

- **Commits:** `git -C <TARGET_DIR> log --no-merges <range> -- <track paths>` (omit `-- <paths>` when the track is the whole repo). Capture subjects **and** bodies.
- **Merged PRs:** squash commits carry `(#NN)`. For each, `gh pr view <NN> --json title,body,labels` (run with `cwd: <TARGET_DIR>`) — the PR body usually states the user-facing change and what was tested far better than the commit subject.
- **Use cases:** if any files under the brief's `use_cases.folder` were added/changed in the range, read each one's `## Summary` — it is the cleanest human-facing description of the capability. The ledger (`use_cases.index`) tells you which UCs went `done` recently.
- **Product context:** read `PROJECT_BRIEF.md` for the project's name, audience, and terminology so the notes use the product's own words, not internal class names.

## Step 3 — Classify and deduplicate

Sort each change into **feature** or **bugfix**, and drop noise:

- **New feature** — adds or expands user-visible capability. Signals: conventional `feat`/`feat(...)`, a use case that introduces new behavior, a PR labeled `enhancement`/`feature`.
- **Bugfix** — corrects broken behavior. Signals: conventional `fix`/`fix(...)`, regression fixes, a PR labeled `bug`.
- **Drop from the notes** — `chore`, `ci`, `build`, `test`, `refactor`, and pure-internal `docs` with no user-visible effect. Do not pad the notes with these. (A doc change that alters a user-facing contract may earn a short feature/fix line.)
- **Deduplicate** — collapse the squash-PR and its constituent commits into one item; merge multiple commits of one logical change into a single bullet. One change → one bullet.

## Step 4 — Write the two sections (bullets, per-bullet caps, UC-linked)

Write for the person installing the release — the change and its benefit, not the implementation. Use the project's terminology. Both sections are **bullet lists**; one bullet per logical change, impact-ordered.

**Linking each bullet to its use case(s).** Resolve the repo slug once: `gh repo view --json nameWithOwner -q .nameWithOwner` (cwd `<TARGET_DIR>`). Pick the ref for permalinks: `T_new` if it is already tagged, else the default branch. For every use case a bullet covers, append a Markdown link:

```
[UC-<NN>](https://github.com/<owner>/<repo>/blob/<ref>/<use_cases.folder>/<file>)
```

`<NN>` is the use case's zero-padded number (from its filename); `<file>` is the use-case filename; `<use_cases.folder>` comes from the brief frontmatter (default `use-cases/`). A bullet that maps to several use cases links each. A bullet with **no** use case (a change made outside the use-case flow) links its PR instead — `[#NN](https://github.com/<owner>/<repo>/pull/NN)` — or, failing that, the commit.

```markdown
## New features

- <Most impactful capability — what it does and why it helps, in the user's terms.> ([UC-12](…/use-cases/12-….md))
- <next feature, possibly spanning two use cases> ([UC-15](…), [UC-16](…))

## Bugfixes

- <Terse one-line fix.> ([UC-24](…/use-cases/24-….md))
- <fix with no use case> ([#41](…/pull/41))
```

Caps and empties:
- **Per feature bullet:** ≤ **200 words** (the link does not count). Most features need far fewer — use the budget only when a feature genuinely warrants explanation.
- **Per bugfix bullet:** ≤ **50 words**. Keep them to a crisp line.
- After drafting, **count each bullet's words** and tighten any that overflow its cap; do not merge unrelated changes just to save words.
- If a section has no items in the range, write the explicit marker — never invent content: `## New features` → `_No new features in this release._`; `## Bugfixes` → `_No bug fixes in this release._`

## Step 5 — Apply to the release

Write the body to a temp file (e.g. `/tmp/release-notes-<T_new>.md`), then:

- **If the release already exists** (a release workflow typically auto-creates it on tag push — and auto-notes are exactly the stale content to replace): `gh release edit <T_new> --notes-file <file>` (run with `cwd: <TARGET_DIR>`). This overwrites the auto-generated/stale body.
- **If the release does not exist yet and the user wants you to create it:** `gh release create <T_new> --title "<project> <version>" --notes-file <file>`. Prefer `edit` when a release is already present; do not duplicate.

Then show the user the final notes and the release URL (`gh release view <T_new> --json url --jq .url`).

If `T_new` is not yet tagged (you're preparing notes ahead of the tag), do not create the tag — output the notes for the orchestrator/release step to apply, and say so.

## Notes

- Re-running is safe: it recomputes from the range and overwrites the body with `gh release edit`.
- Multi-track repos: run once per track being released, each scoped to its own paths, so each release lists only its own changes.
