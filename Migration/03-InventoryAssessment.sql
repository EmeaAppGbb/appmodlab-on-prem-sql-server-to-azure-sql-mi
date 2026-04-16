-- ============================================
-- Database Object Inventory Assessment
-- Lakeview Medical Center
-- Inventories all objects across PatientDB,
-- BillingDB, SchedulingDB, and ReportingDB
-- ============================================
-- Run against the on-premises SQL Server instance
-- Requires: VIEW ANY DEFINITION
-- ============================================

SET NOCOUNT ON;
GO

PRINT '================================================================';
PRINT ' Lakeview Medical Center - Database Object Inventory';
PRINT ' Run Date: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT ' Server  : ' + @@SERVERNAME;
PRINT '================================================================';
PRINT '';
GO

-- ============================================
-- Inventory staging tables
-- ============================================
IF OBJECT_ID('tempdb..#ObjectInventory') IS NOT NULL
    DROP TABLE #ObjectInventory;

IF OBJECT_ID('tempdb..#ColumnInventory') IS NOT NULL
    DROP TABLE #ColumnInventory;

IF OBJECT_ID('tempdb..#IndexInventory') IS NOT NULL
    DROP TABLE #IndexInventory;

CREATE TABLE #ObjectInventory (
    InventoryID     INT IDENTITY(1,1),
    DatabaseName    NVARCHAR(128)  NOT NULL,
    SchemaName      NVARCHAR(128)  NOT NULL,
    ObjectName      NVARCHAR(128)  NOT NULL,
    ObjectType      NVARCHAR(60)   NOT NULL,
    ObjectTypeCode  NVARCHAR(10)   NOT NULL,
    CreateDate      DATETIME       NULL,
    ModifyDate      DATETIME       NULL,
    RowCount        BIGINT         NULL,
    SizeMB          DECIMAL(18,2)  NULL,
    HasIdentity     BIT            NULL,
    HasTriggers     BIT            NULL,
    IsEncrypted     BIT            NULL,
    DefinitionLen   INT            NULL
);

CREATE TABLE #ColumnInventory (
    DatabaseName    NVARCHAR(128)  NOT NULL,
    SchemaName      NVARCHAR(128)  NOT NULL,
    TableName       NVARCHAR(128)  NOT NULL,
    ColumnName      NVARCHAR(128)  NOT NULL,
    OrdinalPosition INT            NOT NULL,
    DataType        NVARCHAR(128)  NOT NULL,
    MaxLength       INT            NULL,
    Precision       INT            NULL,
    Scale           INT            NULL,
    IsNullable      BIT            NOT NULL,
    HasDefault      BIT            NOT NULL,
    IsComputed      BIT            NOT NULL,
    IsIdentity      BIT            NOT NULL,
    IsFilestream    BIT            NOT NULL
);

CREATE TABLE #IndexInventory (
    DatabaseName    NVARCHAR(128)  NOT NULL,
    SchemaName      NVARCHAR(128)  NOT NULL,
    TableName       NVARCHAR(128)  NOT NULL,
    IndexName       NVARCHAR(128)  NULL,
    IndexType       NVARCHAR(60)   NOT NULL,
    IsUnique        BIT            NOT NULL,
    IsPrimaryKey    BIT            NOT NULL,
    ColumnCount     INT            NOT NULL,
    IndexColumns    NVARCHAR(MAX)  NULL,
    SizeMB          DECIMAL(18,2)  NULL,
    RowCount        BIGINT         NULL
);
GO

-- ============================================
-- Collect object inventory from each database
-- ============================================
DECLARE @db NVARCHAR(128);
DECLARE @sql NVARCHAR(MAX);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT '>> Inventorying [' + @db + ']...';

    -- ============================================
    -- Objects (tables, views, procs, functions, etc.)
    -- ============================================
    SET @sql = N'
    USE [' + @db + N'];

    INSERT INTO #ObjectInventory (DatabaseName, SchemaName, ObjectName, ObjectType, ObjectTypeCode, CreateDate, ModifyDate, IsEncrypted, DefinitionLen)
    SELECT
        ''' + @db + N''',
        SCHEMA_NAME(o.schema_id),
        o.name,
        o.type_desc,
        o.type,
        o.create_date,
        o.modify_date,
        ISNULL(m.is_encrypted, 0),
        ISNULL(DATALENGTH(m.definition), 0)
    FROM sys.objects o
    LEFT JOIN sys.sql_modules m ON o.object_id = m.object_id
    WHERE o.is_ms_shipped = 0
      AND o.type IN (
          ''U'',   -- User table
          ''V'',   -- View
          ''P'',   -- Stored procedure
          ''FN'',  -- Scalar function
          ''IF'',  -- Inline table-valued function
          ''TF'',  -- Table-valued function
          ''FS'',  -- CLR scalar function
          ''FT'',  -- CLR table-valued function
          ''PC'',  -- CLR stored procedure
          ''TR'',  -- Trigger
          ''SN''   -- Synonym
      );

    -- Update table row counts and sizes
    UPDATE oi SET
        RowCount = ps.row_count,
        SizeMB = ps.reserved_mb
    FROM #ObjectInventory oi
    CROSS APPLY (
        SELECT
            SUM(p.rows) AS row_count,
            CAST(SUM(a.total_pages) * 8.0 / 1024 AS DECIMAL(18,2)) AS reserved_mb
        FROM sys.partitions p
        JOIN sys.allocation_units a ON p.partition_id = a.container_id
        WHERE p.object_id = OBJECT_ID(QUOTENAME(oi.SchemaName) + ''.'' + QUOTENAME(oi.ObjectName))
          AND p.index_id IN (0, 1)
    ) ps
    WHERE oi.DatabaseName = ''' + @db + N'''
      AND oi.ObjectTypeCode = ''U'';

    -- Update HasIdentity flag
    UPDATE oi SET HasIdentity = 1
    FROM #ObjectInventory oi
    WHERE oi.DatabaseName = ''' + @db + N'''
      AND oi.ObjectTypeCode = ''U''
      AND EXISTS (
          SELECT 1 FROM sys.identity_columns ic
          WHERE ic.object_id = OBJECT_ID(QUOTENAME(oi.SchemaName) + ''.'' + QUOTENAME(oi.ObjectName))
      );

    -- Update HasTriggers flag
    UPDATE oi SET HasTriggers = 1
    FROM #ObjectInventory oi
    WHERE oi.DatabaseName = ''' + @db + N'''
      AND oi.ObjectTypeCode = ''U''
      AND EXISTS (
          SELECT 1 FROM sys.triggers tr
          WHERE tr.parent_id = OBJECT_ID(QUOTENAME(oi.SchemaName) + ''.'' + QUOTENAME(oi.ObjectName))
      );
    ';
    EXEC sp_executesql @sql;

    -- ============================================
    -- Column inventory (tables only)
    -- ============================================
    SET @sql = N'
    USE [' + @db + N'];
    INSERT INTO #ColumnInventory
    SELECT
        ''' + @db + N''',
        SCHEMA_NAME(t.schema_id),
        t.name,
        c.name,
        c.column_id,
        TYPE_NAME(c.user_type_id) +
            CASE
                WHEN TYPE_NAME(c.user_type_id) IN (''varchar'', ''nvarchar'', ''char'', ''nchar'', ''varbinary'')
                    THEN ''('' + CASE WHEN c.max_length = -1 THEN ''MAX'' ELSE CAST(c.max_length AS VARCHAR) END + '')''
                WHEN TYPE_NAME(c.user_type_id) IN (''decimal'', ''numeric'')
                    THEN ''('' + CAST(c.precision AS VARCHAR) + '','' + CAST(c.scale AS VARCHAR) + '')''
                ELSE ''''
            END,
        c.max_length,
        c.precision,
        c.scale,
        c.is_nullable,
        CASE WHEN c.default_object_id <> 0 THEN 1 ELSE 0 END,
        c.is_computed,
        c.is_identity,
        c.is_filestream
    FROM sys.tables t
    JOIN sys.columns c ON t.object_id = c.object_id
    WHERE t.is_ms_shipped = 0;
    ';
    EXEC sp_executesql @sql;

    -- ============================================
    -- Index inventory
    -- ============================================
    SET @sql = N'
    USE [' + @db + N'];
    INSERT INTO #IndexInventory
    SELECT
        ''' + @db + N''',
        SCHEMA_NAME(t.schema_id),
        t.name,
        i.name,
        i.type_desc,
        i.is_unique,
        i.is_primary_key,
        (SELECT COUNT(*) FROM sys.index_columns ic2 WHERE ic2.object_id = i.object_id AND ic2.index_id = i.index_id AND ic2.is_included_column = 0),
        STUFF((
            SELECT '', '' + c.name
            FROM sys.index_columns ic
            JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
            WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0
            ORDER BY ic.key_ordinal
            FOR XML PATH('''')
        ), 1, 2, ''''),
        CAST((
            SELECT SUM(a.total_pages) * 8.0 / 1024
            FROM sys.partitions p
            JOIN sys.allocation_units a ON p.partition_id = a.container_id
            WHERE p.object_id = i.object_id AND p.index_id = i.index_id
        ) AS DECIMAL(18,2)),
        (SELECT SUM(p.rows) FROM sys.partitions p WHERE p.object_id = i.object_id AND p.index_id = i.index_id)
    FROM sys.tables t
    JOIN sys.indexes i ON t.object_id = i.object_id
    WHERE t.is_ms_shipped = 0
      AND i.type > 0;
    ';
    EXEC sp_executesql @sql;

    FETCH NEXT FROM db_cursor INTO @db;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;
GO

-- ============================================
-- Additional server-level inventory
-- ============================================
PRINT '>> Inventorying server-level objects...';

-- SQL Agent Jobs
IF OBJECT_ID('tempdb..#AgentJobs') IS NOT NULL
    DROP TABLE #AgentJobs;

SELECT
    j.name AS JobName,
    SUSER_SNAME(j.owner_sid) AS Owner,
    j.enabled AS IsEnabled,
    j.date_created AS CreateDate,
    j.date_modified AS ModifyDate,
    (SELECT COUNT(*) FROM msdb.dbo.sysjobsteps js WHERE js.job_id = j.job_id) AS StepCount,
    (SELECT COUNT(*) FROM msdb.dbo.sysjobschedules jsc WHERE jsc.job_id = j.job_id) AS ScheduleCount,
    CASE WHEN jh.run_status IS NOT NULL
         THEN CASE jh.run_status WHEN 0 THEN 'Failed' WHEN 1 THEN 'Succeeded' WHEN 2 THEN 'Retry' WHEN 3 THEN 'Canceled' ELSE 'Unknown' END
         ELSE 'Never Run'
    END AS LastRunStatus
INTO #AgentJobs
FROM msdb.dbo.sysjobs j
LEFT JOIN (
    SELECT job_id, run_status,
           ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY run_date DESC, run_time DESC) AS rn
    FROM msdb.dbo.sysjobhistory
    WHERE step_id = 0
) jh ON j.job_id = jh.job_id AND jh.rn = 1
WHERE j.name LIKE 'LMC%'
   OR j.name LIKE 'Lakeview%';
GO

-- Linked Servers
IF OBJECT_ID('tempdb..#LinkedServers') IS NOT NULL
    DROP TABLE #LinkedServers;

SELECT
    s.name AS ServerName,
    s.provider AS Provider,
    s.data_source AS DataSource,
    s.catalog AS Catalog,
    s.product AS Product,
    s.is_data_access_enabled AS DataAccess,
    s.is_rpc_enabled AS RPC,
    s.is_rpc_out_enabled AS RPCOut
INTO #LinkedServers
FROM sys.servers s
WHERE s.server_id <> 0
  AND s.is_linked = 1;
GO

-- ============================================
-- REPORT: SUMMARY DASHBOARD
-- ============================================
PRINT '';
PRINT '================================================================';
PRINT ' INVENTORY SUMMARY DASHBOARD';
PRINT '================================================================';
PRINT '';

-- Object counts by database and type
PRINT '-- Object Counts by Database --';
SELECT
    DatabaseName,
    SUM(CASE WHEN ObjectTypeCode = 'U' THEN 1 ELSE 0 END) AS Tables,
    SUM(CASE WHEN ObjectTypeCode = 'V' THEN 1 ELSE 0 END) AS [Views],
    SUM(CASE WHEN ObjectTypeCode = 'P' THEN 1 ELSE 0 END) AS StoredProcs,
    SUM(CASE WHEN ObjectTypeCode IN ('FN','IF','TF') THEN 1 ELSE 0 END) AS Functions,
    SUM(CASE WHEN ObjectTypeCode IN ('FS','FT','PC') THEN 1 ELSE 0 END) AS CLRObjects,
    SUM(CASE WHEN ObjectTypeCode = 'TR' THEN 1 ELSE 0 END) AS Triggers,
    SUM(CASE WHEN ObjectTypeCode = 'SN' THEN 1 ELSE 0 END) AS Synonyms,
    COUNT(*) AS TotalObjects
FROM #ObjectInventory
GROUP BY DatabaseName
ORDER BY DatabaseName;
GO

-- Table sizes
PRINT '';
PRINT '-- Database Size Summary --';
SELECT
    DatabaseName,
    COUNT(*) AS TableCount,
    SUM(ISNULL(RowCount, 0)) AS TotalRows,
    CAST(SUM(ISNULL(SizeMB, 0)) AS DECIMAL(18,2)) AS TotalDataMB,
    CAST(MAX(ISNULL(SizeMB, 0)) AS DECIMAL(18,2)) AS LargestTableMB,
    MAX(CASE WHEN SizeMB = (SELECT MAX(SizeMB) FROM #ObjectInventory oi2 WHERE oi2.DatabaseName = oi.DatabaseName AND oi2.ObjectTypeCode = 'U')
        THEN ObjectName ELSE NULL END) AS LargestTable
FROM #ObjectInventory oi
WHERE ObjectTypeCode = 'U'
GROUP BY DatabaseName
ORDER BY DatabaseName;
GO

-- ============================================
-- REPORT: DETAILED TABLE INVENTORY
-- ============================================
PRINT '';
PRINT '================================================================';
PRINT ' TABLE INVENTORY (All Databases)';
PRINT '================================================================';

SELECT
    DatabaseName AS [Database],
    SchemaName AS [Schema],
    ObjectName AS [Table],
    ISNULL(RowCount, 0) AS [Rows],
    ISNULL(SizeMB, 0) AS [Size MB],
    ISNULL(HasIdentity, 0) AS [Identity],
    ISNULL(HasTriggers, 0) AS [Triggers],
    CreateDate,
    ModifyDate
FROM #ObjectInventory
WHERE ObjectTypeCode = 'U'
ORDER BY DatabaseName, SchemaName, ObjectName;
GO

-- ============================================
-- REPORT: COLUMN DATA TYPE SUMMARY
-- ============================================
PRINT '';
PRINT '================================================================';
PRINT ' COLUMN DATA TYPE DISTRIBUTION';
PRINT '================================================================';

SELECT
    DatabaseName AS [Database],
    DataType,
    COUNT(*) AS ColumnCount,
    COUNT(DISTINCT TableName) AS TablesUsing
FROM #ColumnInventory
GROUP BY DatabaseName, DataType
ORDER BY DatabaseName, COUNT(*) DESC;
GO

-- Special data types that may need attention
PRINT '';
PRINT '-- Columns with Special Data Types --';
SELECT
    DatabaseName AS [Database],
    SchemaName + '.' + TableName + '.' + ColumnName AS [Column],
    DataType,
    CASE
        WHEN IsFilestream = 1 THEN 'FILESTREAM - NOT supported on MI'
        WHEN DataType LIKE '%geography%' THEN 'Spatial type - supported on MI'
        WHEN DataType LIKE '%geometry%' THEN 'Spatial type - supported on MI'
        WHEN DataType LIKE '%hierarchyid%' THEN 'HierarchyID - supported on MI'
        WHEN DataType LIKE '%xml%' THEN 'XML - supported on MI'
        WHEN DataType LIKE '%sql_variant%' THEN 'sql_variant - supported on MI'
        WHEN DataType = 'timestamp' THEN 'timestamp/rowversion - supported on MI'
        ELSE 'Standard type'
    END AS MigrationNote
FROM #ColumnInventory
WHERE DataType IN ('xml', 'geography', 'geometry', 'hierarchyid', 'sql_variant', 'timestamp', 'image', 'text', 'ntext')
   OR IsFilestream = 1
ORDER BY DatabaseName, TableName, ColumnName;
GO

-- ============================================
-- REPORT: VIEWS INVENTORY
-- ============================================
PRINT '';
PRINT '================================================================';
PRINT ' VIEW INVENTORY';
PRINT '================================================================';

SELECT
    DatabaseName AS [Database],
    SchemaName AS [Schema],
    ObjectName AS [View],
    IsEncrypted AS Encrypted,
    DefinitionLen AS [Def Length],
    CreateDate,
    ModifyDate
FROM #ObjectInventory
WHERE ObjectTypeCode = 'V'
ORDER BY DatabaseName, SchemaName, ObjectName;
GO

-- ============================================
-- REPORT: STORED PROCEDURE INVENTORY
-- ============================================
PRINT '';
PRINT '================================================================';
PRINT ' STORED PROCEDURE INVENTORY';
PRINT '================================================================';

SELECT
    DatabaseName AS [Database],
    SchemaName AS [Schema],
    ObjectName AS [Procedure],
    ObjectType AS Type,
    IsEncrypted AS Encrypted,
    DefinitionLen AS [Def Length],
    CreateDate,
    ModifyDate
FROM #ObjectInventory
WHERE ObjectTypeCode IN ('P', 'PC')
ORDER BY DatabaseName, SchemaName, ObjectName;
GO

-- ============================================
-- REPORT: FUNCTION INVENTORY
-- ============================================
PRINT '';
PRINT '================================================================';
PRINT ' FUNCTION INVENTORY';
PRINT '================================================================';

SELECT
    DatabaseName AS [Database],
    SchemaName AS [Schema],
    ObjectName AS [Function],
    ObjectType AS Type,
    ObjectTypeCode AS TypeCode,
    IsEncrypted AS Encrypted,
    DefinitionLen AS [Def Length],
    CreateDate,
    ModifyDate
FROM #ObjectInventory
WHERE ObjectTypeCode IN ('FN', 'IF', 'TF', 'FS', 'FT')
ORDER BY DatabaseName, SchemaName, ObjectName;
GO

-- ============================================
-- REPORT: INDEX INVENTORY
-- ============================================
PRINT '';
PRINT '================================================================';
PRINT ' INDEX INVENTORY';
PRINT '================================================================';

SELECT
    DatabaseName AS [Database],
    SchemaName + '.' + TableName AS [Table],
    ISNULL(IndexName, '(HEAP)') AS [Index],
    IndexType AS Type,
    IsUnique AS [Unique],
    IsPrimaryKey AS PK,
    ColumnCount AS [Key Cols],
    IndexColumns AS [Columns],
    ISNULL(SizeMB, 0) AS [Size MB],
    ISNULL(RowCount, 0) AS [Rows]
FROM #IndexInventory
ORDER BY DatabaseName, TableName, IsPrimaryKey DESC, IndexName;
GO

-- Index summary
PRINT '';
PRINT '-- Index Summary by Database --';
SELECT
    DatabaseName AS [Database],
    COUNT(*) AS TotalIndexes,
    SUM(CASE WHEN IsPrimaryKey = 1 THEN 1 ELSE 0 END) AS PKs,
    SUM(CASE WHEN IsUnique = 1 AND IsPrimaryKey = 0 THEN 1 ELSE 0 END) AS UniqueIndexes,
    SUM(CASE WHEN IndexType = 'CLUSTERED' AND IsPrimaryKey = 0 THEN 1 ELSE 0 END) AS ClusteredNonPK,
    SUM(CASE WHEN IndexType = 'NONCLUSTERED' THEN 1 ELSE 0 END) AS Nonclustered,
    CAST(SUM(ISNULL(SizeMB, 0)) AS DECIMAL(18,2)) AS TotalIndexSizeMB
FROM #IndexInventory
GROUP BY DatabaseName
ORDER BY DatabaseName;
GO

-- ============================================
-- REPORT: TRIGGER INVENTORY
-- ============================================
PRINT '';
PRINT '================================================================';
PRINT ' TRIGGER INVENTORY';
PRINT '================================================================';

SELECT
    DatabaseName AS [Database],
    SchemaName AS [Schema],
    ObjectName AS [Trigger],
    IsEncrypted AS Encrypted,
    CreateDate,
    ModifyDate
FROM #ObjectInventory
WHERE ObjectTypeCode = 'TR'
ORDER BY DatabaseName, SchemaName, ObjectName;
GO

-- ============================================
-- REPORT: SQL AGENT JOBS
-- ============================================
PRINT '';
PRINT '================================================================';
PRINT ' SQL AGENT JOB INVENTORY';
PRINT '================================================================';

SELECT * FROM #AgentJobs ORDER BY JobName;
GO

-- ============================================
-- REPORT: LINKED SERVERS
-- ============================================
PRINT '';
PRINT '================================================================';
PRINT ' LINKED SERVER INVENTORY';
PRINT '================================================================';

SELECT * FROM #LinkedServers ORDER BY ServerName;
GO

-- ============================================
-- REPORT: CONSTRAINT INVENTORY
-- ============================================
PRINT '';
PRINT '================================================================';
PRINT ' CONSTRAINT INVENTORY';
PRINT '================================================================';

DECLARE @db2 NVARCHAR(128);
DECLARE @sql2 NVARCHAR(MAX);

IF OBJECT_ID('tempdb..#Constraints') IS NOT NULL
    DROP TABLE #Constraints;

CREATE TABLE #Constraints (
    DatabaseName    NVARCHAR(128),
    SchemaName      NVARCHAR(128),
    TableName       NVARCHAR(128),
    ConstraintName  NVARCHAR(128),
    ConstraintType  NVARCHAR(30)
);

DECLARE db_cursor2 CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

OPEN db_cursor2;
FETCH NEXT FROM db_cursor2 INTO @db2;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql2 = N'
    USE [' + @db2 + N'];
    INSERT INTO #Constraints
    SELECT
        ''' + @db2 + N''',
        SCHEMA_NAME(t.schema_id),
        t.name,
        kc.name,
        kc.type_desc
    FROM sys.key_constraints kc
    JOIN sys.tables t ON kc.parent_object_id = t.object_id;

    INSERT INTO #Constraints
    SELECT
        ''' + @db2 + N''',
        SCHEMA_NAME(t.schema_id),
        t.name,
        fk.name,
        ''FOREIGN_KEY_CONSTRAINT''
    FROM sys.foreign_keys fk
    JOIN sys.tables t ON fk.parent_object_id = t.object_id;

    INSERT INTO #Constraints
    SELECT
        ''' + @db2 + N''',
        SCHEMA_NAME(t.schema_id),
        t.name,
        cc.name,
        ''CHECK_CONSTRAINT''
    FROM sys.check_constraints cc
    JOIN sys.tables t ON cc.parent_object_id = t.object_id;

    INSERT INTO #Constraints
    SELECT
        ''' + @db2 + N''',
        SCHEMA_NAME(t.schema_id),
        t.name,
        dc.name,
        ''DEFAULT_CONSTRAINT''
    FROM sys.default_constraints dc
    JOIN sys.tables t ON dc.parent_object_id = t.object_id;
    ';
    EXEC sp_executesql @sql2;

    FETCH NEXT FROM db_cursor2 INTO @db2;
END

CLOSE db_cursor2;
DEALLOCATE db_cursor2;

-- Constraint summary
SELECT
    DatabaseName AS [Database],
    SUM(CASE WHEN ConstraintType = 'PRIMARY_KEY_CONSTRAINT' THEN 1 ELSE 0 END) AS PKs,
    SUM(CASE WHEN ConstraintType = 'UNIQUE_CONSTRAINT' THEN 1 ELSE 0 END) AS [Unique],
    SUM(CASE WHEN ConstraintType = 'FOREIGN_KEY_CONSTRAINT' THEN 1 ELSE 0 END) AS FKs,
    SUM(CASE WHEN ConstraintType = 'CHECK_CONSTRAINT' THEN 1 ELSE 0 END) AS [Check],
    SUM(CASE WHEN ConstraintType = 'DEFAULT_CONSTRAINT' THEN 1 ELSE 0 END) AS [Default],
    COUNT(*) AS Total
FROM #Constraints
GROUP BY DatabaseName
ORDER BY DatabaseName;
GO

-- ============================================
-- REPORT: GRAND TOTALS
-- ============================================
PRINT '';
PRINT '================================================================';
PRINT ' GRAND TOTALS';
PRINT '================================================================';

SELECT
    (SELECT COUNT(*) FROM #ObjectInventory) AS TotalObjects,
    (SELECT COUNT(*) FROM #ObjectInventory WHERE ObjectTypeCode = 'U') AS TotalTables,
    (SELECT COUNT(*) FROM #ColumnInventory) AS TotalColumns,
    (SELECT COUNT(*) FROM #IndexInventory) AS TotalIndexes,
    (SELECT COUNT(*) FROM #Constraints) AS TotalConstraints,
    (SELECT COUNT(*) FROM #AgentJobs) AS AgentJobs,
    (SELECT COUNT(*) FROM #LinkedServers) AS LinkedServers,
    (SELECT CAST(SUM(ISNULL(SizeMB, 0)) AS DECIMAL(18,2)) FROM #ObjectInventory WHERE ObjectTypeCode = 'U') AS TotalDataMB;
GO

PRINT '';
PRINT '================================================================';
PRINT ' Inventory assessment complete.';
PRINT '================================================================';

-- Cleanup
DROP TABLE #ObjectInventory;
DROP TABLE #ColumnInventory;
DROP TABLE #IndexInventory;
DROP TABLE #AgentJobs;
DROP TABLE #LinkedServers;
DROP TABLE #Constraints;
GO
