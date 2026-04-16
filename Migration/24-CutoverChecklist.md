# Cutover Checklist — Lakeview Medical Center

## Overview

This checklist covers the complete cutover process for migrating Lakeview Medical Center's databases from on-premises SQL Server 2016 to Azure SQL Managed Instance. The cutover includes four databases: **PatientDB**, **BillingDB**, **SchedulingDB**, and **ReportingDB**.

| Attribute | Value |
|-----------|-------|
| **Migration Type** | Online (minimal downtime) |
| **Source** | SQL Server 2016 (on-premises) |
| **Target** | Azure SQL Managed Instance |
| **Databases** | PatientDB, BillingDB, SchedulingDB, ReportingDB |
| **Estimated Downtime** | 30–60 minutes |
| **Maintenance Window** | Saturday 2:00 AM – 6:00 AM ET |

---

## Pre-Cutover Steps (T-minus 1 week to T-minus 1 hour)

### T-minus 7 days

- [ ] **Confirm maintenance window** with all stakeholders (clinical, billing, scheduling, IT)
- [ ] **Send initial cutover notification** to all teams (see [Communication Template](#communication-template) below)
- [ ] **Verify MI readiness** — all databases are in RESTORING state on the target MI and log shipping is current
- [ ] **Run `12-MigrationMonitoring.sql`** and confirm log backup chain is intact with no breaks
- [ ] **Verify log shipping lag** is consistently under 5 minutes
- [ ] **Confirm DNS TTL** is lowered to 300 seconds (5 minutes) for any DNS records pointing to the SQL Server
- [ ] **Validate rollback plan** — confirm the on-premises server can be brought back online if needed
- [ ] **Test connectivity** from all application servers to the MI endpoint (TCP port 1433)
- [ ] **Verify Azure Key Vault** access policies allow the application identities to read secrets
- [ ] **Confirm backup retention** — verify latest full backup of all 4 databases on source is less than 24 hours old

### T-minus 3 days

- [ ] **Run a dry-run cutover** in a non-production environment (if available)
- [ ] **Verify all migration scripts** are tested: `22-CutoverProcedure.sql`, `23-ConnectionStringUpdate.ps1`
- [ ] **Confirm all Agent Jobs** have been migrated (`14-AgentJobValidation.sql` passes)
- [ ] **Confirm Linked Server** alternatives are in place (`17-LinkedServerValidation.sql` passes)
- [ ] **Confirm CLR and Service Broker** migrations are validated (`21-CLRServiceBrokerValidation.sql` passes)
- [ ] **Validate application health** — run full application test suite against the current on-premises environment
- [ ] **Prepare monitoring dashboards** in Azure Monitor for the MI instance

### T-minus 1 day

- [ ] **Send 24-hour cutover reminder** to all teams
- [ ] **Capture source baseline** — run Part 4 of `22-CutoverProcedure.sql` (row counts, checksums, object counts) against the source and save results
- [ ] **Verify no long-running maintenance jobs** are scheduled during the cutover window
- [ ] **Confirm on-call DBA and application team contacts** are available during the cutover window
- [ ] **Prepare rollback connection strings** — run `23-ConnectionStringUpdate.ps1 -GenerateRollback`

### T-minus 1 hour

- [ ] **Final go/no-go decision** with all stakeholders on the bridge call
- [ ] **Verify log shipping is current** — lag should be under 2 minutes
- [ ] **Confirm no active batch jobs** are running on the source databases
- [ ] **Open monitoring dashboards** for both source and target
- [ ] **Start a shared timer** to track downtime duration
- [ ] **Send "cutover starting" notification** to all teams

---

## During Cutover Steps (Maintenance Window)

### Phase 1: Stop Application Writes (5–10 minutes)

| Step | Action | Script/Command | Owner | Status |
|------|--------|---------------|-------|--------|
| 1.1 | Enable application maintenance mode | Application-specific procedure | App Team | ☐ |
| 1.2 | Disable scheduled jobs on source | `22-CutoverProcedure.sql` — Step 1b | DBA | ☐ |
| 1.3 | Set databases to READ_ONLY on source | `22-CutoverProcedure.sql` — Step 1c | DBA | ☐ |
| 1.4 | Verify no open transactions | `22-CutoverProcedure.sql` — Step 1d | DBA | ☐ |
| 1.5 | Record downtime start timestamp | Manual | DBA | ☐ |

### Phase 2: Final Tail-Log Backup (5–10 minutes)

| Step | Action | Script/Command | Owner | Status |
|------|--------|---------------|-------|--------|
| 2.1 | Take tail-log backups for all 4 databases | `22-CutoverProcedure.sql` — Step 1e | DBA | ☐ |
| 2.2 | Record tail-log file names | Copy from script output | DBA | ☐ |
| 2.3 | Verify tail-log files are in blob storage | Azure Portal or `Get-AzStorageBlob` | DBA | ☐ |

### Phase 3: Restore Final Logs on MI (10–20 minutes)

| Step | Action | Script/Command | Owner | Status |
|------|--------|---------------|-------|--------|
| 3.1 | Switch connection to MI | SSMS / Azure Data Studio | DBA | ☐ |
| 3.2 | Verify databases are in RESTORING state | `22-CutoverProcedure.sql` — Step 2a | DBA | ☐ |
| 3.3 | Restore tail-logs WITH RECOVERY | `22-CutoverProcedure.sql` — Step 2b | DBA | ☐ |
| 3.4 | Verify all 4 databases are ONLINE | `22-CutoverProcedure.sql` — Part 3 | DBA | ☐ |
| 3.5 | Run DBCC CHECKDB on all databases | `22-CutoverProcedure.sql` — Step 4c | DBA | ☐ |

### Phase 4: Data Integrity Verification (5–10 minutes)

| Step | Action | Script/Command | Owner | Status |
|------|--------|---------------|-------|--------|
| 4.1 | Compare row counts (source vs. target) | `22-CutoverProcedure.sql` — Step 4a | DBA | ☐ |
| 4.2 | Compare checksums (source vs. target) | `22-CutoverProcedure.sql` — Step 4b | DBA | ☐ |
| 4.3 | Compare schema object counts | `22-CutoverProcedure.sql` — Step 4d | DBA | ☐ |
| 4.4 | Verify database users and permissions | `22-CutoverProcedure.sql` — Step 4e | DBA | ☐ |

### Phase 5: Connection String Switch (5–10 minutes)

| Step | Action | Script/Command | Owner | Status |
|------|--------|---------------|-------|--------|
| 5.1 | Update connection strings in Key Vault | `23-ConnectionStringUpdate.ps1` | DBA/DevOps | ☐ |
| 5.2 | Update App Service connection strings (if applicable) | `23-ConnectionStringUpdate.ps1 -AppServiceNames ...` | DevOps | ☐ |
| 5.3 | Update any additional config files or services | Manual / app-specific | App Team | ☐ |
| 5.4 | Restart application services | Application-specific procedure | App Team | ☐ |
| 5.5 | Verify application connects to MI | Application health check | App Team | ☐ |

### Phase 6: Go Live (5 minutes)

| Step | Action | Script/Command | Owner | Status |
|------|--------|---------------|-------|--------|
| 6.1 | Disable application maintenance mode | Application-specific procedure | App Team | ☐ |
| 6.2 | Record downtime end timestamp | Manual | DBA | ☐ |
| 6.3 | Calculate total downtime | Manual | DBA | ☐ |
| 6.4 | Perform smoke tests (critical workflows) | Application test plan | App Team | ☐ |
| 6.5 | Send "cutover complete" notification | See [Communication Template](#communication-template) | Project Lead | ☐ |

---

## Post-Cutover Steps (T-plus 1 hour to T-plus 7 days)

### Immediate (T-plus 0 to 2 hours)

- [ ] **Monitor MI performance** — CPU, memory, IOPS, DTU/vCore utilization in Azure Monitor
- [ ] **Monitor application logs** for connection errors or unexpected behavior
- [ ] **Verify SQL Agent jobs** are running on the MI (check first scheduled execution)
- [ ] **Verify Database Mail** is working (send test email from MI)
- [ ] **Verify cross-database queries** work (PatientDB ↔ BillingDB)
- [ ] **Check for blocking and deadlocks** on MI using `sys.dm_exec_requests`

### Day 1 (T-plus 24 hours)

- [ ] **Review overnight job execution** — verify nightly billing batch and other Agent jobs completed
- [ ] **Review query performance** — compare top queries on MI vs. baseline from source
- [ ] **Verify automated backups** are running on MI (check in Azure Portal)
- [ ] **Remove log shipping Agent job** from the source server:
  ```sql
  EXEC msdb.dbo.sp_delete_job
      @job_name = N'Lakeview_MI_Migration_LogShipping',
      @delete_unused_schedule = 1;
  ```
- [ ] **Update DNS records** (if applicable) to point to the MI endpoint

### Day 3

- [ ] **Review application performance metrics** over the past 72 hours
- [ ] **Check for any missing indexes** recommended by the MI query store / DMVs
- [ ] **Verify Long-Term Retention (LTR)** backup policies are configured for compliance
- [ ] **Confirm Azure Monitor alerts** are configured (replacing on-prem disk space alerts)

### Day 7

- [ ] **Conduct post-migration review** with all stakeholders
- [ ] **Document any issues encountered** and their resolutions
- [ ] **Decommission source server** (or move to standby) — only after stakeholder sign-off
- [ ] **Remove blob storage backups** used for migration (retain per retention policy)
- [ ] **Close the migration project** and update internal documentation

---

## Rollback Plan

> **Rollback window:** The rollback plan is viable for up to **4 hours** after cutover. After that, data written to the MI will not be present on the on-premises source.

### Rollback Triggers

Initiate rollback if any of the following occur:

| Trigger | Threshold | Decision Maker |
|---------|-----------|----------------|
| Databases fail to come ONLINE on MI | Any database not ONLINE after 30 min | DBA Lead |
| Data integrity check fails | Row counts or checksums differ | DBA Lead |
| Application cannot connect to MI | Connection failures after 15 min of troubleshooting | App Team Lead |
| Critical application functionality broken | P1 issues not resolvable within 1 hour | Project Lead |
| Performance degradation | Response time > 3x baseline | DBA + App Team |

### Rollback Procedure

| Step | Action | Responsible |
|------|--------|-------------|
| 1 | **Announce rollback decision** on the bridge call | Project Lead |
| 2 | **Enable maintenance mode** on applications | App Team |
| 3 | **Restore source databases from RESTORING state** — run `RESTORE DATABASE [<DB>] WITH RECOVERY` on the on-premises server (if tail-log used NORECOVERY) | DBA |
| 4 | **Set source databases back to READ_WRITE** — `ALTER DATABASE [<DB>] SET READ_WRITE` | DBA |
| 5 | **Re-enable log shipping Agent job** on source (if needed for future attempt) | DBA |
| 6 | **Revert connection strings** — restore from Key Vault rollback secrets or previous config | DevOps |
| 7 | **Restart application services** | App Team |
| 8 | **Disable maintenance mode** | App Team |
| 9 | **Verify applications are working** against on-premises databases | App Team |
| 10 | **Send rollback notification** to all teams | Project Lead |
| 11 | **Schedule post-mortem** to analyze root cause | Project Lead |

### Rollback — Restore Source Databases

```sql
-- Run on the on-premises SQL Server if databases are in RESTORING state
RESTORE DATABASE [PatientDB] WITH RECOVERY;
RESTORE DATABASE [BillingDB] WITH RECOVERY;
RESTORE DATABASE [SchedulingDB] WITH RECOVERY;
RESTORE DATABASE [ReportingDB] WITH RECOVERY;

-- Set databases back to READ_WRITE
ALTER DATABASE [PatientDB] SET READ_WRITE;
ALTER DATABASE [BillingDB] SET READ_WRITE;
ALTER DATABASE [SchedulingDB] SET READ_WRITE;
ALTER DATABASE [ReportingDB] SET READ_WRITE;
```

### Rollback — Revert Connection Strings

```powershell
# Retrieve rollback connection strings from Key Vault
$databases = @("PatientDB", "BillingDB", "SchedulingDB", "ReportingDB")

foreach ($db in $databases) {
    $rollbackSecret = Get-AzKeyVaultSecret `
        -VaultName "<KEY-VAULT-NAME>" `
        -Name "ConnectionString-$db-OnPrem-Rollback" `
        -AsPlainText

    Write-Host "Rollback connection string for ${db}: $rollbackSecret"
    # Apply to your application configuration as needed
}
```

---

## Communication Template

### Pre-Cutover Notification (T-minus 7 days)

> **Subject:** [PLANNED] Lakeview Medical Center — Database Migration Cutover Scheduled
>
> **To:** All Teams (Clinical, Billing, Scheduling, IT, Management)
>
> Team,
>
> We have scheduled the final database migration cutover from our on-premises SQL Server to Azure SQL Managed Instance.
>
> **Cutover Window:** Saturday, [DATE], 2:00 AM – 6:00 AM ET
> **Expected Downtime:** 30–60 minutes
> **Affected Systems:** All applications using PatientDB, BillingDB, SchedulingDB, and ReportingDB
>
> During the maintenance window, affected applications will be placed in maintenance mode. Users will see a maintenance notification. No data entry or queries will be possible during this period.
>
> **What you need to do:**
> - Complete any pending work before Friday at 5:00 PM ET
> - Do not schedule critical batch jobs during the maintenance window
> - Report any issues after the cutover to: [DBA-TEAM-EMAIL]
>
> A detailed timeline will follow. If you have concerns, please reply to this email.
>
> Thank you,
> [PROJECT LEAD NAME]

### Cutover Starting Notification (T-minus 0)

> **Subject:** [IN PROGRESS] Lakeview Medical Center — Database Migration Cutover STARTING NOW
>
> **To:** All Teams
>
> Team,
>
> The database migration cutover is starting now.
>
> **Start Time:** [TIMESTAMP]
> **Expected Duration:** 30–60 minutes
>
> Applications are being placed in maintenance mode. Please do not attempt to access affected systems.
>
> We will notify you when the cutover is complete and systems are available.
>
> [PROJECT LEAD NAME]

### Cutover Complete Notification

> **Subject:** [COMPLETE] Lakeview Medical Center — Database Migration Cutover Successful
>
> **To:** All Teams
>
> Team,
>
> The database migration cutover has been completed successfully.
>
> **Completion Time:** [TIMESTAMP]
> **Total Downtime:** [DURATION]
> **Status:** All systems operational
>
> All databases (PatientDB, BillingDB, SchedulingDB, ReportingDB) are now running on Azure SQL Managed Instance. Applications have been restored to normal operation.
>
> **Please verify:**
> - You can log in and access your applications normally
> - Key workflows function as expected
>
> **Report issues to:** [DBA-TEAM-EMAIL] or call [ON-CALL-NUMBER]
>
> Thank you for your patience during the migration.
>
> [PROJECT LEAD NAME]

### Rollback Notification (if needed)

> **Subject:** [ROLLBACK] Lakeview Medical Center — Database Migration Cutover Rolled Back
>
> **To:** All Teams
>
> Team,
>
> The database migration cutover has been rolled back to the on-premises environment.
>
> **Rollback Time:** [TIMESTAMP]
> **Reason:** [BRIEF DESCRIPTION]
> **Status:** All systems restored to pre-migration state
>
> Applications are back online using the original on-premises databases. A new cutover date will be communicated after a post-mortem review.
>
> **Report issues to:** [DBA-TEAM-EMAIL]
>
> [PROJECT LEAD NAME]

---

## Key Contacts

| Role | Name | Contact |
|------|------|---------|
| Project Lead | [NAME] | [EMAIL / PHONE] |
| DBA Lead | [NAME] | [EMAIL / PHONE] |
| Application Team Lead | [NAME] | [EMAIL / PHONE] |
| DevOps Lead | [NAME] | [EMAIL / PHONE] |
| Azure Support (if Rapid Response engaged) | Microsoft | [CASE NUMBER] |

---

## Appendix: Script Reference

| Script | Purpose | Run On |
|--------|---------|--------|
| `22-CutoverProcedure.sql` Part 1 | Stop writes, take tail-log backups | Source (on-premises) |
| `22-CutoverProcedure.sql` Part 2 | Restore tail-logs WITH RECOVERY | Target (SQL MI) |
| `22-CutoverProcedure.sql` Part 3 | Verify databases ONLINE | Target (SQL MI) |
| `22-CutoverProcedure.sql` Part 4 | Data integrity checks | Target (SQL MI) |
| `23-ConnectionStringUpdate.ps1` | Update connection strings + Key Vault | Admin workstation |
| `12-MigrationMonitoring.sql` | Monitor log shipping status | Source (on-premises) |
| `14-AgentJobValidation.sql` | Validate Agent jobs on MI | Target (SQL MI) |
