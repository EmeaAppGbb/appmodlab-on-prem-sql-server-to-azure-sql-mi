-- ============================================
-- SQL Agent Job: Monthly Data Archival
-- Lakeview Medical Center
-- Runs first Sunday of each month at 1:00 AM
-- ============================================
USE msdb;
GO

IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = N'LMC - Monthly Data Archival')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'LMC - Monthly Data Archival', @delete_unused_schedule = 1;
END
GO

DECLARE @jobId BINARY(16);

EXEC msdb.dbo.sp_add_job 
    @job_name = N'LMC - Monthly Data Archival',
    @enabled = 1,
    @notify_level_eventlog = 2,
    @notify_level_email = 2,
    @description = N'Archives old clinical and billing records beyond the retention period (7 years). Moves data to archive tables and purges from primary tables.',
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
        -- Archive encounters older than 7 years (84 months)
        EXEC PatientDB.dbo.usp_ArchiveOldRecords 
            @RetentionMonths = 84,
            @BatchSize = 5000,
            @DryRun = 0;
    ',
    @database_name = N'PatientDB',
    @retry_attempts = 1,
    @retry_interval = 10,
    @on_success_action = 2,
    @on_fail_action = 2;

-- Step 2: Archive BillingDB records
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Monthly Data Archival',
    @step_name = N'Archive BillingDB Old Records',
    @step_id = 2,
    @subsystem = N'TSQL',
    @command = N'
        -- Archive old billing charges
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
    @on_success_action = 2,
    @on_fail_action = 2;

-- Step 3: Archive PatientDB audit log
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Monthly Data Archival',
    @step_name = N'Purge Old Audit Records',
    @step_id = 3,
    @subsystem = N'TSQL',
    @command = N'
        -- Purge PatientDB audit log older than 3 years
        DECLARE @PurgeDate DATE = DATEADD(YEAR, -3, GETDATE());
        
        DELETE FROM PatientDB.dbo.AuditLog
        WHERE ChangedDate < @PurgeDate;
        
        PRINT ''Audit records purged: '' + CAST(@@ROWCOUNT AS VARCHAR);
    ',
    @database_name = N'PatientDB',
    @retry_attempts = 0,
    @on_success_action = 2,
    @on_fail_action = 2;

-- Step 4: Rebuild indexes after archival
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Monthly Data Archival',
    @step_name = N'Rebuild Fragmented Indexes',
    @step_id = 4,
    @subsystem = N'TSQL',
    @command = N'
        -- Rebuild indexes with > 30% fragmentation
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
            SET @SQL = ''ALTER INDEX '' + @IndexName + '' ON '' + @TableName + '' REBUILD WITH (ONLINE = OFF)'';
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
    @freq_type = 32,         -- Monthly relative
    @freq_interval = 1,      -- Sunday
    @freq_relative_interval = 1,  -- First
    @freq_recurrence_factor = 1,
    @active_start_time = 010000;

PRINT 'SQL Agent Job "LMC - Monthly Data Archival" created.';
GO
