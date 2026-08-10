---
description: Delegate a task directly to the salesforce-devops subagent (post-merge deployment validation)
argument-hint: [optional notes, e.g. which org/PR]
---

Use the Agent tool with subagent_type="salesforce-devops" to handle deployment for this feature.
Additional notes, if any: $ARGUMENTS

Follow this repo's CLAUDE.md workflow exactly as you normally would — do not skip its rules just
because this was invoked via a shortcut command. In particular: this agent only runs AFTER the
user has confirmed the PR is merged to main — confirm that first if it isn't already established
in this conversation. It has no Salesforce MCP tools itself; it validates the merged code and hands
you back a dependency-ordered component list. Apply Gate 3 from CLAUDE.md before deploying: show
the component list and get explicit approve / partial / cancel from the user — you make the actual
`mcp__salesforce__deploy_metadata` call, never the subagent.
