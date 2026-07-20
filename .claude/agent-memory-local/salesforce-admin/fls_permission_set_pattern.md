---
name: fls-permission-set-pattern
description: How FLS/object permissions are granted in this repo — one dedicated permission set per object, not Profile edits
metadata:
  type: project
---

This repo has no scratch org / Dev Hub connected during admin-agent work — all metadata is
authored and committed to a feature branch without deploying (deploy happens post-PR-merge, see
CLAUDE.md "Critical rule"). Because of this, FLS/object permissions can't be validated against a
live org at commit time; they're hand-authored based on the field list in the design spec.

**Why:** CLAUDE.md's non-negotiable rules require "Field-level security: always configure FLS when
creating custom fields" and "Permission Sets over Profile modifications". There was no pre-existing
example of a multi-field permission set before Employee__c, so the pattern (one permission set per
object, `<objectPermissions>` block + one `<fieldPermissions>` block per custom field, formula
fields marked `editable=false`) was established here — reuse it for future objects.

**How to apply:** For every new custom object with custom fields, create exactly one permission set
named `<Object/FeatureName>Access.permissionset-meta.xml` granting object CRUD + `viewAllRecords`
(not `modifyAllRecords` unless requested) and readable/editable FLS per field (formula/rollup
fields get `editable=false`). Do not touch Profile XML. See [[naming-and-metadata-conventions]].
