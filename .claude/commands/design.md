---
description: Delegate a task directly to the salesforce-design subagent (requirements analysis, admin/dev split, feature branch creation)
argument-hint: [feature request description]
---

Use the Agent tool with subagent_type="salesforce-design" to handle the following request:

$ARGUMENTS

Follow this repo's CLAUDE.md workflow exactly as you normally would — do not skip its rules just
because this was invoked via a shortcut command. In particular: this is the FIRST step in the
pipeline. It creates the feature branch and writes `agent-output/current-branch.md` for every
downstream agent to read. Present its plan at Gate 1 (yes / no / changes) before letting it create
the branch — do not auto-approve.
