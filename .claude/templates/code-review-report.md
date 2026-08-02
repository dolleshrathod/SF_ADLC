# Code Review Report

**Branch:** {{branch-name}}
**Reviewed:** {{date}}
**Verdict:** {{APPROVED | APPROVED WITH WARNINGS | CHANGES REQUIRED}}

## Summary

{{1-2 sentence overall assessment}}

## Critical issues (must fix before deploy)

| #   | File     | Line     | Issue     | Why it's wrong | Suggested fix |
| --- | -------- | -------- | --------- | -------------- | ------------- |
| 1   | {{path}} | {{line}} | {{issue}} | {{reason}}     | {{fix}}       |

_(none — remove table if no critical issues)_

## Warnings (should fix, non-blocking)

| #   | File     | Line     | Issue     | Suggested fix |
| --- | -------- | -------- | --------- | ------------- |
| 1   | {{path}} | {{line}} | {{issue}} | {{fix}}       |

_(none — remove table if no warnings)_

## Good practices observed

- {{specific thing done well, with file reference}}

## Checklist results

| Check                                                    | Result        |
| --------------------------------------------------------- | ------------- |
| SOQL/DML in loops                                        | {{pass/fail}} |
| Bulkification                                            | {{pass/fail}} |
| `with sharing` on service/handler classes                | {{pass/fail}} |
| `WITH USER_MODE` / `USER_MODE` DML                       | {{pass/fail}} |
| Recursion prevention (triggers)                          | {{pass/fail}} |
| Hardcoded IDs                                            | {{pass/fail}} |
| Null checks                                              | {{pass/fail}} |
| Test coverage (no `@SeeAllData`, positive/negative/bulk) | {{pass/fail}} |

## Next step

{{"Proceed to salesforce-documentation" | "Awaiting user decision: Fix / Skip / Cancel"}}
