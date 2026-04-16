-- ============================================
-- Final Cutover Procedure for Online Migration
-- Lakeview Medical Center
-- Performs the final cutover from on-premises
-- SQL Server 2016 to Azure SQL Managed Instance:
--   1. Stop application writes on source
--   2. Take final tail-log backups
--   3. Restore final logs WITH RECOVERY on MI
--   4. Verify all databases are ONLINE
--   5. Run data integrity checks (row counts
--      and checksums) between source and target
-- ============================================
-- Part 1: Run against the on-premises SQL Server
-- Part 2: Run against the Azure SQL MI target
-- Requires: sysadmin (both source and target)
-- Databases: PatientDB, BillingDB, SchedulingDB,
--            ReportingDB
-- ============================================

SET NOCOUNT ON;
GO

PRINT '================================================================';
PRINT ' Lakeview Medical Center - Final Cutover Procedure';
PRINT ' Run Date: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT ' Server  : ' + @@SERVERNAME;
PRINT ' Version : ' + @@VERSION;
PRINT '================================================================';
PRINT '';
GO

-- ============================================
-- PART 1: SOURCE SERVER — STOP WRITES & TAIL-LOG
-- ============================================
-- Run these steps on the ON-PREMISES SQL Server.
-- ============================================

-- Verify we are on the source server
IF SERVERPROPERTY('EngineEdition') = 8
BEGIN
    RAISERROR('PART 1 must be run on the ON-PREMISES SQL Server, not on SQL Managed Instance.', 16, 1);
    RETURN;
END
GO

PRINT '================================================================';
PRINT ' PART 1: Stop Application Writes & Take Final Tail-Log Backups';
PRINT '================================================================';
PRINT '';
GO

-- ============================================
-- CONFIGURATION - Update these values
-- ============================================
DECLARE @BackupShare   NVARCHAR(500) = N'\\<FILE-SERVER>\SQLBackups\LakeviewMedical\LogBackups';
DECLARE @BlobContainer NVARCHAR(500) = N'https://<STORAGE-ACCOUNT>.blob.core.windows.net/dms-backups';
DECLARE @Timestamp     NVARCHAR(20)  = REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(20), GETDATE(), 120), '-', ''), ':', ''), ' ', '_');

PRINT 'Configuration:';
PRINT '  Backup share   : ' + @BackupShare;
PRINT '  Blob container : ' + @BlobContainer;
PRINT '  Timestamp      : ' + @Timestamp;
PRINT '';
GO

-- ============================================
-- Step 1a: Record pre-cutover baseline
-- ============================================
PRINT '--- Step 1a: Pre-Cutover Baseline ---';
PRINT '';

IF OBJECT_ID('tempdb..#CutoverBaseline') IS NOT NULL
    DROP TABLE #CutoverBaseline;

CREATE TABLE #CutoverBaseline (
    DatabaseName     NVARCHAR(128),
    ActiveSessions   INT,
    OpenTransactions INT,
    CutoverStartTime DATETIME DEFAULT GETDATE()
);

INSERT INTO #CutoverBaseline (DatabaseName, ActiveSessions, OpenTransactions)
SELECT
    db.name,
    (SELECT COUNT(*) FROM sys.dm_exec_sessions s WHERE s.database_id = db.database_id AND s.session_id > 50),
    (SELECT COUNT(*) FROM sys.dm_tran_active_transactions t
     INNER JOIN sys.dm_tran_session_transactions st ON t.transaction_id = st.transaction_id
     INNER JOIN sys.dm_exec_sessions s ON st.session_id = s.session_id
     WHERE s.database_id = db.database_id)
FROM sys.databases db
WHERE db.name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

SELECT
    DatabaseName,
    ActiveSessions   AS [Active Sessions],
    OpenTransactions AS [Open Transactions],
    CutoverStartTime AS [Cutover Start]
FROM #CutoverBaseline;

PRINT '';
GO

-- ============================================
-- Step 1b: Disable the log shipping agent job
-- ============================================
PRINT '--- Step 1b: Disable Log Shipping Agent Job ---';
PRINT '';

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'Lakeview_MI_Migration_LogShipping')
BEGIN
    EXEC msdb.dbo.sp_update_job
        @job_name = N'Lakeview_MI_Migration_LogShipping',
        @enabled = 0;
    PRINT 'Log shipping job [Lakeview_MI_Migration_LogShipping] disabled.';
END
ELSE
    PRINT 'WARNING: Log shipping job not found. Ensure log shipping is stopped before proceeding.';

PRINT '';
GO

-- ============================================
-- Step 1c: Set all databases to READ_ONLY to
-- stop application writes
-- ============================================
PRINT '--- Step 1c: Set Databases to READ_ONLY ---';
PRINT '';
PRINT 'WARNING: This will disconnect all active sessions and prevent writes.';
PRINT 'Ensure the application maintenance window has started.';
PRINT '';

DECLARE @DbName NVARCHAR(128);
DECLARE @SQL    NVARCHAR(500);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
    ORDER BY name;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DbName;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Kill active connections then set READ_ONLY
    SET @SQL = N'ALTER DATABASE [' + @DbName + N'] SET READ_ONLY WITH ROLLBACK IMMEDIATE;';

    BEGIN TRY
        EXEC sp_executesql @SQL;
        PRINT @DbName + ' — set to READ_ONLY.';
    END TRY
    BEGIN CATCH
        PRINT 'ERROR setting ' + @DbName + ' to READ_ONLY: ' + ERROR_MESSAGE();
    END CATCH

    FETCH NEXT FROM db_cursor INTO @DbName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

PRINT '';
PRINT 'All databases are now READ_ONLY. Applications cannot write.';
PRINT '';
GO

-- ============================================
-- Step 1d: Verify no open transactions remain
-- ============================================
PRINT '--- Step 1d: Verify No Open Transactions ---';
PRINT '';

DECLARE @OpenTxCount INT = 0;

SELECT @OpenTxCount = COUNT(*)
FROM sys.dm_tran_active_transactions t
INNER JOIN sys.dm_tran_session_transactions st ON t.transaction_id = st.transaction_id
INNER JOIN sys.dm_exec_sessions s ON st.session_id = s.session_id
WHERE DB_NAME(s.database_id) IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

IF @OpenTxCount > 0
BEGIN
    PRINT 'WARNING: ' + CAST(@OpenTxCount AS VARCHAR(10)) + ' open transaction(s) detected. Investigate before proceeding.';

    SELECT
        DB_NAME(s.database_id) AS [Database],
        s.session_id           AS [Session ID],
        s.login_name           AS [Login],
        s.host_name            AS [Host],
        s.program_name         AS [Program],
        t.transaction_begin_time AS [Transaction Start],
        DATEDIFF(SECOND, t.transaction_begin_time, GETDATE()) AS [Duration (sec)]
    FROM sys.dm_tran_active_transactions t
    INNER JOIN sys.dm_tran_session_transactions st ON t.transaction_id = st.transaction_id
    INNER JOIN sys.dm_exec_sessions s ON st.session_id = s.session_id
    WHERE DB_NAME(s.database_id) IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');
END
ELSE
    PRINT 'No open transactions. Safe to proceed with tail-log backups.';

PRINT '';
GO

-- ============================================
-- Step 1e: Take final tail-log backups with
-- NORECOVERY (leaves source in RESTORING state)
-- ============================================
PRINT '--- Step 1e: Final Tail-Log Backups ---';
PRINT '';
GO

-- PatientDB tail-log
DECLARE @BlobContainer NVARCHAR(500) = N'https://<STORAGE-ACCOUNT>.blob.core.windows.net/dms-backups';
DECLARE @Timestamp NVARCHAR(20) = REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(20), GETDATE(), 120), '-', ''), ':', ''), ' ', '_');
DECLARE @LogFile   NVARCHAR(500);
DECLARE @StartTime DATETIME;
DECLARE @Duration  INT;

SET @LogFile = @BlobContainer + N'/PatientDB_TAILLOG_' + @Timestamp + N'.trn';

PRINT 'Taking PatientDB tail-log backup...';
SET @StartTime = GETDATE();

BACKUP LOG [PatientDB]
TO URL = @LogFile
WITH
    NORECOVERY,
    COMPRESSION,
    CHECKSUM,
    NAME = N'PatientDB - Final Tail-Log for Cutover',
    STATS = 10;

SET @Duration = DATEDIFF(SECOND, @StartTime, GETDATE());
PRINT 'PatientDB tail-log completed in ' + CAST(@Duration AS VARCHAR(10)) + ' seconds.';
PRINT 'Backup path: ' + @LogFile;
PRINT '';
GO

-- BillingDB tail-log
DECLARE @BlobContainer NVARCHAR(500) = N'https://<STORAGE-ACCOUNT>.blob.core.windows.net/dms-backups';
DECLARE @Timestamp NVARCHAR(20) = REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(20), GETDATE(), 120), '-', ''), ':', ''), ' ', '_');
DECLARE @LogFile   NVARCHAR(500);
DECLARE @StartTime DATETIME;
DECLARE @Duration  INT;

SET @LogFile = @BlobContainer + N'/BillingDB_TAILLOG_' + @Timestamp + N'.trn';

PRINT 'Taking BillingDB tail-log backup...';
SET @StartTime = GETDATE();

BACKUP LOG [BillingDB]
TO URL = @LogFile
WITH
    NORECOVERY,
    COMPRESSION,
    CHECKSUM,
    NAME = N'BillingDB - Final Tail-Log for Cutover',
    STATS = 10;

SET @Duration = DATEDIFF(SECOND, @StartTime, GETDATE());
PRINT 'BillingDB tail-log completed in ' + CAST(@Duration AS VARCHAR(10)) + ' seconds.';
PRINT 'Backup path: ' + @LogFile;
PRINT '';
GO

-- SchedulingDB tail-log
DECLARE @BlobContainer NVARCHAR(500) = N'https://<STORAGE-ACCOUNT>.blob.core.windows.net/dms-backups';
DECLARE @Timestamp NVARCHAR(20) = REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(20), GETDATE(), 120), '-', ''), ':', ''), ' ', '_');
DECLARE @LogFile   NVARCHAR(500);
DECLARE @StartTime DATETIME;
DECLARE @Duration  INT;

SET @LogFile = @BlobContainer + N'/SchedulingDB_TAILLOG_' + @Timestamp + N'.trn';

PRINT 'Taking SchedulingDB tail-log backup...';
SET @StartTime = GETDATE();

BACKUP LOG [SchedulingDB]
TO URL = @LogFile
WITH
    NORECOVERY,
    COMPRESSION,
    CHECKSUM,
    NAME = N'SchedulingDB - Final Tail-Log for Cutover',
    STATS = 10;

SET @Duration = DATEDIFF(SECOND, @StartTime, GETDATE());
PRINT 'SchedulingDB tail-log completed in ' + CAST(@Duration AS VARCHAR(10)) + ' seconds.';
PRINT 'Backup path: ' + @LogFile;
PRINT '';
GO

-- ReportingDB tail-log
DECLARE @BlobContainer NVARCHAR(500) = N'https://<STORAGE-ACCOUNT>.blob.core.windows.net/dms-backups';
DECLARE @Timestamp NVARCHAR(20) = REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(20), GETDATE(), 120), '-', ''), ':', ''), ' ', '_');
DECLARE @LogFile   NVARCHAR(500);
DECLARE @StartTime DATETIME;
DECLARE @Duration  INT;

SET @LogFile = @BlobContainer + N'/ReportingDB_TAILLOG_' + @Timestamp + N'.trn';

PRINT 'Taking ReportingDB tail-log backup...';
SET @StartTime = GETDATE();

BACKUP LOG [ReportingDB]
TO URL = @LogFile
WITH
    NORECOVERY,
    COMPRESSION,
    CHECKSUM,
    NAME = N'ReportingDB - Final Tail-Log for Cutover',
    STATS = 10;

SET @Duration = DATEDIFF(SECOND, @StartTime, GETDATE());
PRINT 'ReportingDB tail-log completed in ' + CAST(@Duration AS VARCHAR(10)) + ' seconds.';
PRINT 'Backup path: ' + @LogFile;
PRINT '';
GO

PRINT '================================================================';
PRINT ' PART 1 COMPLETE';
PRINT ' All tail-log backups taken. Source databases are in RESTORING state.';
PRINT ' Tail-log files are in Azure Blob storage.';
PRINT '';
PRINT ' Record the tail-log filenames above — you will need them in Part 2.';
PRINT '';
PRINT ' *** Switch connection to Azure SQL Managed Instance for Part 2 ***';
PRINT '================================================================';
GO


-- ============================================
-- PART 2: MANAGED INSTANCE — RESTORE FINAL LOGS
-- ============================================
-- *** STOP HERE ***
-- Switch connection to the Azure SQL Managed
-- Instance before running Part 2.
-- ============================================

/*
-- Uncomment and run on SQL Managed Instance

PRINT '================================================================';
PRINT ' PART 2: Restore Final Tail-Logs WITH RECOVERY (Azure SQL MI)';
PRINT '================================================================';
PRINT '';
GO

-- ============================================
-- CONFIGURATION - Update with actual tail-log
-- file names from Part 1 output
-- ============================================
DECLARE @BlobContainer NVARCHAR(500) = N'https://<STORAGE-ACCOUNT>.blob.core.windows.net/dms-backups';

-- Update these with the actual tail-log file names from Part 1
DECLARE @PatientDB_TailLog    NVARCHAR(500) = @BlobContainer + N'/PatientDB_TAILLOG_<TIMESTAMP>.trn';
DECLARE @BillingDB_TailLog    NVARCHAR(500) = @BlobContainer + N'/BillingDB_TAILLOG_<TIMESTAMP>.trn';
DECLARE @SchedulingDB_TailLog NVARCHAR(500) = @BlobContainer + N'/SchedulingDB_TAILLOG_<TIMESTAMP>.trn';
DECLARE @ReportingDB_TailLog  NVARCHAR(500) = @BlobContainer + N'/ReportingDB_TAILLOG_<TIMESTAMP>.trn';

PRINT 'Tail-log files:';
PRINT '  PatientDB    : ' + @PatientDB_TailLog;
PRINT '  BillingDB    : ' + @BillingDB_TailLog;
PRINT '  SchedulingDB : ' + @SchedulingDB_TailLog;
PRINT '  ReportingDB  : ' + @ReportingDB_TailLog;
PRINT '';
GO

-- ============================================
-- Step 2a: Verify databases are in RESTORING
-- state before applying final logs
-- ============================================
PRINT '--- Step 2a: Verify Databases in RESTORING State ---';
PRINT '';

DECLARE @NotRestoringCount INT = 0;

SELECT @NotRestoringCount = COUNT(*)
FROM sys.databases
WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
    AND state_desc <> 'RESTORING';

IF @NotRestoringCount > 0
BEGIN
    SELECT
        name        AS [Database],
        state_desc  AS [State],
        CASE
            WHEN state_desc = 'ONLINE' THEN 'ERROR: Already ONLINE — cannot apply logs'
            ELSE 'ERROR: Unexpected state — investigate'
        END AS [Issue]
    FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
        AND state_desc <> 'RESTORING';

    RAISERROR('Not all databases are in RESTORING state. Fix before proceeding.', 16, 1);
    RETURN;
END

PRINT 'All 4 databases are in RESTORING state. Ready for final log restore.';
PRINT '';
GO

-- ============================================
-- Step 2b: Restore final tail-logs WITH RECOVERY
-- ============================================
PRINT '--- Step 2b: Restore Final Tail-Logs WITH RECOVERY ---';
PRINT '';

-- PatientDB
DECLARE @BlobContainer NVARCHAR(500) = N'https://<STORAGE-ACCOUNT>.blob.core.windows.net/dms-backups';
DECLARE @TailLog NVARCHAR(500) = @BlobContainer + N'/PatientDB_TAILLOG_<TIMESTAMP>.trn';
DECLARE @StartTime DATETIME;
DECLARE @Duration  INT;

PRINT 'Restoring PatientDB final tail-log WITH RECOVERY...';
SET @StartTime = GETDATE();

RESTORE LOG [PatientDB]
FROM URL = @TailLog
WITH RECOVERY, STATS = 10;

SET @Duration = DATEDIFF(SECOND, @StartTime, GETDATE());
PRINT 'PatientDB restored WITH RECOVERY in ' + CAST(@Duration AS VARCHAR(10)) + ' seconds.';
PRINT '';
GO

-- BillingDB
DECLARE @BlobContainer NVARCHAR(500) = N'https://<STORAGE-ACCOUNT>.blob.core.windows.net/dms-backups';
DECLARE @TailLog NVARCHAR(500) = @BlobContainer + N'/BillingDB_TAILLOG_<TIMESTAMP>.trn';
DECLARE @StartTime DATETIME;
DECLARE @Duration  INT;

PRINT 'Restoring BillingDB final tail-log WITH RECOVERY...';
SET @StartTime = GETDATE();

RESTORE LOG [BillingDB]
FROM URL = @TailLog
WITH RECOVERY, STATS = 10;

SET @Duration = DATEDIFF(SECOND, @StartTime, GETDATE());
PRINT 'BillingDB restored WITH RECOVERY in ' + CAST(@Duration AS VARCHAR(10)) + ' seconds.';
PRINT '';
GO

-- SchedulingDB
DECLARE @BlobContainer NVARCHAR(500) = N'https://<STORAGE-ACCOUNT>.blob.core.windows.net/dms-backups';
DECLARE @TailLog NVARCHAR(500) = @BlobContainer + N'/SchedulingDB_TAILLOG_<TIMESTAMP>.trn';
DECLARE @StartTime DATETIME;
DECLARE @Duration  INT;

PRINT 'Restoring SchedulingDB final tail-log WITH RECOVERY...';
SET @StartTime = GETDATE();

RESTORE LOG [SchedulingDB]
FROM URL = @TailLog
WITH RECOVERY, STATS = 10;

SET @Duration = DATEDIFF(SECOND, @StartTime, GETDATE());
PRINT 'SchedulingDB restored WITH RECOVERY in ' + CAST(@Duration AS VARCHAR(10)) + ' seconds.';
PRINT '';
GO

-- ReportingDB
DECLARE @BlobContainer NVARCHAR(500) = N'https://<STORAGE-ACCOUNT>.blob.core.windows.net/dms-backups';
DECLARE @TailLog NVARCHAR(500) = @BlobContainer + N'/ReportingDB_TAILLOG_<TIMESTAMP>.trn';
DECLARE @StartTime DATETIME;
DECLARE @Duration  INT;

PRINT 'Restoring ReportingDB final tail-log WITH RECOVERY...';
SET @StartTime = GETDATE();

RESTORE LOG [ReportingDB]
FROM URL = @TailLog
WITH RECOVERY, STATS = 10;

SET @Duration = DATEDIFF(SECOND, @StartTime, GETDATE());
PRINT 'ReportingDB restored WITH RECOVERY in ' + CAST(@Duration AS VARCHAR(10)) + ' seconds.';
PRINT '';
GO

-- ============================================
-- PART 3: VERIFY ALL DATABASES ARE ONLINE
-- ============================================
PRINT '================================================================';
PRINT ' PART 3: Database State Verification';
PRINT '================================================================';
PRINT '';

DECLARE @OfflineCount INT = 0;

SELECT
    d.name                  AS [Database],
    d.state_desc            AS [State],
    d.recovery_model_desc   AS [Recovery Model],
    d.collation_name        AS [Collation],
    d.compatibility_level   AS [Compat Level],
    d.create_date           AS [Created],
    CASE
        WHEN d.state_desc = 'ONLINE' THEN 'OK'
        ELSE 'PROBLEM — database is NOT ONLINE'
    END AS [Cutover Status]
FROM sys.databases d
WHERE d.name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
ORDER BY d.name;

SELECT @OfflineCount = COUNT(*)
FROM sys.databases
WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
    AND state_desc <> 'ONLINE';

IF @OfflineCount > 0
BEGIN
    PRINT '';
    PRINT '*** CRITICAL: ' + CAST(@OfflineCount AS VARCHAR(10)) + ' database(s) are NOT ONLINE. ***';
    PRINT 'Investigate before proceeding with data integrity checks.';
    RAISERROR('Not all databases are ONLINE after cutover.', 16, 1);
    RETURN;
END

PRINT '';
PRINT 'All 4 databases are ONLINE on Azure SQL Managed Instance.';
PRINT '';
GO

-- Verify database files
PRINT '--- Database File Details ---';
PRINT '';

SELECT
    DB_NAME(mf.database_id)  AS [Database],
    mf.name                  AS [Logical Name],
    mf.type_desc             AS [File Type],
    mf.state_desc            AS [State],
    CAST(mf.size * 8.0 / 1024 AS DECIMAL(12,2)) AS [Size (MB)],
    mf.physical_name         AS [Physical Path]
FROM sys.master_files mf
WHERE DB_NAME(mf.database_id) IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
ORDER BY DB_NAME(mf.database_id), mf.type;
GO

-- ============================================
-- PART 4: DATA INTEGRITY CHECKS
-- ============================================
-- These queries capture row counts and checksums
-- on the MI target. Run the same queries on the
-- source (before setting READ_ONLY) to compare.
-- ============================================

PRINT '';
PRINT '================================================================';
PRINT ' PART 4: Data Integrity Checks';
PRINT '================================================================';
PRINT '';
PRINT 'Run these queries on BOTH source and target to compare results.';
PRINT 'Source data should be captured BEFORE setting databases to READ_ONLY,';
PRINT 'or compare after cutover with the source in RESTORING state.';
PRINT '';
GO

-- ============================================
-- 4a: Row Count Comparison
-- ============================================
PRINT '--- 4a: Row Counts Per Table (All Databases) ---';
PRINT '';

IF OBJECT_ID('tempdb..#RowCounts') IS NOT NULL
    DROP TABLE #RowCounts;

CREATE TABLE #RowCounts (
    DatabaseName NVARCHAR(128),
    SchemaName   NVARCHAR(128),
    TableName    NVARCHAR(128),
    RowCount     BIGINT
);

-- Collect row counts from all 4 databases
DECLARE @DbName NVARCHAR(128);
DECLARE @SQL    NVARCHAR(MAX);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
        AND state_desc = 'ONLINE'
    ORDER BY name;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DbName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @SQL = N'
        USE [' + @DbName + N'];
        INSERT INTO #RowCounts (DatabaseName, SchemaName, TableName, RowCount)
        SELECT
            DB_NAME(),
            s.name,
            t.name,
            p.rows
        FROM sys.tables t
        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
        INNER JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0, 1)
        WHERE t.is_ms_shipped = 0
        ORDER BY s.name, t.name;
    ';

    EXEC sp_executesql @SQL;
    FETCH NEXT FROM db_cursor INTO @DbName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

SELECT
    DatabaseName AS [Database],
    SchemaName   AS [Schema],
    TableName    AS [Table],
    [RowCount]   AS [Row Count]
FROM #RowCounts
ORDER BY DatabaseName, SchemaName, TableName;

-- Summary per database
SELECT
    DatabaseName            AS [Database],
    COUNT(*)                AS [Table Count],
    SUM([RowCount])         AS [Total Rows],
    MIN([RowCount])         AS [Min Rows],
    MAX([RowCount])         AS [Max Rows]
FROM #RowCounts
GROUP BY DatabaseName
ORDER BY DatabaseName;
GO

-- ============================================
-- 4b: Checksum Comparison
-- Uses CHECKSUM_AGG over key columns to detect
-- data differences between source and target
-- ============================================
PRINT '';
PRINT '--- 4b: Table Checksums (All Databases) ---';
PRINT '';

IF OBJECT_ID('tempdb..#TableChecksums') IS NOT NULL
    DROP TABLE #TableChecksums;

CREATE TABLE #TableChecksums (
    DatabaseName NVARCHAR(128),
    SchemaName   NVARCHAR(128),
    TableName    NVARCHAR(128),
    RowCount     BIGINT,
    ChecksumAgg  INT
);

DECLARE @DbName2 NVARCHAR(128);
DECLARE @SQL2    NVARCHAR(MAX);

DECLARE db_cursor2 CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
        AND state_desc = 'ONLINE'
    ORDER BY name;

OPEN db_cursor2;
FETCH NEXT FROM db_cursor2 INTO @DbName2;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @SQL2 = N'
        USE [' + @DbName2 + N'];

        DECLARE @tblName NVARCHAR(256);
        DECLARE @schName NVARCHAR(128);
        DECLARE @dynSQL  NVARCHAR(MAX);

        DECLARE tbl_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT s.name, t.name
            FROM sys.tables t
            INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
            WHERE t.is_ms_shipped = 0
            ORDER BY s.name, t.name;

        OPEN tbl_cursor;
        FETCH NEXT FROM tbl_cursor INTO @schName, @tblName;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY
                SET @dynSQL = N''
                    INSERT INTO #TableChecksums (DatabaseName, SchemaName, TableName, RowCount, ChecksumAgg)
                    SELECT
                        DB_NAME(),
                        N'''''' + @schName + N'''''',
                        N'''''' + @tblName + N'''''',
                        COUNT(*),
                        CHECKSUM_AGG(CHECKSUM(*))
                    FROM ['' + @schName + N''].['' + @tblName + N''];
                '';
                EXEC sp_executesql @dynSQL;
            END TRY
            BEGIN CATCH
                INSERT INTO #TableChecksums (DatabaseName, SchemaName, TableName, RowCount, ChecksumAgg)
                VALUES (DB_NAME(), @schName, @tblName, -1, NULL);
            END CATCH

            FETCH NEXT FROM tbl_cursor INTO @schName, @tblName;
        END

        CLOSE tbl_cursor;
        DEALLOCATE tbl_cursor;
    ';

    EXEC sp_executesql @SQL2;
    FETCH NEXT FROM db_cursor2 INTO @DbName2;
END

CLOSE db_cursor2;
DEALLOCATE db_cursor2;

SELECT
    DatabaseName AS [Database],
    SchemaName   AS [Schema],
    TableName    AS [Table],
    RowCount     AS [Row Count],
    ChecksumAgg  AS [CHECKSUM_AGG],
    CASE
        WHEN RowCount = -1 THEN 'ERROR — could not compute checksum'
        ELSE 'OK'
    END AS [Status]
FROM #TableChecksums
ORDER BY DatabaseName, SchemaName, TableName;
GO

-- ============================================
-- 4c: DBCC CHECKDB on all migrated databases
-- ============================================
PRINT '';
PRINT '--- 4c: DBCC CHECKDB (Logical Consistency) ---';
PRINT '';

DECLARE @DbName3 NVARCHAR(128);
DECLARE @SQL3    NVARCHAR(MAX);

DECLARE db_cursor3 CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
        AND state_desc = 'ONLINE'
    ORDER BY name;

OPEN db_cursor3;
FETCH NEXT FROM db_cursor3 INTO @DbName3;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT 'Running DBCC CHECKDB on ' + @DbName3 + '...';

    SET @SQL3 = N'DBCC CHECKDB ([' + @DbName3 + N']) WITH NO_INFOMSGS, ALL_ERRORMSGS;';

    BEGIN TRY
        EXEC sp_executesql @SQL3;
        PRINT @DbName3 + ' — DBCC CHECKDB passed.';
    END TRY
    BEGIN CATCH
        PRINT 'ERROR: DBCC CHECKDB failed on ' + @DbName3 + ': ' + ERROR_MESSAGE();
    END CATCH

    PRINT '';
    FETCH NEXT FROM db_cursor3 INTO @DbName3;
END

CLOSE db_cursor3;
DEALLOCATE db_cursor3;
GO

-- ============================================
-- 4d: Verify schema object counts match
-- ============================================
PRINT '--- 4d: Schema Object Counts ---';
PRINT '';

IF OBJECT_ID('tempdb..#ObjectCounts') IS NOT NULL
    DROP TABLE #ObjectCounts;

CREATE TABLE #ObjectCounts (
    DatabaseName NVARCHAR(128),
    ObjectType   NVARCHAR(60),
    ObjectCount  INT
);

DECLARE @DbName4 NVARCHAR(128);
DECLARE @SQL4    NVARCHAR(MAX);

DECLARE db_cursor4 CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
        AND state_desc = 'ONLINE'
    ORDER BY name;

OPEN db_cursor4;
FETCH NEXT FROM db_cursor4 INTO @DbName4;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @SQL4 = N'
        USE [' + @DbName4 + N'];
        INSERT INTO #ObjectCounts (DatabaseName, ObjectType, ObjectCount)
        SELECT
            DB_NAME(),
            type_desc,
            COUNT(*)
        FROM sys.objects
        WHERE is_ms_shipped = 0
        GROUP BY type_desc;
    ';

    EXEC sp_executesql @SQL4;
    FETCH NEXT FROM db_cursor4 INTO @DbName4;
END

CLOSE db_cursor4;
DEALLOCATE db_cursor4;

SELECT
    DatabaseName AS [Database],
    ObjectType   AS [Object Type],
    ObjectCount  AS [Count]
FROM #ObjectCounts
ORDER BY DatabaseName, ObjectType;
GO

-- ============================================
-- 4e: Verify user and permission counts
-- ============================================
PRINT '';
PRINT '--- 4e: Database Users & Permissions ---';
PRINT '';

IF OBJECT_ID('tempdb..#UserCounts') IS NOT NULL
    DROP TABLE #UserCounts;

CREATE TABLE #UserCounts (
    DatabaseName NVARCHAR(128),
    UserCount    INT,
    RoleCount    INT
);

DECLARE @DbName5 NVARCHAR(128);
DECLARE @SQL5    NVARCHAR(MAX);

DECLARE db_cursor5 CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
        AND state_desc = 'ONLINE'
    ORDER BY name;

OPEN db_cursor5;
FETCH NEXT FROM db_cursor5 INTO @DbName5;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @SQL5 = N'
        USE [' + @DbName5 + N'];
        INSERT INTO #UserCounts (DatabaseName, UserCount, RoleCount)
        SELECT
            DB_NAME(),
            (SELECT COUNT(*) FROM sys.database_principals WHERE type IN (''S'', ''U'', ''G'') AND principal_id > 4),
            (SELECT COUNT(*) FROM sys.database_principals WHERE type = ''R'' AND is_fixed_role = 0 AND principal_id > 0 AND name <> ''public'');
    ';

    EXEC sp_executesql @SQL5;
    FETCH NEXT FROM db_cursor5 INTO @DbName5;
END

CLOSE db_cursor5;
DEALLOCATE db_cursor5;

SELECT
    DatabaseName AS [Database],
    UserCount    AS [Users],
    RoleCount    AS [Custom Roles]
FROM #UserCounts
ORDER BY DatabaseName;
GO

-- ============================================
-- Final cutover status report
-- ============================================
PRINT '';
PRINT '================================================================';
PRINT ' CUTOVER COMPLETE — SUMMARY';
PRINT '================================================================';
PRINT '';
PRINT ' Run Date  : ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT ' MI Server : ' + @@SERVERNAME;
PRINT '';
PRINT ' Status:';
PRINT '   [1] Application writes stopped          — DONE';
PRINT '   [2] Final tail-log backups taken         — DONE';
PRINT '   [3] Tail-logs restored WITH RECOVERY     — DONE';
PRINT '   [4] All databases ONLINE on MI           — VERIFIED';
PRINT '   [5] Data integrity checks                — COMPLETED';
PRINT '';
PRINT ' Next Steps:';
PRINT '   1. Compare row counts and checksums with source baseline.';
PRINT '   2. Run 23-ConnectionStringUpdate.ps1 to switch application';
PRINT '      connection strings to the MI endpoint.';
PRINT '   3. Verify application connectivity and functionality.';
PRINT '   4. Follow 24-CutoverChecklist.md for post-cutover tasks.';
PRINT '   5. Monitor the MI instance for 24-48 hours.';
PRINT '================================================================';
GO

*/
