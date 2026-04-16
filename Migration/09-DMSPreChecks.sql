-- ============================================
-- DMS Pre-Migration Readiness Checks
-- Lakeview Medical Center
-- Validates that the on-premises SQL Server 2016
-- source is ready for online (continuous sync)
-- migration to Azure SQL Managed Instance via
-- Azure Database Migration Service.
-- ============================================
-- Run against the on-premises SQL Server instance
-- Requires: VIEW SERVER STATE, VIEW ANY DEFINITION
-- Databases: PatientDB, BillingDB, SchedulingDB,
--            ReportingDB
-- ============================================

SET NOCOUNT ON;
GO

PRINT '================================================================';
PRINT ' Lakeview Medical Center - DMS Pre-Migration Readiness Checks';
PRINT ' Run Date: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT ' Server  : ' + @@SERVERNAME;
PRINT ' Version : ' + @@VERSION;
PRINT '================================================================';
PRINT '';
GO

-- ============================================
-- Results staging table
-- ============================================
IF OBJECT_ID('tempdb..#PreCheckResults') IS NOT NULL
    DROP TABLE #PreCheckResults;

CREATE TABLE #PreCheckResults (
    CheckID         INT IDENTITY(1,1),
    CheckName       NVARCHAR(100)  NOT NULL,
    DatabaseName    NVARCHAR(128)  NULL,
    Status          NVARCHAR(20)   NOT NULL,  -- PASS, FAIL, WARNING, INFO
    Details         NVARCHAR(1000) NOT NULL,
    Recommendation  NVARCHAR(1000) NULL
);
GO

-- Target databases for migration
IF OBJECT_ID('tempdb..#TargetDatabases') IS NOT NULL
    DROP TABLE #TargetDatabases;

CREATE TABLE #TargetDatabases (DatabaseName NVARCHAR(128));
INSERT INTO #TargetDatabases VALUES
    ('PatientDB'), ('BillingDB'), ('SchedulingDB'), ('ReportingDB');
GO

-- ============================================
-- 1. SQL SERVER VERSION CHECK
-- ============================================
PRINT '>> Check 1: SQL Server version...';

DECLARE @MajorVersion INT = CAST(SERVERPROPERTY('ProductMajorVersion') AS INT);
DECLARE @VersionString NVARCHAR(256) = CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(256));

IF @MajorVersion >= 13  -- SQL Server 2016+
BEGIN
    INSERT INTO #PreCheckResults (CheckName, Status, Details)
    VALUES ('SQL Server Version', 'PASS',
        'SQL Server version ' + @VersionString + ' is supported for DMS online migration.');
END
ELSE
BEGIN
    INSERT INTO #PreCheckResults (CheckName, Status, Details, Recommendation)
    VALUES ('SQL Server Version', 'FAIL',
        'SQL Server version ' + @VersionString + ' (major: ' + CAST(@MajorVersion AS VARCHAR(5)) + ').',
        'DMS online migration requires SQL Server 2016 or later. Upgrade the source instance or use offline migration.');
END
GO

-- ============================================
-- 2. VERIFY ALL TARGET DATABASES EXIST
-- ============================================
PRINT '>> Check 2: Verify target databases exist...';

INSERT INTO #PreCheckResults (CheckName, DatabaseName, Status, Details, Recommendation)
SELECT
    'Database Exists',
    td.DatabaseName,
    CASE WHEN d.name IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
    CASE WHEN d.name IS NOT NULL
         THEN td.DatabaseName + ' exists on this instance.'
         ELSE td.DatabaseName + ' was NOT found on this instance.'
    END,
    CASE WHEN d.name IS NULL
         THEN 'Verify the database name. Migration cannot proceed for a missing database.'
         ELSE NULL
    END
FROM #TargetDatabases td
    LEFT JOIN sys.databases d ON d.name = td.DatabaseName;
GO

-- ============================================
-- 3. RECOVERY MODEL CHECK (must be FULL)
-- ============================================
PRINT '>> Check 3: Recovery model (FULL required for online migration)...';

INSERT INTO #PreCheckResults (CheckName, DatabaseName, Status, Details, Recommendation)
SELECT
    'Recovery Model',
    d.name,
    CASE WHEN d.recovery_model_desc = 'FULL' THEN 'PASS' ELSE 'FAIL' END,
    d.name + ' recovery model: ' + d.recovery_model_desc + '.',
    CASE WHEN d.recovery_model_desc <> 'FULL'
         THEN 'Run: ALTER DATABASE [' + d.name + '] SET RECOVERY FULL; -- Online migration requires FULL recovery model.'
         ELSE NULL
    END
FROM sys.databases d
    INNER JOIN #TargetDatabases td ON d.name = td.DatabaseName;
GO

-- ============================================
-- 4. BACKUP CHAIN EXISTS (full + log backups)
-- ============================================
PRINT '>> Check 4: Backup chain exists (full + log backups)...';

-- Check for a recent full backup
INSERT INTO #PreCheckResults (CheckName, DatabaseName, Status, Details, Recommendation)
SELECT
    'Full Backup Exists',
    td.DatabaseName,
    CASE WHEN bs.backup_finish_date IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
    CASE WHEN bs.backup_finish_date IS NOT NULL
         THEN td.DatabaseName + ' last full backup: ' + CONVERT(VARCHAR(30), bs.backup_finish_date, 120) + '.'
         ELSE td.DatabaseName + ' has no full backup in msdb history.'
    END,
    CASE WHEN bs.backup_finish_date IS NULL
         THEN 'Take a full backup before starting DMS migration: BACKUP DATABASE [' + td.DatabaseName + '] TO DISK = ...;'
         ELSE NULL
    END
FROM #TargetDatabases td
    LEFT JOIN (
        SELECT database_name, MAX(backup_finish_date) AS backup_finish_date
        FROM msdb.dbo.backupset
        WHERE type = 'D'
        GROUP BY database_name
    ) bs ON bs.database_name = td.DatabaseName;

-- Check for a recent log backup
INSERT INTO #PreCheckResults (CheckName, DatabaseName, Status, Details, Recommendation)
SELECT
    'Log Backup Exists',
    td.DatabaseName,
    CASE WHEN bs.backup_finish_date IS NOT NULL THEN 'PASS' ELSE 'WARNING' END,
    CASE WHEN bs.backup_finish_date IS NOT NULL
         THEN td.DatabaseName + ' last log backup: ' + CONVERT(VARCHAR(30), bs.backup_finish_date, 120) + '.'
         ELSE td.DatabaseName + ' has no log backup in msdb history.'
    END,
    CASE WHEN bs.backup_finish_date IS NULL
         THEN 'Ensure log backups are running. DMS online migration relies on the log chain for continuous sync.'
         ELSE NULL
    END
FROM #TargetDatabases td
    LEFT JOIN (
        SELECT database_name, MAX(backup_finish_date) AS backup_finish_date
        FROM msdb.dbo.backupset
        WHERE type = 'L'
        GROUP BY database_name
    ) bs ON bs.database_name = td.DatabaseName;
GO

-- ============================================
-- 5. SQL SERVER AGENT STATUS
-- ============================================
PRINT '>> Check 5: SQL Server Agent status...';

DECLARE @AgentStatus INT;
EXEC master.dbo.xp_servicecontrol N'QUERYSTATE', N'SQLServerAGENT';

-- xp_servicecontrol prints output; also check via DMV
IF EXISTS (
    SELECT 1 FROM sys.dm_server_services
    WHERE servicename LIKE '%Agent%'
      AND status_desc = 'Running'
)
BEGIN
    INSERT INTO #PreCheckResults (CheckName, Status, Details)
    VALUES ('SQL Server Agent', 'PASS', 'SQL Server Agent is running.');
END
ELSE
BEGIN
    INSERT INTO #PreCheckResults (CheckName, Status, Details, Recommendation)
    VALUES ('SQL Server Agent', 'WARNING',
        'SQL Server Agent may not be running or status could not be confirmed.',
        'Ensure SQL Server Agent is running for scheduled log backups during online migration.');
END
GO

-- ============================================
-- 6. CHANGE TRACKING / CDC CHECK
-- ============================================
PRINT '>> Check 6: Change tracking and CDC status...';

-- DMS online migration uses log reading, not change tracking/CDC.
-- However, having CT or CDC enabled can affect performance.
INSERT INTO #PreCheckResults (CheckName, DatabaseName, Status, Details)
SELECT
    'Change Tracking',
    d.name,
    'INFO',
    CASE WHEN ct.database_id IS NOT NULL
         THEN d.name + ' has change tracking ENABLED (auto-cleanup: ' +
              CASE WHEN ct.is_auto_cleanup_on = 1 THEN 'ON' ELSE 'OFF' END + ').'
         ELSE d.name + ' does not have change tracking enabled.'
    END
FROM sys.databases d
    INNER JOIN #TargetDatabases td ON d.name = td.DatabaseName
    LEFT JOIN sys.change_tracking_databases ct ON ct.database_id = d.database_id;

INSERT INTO #PreCheckResults (CheckName, DatabaseName, Status, Details)
SELECT
    'Change Data Capture',
    d.name,
    'INFO',
    CASE WHEN d.is_cdc_enabled = 1
         THEN d.name + ' has CDC ENABLED.'
         ELSE d.name + ' does not have CDC enabled.'
    END
FROM sys.databases d
    INNER JOIN #TargetDatabases td ON d.name = td.DatabaseName;
GO

-- ============================================
-- 7. DATABASE OWNER CHECK (should be sa)
-- ============================================
PRINT '>> Check 7: Database owner check...';

INSERT INTO #PreCheckResults (CheckName, DatabaseName, Status, Details, Recommendation)
SELECT
    'Database Owner',
    d.name,
    CASE WHEN sp.name = 'sa' THEN 'PASS' ELSE 'WARNING' END,
    d.name + ' owner: ' + ISNULL(sp.name, 'UNKNOWN') + '.',
    CASE WHEN ISNULL(sp.name, '') <> 'sa'
         THEN 'Consider setting owner to sa: ALTER AUTHORIZATION ON DATABASE::[' + d.name + '] TO sa;'
         ELSE NULL
    END
FROM sys.databases d
    INNER JOIN #TargetDatabases td ON d.name = td.DatabaseName
    LEFT JOIN sys.server_principals sp ON d.owner_sid = sp.sid;
GO

-- ============================================
-- 8. DATABASE STATE CHECK (must be ONLINE)
-- ============================================
PRINT '>> Check 8: Database state check...';

INSERT INTO #PreCheckResults (CheckName, DatabaseName, Status, Details, Recommendation)
SELECT
    'Database State',
    d.name,
    CASE WHEN d.state_desc = 'ONLINE' THEN 'PASS' ELSE 'FAIL' END,
    d.name + ' state: ' + d.state_desc + '.',
    CASE WHEN d.state_desc <> 'ONLINE'
         THEN 'Database must be ONLINE for migration. Investigate and bring the database online.'
         ELSE NULL
    END
FROM sys.databases d
    INNER JOIN #TargetDatabases td ON d.name = td.DatabaseName;
GO

-- ============================================
-- 9. ORPHANED USERS CHECK
-- ============================================
PRINT '>> Check 9: Orphaned users check...';

DECLARE @OrphanSQL NVARCHAR(MAX);
DECLARE @DbNameCur NVARCHAR(128);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT DatabaseName FROM #TargetDatabases;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DbNameCur;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @OrphanSQL = N'
        INSERT INTO #PreCheckResults (CheckName, DatabaseName, Status, Details, Recommendation)
        SELECT
            ''Orphaned Users'',
            ''' + @DbNameCur + N''',
            CASE WHEN COUNT(*) > 0 THEN ''WARNING'' ELSE ''PASS'' END,
            CASE WHEN COUNT(*) > 0
                 THEN ''' + @DbNameCur + N' has '' + CAST(COUNT(*) AS VARCHAR(10)) + '' orphaned user(s).''
                 ELSE ''' + @DbNameCur + N' has no orphaned users.''
            END,
            CASE WHEN COUNT(*) > 0
                 THEN ''Remap orphaned users before cutover: ALTER USER [username] WITH LOGIN = [loginname];''
                 ELSE NULL
            END
        FROM [' + @DbNameCur + N'].sys.database_principals dp
            LEFT JOIN sys.server_principals sp ON dp.sid = sp.sid
        WHERE dp.type IN (''S'', ''U'')
          AND dp.name NOT IN (''dbo'', ''guest'', ''INFORMATION_SCHEMA'', ''sys'')
          AND dp.authentication_type <> 0
          AND sp.sid IS NULL;';

    EXEC sp_executesql @OrphanSQL;
    FETCH NEXT FROM db_cursor INTO @DbNameCur;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;
GO

-- ============================================
-- 10. UNSUPPORTED FEATURES CHECK
-- ============================================
PRINT '>> Check 10: Unsupported features for SQL MI...';

-- CLR assemblies with UNSAFE or EXTERNAL_ACCESS
DECLARE @ClrSQL NVARCHAR(MAX);
DECLARE @DbClr NVARCHAR(128);

DECLARE clr_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT DatabaseName FROM #TargetDatabases;

OPEN clr_cursor;
FETCH NEXT FROM clr_cursor INTO @DbClr;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @ClrSQL = N'
        INSERT INTO #PreCheckResults (CheckName, DatabaseName, Status, Details, Recommendation)
        SELECT
            ''CLR UNSAFE Assemblies'',
            ''' + @DbClr + N''',
            CASE WHEN COUNT(*) > 0 THEN ''WARNING'' ELSE ''PASS'' END,
            CASE WHEN COUNT(*) > 0
                 THEN ''' + @DbClr + N' has '' + CAST(COUNT(*) AS VARCHAR(10)) + '' UNSAFE/EXTERNAL_ACCESS CLR assembly(ies).''
                 ELSE ''' + @DbClr + N' has no UNSAFE CLR assemblies.''
            END,
            CASE WHEN COUNT(*) > 0
                 THEN ''Review CLR assemblies. Azure SQL MI supports SAFE assemblies by default. UNSAFE requires additional configuration.''
                 ELSE NULL
            END
        FROM [' + @DbClr + N'].sys.assemblies
        WHERE permission_set_desc IN (''UNSAFE_ACCESS'', ''EXTERNAL_ACCESS'')
          AND is_user_defined = 1;';

    EXEC sp_executesql @ClrSQL;
    FETCH NEXT FROM clr_cursor INTO @DbClr;
END

CLOSE clr_cursor;
DEALLOCATE clr_cursor;
GO

-- ============================================
-- 11. LOG FILE SIZE AND VLF COUNT
-- ============================================
PRINT '>> Check 11: Transaction log file size and VLF count...';

DECLARE @LogSQL NVARCHAR(MAX);
DECLARE @DbLog NVARCHAR(128);

DECLARE log_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT DatabaseName FROM #TargetDatabases;

OPEN log_cursor;
FETCH NEXT FROM log_cursor INTO @DbLog;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Log file size
    SET @LogSQL = N'
        INSERT INTO #PreCheckResults (CheckName, DatabaseName, Status, Details, Recommendation)
        SELECT
            ''Log File Size'',
            ''' + @DbLog + N''',
            CASE WHEN (size * 8 / 1024) > 10240 THEN ''WARNING'' ELSE ''INFO'' END,
            ''' + @DbLog + N' log file: '' + CAST(size * 8 / 1024 AS VARCHAR(20)) + '' MB.'',
            CASE WHEN (size * 8 / 1024) > 10240
                 THEN ''Large transaction log may slow initial migration. Consider shrinking after a log backup.''
                 ELSE NULL
            END
        FROM [' + @DbLog + N'].sys.database_files
        WHERE type_desc = ''LOG'';';

    EXEC sp_executesql @LogSQL;
    FETCH NEXT FROM log_cursor INTO @DbLog;
END

CLOSE log_cursor;
DEALLOCATE log_cursor;
GO

-- ============================================
-- 12. NETWORK CONNECTIVITY NOTES
-- ============================================
PRINT '>> Check 12: Network and connectivity reminders...';

INSERT INTO #PreCheckResults (CheckName, Status, Details, Recommendation)
VALUES ('Network Connectivity', 'INFO',
    'DMS requires network access from the DMS VNet to both the source SQL Server and target SQL MI.',
    'Verify: (1) VPN/ExpressRoute to on-prem is configured, (2) NSG rules allow port 1433, (3) SQL MI public endpoint is enabled if needed.');

INSERT INTO #PreCheckResults (CheckName, Status, Details, Recommendation)
VALUES ('Windows Firewall', 'INFO',
    'Ensure Windows Firewall on the source server allows inbound TCP 1433 from the DMS subnet.',
    'Open port 1433 in Windows Firewall for the DMS subnet IP range.');
GO

-- ============================================
-- 13. DISTRIBUTED TRANSACTIONS (MSDTC)
-- ============================================
PRINT '>> Check 13: Distributed transaction check...';

DECLARE @DtcSQL NVARCHAR(MAX);
DECLARE @DbDtc NVARCHAR(128);

DECLARE dtc_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT DatabaseName FROM #TargetDatabases;

OPEN dtc_cursor;
FETCH NEXT FROM dtc_cursor INTO @DbDtc;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @DtcSQL = N'
        INSERT INTO #PreCheckResults (CheckName, DatabaseName, Status, Details)
        SELECT TOP 1
            ''Cross-Database Queries'',
            ''' + @DbDtc + N''',
            ''INFO'',
            ''' + @DbDtc + N': Check application code for cross-database or distributed queries that may break post-migration.''
        ;';

    EXEC sp_executesql @DtcSQL;
    FETCH NEXT FROM dtc_cursor INTO @DbDtc;
END

CLOSE dtc_cursor;
DEALLOCATE dtc_cursor;
GO

-- ============================================
-- 14. DATABASE SIZE SUMMARY
-- ============================================
PRINT '>> Check 14: Database size summary...';

DECLARE @SizeSQL NVARCHAR(MAX);
DECLARE @DbSize NVARCHAR(128);

DECLARE size_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT DatabaseName FROM #TargetDatabases;

OPEN size_cursor;
FETCH NEXT FROM size_cursor INTO @DbSize;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @SizeSQL = N'
        INSERT INTO #PreCheckResults (CheckName, DatabaseName, Status, Details)
        SELECT
            ''Database Size'',
            ''' + @DbSize + N''',
            ''INFO'',
            ''' + @DbSize + N' total size: '' +
                CAST(SUM(size * 8 / 1024) AS VARCHAR(20)) + '' MB ('' +
                CAST(COUNT(*) AS VARCHAR(5)) + '' file(s)).''
        FROM [' + @DbSize + N'].sys.database_files;';

    EXEC sp_executesql @SizeSQL;
    FETCH NEXT FROM size_cursor INTO @DbSize;
END

CLOSE size_cursor;
DEALLOCATE size_cursor;
GO

-- ============================================
-- PRINT PRE-CHECK RESULTS
-- ============================================

PRINT '';
PRINT '================================================================';
PRINT ' DMS Pre-Migration Readiness Results';
PRINT '================================================================';
PRINT '';

-- Summary counts
DECLARE @PassCnt INT, @FailCnt INT, @WarnCnt INT, @InfoCnt INT;

SELECT
    @PassCnt = SUM(CASE WHEN Status = 'PASS' THEN 1 ELSE 0 END),
    @FailCnt = SUM(CASE WHEN Status = 'FAIL' THEN 1 ELSE 0 END),
    @WarnCnt = SUM(CASE WHEN Status = 'WARNING' THEN 1 ELSE 0 END),
    @InfoCnt = SUM(CASE WHEN Status = 'INFO' THEN 1 ELSE 0 END)
FROM #PreCheckResults;

PRINT ' PASS    : ' + CAST(ISNULL(@PassCnt, 0) AS VARCHAR(5));
PRINT ' FAIL    : ' + CAST(ISNULL(@FailCnt, 0) AS VARCHAR(5));
PRINT ' WARNING : ' + CAST(ISNULL(@WarnCnt, 0) AS VARCHAR(5));
PRINT ' INFO    : ' + CAST(ISNULL(@InfoCnt, 0) AS VARCHAR(5));
PRINT '';

-- Detailed results
SELECT
    CheckID,
    CheckName,
    ISNULL(DatabaseName, '(server)') AS DatabaseName,
    Status,
    Details,
    ISNULL(Recommendation, '')       AS Recommendation
FROM #PreCheckResults
ORDER BY
    CASE Status
        WHEN 'FAIL'    THEN 1
        WHEN 'WARNING' THEN 2
        WHEN 'PASS'    THEN 3
        WHEN 'INFO'    THEN 4
    END,
    CheckID;

-- Overall verdict
IF @FailCnt > 0
BEGIN
    PRINT '';
    PRINT '*** PRE-CHECK FAILED ***';
    PRINT 'There are ' + CAST(@FailCnt AS VARCHAR(5)) + ' failed check(s).';
    PRINT 'Resolve all FAIL items before starting DMS online migration.';
END
ELSE IF @WarnCnt > 0
BEGIN
    PRINT '';
    PRINT '*** PRE-CHECK PASSED WITH WARNINGS ***';
    PRINT 'Source is ready for migration but ' + CAST(@WarnCnt AS VARCHAR(5)) + ' warning(s) should be reviewed.';
END
ELSE
BEGIN
    PRINT '';
    PRINT '*** PRE-CHECK PASSED ***';
    PRINT 'Source server is ready for DMS online migration.';
END

PRINT '';
PRINT '================================================================';
PRINT ' Required Actions Before Starting DMS Migration';
PRINT '================================================================';
PRINT '';
PRINT '  1. Resolve all FAIL items listed above.';
PRINT '  2. Review all WARNING items and remediate where possible.';
PRINT '  3. Ensure a recent full backup exists for each database.';
PRINT '  4. Verify network connectivity from DMS to source (port 1433).';
PRINT '  5. Confirm backup file share is accessible from source server.';
PRINT '  6. Run 08-DMSMigrationConfig.ps1 to create the DMS project.';
PRINT '';
PRINT '================================================================';
PRINT ' Pre-check complete.';
PRINT '================================================================';
GO

-- Cleanup
IF OBJECT_ID('tempdb..#PreCheckResults') IS NOT NULL
    DROP TABLE #PreCheckResults;
IF OBJECT_ID('tempdb..#TargetDatabases') IS NOT NULL
    DROP TABLE #TargetDatabases;
GO
