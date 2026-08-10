---
description: Delegate a task directly to the salesforce-admin subagent (Custom Objects, Fields, Flows, Permission Sets, Profiles, and other declarative work)
argument-hint: [task description]
---

Use the Agent tool with subagent_type="salesforce-admin" to handle the following task:

$ARGUMENTS

Follow this repo's CLAUDE.md workflow exactly as you normally would — do not skip its rules just
because this was invoked via a shortcut command. In particular: this agent requires
`agent-output/current-branch.md` to exist (written by salesforce-design) before it will create or
modify any metadata. If that file is missing, let the subagent report that and stop rather than
working around it or substituting a different agent.
