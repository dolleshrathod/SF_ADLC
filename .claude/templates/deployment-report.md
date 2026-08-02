# Deployment Report

**Date:** {{date}}
**Source:** main branch (PR #{{pr-number}} merged)
**Target org:** {{alias}} ({{username}}) — {{Dev Org | Production}}

## Scratch org validation

- Scratch org alias: {{alias}}
- Deploy to scratch org: {{pass/fail}}
- Tests run: {{RunAllTestsInOrg}}
- Test result: {{X}}/{{X}} passing
- Code coverage: {{XX}}% (minimum 75% required)
- Scratch org deleted: {{yes/no}}

## Components deployed to target org

| #   | Type     | Name     | Path     |
| --- | -------- | -------- | -------- |
| 1   | {{type}} | {{name}} | {{path}} |

**Total:** {{N}} components

## Deploy order

1. Custom objects → fields → validation rules
2. Apex classes (non-test) → triggers → test classes
3. LWC → flows → permission sets

## Result

{{SUCCESS | FAILED — reason}}

## Post-deployment

- Deployment log updated: `agent-output/deployment-log.md`
- {{Any manual follow-up needed}}
