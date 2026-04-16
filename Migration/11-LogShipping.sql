-- ============================================
-- Continuous Transaction Log Shipping for
-- Online Migration to Azure SQL MI
-- Lakeview Medical Center
-- Sets up scheduled transaction log backups on
-- the on-premises SQL Server 2016 and ships them
-- to Azure Blob storage for continuous restore
-- on the target Managed Instance.
-- ============================================
-- Run against the on-premises SQL Server instance
-- Requires: sysadmin (for SQL Agent job creation)
-- Databases: PatientDB, BillingDB, SchedulingDB,
--            ReportingDB
-- ============================================

SET NOCOUNT ON;
GO

PRINT '================================================================';
PRINT ' Lakeview Medical Center - Transaction Log Shipping Setup';
PRINT ' Run Date: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT ' Server  : ' + @@SERVERNAME;
PRINT ' Version : ' + @@VERSION;
PRINT '================================================================';
PRINT '';
GO

-- ============================================
-- Verify we are on the source server
-- ============================================
IF SERVERPROPERTY('EngineEdition') = 8
BEGIN
    RAISERROR('This script must be run on the ON-PREMISES SQL Server, not on SQL Managed Instance.', 16, 1);
    RETURN;
END
GO

-- ============================================
-- CONFIGURATION - Update these values
-- ============================================
DECLARE @BackupShare    NVARCHAR(500) = N'\\<FILE-SERVER>\SQLBackups\LakeviewMedical\LogBackups';
DECLARE @BlobContainer  NVARCHAR(500) = N'https://<STORAGE-ACCOUNT>.blob.core.windows.net/dms-backups';
DECLARE @CredentialName NVARCHAR(256) = N'LakeviewMedical_AzureBlobCredential';
DECLARE @LogIntervalMin INT           = 5;  -- Log backup frequency in minutes

PRINT 'Configuration:';
PRINT '  Backup share     : ' + @BackupShare;
PRINT '  Blob container   : ' + @BlobContainer;
PRINT '  Credential       : ' + @CredentialName;
PRINT '  Log interval     : Every ' + CAST(@LogIntervalMin AS VARCHAR(5)) + ' minutes';
PRINT '';
GO

-- ============================================
-- Step 1: Create credential for Azure Blob
-- storage access (if not already created)
-- ============================================
PRINT '--- Step 1: Azure Blob Storage Credential ---';
PRINT '';

IF NOT EXISTS (SELECT 1 FROM sys.credentials WHERE name = N'LakeviewMedical_AzureBlobCredential')
BEGIN
    CREATE CREDENTIAL [LakeviewMedical_AzureBlobCredential]
    WITH IDENTITY = N'<STORAGE-ACCOUNT>',
    SECRET = N'<STORAGE-ACCOUNT-ACCESS-KEY>';

    PRINT 'Credential [LakeviewMedical_AzureBlobCredential] created.';
END
ELSE
    PRINT 'Credential [LakeviewMedical_AzureBlobCredential] already exists.';
GO

-- ============================================
-- Step 2: Verify recovery model is FULL for
-- all migration databases
-- ============================================
PRINT '';
PRINT '--- Step 2: Recovery Model Verification ---';
PRINT '';

DECLARE @DbName NVARCHAR(128);
DECLARE @RecModel NVARCHAR(20);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name, recovery_model_desc
    FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DbName, @RecModel;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF @RecModel <> 'FULL'
    BEGIN
        PRINT 'WARNING: ' + @DbName + ' is in ' + @RecModel + ' recovery — switching to FULL.';
        DECLARE @sql NVARCHAR(200) = N'ALTER DATABASE [' + @DbName + N'] SET RECOVERY FULL;';
        EXEC sp_executesql @sql;
        PRINT @DbName + ' recovery model set to FULL.';
    END
    ELSE
        PRINT @DbName + ' — recovery model is FULL (OK).';

    FETCH NEXT FROM db_cursor INTO @DbName, @RecModel;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;
GO

-- ============================================
-- Step 3: Take initial transaction log backups
-- to Azure Blob storage (direct to URL)
-- ============================================
PRINT '';
PRINT '--- Step 3: Initial Transaction Log Backups to Azure Blob ---';
PRINT '';
GO

-- PatientDB log backup
DECLARE @BlobContainer NVARCHAR(500) = N'https://<STORAGE-ACCOUNT>.blob.core.windows.net/dms-backups';
DECLARE @LogFile NVARCHAR(500);
DECLARE @StartTime DATETIME;
DECLARE @Duration INT;

SET @LogFile = @BlobContainer + N'/PatientDB_LOG_' +
    REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(20), GETDATE(), 120), '-', ''), ':', ''), ' ', '_') + N'.trn';

PRINT 'Backing up PatientDB transaction log to blob...';
SET @StartTime = GETDATE();

BACKUP LOG [PatientDB]
TO URL = @LogFile
WITH
    COMPRESSION,
    CHECKSUM,
    NO_TRUNCATE,
    NAME = N'PatientDB - Log Backup for MI Migration',
    STATS = 10;

SET @Duration = DATEDIFF(SECOND, @StartTime, GETDATE());
PRINT 'PatientDB log backup completed in ' + CAST(@Duration AS VARCHAR(10)) + ' seconds.';
PRINT '';
GO

-- BillingDB log backup
DECLARE @BlobContainer NVARCHAR(500) = N'https://<STORAGE-ACCOUNT>.blob.core.windows.net/dms-backups';
DECLARE @LogFile NVARCHAR(500);
DECLARE @StartTime DATETIME;
DECLARE @Duration INT;

SET @LogFile = @BlobContainer + N'/BillingDB_LOG_' +
    REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(20), GETDATE(), 120), '-', ''), ':', ''), ' ', '_') + N'.trn';

PRINT 'Backing up BillingDB transaction log to blob...';
SET @StartTime = GETDATE();

BACKUP LOG [BillingDB]
TO URL = @LogFile
WITH
    COMPRESSION,
    CHECKSUM,
    NO_TRUNCATE,
    NAME = N'BillingDB - Log Backup for MI Migration',
    STATS = 10;

SET @Duration = DATEDIFF(SECOND, @StartTime, GETDATE());
PRINT 'BillingDB log backup completed in ' + CAST(@Duration AS VARCHAR(10)) + ' seconds.';
PRINT '';
GO

-- SchedulingDB log backup
DECLARE @BlobContainer NVARCHAR(500) = N'https://<STORAGE-ACCOUNT>.blob.core.windows.net/dms-backups';
DECLARE @LogFile NVARCHAR(500);
DECLARE @StartTime DATETIME;
DECLARE @Duration INT;

SET @LogFile = @BlobContainer + N'/SchedulingDB_LOG_' +
    REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(20), GETDATE(), 120), '-', ''), ':', ''), ' ', '_') + N'.trn';

PRINT 'Backing up SchedulingDB transaction log to blob...';
SET @StartTime = GETDATE();

BACKUP LOG [SchedulingDB]
TO URL = @LogFile
WITH
    COMPRESSION,
    CHECKSUM,
    NO_TRUNCATE,
    NAME = N'SchedulingDB - Log Backup for MI Migration',
    STATS = 10;

SET @Duration = DATEDIFF(SECOND, @StartTime, GETDATE());
PRINT 'SchedulingDB log backup completed in ' + CAST(@Duration AS VARCHAR(10)) + ' seconds.';
PRINT '';
GO

-- ReportingDB log backup
DECLARE @BlobContainer NVARCHAR(500) = N'https://<STORAGE-ACCOUNT>.blob.core.windows.net/dms-backups';
DECLARE @LogFile NVARCHAR(500);
DECLARE @StartTime DATETIME;
DECLARE @Duration INT;

SET @LogFile = @BlobContainer + N'/ReportingDB_LOG_' +
    REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(20), GETDATE(), 120), '-', ''), ':', ''), ' ', '_') + N'.trn';

PRINT 'Backing up ReportingDB transaction log to blob...';
SET @StartTime = GETDATE();

BACKUP LOG [ReportingDB]
TO URL = @LogFile
WITH
    COMPRESSION,
    CHECKSUM,
    NO_TRUNCATE,
    NAME = N'ReportingDB - Log Backup for MI Migration',
    STATS = 10;

SET @Duration = DATEDIFF(SECOND, @StartTime, GETDATE());
PRINT 'ReportingDB log backup completed in ' + CAST(@Duration AS VARCHAR(10)) + ' seconds.';
PRINT '';
GO

-- ============================================
-- Step 4: Create SQL Agent job for continuous
-- log backups every N minutes
-- ============================================
PRINT '';
PRINT '--- Step 4: SQL Agent Job for Continuous Log Shipping ---';
PRINT '';
GO

USE msdb;
GO

-- Remove existing job if re-running
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'Lakeview_MI_Migration_LogShipping')
BEGIN
    EXEC sp_delete_job @job_name = N'Lakeview_MI_Migration_LogShipping', @delete_unused_schedule = 1;
    PRINT 'Removed existing log shipping job.';
END
GO

-- Create the job
EXEC sp_add_job
    @job_name = N'Lakeview_MI_Migration_LogShipping',
    @enabled = 1,
    @description = N'Continuous transaction log backups to Azure Blob for online migration of Lakeview Medical databases to SQL MI.',
    @category_name = N'Database Maintenance',
    @owner_login_name = N'sa',
    @notify_level_eventlog = 2;  -- On failure
GO

-- Job step: Back up all 4 database transaction logs to blob
EXEC sp_add_jobstep
    @job_name = N'Lakeview_MI_Migration_LogShipping',
    @step_name = N'Backup All Transaction Logs to Blob',
    @step_id = 1,
    @subsystem = N'TSQL',
    @command = N'
SET NOCOUNT ON;

DECLARE @BlobContainer NVARCHAR(500) = N''https://<STORAGE-ACCOUNT>.blob.core.windows.net/dms-backups'';
DECLARE @Timestamp NVARCHAR(20) = REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(20), GETDATE(), 120), ''-'', ''''), '':'', ''''), '' '', ''_'');
DECLARE @DbName NVARCHAR(128);
DECLARE @SQL NVARCHAR(MAX);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN (''PatientDB'', ''BillingDB'', ''SchedulingDB'', ''ReportingDB'')
      AND state_desc = ''ONLINE''
      AND recovery_model_desc = ''FULL'';

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DbName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @SQL = N''BACKUP LOG ['' + @DbName + N'']
        TO URL = N'''''' + @BlobContainer + N''/'' + @DbName + N''_LOG_'' + @Timestamp + N''.trn''''
        WITH COMPRESSION, CHECKSUM, NAME = N'''''' + @DbName + N'' - Log Backup for MI Migration'''''', STATS = 10;'';

    BEGIN TRY
        EXEC sp_executesql @SQL;
        PRINT @DbName + '' log backup completed.'';
    END TRY
    BEGIN CATCH
        PRINT ''ERROR backing up '' + @DbName + '': '' + ERROR_MESSAGE();
    END CATCH

    FETCH NEXT FROM db_cursor INTO @DbName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;
',
    @database_name = N'master',
    @retry_attempts = 3,
    @retry_interval = 2,
    @on_success_action = 1,  -- Quit with success
    @on_fail_action = 2;     -- Quit with failure
GO

-- Schedule: Run every 5 minutes
EXEC sp_add_jobschedule
    @job_name = N'Lakeview_MI_Migration_LogShipping',
    @name = N'Every_5_Minutes_LogBackup',
    @freq_type = 4,           -- Daily
    @freq_interval = 1,
    @freq_subday_type = 4,    -- Minutes
    @freq_subday_interval = 5,
    @active_start_time = 0,   -- 00:00:00
    @active_end_time = 235959;
GO

-- Assign to local server
EXEC sp_add_jobserver
    @job_name = N'Lakeview_MI_Migration_LogShipping',
    @server_name = N'(LOCAL)';
GO

PRINT 'SQL Agent job [Lakeview_MI_Migration_LogShipping] created and scheduled (every 5 minutes).';
PRINT '';
GO

USE master;
GO

-- ============================================
-- Step 5: Log Shipping Status & Monitoring
-- ============================================
PRINT '';
PRINT '================================================================';
PRINT ' LOG SHIPPING MONITORING QUERIES';
PRINT '================================================================';
PRINT '';
GO

-- ============================================
-- 5a: Recent log backup history
-- ============================================
PRINT '--- Recent Log Backup History (Last Hour) ---';
PRINT '';

SELECT
    bs.database_name                                       AS [Database],
    bs.backup_start_date                                   AS [Start Time],
    bs.backup_finish_date                                  AS [End Time],
    DATEDIFF(SECOND, bs.backup_start_date,
             bs.backup_finish_date)                        AS [Duration (sec)],
    CAST(bs.backup_size / 1048576.0 AS DECIMAL(12,2))     AS [Size (MB)],
    CAST(bs.compressed_backup_size / 1048576.0
         AS DECIMAL(12,2))                                 AS [Compressed (MB)],
    bs.first_lsn                                           AS [First LSN],
    bs.last_lsn                                            AS [Last LSN],
    bmf.physical_device_name                               AS [Backup Destination]
FROM msdb.dbo.backupset bs
INNER JOIN msdb.dbo.backupmediafamily bmf
    ON bs.media_set_id = bmf.media_set_id
WHERE bs.database_name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
    AND bs.type = 'L'  -- Log backups
    AND bs.backup_start_date >= DATEADD(HOUR, -1, GETDATE())
ORDER BY bs.database_name, bs.backup_start_date DESC;
GO

-- ============================================
-- 5b: Log backup chain continuity check
-- ============================================
PRINT '';
PRINT '--- Log Backup Chain Continuity ---';
PRINT '';

;WITH LogChain AS (
    SELECT
        bs.database_name,
        bs.first_lsn,
        bs.last_lsn,
        bs.backup_start_date,
        LAG(bs.last_lsn) OVER (
            PARTITION BY bs.database_name ORDER BY bs.backup_start_date
        ) AS prev_last_lsn
    FROM msdb.dbo.backupset bs
    WHERE bs.database_name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
        AND bs.type = 'L'
        AND bs.backup_start_date >= DATEADD(DAY, -1, GETDATE())
)
SELECT
    database_name                                     AS [Database],
    COUNT(*)                                          AS [Log Backups (24h)],
    MIN(backup_start_date)                            AS [Earliest],
    MAX(backup_start_date)                            AS [Latest],
    SUM(CASE WHEN prev_last_lsn IS NOT NULL
              AND first_lsn <> prev_last_lsn
         THEN 1 ELSE 0 END)                          AS [Chain Breaks],
    CASE
        WHEN SUM(CASE WHEN prev_last_lsn IS NOT NULL
                       AND first_lsn <> prev_last_lsn
                  THEN 1 ELSE 0 END) = 0 THEN 'OK'
        ELSE 'BROKEN — new full backup required'
    END                                               AS [Chain Status]
FROM LogChain
GROUP BY database_name
ORDER BY database_name;
GO

-- ============================================
-- 5c: Current log space usage
-- ============================================
PRINT '';
PRINT '--- Transaction Log Space Usage ---';
PRINT '';

DBCC SQLPERF(LOGSPACE);
GO

-- ============================================
-- 5d: SQL Agent job run history
-- ============================================
PRINT '';
PRINT '--- Log Shipping Job Run History (Last 20 Runs) ---';
PRINT '';

SELECT TOP 20
    j.name                                              AS [Job Name],
    CASE h.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Canceled'
        WHEN 4 THEN 'In Progress'
    END                                                 AS [Status],
    msdb.dbo.agent_datetime(h.run_date, h.run_time)    AS [Run DateTime],
    STUFF(STUFF(RIGHT('000000' + CAST(h.run_duration AS VARCHAR(6)), 6),
          3, 0, ':'), 6, 0, ':')                        AS [Duration (HH:MM:SS)],
    h.message                                           AS [Message]
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobhistory h
    ON j.job_id = h.job_id
WHERE j.name = N'Lakeview_MI_Migration_LogShipping'
    AND h.step_id = 0  -- Job outcome
ORDER BY h.run_date DESC, h.run_time DESC;
GO

-- ============================================
-- 5e: Log generation rate (helps estimate
-- cutover window timing)
-- ============================================
PRINT '';
PRINT '--- Log Generation Rate (Last Hour) ---';
PRINT '';

SELECT
    bs.database_name                                       AS [Database],
    COUNT(*)                                               AS [Log Backups],
    CAST(SUM(bs.backup_size) / 1048576.0
         AS DECIMAL(12,2))                                 AS [Total Log (MB)],
    CAST(AVG(bs.backup_size) / 1048576.0
         AS DECIMAL(12,2))                                 AS [Avg Log (MB)],
    CAST(SUM(bs.backup_size) / 1048576.0 / 60.0
         AS DECIMAL(12,2))                                 AS [Log Rate (MB/min)]
FROM msdb.dbo.backupset bs
WHERE bs.database_name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
    AND bs.type = 'L'
    AND bs.backup_start_date >= DATEADD(HOUR, -1, GETDATE())
GROUP BY bs.database_name
ORDER BY bs.database_name;
GO

PRINT '';
PRINT '================================================================';
PRINT ' LOG SHIPPING SETUP COMPLETE';
PRINT ' SQL Agent job is running every 5 minutes.';
PRINT ' Monitor with queries above or 12-MigrationMonitoring.sql.';
PRINT '';
PRINT ' To STOP log shipping before cutover, disable the job:';
PRINT '   EXEC msdb.dbo.sp_update_job';
PRINT '       @job_name = N''Lakeview_MI_Migration_LogShipping'',';
PRINT '       @enabled = 0;';
PRINT '';
PRINT ' To REMOVE the job after migration completes:';
PRINT '   EXEC msdb.dbo.sp_delete_job';
PRINT '       @job_name = N''Lakeview_MI_Migration_LogShipping'',';
PRINT '       @delete_unused_schedule = 1;';
PRINT '================================================================';
GO
