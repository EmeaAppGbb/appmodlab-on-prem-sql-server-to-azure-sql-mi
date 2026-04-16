# SQL Agent Job Migration Mapping - Lakeview Medical Center

## Overview

This document maps all SQL Agent jobs and alerts from the on-premises SQL Server to Azure SQL Managed Instance. It covers each job's migration status, compatibility changes, and any required post-migration actions.

| Metric | Count |
|--------|-------|
| Total Jobs Migrated | 7 |
| Jobs Enabled on MI | 5 |
| Jobs Disabled on MI | 2 (backup jobs) |
| Alerts Migrated | 10 |
| Alerts Skipped | 2 (disk space — not supported on MI) |

---

## Job Migration Details

### Job 1: LMC - Nightly Billing Batch

| Attribute | Source (On-Premises) | Target (Azure SQL MI) |
|-----------|---------------------|-----------------------|
| **Source File** | `SQLAgent/Jobs/01-NightlyBilling.sql` | `Migration/13-MigrateAgentJobs.sql` |
| **Status** | Enabled | **Enabled** |
| **Schedule** | Daily at 2:00 AM | Daily at 2:00 AM (unchanged) |
| **Steps** | 3 | 3 (unchanged) |
| **Owner** | sa | sa |
| **Databases** | BillingDB, PatientDB | BillingDB, PatientDB |

**Steps:**

| # | Step Name | Database | Retries | Changes for MI |
|---|-----------|----------|---------|----------------|
| 1 | Execute Nightly Billing Batch | BillingDB | 2 | None |
| 2 | Reconcile Encounter Totals | PatientDB | 1 | None — cross-DB queries supported on MI |
| 3 | Process Payment Plan Reminders | BillingDB | 0 | None |

**MI Compatibility Notes:** Fully compatible. Cross-database references between databases hosted on the same MI instance work without changes.

---

### Job 2: LMC - Daily Claims Submission

| Attribute | Source (On-Premises) | Target (Azure SQL MI) |
|-----------|---------------------|-----------------------|
| **Source File** | `SQLAgent/Jobs/02-InsuranceClaims.sql` | `Migration/13-MigrateAgentJobs.sql` |
| **Status** | Enabled | **Enabled** |
| **Schedule** | Daily at 6:00 AM and 6:00 PM | Daily at 6:00 AM and 6:00 PM (unchanged) |
| **Steps** | 3 | 3 (unchanged) |
| **Owner** | sa | sa |
| **Databases** | BillingDB | BillingDB |

**Steps:**

| # | Step Name | Database | Retries | Changes for MI |
|---|-----------|----------|---------|----------------|
| 1 | Submit Pending Claims | BillingDB | 3 | None |
| 2 | Process Claim Responses (835) | BillingDB | 1 | Linked server `OPENQUERY` was already commented out; added TODO for Azure-native integration |
| 3 | Flag Claims for Appeal | BillingDB | 0 | None |

**MI Compatibility Notes:** The linked server reference to `INSURANCE_CLEARINGHOUSE` was already commented out in the source. Consider replacing with Azure Logic Apps or Service Bus integration for clearinghouse communication.

**Post-Migration Action:** Plan Azure-native clearinghouse integration to replace the legacy linked server pattern.

---

### Job 3: LMC - Monthly Data Archival

| Attribute | Source (On-Premises) | Target (Azure SQL MI) |
|-----------|---------------------|-----------------------|
| **Source File** | `SQLAgent/Jobs/03-DataArchival.sql` | `Migration/13-MigrateAgentJobs.sql` |
| **Status** | Enabled | **Enabled** |
| **Schedule** | 1st Sunday of month at 1:00 AM | 1st Sunday of month at 1:00 AM (unchanged) |
| **Steps** | 4 | 4 (unchanged) |
| **Owner** | sa | sa |
| **Databases** | PatientDB, BillingDB | PatientDB, BillingDB |

**Steps:**

| # | Step Name | Database | Retries | Changes for MI |
|---|-----------|----------|---------|----------------|
| 1 | Archive PatientDB Old Records | PatientDB | 1 | None |
| 2 | Archive BillingDB Old Records | BillingDB | 1 | None — cross-DB queries supported on MI |
| 3 | Purge Old Audit Records | PatientDB | 0 | None |
| 4 | Rebuild Fragmented Indexes | PatientDB | 0 | Changed `ONLINE = OFF` → `ONLINE = ON` (supported on Business Critical tier) |

**MI Compatibility Notes:**
- Index rebuild changed to `ONLINE = ON` for minimal disruption (supported on Business Critical tier; if using General Purpose tier, revert to `ONLINE = OFF`).
- Cross-database deletes between PatientDB and BillingDB work on MI.

---

### Job 4: LMC - Daily Statistics Update

| Attribute | Source (On-Premises) | Target (Azure SQL MI) |
|-----------|---------------------|-----------------------|
| **Source File** | `SQLAgent/Jobs/04-StatisticsUpdate.sql` | `Migration/13-MigrateAgentJobs.sql` |
| **Status** | Enabled | **Enabled** |
| **Schedule** | Daily at 3:00 AM | Daily at 3:00 AM (unchanged) |
| **Steps** | 3 | 3 (unchanged) |
| **Owner** | sa | sa |
| **Databases** | PatientDB, BillingDB, SchedulingDB | PatientDB, BillingDB, SchedulingDB |

**Steps:**

| # | Step Name | Database | Retries | Changes for MI |
|---|-----------|----------|---------|----------------|
| 1 | Update PatientDB Statistics | PatientDB | 1 | None |
| 2 | Update BillingDB Statistics | BillingDB | 1 | None |
| 3 | Update SchedulingDB Statistics | SchedulingDB | 0 | None |

**MI Compatibility Notes:** Fully compatible. `UPDATE STATISTICS` and `sp_updatestats` work on MI. Note that MI also has auto-update statistics enabled by default; this job provides more aggressive/controlled statistics updates.

---

### Job 5: LMC - Full Database Backup ⛔ DISABLED

| Attribute | Source (On-Premises) | Target (Azure SQL MI) |
|-----------|---------------------|-----------------------|
| **Source File** | `SQLAgent/Jobs/05-BackupJob.sql` | `Migration/13-MigrateAgentJobs.sql` |
| **Status** | Enabled | **Disabled** |
| **Schedule** | Daily at 11:00 PM | N/A (disabled) |
| **Steps** | 2 | 1 (placeholder notice) |
| **Owner** | sa | sa |
| **Databases** | PatientDB, BillingDB, SchedulingDB, ReportingDB | N/A |

**Reason for Disabling:** Azure SQL MI provides automated backups:
- **Full backups:** Weekly
- **Differential backups:** Every 12 hours
- **Transaction log backups:** Every 5-10 minutes
- **Retention:** Configurable 1-35 days (default 7 days)

**Original Configuration:**
- Backed up to UNC path `\\BACKUP-SERVER\SQLBackups\LakeviewMedical\`
- 30-day retention with cleanup via `xp_delete_files`
- Both `xp_delete_files` and UNC paths are not available on MI

**Post-Migration Actions:**
1. Configure backup retention period: `az sql mi update --name <mi> --resource-group <rg> --backup-storage-redundancy Geo`
2. Set up Long-Term Retention (LTR) for compliance: `az sql midb ltr-policy set`
3. Verify PITR (point-in-time restore) works within the retention window

---

### Job 6: LMC - Transaction Log Backup ⛔ DISABLED

| Attribute | Source (On-Premises) | Target (Azure SQL MI) |
|-----------|---------------------|-----------------------|
| **Source File** | `SQLAgent/Jobs/05-BackupJob.sql` | `Migration/13-MigrateAgentJobs.sql` |
| **Status** | Enabled | **Disabled** |
| **Schedule** | Every 15 minutes, 24/7 | N/A (disabled) |
| **Steps** | 1 | 1 (placeholder notice) |
| **Owner** | sa | sa |
| **Databases** | PatientDB, BillingDB, SchedulingDB | N/A |

**Reason for Disabling:** MI takes automated transaction log backups every 5-10 minutes, which is more frequent than the original 15-minute schedule. Point-in-time restore (PITR) is available within the configured retention window.

---

### Job 7: LMC - Blocking Monitor

| Attribute | Source (On-Premises) | Target (Azure SQL MI) |
|-----------|---------------------|-----------------------|
| **Source File** | `SQLAgent/Alerts/01-DiskSpaceAlert.sql` | `Migration/13-MigrateAgentJobs.sql` |
| **Status** | Enabled | **Enabled** |
| **Schedule** | Every 2 min, 6:00 AM - 10:00 PM | Every 2 min, 6:00 AM - 10:00 PM (unchanged) |
| **Steps** | 1 | 1 (unchanged) |
| **Owner** | sa | sa |
| **Databases** | master (queries DMVs) | master |

**Steps:**

| # | Step Name | Database | Retries | Changes for MI |
|---|-----------|----------|---------|----------------|
| 1 | Check for Blocking | master | 0 | Updated email subject to include "MI" identifier |

**MI Compatibility Notes:** `sys.dm_exec_requests`, `sys.dm_exec_sql_text`, and Database Mail (`sp_send_dbmail`) are all supported on MI.

**Post-Migration Action:** Ensure Database Mail profile "DBA Mail Profile" is configured on MI.

---

## Alert Migration Details

### Migrated Alerts (MI-Compatible)

| Alert Name | Type | Configuration | Notification |
|------------|------|---------------|-------------|
| LMC - Severity 17 Error | Severity | Severity = 17 | DBA Team (Email) |
| LMC - Severity 18 Error | Severity | Severity = 18 | DBA Team (Email) |
| LMC - Severity 19 Error | Severity | Severity = 19 | DBA Team (Email) |
| LMC - Severity 20 Error | Severity | Severity = 20 | DBA Team (Email) |
| LMC - Severity 21 Error | Severity | Severity = 21 | DBA Team (Email) |
| LMC - Severity 22 Error | Severity | Severity = 22 | DBA Team (Email) |
| LMC - Severity 23 Error | Severity | Severity = 23 | DBA Team (Email) |
| LMC - Severity 24 Error | Severity | Severity = 24 | DBA Team (Email) |
| LMC - Severity 25 Error | Severity | Severity = 25 | DBA Team (Email) |
| LMC - Transaction Log Full | Message ID | Error 9002 | DBA Team (Email) |

### Skipped Alerts (Not Supported on MI)

| Alert Name | Reason Skipped | Azure Alternative |
|------------|---------------|-------------------|
| LMC - Disk Space Warning | Performance condition alerts (`LogicalDisk\|% Free Space`) not supported on MI | Azure Monitor metric alert on `storage_space_used_mb` |
| LMC - Disk Space Critical | Performance condition alerts not supported on MI | Azure Monitor metric alert on `storage_space_used_mb` |

**Post-Migration Action:** Create Azure Monitor alerts for storage monitoring:
```bash
az monitor metrics alert create \
  --name "LMC-MI-Storage-Warning" \
  --resource <mi-resource-id> \
  --condition "avg storage_space_used_mb > 80" \
  --action <action-group-id>
```

---

## Operator Configuration

| Operator | Email | On-Prem Pager | MI Pager |
|----------|-------|---------------|----------|
| DBA Team | dba-team@lakeviewmedical.org | dba-oncall@lakeviewmedical.org | Removed (pager not supported on MI; use Azure Monitor action groups) |

---

## Schedule Summary

| Job | Schedule | Frequency | Time |
|-----|----------|-----------|------|
| Nightly Billing Batch | Nightly at 2AM | Daily | 02:00 |
| Daily Claims Submission | Morning Claims Run | Daily | 06:00 |
| Daily Claims Submission | Evening Claims Run | Daily | 18:00 |
| Monthly Data Archival | First Sunday Monthly | Monthly (1st Sunday) | 01:00 |
| Daily Statistics Update | Daily at 3AM | Daily | 03:00 |
| Full Database Backup | *(disabled)* | — | — |
| Transaction Log Backup | *(disabled)* | — | — |
| Blocking Monitor | Every 2 Minutes | Daily subday (2 min) | 06:00–22:00 |

---

## Post-Migration Checklist

- [ ] Run `Migration/13-MigrateAgentJobs.sql` on the target MI instance
- [ ] Run `Migration/14-AgentJobValidation.sql` and verify all checks pass
- [ ] Configure Database Mail profile "DBA Mail Profile" on MI
- [ ] Configure MI backup retention period (recommended: 35 days for compliance)
- [ ] Set up Long-Term Retention (LTR) policies for HIPAA compliance
- [ ] Create Azure Monitor alerts to replace disk space performance alerts
- [ ] Verify cross-database queries work (PatientDB ↔ BillingDB)
- [ ] Test blocking monitor email delivery
- [ ] Monitor first execution of each enabled job
- [ ] Plan Azure-native clearinghouse integration (replace linked server pattern)
- [ ] If using General Purpose tier, change index rebuild `ONLINE = ON` to `ONLINE = OFF` in archival job
