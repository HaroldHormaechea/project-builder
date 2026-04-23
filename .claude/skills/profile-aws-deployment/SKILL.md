---
name: profile-aws-deployment
description: Opt-in profile. AWS is the preferred cloud provider. Any AWS-based suggestion or solution MUST include a cost estimation table — per-service daily / monthly / yearly costs and cumulative totals that account for both newly proposed services AND pre-existing AWS services already in use by the project. Only invoke when PROJECT_BRIEF.md's `## Profiles` section lists this skill by name. Do NOT auto-invoke on arbitrary cloud or deployment discussions.
---

# Profile — AWS Deployment

Opinionated cloud-deployment conventions for projects that deploy to AWS. Apply only when `PROJECT_BRIEF.md` → `## Profiles` lists `profile-aws-deployment`.

## Precedence

`PROJECT_BRIEF.md` > this profile > model defaults. If the brief pins a different cloud provider or overrides any rule below, follow the brief and surface the conflict.

## Rules

### 1. AWS is the preferred cloud provider

- When proposing or designing cloud deployment, default to AWS services unless `PROJECT_BRIEF.md` → `## Deployment` explicitly records a different provider.
- If the brief already pins AWS, do not propose alternatives mid-feature — the decision is made.
- For multi-cloud or hybrid projects, this profile's cost rule still applies to the AWS portion.

### 2. Every AWS suggestion MUST include a cost estimation table

Any response, proposal, ADR, or design note that recommends, adds, or modifies AWS services **must** include a cost table. No exceptions — not even for "small" additions or "temporary" infrastructure. The absence of a cost table is grounds for the challenger to send **Request revision** (Major).

**Prescriptive table format:**

| Service | Usage assumption | Unit cost | Daily | Monthly | Yearly | Status |
|---|---|---|---|---|---|---|
| `<AWS service + SKU>` | `<concrete: hours, GB-months, req/s, GB-transfer>` | `<$ / unit>` | `$X.XX` | `$X.XX` | `$X.XX` | New / Pre-existing |
| ... | | | | | | |
| **Subtotal — new** | | | `<sum>` | `<sum>` | `<sum>` | |
| **Subtotal — pre-existing** | | | `<sum>` | `<sum>` | `<sum>` | |
| **Total** | | | `<sum>` | `<sum>` | `<sum>` | |

**Required table elements:**

- **Per-service rows** with concrete usage assumptions (instance type + hours per day, GB-months, requests per day, data-transfer GB). Vague assumptions like "low traffic" are not acceptable — turn them into numbers, however rough.
- **Status column** — every row marked `New` (added or modified by this proposal) or `Pre-existing` (already in use for the project).
- **Subtotals** — one row for new, one for pre-existing.
- **Total** — cumulative impact across new + pre-existing.
- **All monetary values in USD**, rounded to two decimals.

**Required notes below the table:**

- **Region** used for pricing (default: `us-east-1` unless the brief specifies otherwise).
- **Pricing basis** — On-Demand / Reserved / Savings Plan / Spot. State per row if mixed.
- **Free tier handling** — note any row partially or fully covered by the AWS Free Tier. Do not silently net it out of totals; show gross, then the discount separately.
- **Pricing date and source** — the date prices were looked up and the source (AWS Pricing Calculator, service pricing page URL, etc.). Prices drift — the date makes the estimate auditable.
- **Variance** — for usage that is hard to bound (Lambda invocations, S3 egress, CloudWatch ingestion, DynamoDB on-demand), provide a **low / expected / high** band rather than a single number, and call out the driving assumption for each.

### 3. Pre-existing services — sourcing the footprint

Before building the table, identify the project's pre-existing AWS footprint:

- Read `PROJECT_BRIEF.md` → `## Deployment` (and `## Architecture` if it lists AWS services) for what is already in use.
- If the brief is silent or incomplete, ask the user what is already running in AWS for this project before producing the table. **Do not invent a footprint.**
- If the user confirms "nothing yet," the table still includes a zero-row Pre-existing subtotal — do not omit the structure, because the next proposal will need it.

### 3a. Pricing-lookup procedure (mandatory)

Before populating the cost table, the agent MUST look up current prices via `WebFetch` — **not** from training data. Training-data prices drift fast and confident-looking numbers are worse than honest uncertainty.

**Preferred source — Vantage** (https://instances.vantage.sh/). Vantage publishes per-instance pricing for the services listed below in a consistent, scrapable format. Use Vantage first for:

- **EC2** — `https://instances.vantage.sh/aws/ec2/<instance-type>` (e.g., `.../ec2/t3.medium`). List view at `https://instances.vantage.sh/`.
- **RDS** — `https://instances.vantage.sh/aws/rds/<instance-type>` (e.g., `.../rds/db.t3.medium`). List view at `https://instances.vantage.sh/rds/`.
- **ElastiCache** — `https://instances.vantage.sh/aws/elasticache/<node-type>` (e.g., `.../elasticache/cache.t3.medium`). List view at `https://instances.vantage.sh/elasticache/`.
- Other instance-based services Vantage covers (OpenSearch, Redshift, etc.): prefer Vantage when available.

**Fallback — AWS official pricing pages** for services Vantage does not cover (or if a Vantage fetch fails):

- `https://aws.amazon.com/s3/pricing/`
- `https://aws.amazon.com/lambda/pricing/`
- `https://aws.amazon.com/dynamodb/pricing/`
- `https://aws.amazon.com/cloudfront/pricing/`
- `https://aws.amazon.com/<service>/pricing/` for anything else.

For every row:

1. `WebFetch` the appropriate source (Vantage first if applicable, AWS page otherwise).
2. Capture the **exact URL and the fetch date** for each row. Both go in the required "Pricing date / source" note below the table.
3. Show the math explicitly: `unit price × usage = line total`, rounded to two decimals in USD.

If `WebFetch` is not available in the agent's tool set, or every attempted fetch fails (including the fallback), the agent MUST stop and ask the user for current prices — NEVER invent values or rely on training data. Produce the table structure with the affected rows marked `TBD — awaiting user-supplied prices` rather than fabricating numbers.

### 4. Cost-conscious service selection

When two AWS services achieve the same outcome at materially different cost profiles, mention both in the proposal with their cost rows, and recommend one with the tradeoff stated. Typical forks:

- Fargate vs. EC2 for a containerized workload.
- RDS vs. Aurora vs. DynamoDB for relational-ish storage.
- ALB vs. API Gateway vs. CloudFront-only for HTTP entry.
- Managed (MSK, OpenSearch, ElastiCache) vs. self-hosted-on-EC2.
- Lambda vs. ECS/Fargate for event-driven workloads.

One alternative, with a one-line tradeoff, is enough — not exhaustive comparison.

### 5. IaC and deployment posture

- Infrastructure changes MUST be expressed in IaC (Terraform, CDK, CloudFormation, or SAM — whichever the brief records). No proposals that would require console-only changes.
- Per-environment parameterization (dev / staging / prod) is expected. Cost tables state which environment they represent; if a proposal spans multiple environments, produce one table per environment.
- Use managed identities (IAM roles) wherever the AWS service supports them — never static access keys baked into application config.

## How each role applies this profile

- **Analyst** — build the cost table as part of the Proposed Solution. Block your own proposal submission until the table is complete and the pre-existing footprint is confirmed with the user (if the brief is silent).
- **Challenger** — if an AWS-adding proposal lacks the cost table, or the table uses vague usage assumptions, send **Request revision** (Major). If subtotals and totals do not reconcile with per-row figures, that is **Critical** — the table is actively misleading.
- **Developer** — IaC changes go in the IaC module declared by the brief. Do not create infrastructure out of band (console clicks, ad-hoc CLI provisioning). If implementation reveals the real usage profile differs materially from the analyst's assumptions (e.g., a larger instance is needed), report back so the analyst can revise the proposal and the table.
- **QA** — not typically involved in cost figures, but if the brief mandates infra tests (Terratest, `terraform validate`, LocalStack integration), cover them with the project's test framework.

## Non-goals

- Organization-wide AWS account structure, SSO, or Landing Zone guidance.
- Detailed security baselines (IAM least privilege, KMS policy, VPC peering) — out of scope here; these belong in the brief's security section or a dedicated future profile.
- Multi-region DR strategy — handled by `PROJECT_BRIEF.md` → `## Deployment` → `dr`.
- Non-AWS clouds.
