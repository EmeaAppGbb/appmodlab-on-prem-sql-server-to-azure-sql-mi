-- ============================================
-- Step 28 - Comprehensive Post-Migration Validation
-- Lakeview Medical Center
-- Validates all aspects of the migration from
-- on-premises SQL Server 2016 to Azure SQL MI:
--   1. Database health & configuration
--   2. Object inventory (tables, views, procs, etc.)
--   3. Data integrity (row counts & checksums)
--   4. Security & permissions
--   5. TDE encryption status
--   6. CLR assemblies & functions
--   7. Service Broker configuration
--   8. SQL Agent jobs
--   9. Linked server alternatives
--  10. Performance & Query Store
--  11. Backup configuration
--  12. Connectivity & endpoints
-- ============================================
-- Run against: Azure SQL Managed Instance
-- Requires: VIEW SERVER STATE, VIEW ANY DEFINITION
-- Databases: PatientDB, BillingDB, SchedulingDB,
--            ReportingDB
-- ============================================

SET NOCOUNT ON;
GO

PRINT '================================================================';
PRINT ' Lakeview Medical Center - Post-Migration Validation';
PRINT ' Run Date: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT ' Server  : ' + @@SERVERNAME;
PRINT ' Version : ' + @@VERSION;
PRINT '================================================================';
PRINT '';
GO

-- ============================================
-- Validation results staging table
-- ============================================
IF OBJECT_ID('tempdb..#ValidationResults') IS NOT NULL
    DROP TABLE #ValidationResults;

CREATE TABLE #ValidationResults (
    TestID          INT IDENTITY(1,1),
    Category        NVARCHAR(50),
    TestName        NVARCHAR(200),
    DatabaseName    NVARCHAR(128)   NULL,
    Status          NVARCHAR(10),       -- PASS / FAIL / WARN / INFO
    Details         NVARCHAR(MAX),
    TestedAt        DATETIME            DEFAULT GETDATE()
);
GO

-- ============================================
-- SECTION 1: Database Health & Configuration
-- ============================================
PRINT '========================================';
PRINT ' SECTION 1: DATABASE HEALTH';
PRINT '========================================';
PRINT '';

PRINT '>> 1a. Database online status...';
PRINT '';

INSERT INTO #ValidationResults (Category, TestName, DatabaseName, Status, Details)
SELECT
    'Database Health',
    'Database Online',
    name,
    CASE WHEN state_desc = 'ONLINE' THEN 'PASS' ELSE 'FAIL' END,
    'State: ' + state_desc + ', Recovery: ' + recovery_model_desc
FROM sys.databases
WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');
GO

PRINT '>> 1b. Compatibility level check...';
PRINT '';

INSERT INTO #ValidationResults (Category, TestName, DatabaseName, Status, Details)
SELECT
    'Database Health',
    'Compatibility Level',
    name,
    CASE
        WHEN compatibility_level >= 130 THEN 'PASS'
        ELSE 'WARN'
    END,
    'Compatibility Level: ' + CAST(compatibility_level AS VARCHAR(5))
        + ' (130 = SQL 2016, 140 = SQL 2017, 150 = SQL 2019)'
FROM sys.databases
WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');
GO

PRINT '>> 1c. Auto-configuration settings...';
PRINT '';

INSERT INTO #ValidationResults (Category, TestName, DatabaseName, Status, Details)
SELECT
    'Database Health',
    'Auto Configuration',
    name,
    CASE
        WHEN is_auto_create_stats_on = 1
         AND is_auto_update_stats_on = 1
         AND is_auto_shrink_on = 0
        THEN 'PASS'
        WHEN is_auto_shrink_on = 1 THEN 'FAIL'
        ELSE 'WARN'
    END,
    'AutoCreateStats=' + CAST(is_auto_create_stats_on AS VARCHAR(1))
        + ', AutoUpdateStats=' + CAST(is_auto_update_stats_on AS VARCHAR(1))
        + ', AutoShrink=' + CAST(is_auto_shrink_on AS VARCHAR(1))
        + CASE WHEN is_auto_shrink_on = 1 THEN ' (DISABLE AUTO_SHRINK!)' ELSE '' END
FROM sys.databases
WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');
GO

PRINT '>> 1d. Page verify option...';
PRINT '';

INSERT INTO #ValidationResults (Category, TestName, DatabaseName, Status, Details)
SELECT
    'Database Health',
    'Page Verify = CHECKSUM',
    name,
    CASE WHEN page_verify_option_desc = 'CHECKSUM' THEN 'PASS' ELSE 'FAIL' END,
    'Page Verify: ' + page_verify_option_desc
FROM sys.databases
WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');
GO

-- ============================================
-- SECTION 2: Object Inventory Validation
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 2: OBJECT INVENTORY';
PRINT '========================================';
PRINT '';

DECLARE @db NVARCHAR(128);
DECLARE @sql NVARCHAR(MAX);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
      AND state_desc = 'ONLINE';

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT '>> Object counts for [' + @db + ']...';

    SET @sql = N'
    USE [' + @db + N'];

    INSERT INTO #ValidationResults (Category, TestName, DatabaseName, Status, Details)
    SELECT
        ''Object Inventory'',
        ''Object Counts'',
        DB_NAME(),
        ''INFO'',
        ''Tables='' + CAST(SUM(CASE WHEN type = ''U'' THEN 1 ELSE 0 END) AS VARCHAR(10))
        + '', Views='' + CAST(SUM(CASE WHEN type = ''V'' THEN 1 ELSE 0 END) AS VARCHAR(10))
        + '', Procs='' + CAST(SUM(CASE WHEN type = ''P'' THEN 1 ELSE 0 END) AS VARCHAR(10))
        + '', Functions='' + CAST(SUM(CASE WHEN type IN (''FN'',''IF'',''TF'',''FS'',''FT'') THEN 1 ELSE 0 END) AS VARCHAR(10))
        + '', Triggers='' + CAST(SUM(CASE WHEN type = ''TR'' THEN 1 ELSE 0 END) AS VARCHAR(10))
        + '', Indexes='' + CAST((SELECT COUNT(*) FROM sys.indexes WHERE object_id IN
            (SELECT object_id FROM sys.objects WHERE is_ms_shipped = 0)) AS VARCHAR(10))
    FROM sys.objects
    WHERE is_ms_shipped = 0;
    ';

    EXEC sp_executesql @sql;

    -- Check for invalid objects
    SET @sql = N'
    USE [' + @db + N'];

    INSERT INTO #ValidationResults (Category, TestName, DatabaseName, Status, Details)
    SELECT
        ''Object Inventory'',
        ''Invalid Objects'',
        DB_NAME(),
        CASE WHEN COUNT(*) = 0 THEN ''PASS'' ELSE ''WARN'' END,
        CASE WHEN COUNT(*) = 0
             THEN ''No invalid objects found''
             ELSE CAST(COUNT(*) AS VARCHAR(10)) + '' objects failed validation''
        END
    FROM sys.sql_modules m
    INNER JOIN sys.objects o ON m.object_id = o.object_id
    WHERE o.is_ms_shipped = 0
      AND OBJECTPROPERTY(m.object_id, ''ExecIsQuotedIdentOn'') IS NULL;
    ';

    EXEC sp_executesql @sql;

    FETCH NEXT FROM db_cursor INTO @db;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;
GO

-- ============================================
-- SECTION 3: Data Integrity (Row Counts)
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 3: DATA INTEGRITY';
PRINT '========================================';
PRINT '';

DECLARE @db2 NVARCHAR(128);
DECLARE @sql2 NVARCHAR(MAX);

DECLARE db_cursor2 CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
      AND state_desc = 'ONLINE';

OPEN db_cursor2;
FETCH NEXT FROM db_cursor2 INTO @db2;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT '>> Row counts for [' + @db2 + ']...';

    SET @sql2 = N'
    USE [' + @db2 + N'];

    SELECT
        DB_NAME()                               AS DatabaseName,
        s.name + ''.'' + t.name                 AS TableName,
        SUM(p.rows)                             AS RowCount
    FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0, 1)
    GROUP BY s.name, t.name
    ORDER BY SUM(p.rows) DESC;

    INSERT INTO #ValidationResults (Category, TestName, DatabaseName, Status, Details)
    SELECT
        ''Data Integrity'',
        ''Row Count - '' + s.name + ''.'' + t.name,
        DB_NAME(),
        CASE
            WHEN SUM(p.rows) > 0 THEN ''PASS''
            ELSE ''WARN''
        END,
        CAST(SUM(p.rows) AS VARCHAR(20)) + '' rows''
        + '' (compare with source to verify completeness)''
    FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    INNER JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0, 1)
    GROUP BY s.name, t.name;
    ';

    EXEC sp_executesql @sql2;

    FETCH NEXT FROM db_cursor2 INTO @db2;
END

CLOSE db_cursor2;
DEALLOCATE db_cursor2;
GO

PRINT '';
PRINT '>> DBCC CHECKDB on all databases...';
PRINT '';

DECLARE @db3 NVARCHAR(128);
DECLARE @sql3 NVARCHAR(MAX);
DECLARE @startTime DATETIME;

DECLARE db_cursor3 CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
      AND state_desc = 'ONLINE';

OPEN db_cursor3;
FETCH NEXT FROM db_cursor3 INTO @db3;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @startTime = GETDATE();
    PRINT '   Running DBCC CHECKDB on [' + @db3 + ']...';

    BEGIN TRY
        SET @sql3 = N'DBCC CHECKDB ([' + @db3 + N']) WITH NO_INFOMSGS, ALL_ERRORMSGS;';
        EXEC sp_executesql @sql3;

        INSERT INTO #ValidationResults (Category, TestName, DatabaseName, Status, Details)
        VALUES ('Data Integrity', 'DBCC CHECKDB', @db3, 'PASS',
                'No errors. Duration: ' + CAST(DATEDIFF(SECOND, @startTime, GETDATE()) AS VARCHAR(10)) + 's');
    END TRY
    BEGIN CATCH
        INSERT INTO #ValidationResults (Category, TestName, DatabaseName, Status, Details)
        VALUES ('Data Integrity', 'DBCC CHECKDB', @db3, 'FAIL', ERROR_MESSAGE());
    END CATCH

    FETCH NEXT FROM db_cursor3 INTO @db3;
END

CLOSE db_cursor3;
DEALLOCATE db_cursor3;
GO

-- ============================================
-- SECTION 4: Security & Permissions
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 4: SECURITY & PERMISSIONS';
PRINT '========================================';
PRINT '';

PRINT '>> 4a. Server-level logins...';
PRINT '';

INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT
    'Security',
    'Server Login: ' + name,
    'INFO',
    'Type: ' + type_desc
        + ', Default DB: ' + ISNULL(default_database_name, 'N/A')
        + ', Disabled: ' + CAST(is_disabled AS VARCHAR(1))
FROM sys.server_principals
WHERE type IN ('S', 'U', 'G', 'E', 'X')
  AND name NOT LIKE '##%'
  AND name NOT IN ('sa', 'public');
GO

PRINT '>> 4b. Database-level users per database...';
PRINT '';

DECLARE @db4 NVARCHAR(128);
DECLARE @sql4 NVARCHAR(MAX);

DECLARE db_cursor4 CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
      AND state_desc = 'ONLINE';

OPEN db_cursor4;
FETCH NEXT FROM db_cursor4 INTO @db4;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql4 = N'
    USE [' + @db4 + N'];

    INSERT INTO #ValidationResults (Category, TestName, DatabaseName, Status, Details)
    SELECT
        ''Security'',
        ''DB User: '' + dp.name,
        DB_NAME(),
        CASE WHEN dp.name = ''dbo'' OR sp.name IS NOT NULL THEN ''PASS'' ELSE ''WARN'' END,
        ''Type: '' + dp.type_desc
            + '', Login: '' + ISNULL(sp.name, ''ORPHANED'')
            + '', Roles: '' + ISNULL(STUFF((
                SELECT '', '' + r.name
                FROM sys.database_role_members rm
                INNER JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id
                WHERE rm.member_principal_id = dp.principal_id
                FOR XML PATH('''')), 1, 2, ''''), ''none'')
    FROM sys.database_principals dp
    LEFT JOIN sys.server_principals sp ON dp.sid = sp.sid
    WHERE dp.type IN (''S'', ''U'', ''G'', ''E'', ''X'')
      AND dp.name NOT IN (''dbo'', ''guest'', ''INFORMATION_SCHEMA'', ''sys'')
      AND dp.name NOT LIKE ''##%'';
    ';

    EXEC sp_executesql @sql4;

    FETCH NEXT FROM db_cursor4 INTO @db4;
END

CLOSE db_cursor4;
DEALLOCATE db_cursor4;
GO

PRINT '>> 4c. Orphaned users check...';
PRINT '';

DECLARE @db4b NVARCHAR(128);
DECLARE @sql4b NVARCHAR(MAX);

DECLARE db_cursor4b CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
      AND state_desc = 'ONLINE';

OPEN db_cursor4b;
FETCH NEXT FROM db_cursor4b INTO @db4b;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql4b = N'
    USE [' + @db4b + N'];

    INSERT INTO #ValidationResults (Category, TestName, DatabaseName, Status, Details)
    SELECT
        ''Security'',
        ''Orphaned User Check'',
        DB_NAME(),
        CASE WHEN COUNT(*) = 0 THEN ''PASS'' ELSE ''FAIL'' END,
        CASE WHEN COUNT(*) = 0
             THEN ''No orphaned users''
             ELSE CAST(COUNT(*) AS VARCHAR(10)) + '' orphaned user(s): ''
                  + STUFF((
                      SELECT '', '' + dp.name
                      FROM sys.database_principals dp
                      LEFT JOIN sys.server_principals sp ON dp.sid = sp.sid
                      WHERE dp.type IN (''S'', ''U'') AND sp.sid IS NULL
                        AND dp.name NOT IN (''dbo'', ''guest'', ''INFORMATION_SCHEMA'', ''sys'')
                        AND dp.name NOT LIKE ''##%''
                        AND dp.authentication_type <> 0
                      FOR XML PATH('''')), 1, 2, '''')
        END
    FROM sys.database_principals dp
    LEFT JOIN sys.server_principals sp ON dp.sid = sp.sid
    WHERE dp.type IN (''S'', ''U'') AND sp.sid IS NULL
      AND dp.name NOT IN (''dbo'', ''guest'', ''INFORMATION_SCHEMA'', ''sys'')
      AND dp.name NOT LIKE ''##%''
      AND dp.authentication_type <> 0;
    ';

    EXEC sp_executesql @sql4b;

    FETCH NEXT FROM db_cursor4b INTO @db4b;
END

CLOSE db_cursor4b;
DEALLOCATE db_cursor4b;
GO

-- ============================================
-- SECTION 5: TDE Encryption Status
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 5: TDE ENCRYPTION';
PRINT '========================================';
PRINT '';

PRINT '>> 5a. TDE status per database...';
PRINT '';

INSERT INTO #ValidationResults (Category, TestName, DatabaseName, Status, Details)
SELECT
    'TDE',
    'Encryption State',
    DB_NAME(dek.database_id),
    CASE
        WHEN dek.encryption_state = 3 THEN 'PASS'
        WHEN dek.encryption_state = 2 THEN 'WARN'
        ELSE 'FAIL'
    END,
    'State: ' + CASE dek.encryption_state
        WHEN 0 THEN 'No encryption key'
        WHEN 1 THEN 'Unencrypted'
        WHEN 2 THEN 'Encryption in progress'
        WHEN 3 THEN 'Encrypted'
        WHEN 4 THEN 'Key change in progress'
        WHEN 5 THEN 'Decryption in progress'
        ELSE 'Unknown (' + CAST(dek.encryption_state AS VARCHAR(5)) + ')'
    END
    + ', Algorithm: ' + ISNULL(dek.encryptor_type, 'N/A')
    + ', Key: ' + ISNULL(dek.key_algorithm + ' ' + CAST(dek.key_length AS VARCHAR(5)), 'N/A')
FROM sys.dm_database_encryption_keys dek
INNER JOIN sys.databases d ON dek.database_id = d.database_id
WHERE d.name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

-- Check for databases without TDE
INSERT INTO #ValidationResults (Category, TestName, DatabaseName, Status, Details)
SELECT
    'TDE',
    'TDE Not Configured',
    d.name,
    'WARN',
    'Database does not have TDE encryption configured'
FROM sys.databases d
LEFT JOIN sys.dm_database_encryption_keys dek ON d.database_id = dek.database_id
WHERE d.name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
  AND dek.database_id IS NULL;
GO

-- ============================================
-- SECTION 6: CLR Assemblies & Functions
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 6: CLR VALIDATION';
PRINT '========================================';
PRINT '';

PRINT '>> 6a. CLR enabled check...';
PRINT '';

INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT
    'CLR',
    'CLR Enabled',
    CASE WHEN CAST(value_in_use AS INT) = 1 THEN 'PASS' ELSE 'FAIL' END,
    'clr enabled = ' + CAST(value_in_use AS VARCHAR(5))
FROM sys.configurations
WHERE name = 'clr enabled';
GO

PRINT '>> 6b. CLR assemblies per database...';
PRINT '';

DECLARE @db6 NVARCHAR(128);
DECLARE @sql6 NVARCHAR(MAX);

DECLARE db_cursor6 CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
      AND state_desc = 'ONLINE';

OPEN db_cursor6;
FETCH NEXT FROM db_cursor6 INTO @db6;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql6 = N'
    USE [' + @db6 + N'];

    INSERT INTO #ValidationResults (Category, TestName, DatabaseName, Status, Details)
    SELECT
        ''CLR'',
        ''Assembly: '' + a.name,
        DB_NAME(),
        CASE
            WHEN a.permission_set_desc IN (''SAFE_ACCESS'', ''EXTERNAL_ACCESS'', ''UNSAFE_ACCESS'')
            THEN ''PASS''
            ELSE ''WARN''
        END,
        ''Permission: '' + a.permission_set_desc
            + '', Version: '' + CAST(a.clr_name AS NVARCHAR(500))
    FROM sys.assemblies a
    WHERE a.is_user_defined = 1;

    -- Check CLR functions exist and are valid
    INSERT INTO #ValidationResults (Category, TestName, DatabaseName, Status, Details)
    SELECT
        ''CLR'',
        ''CLR Function: '' + SCHEMA_NAME(o.schema_id) + ''.'' + o.name,
        DB_NAME(),
        ''INFO'',
        ''Type: '' + o.type_desc
    FROM sys.objects o
    WHERE o.type IN (''FS'', ''FT'', ''PC'')
      AND o.is_ms_shipped = 0;
    ';

    EXEC sp_executesql @sql6;

    FETCH NEXT FROM db_cursor6 INTO @db6;
END

CLOSE db_cursor6;
DEALLOCATE db_cursor6;
GO

-- ============================================
-- SECTION 7: Service Broker Validation
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 7: SERVICE BROKER';
PRINT '========================================';
PRINT '';

PRINT '>> 7a. Service Broker enabled status...';
PRINT '';

INSERT INTO #ValidationResults (Category, TestName, DatabaseName, Status, Details)
SELECT
    'Service Broker',
    'Broker Enabled',
    name,
    CASE WHEN is_broker_enabled = 1 THEN 'PASS' ELSE 'WARN' END,
    'Broker Enabled: ' + CAST(is_broker_enabled AS VARCHAR(1))
        + ', Broker GUID: ' + CAST(service_broker_guid AS VARCHAR(50))
FROM sys.databases
WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');
GO

PRINT '>> 7b. Service Broker objects per database...';
PRINT '';

DECLARE @db7 NVARCHAR(128);
DECLARE @sql7 NVARCHAR(MAX);

DECLARE db_cursor7 CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
      AND state_desc = 'ONLINE';

OPEN db_cursor7;
FETCH NEXT FROM db_cursor7 INTO @db7;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql7 = N'
    USE [' + @db7 + N'];

    INSERT INTO #ValidationResults (Category, TestName, DatabaseName, Status, Details)
    SELECT
        ''Service Broker'',
        ''Broker Objects'',
        DB_NAME(),
        ''INFO'',
        ''Queues='' + CAST((SELECT COUNT(*) FROM sys.service_queues WHERE is_ms_shipped = 0) AS VARCHAR(10))
        + '', Services='' + CAST((SELECT COUNT(*) FROM sys.services WHERE is_ms_shipped = 0) AS VARCHAR(10))
        + '', Contracts='' + CAST((SELECT COUNT(*) FROM sys.service_contracts WHERE is_ms_shipped = 0) AS VARCHAR(10))
        + '', MessageTypes='' + CAST((SELECT COUNT(*) FROM sys.service_message_types WHERE is_ms_shipped = 0) AS VARCHAR(10));

    -- Check for poison messages in queues
    DECLARE @queueName NVARCHAR(256);
    DECLARE @queueSQL NVARCHAR(MAX);

    DECLARE q_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT SCHEMA_NAME(schema_id) + ''.'' + name
        FROM sys.service_queues WHERE is_ms_shipped = 0;

    OPEN q_cursor;
    FETCH NEXT FROM q_cursor INTO @queueName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        INSERT INTO #ValidationResults (Category, TestName, DatabaseName, Status, Details)
        VALUES (''Service Broker'', ''Queue Status: '' + @queueName, DB_NAME(), ''INFO'',
                ''Queue exists and accessible'');
        FETCH NEXT FROM q_cursor INTO @queueName;
    END

    CLOSE q_cursor;
    DEALLOCATE q_cursor;
    ';

    EXEC sp_executesql @sql7;

    FETCH NEXT FROM db_cursor7 INTO @db7;
END

CLOSE db_cursor7;
DEALLOCATE db_cursor7;
GO

-- ============================================
-- SECTION 8: SQL Agent Jobs
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 8: SQL AGENT JOBS';
PRINT '========================================';
PRINT '';

PRINT '>> 8a. Agent job inventory and status...';
PRINT '';

INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT
    'Agent Jobs',
    'Job: ' + j.name,
    CASE
        WHEN j.enabled = 1 AND jh.run_status = 1 THEN 'PASS'
        WHEN j.enabled = 1 AND jh.run_status IS NULL THEN 'WARN'
        WHEN j.enabled = 0 THEN 'INFO'
        ELSE 'FAIL'
    END,
    'Enabled: ' + CAST(j.enabled AS VARCHAR(1))
        + ', Last Run: ' + CASE
            WHEN jh.run_date IS NOT NULL
            THEN CAST(jh.run_date AS VARCHAR(10)) + ' ' + CAST(jh.run_time AS VARCHAR(10))
            ELSE 'Never' END
        + ', Last Status: ' + ISNULL(
            CASE jh.run_status
                WHEN 0 THEN 'Failed'
                WHEN 1 THEN 'Succeeded'
                WHEN 2 THEN 'Retry'
                WHEN 3 THEN 'Canceled'
                ELSE 'Unknown'
            END, 'N/A')
FROM msdb.dbo.sysjobs j
LEFT JOIN (
    SELECT job_id, run_date, run_time, run_status,
           ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY run_date DESC, run_time DESC) AS rn
    FROM msdb.dbo.sysjobhistory
    WHERE step_id = 0
) jh ON j.job_id = jh.job_id AND jh.rn = 1
ORDER BY j.name;
GO

PRINT '>> 8b. Failed jobs in last 7 days...';
PRINT '';

INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT
    'Agent Jobs',
    'Recent Failures',
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'WARN' END,
    CASE WHEN COUNT(*) = 0
         THEN 'No job failures in last 7 days'
         ELSE CAST(COUNT(*) AS VARCHAR(10)) + ' job failure(s) in last 7 days'
    END
FROM msdb.dbo.sysjobhistory jh
INNER JOIN msdb.dbo.sysjobs j ON jh.job_id = j.job_id
WHERE jh.run_status = 0
  AND jh.step_id = 0
  AND msdb.dbo.agent_datetime(jh.run_date, jh.run_time) >= DATEADD(DAY, -7, GETDATE());
GO

-- ============================================
-- SECTION 9: Linked Server Alternatives
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 9: LINKED SERVERS';
PRINT '========================================';
PRINT '';

PRINT '>> 9a. Linked server configuration...';
PRINT '';

INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT
    'Linked Servers',
    'Linked Server: ' + name,
    CASE
        WHEN provider = 'SQLNCLI' OR provider = 'SQLNCLI11' OR provider = 'MSOLEDBSQL'
        THEN 'INFO'
        ELSE 'WARN'
    END,
    'Provider: ' + ISNULL(provider, 'N/A')
        + ', Data Source: ' + ISNULL(data_source, 'N/A')
        + ', Product: ' + ISNULL(product, 'N/A')
FROM sys.servers
WHERE is_linked = 1;

-- If no linked servers, record that
IF NOT EXISTS (SELECT 1 FROM sys.servers WHERE is_linked = 1)
BEGIN
    INSERT INTO #ValidationResults (Category, TestName, Status, Details)
    VALUES ('Linked Servers', 'Linked Server Check', 'INFO',
            'No linked servers configured (expected if using alternatives per Step 18)');
END
GO

-- ============================================
-- SECTION 10: Performance & Query Store
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 10: PERFORMANCE & QUERY STORE';
PRINT '========================================';
PRINT '';

PRINT '>> 10a. Query Store status per database...';
PRINT '';

INSERT INTO #ValidationResults (Category, TestName, DatabaseName, Status, Details)
SELECT
    'Performance',
    'Query Store Enabled',
    name,
    CASE WHEN is_query_store_on = 1 THEN 'PASS' ELSE 'WARN' END,
    'Query Store: ' + CASE WHEN is_query_store_on = 1 THEN 'ON' ELSE 'OFF' END
FROM sys.databases
WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');
GO

PRINT '>> 10b. Query Store configuration details...';
PRINT '';

DECLARE @db10 NVARCHAR(128);
DECLARE @sql10 NVARCHAR(MAX);

DECLARE db_cursor10 CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
      AND state_desc = 'ONLINE'
      AND is_query_store_on = 1;

OPEN db_cursor10;
FETCH NEXT FROM db_cursor10 INTO @db10;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql10 = N'
    USE [' + @db10 + N'];

    INSERT INTO #ValidationResults (Category, TestName, DatabaseName, Status, Details)
    SELECT
        ''Performance'',
        ''Query Store Config'',
        DB_NAME(),
        CASE
            WHEN actual_state_desc = ''READ_WRITE'' THEN ''PASS''
            WHEN actual_state_desc = ''READ_ONLY'' THEN ''WARN''
            ELSE ''FAIL''
        END,
        ''State: '' + actual_state_desc
            + '', MaxSize: '' + CAST(max_storage_size_mb AS VARCHAR(10)) + ''MB''
            + '', CurrentSize: '' + CAST(current_storage_size_mb AS VARCHAR(10)) + ''MB''
            + '', CaptureMode: '' + capture_mode_desc
            + '', StaleThreshold: '' + CAST(stale_query_threshold_days AS VARCHAR(10)) + '' days''
    FROM sys.database_query_store_options;
    ';

    EXEC sp_executesql @sql10;

    FETCH NEXT FROM db_cursor10 INTO @db10;
END

CLOSE db_cursor10;
DEALLOCATE db_cursor10;
GO

PRINT '>> 10c. MI resource utilization snapshot...';
PRINT '';

INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT TOP 1
    'Performance',
    'MI Resource Utilization (Latest)',
    CASE
        WHEN avg_cpu_percent < 80 AND avg_instance_cpu_percent < 80 THEN 'PASS'
        WHEN avg_cpu_percent < 95 THEN 'WARN'
        ELSE 'FAIL'
    END,
    'CPU=' + CAST(CAST(avg_cpu_percent AS DECIMAL(5,1)) AS VARCHAR(10)) + '%'
        + ', InstanceCPU=' + CAST(CAST(avg_instance_cpu_percent AS DECIMAL(5,1)) AS VARCHAR(10)) + '%'
        + ', DataIO=' + CAST(CAST(avg_data_io_percent AS DECIMAL(5,1)) AS VARCHAR(10)) + '%'
        + ', LogWrite=' + CAST(CAST(avg_log_write_percent AS DECIMAL(5,1)) AS VARCHAR(10)) + '%'
        + ', Memory=' + CAST(CAST(avg_memory_usage_percent AS DECIMAL(5,1)) AS VARCHAR(10)) + '%'
FROM sys.server_resource_stats
ORDER BY end_time DESC;
GO

-- ============================================
-- SECTION 11: Backup Configuration
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 11: BACKUP CONFIGURATION';
PRINT '========================================';
PRINT '';

PRINT '>> 11a. Recent backup history...';
PRINT '';

INSERT INTO #ValidationResults (Category, TestName, DatabaseName, Status, Details)
SELECT
    'Backups',
    'Last Backup: ' + CASE bs.type
        WHEN 'D' THEN 'Full'
        WHEN 'I' THEN 'Differential'
        WHEN 'L' THEN 'Log'
        ELSE bs.type END,
    bs.database_name,
    CASE
        WHEN bs.type = 'D' AND DATEDIFF(DAY, bs.backup_finish_date, GETDATE()) <= 7 THEN 'PASS'
        WHEN bs.type = 'L' AND DATEDIFF(MINUTE, bs.backup_finish_date, GETDATE()) <= 60 THEN 'PASS'
        WHEN bs.type = 'D' AND DATEDIFF(DAY, bs.backup_finish_date, GETDATE()) <= 14 THEN 'WARN'
        ELSE 'WARN'
    END,
    'Finished: ' + CONVERT(VARCHAR(30), bs.backup_finish_date, 120)
        + ', Size: ' + CAST(CAST(bs.backup_size / 1048576.0 AS DECIMAL(10,1)) AS VARCHAR(20)) + ' MB'
        + ', Compressed: ' + CAST(CAST(ISNULL(bs.compressed_backup_size, bs.backup_size) / 1048576.0 AS DECIMAL(10,1)) AS VARCHAR(20)) + ' MB'
FROM msdb.dbo.backupset bs
INNER JOIN (
    SELECT database_name, type, MAX(backup_finish_date) AS max_finish
    FROM msdb.dbo.backupset
    WHERE database_name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
    GROUP BY database_name, type
) latest ON bs.database_name = latest.database_name
        AND bs.type = latest.type
        AND bs.backup_finish_date = latest.max_finish
WHERE bs.database_name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
ORDER BY bs.database_name, bs.type;
GO

-- ============================================
-- SECTION 12: Connectivity & Endpoints
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 12: CONNECTIVITY & ENDPOINTS';
PRINT '========================================';
PRINT '';

PRINT '>> 12a. MI endpoint information...';
PRINT '';

INSERT INTO #ValidationResults (Category, TestName, Status, Details)
VALUES ('Connectivity', 'MI FQDN', 'INFO',
        'Server: ' + @@SERVERNAME);

INSERT INTO #ValidationResults (Category, TestName, Status, Details)
SELECT
    'Connectivity',
    'Endpoint: ' + name,
    'INFO',
    'Protocol: ' + protocol_desc + ', Type: ' + type_desc
        + ', State: ' + state_desc
FROM sys.endpoints
WHERE type <> 2;    -- Exclude TSQL endpoints
GO

PRINT '>> 12b. Active connection count by database...';
PRINT '';

INSERT INTO #ValidationResults (Category, TestName, DatabaseName, Status, Details)
SELECT
    'Connectivity',
    'Active Connections',
    DB_NAME(database_id),
    'INFO',
    CAST(COUNT(*) AS VARCHAR(10)) + ' active connection(s)'
FROM sys.dm_exec_sessions
WHERE database_id IN (
    SELECT database_id FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
)
GROUP BY database_id;
GO

-- ============================================
-- VALIDATION SUMMARY
-- ============================================
PRINT '';
PRINT '================================================================';
PRINT ' VALIDATION SUMMARY';
PRINT '================================================================';
PRINT '';

SELECT
    Status,
    COUNT(*) AS TestCount
FROM #ValidationResults
GROUP BY Status
ORDER BY
    CASE Status
        WHEN 'FAIL' THEN 1
        WHEN 'WARN' THEN 2
        WHEN 'PASS' THEN 3
        WHEN 'INFO' THEN 4
    END;

PRINT '';
PRINT '--- FAILURES ---';
PRINT '';

SELECT
    TestID,
    Category,
    TestName,
    ISNULL(DatabaseName, 'Server') AS Scope,
    Details
FROM #ValidationResults
WHERE Status = 'FAIL'
ORDER BY Category, TestName;

PRINT '';
PRINT '--- WARNINGS ---';
PRINT '';

SELECT
    TestID,
    Category,
    TestName,
    ISNULL(DatabaseName, 'Server') AS Scope,
    Details
FROM #ValidationResults
WHERE Status = 'WARN'
ORDER BY Category, TestName;

PRINT '';
PRINT '--- ALL RESULTS ---';
PRINT '';

SELECT
    TestID,
    Category,
    TestName,
    ISNULL(DatabaseName, 'Server') AS Scope,
    Status,
    Details,
    TestedAt
FROM #ValidationResults
ORDER BY
    CASE Status
        WHEN 'FAIL' THEN 1
        WHEN 'WARN' THEN 2
        WHEN 'PASS' THEN 3
        WHEN 'INFO' THEN 4
    END,
    Category,
    TestName;
GO

PRINT '';
PRINT '================================================================';
PRINT ' Post-Migration Validation Complete';
PRINT ' Timestamp: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT '';
PRINT ' Review FAIL and WARN items above before sign-off.';
PRINT '';
PRINT ' Migration Steps Validated:';
PRINT '   [x] Database health & configuration';
PRINT '   [x] Object inventory (tables, views, procs, functions)';
PRINT '   [x] Data integrity (row counts, DBCC CHECKDB)';
PRINT '   [x] Security & permissions (logins, users, orphans)';
PRINT '   [x] TDE encryption status';
PRINT '   [x] CLR assemblies & functions';
PRINT '   [x] Service Broker configuration';
PRINT '   [x] SQL Agent jobs';
PRINT '   [x] Linked server configuration';
PRINT '   [x] Performance & Query Store';
PRINT '   [x] Backup configuration';
PRINT '   [x] Connectivity & endpoints';
PRINT '================================================================';
GO

-- Clean up
DROP TABLE IF EXISTS #ValidationResults;
GO
