# Order Management (SCRUM-1 — Salesforce Order Creation)

Date: 2026-08-01
Branch: `feature/2026-08-01-order-management`
API version: 67.0 | Namespace: none | Target org alias: `Agentfrceorg`
JIRA: SCRUM-1, Story, Medium, reporter Naresh Aluri

## Original request

> Create an Order management App to be able to create and edit orders. When the order amount
> exceeds $1k then create task

Clarified during design:

- Custom `Order__c` object with an editable `Amount__c` currency field — standard `Order`/
  `OrderItem` were rejected because `Order.TotalAmount` is a non-editable roll-up from
  `OrderItem` (requires Products + Price Book), which doesn't fit a directly-entered amount.
- Task creation fires **only when the amount crosses above $1,000**, not on every save of an
  already-high-value order.
- Threshold is strictly `> 1000` — an amount of exactly `1000.00` does not fire.
- Task `OwnerId` = the triggering Order's `OwnerId`.
- Lightning app "Order Management" with Home, Orders, Accounts, Tasks, Reports tabs.
- Declarative only (record-triggered Flow), matching the `Account_Creates_Opportunity` pattern
  from the prior feature — no Apex.

## Components created

| Type            | Name                                                                                                       | Path                                                                                 |
| --------------- | ---------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Custom object   | `Order__c`                                                                                                 | `force-app/main/default/objects/Order__c/Order__c.object-meta.xml`                   |
| Field           | `Account__c`                                                                                               | `force-app/main/default/objects/Order__c/fields/Account__c.field-meta.xml`           |
| Field           | `Amount__c`                                                                                                | `force-app/main/default/objects/Order__c/fields/Amount__c.field-meta.xml`            |
| Field           | `Status__c`                                                                                                | `force-app/main/default/objects/Order__c/fields/Status__c.field-meta.xml`            |
| Field           | `Order_Date__c`                                                                                            | `force-app/main/default/objects/Order__c/fields/Order_Date__c.field-meta.xml`        |
| Page layout     | Order Layout                                                                                               | `force-app/main/default/layouts/Order__c-Order Layout.layout-meta.xml`               |
| Tab             | `Order__c`                                                                                                 | `force-app/main/default/tabs/Order__c.tab-meta.xml`                                  |
| Lightning app   | `Order_Management`                                                                                         | `force-app/main/default/applications/Order_Management.app-meta.xml`                  |
| Permission set  | `OrderManagementAccess`                                                                                    | `force-app/main/default/permissionsets/OrderManagementAccess.permissionset-meta.xml` |
| Profile         | `Admin` (System Administrator)                                                                             | `force-app/main/default/profiles/Admin.profile-meta.xml`                             |
| Flow            | `Order_Amount_Creates_Task`                                                                                | `force-app/main/default/flows/Order_Amount_Creates_Task.flow-meta.xml`               |
| Manifest update | `CustomApplication`, `CustomObject`, `CustomTab`, `Flow`, `Layout`, `PermissionSet`, `Profile` types added | `manifest/package.xml`                                                               |

No Apex, triggers, or LWC — this is fully declarative, matching the `Account_Creates_Opportunity`
feature.

### `Order__c` object

Label "Order", plural "Orders". Name field is **Auto Number**, label "Order Number", format
`ORD-{00000}`. Settings mirror `ClaudeAgents__c` (`deploymentStatus=Deployed`,
`sharingModel=ReadWrite`, `enableBulkApi`/`enableReports`/`enableSearch`/`enableSharing`/
`enableStreamingApi=true`, `enableFeeds`/`enableHistory=false`) with one deliberate difference:
**`enableActivities=true`**. This is required so the Flow can set `Task.WhatId` to the Order —
without it, Task creation against a custom object fails at runtime.

### Fields

| Label      | API name        | Type                            | Required | Notes                                               |
| ---------- | --------------- | ------------------------------- | -------- | --------------------------------------------------- |
| Account    | `Account__c`    | Lookup(Account)                 | Yes      | `deleteConstraint=Restrict`                         |
| Amount     | `Amount__c`     | Currency, precision 16, scale 2 | Yes      | Drives the Flow threshold                           |
| Status     | `Status__c`     | Restricted Picklist             | No       | Draft (default) / Submitted / Activated / Cancelled |
| Order Date | `Order_Date__c` | Date                            | No       | Default value `TODAY()`                             |

### Page layout

`Order__c-Order Layout.layout-meta.xml` (literal space in the filename, per repo convention).
Two-column "Order Information" section: Order Number (readonly), Account (required), Amount
(required) in column one; Owner, Status, Order Date in column two. Includes the standard
`RelatedActivityList` (open activities) and `RelatedHistoryList` (activity history) related
lists so Tasks created by the Flow are visible on the record, showing Subject, Who Name, Due
Date, and Status columns.

### Tab and Lightning app

`Order__c.tab-meta.xml` is a standard `CustomTab` (`customObject=true`). The `Order_Management`
Lightning app (`uiType=Lightning`, `navType=Standard`, `formFactors=Large`) exposes tabs in this
order: Home, Orders (`Order__c`), Accounts, Tasks, Reports.

### `OrderManagementAccess` permission set

Grants on `Order__c`: create/read/edit/delete = true, `viewAllRecords=true`,
`modifyAllRecords=false`. Field-level read+edit on `Account__c`, `Amount__c`, `Status__c`,
`Order_Date__c` (the Auto Number `Name` field is intentionally omitted — it is not
FLS-controllable and a `fieldPermissions` entry for it would fail to deploy). `Order__c` tab set
to Visible, and `Order_Management` app visibility set to `visible=true`, `default=false`.

### `Admin` profile (System Administrator)

Added in commit `bcaa3ff`, at the user's **explicit request outside the original design
spec** — the repo's stated convention is permission-set-only access (see `CLAUDE.md`), and this
is the first Profile metadata file in the repository (previously `force-app/main/default/profiles/`
did not exist). It grants the System Administrator profile the same object/field permissions as
`OrderManagementAccess`, plus `modifyAllRecords=true` (which the permission set deliberately
does not grant) and `applicationVisibilities`/`tabVisibilities` for `Order_Management`/`Order__c`.

It is **deliberately scoped to only the Order__c/Order_Management permissions relevant to this
story** — it is not a full profile export, and contains no other object, field, or app grants
that a real System Administrator profile would normally include. Any future automation that
retrieves and overwrites this file from the org (e.g. `sf project retrieve start` against a
profile-heavy metadata set) would need to preserve this scoping or intentionally broaden it.

### Flow `Order_Amount_Creates_Task`

Record-triggered Flow on `Order__c`, `processType=AutoLaunchedFlow`, `status=Active`,
`triggerType=RecordAfterSave`, `recordTriggerType=CreateAndUpdate`.

- **Entry criteria**: `filterLogic=and`, single filter `Amount__c GreaterThan 1000.0`.
- **`doesRequireRecordChangedToMeetCriteria=true`** — this is what implements "only when the
  amount crosses the threshold." The Flow fires on create when the amount is already above
  $1,000, and on update **only** when the record's Amount__c changes such that the record newly
  meets the filter (i.e., transitions from `<= 1000` to `> 1000`). Editing an unrelated field
  (or re-saving) on an order already above $1,000 does not create a duplicate Task. This is a
  start-element flag, not a decision element — matching the design requirement exactly.
- **Formulas**: `Task_Subject_Formula` (String) = `"Review high-value order " & {!$Record.Name}`;
  `Task_Due_Date_Formula` (Date) = `TODAY() + 3`.
- **`Create_Task` (recordCreates on Task)**: `Subject`=`Task_Subject_Formula`,
  `OwnerId`=`$Record.OwnerId`, `WhatId`=`$Record.Id`, `ActivityDate`=`Task_Due_Date_Formula`,
  `Priority`="High" (literal), `Status`="Not Started" (literal).
- **Fault path (mandatory)**: `Create_Task` has a `faultConnector` to the `Log_Fault` assignment
  element, which assigns `$Flow.FaultMessage` into a local String variable `vFaultMessage`. This
  mirrors `Account_Creates_Opportunity.flow-meta.xml` from the prior feature branch exactly.
  Rationale: the Flow runs after-save in the same transaction as the Order insert/update, so an
  unhandled fault on the Task create would otherwise roll back the Order save itself.

### Manifest

`manifest/package.xml` gained `CustomApplication`, `CustomObject`, `CustomTab`, `Flow`, `Layout`,
`PermissionSet` (commit `6b98f5d`) and `Profile` (commit `bcaa3ff`) types, each with
`<members>*</members>`, kept alphabetical by `<name>`. Note the `Profile` entry's wildcard
`<members>*</members>` will retrieve/deploy **every** profile in the org, not just `Admin` — see
Known limitations.

## Data flow

1. A user (or integration/data load) creates or edits an `Order__c` record and sets `Amount__c`.
2. `Order_Amount_Creates_Task` runs **after save**. On insert, it fires immediately if
   `Amount__c > 1000`. On update, it fires only if the record _newly_ satisfies that condition
   (crossed from `<= 1000` to `> 1000` on this save) — a save that doesn't change whether the
   filter is met (including edits to other fields, or an update that keeps the amount above
   $1,000) does not re-fire.
3. On fire, `Create_Task` creates one Task: Subject "Review high-value order ORD-NNNNN", owned
   by the Order's owner, related to the Order via `WhatId`, due 3 days from creation, Priority
   High, Status Not Started.
4. If the Task create fails, the `Log_Fault` assignment element catches the fault via
   `$Flow.FaultMessage` into `vFaultMessage`, preventing the fault from propagating unhandled and
   rolling back the Order save. `vFaultMessage` is not surfaced or persisted anywhere beyond that
   local assignment — see Known limitations.
5. The Order's page layout surfaces created Tasks in the Activities related lists so users can
   see the follow-up without leaving the Order record.

## Test coverage

Not applicable — fully declarative (Flow + metadata only), so there is no Apex test class or
Jest target. Same outcome as `Account_Creates_Opportunity`. Verification is by code review plus
manual functional testing after deployment. Per `agent-output/design-requirements.md`, the
scenarios to validate in org/scratch-org testing are:

- Create an Order at $1,500 → expect exactly one Task.
- Edit an unrelated field on that order → expect **no** second Task.
- Raise an order from $500 to $1,500 → expect one Task.
- Create an order at exactly $1,000.00 → expect **no** Task.

## Security model

- `Order__c` sharing model is `ReadWrite`, with `enableSharing=true` (org-wide default record
  visibility follows standard sharing rules; not overridden by this feature).
- Standard user access is via the **`OrderManagementAccess` permission set**: CRUD on `Order__c`,
  FLS on all four custom fields, tab visibility, and app visibility. `viewAllRecords=true` but
  `modifyAllRecords=false` — assigned users can see all Orders but only edit ones they have
  edit access to via ownership/sharing rules.
- The **`Admin` profile** additionally grants the same object/field/tab/app access directly to
  System Administrators, plus `modifyAllRecords=true`, so admins can edit any Order regardless of
  ownership or sharing. This was an explicit, out-of-spec addition (see above) — it does not
  replace the permission set, both exist independently.
- The Flow has no `<runInMode>` set, so it defaults to **system context without sharing** — Task
  creation is not gated by the triggering user's create/FLS access on Task, nor by Order/Task
  sharing rules. This mirrors the same (accepted, non-blocking) pattern flagged in code review
  for `Account_Creates_Opportunity`.

## Known limitations / future enhancements

- **Silent fault handling**: as with the prior `Account_Creates_Opportunity` feature, the Flow's
  fault path only writes `$Flow.FaultMessage` into the local `vFaultMessage` variable — there is
  no email alert, Custom Notification, or error-log object. If Task creation starts failing (for
  example, a future validation rule on Task), there is no durable visibility into it beyond debug
  logs. Flagged as a non-blocking warning in code review; consider adding an email alert or
  lightweight error-log object if this becomes a real risk.
- **Manifest `Profile` wildcard**: `manifest/package.xml`'s `Profile` entry uses
  `<members>*</members>` rather than scoping to `Admin` specifically. Since `Admin` is currently
  the only profile file in the repo, this is harmless today, but a future retrieve using this
  manifest will pull in every profile in the target org, not just `Admin`. Consider scoping to
  `<members>Admin</members>` once the intent is confirmed, or explicitly keep the wildcard if
  broader profile management is planned.
- **Blank Who Name column (cosmetic)**: the Order layout's Activities related list includes a
  `TASK.WHO_NAME` column, but flow-created Tasks only set `WhatId` (the Order), not `WhoId` (a
  Contact/Lead), so that column will always render blank for these Tasks. Cosmetic only — no
  functional impact.
- **Scoped, non-standard profile file**: `Admin.profile-meta.xml` only contains the Order__c /
  Order_Management grants relevant to this story, not a full profile export. If this file is ever
  retrieved fresh from an org (which returns the _entire_ profile), any manual re-scoping done
  here will be lost — worth a note for whoever next touches profile metadata in this repo.
- **Unconditional entry beyond the threshold check**: any Order create/update that crosses above
  $1,000 fires the Flow, including bulk data loads and integration-user saves. This was confirmed
  intentional during design (Q4/Q5) but worth revisiting if bulk imports start generating
  unwanted Tasks.

## Review history

- `salesforce-code-review`: both commits (`6b98f5d` Order object/app/flow, `bcaa3ff` Admin
  profile) reviewed together — verdict **APPROVED WITH WARNINGS**, no blockers. The three
  warnings carried forward are documented above under Known limitations (silent fault logging,
  manifest Profile wildcard, blank Who Name column).

## Deployment

Not yet deployed. Per project workflow, deployment only happens via `salesforce-devops` after
this branch's PR is merged to `main`, using the Salesforce MCP (no `sf`/`sfdx` CLI for deploys)
against target org `Agentfrceorg`.

**Note on this branch**: no git remote is configured for this repository, so there is no GitHub
PR to link and the final `git push` step described in the standard workflow does not apply —
this documentation commit exists only locally on `feature/2026-08-01-order-management`. Gate 3
(devops) will need to be a local decision rather than a "confirm PR merged" check.
