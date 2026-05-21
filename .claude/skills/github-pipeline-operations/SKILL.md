---
name: github-pipeline-operations
description: Trigger and monitor GitHub Actions pipelines via the gh CLI — push-triggered workflow_run dispatch, tag-triggered release workflows, PR check rollups, and the polling patterns that reliably exit on terminal states. Includes the exact field names, expected success/failure outputs, and the foot-guns that silently leave polls spinning forever. Use whenever a Claude run needs to wait for CI / a release workflow to finish, or wants to read out a failed step's logs without dumping the full run.
---

# GitHub Pipeline Operations

How to trigger GitHub Actions pipelines, monitor them to terminal state, and read their results, using the `gh` CLI. Written to be picked up by a Claude run that has just pushed a branch / tag / PR and needs to wait for CI to finish before taking the next step (approve, merge, tag the next release, escalate to the user).

## Why this skill exists

Polling GitHub Actions correctly is harder than it looks. `gh pr checks` and `gh run view` expose **different** JSON field names with **different** value vocabularies. A poll written against one and pointed at the other returns `Unknown JSON field: ...` and falls into a silent until-loop that never exits. This skill documents the field-name traps explicitly so a future run does not have to rediscover them mid-flight.

## The two CLI surfaces

There are two distinct surfaces, and the JSON shape is different on each:

| Use this when… | Command | Returns |
|---|---|---|
| You have a **PR number** and want the rollup of every check attached to its head SHA | `gh pr checks <pr>` | one row per check; each row has `state`, `bucket`, `name`, `link`, `workflow`, `completedAt`, `startedAt`, `description`, `event` |
| You have a **workflow run id** (from `gh run list` / a tag push / a PR comment) and want that specific run | `gh run view <run-id>` | a single object with `status`, `conclusion`, `name`, `url`, `databaseId`, plus a `jobs[]` array with per-job `status` + `conclusion` |

**`status` does NOT exist as a `--json` field on `gh pr checks`.** Asking for it returns:

```
Unknown JSON field: "status"
Available fields:
  bucket, completedAt, description, event, link, name, startedAt, state, workflow
```

This is the foot-gun that silently breaks polls. Validate the field name on the first call.

## The value vocabularies

Each surface has its own vocabulary; do not assume case-folding works across them.

### `gh pr checks <pr> --json state`

`state` is the GraphQL `StatusState` enum. Terminal: `SUCCESS`, `FAILURE`, `ERROR`. Non-terminal: `PENDING`, `EXPECTED`. **`COMPLETED` is NOT a value of `state` here** — checking for it will loop forever. This bug was hit twice during this skill's development; prefer `bucket` over `state` for poll exit conditions for that reason.

### `gh pr checks <pr> --json bucket`

`bucket` is a higher-level grouping. Terminal: `pass`, `fail`, `skipping`, `cancel`. Non-terminal: `pending`. Lowercase. Easier to script against than `state` because the terminal set is finite and stable.

### `gh run view <run-id> --json status`

`status` is the workflow-run lifecycle field. Terminal: `completed`. Non-terminal: `queued`, `in_progress`, `waiting`, `requested`, `pending`. Lowercase.

### `gh run view <run-id> --json conclusion`

`conclusion` is the run's outcome — populated **only when `status == completed`**. Values: `success`, `failure`, `cancelled`, `skipped`, `neutral`, `timed_out`, `action_required`, `stale`, `startup_failure`. Lowercase. Empty string while the run is still in flight.

## Triggering pipelines

### Tag-triggered (release workflows)

Standard pattern: a workflow with `on: push: tags: ['<glob>']` (e.g. `'server-v*'`, `'android-v*'`).

```bash
git -C <TARGET_DIR> tag <tag> <sha>
git -C <TARGET_DIR> push origin <tag>
```

The tag push enqueues a workflow run within seconds. Find it via:

```bash
gh -R <owner>/<repo> run list --workflow=<workflow-name> --limit 1 \
    --json databaseId,status,headSha,event,url \
    -q '.[0]'
```

`<workflow-name>` matches `name:` in the YAML, not the filename (e.g. `android-release`, not `android-release.yml`). Verify the `headSha` matches your tagged commit — it is possible (rare) for an unrelated workflow to land first if multiple are triggered.

### Push-triggered (CI on a branch)

`git push` to a branch with `on: push: branches: [...]` triggers a run. Same `gh run list` query.

### PR-triggered (check suites on a PR head SHA)

Opening or updating a PR enqueues runs for any workflow with `on: pull_request:`. Use `gh pr checks <pr>` rather than `gh run list` here — it correctly aggregates across multiple check suites and external status providers (e.g. Codecov posts a status check, not a workflow run).

### Manual dispatch (workflow_dispatch)

```bash
gh -R <owner>/<repo> workflow run <workflow-name> \
    --ref <branch-or-tag> \
    -f <input-name>=<value>
```

Wait ~3 seconds for the dispatched run to register, then `gh run list --workflow=<workflow-name> --limit 1` to capture its id. There is no way to get the new run id back from `workflow run` itself.

## Monitoring to terminal state

### The reliable polling pattern (workflow runs)

```bash
until gh -R <owner>/<repo> run view <run-id> --json status -q '.status' 2>/dev/null \
    | grep -q '^completed$'
do
    sleep 30
done
gh -R <owner>/<repo> run view <run-id> --json status,conclusion,url
```

Key properties of the working pattern:

- **`--json status`** (lowercase scalar) + **`-q '.status'`** scalar extraction.
- **`grep -q '^completed$'`** anchored on both ends — so a future intermediate state like `completion_pending` (none currently, but reserve the option) does not falsely match.
- **`2>/dev/null`** swallows transient API errors (rate-limit blips) so the loop survives them; the next iteration retries.
- **Spaced 30s** — workflows take minutes; polling faster wastes API budget without faster signal.

When the loop exits, the **second** `gh run view` call prints both `status` and `conclusion` so the caller can branch on outcome.

### The reliable polling pattern (PR check rollup)

```bash
while true; do
    output=$(gh -R <owner>/<repo> pr checks <pr> --json bucket -q '.[].bucket' 2>/dev/null)
    if [ -n "$output" ] && ! echo "$output" | grep -q '^pending$'; then
        break
    fi
    sleep 30
done
gh -R <owner>/<repo> pr checks <pr>
```

A PR rollup has multiple checks. The exit condition combines two defenses:

1. `[ -n "$output" ]` — require non-empty output. A transient `gh` failure (network blip, GitHub API hiccup) returns exit-non-zero AND empty stdout. Without this guard, an empty string from gh gets piped into `grep -q '^pending$'`, grep finds no matches, the negation flips to true, the loop exits — and the harness reports completion on the next gh call's exit code, with no real signal about whether CI is actually done. Empty output ≠ "all checks done."
2. `! echo "$output" | grep -q '^pending$'` — no row says pending. `grep -q '^pending$'` exits 0 if ANY line is `pending`; the `!` inverts that. Together: "no row says pending."

The loop holds while gh fails OR at least one check is still `pending`; it exits the first iteration where gh succeeds AND no row is pending. The follow-up `gh pr checks <pr>` (no `--json`) prints the human-readable table so the caller can see which check(s) ended in `fail`.

**Note on the follow-up `gh pr checks` exit code**: gh documents exit code 8 for "any check is pending or failing." If a check ended in `fail`, the whole shell script exits 8 even though the loop did its job. Read it as "exited normally; some checks failed; see the table." If you need a structured success/fail signal at the script level, capture the bucket list a second time and compare against `pass`.

**Common foot-guns** that broke earlier versions of this same skill:

1. Writing `grep -vq '^pending$'` instead of `! grep -q '^pending$'`. `grep -v` succeeds if ANY line is *non-pending*, which exits the loop the moment the first check finishes — leaving slower checks still running. Verified the fix on PR #15 of `ai-sandbox` 2026-05-21.
2. Omitting the `[ -n "$output" ]` guard. A transient gh API blip empties the stdout pipeline, the negation-of-grep-on-empty flips true, and the loop exits prematurely. Verified the fix on the same PR — second poll iteration. The lesson: an empty output from gh is **never** evidence that polling is complete; it's evidence the API call failed.

### What NOT to do

Each of these silently breaks polling — the loop's condition is always false and the until-loop spins forever:

| Mistake | Why it breaks |
|---|---|
| `gh pr checks <pr> --json status` | `status` is not a field on `gh pr checks`; CLI prints an "Unknown JSON field" error to stderr; `-q` extracts empty; loop never exits |
| `[ "$(...)" = "COMPLETED" ]` against `gh pr checks --json state` | `state` returns `SUCCESS` / `FAILURE` for terminal checks, never `COMPLETED` |
| `[ "$(...)" = "completed" ]` against `gh run view --json conclusion` | `conclusion` is `success` / `failure` for completed runs, never `completed` |
| `gh run view ... --json status -q .status | grep completed` (no anchors) | also matches `completed_at` or any future status containing the substring; low-risk today, but a one-character `^…$` fix avoids the trap |
| Polling without `sleep` between iterations | Hits the GitHub API rate limit on long runs; the limit error returns no JSON, the condition becomes "no match," loop continues to hammer |
| Polling without `2>/dev/null` and without a max-iteration cap | Transient API failures get swallowed in stdout-vs-stderr crossfire; subtle |

### Pre-flight validation

Before launching any long-running poll, **call the underlying query once synchronously** and confirm:

1. The field name actually exists (`gh ... --json help` is not supported — easiest is to run `gh ... --json <field> -q '<path>'` once and check stderr for "Unknown JSON field").
2. The value you are testing against actually appears for an *in-flight* run, not just a completed one.
3. The exit condition will plausibly be reached — e.g. test the same command against a previously-completed run and confirm the value you expect.

A 30-second smoke test prevents a half-hour silent spin.

## Reading results

### Successful run

```json
{"status":"completed","conclusion":"success","url":"https://github.com/..."}
```

Proceed to the next step in the caller's flow.

### Failed run

```json
{"status":"completed","conclusion":"failure","url":"https://github.com/..."}
```

Read the failure with **`--log-failed`**, which filters to steps whose conclusion was `failure`:

```bash
gh -R <owner>/<repo> run view <run-id> --log-failed 2>&1 \
    | rg -e 'e: file' -e 'error:' -e 'FAILED' -e '##\[error\]' \
    | head -30
```

The `rg` filter is necessary — `--log-failed` is still verbose (license texts, environment dumps, post-action cleanup). The four patterns above catch Kotlin compile errors, generic tool errors, Gradle's `FAILED` marker, and GitHub Actions' `##[error]` annotations respectively.

For a specific job in a multi-job workflow:

```bash
gh -R <owner>/<repo> run view <run-id> --job <job-id> --log 2>&1 | rg -e 'error' -e 'FAIL'
```

`<job-id>` comes from `gh run view <run-id> --json jobs -q '.jobs[] | select(.conclusion=="failure") | .databaseId'`.

### Cancelled / timed-out run

```json
{"status":"completed","conclusion":"cancelled"}
{"status":"completed","conclusion":"timed_out"}
```

Treat as failure for poll-exit purposes. Surface to the user — these are not autonomously recoverable.

### Skipped run

```json
{"status":"completed","conclusion":"skipped"}
```

Means the workflow's `if:` condition or path filter excluded it. Not a failure, but the caller's expectation that the run validated the change is now false; treat as "I do not know whether the change is good" and surface that to the user.

## Approving and merging PRs

### Approving

```bash
gh -R <owner>/<repo> pr review <pr> --approve --body "<rationale>"
```

**Self-approval is blocked by GitHub.** If the current `gh auth` user is the PR author, the call fails with:

```
failed to create review: GraphQL: Review Can not approve your own pull request (addPullRequestReview)
```

This is a hard GitHub constraint, not something the CLI can work around. Options:

1. The PR author cannot approve their own PR. If the autonomous flow requires an approval and the bot account is also the author, the approval step must be skipped or routed to a different reviewer.
2. If the branch protection rules require an approval before merge, the merge will be rejected too — the flow needs a human checkpoint at this gate.
3. If the repo allows self-merge without prior approval (no required-review rule), `gh pr merge` works directly without `gh pr review --approve` first.

### Merging

```bash
gh -R <owner>/<repo> pr merge <pr> --squash --delete-branch
```

Flags by repository convention:
- `--squash` (default for most projects; a single PR commit lands on main)
- `--merge` (preserves all per-slice commits on main)
- `--rebase` (replays commits on main without a merge commit)

Match the repo's existing style — inspect a recent merged PR (`gh pr view <recent-pr> --json mergeCommit,commits`) before picking.

`--delete-branch` removes the head branch from origin after merge. Safe default for short-lived feature branches; omit for long-lived integration branches.

### What NOT to use

- **`gh pr merge --auto`** schedules an automatic merge as soon as required checks pass. Tempting for autonomous flows but **dangerous** — if a check fails the auto-merge is held in a pending state and there is no `gh` command that surfaces this clearly. Prefer explicit blocking poll + explicit merge.
- **`gh pr merge --admin`** bypasses branch protections. Never use this without explicit per-PR user authorization.

## Triggering a release

The common shape across this workspace's target projects:

1. Merge the feature PR to the default branch.
2. Tag the merge commit with the release tag (`<component>-vX.Y.Z`).
3. Push the tag; the tag-triggered release workflow handles building + uploading artifacts + creating the GitHub Release.

```bash
git -C <TARGET_DIR> checkout <default-branch>
git -C <TARGET_DIR> pull --ff-only
git -C <TARGET_DIR> tag <release-tag> <merge-sha>
git -C <TARGET_DIR> push origin <release-tag>

# Wait ~5s for the workflow to register, then capture its id:
RUN_ID=$(gh -R <owner>/<repo> run list \
    --workflow=<release-workflow-name> --limit 1 \
    --json databaseId -q '.[0].databaseId')

# Then poll using the workflow-run pattern from above.
```

The release workflow's output is a GitHub Release object (visible at `https://github.com/<owner>/<repo>/releases/tag/<release-tag>`). Verify with:

```bash
gh -R <owner>/<repo> release view <release-tag> --json name,createdAt,assets
```

`assets` should list the expected artifacts (e.g. `.apk`, `.aab`, `.deb`, `.jar`); an empty list means the workflow ran but failed to attach files — read the failed step.

## Summary checklist (when in doubt)

Before launching a poll:

- [ ] Did I confirm the field name exists with one synchronous test call?
- [ ] Did I confirm the value-string I am comparing against appears for the terminal state I want to detect?
- [ ] Is my `until` loop pattern `grep -q '^<value>$'`-anchored?
- [ ] Did I `2>/dev/null` to swallow transient API errors?
- [ ] Is the sleep between iterations ≥ 30s?
- [ ] If the run fails, do I have a follow-up command that surfaces *which step* failed (not just "the run failed")?

If you can answer yes to all six, the poll will reliably exit on terminal state — pass or fail — and will not silently spin.
