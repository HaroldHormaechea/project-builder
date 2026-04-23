---
name: define-overview
description: Capture the high-level definition of a project — problem, target users, value proposition, scope boundaries, non-goals, and success criteria. Use when the project-builder agent is gathering overview information.
---

# Purpose

Produce a crisp, shared understanding of **what** the project is and **why** it exists, before any technical discussion.

# Questions to ask (in order)

1. Working name for the project.
2. One-sentence problem statement: what pain or opportunity does it address?
3. Primary users (persona + context of use). Allow up to three.
4. Value proposition: why would a user pick this over doing nothing or using an alternative?
5. Maturity target: Prototype, MVP, or Production.
6. In-scope: the 3–5 capabilities the project must deliver.
7. Non-goals: the 3–5 things it explicitly will not do (critical for boundary-setting).
8. Success criteria: how you will know it works (qualitative or quantitative).

Use `AskUserQuestion` for multi-choice items (maturity target, audience breadth, differentiation axis). Free-text the rest.

# Solution space to present

When the user is unsure, offer these framings as prompts (not prescriptions):

- **Maturity target**: *Prototype* (proves the idea) / *MVP* (usable by early adopters) / *Production* (reliable, multi-user).
- **Audience breadth**: *Personal or internal tool* / *Small team* / *Wider community* / *Commercial customers*.
- **Differentiation axis**: *Cheaper* / *Faster* / *Simpler* / *More capable* / *More private* / *More integrated*.

# Required schema (must be captured)

- `name`
- `problem`
- `users` (list)
- `value_proposition`
- `maturity_target`
- `in_scope` (list)
- `non_goals` (list)
- `success_criteria` (list)

# Output

Write to `PROJECT_BRIEF.md` in the target folder under a `## Overview` heading with these fields, one per line. Replace any prior `## Overview` section when re-run.

# Frontmatter contribution

Update these YAML frontmatter fields (see `CLAUDE.md` for the full schema). Leave every other field untouched:

- `project.name` — the working name
- `project.target_dir` — the absolute path `TARGET_DIR`
- `project.maturity_target` — `prototype`, `mvp`, or `production`
