---
description: Delegate a task directly to the salesforce-code-review subagent (read-only review of Apex/LWC/metadata against best practices)
argument-hint: [optional focus areas, or leave blank to review the whole branch]
---

Use the Agent tool with subagent_type="salesforce-code-review" to review the current feature
branch. Focus areas, if any: $ARGUMENTS

Follow this repo's CLAUDE.md workflow exactly as you normally would — do not skip its rules just
because this was invoked via a shortcut command. In particular: this agent requires
`agent-output/current-branch.md` to exist (written by salesforce-design), is strictly read-only
(no commits), and produces a verdict (APPROVED / APPROVED WITH WARNINGS / CHANGES REQUIRED). Apply
the Gate 2 logic from CLAUDE.md once it reports back — CHANGES REQUIRED means asking the user
fix / skip / cancel, not proceeding automatically.
