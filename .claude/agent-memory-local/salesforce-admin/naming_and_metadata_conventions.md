---
name: naming-and-metadata-conventions
description: Confirmed file/metadata naming conventions for custom objects, permission sets, tabs, apps, layouts in this repo
metadata:
  type: feedback
---

Confirmed conventions used successfully for the Employee__c object build (2026-07-18), consistent
with the pre-existing ClaudeAgents__c object metadata:

- Permission sets are named `<ObjectPluralOrFeatureName>Access.permissionset-meta.xml` (e.g.
  `ClaudeAgentsAccess`, `EmployeeManagementAccess`), PascalCase no underscores in the filename/API
  name, but the `<label>` is a spaced human-readable string.
- Object-level settings mirror `ClaudeAgents__c.object-meta.xml`: explicit
  `enableActivities`/`enableBulkApi`/`enableFeeds`/`enableHistory`/`enableReports`/`enableSearch`/
  `enableSharing`/`enableStreamingApi`, `deploymentStatus>Deployed`, `sharingModel>ReadWrite`.
- Layout files use the standard Salesforce convention with a literal space in the filename:
  `<Object__c>-<Layout Label>.layout-meta.xml` (e.g. `Employee__c-Employee Layout.layout-meta.xml`).
  This is valid and matches the metadata API's own naming; don't rename to remove the space.
- Every custom field gets a corresponding `<fieldPermissions>` block in a dedicated permission set
  (never on the Profile) — this repo's CLAUDE.md explicitly calls for Permission Sets over Profile
  edits and FLS configuration on every new field. See [[fls-permission-set-pattern]].
- `manifest/package.xml` should be kept in sync: add new metadata type entries (e.g.
  `CustomApplication`, `CustomObject`, `CustomTab`, `Layout`, `PermissionSet`) using `<members>*</members>`
  wildcards, alphabetically ordered by `<name>`, whenever a new metadata type first appears in the repo.
  Note: the very first object (ClaudeAgents__c) was added without updating package.xml — treat that as
  a gap to close opportunistically, not a pattern to repeat.
- Lightning Apps are `CustomApplication` metadata (`.app-meta.xml` under `applications/`), same type
  for classic and Lightning; distinguish via `<uiType>Lightning</uiType>` and `<navType>Standard</navType>`.
- No project-specific field/object prefix beyond the standard `__c` suffix — CLAUDE.md doesn't define
  a custom namespace/prefix (namespace is empty per `sfdx-project.json`).
