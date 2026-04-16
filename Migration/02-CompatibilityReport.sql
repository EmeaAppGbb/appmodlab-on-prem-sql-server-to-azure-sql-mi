-- ============================================
-- Azure SQL MI Compatibility Report
-- Lakeview Medical Center
-- Generates a detailed compatibility report with
-- blockers, warnings, and recommendations
-- ============================================
-- Run against the on-premises SQL Server instance
-- Requires: VIEW SERVER STATE, VIEW ANY DEFINITION
-- ============================================

SET NOCOUNT ON;
GO

PRINT '================================================================';
PRINT ' Lakeview Medical Center - Compatibility Report';
PRINT ' Run Date: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT ' Server  : ' + @@SERVERNAME;
PRINT '================================================================';
PRINT '';
GO

-- ============================================
-- Report staging table
-- ============================================
IF OBJECT_ID('tempdb..#CompatReport') IS NOT NULL
    DROP TABLE #CompatReport;

CREATE TABLE #CompatReport (
    ReportID        INT IDENTITY(1,1),
    Section         NVARCHAR(50)   NOT NULL,
    Category        NVARCHAR(100)  NOT NULL,
    DatabaseName    NVARCHAR(128)  NULL,
    ObjectName      NVARCHAR(256)  NULL,
    Severity        NVARCHAR(20)   NOT NULL,
    Finding         NVARCHAR(1000) NOT NULL,
    Recommendation  NVARCHAR(2000) NULL,
    MigrationPhase  NVARCHAR(50)   NULL,
    EstimatedEffort NVARCHAR(20)   NULL
);
GO

-- ============================================
-- SECTION 1: DATABASE CONFIGURATION BLOCKERS
-- ============================================
PRINT '>> Section 1: Database Configuration...';

-- Compatibility levels
INSERT INTO #CompatReport (Section, Category, DatabaseName, Severity, Finding, Recommendation, MigrationPhase, EstimatedEffort)
SELECT
    'Configuration',
    'Compatibility Level',
    d.name,
    CASE WHEN d.compatibility_level < 100 THEN 'BLOCKER'
         WHEN d.compatibility_level < 130 THEN 'WARNING'
         ELSE 'PASS' END,
    'Database [' + d.name + '] compatibility level: ' + CAST(d.compatibility_level AS VARCHAR(10)) +
    ' (SQL Server ' +
    CASE d.compatibility_level
        WHEN 80  THEN '2000'
        WHEN 90  THEN '2005'
        WHEN 100 THEN '2008'
        WHEN 110 THEN '2012'
        WHEN 120 THEN '2014'
        WHEN 130 THEN '2016'
        WHEN 140 THEN '2017'
        WHEN 150 THEN '2019'
        WHEN 160 THEN '2022'
        ELSE 'Unknown'
    END + ')',
    CASE WHEN d.compatibility_level < 100
        THEN 'REQUIRED: Upgrade compatibility level to at least 100 before migration.'
        WHEN d.compatibility_level < 130
        THEN 'RECOMMENDED: Upgrade to 130+ for Query Store support and modern optimizer.'
        ELSE 'No action needed.'
    END,
    'Pre-Migration',
    CASE WHEN d.compatibility_level < 100 THEN 'Low' ELSE 'Minimal' END
FROM sys.databases d
WHERE d.name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

-- Recovery model
INSERT INTO #CompatReport (Section, Category, DatabaseName, Severity, Finding, Recommendation, MigrationPhase, EstimatedEffort)
SELECT
    'Configuration',
    'Recovery Model',
    d.name,
    CASE WHEN d.recovery_model_desc <> 'FULL' THEN 'WARNING' ELSE 'PASS' END,
    'Database [' + d.name + '] recovery model: ' + d.recovery_model_desc,
    CASE WHEN d.recovery_model_desc <> 'FULL'
        THEN 'Azure SQL MI requires FULL recovery model. Change before migration with: ' +
             'ALTER DATABASE [' + d.name + '] SET RECOVERY FULL;'
        ELSE 'FULL recovery model is compatible.'
    END,
    'Pre-Migration',
    'Low'
FROM sys.databases d
WHERE d.name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

-- Collation check
INSERT INTO #CompatReport (Section, Category, DatabaseName, Severity, Finding, Recommendation, MigrationPhase, EstimatedEffort)
SELECT
    'Configuration',
    'Collation',
    d.name,
    CASE WHEN d.collation_name <> SERVERPROPERTY('Collation') THEN 'WARNING' ELSE 'PASS' END,
    'Database [' + d.name + '] collation: ' + d.collation_name +
    ' (Server: ' + CAST(SERVERPROPERTY('Collation') AS NVARCHAR(128)) + ')',
    'Azure SQL MI default server collation can be specified at creation time. ' +
    'Ensure the MI instance collation matches or plan for collation differences. ' +
    'Database-level collations are preserved during migration.',
    'Pre-Migration',
    CASE WHEN d.collation_name <> SERVERPROPERTY('Collation') THEN 'Medium' ELSE 'Minimal' END
FROM sys.databases d
WHERE d.name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

-- Database size for planning
INSERT INTO #CompatReport (Section, Category, DatabaseName, Severity, Finding, Recommendation, MigrationPhase, EstimatedEffort)
SELECT
    'Configuration',
    'Database Size',
    d.name,
    'INFO',
    'Database [' + d.name + ']: Data files = ' +
    CAST(CAST(SUM(CASE WHEN mf.type = 0 THEN mf.size END) * 8.0 / 1024 AS DECIMAL(10,2)) AS VARCHAR) + ' MB, ' +
    'Log files = ' +
    CAST(CAST(SUM(CASE WHEN mf.type = 1 THEN mf.size END) * 8.0 / 1024 AS DECIMAL(10,2)) AS VARCHAR) + ' MB',
    'Plan Azure SQL MI storage tier based on total size. ' +
    'General Purpose: max 8 TB, Business Critical: max 4 TB. ' +
    'Migration time ~1 hour per 100 GB via online migration.',
    'Planning',
    'N/A'
FROM sys.databases d
JOIN sys.master_files mf ON d.database_id = mf.database_id
WHERE d.name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
GROUP BY d.name;
GO

-- ============================================
-- SECTION 2: CROSS-DATABASE DEPENDENCY ANALYSIS
-- ============================================
PRINT '>> Section 2: Cross-Database Dependencies...';

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
    INSERT INTO #CompatReport (Section, Category, DatabaseName, ObjectName, Severity, Finding, Recommendation, MigrationPhase, EstimatedEffort)
    SELECT
        ''Dependencies'',
        ''Cross-Database Reference'',
        ''' + @db + N''',
        QUOTENAME(OBJECT_SCHEMA_NAME(d.referencing_id)) + ''.'' + QUOTENAME(OBJECT_NAME(d.referencing_id)),
        CASE
            WHEN d.referenced_database_name IN (''PatientDB'', ''BillingDB'', ''SchedulingDB'', ''ReportingDB'')
                THEN ''WARNING''
            ELSE ''BLOCKER''
        END,
        OBJECT_NAME(d.referencing_id) + '' ('' + o.type_desc + '') references '' +
        d.referenced_database_name + ''.'' + ISNULL(d.referenced_schema_name, ''dbo'') + ''.'' + d.referenced_entity_name,
        CASE
            WHEN d.referenced_database_name IN (''PatientDB'', ''BillingDB'', ''SchedulingDB'', ''ReportingDB'')
                THEN ''Cross-database query within the Lakeview system. Supported on Azure SQL MI if all '' +
                     ''databases are on the same instance. Ensure all 4 databases migrate together. '' +
                     ''Long-term: consider consolidating into a single database with schemas.''
            ELSE ''Reference to external database ['' + d.referenced_database_name + ''] requires '' +
                 ''linked server, elastic query, or application-level integration on Azure SQL MI.''
        END,
        ''Pre-Migration'',
        CASE
            WHEN d.referenced_database_name IN (''PatientDB'', ''BillingDB'', ''SchedulingDB'', ''ReportingDB'')
                THEN ''Low''
            ELSE ''High''
        END
    FROM sys.sql_expression_dependencies d
    JOIN sys.objects o ON d.referencing_id = o.object_id
    WHERE d.referenced_database_name IS NOT NULL
      AND d.referenced_database_name <> DB_NAME()
      AND d.referenced_database_name NOT IN (''master'', ''msdb'', ''tempdb'');
    ';
    EXEC sp_executesql @sql;

    FETCH NEXT FROM db_cursor INTO @db;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;
GO

-- ============================================
-- SECTION 3: CLR ASSEMBLY ANALYSIS
-- ============================================
PRINT '>> Section 3: CLR Assemblies...';

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
    INSERT INTO #CompatReport (Section, Category, DatabaseName, ObjectName, Severity, Finding, Recommendation, MigrationPhase, EstimatedEffort)
    SELECT
        ''CLR'',
        ''CLR Assembly'',
        ''' + @db2 + N''',
        a.name,
        CASE a.permission_set_desc
            WHEN ''UNSAFE_ACCESS'' THEN ''BLOCKER''
            WHEN ''EXTERNAL_ACCESS'' THEN ''WARNING''
            ELSE ''PASS''
        END,
        ''Assembly ['' + a.name + '']: Permission = '' + a.permission_set_desc +
        '', CLR version = '' + ISNULL(a.clr_name, ''N/A''),
        CASE a.permission_set_desc
            WHEN ''UNSAFE_ACCESS''
                THEN ''BLOCKER: UNSAFE assemblies not supported. Options: '' + CHAR(13) + CHAR(10) +
                     ''  1. Rewrite CLR functions as T-SQL (preferred for simple logic) '' + CHAR(13) + CHAR(10) +
                     ''  2. Convert to SAFE permission set if possible '' + CHAR(13) + CHAR(10) +
                     ''  3. Sign assembly with certificate and create login with UNSAFE ASSEMBLY permission''
            WHEN ''EXTERNAL_ACCESS''
                THEN ''Sign assembly with certificate, create login from cert, grant UNSAFE ASSEMBLY. '' +
                     ''Review external resource access for MI VNet compatibility.''
            ELSE ''SAFE assemblies work on Azure SQL MI. Deploy using CREATE ASSEMBLY FROM binary (varbinary literal).''
        END,
        CASE a.permission_set_desc
            WHEN ''UNSAFE_ACCESS'' THEN ''Pre-Migration''
            WHEN ''EXTERNAL_ACCESS'' THEN ''Pre-Migration''
            ELSE ''Migration''
        END,
        CASE a.permission_set_desc
            WHEN ''UNSAFE_ACCESS'' THEN ''High''
            WHEN ''EXTERNAL_ACCESS'' THEN ''Medium''
            ELSE ''Low''
        END
    FROM sys.assemblies a
    WHERE a.is_user_defined = 1;

    -- CLR functions detail
    INSERT INTO #CompatReport (Section, Category, DatabaseName, ObjectName, Severity, Finding, Recommendation, MigrationPhase, EstimatedEffort)
    SELECT
        ''CLR'',
        ''CLR Function'',
        ''' + @db2 + N''',
        QUOTENAME(OBJECT_SCHEMA_NAME(o.object_id)) + ''.'' + QUOTENAME(o.name),
        ''INFO'',
        ''CLR '' + LOWER(o.type_desc) + '': '' + o.name +
        '' -> '' + am.assembly_class + ''.'' + am.assembly_method,
        ''Ensure parent assembly migrates successfully. Test function behavior after migration.'',
        ''Post-Migration'',
        ''Low''
    FROM sys.objects o
    JOIN sys.assembly_modules am ON o.object_id = am.object_id
    WHERE o.type IN (''FS'', ''FT'', ''PC'');
    ';
    EXEC sp_executesql @sql2;

    FETCH NEXT FROM db_cursor2 INTO @db2;
END

CLOSE db_cursor2;
DEALLOCATE db_cursor2;
GO

-- ============================================
-- SECTION 4: SERVICE BROKER ANALYSIS
-- ============================================
PRINT '>> Section 4: Service Broker...';

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
    -- Message types
    INSERT INTO #CompatReport (Section, Category, DatabaseName, ObjectName, Severity, Finding, Recommendation, MigrationPhase, EstimatedEffort)
    SELECT
        ''Service Broker'',
        ''Message Type'',
        ''' + @db3 + N''',
        mt.name,
        ''INFO'',
        ''Message type ['' + mt.name + ''] validation: '' + mt.validation_desc,
        ''Message types migrate with the database. No action needed.'',
        ''Migration'',
        ''Minimal''
    FROM sys.service_message_types mt
    WHERE mt.message_type_id > 65535;

    -- Contracts
    INSERT INTO #CompatReport (Section, Category, DatabaseName, ObjectName, Severity, Finding, Recommendation, MigrationPhase, EstimatedEffort)
    SELECT
        ''Service Broker'',
        ''Contract'',
        ''' + @db3 + N''',
        sc.name,
        ''INFO'',
        ''Contract ['' + sc.name + '']'',
        ''Contracts migrate with the database. No action needed.'',
        ''Migration'',
        ''Minimal''
    FROM sys.service_contracts sc
    WHERE sc.service_contract_id > 65535;

    -- Queues with activation
    INSERT INTO #CompatReport (Section, Category, DatabaseName, ObjectName, Severity, Finding, Recommendation, MigrationPhase, EstimatedEffort)
    SELECT
        ''Service Broker'',
        ''Queue Activation'',
        ''' + @db3 + N''',
        q.name,
        CASE WHEN q.is_activation_enabled = 1 THEN ''WARNING'' ELSE ''INFO'' END,
        ''Queue ['' + q.name + ''] activation: '' +
        CASE WHEN q.is_activation_enabled = 1 THEN ''ENABLED (proc: '' + ISNULL(q.activation_procedure, ''N/A'') + '')''
             ELSE ''DISABLED'' END,
        CASE WHEN q.is_activation_enabled = 1
            THEN ''Activation procedures run automatically. Verify they work correctly after migration '' +
                 ''and don''''t reference external resources unavailable from MI VNet.''
            ELSE ''No action needed.''
        END,
        ''Post-Migration'',
        CASE WHEN q.is_activation_enabled = 1 THEN ''Medium'' ELSE ''Minimal'' END
    FROM sys.service_queues q
    WHERE q.is_ms_shipped = 0;

    -- Routes (non-LOCAL are blockers)
    INSERT INTO #CompatReport (Section, Category, DatabaseName, ObjectName, Severity, Finding, Recommendation, MigrationPhase, EstimatedEffort)
    SELECT
        ''Service Broker'',
        ''Route'',
        ''' + @db3 + N''',
        r.name,
        CASE WHEN r.address <> ''LOCAL'' THEN ''BLOCKER'' ELSE ''PASS'' END,
        ''Route ['' + r.name + ''] address: '' + r.address +
        ISNULL('' -> '' + r.remote_service_name, ''''),
        CASE WHEN r.address <> ''LOCAL''
            THEN ''BLOCKER: Cross-instance Service Broker routes not supported. '' +
                 ''Replace with Azure Service Bus for cross-instance/external messaging. '' +
                 ''Estimated effort: redesign messaging layer.''
            ELSE ''LOCAL routes work on Azure SQL MI for same-instance communication.''
        END,
        CASE WHEN r.address <> ''LOCAL'' THEN ''Pre-Migration'' ELSE ''Migration'' END,
        CASE WHEN r.address <> ''LOCAL'' THEN ''High'' ELSE ''Minimal'' END
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
-- SECTION 5: LINKED SERVER ANALYSIS
-- ============================================
PRINT '>> Section 5: Linked Servers...';

INSERT INTO #CompatReport (Section, Category, DatabaseName, ObjectName, Severity, Finding, Recommendation, MigrationPhase, EstimatedEffort)
SELECT
    'Linked Servers',
    'Linked Server Definition',
    NULL,
    s.name,
    CASE
        WHEN s.provider = 'OraOLEDB.Oracle' THEN 'BLOCKER'
        WHEN s.provider NOT IN ('SQLNCLI11', 'MSOLEDBSQL', 'SQLOLEDB') THEN 'BLOCKER'
        ELSE 'WARNING'
    END,
    'Linked server [' + s.name + ']: Provider=' + s.provider +
    ', DataSource=' + ISNULL(s.data_source, 'N/A') +
    ISNULL(', Catalog=' + s.catalog, ''),
    CASE
        WHEN s.name = 'PHARMACY_SERVER'
            THEN 'SQL Server linked server to pharmacy system. On Azure SQL MI: ' +
                 '(1) Ensure PHARMACY_SERVER is reachable from MI VNet via VPN/ExpressRoute, ' +
                 '(2) Update data source to use FQDN or IP, ' +
                 '(3) Consider migrating to MSOLEDBSQL provider.'
        WHEN s.name = 'INSURANCE_CLEARINGHOUSE'
            THEN 'SQL Server linked server to clearinghouse. On Azure SQL MI: ' +
                 '(1) Ensure network path exists from MI VNet, ' +
                 '(2) Consider replacing with API-based integration via Azure Functions.'
        WHEN s.name = 'LAB_SYSTEM'
            THEN 'SQL Server linked server to LIS. Ensure reachable from MI VNet. ' +
                 'Consider Azure Data Factory for batch data movement.'
        WHEN s.name = 'RADIOLOGY_PACS'
            THEN 'BLOCKER: Oracle OLEDB provider not available on Azure SQL MI. ' +
                 'Options: (1) Azure Data Factory with Oracle connector, ' +
                 '(2) Self-hosted Integration Runtime, ' +
                 '(3) Application-level REST API integration, ' +
                 '(4) Oracle-to-Azure SQL replication via GoldenGate/Striim.'
        ELSE 'Review provider compatibility and network connectivity from MI VNet.'
    END,
    'Pre-Migration',
    CASE
        WHEN s.provider = 'OraOLEDB.Oracle' THEN 'High'
        ELSE 'Medium'
    END
FROM sys.servers s
WHERE s.server_id <> 0
  AND s.is_linked = 1;
GO

-- ============================================
-- SECTION 6: SQL AGENT JOB ANALYSIS
-- ============================================
PRINT '>> Section 6: SQL Agent Jobs...';

INSERT INTO #CompatReport (Section, Category, DatabaseName, ObjectName, Severity, Finding, Recommendation, MigrationPhase, EstimatedEffort)
SELECT
    'SQL Agent',
    'Job Step',
    ISNULL(js.database_name, 'msdb'),
    j.name + ' [Step ' + CAST(js.step_id AS VARCHAR) + ': ' + js.step_name + ']',
    CASE
        WHEN js.subsystem IN ('CmdExec', 'PowerShell', 'ActiveScripting') THEN 'BLOCKER'
        WHEN js.subsystem = 'SSIS' THEN 'BLOCKER'
        WHEN js.subsystem = 'TSQL' AND (
            js.command LIKE '%xp_cmdshell%' OR
            js.command LIKE '%OPENROWSET%' OR
            js.command LIKE '%BULK INSERT%FROM%\\%'
        ) THEN 'WARNING'
        ELSE 'PASS'
    END,
    'Job [' + j.name + '] -> Step [' + js.step_name + ']: subsystem=' + js.subsystem +
    CASE WHEN js.database_name IS NOT NULL THEN ', db=' + js.database_name ELSE '' END,
    CASE
        WHEN js.subsystem = 'CmdExec'
            THEN 'CmdExec not supported. Convert to T-SQL or Azure Automation Runbook. ' +
                 'For file operations, use Azure Blob Storage + OPENROWSET.'
        WHEN js.subsystem = 'PowerShell'
            THEN 'PowerShell not supported. Migrate to Azure Automation or Azure Functions.'
        WHEN js.subsystem = 'SSIS'
            THEN 'SSIS not supported. Migrate packages to Azure Data Factory pipelines ' +
                 'or deploy to Azure-SSIS Integration Runtime.'
        WHEN js.subsystem = 'TSQL'
            THEN 'T-SQL steps are supported. Review for: cross-database refs, linked server usage, ' +
                 'file system access, xp_cmdshell calls, BULK INSERT from UNC paths.'
        ELSE 'Review subsystem [' + js.subsystem + '] compatibility.'
    END,
    CASE WHEN js.subsystem IN ('CmdExec', 'PowerShell', 'SSIS') THEN 'Pre-Migration' ELSE 'Post-Migration' END,
    CASE WHEN js.subsystem IN ('CmdExec', 'PowerShell', 'SSIS') THEN 'High' ELSE 'Low' END
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobsteps js ON j.job_id = js.job_id
WHERE j.name LIKE 'LMC%'
   OR j.name LIKE 'Lakeview%';
GO

-- ============================================
-- SECTION 7: SECURITY & AUTHENTICATION
-- ============================================
PRINT '>> Section 7: Security & Authentication...';

-- Windows logins
INSERT INTO #CompatReport (Section, Category, DatabaseName, ObjectName, Severity, Finding, Recommendation, MigrationPhase, EstimatedEffort)
SELECT
    'Security',
    'Windows Login',
    NULL,
    sp.name,
    'WARNING',
    'Windows login: ' + sp.name + ' (type: ' + sp.type_desc + ')',
    'Azure SQL MI supports Windows authentication via Azure AD/Entra ID with Kerberos. ' +
    'Configure Azure AD integration and map Windows accounts to Azure AD identities.'
FROM sys.server_principals sp
WHERE sp.type IN ('U', 'G')  -- Windows login / Windows group
  AND sp.name NOT LIKE 'NT %'
  AND sp.name NOT LIKE 'BUILTIN%';

-- SQL logins used by the lab databases
INSERT INTO #CompatReport (Section, Category, DatabaseName, ObjectName, Severity, Finding, Recommendation, MigrationPhase, EstimatedEffort)
SELECT
    'Security',
    'SQL Login',
    NULL,
    sp.name,
    'INFO',
    'SQL login: ' + sp.name + ' (disabled: ' + CAST(sp.is_disabled AS VARCHAR) + ')',
    'SQL logins are supported on Azure SQL MI. Recreate logins after migration. ' +
    'Consider migrating to Azure AD authentication for better security.'
FROM sys.server_principals sp
WHERE sp.type = 'S'
  AND sp.name NOT IN ('sa', 'public', '##MS_PolicyEventProcessingLogin##',
                       '##MS_PolicyTsqlExecutionLogin##', '##MS_AgentSigningCertificate##');
GO

-- ============================================
-- SECTION 8: TDE & ENCRYPTION
-- ============================================
PRINT '>> Section 8: Encryption...';

INSERT INTO #CompatReport (Section, Category, DatabaseName, Severity, Finding, Recommendation, MigrationPhase, EstimatedEffort)
SELECT
    'Encryption',
    'TDE Status',
    d.name,
    CASE WHEN d.is_encrypted = 1 THEN 'WARNING' ELSE 'INFO' END,
    'Database [' + d.name + '] TDE: ' +
    CASE WHEN d.is_encrypted = 1 THEN 'ENABLED' ELSE 'DISABLED' END,
    CASE WHEN d.is_encrypted = 1
        THEN 'Source TDE must be handled during migration: ' +
             '(1) For backup/restore: export TDE certificate and import to MI, ' +
             '(2) For online migration (DMS): handled automatically. ' +
             'Azure SQL MI uses TDE by default with service-managed or customer-managed keys (Azure Key Vault).'
        ELSE 'No on-prem TDE. Azure SQL MI will enable TDE with service-managed key automatically.'
    END,
    'Migration',
    CASE WHEN d.is_encrypted = 1 THEN 'Medium' ELSE 'Minimal' END
FROM sys.databases d
WHERE d.name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');
GO

-- ============================================
-- GENERATE FINAL REPORT
-- ============================================
PRINT '';
PRINT '================================================================';
PRINT ' COMPATIBILITY REPORT - EXECUTIVE SUMMARY';
PRINT '================================================================';
PRINT '';

-- Summary counts
SELECT
    Severity,
    COUNT(*) AS TotalFindings,
    COUNT(DISTINCT DatabaseName) AS DatabasesAffected
FROM #CompatReport
WHERE Severity <> 'PASS'
GROUP BY Severity
ORDER BY CASE Severity WHEN 'BLOCKER' THEN 1 WHEN 'WARNING' THEN 2 WHEN 'INFO' THEN 3 END;
GO

-- Effort estimate by phase
PRINT '';
PRINT '-- Migration Effort by Phase --';

SELECT
    MigrationPhase,
    Severity,
    COUNT(*) AS Items,
    STRING_AGG(DISTINCT Category, ', ') AS Categories
FROM #CompatReport
WHERE Severity IN ('BLOCKER', 'WARNING')
GROUP BY MigrationPhase, Severity
ORDER BY
    CASE MigrationPhase WHEN 'Planning' THEN 1 WHEN 'Pre-Migration' THEN 2 WHEN 'Migration' THEN 3 WHEN 'Post-Migration' THEN 4 END,
    CASE Severity WHEN 'BLOCKER' THEN 1 WHEN 'WARNING' THEN 2 END;
GO

-- ============================================
-- DETAILED FINDINGS: BLOCKERS
-- ============================================
PRINT '';
PRINT '================================================================';
PRINT ' BLOCKERS - Must Resolve Before Migration';
PRINT '================================================================';

SELECT
    ReportID AS [#],
    Section,
    Category,
    ISNULL(DatabaseName, '(server)') AS [Database],
    ISNULL(ObjectName, '-') AS [Object],
    Finding,
    Recommendation,
    EstimatedEffort AS Effort
FROM #CompatReport
WHERE Severity = 'BLOCKER'
ORDER BY Section, Category, DatabaseName;
GO

-- ============================================
-- DETAILED FINDINGS: WARNINGS
-- ============================================
PRINT '';
PRINT '================================================================';
PRINT ' WARNINGS - Plan Remediation';
PRINT '================================================================';

SELECT
    ReportID AS [#],
    Section,
    Category,
    ISNULL(DatabaseName, '(server)') AS [Database],
    ISNULL(ObjectName, '-') AS [Object],
    Finding,
    Recommendation,
    MigrationPhase AS Phase,
    EstimatedEffort AS Effort
FROM #CompatReport
WHERE Severity = 'WARNING'
ORDER BY
    CASE MigrationPhase WHEN 'Pre-Migration' THEN 1 WHEN 'Migration' THEN 2 WHEN 'Post-Migration' THEN 3 END,
    Section, Category;
GO

-- ============================================
-- DETAILED FINDINGS: INFORMATIONAL
-- ============================================
PRINT '';
PRINT '================================================================';
PRINT ' INFORMATIONAL';
PRINT '================================================================';

SELECT
    ReportID AS [#],
    Section,
    Category,
    ISNULL(DatabaseName, '(server)') AS [Database],
    ISNULL(ObjectName, '-') AS [Object],
    Finding
FROM #CompatReport
WHERE Severity = 'INFO'
ORDER BY Section, Category, DatabaseName;
GO

-- ============================================
-- MIGRATION CHECKLIST
-- ============================================
PRINT '';
PRINT '================================================================';
PRINT ' MIGRATION CHECKLIST';
PRINT '================================================================';
PRINT '';
PRINT ' PRE-MIGRATION:';
PRINT '   [ ] Resolve all BLOCKER items';
PRINT '   [ ] Set all databases to FULL recovery model';
PRINT '   [ ] Upgrade compatibility levels if needed';
PRINT '   [ ] Refactor UNSAFE CLR assemblies or sign with certificate';
PRINT '   [ ] Replace Oracle linked server (RADIOLOGY_PACS)';
PRINT '   [ ] Convert CmdExec/PowerShell job steps to T-SQL';
PRINT '   [ ] Plan VNet connectivity for linked servers';
PRINT '   [ ] Export TDE certificates (if TDE enabled)';
PRINT '';
PRINT ' MIGRATION:';
PRINT '   [ ] Provision Azure SQL MI (match collation, timezone)';
PRINT '   [ ] Configure VNet, NSG, and route tables';
PRINT '   [ ] Migrate all 4 databases to same MI instance';
PRINT '   [ ] Recreate logins and map users';
PRINT '   [ ] Recreate linked servers with updated endpoints';
PRINT '   [ ] Deploy CLR assemblies from binary';
PRINT '   [ ] Recreate SQL Agent jobs';
PRINT '';
PRINT ' POST-MIGRATION:';
PRINT '   [ ] Verify cross-database queries (ReportingDB views)';
PRINT '   [ ] Test Service Broker messaging (PatientDB<->BillingDB)';
PRINT '   [ ] Validate SQL Agent job execution';
PRINT '   [ ] Test linked server connectivity';
PRINT '   [ ] Run application regression tests';
PRINT '   [ ] Verify Database Mail configuration';
PRINT '   [ ] Update connection strings in all applications';
PRINT '';
PRINT '================================================================';
PRINT ' Report complete.';
PRINT '================================================================';

-- Cleanup
DROP TABLE #CompatReport;
GO
