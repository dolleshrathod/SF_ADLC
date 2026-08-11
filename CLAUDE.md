# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## You are the orchestrator — never the implementer

Delegate ALL Salesforce implementation work. Never write `.cls`, `.trigger`, `.xml`, `.html`, `.js`
files yourself.

## Workflow

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

| Step | Agent                      | Model  | Role                                                         |
| ---- | --------------------------- | ------ | -------------------------------------------------------------- |
| 1    | `salesforce-design`        | opus   | Analyzes request, creates feature branch                     |
| 2    | `salesforce-admin`         | sonnet | Creates metadata, commits to branch                          |
| 3    | `salesforce-developer`     | opus   | Writes Apex/LWC, commits to branch                           |
| 4    | `salesforce-unit-testing`  | sonnet | Writes tests, commits to branch                              |
| 5    | `salesforce-code-review`   | sonnet | Reviews branch — read only, no commits                       |
| 6    | `salesforce-documentation` | sonnet | Writes docs, commits to branch                               |
| 7    | orchestrator (you)         | —      | Pushes branch, opens + merges PR (see Git push policy below) |
| 8    | `salesforce-devops`        | opus   | Deploys from main AFTER PR is merged                         |

## Branch flow

- `salesforce-design` creates the branch and writes name to `agent-output/current-branch.md`
- Every agent reads `agent-output/current-branch.md` to know which branch to use
- All agents except devops commit to the feature branch — never to main
- `salesforce-devops` only runs after user confirms PR is merged
- `agent-output/` is gitignored, local-only scratch state — never committed. It's regenerated
  from scratch by `salesforce-design` at the start of every task, so a completed task's branch
  pointer can never leak into the next one. If a downstream agent finds `current-branch.md`
  missing, that means design hasn't run yet for this task — it must run first.

## Git push policy

Local `git push` on this machine authenticates as a GitHub identity that does **not** have write
access to this repo (confirmed repeatedly: `403 Permission to srinialuri/SF_ADLC.git denied to
nareshas-ops`). Feature-branch agents (admin, developer, unit-testing, documentation) hit this
every time they try to push themselves, so:

- **Feature-branch agents commit locally only.** None of them run `git push`. If an agent's
  instructions say to push, that's stale — commit and stop there.
- **The orchestrator pushes.** After an agent finishes its commits, the orchestrator (you) pushes
  using the **GitHub MCP server tools** — `mcp__github__create_branch` (only if the branch doesn't
  exist on origin yet), `mcp__github__push_files` to land the commit's file contents, and
  `mcp__github__create_pull_request` / `mcp__github__merge_pull_request` for the PR itself. This is
  the default and preferred path — it works regardless of the local git credential.
- **Fallback only:** if the GitHub MCP server tools are unavailable in a session, fall back to
  local `git push` — but expect the 403 above unless the user has fixed local git credentials
  first (e.g. `gh auth switch` to an account with push access), and tell the user plainly if it
  fails rather than retrying blindly.
- This applies to every branch push/PR step in this workflow, including design's newly created
  branch, each agent's incremental commits, and any post-merge hotfix branches.

## Confirmation gates

- **Gate 1** — After design outputs plan: ask yes / no / changes — branch created after yes
- **Gate 2** — After code review: show verdict, offer fix / skip / cancel
- **Gate 3** — Inside devops: confirm PR merged + show component list, ask A / P / C

## Skip rules

User must explicitly say "skip [agent name]". Default is always full workflow.

## Project conventions

```
API Version: 67.0
Field prefix: (none — no namespace configured)
Package dir: force-app/main/default
Trigger pattern: one trigger per object → handler class
Deployment: Salesforce MCP only (no sf/sfdx CLI for deploys)
Docs location: docs/
Agent output: agent-output/
Branch file: agent-output/current-branch.md
```

## Code review gate logic

```
APPROVED or APPROVED WITH WARNINGS → proceed to documentation
CHANGES REQUIRED → ask user:
  [F] Fix — send back to salesforce-developer, re-commit, re-review
  [S] Skip — proceed with warning
  [C] Cancel
```

Deployment to an org only happens after the PR is reviewed and merged — none of the feature-branch agents deploy.

## Project state

Salesforce DX project (target org alias: `Agentfrceorg`, namespace: none, API version: 67.0).

Features built so far (authoritative record in `docs/`):

- **Order Management** — `Order__c` custom object, `Order_Amount_Creates_Task` Flow, `OrderManagementAccess` permission set, Order Management Lightning App, tab, layout.
- **Opportunity Closed Won → Assets + Inventory** — `Inventory__c` custom object, `Asset.Opportunity__c` lookup field, `Opportunity_Closed_Won_Creates_Assets` Record-Triggered Flow (async scheduled path), `InventoryDecrementAction` invocable Apex class + test, `AssetAccess` / `InventoryAccess` permission sets.
- **Supporting** — `ClaudeAgents__c` custom object, `ClaudeAgentsAccess` permission set, `Admin` profile with explicit CRUD + FLS grants for all features above.

When adding a new metadata type for the first time, follow Salesforce's standard folder/file conventions (`classes/Foo.cls` + `Foo.cls-meta.xml`; `lwc/foo/foo.js` + `.html` + `.js-meta.xml`) and update `manifest/package.xml`.

## MCP servers

Three MCP servers are configured in `.mcp.json`:

- **Salesforce** (`@salesforce/mcp`, `--orgs Agentfrceorg`, `--toolsets all`) — used by the orchestrator to deploy metadata post-merge. Do not use `sf project deploy` in the pipeline.
- **GitHub** (`@modelcontextprotocol/server-github`, uses `GITHUB_PERSONAL_ACCESS_TOKEN` env var) — used by the orchestrator to push branches and manage PRs.
- **Jira / Atlassian** (`mcp-atlassian`, `JIRA_URL=https://nareshas.atlassian.net`, uses `JIRA_USERNAME` / `JIRA_API_TOKEN` env vars) — available for issue tracking and sprint context.

## Org-specific deployment constraints (Agentfrceorg)

These constraints were discovered from real MCP deploy attempts and are invisible to code review:

- **`deleteConstraint=Restrict` (and Cascade) is disallowed on custom lookup fields to the standard `Product2` object** in this org. Always use `deleteConstraint=SetNull` for lookups to `Product2`.
- **A required lookup must use `Cascade` or `Restrict` as its delete constraint.** Combined with the constraint above, a required lookup to `Product2` is impossible — mark such fields `required=false`.
- **`IsBlank` / `IsNull` operators in Flow Decision conditions do not work when the resource is a record collection** (`getFirstRecordOnly=false`). Do not add a Decision to null-check a Get Records collection — connect directly to a Loop; an empty collection naturally exits via `noMoreValuesConnector`.
- **`Decimal.valueOf()` called on an `OpportunityLineItem.Quantity` field causes a compile error** — `OLI.Quantity` is already `Decimal` in Apex (despite SOQL describe reporting it as `double`). Assign directly without conversion.
- **Flow and its referenced invocable Apex class must be deployed in the same `deploy_metadata` call** (or the Apex class must already be present and compiled). Deploying the Flow alone fails if the referenced class does not yet exist in the org.
- **Deploy uses `RunSpecifiedTests`** (not `RunAllTests`) with the relevant test class specified. The deploy rolls back atomically if the test fails. No Dev Hub / scratch org is available on this machine.

## Commands

Package manager: npm.

- `npm run lint` — ESLint over `**/{aura,lwc}/**/*.js`
- `npm run test:unit` — run LWC Jest tests (`sfdx-lwc-jest`)
- `npm run test:unit:watch` — watch mode
- `npm run test:unit:debug` — debug mode
- `npm run test:unit:coverage` — with coverage
- `npm run prettier` — format all supported files (`.cls,.cmp,.component,.css,.html,.js,.json,.md,.page,.trigger,.xml,.yaml,.yml`)
- `npm run prettier:verify` — check formatting without writing

To run a single Jest test file: `npx sfdx-lwc-jest force-app/main/default/lwc/<component>/__tests__/<file>.test.js`

### Salesforce CLI (`sf`)

- `sf org login web` — authorize an org
- `sf org create scratch` — create a scratch org (requires Dev Hub)
- `sf project deploy start` — deploy local metadata to the target org
- `sf project retrieve start` — pull metadata from the org into `force-app`
- `sf apex run test` — run Apex tests
- `sf apex run --file scripts/apex/hello.apex` — execute anonymous Apex from a `.apex` script
- `sf data query --file scripts/soql/account.soql` — run a `.soql` script
- `sf template generate <artifact>` — scaffold new Apex classes/triggers, LWC/Aura components, etc. — prefer this over hand-writing meta.xml files so naming and API versions stay consistent

## Pre-commit hooks

Husky runs `npm run precommit` (`lint-staged`) on commit:

- All formattable files → `prettier --write`
- `**/{aura,lwc}/**/*.js` → `eslint`
- Anything under `**/lwc/**` → `sfdx-lwc-jest --bail --findRelatedTests --passWithNoTests`

Don't bypass these with `--no-verify`; fix lint/format/test failures instead.

## Architecture notes

- Single default package directory: `force-app` (`sfdx-project.json`). Add new packages here if the project grows a multi-package structure.
- `.forceignore` excludes `**/jsconfig.json`, `**/.eslintrc.json`, `**/__tests__/**`, and `node_modules/` from org push/pull/status — generated LWC config and test files are local-only and shouldn't round-trip to the org.
- `manifest/package.xml` currently covers (all `<members>*</members>`, API v67.0): `ApexClass`, `ApexComponent`, `ApexPage`, `ApexTestSuite`, `ApexTrigger`, `AuraDefinitionBundle`, `CustomApplication`, `CustomField`, `CustomObject`, `CustomTab`, `Flow`, `Layout`, `LightningComponentBundle`, `PermissionSet`, `Profile`, `StaticResource`. Add new metadata type entries alphabetically whenever a new type first appears in the repo.
- ESLint (`eslint.config.js`) has separate rule sets for Aura JS (`@salesforce/eslint-plugin-aura`, recommended + locker configs), LWC JS (`@salesforce/eslint-config-lwc`), LWC test files (same config with `@lwc/lwc/no-unexpected-wire-adapter-usages` turned off, Node globals), and Jest mock files under `**/jest-mocks/**`.
- Prettier uses `prettier-plugin-apex` and `@prettier/plugin-xml`, with the `lwc` parser for `**/lwc/**/*.html` and the `html` parser for `.cmp`/`.page`/`.component` files.
- Each subagent has a persistent memory directory at `.claude/agent-memory-local/<agent-name>/` (gitignored). Agents are expected to read their own memory at task start and write durable lessons (org quirks, established patterns) there rather than into `CLAUDE.md`. The orchestrator's own memory lives at `C:\Users\DELL\.claude\projects\...\memory\`.
