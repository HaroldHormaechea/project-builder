---
name: define-monetization
description: Capture the monetization and distribution model of the project — business model, pricing tiers, target market, licensing, and any non-commercial framing. Use when the project-builder agent is gathering monetization information.
---

# Purpose

Decide how the project sustains itself — or explicitly that it does not need to. This framing influences later technical choices (auth, billing, multi-tenancy, infrastructure cost profile).

# Questions to ask (in order)

1. Is there a commercial intent, or is the project non-commercial (personal, internal, open-source, research)?
2. If commercial: which model best fits (see solution space).
3. If open-source: intended license, contribution model, and any commercial overlay (hosted service, paid support, enterprise edition).
4. Target market segments (e.g., individual developers, SMBs, enterprise, a specific industry or region).
5. Pricing anchors (if applicable): prices in the space that feel right or wrong as reference points.
6. Tiers or packaging (if applicable): what differentiates free vs. paid levels.
7. Constraints: ethical, legal, or compliance considerations (e.g., no ads, no data resale, regulated industry, geographic restrictions).

Use `AskUserQuestion` for the commercial/non-commercial choice and the model selection.

# Solution space to present

- **Non-commercial**: personal tool, internal tool, open-source (MIT / Apache-2.0 / BSD / MPL / GPL / AGPL), research artifact.
- **One-time purchase**: desktop or mobile app with a single price; optional paid upgrades.
- **Subscription / SaaS**: monthly or annual; flat, per-seat, or usage-based; optional free tier.
- **Freemium**: free core product, paid premium features or higher limits.
- **Usage / metered**: pay per API call, per GB, per job.
- **Marketplace / transaction fee**: cut of value exchanged on the platform.
- **Advertising**: free to users, monetized via ads or sponsorships.
- **Open-core**: OSS core plus commercial hosted or enterprise edition.
- **Donations / sponsorship**: GitHub Sponsors, OpenCollective, Patreon.

When the user is undecided, present 2–3 candidates with one-line tradeoffs (billing complexity, infrastructure implications, user friction, compliance exposure). Do not push a favorite.

# Required schema

- `commercial_intent` (yes/no)
- `model` (one of the options above, or `"none"`)
- `license` (if applicable)
- `target_market` (list)
- `tiers` (list of `{name, includes, price_anchor}`; empty if not applicable)
- `constraints` (list)

# Output

Write to `PROJECT_BRIEF.md` under a `## Monetization` heading. Replace any prior `## Monetization` section when re-run.
