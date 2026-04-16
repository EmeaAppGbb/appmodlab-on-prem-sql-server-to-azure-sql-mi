-- ============================================
-- Migration Monitoring Dashboard
-- Lakeview Medical Center
-- Comprehensive monitoring of the online
-- migration from on-premises SQL Server 2016
-- to Azure SQL Managed Instance via DMS.
-- ============================================
-- Run sections against source or target as noted
-- Requires: VIEW SERVER STATE, VIEW ANY DEFINITION
-- Databases: PatientDB, BillingDB, SchedulingDB,
--            ReportingDB
-- ============================================

SET NOCOUNT ON;
GO

PRINT '================================================================';
PRINT ' Lakeview Medical Center - Migration Monitoring Dashboard';
PRINT ' Run Date: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT ' Server  : ' + @@SERVERNAME;
PRINT '================================================================';
PRINT '';
GO

-- ============================================
-- SECTION 1: SOURCE SERVER MONITORING
-- (Run on on-premises SQL Server)
-- ============================================

PRINT '================================================================';
PRINT ' SECTION 1: SOURCE SERVER STATUS';
PRINT '================================================================';
PRINT '';
GO

-- ============================================
-- 1a: Database status overview
-- ============================================
PRINT '--- 1a: Database Status Overview ---';
PRINT '';

SELECT
    d.name                                              AS [Database],
    d.state_desc                                        AS [State],
    d.recovery_model_desc                               AS [Recovery Model],
    CAST(SUM(mf.size) * 8.0 / 1024.0 AS DECIMAL(12,2)) AS [Total Size (MB)],
    d.is_encrypted                                      AS [TDE Encrypted],
    d.log_reuse_wait_desc                               AS [Log Reuse Wait],
    d.compatibility_level                               AS [Compat Level]
FROM sys.databases d
INNER JOIN sys.master_files mf ON d.database_id = mf.database_id
WHERE d.name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
GROUP BY d.name, d.state_desc, d.recovery_model_desc,
         d.is_encrypted, d.log_reuse_wait_desc, d.compatibility_level
ORDER BY d.name;
GO

-- ============================================
-- 1b: Transaction log space usage
-- ============================================
PRINT '';
PRINT '--- 1b: Transaction Log Space Usage ---';
PRINT '';

IF OBJECT_ID('tempdb..#LogSpace') IS NOT NULL
    DROP TABLE #LogSpace;

CREATE TABLE #LogSpace (
    DatabaseName  NVARCHAR(128),
    LogSizeMB     DECIMAL(12,2),
    LogUsedPct    DECIMAL(5,2),
    Status        INT
);

INSERT INTO #LogSpace
EXEC ('DBCC SQLPERF(LOGSPACE) WITH NO_INFOMSGS');

SELECT
    DatabaseName                                         AS [Database],
    LogSizeMB                                            AS [Log Size (MB)],
    LogUsedPct                                           AS [Log Used (%)],
    CAST(LogSizeMB * LogUsedPct / 100.0
         AS DECIMAL(12,2))                               AS [Log Used (MB)],
    CASE
        WHEN LogUsedPct > 90 THEN 'CRITICAL — log nearly full'
        WHEN LogUsedPct > 75 THEN 'WARNING — consider log backup'
        ELSE 'OK'
    END                                                  AS [Health]
FROM #LogSpace
WHERE DatabaseName IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
ORDER BY DatabaseName;
GO

-- ============================================
-- 1c: Last backup times and LSN tracking
-- ============================================
PRINT '';
PRINT '--- 1c: Last Backup Times & LSN Progress ---';
PRINT '';

SELECT
    bs.database_name                                     AS [Database],
    CASE bs.type
        WHEN 'D' THEN 'Full'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Log'
    END                                                  AS [Backup Type],
    MAX(bs.backup_finish_date)                           AS [Last Backup Time],
    DATEDIFF(MINUTE, MAX(bs.backup_finish_date),
             GETDATE())                                  AS [Minutes Since Last],
    MAX(bs.last_lsn)                                     AS [Last LSN Backed Up],
    CASE
        WHEN DATEDIFF(MINUTE, MAX(bs.backup_finish_date), GETDATE()) > 15
        THEN 'WARNING — backup may be stale'
        ELSE 'OK'
    END                                                  AS [Status]
FROM msdb.dbo.backupset bs
WHERE bs.database_name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
    AND bs.type IN ('D', 'L')
    AND bs.backup_start_date >= DATEADD(DAY, -1, GETDATE())
GROUP BY bs.database_name, bs.type
ORDER BY bs.database_name, bs.type;
GO

-- ============================================
-- 1d: Active transactions that could delay
-- log truncation
-- ============================================
PRINT '';
PRINT '--- 1d: Long-Running Active Transactions ---';
PRINT '';

SELECT
    DB_NAME(dt.database_id)                              AS [Database],
    dt.transaction_id                                    AS [Transaction ID],
    tat.name                                             AS [Transaction Name],
    tat.transaction_begin_time                           AS [Start Time],
    DATEDIFF(MINUTE, tat.transaction_begin_time,
             GETDATE())                                  AS [Duration (min)],
    CASE tat.transaction_state
        WHEN 0 THEN 'Initializing'
        WHEN 1 THEN 'Initialized (not started)'
        WHEN 2 THEN 'Active'
        WHEN 3 THEN 'Ended (read-only)'
        WHEN 4 THEN 'Commit initiated (distributed)'
        WHEN 5 THEN 'Prepared (waiting resolution)'
        WHEN 6 THEN 'Committed'
        WHEN 7 THEN 'Rolling back'
        WHEN 8 THEN 'Rolled back'
    END                                                  AS [State],
    es.login_name                                        AS [Login],
    es.host_name                                         AS [Host],
    es.program_name                                      AS [Application]
FROM sys.dm_tran_database_transactions dt
INNER JOIN sys.dm_tran_active_transactions tat
    ON dt.transaction_id = tat.transaction_id
LEFT JOIN sys.dm_tran_session_transactions st
    ON tat.transaction_id = st.transaction_id
LEFT JOIN sys.dm_exec_sessions es
    ON st.session_id = es.session_id
WHERE DB_NAME(dt.database_id) IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
    AND DATEDIFF(MINUTE, tat.transaction_begin_time, GETDATE()) > 5
ORDER BY tat.transaction_begin_time;
GO

-- ============================================
-- 1e: Log shipping job health
-- ============================================
PRINT '';
PRINT '--- 1e: Log Shipping Agent Job Status ---';
PRINT '';

SELECT
    j.name                                              AS [Job Name],
    CASE ja.run_requested_source
        WHEN 1 THEN 'Schedule'
        WHEN 2 THEN 'Alerter'
        WHEN 3 THEN 'Boot'
        WHEN 4 THEN 'User'
        ELSE 'Unknown'
    END                                                 AS [Last Start Source],
    ja.start_execution_date                             AS [Last Start Time],
    ja.stop_execution_date                              AS [Last Stop Time],
    CASE
        WHEN ja.start_execution_date IS NOT NULL
             AND ja.stop_execution_date IS NULL THEN 'Running'
        ELSE 'Idle'
    END                                                 AS [Current State],
    CASE j.enabled
        WHEN 1 THEN 'Enabled'
        WHEN 0 THEN 'DISABLED'
    END                                                 AS [Job Enabled],
    (SELECT TOP 1
         CASE h.run_status WHEN 0 THEN 'Failed'
              WHEN 1 THEN 'Succeeded' WHEN 2 THEN 'Retry'
              WHEN 3 THEN 'Canceled' END
     FROM msdb.dbo.sysjobhistory h
     WHERE h.job_id = j.job_id AND h.step_id = 0
     ORDER BY h.run_date DESC, h.run_time DESC)         AS [Last Outcome]
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.sysjobactivity ja
    ON j.job_id = ja.job_id
    AND ja.session_id = (SELECT MAX(session_id)
                         FROM msdb.dbo.syssessions)
WHERE j.name LIKE N'%Lakeview%Migration%LogShipping%';
GO

-- ============================================
-- 1f: Log generation rate and throughput
-- ============================================
PRINT '';
PRINT '--- 1f: Log Generation Rate (Last Hour) ---';
PRINT '';

SELECT
    bs.database_name                                     AS [Database],
    COUNT(*)                                             AS [Backups (1h)],
    CAST(SUM(bs.backup_size) / 1048576.0
         AS DECIMAL(12,2))                               AS [Total Log (MB)],
    CAST(AVG(bs.backup_size) / 1048576.0
         AS DECIMAL(12,2))                               AS [Avg Per Backup (MB)],
    CAST(SUM(bs.backup_size) / 1048576.0 / 60.0
         AS DECIMAL(12,4))                               AS [Rate (MB/min)],
    CAST(SUM(bs.compressed_backup_size) / 1048576.0
         AS DECIMAL(12,2))                               AS [Compressed (MB)],
    MIN(bs.first_lsn)                                    AS [Earliest LSN],
    MAX(bs.last_lsn)                                     AS [Latest LSN]
FROM msdb.dbo.backupset bs
WHERE bs.database_name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
    AND bs.type = 'L'
    AND bs.backup_start_date >= DATEADD(HOUR, -1, GETDATE())
GROUP BY bs.database_name
ORDER BY bs.database_name;
GO


-- ============================================
-- SECTION 2: TARGET MI MONITORING
-- (Run on Azure SQL Managed Instance)
-- ============================================

/*
-- Uncomment and run on the Azure SQL Managed Instance

PRINT '';
PRINT '================================================================';
PRINT ' SECTION 2: TARGET MI - DATABASE RESTORE STATUS';
PRINT '================================================================';
PRINT '';
GO

-- ============================================
-- 2a: Database restore state on MI
-- ============================================
PRINT '--- 2a: Database State on Managed Instance ---';
PRINT '';

SELECT
    d.name                                              AS [Database],
    d.state_desc                                        AS [State],
    d.recovery_model_desc                               AS [Recovery Model],
    d.create_date                                       AS [Created On MI],
    CASE
        WHEN d.state_desc = 'RESTORING'  THEN 'Receiving logs — ready for migration'
        WHEN d.state_desc = 'ONLINE'     THEN 'ONLINE — migration may be complete'
        WHEN d.state_desc = 'RECOVERING' THEN 'Recovery in progress'
        ELSE d.state_desc
    END                                                 AS [Migration State]
FROM sys.databases d
WHERE d.name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
ORDER BY d.name;
GO

-- ============================================
-- 2b: Last restored log backup details
-- ============================================
PRINT '';
PRINT '--- 2b: Last Restored Backup Details ---';
PRINT '';

SELECT
    rh.destination_database_name                        AS [Database],
    CASE rh.restore_type
        WHEN 'D' THEN 'Full'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Log'
    END                                                 AS [Restore Type],
    rh.restore_date                                     AS [Restore Date],
    DATEDIFF(MINUTE, rh.restore_date, GETDATE())       AS [Minutes Ago],
    bf.physical_device_name                             AS [Source File]
FROM msdb.dbo.restorehistory rh
LEFT JOIN msdb.dbo.backupset bs
    ON rh.backup_set_id = bs.backup_set_id
LEFT JOIN msdb.dbo.backupmediafamily bf
    ON bs.media_set_id = bf.media_set_id
WHERE rh.destination_database_name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
    AND rh.restore_date = (
        SELECT MAX(rh2.restore_date)
        FROM msdb.dbo.restorehistory rh2
        WHERE rh2.destination_database_name = rh.destination_database_name
    )
ORDER BY rh.destination_database_name;
GO

*/


-- ============================================
-- SECTION 3: DMS MIGRATION STATUS
-- (Query DMS status via system DMVs or
--  Azure portal REST API calls)
-- ============================================

PRINT '';
PRINT '================================================================';
PRINT ' SECTION 3: DMS / MIGRATION PROGRESS ESTIMATION';
PRINT '================================================================';
PRINT '';
GO

-- ============================================
-- 3a: Data sync progress estimation
-- Compares source database sizes and log
-- generation to estimate completion
-- ============================================
PRINT '--- 3a: Data Sync Progress Estimation ---';
PRINT '';

IF OBJECT_ID('tempdb..#MigrationProgress') IS NOT NULL
    DROP TABLE #MigrationProgress;

CREATE TABLE #MigrationProgress (
    DatabaseName        NVARCHAR(128),
    DataSizeMB          DECIMAL(12,2),
    LogSizeMB           DECIMAL(12,2),
    LogUsedMB           DECIMAL(12,2),
    LastFullBackup      DATETIME,
    LastLogBackup       DATETIME,
    LogBackupsLast1h    INT,
    LogMBLast1h         DECIMAL(12,2),
    LogRateMBPerMin     DECIMAL(12,4),
    PendingLogMB        DECIMAL(12,2),
    EstMinutesToSync    DECIMAL(12,2)
);

INSERT INTO #MigrationProgress (
    DatabaseName, DataSizeMB, LogSizeMB, LogUsedMB,
    LastFullBackup, LastLogBackup,
    LogBackupsLast1h, LogMBLast1h, LogRateMBPerMin,
    PendingLogMB, EstMinutesToSync
)
SELECT
    d.name,
    -- Data size
    (SELECT CAST(SUM(mf.size) * 8.0 / 1024.0 AS DECIMAL(12,2))
     FROM sys.master_files mf
     WHERE mf.database_id = d.database_id AND mf.type = 0),
    -- Log size
    (SELECT CAST(SUM(mf.size) * 8.0 / 1024.0 AS DECIMAL(12,2))
     FROM sys.master_files mf
     WHERE mf.database_id = d.database_id AND mf.type = 1),
    -- Log used (from SQLPERF)
    ISNULL((SELECT CAST(ls.LogSizeMB * ls.LogUsedPct / 100.0 AS DECIMAL(12,2))
            FROM #LogSpace ls WHERE ls.DatabaseName = d.name), 0),
    -- Last full backup
    (SELECT MAX(bs.backup_finish_date)
     FROM msdb.dbo.backupset bs
     WHERE bs.database_name = d.name AND bs.type = 'D'),
    -- Last log backup
    (SELECT MAX(bs.backup_finish_date)
     FROM msdb.dbo.backupset bs
     WHERE bs.database_name = d.name AND bs.type = 'L'),
    -- Log backups in last hour
    ISNULL((SELECT COUNT(*)
            FROM msdb.dbo.backupset bs
            WHERE bs.database_name = d.name AND bs.type = 'L'
              AND bs.backup_start_date >= DATEADD(HOUR, -1, GETDATE())), 0),
    -- Log MB in last hour
    ISNULL((SELECT CAST(SUM(bs.backup_size) / 1048576.0 AS DECIMAL(12,2))
            FROM msdb.dbo.backupset bs
            WHERE bs.database_name = d.name AND bs.type = 'L'
              AND bs.backup_start_date >= DATEADD(HOUR, -1, GETDATE())), 0),
    -- Log rate MB/min
    ISNULL((SELECT CAST(SUM(bs.backup_size) / 1048576.0 / 60.0 AS DECIMAL(12,4))
            FROM msdb.dbo.backupset bs
            WHERE bs.database_name = d.name AND bs.type = 'L'
              AND bs.backup_start_date >= DATEADD(HOUR, -1, GETDATE())), 0),
    -- Pending log (estimated from log used since last backup)
    ISNULL((SELECT CAST(ls.LogSizeMB * ls.LogUsedPct / 100.0 AS DECIMAL(12,2))
            FROM #LogSpace ls WHERE ls.DatabaseName = d.name), 0),
    -- Estimated minutes to sync (pending log / rate)
    CASE
        WHEN ISNULL((SELECT SUM(bs.backup_size) / 1048576.0 / 60.0
                     FROM msdb.dbo.backupset bs
                     WHERE bs.database_name = d.name AND bs.type = 'L'
                       AND bs.backup_start_date >= DATEADD(HOUR, -1, GETDATE())), 0) > 0
        THEN CAST(
            ISNULL((SELECT ls.LogSizeMB * ls.LogUsedPct / 100.0
                    FROM #LogSpace ls WHERE ls.DatabaseName = d.name), 0)
            /
            (SELECT SUM(bs.backup_size) / 1048576.0 / 60.0
             FROM msdb.dbo.backupset bs
             WHERE bs.database_name = d.name AND bs.type = 'L'
               AND bs.backup_start_date >= DATEADD(HOUR, -1, GETDATE()))
            AS DECIMAL(12,2))
        ELSE NULL
    END
FROM sys.databases d
WHERE d.name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

SELECT
    DatabaseName                                        AS [Database],
    DataSizeMB                                          AS [Data Size (MB)],
    LogSizeMB                                           AS [Log Size (MB)],
    LogUsedMB                                           AS [Log Used (MB)],
    LastFullBackup                                      AS [Last Full Backup],
    LastLogBackup                                       AS [Last Log Backup],
    DATEDIFF(MINUTE, LastLogBackup, GETDATE())          AS [Min Since Last Log],
    LogBackupsLast1h                                    AS [Log Backups (1h)],
    LogMBLast1h                                         AS [Log Shipped (MB/1h)],
    LogRateMBPerMin                                     AS [Log Rate (MB/min)],
    PendingLogMB                                        AS [Pending Log (MB)],
    CASE
        WHEN EstMinutesToSync IS NOT NULL
        THEN CAST(EstMinutesToSync AS VARCHAR(10)) + ' min'
        ELSE 'N/A — no recent log backups'
    END                                                 AS [Est. Time to Sync]
FROM #MigrationProgress
ORDER BY DatabaseName;
GO

-- ============================================
-- 3b: Pending log records (VLFs waiting to
-- be backed up and shipped)
-- ============================================
PRINT '';
PRINT '--- 3b: Virtual Log File (VLF) Status ---';
PRINT '';

IF OBJECT_ID('tempdb..#VLFInfo') IS NOT NULL
    DROP TABLE #VLFInfo;

CREATE TABLE #VLFInfo (
    RecoveryUnitId  INT,
    FileId          INT,
    FileSize        BIGINT,
    StartOffset     BIGINT,
    FSeqNo          INT,
    Status          INT,
    Parity          SMALLINT,
    CreateLSN       NUMERIC(25,0)
);

IF OBJECT_ID('tempdb..#VLFSummary') IS NOT NULL
    DROP TABLE #VLFSummary;

CREATE TABLE #VLFSummary (
    DatabaseName  NVARCHAR(128),
    TotalVLFs     INT,
    ActiveVLFs    INT,
    ActiveSizeMB  DECIMAL(12,2)
);

DECLARE @dbname NVARCHAR(128);
DECLARE vlf_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

OPEN vlf_cursor;
FETCH NEXT FROM vlf_cursor INTO @dbname;

WHILE @@FETCH_STATUS = 0
BEGIN
    TRUNCATE TABLE #VLFInfo;

    DECLARE @vlfsql NVARCHAR(200) = N'DBCC LOGINFO([' + @dbname + N']) WITH NO_INFOMSGS';
    INSERT INTO #VLFInfo EXEC sp_executesql @vlfsql;

    INSERT INTO #VLFSummary
    SELECT
        @dbname,
        COUNT(*),
        SUM(CASE WHEN Status = 2 THEN 1 ELSE 0 END),
        CAST(SUM(CASE WHEN Status = 2 THEN FileSize ELSE 0 END)
             / 1048576.0 AS DECIMAL(12,2));

    FETCH NEXT FROM vlf_cursor INTO @dbname;
END

CLOSE vlf_cursor;
DEALLOCATE vlf_cursor;

SELECT
    DatabaseName                                        AS [Database],
    TotalVLFs                                           AS [Total VLFs],
    ActiveVLFs                                          AS [Active VLFs],
    ActiveSizeMB                                        AS [Active VLF Size (MB)],
    CASE
        WHEN TotalVLFs > 1000 THEN 'WARNING — excessive VLFs may slow restores'
        WHEN TotalVLFs > 500  THEN 'CAUTION — elevated VLF count'
        ELSE 'OK'
    END                                                 AS [Health]
FROM #VLFSummary
ORDER BY DatabaseName;
GO

-- ============================================
-- SECTION 4: OVERALL MIGRATION HEALTH SUMMARY
-- ============================================

PRINT '';
PRINT '================================================================';
PRINT ' SECTION 4: MIGRATION HEALTH SUMMARY';
PRINT '================================================================';
PRINT '';
GO

IF OBJECT_ID('tempdb..#HealthChecks') IS NOT NULL
    DROP TABLE #HealthChecks;

CREATE TABLE #HealthChecks (
    CheckID     INT IDENTITY(1,1),
    Category    NVARCHAR(50),
    CheckName   NVARCHAR(100),
    DatabaseName NVARCHAR(128),
    Status      NVARCHAR(20),
    Details     NVARCHAR(500)
);

-- Check: Recovery model
INSERT INTO #HealthChecks (Category, CheckName, DatabaseName, Status, Details)
SELECT
    'Configuration', 'Recovery Model', d.name,
    CASE WHEN d.recovery_model_desc = 'FULL' THEN 'PASS' ELSE 'FAIL' END,
    'Recovery model: ' + d.recovery_model_desc
FROM sys.databases d
WHERE d.name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

-- Check: Database online
INSERT INTO #HealthChecks (Category, CheckName, DatabaseName, Status, Details)
SELECT
    'Availability', 'Database Online', d.name,
    CASE WHEN d.state_desc = 'ONLINE' THEN 'PASS' ELSE 'FAIL' END,
    'State: ' + d.state_desc
FROM sys.databases d
WHERE d.name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

-- Check: Recent log backup (within 10 minutes)
INSERT INTO #HealthChecks (Category, CheckName, DatabaseName, Status, Details)
SELECT
    'Log Shipping', 'Recent Log Backup', d.name,
    CASE
        WHEN MAX(bs.backup_finish_date) >= DATEADD(MINUTE, -10, GETDATE()) THEN 'PASS'
        WHEN MAX(bs.backup_finish_date) >= DATEADD(MINUTE, -30, GETDATE()) THEN 'WARNING'
        WHEN MAX(bs.backup_finish_date) IS NULL THEN 'FAIL'
        ELSE 'FAIL'
    END,
    CASE
        WHEN MAX(bs.backup_finish_date) IS NOT NULL
        THEN 'Last log backup: ' + CONVERT(VARCHAR(30), MAX(bs.backup_finish_date), 120)
             + ' (' + CAST(DATEDIFF(MINUTE, MAX(bs.backup_finish_date), GETDATE()) AS VARCHAR(10))
             + ' min ago)'
        ELSE 'No log backups found'
    END
FROM sys.databases d
LEFT JOIN msdb.dbo.backupset bs
    ON bs.database_name = d.name AND bs.type = 'L'
WHERE d.name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
GROUP BY d.name;

-- Check: Log backup chain intact
INSERT INTO #HealthChecks (Category, CheckName, DatabaseName, Status, Details)
SELECT
    'Log Shipping', 'Backup Chain Intact', lc.database_name,
    CASE WHEN lc.chain_breaks = 0 THEN 'PASS' ELSE 'FAIL' END,
    CASE WHEN lc.chain_breaks = 0 THEN 'Log chain is continuous'
         ELSE CAST(lc.chain_breaks AS VARCHAR(10)) + ' chain break(s) detected — new full backup required'
    END
FROM (
    SELECT
        bs.database_name,
        SUM(CASE
            WHEN LAG(bs.last_lsn) OVER (PARTITION BY bs.database_name ORDER BY bs.backup_start_date) IS NOT NULL
                 AND bs.first_lsn <> LAG(bs.last_lsn) OVER (PARTITION BY bs.database_name ORDER BY bs.backup_start_date)
            THEN 1 ELSE 0 END) AS chain_breaks
    FROM msdb.dbo.backupset bs
    WHERE bs.database_name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
        AND bs.type = 'L'
        AND bs.backup_start_date >= DATEADD(DAY, -1, GETDATE())
    GROUP BY bs.database_name
) lc;

-- Check: Log space not critical
INSERT INTO #HealthChecks (Category, CheckName, DatabaseName, Status, Details)
SELECT
    'Resources', 'Log Space', ls.DatabaseName,
    CASE
        WHEN ls.LogUsedPct > 90 THEN 'FAIL'
        WHEN ls.LogUsedPct > 75 THEN 'WARNING'
        ELSE 'PASS'
    END,
    'Log used: ' + CAST(ls.LogUsedPct AS VARCHAR(10)) + '% of '
    + CAST(ls.LogSizeMB AS VARCHAR(20)) + ' MB'
FROM #LogSpace ls
WHERE ls.DatabaseName IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

-- Check: Log shipping job enabled
INSERT INTO #HealthChecks (Category, CheckName, DatabaseName, Status, Details)
SELECT
    'Agent Jobs', 'Log Shipping Job', '(all)',
    CASE WHEN j.enabled = 1 THEN 'PASS' ELSE 'FAIL' END,
    'Job [' + j.name + '] is ' + CASE j.enabled WHEN 1 THEN 'ENABLED' ELSE 'DISABLED' END
FROM msdb.dbo.sysjobs j
WHERE j.name LIKE N'%Lakeview%Migration%LogShipping%';

-- Display results
SELECT
    CheckID                                             AS [#],
    Category                                            AS [Category],
    CheckName                                           AS [Check],
    DatabaseName                                        AS [Database],
    Status                                              AS [Status],
    Details                                             AS [Details]
FROM #HealthChecks
ORDER BY
    CASE Status WHEN 'FAIL' THEN 1 WHEN 'WARNING' THEN 2 ELSE 3 END,
    Category, DatabaseName;
GO

-- Summary counts
PRINT '';
SELECT
    Status,
    COUNT(*) AS [Count]
FROM #HealthChecks
GROUP BY Status
ORDER BY CASE Status WHEN 'FAIL' THEN 1 WHEN 'WARNING' THEN 2 ELSE 3 END;
GO

DECLARE @FailCount INT = (SELECT COUNT(*) FROM #HealthChecks WHERE Status = 'FAIL');
DECLARE @WarnCount INT = (SELECT COUNT(*) FROM #HealthChecks WHERE Status = 'WARNING');

PRINT '';
IF @FailCount > 0
    PRINT '*** MIGRATION HEALTH: ' + CAST(@FailCount AS VARCHAR(5)) + ' FAILURE(s) detected. Investigate before cutover. ***';
ELSE IF @WarnCount > 0
    PRINT 'MIGRATION HEALTH: All checks passed with ' + CAST(@WarnCount AS VARCHAR(5)) + ' warning(s). Review before cutover.';
ELSE
    PRINT 'MIGRATION HEALTH: All checks PASSED. Migration is healthy.';
GO

PRINT '';
PRINT '================================================================';
PRINT ' Monitoring complete. Re-run periodically to track migration.';
PRINT ' For cutover readiness, ensure:';
PRINT '   1. All health checks PASS';
PRINT '   2. Log shipping latency < 5 minutes';
PRINT '   3. No long-running transactions on source';
PRINT '   4. Databases on MI are in RESTORING state';
PRINT '================================================================';
GO
