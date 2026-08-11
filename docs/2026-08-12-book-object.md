# Book__c Custom Object

**Date:** 2026-08-12
**Branch:** feature/2026-08-12-book-object
**Requested by:** Jira SCRUM-1

## Original request

> Create a custom Salesforce object named Book with the following fields:
> - Book Name (Text)
> - Issued Date (Date)
> - Return Date (Date)

## Components created

### Admin / declarative

| Type | Name | Path | Purpose |
| ---- | ---- | ---- | ------- |
| Custom Object | Book__c | force-app/main/default/objects/Book__c/Book__c.object-meta.xml | Tracks books with name, issued date, and return date; sharing model ReadWrite |
| Custom Field | Book__c.Issued_Date__c | force-app/main/default/objects/Book__c/fields/Issued_Date__c.field-meta.xml | Date field recording when a book was issued; optional |
| Custom Field | Book__c.Return_Date__c | force-app/main/default/objects/Book__c/fields/Return_Date__c.field-meta.xml | Date field recording when a book should be returned; optional |
| Tab | Book__c | force-app/main/default/tabs/Book__c.tab-meta.xml | Navigation tab (motif: Custom36 Package) for Book records |
| Page Layout | Book__c-Book Layout | force-app/main/default/layouts/Book__c-Book Layout.layout-meta.xml | Two-column layout with Name, Issued Date, and Return Date all set to Edit behavior |
| Permission Set | Book_Admin | force-app/main/default/permissionsets/Book_Admin.permissionset-meta.xml | Grants full CRUD on Book__c plus read/edit FLS on both date fields; tab visibility set to Available |

### Programmatic

No Apex classes, triggers, or LWC components were created. This feature is entirely declarative.

## Data flow

This is a standalone declarative object with no automation layer.

1. A user assigned the **Book_Admin** permission set navigates to the Books tab.
2. They create a new Book record, entering a Book Name (required — standard Name field), and optionally an Issued Date and Return Date.
3. The record is saved directly to the `Book__c` object in the database. No triggers, flows, or process automation run on save.
4. All users whose profiles or permission sets grant read access to `Book__c` can view records subject to the **ReadWrite** sharing model, meaning record owners share read/write access with other users who have been explicitly granted sharing (via manual sharing, sharing rules, or role hierarchy), but no user automatically sees all records unless they have View All on the object or View All Data at the profile level.

## Security model

- **Object sharing model:** ReadWrite — record owners and those above them in the role hierarchy can read and edit owned records. No implicit "public read/write" or "private" restriction.
- **Permission set — Book_Admin:** Grants `allowCreate`, `allowRead`, `allowEdit`, `allowDelete` on `Book__c`. `viewAllRecords` and `modifyAllRecords` are explicitly `false`, so assignment does not bypass the sharing model.
- **FLS:** `Issued_Date__c` and `Return_Date__c` are readable and editable for users assigned Book_Admin. The standard Name field (relabeled "Book Name") is governed by object-level access, not a separate FLS entry.
- **Tab visibility:** Book_Admin sets the Books tab to `Available`, meaning assigned users can pin it to their nav bar but it does not appear by default for everyone.
- No Apex is present, so there is no `with sharing` / `without sharing` consideration.

## Test coverage

No Apex code was written for this feature. There are no test classes to report.

| Class | Coverage |
| ----- | -------- |
| N/A — declarative only | — |

## Known limitations / future enhancements

- **No validation rules:** Neither date field is required and there is no rule enforcing that Return Date is on or after Issued Date. A validation rule (`Return_Date__c >= Issued_Date__c`) should be added before the object is used in production to prevent data quality issues.
- **No overdue automation:** There is no flow or scheduled job to flag books that are past their Return Date. A scheduled flow or Apex batch could set a status field when `Return_Date__c < TODAY()`.
- **No Status field:** The current schema cannot distinguish "checked out", "returned", or "overdue" without manual inspection of dates. Adding a picklist Status field and a flow to manage transitions would improve usability.
- **Tab motif:** The tab uses the generic `Custom36: Package` icon. A more descriptive icon can be set in Setup once the object is deployed.
- **Permission set scope:** Book_Admin covers only the custom date fields. If additional custom fields are added to `Book__c` in the future, the permission set must be updated to include FLS for those fields.
- **No record page customization:** A Lightning record page (flexipage) was not created. The object uses the default Lightning page. A custom flexipage with related lists or highlights panel components can be added as a follow-on.

## File locations

```
force-app/main/default/objects/Book__c/Book__c.object-meta.xml
force-app/main/default/objects/Book__c/fields/Issued_Date__c.field-meta.xml
force-app/main/default/objects/Book__c/fields/Return_Date__c.field-meta.xml
force-app/main/default/tabs/Book__c.tab-meta.xml
force-app/main/default/layouts/Book__c-Book Layout.layout-meta.xml
force-app/main/default/permissionsets/Book_Admin.permissionset-meta.xml
docs/2026-08-12-book-object.md
```
