---
name: check-permissions-mode
description: Check whether the current Claude session was launched with --dangerously-skip-permissions. Run `ps aux`, find the claude process, and report yes/no via the command's exit code.
---

Run this shell command and read its **exit (return) code** — do not parse its stdout:

```
! ps aux | grep -q "[c]laude.*dangerously-skip-permissions"
```

The command intentionally produces **no output**; the assessment is driven entirely by the exit code:

- **Exit code `0` → bypass permissions is OFF** (the session was *not* launched with `--dangerously-skip-permissions`).
- **Exit code `1` → bypass permissions is ON** (the session *was* launched with `--dangerously-skip-permissions`).

Why the exit code rather than the output: output filters/proxies in the user's shell (e.g. RTK token compression) can rewrite or strip stdout, which would corrupt an output-based check. The exit code is unaffected, so it is the single source of truth. The `grep -q` keeps stdout empty, the leading `!` inverts grep's natural result (match → bypass ON) into the requested `0`=OFF / `1`=ON convention, and the `[c]laude` bracket pattern stops grep from matching its own process, so no `grep -v grep` is needed.

Report the answer in one sentence ("bypass permissions is ON/OFF"). No other output.
