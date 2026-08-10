---
description: Delegate a task directly to the salesforce-developer subagent (Apex, LWC, integrations)
argument-hint: [task description]
---

Use the Agent tool with subagent_type="salesforce-developer" to handle the following task:

$ARGUMENTS

Follow this repo's CLAUDE.md workflow exactly as you normally would — do not skip its rules just
because this was invoked via a shortcut command. In particular: the developer agent requires
`agent-output/current-branch.md` to exist (written by salesforce-design) before it will write any
code. If that file is missing, let the subagent report that and stop rather than working around it
or substituting a different agent.
