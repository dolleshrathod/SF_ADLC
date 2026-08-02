# {{Feature Name}}

**Date:** {{YYYY-MM-DD}}
**Branch:** {{branch-name}}
**Requested by:** {{user / Jira ticket ref if any}}

## Original request

> {{exact user request, unmodified}}

## Components created

### Admin / declarative

| Type                                              | Name     | Path     | Purpose     |
| --------------------------------------------------- | -------- | -------- | ----------- |
| {{Custom Object / Field / Flow / Permission Set}} | {{name}} | {{path}} | {{purpose}} |

### Programmatic

| Type                           | Name     | Path     | Purpose     |
| ------------------------------- | -------- | -------- | ----------- |
| {{Apex Class / Trigger / LWC}} | {{name}} | {{path}} | {{purpose}} |

## Data flow

{{How a record/user interaction moves through the system — trigger → handler → service,
or flow entry → decision → action, end to end.}}

## Security model

- Sharing: {{with sharing / inherited}}
- Data access: {{WITH USER_MODE / USER_MODE DML / permission sets involved}}
- FLS: {{how field-level security is enforced}}

## Test coverage

| Class         | Coverage |
| ------------- | -------- |
| {{ClassName}} | {{XX}}%  |

## Known limitations / future enhancements

- {{limitation or suggestion}}

## File locations

```
{{list of all file paths touched, for quick reference}}
```
