-- ============================================
-- Azure SQL MI Migration Assessment
-- Lakeview Medical Center
-- Checks PatientDB, BillingDB, SchedulingDB,
-- and ReportingDB for compatibility issues
-- ============================================
-- Run against the on-premises SQL Server instance
-- Requires: VIEW SERVER STATE, VIEW ANY DEFINITION
-- ============================================

SET NOCOUNT ON;
GO

PRINT '================================================================';
PRINT ' Lakeview Medical Center - Azure SQL MI Compatibility Assessment';
PRINT ' Run Date: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT ' Server  : ' + @@SERVERNAME;
PRINT ' Version : ' + @@VERSION;
PRINT '================================================================';
PRINT '';
GO

-- ============================================
-- Assessment results staging table
-- ============================================
IF OBJECT_ID('tempdb..#AssessmentResults') IS NOT NULL
    DROP TABLE #AssessmentResults;

CREATE TABLE #AssessmentResults (
    AssessmentID    INT IDENTITY(1,1),
    Category        NVARCHAR(50)   NOT NULL,
    DatabaseName    NVARCHAR(128)  NULL,
    ObjectName      NVARCHAR(256)  NULL,
    Severity        NVARCHAR(20)   NOT NULL,  -- BLOCKER, WARNING, INFO
    Issue           NVARCHAR(500)  NOT NULL,
    Recommendation  NVARCHAR(1000) NULL
);
GO

-- ============================================
-- 1. CROSS-DATABASE QUERIES
-- Azure SQL MI supports cross-database queries
-- within the same instance, but cross-instance
-- queries require Elastic Query or Linked Servers
-- ============================================
PRINT '>> Checking cross-database references...';

DECLARE @db NVARCHAR(128);
DECLARE @sql NVARCHAR(MAX);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'
    USE [' + @db + N'];
    INSERT INTO #AssessmentResults (Category, DatabaseName, ObjectName, Severity, Issue, Recommendation)
    SELECT DISTINCT
        ''Cross-Database Query'',
        ''' + @db + N''',
        QUOTENAME(OBJECT_SCHEMA_NAME(d.referencing_id)) + ''.'' + QUOTENAME(OBJECT_NAME(d.referencing_id)),
        ''WARNING'',
        ''References '' + d.referenced_database_name + ''.'' +
            ISNULL(d.referenced_schema_name, ''dbo'') + ''.'' + d.referenced_entity_name,
        ''Cross-database queries work on Azure SQL MI within the same instance. '' +
        ''Verify all 4 databases will be migrated to the same MI instance, '' +
        ''or refactor to use synonyms/elastic queries.''
    FROM sys.sql_expression_dependencies d
    WHERE d.referenced_database_name IS NOT NULL
      AND d.referenced_database_name NOT IN (DB_NAME(), ''master'', ''msdb'', ''tempdb'');
    ';
    EXEC sp_executesql @sql;

    FETCH NEXT FROM db_cursor INTO @db;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;
GO

-- ============================================
-- 2. CLR ASSEMBLIES
-- Azure SQL MI supports CLR with SAFE permission
-- set. EXTERNAL_ACCESS and UNSAFE require review.
-- ============================================
PRINT '>> Checking CLR assemblies...';

DECLARE @db2 NVARCHAR(128);
DECLARE @sql2 NVARCHAR(MAX);

DECLARE db_cursor2 CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

OPEN db_cursor2;
FETCH NEXT FROM db_cursor2 INTO @db2;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql2 = N'
    USE [' + @db2 + N'];
    INSERT INTO #AssessmentResults (Category, DatabaseName, ObjectName, Severity, Issue, Recommendation)
    SELECT
        ''CLR Assembly'',
        ''' + @db2 + N''',
        a.name,
        CASE
            WHEN a.permission_set_desc = ''UNSAFE_ACCESS'' THEN ''BLOCKER''
            WHEN a.permission_set_desc = ''EXTERNAL_ACCESS'' THEN ''WARNING''
            ELSE ''INFO''
        END,
        ''CLR assembly ['' + a.name + ''] with permission_set = '' + a.permission_set_desc +
        ''. CLR enabled = '' + CAST(a.is_visible AS VARCHAR),
        CASE
            WHEN a.permission_set_desc = ''UNSAFE_ACCESS''
                THEN ''UNSAFE assemblies are not supported on Azure SQL MI. '' +
                     ''Rewrite as T-SQL or convert to SAFE. Review MedicalCalculations CLR functions.''
            WHEN a.permission_set_desc = ''EXTERNAL_ACCESS''
                THEN ''EXTERNAL_ACCESS requires signing the assembly with a certificate/asymmetric key '' +
                     ''and creating a login with UNSAFE ASSEMBLY permission.''
            ELSE ''SAFE assemblies are supported on Azure SQL MI. Migrate using CREATE ASSEMBLY FROM binary.''
        END
    FROM sys.assemblies a
    WHERE a.is_user_defined = 1;
    ';
    EXEC sp_executesql @sql2;

    FETCH NEXT FROM db_cursor2 INTO @db2;
END

CLOSE db_cursor2;
DEALLOCATE db_cursor2;
GO

-- ============================================
-- 3. SERVICE BROKER
-- Azure SQL MI supports Service Broker within
-- a single instance. Cross-instance SB is not
-- supported.
-- ============================================
PRINT '>> Checking Service Broker configuration...';

INSERT INTO #AssessmentResults (Category, DatabaseName, ObjectName, Severity, Issue, Recommendation)
SELECT
    'Service Broker',
    d.name,
    NULL,
    CASE WHEN d.is_broker_enabled = 1 THEN 'WARNING' ELSE 'INFO' END,
    'Service Broker is ' + CASE WHEN d.is_broker_enabled = 1 THEN 'ENABLED' ELSE 'DISABLED' END +
    '. Broker GUID: ' + CAST(d.service_broker_guid AS NVARCHAR(50)),
    CASE WHEN d.is_broker_enabled = 1
        THEN 'Azure SQL MI supports Service Broker within the same instance. ' +
             'Cross-instance messaging requires redesign (e.g., Azure Service Bus). ' +
             'Verify PatientDB<->BillingDB broker routes use LOCAL address.'
        ELSE 'No action required - Service Broker is not enabled.'
    END
FROM sys.databases d
WHERE d.name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');
GO

-- Service Broker objects detail
DECLARE @db3 NVARCHAR(128);
DECLARE @sql3 NVARCHAR(MAX);

DECLARE db_cursor3 CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

OPEN db_cursor3;
FETCH NEXT FROM db_cursor3 INTO @db3;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql3 = N'
    USE [' + @db3 + N'];
    INSERT INTO #AssessmentResults (Category, DatabaseName, ObjectName, Severity, Issue, Recommendation)
    SELECT
        ''Service Broker Object'',
        ''' + @db3 + N''',
        s.name,
        ''INFO'',
        ''Service: ['' + s.name + ''] on queue ['' + q.name + '']'',
        ''Review service contract and ensure routes use LOCAL address for same-instance MI migration.''
    FROM sys.services s
    JOIN sys.service_queues q ON s.service_queue_id = q.object_id;

    INSERT INTO #AssessmentResults (Category, DatabaseName, ObjectName, Severity, Issue, Recommendation)
    SELECT
        ''Service Broker Route'',
        ''' + @db3 + N''',
        r.name,
        CASE WHEN r.address <> ''LOCAL'' THEN ''BLOCKER'' ELSE ''INFO'' END,
        ''Route ['' + r.name + ''] -> '' + r.address +
        CASE WHEN r.remote_service_name IS NOT NULL
             THEN '' (remote: '' + r.remote_service_name + '')''
             ELSE '''' END,
        CASE WHEN r.address <> ''LOCAL''
             THEN ''Non-LOCAL routes indicate cross-instance messaging which is not supported on Azure SQL MI. '' +
                  ''Redesign with Azure Service Bus or Azure Queue Storage.''
             ELSE ''LOCAL route is compatible with Azure SQL MI same-instance deployment.''
        END
    FROM sys.routes r
    WHERE r.name <> ''AutoCreatedLocal'';
    ';
    EXEC sp_executesql @sql3;

    FETCH NEXT FROM db_cursor3 INTO @db3;
END

CLOSE db_cursor3;
DEALLOCATE db_cursor3;
GO

-- ============================================
-- 4. LINKED SERVERS
-- Azure SQL MI supports linked servers but with
-- limitations on providers and connectivity.
-- ============================================
PRINT '>> Checking linked servers...';

INSERT INTO #AssessmentResults (Category, DatabaseName, ObjectName, Severity, Issue, Recommendation)
SELECT
    'Linked Server',
    NULL,
    s.name,
    CASE
        WHEN s.provider = 'OraOLEDB.Oracle' THEN 'BLOCKER'
        WHEN s.provider NOT IN ('SQLNCLI11', 'MSOLEDBSQL', 'SQLOLEDB') THEN 'BLOCKER'
        ELSE 'WARNING'
    END,
    'Linked server [' + s.name + '] using provider ' + s.provider +
    ' -> ' + ISNULL(s.data_source, 'N/A') +
    CASE WHEN s.catalog IS NOT NULL THEN ' (catalog: ' + s.catalog + ')' ELSE '' END,
    CASE
        WHEN s.provider = 'OraOLEDB.Oracle'
            THEN 'Oracle OLEDB provider is NOT supported on Azure SQL MI. ' +
                 'Replace RADIOLOGY_PACS linked server with Azure Data Factory, ' +
                 'SSIS in Azure, or application-level integration.'
        WHEN s.provider NOT IN ('SQLNCLI11', 'MSOLEDBSQL', 'SQLOLEDB')
            THEN 'Provider ' + s.provider + ' may not be available on Azure SQL MI. ' +
                 'Only SQL Server-native providers are supported. Consider Azure Data Factory.'
        ELSE 'SQL Server linked servers are supported on Azure SQL MI. ' +
             'Ensure target server is network-reachable from MI VNet. ' +
             'Update connection strings and consider using managed identity.'
    END
FROM sys.servers s
WHERE s.server_id <> 0
  AND s.is_linked = 1;
GO

-- Detect linked server usage in stored procedures
DECLARE @db4 NVARCHAR(128);
DECLARE @sql4 NVARCHAR(MAX);

DECLARE db_cursor4 CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

OPEN db_cursor4;
FETCH NEXT FROM db_cursor4 INTO @db4;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql4 = N'
    USE [' + @db4 + N'];
    INSERT INTO #AssessmentResults (Category, DatabaseName, ObjectName, Severity, Issue, Recommendation)
    SELECT DISTINCT
        ''Linked Server Usage'',
        ''' + @db4 + N''',
        QUOTENAME(OBJECT_SCHEMA_NAME(m.object_id)) + ''.'' + QUOTENAME(OBJECT_NAME(m.object_id)),
        ''WARNING'',
        ''Object references linked server via OPENQUERY or four-part name'',
        ''Review and test linked server queries from Azure SQL MI. '' +
        ''Ensure network connectivity from MI VNet to target servers.''
    FROM sys.sql_modules m
    WHERE m.definition LIKE ''%OPENQUERY%''
       OR m.definition LIKE ''%PHARMACY_SERVER%''
       OR m.definition LIKE ''%INSURANCE_CLEARINGHOUSE%''
       OR m.definition LIKE ''%LAB_SYSTEM%''
       OR m.definition LIKE ''%RADIOLOGY_PACS%'';
    ';
    EXEC sp_executesql @sql4;

    FETCH NEXT FROM db_cursor4 INTO @db4;
END

CLOSE db_cursor4;
DEALLOCATE db_cursor4;
GO

-- ============================================
-- 5. TRANSPARENT DATA ENCRYPTION (TDE)
-- Azure SQL MI uses TDE by default. Customer-
-- managed keys require Azure Key Vault setup.
-- ============================================
PRINT '>> Checking TDE configuration...';

INSERT INTO #AssessmentResults (Category, DatabaseName, ObjectName, Severity, Issue, Recommendation)
SELECT
    'Transparent Data Encryption',
    d.name,
    CASE WHEN dek.encryptor_type IS NOT NULL THEN dek.encryptor_type ELSE 'N/A' END,
    CASE
        WHEN d.is_encrypted = 1 AND dek.encryptor_type = 'CERTIFICATE' THEN 'WARNING'
        WHEN d.is_encrypted = 1 AND dek.encryptor_type = 'ASYMMETRIC_KEY' THEN 'WARNING'
        WHEN d.is_encrypted = 0 THEN 'INFO'
        ELSE 'INFO'
    END,
    CASE
        WHEN d.is_encrypted = 1
            THEN 'TDE is ENABLED. Encryptor: ' + ISNULL(dek.encryptor_type, 'N/A') +
                 ', Algorithm: ' + ISNULL(dek.encryption_algorithm_name, 'N/A') +
                 ', State: ' + ISNULL(dek.encryption_state_desc, 'N/A')
        ELSE 'TDE is DISABLED on this database.'
    END,
    CASE
        WHEN d.is_encrypted = 1
            THEN 'Azure SQL MI encrypts all databases with TDE by default (service-managed key). ' +
                 'To use customer-managed keys, configure Azure Key Vault. ' +
                 'Remove on-prem TDE certificate before migration or use matching cert for backup restore.'
        ELSE 'Azure SQL MI will automatically enable TDE with a service-managed key.'
    END
FROM sys.databases d
LEFT JOIN sys.dm_database_encryption_keys dek ON d.database_id = dek.database_id
WHERE d.name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');
GO

-- ============================================
-- 6. SQL AGENT JOBS
-- Azure SQL MI supports SQL Agent with some
-- limitations (no CmdExec, no PowerShell,
-- no SSIS subsystem, no replication subsystem).
-- ============================================
PRINT '>> Checking SQL Agent jobs...';

INSERT INTO #AssessmentResults (Category, DatabaseName, ObjectName, Severity, Issue, Recommendation)
SELECT
    'SQL Agent Job',
    ISNULL(js.database_name, 'msdb'),
    j.name,
    CASE
        WHEN js.subsystem IN ('CmdExec', 'PowerShell') THEN 'BLOCKER'
        WHEN js.subsystem = 'SSIS' THEN 'BLOCKER'
        WHEN js.subsystem = 'ActiveScripting' THEN 'BLOCKER'
        ELSE 'WARNING'
    END,
    'Job [' + j.name + '] Step [' + js.step_name + '] uses subsystem: ' + js.subsystem +
    CASE WHEN js.database_name IS NOT NULL THEN ' (database: ' + js.database_name + ')' ELSE '' END,
    CASE
        WHEN js.subsystem IN ('CmdExec', 'PowerShell')
            THEN 'CmdExec and PowerShell subsystems are NOT supported on Azure SQL MI. ' +
                 'Convert to T-SQL steps, Azure Automation runbooks, or Azure Functions.'
        WHEN js.subsystem = 'SSIS'
            THEN 'SSIS subsystem is NOT supported on Azure SQL MI. ' +
                 'Migrate SSIS packages to Azure Data Factory or Azure-SSIS IR.'
        WHEN js.subsystem = 'ActiveScripting'
            THEN 'ActiveScripting is NOT supported on Azure SQL MI. Convert to T-SQL.'
        WHEN js.subsystem = 'TSQL'
            THEN 'T-SQL job steps are supported on Azure SQL MI. ' +
                 'Review for cross-database or linked server references within the step command.'
        ELSE 'Review subsystem compatibility with Azure SQL MI.'
    END
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobsteps js ON j.job_id = js.job_id
WHERE j.name LIKE 'LMC%'
   OR j.name LIKE 'Lakeview%';

-- Check job schedules
INSERT INTO #AssessmentResults (Category, DatabaseName, ObjectName, Severity, Issue, Recommendation)
SELECT
    'SQL Agent Schedule',
    NULL,
    j.name + ' -> ' + s.name,
    'INFO',
    'Schedule: ' + s.name +
    ' (Freq type: ' + CAST(s.freq_type AS VARCHAR) +
    ', Interval: ' + CAST(s.freq_interval AS VARCHAR) +
    ', Enabled: ' + CAST(s.enabled AS VARCHAR) + ')',
    'SQL Agent schedules are supported on Azure SQL MI. Verify after migration.'
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobschedules jsc ON j.job_id = jsc.job_id
JOIN msdb.dbo.sysschedules s ON jsc.schedule_id = s.schedule_id
WHERE j.name LIKE 'LMC%'
   OR j.name LIKE 'Lakeview%';
GO

-- ============================================
-- 7. UNSUPPORTED FEATURES
-- ============================================
PRINT '>> Checking for unsupported features...';

-- 7a. FILESTREAM / FileTable
DECLARE @db5 NVARCHAR(128);
DECLARE @sql5 NVARCHAR(MAX);

DECLARE db_cursor5 CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

OPEN db_cursor5;
FETCH NEXT FROM db_cursor5 INTO @db5;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql5 = N'
    USE [' + @db5 + N'];
    -- FILESTREAM columns
    INSERT INTO #AssessmentResults (Category, DatabaseName, ObjectName, Severity, Issue, Recommendation)
    SELECT
        ''FILESTREAM'',
        ''' + @db5 + N''',
        QUOTENAME(OBJECT_SCHEMA_NAME(c.object_id)) + ''.'' + QUOTENAME(OBJECT_NAME(c.object_id)) + ''.'' + c.name,
        ''BLOCKER'',
        ''FILESTREAM column detected: '' + OBJECT_NAME(c.object_id) + ''.'' + c.name,
        ''FILESTREAM is NOT supported on Azure SQL MI. Migrate to Azure Blob Storage '' +
        ''and store URLs/references in the database.''
    FROM sys.columns c
    WHERE c.is_filestream = 1;

    -- FileTables
    INSERT INTO #AssessmentResults (Category, DatabaseName, ObjectName, Severity, Issue, Recommendation)
    SELECT
        ''FileTable'',
        ''' + @db5 + N''',
        QUOTENAME(SCHEMA_NAME(t.schema_id)) + ''.'' + QUOTENAME(t.name),
        ''BLOCKER'',
        ''FileTable detected: '' + t.name,
        ''FileTable is NOT supported on Azure SQL MI. Migrate to Azure Blob Storage '' +
        ''with Azure Files or application-level file management.''
    FROM sys.tables t
    WHERE t.is_filetable = 1;
    ';
    EXEC sp_executesql @sql5;

    FETCH NEXT FROM db_cursor5 INTO @db5;
END

CLOSE db_cursor5;
DEALLOCATE db_cursor5;
GO

-- 7b. Database Mail configuration
IF EXISTS (SELECT * FROM msdb.dbo.sysmail_profile)
BEGIN
    INSERT INTO #AssessmentResults (Category, DatabaseName, ObjectName, Severity, Issue, Recommendation)
    SELECT
        'Database Mail',
        NULL,
        p.name,
        'WARNING',
        'Database Mail profile: [' + p.name + '] (ID: ' + CAST(p.profile_id AS VARCHAR) + ')',
        'Database Mail is supported on Azure SQL MI but requires reconfiguration. ' +
        'Set up SMTP relay (e.g., SendGrid, Office 365) accessible from MI VNet.'
    FROM msdb.dbo.sysmail_profile p;
END
GO

-- 7c. TRUSTWORTHY databases
INSERT INTO #AssessmentResults (Category, DatabaseName, ObjectName, Severity, Issue, Recommendation)
SELECT
    'TRUSTWORTHY Database',
    d.name,
    NULL,
    'WARNING',
    'Database [' + d.name + '] has TRUSTWORTHY = ON',
    'TRUSTWORTHY is supported on Azure SQL MI but is a security concern. ' +
    'Review if required for CLR assemblies. Prefer signing assemblies with certificates.'
FROM sys.databases d
WHERE d.name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
  AND d.is_trustworthy_on = 1;
GO

-- 7d. Server-level configurations
INSERT INTO #AssessmentResults (Category, DatabaseName, ObjectName, Severity, Issue, Recommendation)
SELECT
    'Server Configuration',
    NULL,
    c.name,
    CASE
        WHEN c.name = 'clr enabled' AND c.value_in_use = 1 THEN 'WARNING'
        WHEN c.name = 'clr strict security' AND c.value_in_use = 0 THEN 'WARNING'
        WHEN c.name = 'xp_cmdshell' AND c.value_in_use = 1 THEN 'BLOCKER'
        WHEN c.name = 'Ole Automation Procedures' AND c.value_in_use = 1 THEN 'BLOCKER'
        ELSE 'INFO'
    END,
    'Server config [' + c.name + '] = ' + CAST(c.value_in_use AS VARCHAR(20)),
    CASE
        WHEN c.name = 'clr enabled' AND c.value_in_use = 1
            THEN 'CLR is enabled. Azure SQL MI supports CLR but verify assembly permission sets.'
        WHEN c.name = 'clr strict security' AND c.value_in_use = 0
            THEN 'Strict security disabled. Azure SQL MI enforces clr strict security = 1. ' +
                 'Sign assemblies with a certificate.'
        WHEN c.name = 'xp_cmdshell' AND c.value_in_use = 1
            THEN 'xp_cmdshell is NOT supported on Azure SQL MI. ' +
                 'Replace with Azure Automation, Azure Functions, or application logic.'
        WHEN c.name = 'Ole Automation Procedures' AND c.value_in_use = 1
            THEN 'OLE Automation is NOT supported on Azure SQL MI. ' +
                 'Replace with CLR, Azure Functions, or application-level HTTP calls.'
        ELSE 'Review setting for Azure SQL MI compatibility.'
    END
FROM sys.configurations c
WHERE c.name IN (
    'clr enabled', 'clr strict security', 'xp_cmdshell',
    'Ole Automation Procedures', 'remote access', 'remote proc trans',
    'scan for startup procs', 'allow updates'
);
GO

-- 7e. Database compatibility level
INSERT INTO #AssessmentResults (Category, DatabaseName, ObjectName, Severity, Issue, Recommendation)
SELECT
    'Compatibility Level',
    d.name,
    NULL,
    CASE WHEN d.compatibility_level < 100 THEN 'BLOCKER'
         WHEN d.compatibility_level < 130 THEN 'WARNING'
         ELSE 'INFO'
    END,
    'Compatibility level = ' + CAST(d.compatibility_level AS VARCHAR(10)),
    CASE
        WHEN d.compatibility_level < 100
            THEN 'Azure SQL MI requires compatibility level >= 100. Upgrade before migration.'
        WHEN d.compatibility_level < 130
            THEN 'Consider upgrading to 130+ for better query optimizer and feature support.'
        ELSE 'Compatibility level is supported on Azure SQL MI.'
    END
FROM sys.databases d
WHERE d.name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');
GO

-- 7f. Deprecated features and syntax
DECLARE @db6 NVARCHAR(128);
DECLARE @sql6 NVARCHAR(MAX);

DECLARE db_cursor6 CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

OPEN db_cursor6;
FETCH NEXT FROM db_cursor6 INTO @db6;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql6 = N'
    USE [' + @db6 + N'];

    -- Check for deprecated SET options in modules
    INSERT INTO #AssessmentResults (Category, DatabaseName, ObjectName, Severity, Issue, Recommendation)
    SELECT DISTINCT
        ''Deprecated Syntax'',
        ''' + @db6 + N''',
        QUOTENAME(OBJECT_SCHEMA_NAME(m.object_id)) + ''.'' + QUOTENAME(OBJECT_NAME(m.object_id)),
        ''WARNING'',
        ''Object may contain deprecated syntax (RAISERROR old-style, non-ANSI joins, etc.)'',
        ''Review and update deprecated T-SQL syntax for Azure SQL MI compatibility.''
    FROM sys.sql_modules m
    WHERE m.definition LIKE ''%RAISERROR [0-9]%'' ESCAPE ''''
       OR m.definition LIKE ''%*= %''
       OR m.definition LIKE ''% =*%'';
    ';
    EXEC sp_executesql @sql6;

    FETCH NEXT FROM db_cursor6 INTO @db6;
END

CLOSE db_cursor6;
DEALLOCATE db_cursor6;
GO

-- ============================================
-- ASSESSMENT SUMMARY
-- ============================================
PRINT '';
PRINT '================================================================';
PRINT ' ASSESSMENT SUMMARY';
PRINT '================================================================';
PRINT '';

SELECT Severity, COUNT(*) AS IssueCount
FROM #AssessmentResults
GROUP BY Severity
ORDER BY CASE Severity WHEN 'BLOCKER' THEN 1 WHEN 'WARNING' THEN 2 WHEN 'INFO' THEN 3 END;

PRINT '';
PRINT '-- BLOCKERS (must resolve before migration) --';
SELECT
    AssessmentID,
    Category,
    ISNULL(DatabaseName, '(server)') AS [Database],
    ISNULL(ObjectName, '-') AS [Object],
    Issue,
    Recommendation
FROM #AssessmentResults
WHERE Severity = 'BLOCKER'
ORDER BY Category, DatabaseName;

PRINT '';
PRINT '-- WARNINGS (review and plan remediation) --';
SELECT
    AssessmentID,
    Category,
    ISNULL(DatabaseName, '(server)') AS [Database],
    ISNULL(ObjectName, '-') AS [Object],
    Issue,
    Recommendation
FROM #AssessmentResults
WHERE Severity = 'WARNING'
ORDER BY Category, DatabaseName;

PRINT '';
PRINT '-- INFO (informational, no action required) --';
SELECT
    AssessmentID,
    Category,
    ISNULL(DatabaseName, '(server)') AS [Database],
    ISNULL(ObjectName, '-') AS [Object],
    Issue
FROM #AssessmentResults
WHERE Severity = 'INFO'
ORDER BY Category, DatabaseName;

PRINT '';
PRINT '================================================================';
PRINT ' Assessment complete. Review BLOCKER items before migration.';
PRINT '================================================================';

-- Cleanup
DROP TABLE #AssessmentResults;
GO
