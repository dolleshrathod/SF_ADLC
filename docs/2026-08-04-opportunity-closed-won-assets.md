# Opportunity Closed Won → Assets + Inventory

**Date:** 2026-08-04
**Branch:** `feature/2026-08-04-opportunity-closed-won-assets`
API version: 67.0 | Namespace: none | Target org alias: `Agentfrceorg`

## Original request

> A Record-Triggered Flow on Opportunity that fires when StageName transitions into 'Closed Won'
> (not on every edit while already Closed Won). On the **asynchronous** path it must:
>
> 1. Retrieve all related OpportunityLineItems (up to ~150 per Opportunity).
> 2. Create one Asset record per OpportunityLineItem.
> 3. Decrement an Inventory record's quantity-on-hand per Product.
> 4. Be fully bulkified — no DML/SOQL inside loops; safe for 150 OLIs and for multiple
>    Opportunities closing in the same transaction.

Decisions confirmed during design:

- Asset = **standard Salesforce `Asset` object** (not a custom object) — one Asset per
  OpportunityLineItem, carrying `Quantity` (not one Asset per unit).
- Inventory is keyed by **Product2 only** — no location/warehouse dimension.
- Decrement **floors at zero** (never negative). If no Inventory record exists for a product,
  **skip silently** and continue — no fault.
- Hybrid approach: declarative Flow for record retrieval/Asset creation, plus one invocable Apex
  action for the Inventory decrement only.
- Asset field mapping: `Name`, `Product2Id`, `Quantity` from the OpportunityLineItem;
  `AccountId` from `Opportunity.AccountId`; a new `Opportunity__c` lookup from the triggering
  Opportunity.

Org facts that shaped the design: standard `Asset.Quantity` (`double`) already exists, so no
custom Quantity field was created; standard `Asset` has no Opportunity lookup, so one custom
field (`Opportunity__c`) was required; `OpportunityLineItem` has no `AccountId`, so Account is
pulled from the parent Opportunity instead.

## Components created

### Admin / declarative

| Type           | Name                                    | Path                                                                                    | Purpose                                                                           |
| -------------- | --------------------------------------- | --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| Field          | `Asset.Opportunity__c`                  | `force-app/main/default/objects/Asset/fields/Opportunity__c.field-meta.xml`             | Lookup back to the closed Opportunity that created the Asset                      |
| Custom object  | `Inventory__c`                          | `force-app/main/default/objects/Inventory__c/Inventory__c.object-meta.xml`              | Tracks quantity-on-hand per Product2                                              |
| Field          | `Inventory__c.Product__c`               | `force-app/main/default/objects/Inventory__c/fields/Product__c.field-meta.xml`          | Required lookup to Product2, keys the inventory record                            |
| Field          | `Inventory__c.Quantity_On_Hand__c`      | `force-app/main/default/objects/Inventory__c/fields/Quantity_On_Hand__c.field-meta.xml` | Number(18,2), decremented by the Apex action                                      |
| Permission set | `AssetAccess`                           | `force-app/main/default/permissionsets/AssetAccess.permissionset-meta.xml`              | FLS (read/edit) on `Asset.Opportunity__c`                                         |
| Permission set | `InventoryAccess`                       | `force-app/main/default/permissionsets/InventoryAccess.permissionset-meta.xml`          | Object CRUD + FLS on `Inventory__c` fields                                        |
| Flow           | `Opportunity_Closed_Won_Creates_Assets` | `force-app/main/default/flows/Opportunity_Closed_Won_Creates_Assets.flow-meta.xml`      | Orchestrates Asset creation and inventory decrement on Closed Won transition      |
| Manifest       | —                                       | `manifest/package.xml`                                                                  | `CustomField` wildcard type added so the standard-Asset field addition is covered |

### Programmatic

| Type       | Name                           | Path                                                                              | Purpose                                                              |
| ---------- | ------------------------------ | --------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| Apex class | `InventoryDecrementAction`     | `force-app/main/default/classes/InventoryDecrementAction.cls` (+ `-meta.xml`)     | Invocable action, bulk-decrements `Inventory__c.Quantity_On_Hand__c` |
| Apex test  | `InventoryDecrementActionTest` | `force-app/main/default/classes/InventoryDecrementActionTest.cls` (+ `-meta.xml`) | 9 test methods covering the decrement logic, see Test coverage below |

### `Asset.Opportunity__c`

Lookup to Opportunity, label "Opportunity", not required, `deleteConstraint=SetNull`. This is
the only field added to Asset — standard `Asset.Quantity` (already `double`) is reused as-is for
the quantity carried onto each Asset.

### `Inventory__c` object

Label "Inventory", plural "Inventories". Name field is Text, labeled "Inventory Name".
`deploymentStatus=Deployed`, `sharingModel=ReadWrite`, `enableBulkApi`/`enableReports`/
`enableSearch`/`enableSharing`/`enableStreamingApi=true`, `enableHistory=false`.
**`enableActivities=true`** — flagged as a minor, non-blocking code-review warning (see Known
limitations) because nothing in this feature actually creates Tasks/Events against `Inventory__c`;
unlike `Order__c` in the prior feature, this object has no automation that needs `Task.WhatId`,
so the flag was likely copied forward rather than intentionally needed.

| Label            | API name              | Type             | Required | Notes                                        |
| ---------------- | --------------------- | ---------------- | -------- | -------------------------------------------- |
| Product          | `Product__c`          | Lookup(Product2) | Yes      | `deleteConstraint=Restrict`; keys the record |
| Quantity On Hand | `Quantity_On_Hand__c` | Number, 18.2     | No       | Decremented by `InventoryDecrementAction`    |

### Permission sets

- **`AssetAccess`** — read/edit FLS on `Asset.Opportunity__c` only. No object-permission grant
  is needed because `Asset` is a standard object.
- **`InventoryAccess`** — object CRUD on `Inventory__c` (`create`/`read`/`edit`/`delete=true`,
  `viewAllRecords=true`, `modifyAllRecords=false`), plus read/edit FLS on `Product__c` and
  `Quantity_On_Hand__c`.

**Neither permission set is assigned to any user or profile in this branch.** See the rollout
warning under Known limitations — this is the single most important operational note in this
feature.

### Flow `Opportunity_Closed_Won_Creates_Assets`

Record-Triggered Flow on `Opportunity`, `processType=AutoLaunchedFlow`, `status=Active`,
`triggerType=RecordAfterSave`, `recordTriggerType=CreateAndUpdate`.

- **Entry criteria**: `StageName EqualTo "Closed Won"`.
- **`doesRequireRecordChangedToMeetCriteria=true`** — the Flow only fires when a save causes the
  Opportunity to newly meet the entry condition (i.e., the stage transitions into Closed Won on
  this save, or the record is created already in that stage). A subsequent edit to an
  already-Closed-Won Opportunity does not re-fire it, so Assets are not duplicated by repeat
  saves.
- **All logic runs on the asynchronous scheduled path**
  (`<scheduledPaths><pathType>AsyncAfterCommit</pathType>`), named `Run_Asynchronously` — nothing
  runs on the immediate/synchronous save path. This decouples the OLI query, Asset creation, and
  inventory decrement from the Opportunity save transaction itself.

Async path, in order:

1. **`Get_Line_Items`** — Get Records on `OpportunityLineItem` where `OpportunityId = {!$Record.Id}`,
   all records / all fields (`storeOutputAutomatically=true`, `getFirstRecordOnly=false`).
2. **`Has_Line_Items`** (Decision) — proceeds only when `Get_Line_Items` `IsBlank = false`;
   otherwise the interview ends with no further action (`defaultConnectorLabel="No Line Items"`).
3. **`Loop_Line_Items`** — loops over `Get_Line_Items` in ascending order.
4. **`Set_Asset_Fields`** (inside loop, Assignment) — builds `vAssetRecord`:
   `Name = Loop_Line_Items.Name`, `Product2Id = Loop_Line_Items.Product2Id`,
   `Quantity = Loop_Line_Items.Quantity`, `AccountId = $Record.AccountId`,
   `Opportunity__c = $Record.Id`. `Id` is never assigned.
5. **`Add_Asset_To_Collection`** (inside loop, Assignment) — adds `vAssetRecord` to the
   `vAssetsToCreate` collection, then loops back to `Loop_Line_Items`.
6. **`Create_Assets`** (recordCreates, **after** the loop exits via
   `noMoreValuesConnector`) — a single bulk Create Records from `vAssetsToCreate`. No
   Create/Update/Get Records element sits inside the loop — the only DML is this one bulk create.
   Has a `faultConnector` → `Log_Fault`.
7. **`Decrement_Inventory`** (actionCalls, `actionType=apex`) — calls the invocable
   `InventoryDecrementAction`, passing `Get_Line_Items` directly into the `lineItems` input
   parameter (the full OLI collection, not a per-iteration record). Has a `faultConnector` →
   `Log_Fault`.
8. **`Log_Fault`** (Assignment) — assigns `{!$Flow.FaultMessage}` into the `vFaultMessage`
   text variable. This is the terminal node for both fault connectors; `vFaultMessage` is not
   surfaced anywhere beyond this local assignment (matches the accepted pattern from the prior
   `Order_Amount_Creates_Task` feature).

Variables: `vAssetsToCreate` (SObject collection, Asset), `vAssetRecord` (SObject, Asset),
`vFaultMessage` (Text).

### Apex `InventoryDecrementAction`

`public with sharing class InventoryDecrementAction` — invocable action, API 67.0, called only
from the Flow's `Decrement_Inventory` step.

- Inner `Request` class: `@InvocableVariable(required=true) public List<OpportunityLineItem> lineItems;`
- `@InvocableMethod(label='Decrement Inventory for Line Items') public static void decrement(List<Request> requests)`

Logic (`decrement` → `aggregateQuantitySold` → `applyDecrements` → `queryInventoryByProductId`):

1. **Aggregate**: iterates every `Request` and every `OpportunityLineItem` across **all**
   requests (Flow batches asynchronous interviews, so one invocation can carry many Opportunities'
   worth of line items) into a single `Map<Id, Decimal>` keyed by `Product2Id`, summing
   `Quantity`. Null requests, null `lineItems`, null line items, and line items missing
   `Product2Id`/`Quantity` are skipped without error.
2. **One SOQL**: `SELECT Id, Product__c, Quantity_On_Hand__c FROM Inventory__c WHERE Product__c IN :productIds WITH USER_MODE ORDER BY Id ASC`. The `ORDER BY Id ASC` plus "first record wins" logic in `queryInventoryByProductId` is what makes duplicate-Inventory-per-product handling deterministic — only the lowest-Id record per product is kept in the map, later duplicates are dropped before any update is built.
3. For each product with matching inventory: `newOnHand = Math.max(0, currentOnHand - quantitySold)`, treating a null `Quantity_On_Hand__c` as 0, rounded to `scale(2, HALF_UP)`. If the computed value equals the current value (e.g. already at zero and selling more), the record is **not** added to the update list — this is why the "already zero" test asserts zero DML statements.
4. Products with no matching `Inventory__c` record are skipped silently (no exception, no fault).
5. **One DML**: `Database.update(inventoryToUpdate, true, AccessLevel.USER_MODE)` over the deduped, changed-only list. If empty, no DML runs at all.
6. Both the query and the update are wrapped in try/catch, rethrowing as `InventoryDecrementException` (a custom `Exception` subclass) on `QueryException`/`DmlException` — including on WITH USER_MODE / AccessLevel.USER_MODE access-denial failures. This exception is what routes into the Flow's `faultConnector` on `Decrement_Inventory`.

## Data flow

1. A user (or integration) updates an Opportunity's `StageName` to "Closed Won" (or creates one
   already in that stage). The Opportunity save commits normally and synchronously — nothing in
   this feature runs on the save's critical path.
2. After the transaction commits, `Opportunity_Closed_Won_Creates_Assets` fires on its async
   scheduled path (only if this save is what caused the record to newly meet the Closed Won
   filter — re-saving an already-Closed-Won Opportunity does not re-trigger it).
3. `Get_Line_Items` fetches every `OpportunityLineItem` on that Opportunity (up to ~150 typical).
   `Has_Line_Items` short-circuits the interview if there are none.
4. `Loop_Line_Items` builds one in-memory Asset per OLI (`Set_Asset_Fields` +
   `Add_Asset_To_Collection`) — Name/Product2Id/Quantity from the line item, AccountId from the
   Opportunity, and the new `Opportunity__c` lookup back to the Opportunity. No DML happens
   inside this loop.
5. After the loop, `Create_Assets` performs one bulk `Create Records` DML for every Asset built
   in the loop. If this fails (for example, an Opportunity with no `AccountId` causing an Asset
   validation failure), the fault routes to `Log_Fault` and Asset creation for that Opportunity
   simply does not happen — the interview does not crash, but no Assets are created for it.
6. `Decrement_Inventory` then calls `InventoryDecrementAction.decrement()`, passing the full
   `Get_Line_Items` collection (not the created Assets) as the `lineItems` input.
7. The Apex action aggregates quantity sold per `Product2Id` (across this and any other
   interviews batched into the same invocation), queries all matching `Inventory__c` records in
   one SOQL, computes new floored-at-zero on-hand values, and issues one bulk `update`.
8. If the Apex action throws (most likely: a `WITH USER_MODE` access denial for the running
   user — see Known limitations — or a validation failure on `Inventory__c`), the fault routes to
   the same `Log_Fault` step, which stores `$Flow.FaultMessage` in `vFaultMessage`. This does
   **not** affect step 5 — Asset creation already committed by the time this step runs, so Assets
   exist even when inventory decrement fails for a given user.
9. `vFaultMessage` is not surfaced anywhere beyond the local Flow variable (no email alert,
   Custom Notification, or error-log object) — see Known limitations.

## Test coverage

| Class                                          | Coverage                                                                                                                                                |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `InventoryDecrementAction`                     | Exercised by all 9 methods in `InventoryDecrementActionTest` (below); no numeric org coverage % available until deployed and run against `Agentfrceorg` |
| `Opportunity_Closed_Won_Creates_Assets` (Flow) | Not applicable — declarative Flow, no Apex test class covers Flow logic directly; validated by code review only                                         |

`InventoryDecrementActionTest` (`force-app/main/default/classes/InventoryDecrementActionTest.cls`)
— 9 `@isTest` methods:

1. `testDecrementReducesQuantityOnHand` — normal decrement (100 on hand, sell 30 → 70).
2. `testDecrementFloorsAtZeroWhenSoldExceedsOnHand` — sells more than on-hand, asserts floor at 0.
3. `testAggregatesMultipleLineItemsAcrossRequests` — two line items in one request plus one line
   item in a second request for the same product, asserts they sum correctly (100 − 30 = 70) in a
   single call.
4. `testProductWithNoInventoryRecordIsSkippedSilently` — a product with no `Inventory__c` record
   mixed with one that has inventory; asserts no exception, no record ever created, and the other
   product still decrements correctly.
5. `testDuplicateInventoryRecordsOnlyLowestIdDecremented` — two `Inventory__c` records for the
   same product; asserts only the lowest-Id record is decremented and the other is untouched.
6. `testNoOpWhenInventoryAlreadyAtZero` — asserts **zero DML statements** run (via `Limits.getDmlStatements()`) when the computed value equals the current value.
7. `testBulkVolumeUsesSingleQueryAndSingleDmlStatement` — 4 requests × 50 line items (200 total)
   across 12 products; asserts exactly 1 SOQL query and 1 DML statement via `Limits.getQueries()`/
   `Limits.getDmlStatements()`, and verifies aggregated on-hand values per product.
8. `testNullAndEmptyInputsAreHandledWithoutError` — null requests list, empty list, a null
   request, a request with null `lineItems`, and line items missing `Product2Id`/`Quantity`; all
   must be handled gracefully with no exception and no change to inventory.
9. `testInsufficientAccessThrowsInventoryDecrementException` — creates a Standard User with no
   `InventoryAccess` permission set assignment, runs as that user via `System.runAs`, and asserts
   the `WITH USER_MODE` query failure is caught and rethrown as
   `InventoryDecrementAction.InventoryDecrementException` with a message starting
   `"Unable to read inventory records"`. This test is a direct, executable proof of the rollout
   risk documented below.

Test data strategy: `OpportunityLineItem` records are built in memory only (never inserted) since
the class under test never queries `OpportunityLineItem` itself. `Product2` and `Inventory__c`
records are inserted for real since the class queries/updates `Inventory__c` directly. `@TestSetup`
assigns the `InventoryAccess` permission set to the running user (wrapped in `System.runAs` to
avoid a Mixed DML Operation error against the Product2/Inventory__c inserts in the same
transaction) so the happy-path tests reflect a properly provisioned user.

## Security model

- `InventoryDecrementAction` is declared `with sharing` and enforces object/field-level security
  explicitly: the SOQL uses `WITH USER_MODE`, the `update` DML uses `AccessLevel.USER_MODE`.
  Neither bypasses the running user's actual permissions — this is the correct pattern, but see
  the rollout warning below on what it implies operationally.
- The Flow's async (scheduled) path runs as **the user who triggered the Opportunity save**, not
  as an "Automated Process" system identity — native Flow elements (`Get_Line_Items`,
  `Create_Assets`) run in Flow's own system-context-by-default mode for object access, but the
  invoked Apex action's `WITH USER_MODE`/`AccessLevel.USER_MODE` checks are **not** bypassed by
  that — they always enforce the real running user's CRUD/FLS against `Inventory__c`.
- `AssetAccess` (FLS on `Asset.Opportunity__c`) and `InventoryAccess` (CRUD + FLS on
  `Inventory__c`) exist as permission sets in this branch but are **not assigned to any user or
  profile**. See Known limitations — this is the critical rollout gap.
- `Inventory__c` sharing model is `ReadWrite` with `enableSharing=true` — no sharing rules beyond
  org defaults are added by this feature.
- `Asset` is a standard object; only its new custom field carries explicit FLS via `AssetAccess`.
  No object-level permission grant was needed for Asset itself.

## Known limitations / future enhancements

- **CRITICAL ROLLOUT STEP — permission set assignment required before production go-live.**
  Neither `InventoryAccess` nor `AssetAccess` is assigned to any user, profile, or permission set
  group in this branch. Because `InventoryDecrementAction` runs the async Flow path as the
  triggering user (not a system identity) and correctly enforces `WITH USER_MODE`/
  `AccessLevel.USER_MODE`, **any user who closes an Opportunity without the `InventoryAccess`
  permission set assigned will silently fail the inventory decrement step** — the exception is
  caught and routed to `Log_Fault`, which only writes to an unpersisted Flow variable (see next
  bullet), so there is no visible error to the user or to a monitoring surface. **Asset creation
  is unaffected and still succeeds for these users** — only the Inventory decrement is impacted.
  Before this feature goes live in production, assign `InventoryAccess` (and `AssetAccess`, for
  visibility of the new Asset lookup field) to whichever profiles/permission-set groups cover
  users who close Opportunities (e.g. Sales reps). This is proven directly by
  `testInsufficientAccessThrowsInventoryDecrementException` in the test class. Code review
  verdict: **APPROVED WITH WARNINGS** — this is the primary warning.
- **Silent fault handling**: as with the prior `Order_Amount_Creates_Task` feature, both
  `Create_Assets` and `Decrement_Inventory` fault connectors only write `$Flow.FaultMessage` into
  the local `vFaultMessage` variable — there is no email alert, Custom Notification, or
  error-log object. Combined with the permission-set gap above, this means the inventory-decrement
  failure mode described there has no durable visibility beyond debug logs.
- **No AccountId on the Opportunity**: if a Closed Won Opportunity has a null `AccountId`, the
  in-loop `Set_Asset_Fields` step still assigns `vAssetRecord.AccountId = $Record.AccountId`
  (null), and the bulk `Create_Assets` step may fail Asset validation for that Opportunity's
  entire batch of Assets. This is caught by the fault path (not a crash), but no Assets are
  created for that Opportunity. Accepted as a known risk during design; not addressed by
  conditional logic in this branch.
- **`Inventory__c.enableActivities=true` is unused**: nothing in this feature creates Tasks or
  Events against `Inventory__c`, so this flag serves no purpose here (unlike `Order__c` in the
  prior feature, where it was required for `Task.WhatId`). Minor, non-blocking code-review
  warning — consider setting it to `false` in a future cleanup pass.
- **No duplicate-Inventory-per-Product guard**: nothing prevents multiple `Inventory__c` records
  from existing for the same `Product__c` (no duplicate rule or validation rule was added, per
  design). `InventoryDecrementAction` handles this deterministically (lowest Id wins) rather than
  preventing it at the data layer.
- **Flow references Apex by name only**: `Decrement_Inventory`'s `actionName` is
  `InventoryDecrementAction` with no explicit version pin — the Flow and Apex class must be
  deployed together (Apex first, or in the same deployment), otherwise the Flow fails to
  validate/deploy.

## File locations

```
force-app/main/default/objects/Asset/fields/Opportunity__c.field-meta.xml
force-app/main/default/objects/Inventory__c/Inventory__c.object-meta.xml
force-app/main/default/objects/Inventory__c/fields/Product__c.field-meta.xml
force-app/main/default/objects/Inventory__c/fields/Quantity_On_Hand__c.field-meta.xml
force-app/main/default/permissionsets/AssetAccess.permissionset-meta.xml
force-app/main/default/permissionsets/InventoryAccess.permissionset-meta.xml
force-app/main/default/flows/Opportunity_Closed_Won_Creates_Assets.flow-meta.xml
force-app/main/default/classes/InventoryDecrementAction.cls
force-app/main/default/classes/InventoryDecrementAction.cls-meta.xml
force-app/main/default/classes/InventoryDecrementActionTest.cls
force-app/main/default/classes/InventoryDecrementActionTest.cls-meta.xml
manifest/package.xml
```

## Review history

- `salesforce-code-review`: reviewed commits `c3dad93` (Asset/Inventory metadata),
  `f386ada` (Apex action), `241470e` (Flow), `b574bc3` (tests) — verdict
  **APPROVED WITH WARNINGS**. Warnings: (1) permission-set assignment for `InventoryAccess`/
  `AssetAccess` must happen before production go-live or inventory decrement silently fails for
  most real users (critical rollout step, not a code defect); (2)
  `Inventory__c.enableActivities=true` is unused by this feature (minor, non-blocking).

## Deployment

Not yet deployed. Per project workflow, deployment only happens via `salesforce-devops` after
this branch's PR is merged to `main`, using the Salesforce MCP (no `sf`/`sfdx` CLI for deploys)
against target org `Agentfrceorg`. Apex and the Flow must deploy together — the Flow will not
validate without `InventoryDecrementAction` already present.

**Reminder for the deploying/rollout step**: assign `InventoryAccess` and `AssetAccess` to the
appropriate profiles/permission-set groups (e.g. Sales) as part of, or immediately after, this
deployment — see Known limitations above.
