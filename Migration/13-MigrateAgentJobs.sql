-- ============================================================================
-- Migration Script 13: Migrate SQL Agent Jobs to Azure SQL Managed Instance
-- Lakeview Medical Center
-- 
-- Recreates all SQL Agent jobs with MI-compatible syntax.
-- Backup jobs are created DISABLED since MI provides automated backups.
-- ============================================================================
USE msdb;
GO

PRINT '========================================';
PRINT 'Starting SQL Agent Job Migration to MI';
PRINT 'Execution Time: ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT '========================================';
GO

-- ============================================================================
-- PREREQUISITE: Create operator for notifications
-- ============================================================================
IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysoperators WHERE name = N'DBA Team')
BEGIN
    EXEC msdb.dbo.sp_add_operator 
        @name = N'DBA Team',
        @enabled = 1,
        @email_address = N'dba-team@lakeviewmedical.org';
    PRINT 'Operator "DBA Team" created.';
END
ELSE
    PRINT 'Operator "DBA Team" already exists.';
GO

-- ============================================================================
-- JOB 1: Nightly Billing Batch
-- Source: SQLAgent/Jobs/01-NightlyBilling.sql
-- Schedule: Daily at 2:00 AM
-- MI Notes: Fully compatible, cross-database references work within MI
-- ============================================================================
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'LMC - Nightly Billing Batch')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'LMC - Nightly Billing Batch', @delete_unused_schedule = 1;
    PRINT 'Existing job "LMC - Nightly Billing Batch" removed.';
END
GO

DECLARE @jobId BINARY(16);

EXEC msdb.dbo.sp_add_job 
    @job_name = N'LMC - Nightly Billing Batch',
    @enabled = 1,
    @notify_level_eventlog = 2,
    @notify_level_email = 2,
    @notify_level_page = 0,
    @delete_level = 0,
    @description = N'Processes nightly billing batch: posts room charges, creates insurance claims for discharged encounters, submits pending claims, and generates patient invoices. [Migrated from on-premises]',
    @category_name = N'[Uncategorized (Local)]',
    @owner_login_name = N'sa',
    @job_id = @jobId OUTPUT;

-- Step 1: Execute nightly billing stored procedure
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Nightly Billing Batch',
    @step_name = N'Execute Nightly Billing Batch',
    @step_id = 1,
    @subsystem = N'TSQL',
    @command = N'EXEC BillingDB.dbo.usp_BatchNightlyBilling;',
    @database_name = N'BillingDB',
    @retry_attempts = 2,
    @retry_interval = 5,
    @on_success_action = 3,
    @on_fail_action = 3;

-- Step 2: Reconcile encounter totals between BillingDB and PatientDB
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Nightly Billing Batch',
    @step_name = N'Reconcile Encounter Totals',
    @step_id = 2,
    @subsystem = N'TSQL',
    @command = N'
        UPDATE e
        SET e.TotalCharges = ISNULL(bc.TotalCharges, 0),
            e.TotalPayments = ISNULL(py.TotalPayments, 0),
            e.PatientBalance = ISNULL(bc.TotalCharges, 0) - ISNULL(py.TotalPayments, 0),
            e.ModifiedDate = GETDATE()
        FROM PatientDB.dbo.Encounters e
        OUTER APPLY (
            SELECT SUM(ChargeAmount - AdjustmentAmount) AS TotalCharges
            FROM BillingDB.dbo.BillingCharges b
            WHERE b.EncounterID = e.EncounterID AND b.ChargeStatus <> ''VOIDED''
        ) bc
        OUTER APPLY (
            SELECT SUM(PaymentAmount) AS TotalPayments
            FROM BillingDB.dbo.Payments p
            WHERE p.EncounterID = e.EncounterID AND p.PaymentStatus <> ''VOIDED''
        ) py
        WHERE e.EncounterStatus IN (''ACTIVE'', ''DISCHARGED'')
          AND e.AdmitDate >= DATEADD(YEAR, -1, GETDATE());
        
        PRINT ''Encounter totals reconciled: '' + CAST(@@ROWCOUNT AS VARCHAR) + '' encounters updated.'';
    ',
    @database_name = N'PatientDB',
    @retry_attempts = 1,
    @retry_interval = 5,
    @on_success_action = 3,
    @on_fail_action = 3;

-- Step 3: Process payment plan reminders and collections
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Nightly Billing Batch',
    @step_name = N'Process Payment Plan Reminders',
    @step_id = 3,
    @subsystem = N'TSQL',
    @command = N'
        -- Flag overdue payment plans
        UPDATE BillingDB.dbo.PaymentPlans
        SET PlanStatus = ''DEFAULTED'',
            DefaultedDate = GETDATE(),
            ModifiedDate = GETDATE()
        WHERE PlanStatus = ''ACTIVE''
          AND NextPaymentDate < DATEADD(DAY, -60, GETDATE());
        
        PRINT ''Defaulted payment plans: '' + CAST(@@ROWCOUNT AS VARCHAR);
        
        -- Send overdue invoices to collections (over 120 days, balance > $50)
        UPDATE BillingDB.dbo.Invoices
        SET InvoiceStatus = ''COLLECTIONS'',
            SentToCollections = 1,
            CollectionDate = GETDATE(),
            ModifiedDate = GETDATE()
        WHERE InvoiceStatus = ''OPEN''
          AND DATEDIFF(DAY, DueDate, GETDATE()) > 120
          AND TotalAmount - PaidAmount > 50.00;
        
        PRINT ''Invoices sent to collections: '' + CAST(@@ROWCOUNT AS VARCHAR);
    ',
    @database_name = N'BillingDB',
    @retry_attempts = 0,
    @retry_interval = 0,
    @on_success_action = 1,
    @on_fail_action = 2;

-- Schedule: Daily at 2:00 AM
EXEC msdb.dbo.sp_add_jobschedule 
    @job_name = N'LMC - Nightly Billing Batch',
    @name = N'Nightly at 2AM',
    @enabled = 1,
    @freq_type = 4,
    @freq_interval = 1,
    @active_start_time = 020000;

PRINT 'Job "LMC - Nightly Billing Batch" created and ENABLED.';
GO

-- ============================================================================
-- JOB 2: Daily Insurance Claims Submission
-- Source: SQLAgent/Jobs/02-InsuranceClaims.sql
-- Schedule: Daily at 6:00 AM and 6:00 PM
-- MI Notes: Removed linked server reference (OPENQUERY commented out in source).
--           Cross-database queries within MI are supported.
-- ============================================================================
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'LMC - Daily Claims Submission')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'LMC - Daily Claims Submission', @delete_unused_schedule = 1;
    PRINT 'Existing job "LMC - Daily Claims Submission" removed.';
END
GO

DECLARE @jobId BINARY(16);

EXEC msdb.dbo.sp_add_job 
    @job_name = N'LMC - Daily Claims Submission',
    @enabled = 1,
    @notify_level_eventlog = 2,
    @notify_level_email = 2,
    @description = N'Submits pending insurance claims to clearinghouse, processes claim responses (835 remittance), and updates claim statuses. [Migrated from on-premises]',
    @category_name = N'[Uncategorized (Local)]',
    @owner_login_name = N'sa',
    @job_id = @jobId OUTPUT;

-- Step 1: Submit pending claims
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Daily Claims Submission',
    @step_name = N'Submit Pending Claims',
    @step_id = 1,
    @subsystem = N'TSQL',
    @command = N'EXEC BillingDB.dbo.usp_SubmitClaimToInsurance @BatchSubmit = 1;',
    @database_name = N'BillingDB',
    @retry_attempts = 3,
    @retry_interval = 10,
    @on_success_action = 3,
    @on_fail_action = 3;

-- Step 2: Process claim responses (auto-adjudication)
-- MI Note: Linked server OPENQUERY removed; using direct adjudication logic
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Daily Claims Submission',
    @step_name = N'Process Claim Responses (835)',
    @step_id = 2,
    @subsystem = N'TSQL',
    @command = N'
        -- Auto-adjudicate claims submitted > 14 days ago
        -- TODO: Replace with Azure-native clearinghouse integration (e.g., Logic Apps, Service Bus)
        UPDATE BillingDB.dbo.InsuranceClaims
        SET ClaimStatus = ''ADJUDICATED'',
            AdjudicatedDate = GETDATE(),
            AllowedAmount = TotalCharges * 0.80,
            ModifiedDate = GETDATE()
        WHERE ClaimStatus = ''SUBMITTED''
          AND DATEDIFF(DAY, SubmittedDate, GETDATE()) > 14;
        
        PRINT ''Claims adjudicated: '' + CAST(@@ROWCOUNT AS VARCHAR);
    ',
    @database_name = N'BillingDB',
    @retry_attempts = 1,
    @retry_interval = 5,
    @on_success_action = 3,
    @on_fail_action = 3;

-- Step 3: Flag denied claims for appeal
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Daily Claims Submission',
    @step_name = N'Flag Claims for Appeal',
    @step_id = 3,
    @subsystem = N'TSQL',
    @command = N'
        -- Flag denied claims approaching appeal deadline
        UPDATE BillingDB.dbo.InsuranceClaims
        SET ClaimStatus = ''APPEALED'',
            AppealedDate = GETDATE(),
            ModifiedDate = GETDATE()
        WHERE ClaimStatus = ''DENIED''
          AND AppealDeadline IS NOT NULL
          AND DATEDIFF(DAY, GETDATE(), AppealDeadline) BETWEEN 1 AND 30
          AND TotalCharges > 500.00;
        
        PRINT ''Claims flagged for appeal: '' + CAST(@@ROWCOUNT AS VARCHAR);
        
        -- Audit denied claims past appeal deadline
        INSERT INTO BillingDB.dbo.BillingAudit (TableName, RecordID, Action, NewValues)
        SELECT ''InsuranceClaims'', ClaimID, ''APPEAL_EXPIRED'',
               ''Claim '' + ClaimNumber + '' denial is past appeal deadline ($'' + CAST(TotalCharges AS VARCHAR) + '')''
        FROM BillingDB.dbo.InsuranceClaims
        WHERE ClaimStatus = ''DENIED''
          AND AppealDeadline < GETDATE();
    ',
    @database_name = N'BillingDB',
    @retry_attempts = 0,
    @on_success_action = 1,
    @on_fail_action = 2;

-- Schedule 1: Morning at 6:00 AM
EXEC msdb.dbo.sp_add_jobschedule 
    @job_name = N'LMC - Daily Claims Submission',
    @name = N'Morning Claims Run',
    @enabled = 1,
    @freq_type = 4,
    @freq_interval = 1,
    @active_start_time = 060000;

-- Schedule 2: Evening at 6:00 PM
EXEC msdb.dbo.sp_add_jobschedule 
    @job_name = N'LMC - Daily Claims Submission',
    @name = N'Evening Claims Run',
    @enabled = 1,
    @freq_type = 4,
    @freq_interval = 1,
    @active_start_time = 180000;

PRINT 'Job "LMC - Daily Claims Submission" created and ENABLED.';
GO

-- ============================================================================
-- JOB 3: Monthly Data Archival
-- Source: SQLAgent/Jobs/03-DataArchival.sql
-- Schedule: First Sunday of each month at 1:00 AM
-- MI Notes: Index rebuild uses ONLINE = ON for Business Critical tier.
--           Cross-database queries within MI are supported.
-- ============================================================================
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'LMC - Monthly Data Archival')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'LMC - Monthly Data Archival', @delete_unused_schedule = 1;
    PRINT 'Existing job "LMC - Monthly Data Archival" removed.';
END
GO

DECLARE @jobId BINARY(16);

EXEC msdb.dbo.sp_add_job 
    @job_name = N'LMC - Monthly Data Archival',
    @enabled = 1,
    @notify_level_eventlog = 2,
    @notify_level_email = 2,
    @description = N'Archives old clinical and billing records beyond the retention period (7 years). Moves data to archive tables and purges from primary tables. [Migrated from on-premises]',
    @category_name = N'[Uncategorized (Local)]',
    @owner_login_name = N'sa',
    @job_id = @jobId OUTPUT;

-- Step 1: Archive PatientDB records
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Monthly Data Archival',
    @step_name = N'Archive PatientDB Old Records',
    @step_id = 1,
    @subsystem = N'TSQL',
    @command = N'
        EXEC PatientDB.dbo.usp_ArchiveOldRecords 
            @RetentionMonths = 84,
            @BatchSize = 5000,
            @DryRun = 0;
    ',
    @database_name = N'PatientDB',
    @retry_attempts = 1,
    @retry_interval = 10,
    @on_success_action = 3,
    @on_fail_action = 3;

-- Step 2: Archive BillingDB records
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Monthly Data Archival',
    @step_name = N'Archive BillingDB Old Records',
    @step_id = 2,
    @subsystem = N'TSQL',
    @command = N'
        DECLARE @CutoffDate DATE = DATEADD(MONTH, -84, GETDATE());
        DECLARE @ArchivedCount INT = 0;
        
        -- Archive paid/closed invoices
        DELETE FROM BillingDB.dbo.Invoices
        WHERE InvoiceStatus IN (''PAID'', ''WRITTEN_OFF'', ''VOIDED'')
          AND InvoiceDate < @CutoffDate;
        SET @ArchivedCount = @ArchivedCount + @@ROWCOUNT;
        
        -- Archive old billing charges for archived encounters
        DELETE bc FROM BillingDB.dbo.BillingCharges bc
        WHERE NOT EXISTS (
            SELECT 1 FROM PatientDB.dbo.Encounters e 
            WHERE e.EncounterID = bc.EncounterID 
              AND e.EncounterStatus <> ''ARCHIVED''
        )
        AND bc.ServiceDate < @CutoffDate;
        SET @ArchivedCount = @ArchivedCount + @@ROWCOUNT;
        
        -- Purge old audit records (keep 3 years)
        DELETE FROM BillingDB.dbo.BillingAudit
        WHERE ChangedDate < DATEADD(YEAR, -3, GETDATE());
        SET @ArchivedCount = @ArchivedCount + @@ROWCOUNT;
        
        PRINT ''BillingDB records archived: '' + CAST(@ArchivedCount AS VARCHAR);
    ',
    @database_name = N'BillingDB',
    @retry_attempts = 1,
    @retry_interval = 10,
    @on_success_action = 3,
    @on_fail_action = 3;

-- Step 3: Purge old audit records from PatientDB
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Monthly Data Archival',
    @step_name = N'Purge Old Audit Records',
    @step_id = 3,
    @subsystem = N'TSQL',
    @command = N'
        DECLARE @PurgeDate DATE = DATEADD(YEAR, -3, GETDATE());
        
        DELETE FROM PatientDB.dbo.AuditLog
        WHERE ChangedDate < @PurgeDate;
        
        PRINT ''Audit records purged: '' + CAST(@@ROWCOUNT AS VARCHAR);
    ',
    @database_name = N'PatientDB',
    @retry_attempts = 0,
    @on_success_action = 3,
    @on_fail_action = 3;

-- Step 4: Rebuild fragmented indexes after archival
-- MI Note: Changed ONLINE = OFF to ONLINE = ON (supported on Business Critical tier)
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Monthly Data Archival',
    @step_name = N'Rebuild Fragmented Indexes',
    @step_id = 4,
    @subsystem = N'TSQL',
    @command = N'
        DECLARE @SQL NVARCHAR(MAX);
        DECLARE @TableName NVARCHAR(256);
        DECLARE @IndexName NVARCHAR(256);
        DECLARE @Frag FLOAT;
        
        DECLARE idx_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT 
                QUOTENAME(s.name) + ''.'' + QUOTENAME(t.name) AS TableName,
                QUOTENAME(i.name) AS IndexName,
                ips.avg_fragmentation_in_percent
            FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, ''LIMITED'') ips
            INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
            INNER JOIN sys.tables t ON i.object_id = t.object_id
            INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
            WHERE ips.avg_fragmentation_in_percent > 30
              AND ips.page_count > 1000
              AND i.name IS NOT NULL;
        
        OPEN idx_cursor;
        FETCH NEXT FROM idx_cursor INTO @TableName, @IndexName, @Frag;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @SQL = ''ALTER INDEX '' + @IndexName + '' ON '' + @TableName + '' REBUILD WITH (ONLINE = ON)'';
            BEGIN TRY
                EXEC sp_executesql @SQL;
                PRINT ''Rebuilt index '' + @IndexName + '' on '' + @TableName + '' ('' + CAST(@Frag AS VARCHAR) + ''% fragmented)'';
            END TRY
            BEGIN CATCH
                PRINT ''Error rebuilding '' + @IndexName + '': '' + ERROR_MESSAGE();
            END CATCH
            FETCH NEXT FROM idx_cursor INTO @TableName, @IndexName, @Frag;
        END
        
        CLOSE idx_cursor;
        DEALLOCATE idx_cursor;
    ',
    @database_name = N'PatientDB',
    @retry_attempts = 0,
    @on_success_action = 1,
    @on_fail_action = 2;

-- Schedule: First Sunday of each month at 1:00 AM
EXEC msdb.dbo.sp_add_jobschedule 
    @job_name = N'LMC - Monthly Data Archival',
    @name = N'First Sunday Monthly',
    @enabled = 1,
    @freq_type = 32,
    @freq_interval = 1,
    @freq_relative_interval = 1,
    @freq_recurrence_factor = 1,
    @active_start_time = 010000;

PRINT 'Job "LMC - Monthly Data Archival" created and ENABLED.';
GO

-- ============================================================================
-- JOB 4: Daily Statistics Update
-- Source: SQLAgent/Jobs/04-StatisticsUpdate.sql
-- Schedule: Daily at 3:00 AM
-- MI Notes: Fully compatible. sp_updatestats and UPDATE STATISTICS work on MI.
-- ============================================================================
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'LMC - Daily Statistics Update')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'LMC - Daily Statistics Update', @delete_unused_schedule = 1;
    PRINT 'Existing job "LMC - Daily Statistics Update" removed.';
END
GO

DECLARE @jobId BINARY(16);

EXEC msdb.dbo.sp_add_job 
    @job_name = N'LMC - Daily Statistics Update',
    @enabled = 1,
    @notify_level_eventlog = 0,
    @description = N'Updates statistics on all user tables across PatientDB, BillingDB, and SchedulingDB. Uses SAMPLE 30% on weekdays, FULLSCAN on weekends. [Migrated from on-premises]',
    @category_name = N'[Uncategorized (Local)]',
    @owner_login_name = N'sa',
    @job_id = @jobId OUTPUT;

-- Step 1: Update PatientDB statistics
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Daily Statistics Update',
    @step_name = N'Update PatientDB Statistics',
    @step_id = 1,
    @subsystem = N'TSQL',
    @command = N'
        DECLARE @FullScan BIT = CASE WHEN DATEPART(WEEKDAY, GETDATE()) IN (1, 7) THEN 1 ELSE 0 END;
        EXEC PatientDB.dbo.usp_UpdateStatistics @FullScan = @FullScan;
    ',
    @database_name = N'PatientDB',
    @retry_attempts = 1,
    @retry_interval = 5,
    @on_success_action = 3,
    @on_fail_action = 3;

-- Step 2: Update BillingDB statistics
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Daily Statistics Update',
    @step_name = N'Update BillingDB Statistics',
    @step_id = 2,
    @subsystem = N'TSQL',
    @command = N'
        DECLARE @TableName NVARCHAR(256);
        DECLARE @SQL NVARCHAR(500);
        DECLARE @FullScan BIT = CASE WHEN DATEPART(WEEKDAY, GETDATE()) IN (1, 7) THEN 1 ELSE 0 END;
        
        DECLARE stat_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT QUOTENAME(s.name) + ''.'' + QUOTENAME(t.name)
            FROM sys.tables t
            INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
            WHERE t.is_ms_shipped = 0;
        
        OPEN stat_cursor;
        FETCH NEXT FROM stat_cursor INTO @TableName;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY
                IF @FullScan = 1
                    SET @SQL = N''UPDATE STATISTICS '' + @TableName + N'' WITH FULLSCAN'';
                ELSE
                    SET @SQL = N''UPDATE STATISTICS '' + @TableName + N'' WITH SAMPLE 30 PERCENT'';
                EXEC sp_executesql @SQL;
            END TRY
            BEGIN CATCH
                PRINT ''Error on '' + @TableName + '': '' + ERROR_MESSAGE();
            END CATCH
            FETCH NEXT FROM stat_cursor INTO @TableName;
        END
        
        CLOSE stat_cursor;
        DEALLOCATE stat_cursor;
    ',
    @database_name = N'BillingDB',
    @retry_attempts = 1,
    @retry_interval = 5,
    @on_success_action = 3,
    @on_fail_action = 3;

-- Step 3: Update SchedulingDB statistics
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Daily Statistics Update',
    @step_name = N'Update SchedulingDB Statistics',
    @step_id = 3,
    @subsystem = N'TSQL',
    @command = N'
        EXEC sp_updatestats;
        PRINT ''SchedulingDB statistics updated.'';
    ',
    @database_name = N'SchedulingDB',
    @retry_attempts = 0,
    @on_success_action = 1,
    @on_fail_action = 2;

-- Schedule: Daily at 3:00 AM
EXEC msdb.dbo.sp_add_jobschedule 
    @job_name = N'LMC - Daily Statistics Update',
    @name = N'Daily at 3AM',
    @enabled = 1,
    @freq_type = 4,
    @freq_interval = 1,
    @active_start_time = 030000;

PRINT 'Job "LMC - Daily Statistics Update" created and ENABLED.';
GO

-- ============================================================================
-- JOB 5: Full Database Backup (DISABLED - MI has automated backups)
-- Source: SQLAgent/Jobs/05-BackupJob.sql
-- Schedule: Daily at 11:00 PM (original)
-- MI Notes: DISABLED. Azure SQL MI provides automated full, differential,
--           and log backups with configurable retention (1-35 days).
--           UNC paths (\\BACKUP-SERVER) are not accessible from MI.
--           xp_delete_files is not available on MI.
-- ============================================================================
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'LMC - Full Database Backup')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'LMC - Full Database Backup', @delete_unused_schedule = 1;
    PRINT 'Existing job "LMC - Full Database Backup" removed.';
END
GO

DECLARE @jobId BINARY(16);

EXEC msdb.dbo.sp_add_job 
    @job_name = N'LMC - Full Database Backup',
    @enabled = 0,  -- DISABLED: MI provides automated backups
    @notify_level_eventlog = 2,
    @notify_level_email = 2,
    @description = N'DISABLED ON MI - Azure SQL MI provides automated full backups. Original job performed full backup of PatientDB, BillingDB, SchedulingDB, and ReportingDB to network share. Retained for reference only. [Migrated from on-premises - DISABLED]',
    @category_name = N'Database Maintenance',
    @owner_login_name = N'sa',
    @job_id = @jobId OUTPUT;

-- Placeholder step documenting original functionality
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Full Database Backup',
    @step_name = N'MI Automated Backup Notice',
    @step_id = 1,
    @subsystem = N'TSQL',
    @command = N'
        -- This job is DISABLED on Azure SQL Managed Instance.
        -- MI provides automated backups:
        --   Full backups:        Weekly
        --   Differential backups: Every 12 hours
        --   Transaction log:     Every 5-10 minutes
        --   Retention:           Configurable 1-35 days (default 7)
        --
        -- To configure backup retention via Azure CLI:
        --   az sql mi update --name <mi-name> --resource-group <rg> --backup-storage-redundancy Geo
        --
        -- For long-term retention (LTR), configure via Azure Portal or CLI:
        --   az sql midb ltr-policy set --managed-instance <mi-name> --database <db>
        --     --resource-group <rg> --weekly-retention P4W --monthly-retention P12M
        --
        -- Original backup targets: PatientDB, BillingDB, SchedulingDB, ReportingDB
        -- Original backup path: \\BACKUP-SERVER\SQLBackups\LakeviewMedical\
        -- Original retention: 30 days
        
        PRINT ''This job is disabled. Azure SQL MI automated backups are active.'';
        PRINT ''Configure retention via Azure Portal > Managed Instance > Backups.'';
    ',
    @database_name = N'master',
    @retry_attempts = 0,
    @on_success_action = 1,
    @on_fail_action = 2;

PRINT 'Job "LMC - Full Database Backup" created and DISABLED (MI automated backups).';
GO

-- ============================================================================
-- JOB 6: Transaction Log Backup (DISABLED - MI has automated log backups)
-- Source: SQLAgent/Jobs/05-BackupJob.sql
-- Schedule: Every 15 minutes (original)
-- MI Notes: DISABLED. MI takes transaction log backups every 5-10 minutes
--           automatically. No network share access available.
-- ============================================================================
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'LMC - Transaction Log Backup')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'LMC - Transaction Log Backup', @delete_unused_schedule = 1;
    PRINT 'Existing job "LMC - Transaction Log Backup" removed.';
END
GO

DECLARE @jobId BINARY(16);

EXEC msdb.dbo.sp_add_job 
    @job_name = N'LMC - Transaction Log Backup',
    @enabled = 0,  -- DISABLED: MI provides automated log backups every 5-10 min
    @notify_level_eventlog = 2,
    @description = N'DISABLED ON MI - Azure SQL MI takes automated transaction log backups every 5-10 minutes. Original job backed up logs every 15 minutes for PatientDB, BillingDB, SchedulingDB. [Migrated from on-premises - DISABLED]',
    @category_name = N'Database Maintenance',
    @owner_login_name = N'sa',
    @job_id = @jobId OUTPUT;

EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Transaction Log Backup',
    @step_name = N'MI Automated Log Backup Notice',
    @step_id = 1,
    @subsystem = N'TSQL',
    @command = N'
        -- This job is DISABLED on Azure SQL Managed Instance.
        -- MI takes automated transaction log backups every 5-10 minutes.
        -- Point-in-time restore (PITR) is available within the retention window.
        --
        -- Original databases: PatientDB, BillingDB, SchedulingDB
        -- Original frequency: Every 15 minutes
        -- Original backup path: \\BACKUP-SERVER\SQLBackups\LakeviewMedical\
        
        PRINT ''This job is disabled. MI automated log backups are active (every 5-10 min).'';
    ',
    @database_name = N'master',
    @retry_attempts = 0,
    @on_success_action = 1,
    @on_fail_action = 2;

PRINT 'Job "LMC - Transaction Log Backup" created and DISABLED (MI automated log backups).';
GO

-- ============================================================================
-- JOB 7: Blocking Monitor
-- Source: SQLAgent/Alerts/01-DiskSpaceAlert.sql
-- Schedule: Every 2 minutes, 6:00 AM - 10:00 PM
-- MI Notes: Database Mail (sp_send_dbmail) is supported on MI.
--           sys.dm_exec_requests and sys.dm_exec_sql_text work on MI.
-- ============================================================================
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'LMC - Blocking Monitor')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'LMC - Blocking Monitor', @delete_unused_schedule = 1;
    PRINT 'Existing job "LMC - Blocking Monitor" removed.';
END
GO

DECLARE @jobId BINARY(16);

EXEC msdb.dbo.sp_add_job 
    @job_name = N'LMC - Blocking Monitor',
    @enabled = 1,
    @notify_level_eventlog = 0,
    @description = N'Checks for blocking chains longer than 30 seconds and logs/alerts. [Migrated from on-premises]',
    @category_name = N'[Uncategorized (Local)]',
    @owner_login_name = N'sa',
    @job_id = @jobId OUTPUT;

EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Blocking Monitor',
    @step_name = N'Check for Blocking',
    @step_id = 1,
    @subsystem = N'TSQL',
    @command = N'
        IF EXISTS (
            SELECT 1 FROM sys.dm_exec_requests r
            WHERE r.blocking_session_id <> 0
              AND r.wait_time > 30000
        )
        BEGIN
            INSERT INTO PatientDB.dbo.AuditLog (TableName, RecordID, Action, NewValues, ChangedBy)
            SELECT ''BLOCKING'', r.session_id, ''BLOCKING_DETECTED'',
                   ''Blocked by session '' + CAST(r.blocking_session_id AS VARCHAR) + 
                   '' for '' + CAST(r.wait_time/1000 AS VARCHAR) + ''s. '' +
                   ''Wait type: '' + ISNULL(r.wait_type, ''N/A'') +
                   ''. Command: '' + ISNULL(SUBSTRING(st.text, 1, 200), ''N/A''),
                   ''BlockingMonitor''
            FROM sys.dm_exec_requests r
            CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) st
            WHERE r.blocking_session_id <> 0
              AND r.wait_time > 30000;
            
            DECLARE @body NVARCHAR(MAX) = ''Blocking detected on Lakeview Medical SQL MI.'';
            
            SELECT @body = @body + CHAR(13) + CHAR(10) +
                ''Session '' + CAST(r.session_id AS VARCHAR) + 
                '' blocked by '' + CAST(r.blocking_session_id AS VARCHAR) +
                '' for '' + CAST(r.wait_time/1000 AS VARCHAR) + '' seconds''
            FROM sys.dm_exec_requests r
            WHERE r.blocking_session_id <> 0 AND r.wait_time > 30000;
            
            EXEC msdb.dbo.sp_send_dbmail
                @profile_name = ''DBA Mail Profile'',
                @recipients = ''dba-team@lakeviewmedical.org'',
                @subject = ''[LMC SQL MI] Blocking Detected'',
                @body = @body;
        END
    ',
    @database_name = N'master',
    @retry_attempts = 0,
    @on_success_action = 1,
    @on_fail_action = 1;

-- Schedule: Every 2 minutes during business hours
EXEC msdb.dbo.sp_add_jobschedule 
    @job_name = N'LMC - Blocking Monitor',
    @name = N'Every 2 Minutes',
    @enabled = 1,
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 4,
    @freq_subday_interval = 2,
    @active_start_time = 060000,
    @active_end_time = 220000;

PRINT 'Job "LMC - Blocking Monitor" created and ENABLED.';
GO

-- ============================================================================
-- ALERTS: Severity-based alerts (supported on MI)
-- Source: SQLAgent/Alerts/01-DiskSpaceAlert.sql
-- MI Notes: Performance condition alerts (disk space) are NOT supported on MI.
--           Severity-based and message-ID alerts ARE supported.
--           Disk space is managed by Azure; no user action needed.
-- ============================================================================
PRINT '';
PRINT '--- Creating MI-Compatible Alerts ---';
GO

-- Severity 17-25 alerts
DECLARE @severity INT = 17;
WHILE @severity <= 25
BEGIN
    DECLARE @alertName NVARCHAR(100) = N'LMC - Severity ' + CAST(@severity AS NVARCHAR(2)) + ' Error';
    
    IF EXISTS (SELECT 1 FROM msdb.dbo.sysalerts WHERE name = @alertName)
        EXEC msdb.dbo.sp_delete_alert @name = @alertName;
    
    EXEC msdb.dbo.sp_add_alert 
        @name = @alertName,
        @message_id = 0,
        @severity = @severity,
        @enabled = 1,
        @delay_between_responses = 300,
        @notification_message = N'A high-severity SQL Server error has occurred on MI. Review error log immediately.',
        @include_event_description_in = 1;
    
    EXEC msdb.dbo.sp_add_notification 
        @alert_name = @alertName,
        @operator_name = N'DBA Team',
        @notification_method = 1;
    
    SET @severity = @severity + 1;
END

PRINT 'Severity 17-25 alerts created.';
GO

-- Transaction Log Full alert (Error 9002)
IF EXISTS (SELECT 1 FROM msdb.dbo.sysalerts WHERE name = N'LMC - Transaction Log Full')
    EXEC msdb.dbo.sp_delete_alert @name = N'LMC - Transaction Log Full';
GO

EXEC msdb.dbo.sp_add_alert 
    @name = N'LMC - Transaction Log Full',
    @message_id = 9002,
    @severity = 0,
    @enabled = 1,
    @delay_between_responses = 300,
    @notification_message = N'CRITICAL: Transaction log is full on MI. Review database size and contact Azure support if needed.',
    @include_event_description_in = 1;

EXEC msdb.dbo.sp_add_notification 
    @alert_name = N'LMC - Transaction Log Full',
    @operator_name = N'DBA Team',
    @notification_method = 1;

PRINT 'Alert "LMC - Transaction Log Full" created.';
GO

-- ============================================================================
-- NOTE: Disk Space alerts (Warning/Critical) are NOT migrated.
-- Performance condition alerts using LogicalDisk counters are not supported
-- on Azure SQL MI. Disk space is managed by Azure infrastructure.
-- Use Azure Monitor alerts for storage monitoring instead:
--   az monitor metrics alert create --name "MI-StorageAlert" \
--     --resource <mi-resource-id> --condition "avg storage_space_used_mb > 80"
-- ============================================================================

PRINT '';
PRINT '========================================';
PRINT 'SQL Agent Job Migration Complete';
PRINT '========================================';
PRINT 'Jobs ENABLED:  5 (Billing, Claims, Archival, Statistics, Blocking Monitor)';
PRINT 'Jobs DISABLED: 2 (Full Backup, Transaction Log Backup)';
PRINT 'Alerts Created: 10 (Severity 17-25, Transaction Log Full)';
PRINT 'Alerts Skipped: 2 (Disk Space - not supported on MI, use Azure Monitor)';
PRINT '========================================';
GO
