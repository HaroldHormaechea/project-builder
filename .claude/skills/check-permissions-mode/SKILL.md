---
name: check-permissions-mode
description: Check whether the current Claude session was launched with --dangerously-skip-permissions. Run `ps aux`, find the claude process, and report yes/no.
---

Run this shell command and report the result:

```
ps aux | grep "claude.*dangerously-skip-permissions" | grep -v grep
```

If the command produces output: the session **is** running with `--dangerously-skip-permissions` (bypass permissions ON).
If the command produces no output: bypass permissions is **OFF**.

Report the answer in one sentence. No other output.
