---
name: project-declarative-patterns
description: Observed patterns and intentional choices in declarative (admin) metadata for this project — avoids false positives in future reviews
metadata:
  type: project
---

This project uses source-format (SFDX) metadata, not deploy-format. Fields live as
individual `.field-meta.xml` files under `objects/<ObjectName>/fields/`, not inside
the object XML.

The `manifest/package.xml` intentionally omits `CustomField` and `Layout` as top-level
types in some older commits (they are present as of the Book__c feature). Do not flag
their absence if the source-format files are correctly placed.

**Why:** SFDX source format splits object metadata into separate files per component;
the deploy manifest is a convenience artifact, not the source of truth.

**How to apply:** When reviewing declarative metadata, validate each file against
Salesforce metadata API schema, not against what appears in package.xml.

## Known intentional choices (Book__c task, 2026-08-12)
- `enableHistory>false` — deliberately omitted per design (not required by user)
- `sharingModel>ReadWrite` — design specified this as the standard default
- `viewAllRecords>false` on permission set — intentionally set to false (fix applied 2026-08-12); "CRUD" does not imply View All / Modify All
- Tab motif `Custom36: Package` — a valid standard motif; no project standard motif defined
- Name field label `Book Name` fulfills the "Book Name (Text)" requirement via the standard Name field, not a redundant custom field
