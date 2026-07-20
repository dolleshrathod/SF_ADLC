# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## You are the orchestrator — never the implementer

Delegate ALL Salesforce implementation work. Never write `.cls`, `.trigger`, `.xml`, `.html`, `.js`
files yourself.

## Workflow

```
Design (creates branch) → Admin (commits metadata) → Developer (commits code)
→ Unit Testing (commits tests) → Code Review → Documentation (commits docs + pushes)
                                                              ↓
                                                    User merges PR on GitHub
                                                              ↓
                                                    DevOps (deploys from main)
```

| Step | Agent                      | Model  | Role                                       |
| ---- | -------------------------- | ------ | ------------------------------------------ |
| 1    | `salesforce-design`        | opus   | Analyzes request, creates feature branch   |
| 2    | `salesforce-admin`         | sonnet | Creates metadata, commits to branch        |
| 3    | `salesforce-developer`     | opus   | Writes Apex/LWC, commits to branch         |
| 4    | `salesforce-unit-testing`  | sonnet | Writes tests, commits to branch            |
| 5    | `salesforce-code-review`   | sonnet | Reviews branch — read only, no commits     |
| 6    | `salesforce-documentation` | sonnet | Writes docs, commits + pushes final branch |
| 7    | `salesforce-devops`        | opus   | Deploys from main AFTER PR is merged       |

## Branch flow

- `salesforce-design` creates the branch and writes name to `agent-output/current-branch.md`
- Every agent reads `agent-output/current-branch.md` to know which branch to use
- All agents except devops commit to the feature branch — never to main
- `salesforce-devops` only runs after user confirms PR is merged

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

This is a Salesforce DX project scaffolded from the standard SFDX template (target org alias: `sfperOrg`, namespace: none, API version: 67.0). The `force-app/main/default/` metadata folders (`classes`, `triggers`, `lwc`, `aura`, `objects`, `applications`, `flexipages`, `layouts`, `permissionsets`, `staticresources`, `tabs`, `contentassets`) are currently all empty — no custom Apex, LWC/Aura components, or objects have been built yet. When adding the first metadata of a given type, follow Salesforce's standard folder/file conventions for that type (e.g. `classes/Foo.cls` + `Foo.cls-meta.xml`; `lwc/foo/foo.js` + `.html` + `.js-meta.xml`).

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
- `manifest/package.xml` is a retrieve/deploy manifest currently scoped to `ApexClass`, `ApexComponent`, `ApexPage`, `ApexTestSuite`, `ApexTrigger`, `AuraDefinitionBundle`, `LightningComponentBundle`, and `StaticResource` (all members, API v67.0). Update it when retrieving other metadata types (objects, permission sets, flexipages, etc.) that aren't yet listed.
- ESLint (`eslint.config.js`) has separate rule sets for Aura JS (`@salesforce/eslint-plugin-aura`, recommended + locker configs), LWC JS (`@salesforce/eslint-config-lwc`), LWC test files (same config with `@lwc/lwc/no-unexpected-wire-adapter-usages` turned off, Node globals), and Jest mock files under `**/jest-mocks/**`.
- Prettier uses `prettier-plugin-apex` and `@prettier/plugin-xml`, with the `lwc` parser for `**/lwc/**/*.html` and the `html` parser for `.cmp`/`.page`/`.component` files.
