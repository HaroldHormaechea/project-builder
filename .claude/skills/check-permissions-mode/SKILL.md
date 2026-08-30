---
name: check-permissions-mode
description: Check whether the current Claude session was launched with --dangerously-skip-permissions. Inspects the command line of this session's own claude process ($CLAUDE_PID) and reports yes/no via the command's exit code. Works on Windows, Linux/WSL, and macOS.
---

Run this command from `SESSION_DIR` and read its **exit (return) code** — do not parse its stdout:

```
bash .claude/scripts/check-bypass-permissions.sh
```

The command intentionally produces **no output**; the assessment is driven entirely by the exit code:

- **Exit code `0` → bypass permissions is OFF** (the session was *not* launched with `--dangerously-skip-permissions`).
- **Exit code `1` → bypass permissions is ON** (the session *was* launched with `--dangerously-skip-permissions`).

Report the answer in one sentence ("bypass permissions is ON/OFF"). No other output.

## How it decides

The script reads the command line of exactly one process: **this session's own claude process**, whose PID the harness publishes as `$CLAUDE_PID`. If that command line contains `--dangerously-skip-permissions`, bypass is ON.

It resolves the command line per platform, because no single method works everywhere:

| Platform | Source |
|---|---|
| Linux / WSL | `/proc/$CLAUDE_PID/cmdline` |
| macOS / other POSIX | `ps -p "$CLAUDE_PID" -o args=` |
| Windows (Git Bash / MSYS) | `powershell.exe … Get-CimInstance Win32_Process -Filter "ProcessId=$CLAUDE_PID"` |

Why the exit code rather than the output: output filters/proxies in the user's shell (e.g. RTK token compression) can rewrite or strip stdout, which would corrupt an output-based check. The exit code is unaffected, so it is the single source of truth.

## Why not `ps aux | grep`

The previous implementation scanned the whole process table:

```
! ps aux | grep -q "[c]laude.*dangerously-skip-permissions"      # DO NOT USE
```

That is wrong in two independent ways, both confirmed by testing:

1. **It can never return ON on Windows.** Under Git Bash, `ps` lists only MSYS processes and never sees the native `claude.exe`, so the pattern cannot match and the inverted exit code is always `0` — i.e. it silently reports "bypass OFF" on every Windows session, including sessions that really were launched with the flag.
2. **It matches unrelated processes.** Any process whose command line merely *quotes* the flag matches too. A `claude -p "…--dangerously-skip-permissions…"` invocation puts that text into the command line of every shell in the pipeline; a table-wide scan matched 8 processes when only 1 was a real bypass session.

Scoping the check to `$CLAUDE_PID` removes both failure modes: it asks about this session and nothing else.

## Known limitation

This detects the **launch flag**. It does not detect bypass reached another way — a `defaultMode: "bypassPermissions"` in `settings.json`, or a permission mode changed at runtime — because neither appears in the process command line. If `$CLAUDE_PID` is unset or the process cannot be inspected, the script reports OFF: the conservative answer, since the caller then shows a permissions prompt it may not have needed rather than skipping one it did need.
