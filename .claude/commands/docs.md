---
description: Delegate a task directly to the salesforce-documentation subagent (writes docs/*.md for the completed feature)
argument-hint: [optional notes for the doc, or leave blank]
---

Use the Agent tool with subagent_type="salesforce-documentation" to write documentation for the
current feature branch. Additional notes, if any: $ARGUMENTS

Follow this repo's CLAUDE.md workflow exactly as you normally would — do not skip its rules just
because this was invoked via a shortcut command. In particular: this agent requires
`agent-output/current-branch.md` to exist (written by salesforce-design), reads
`agent-output/design-requirements.md` and the actual implemented code (never guesses), and commits
its doc as the branch's final commit — it does not push. Pushing the branch and opening the PR via
the GitHub MCP server is your job afterward, per CLAUDE.md's "Git push policy".
