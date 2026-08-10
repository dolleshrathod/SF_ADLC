---
description: Delegate a task directly to the salesforce-unit-testing subagent (Apex test classes, 90%+ coverage)
argument-hint: [task description, e.g. which Apex class(es) to cover]
---

Use the Agent tool with subagent_type="salesforce-unit-testing" to handle the following task:

$ARGUMENTS

Follow this repo's CLAUDE.md workflow exactly as you normally would — do not skip its rules just
because this was invoked via a shortcut command. In particular: this agent requires
`agent-output/current-branch.md` to exist (written by salesforce-design), and it tests Apex classes
that salesforce-developer already committed to that branch. If the branch pointer is missing, or
there's no Apex to test yet, let the subagent report that and stop rather than working around it.
