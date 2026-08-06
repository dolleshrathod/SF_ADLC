# SF_ADLC — Agentic Development Lifecycle for Salesforce

A Salesforce DX project built and maintained by a team of specialized AI agents, coordinated by
a single orchestrator, following a fixed pipeline modeled on a real software development
lifecycle: **design → build → test → review → document → merge → deploy**.

Every feature in this repo — objects, fields, Apex, Flows, permission sets, tests, docs — was
produced by that pipeline rather than hand-written. This README describes how the system works,
who the agents are, and the tech stack underneath.

## How it works

The orchestrator (the main Claude Code session) never writes Salesforce metadata itself. It
delegates every implementation step to a purpose-built subagent, and only steps in directly for
orchestration tasks: gating user confirmation, pushing to GitHub, and calling the Salesforce MCP
server to deploy.

```
Design (creates branch) → Admin (commits metadata) → Developer (commits code)
→ Unit Testing (commits tests) → Code Review → Documentation (commits docs)
                                                              ↓
                                          Orchestrator pushes branch + opens PR (GitHub MCP)
                                                              ↓
                                                    User merges PR on GitHub
                                                              ↓
                                                    DevOps (deploys from main)
```

A single feature branch carries the whole pipeline: `salesforce-design` creates it and every
downstream agent commits to it in turn. Nothing touches `main` until a human merges the pull
request, and nothing deploys to the org until that merge is confirmed.

### Confirmation gates

The pipeline pauses for explicit human sign-off at three points:

1. **Gate 1 — after design**: the plan (admin vs. dev split, clarifying questions resolved) is
   presented before any branch or code exists. User answers yes / no / changes.
2. **Gate 2 — after code review**: the verdict (`APPROVED`, `APPROVED WITH WARNINGS`, or
   `CHANGES REQUIRED`) is shown before documentation runs. `CHANGES REQUIRED` offers fix / skip /
   cancel.
3. **Gate 3 — inside devops**: after the user confirms the PR is merged, the exact component list
   is shown before the real deploy. Approve / partial / cancel.

## The agents

| Agent                                                                    | Model  | Role                                                                                                                                                                                                                                                                                   |
| ------------------------------------------------------------------------ | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`salesforce-design`](.claude/agents/salesforce-design.md)               | Opus   | Analyzes the request, asks clarifying questions, splits admin vs. programmatic work, and creates the feature branch every other agent commits to.                                                                                                                                      |
| [`salesforce-admin`](.claude/agents/salesforce-admin.md)                 | Sonnet | Declarative work: Custom Objects, Fields, Validation Rules, Page Layouts, Permission Sets, Profiles, Flows. Commits metadata, never deploys.                                                                                                                                           |
| [`salesforce-developer`](.claude/agents/salesforce-developer.md)         | Opus   | Programmatic work: Apex classes/triggers/handlers, LWC, integrations, Queueable/batch jobs. Enforces `with sharing`, `WITH USER_MODE`, no SOQL/DML in loops, trigger-handler-service layering. Commits code, never deploys.                                                            |
| [`salesforce-unit-testing`](.claude/agents/salesforce-unit-testing.md)   | Sonnet | Writes or extends Apex test classes to 90%+ coverage for whatever the developer agent just built. Commits tests, never deploys.                                                                                                                                                        |
| [`salesforce-code-review`](.claude/agents/salesforce-code-review.md)     | Sonnet | Read-only review of the full branch diff against Salesforce best practices. Produces a verdict — nothing merges without passing this gate.                                                                                                                                             |
| [`salesforce-documentation`](.claude/agents/salesforce-documentation.md) | Sonnet | Writes the feature's `docs/*.md` — original request, components created, data flow, security model, known limitations — and commits it as the branch's final commit.                                                                                                                   |
| [`salesforce-devops`](.claude/agents/salesforce-devops.md)               | Opus   | Post-merge only. Validates the merged code (scratch org when available), then hands the orchestrator a dependency-ordered component list to deploy via Salesforce MCP. Has no deploy access itself — deployment is always an orchestrator action, gated by explicit user confirmation. |

Each agent has its own persistent memory directory under `.claude/agent-memory-local/<agent>/`,
where it records durable, project-specific lessons (org quirks, established patterns, prior
mistakes) that carry across sessions without polluting `CLAUDE.md`.

## Git & deployment policy

- **Feature-branch agents commit locally only.** None of them push. Local git on this machine
  authenticates as an identity without push access to this repo, so agent-attempted `git push`
  reliably fails with a 403.
- **The orchestrator pushes and manages PRs via the GitHub MCP server** by default
  (`mcp__github__create_branch`, `push_files`, `create_pull_request`, `merge_pull_request`) —
  this works regardless of the local git credential. Local `git push` is a fallback only, used if
  the GitHub MCP tools are unavailable in a session.
- **Deployment is Salesforce MCP only** — no `sf`/`sfdx project deploy` in the pipeline. The
  orchestrator calls `mcp__salesforce__deploy_metadata` directly against the target org, only
  after the PR is merged and the user has explicitly confirmed the component list at Gate 3.
- Deploy-blocking errors that only surface on a real deploy (org-specific schema constraints,
  Apex compile errors invisible to static review, Flow metadata quirks) get their own small
  follow-up branch → PR → merge → redeploy cycle, rather than being force-fixed on top of an
  already-merged branch.

See `CLAUDE.md` for the full, authoritative set of rules the orchestrator follows — this README
is a companion overview, not a replacement for it.

## What's been built here

Everything under `force-app/main/default/` was produced by the pipeline above. Current features:

- **Order Management** (`docs/2026-08-01-order-management.md`) — `Order__c` object,
  `Order_Amount_Creates_Task` Flow.
- **Opportunity Closed Won → Assets + Inventory**
  (`docs/2026-08-04-opportunity-closed-won-assets.md`) — a Record-Triggered Flow on Opportunity
  that, on the transition into Closed Won, runs an **asynchronous** path to bulk-create standard
  `Asset` records from every `OpportunityLineItem` and calls an invocable Apex action
  (`InventoryDecrementAction`) to bulk-decrement a custom `Inventory__c` object per product —
  built to stay safe at ~150 line items per Opportunity with a single SOQL query and single DML
  statement regardless of volume.

Each feature's `docs/*.md` is the authoritative record of what was built, why, its data flow,
security model, test coverage, and known limitations — written by `salesforce-documentation`
directly from the implemented code, not from the request.

## Tech stack

- **Platform**: Salesforce DX, API version 67.0, no namespace, single package directory
  (`force-app`).
- **Apex**: `with sharing` enforced on all service/handler classes; `WITH USER_MODE` /
  `AccessLevel.USER_MODE` for FLS/CRUD enforcement; trigger → handler → service → selector
  layering; Queueable over `@future`.
- **Declarative**: Record-Triggered Flows (including asynchronous "Run Asynchronously After
  Record Changes" scheduled paths for governor-limit isolation from the synchronous save path),
  Permission Sets, Profiles, custom objects/fields.
- **Frontend**: Lightning Web Components, LDS-first (GraphQL / wire adapters before Apex).
- **Tooling**: `npm` scripts wrapping `sfdx-lwc-jest` (LWC unit tests), ESLint
  (`@salesforce/eslint-config-lwc`, `@salesforce/eslint-plugin-aura`), Prettier
  (`prettier-plugin-apex`, `@prettier/plugin-xml`), Husky + lint-staged pre-commit hooks.
- **Deploy target**: `Agentfrceorg` (Developer Edition), via the Salesforce MCP server — no Dev
  Hub / scratch org available on this machine, so validation happens by deploying with the
  relevant Apex test class specified (`RunSpecifiedTests`), which rolls back the whole deploy
  atomically if the test fails.
- **Source control**: GitHub (`srinialuri/SF_ADLC`), pushed and merged via the GitHub MCP server.

## Prerequisites (for a human working in this repo directly)

- **Salesforce CLI** — [developer.salesforce.com/tools/salesforcecli](https://developer.salesforce.com/tools/salesforcecli)
- **Node.js + npm** — for lint/test/format tooling (`npm install` to set up Husky hooks)
- **A Salesforce org** authenticated as `Agentfrceorg` (or update the alias throughout)
- **GitHub access** to `srinialuri/SF_ADLC` with push permission, if working outside the agent
  pipeline's GitHub MCP path

## Common commands

```bash
npm run lint                  # ESLint over aura/lwc JS
npm run test:unit             # LWC Jest tests
npm run prettier:verify       # check formatting without writing
sf apex run test              # run Apex tests
sf apex run --file scripts/apex/hello.apex   # anonymous Apex
sf project deploy start       # manual deploy (the agent pipeline uses Salesforce MCP instead)
```

See `CLAUDE.md` for the full command reference and pre-commit hook behavior.
