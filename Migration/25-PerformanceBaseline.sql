-- ============================================
-- Step 25 - Performance Baseline on Azure SQL MI
-- Lakeview Medical Center
-- Establishes performance baselines after
-- migration: captures query execution stats,
-- wait stats, index usage, creates missing
-- indexes, updates statistics, and sets up a
-- comparison framework between source and target.
-- ============================================
-- Run against: Azure SQL Managed Instance
-- Requires: VIEW SERVER STATE, ALTER on databases
-- Databases: PatientDB, BillingDB, SchedulingDB,
--            ReportingDB
-- ============================================

SET NOCOUNT ON;
GO

PRINT '================================================================';
PRINT ' Lakeview Medical Center - Performance Baseline (Post-Migration)';
PRINT ' Run Date: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT ' Server  : ' + @@SERVERNAME;
PRINT ' Version : ' + @@VERSION;
PRINT '================================================================';
PRINT '';
GO

-- ============================================
-- Baseline staging tables
-- ============================================
IF OBJECT_ID('tempdb..#PerfBaseline') IS NOT NULL
    DROP TABLE #PerfBaseline;

CREATE TABLE #PerfBaseline (
    BaselineID      INT IDENTITY(1,1),
    Category        NVARCHAR(50),
    MetricName      NVARCHAR(200),
    DatabaseName    NVARCHAR(128)   NULL,
    CurrentValue    NVARCHAR(MAX),
    CapturedAt      DATETIME        DEFAULT GETDATE()
);

IF OBJECT_ID('tempdb..#MissingIndexes') IS NOT NULL
    DROP TABLE #MissingIndexes;

CREATE TABLE #MissingIndexes (
    IndexID         INT IDENTITY(1,1),
    DatabaseName    NVARCHAR(128),
    SchemaName      NVARCHAR(128),
    TableName       NVARCHAR(128),
    EqualityColumns NVARCHAR(4000)  NULL,
    InequalityColumns NVARCHAR(4000) NULL,
    IncludeColumns  NVARCHAR(4000)  NULL,
    UserSeeks       BIGINT,
    UserScans       BIGINT,
    AvgUserImpact   FLOAT,
    CreateStatement NVARCHAR(MAX)
);

IF OBJECT_ID('tempdb..#SourceComparison') IS NOT NULL
    DROP TABLE #SourceComparison;

CREATE TABLE #SourceComparison (
    CompareID       INT IDENTITY(1,1),
    Category        NVARCHAR(50),
    MetricName      NVARCHAR(200),
    DatabaseName    NVARCHAR(128)   NULL,
    SourceValue     NVARCHAR(MAX)   NULL,
    TargetValue     NVARCHAR(MAX)   NULL,
    Delta           NVARCHAR(200)   NULL,
    Status          NVARCHAR(10)    NULL
);
GO

-- ============================================
-- SECTION 1: Query Execution Statistics
-- ============================================
PRINT '========================================';
PRINT ' SECTION 1: QUERY EXECUTION STATISTICS';
PRINT '========================================';
PRINT '';

PRINT '>> 1a. Top 25 queries by total CPU time...';
PRINT '';

SELECT TOP 25
    qs.total_worker_time / 1000                     AS TotalCPU_ms,
    qs.execution_count                              AS Executions,
    qs.total_worker_time / qs.execution_count / 1000 AS AvgCPU_ms,
    qs.total_elapsed_time / 1000                    AS TotalElapsed_ms,
    qs.total_logical_reads                          AS TotalLogicalReads,
    qs.total_logical_reads / qs.execution_count     AS AvgLogicalReads,
    qs.total_logical_writes                         AS TotalLogicalWrites,
    DB_NAME(st.dbid)                                AS DatabaseName,
    OBJECT_NAME(st.objectid, st.dbid)               AS ObjectName,
    SUBSTRING(st.text,
        (qs.statement_start_offset / 2) + 1,
        (CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE qs.statement_end_offset
        END - qs.statement_start_offset) / 2 + 1)  AS QueryText,
    qp.query_plan                                   AS QueryPlan
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
WHERE DB_NAME(st.dbid) IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
ORDER BY qs.total_worker_time DESC;

INSERT INTO #PerfBaseline (Category, MetricName, CurrentValue)
SELECT TOP 25
    'Query Stats',
    'Top CPU - ' + ISNULL(DB_NAME(st.dbid), 'N/A') + '.' + ISNULL(OBJECT_NAME(st.objectid, st.dbid), 'AdHoc'),
    'CPU=' + CAST(qs.total_worker_time / 1000 AS VARCHAR(20)) + 'ms, Exec=' + CAST(qs.execution_count AS VARCHAR(20))
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE DB_NAME(st.dbid) IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
ORDER BY qs.total_worker_time DESC;
GO

PRINT '';
PRINT '>> 1b. Top 25 queries by total logical reads (I/O pressure)...';
PRINT '';

SELECT TOP 25
    qs.total_logical_reads                          AS TotalLogicalReads,
    qs.execution_count                              AS Executions,
    qs.total_logical_reads / qs.execution_count     AS AvgLogicalReads,
    qs.total_worker_time / 1000                     AS TotalCPU_ms,
    DB_NAME(st.dbid)                                AS DatabaseName,
    OBJECT_NAME(st.objectid, st.dbid)               AS ObjectName,
    SUBSTRING(st.text,
        (qs.statement_start_offset / 2) + 1,
        (CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE qs.statement_end_offset
        END - qs.statement_start_offset) / 2 + 1)  AS QueryText
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE DB_NAME(st.dbid) IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
ORDER BY qs.total_logical_reads DESC;
GO

PRINT '';
PRINT '>> 1c. Top 25 queries by execution count (hot queries)...';
PRINT '';

SELECT TOP 25
    qs.execution_count                              AS Executions,
    qs.total_worker_time / 1000                     AS TotalCPU_ms,
    qs.total_worker_time / qs.execution_count / 1000 AS AvgCPU_ms,
    qs.total_logical_reads / qs.execution_count     AS AvgLogicalReads,
    DB_NAME(st.dbid)                                AS DatabaseName,
    OBJECT_NAME(st.objectid, st.dbid)               AS ObjectName,
    SUBSTRING(st.text,
        (qs.statement_start_offset / 2) + 1,
        (CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE qs.statement_end_offset
        END - qs.statement_start_offset) / 2 + 1)  AS QueryText
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE DB_NAME(st.dbid) IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
ORDER BY qs.execution_count DESC;
GO

-- ============================================
-- SECTION 2: Wait Statistics
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 2: WAIT STATISTICS';
PRINT '========================================';
PRINT '';

PRINT '>> 2a. Top wait types by total wait time (excluding idle waits)...';
PRINT '';

SELECT TOP 20
    wait_type                                       AS WaitType,
    waiting_tasks_count                             AS WaitCount,
    wait_time_ms                                    AS TotalWait_ms,
    wait_time_ms / NULLIF(waiting_tasks_count, 0)   AS AvgWait_ms,
    max_wait_time_ms                                AS MaxWait_ms,
    signal_wait_time_ms                             AS SignalWait_ms,
    CAST(100.0 * wait_time_ms
        / SUM(wait_time_ms) OVER () AS DECIMAL(5,2)) AS WaitPct
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    'CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'RESOURCE_QUEUE',
    'SLEEP_TASK', 'SLEEP_SYSTEMTASK', 'SQLTRACE_BUFFER_FLUSH',
    'WAITFOR', 'LOGMGR_QUEUE', 'CHECKPOINT_QUEUE',
    'REQUEST_FOR_DEADLOCK_SEARCH', 'XE_TIMER_EVENT',
    'BROKER_TO_FLUSH', 'BROKER_TASK_STOP', 'CLR_MANUAL_EVENT',
    'CLR_AUTO_EVENT', 'DISPATCHER_QUEUE_SEMAPHORE',
    'FT_IFTS_SCHEDULER_IDLE_WAIT', 'XE_DISPATCHER_WAIT',
    'XE_DISPATCHER_JOIN', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
    'ONDEMAND_TASK_QUEUE', 'BROKER_EVENTHANDLER',
    'SLEEP_BPOOL_FLUSH', 'DIRTY_PAGE_POLL',
    'HADR_FILESTREAM_IOMGR_IOCOMPLETION', 'SP_SERVER_DIAGNOSTICS_SLEEP',
    'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', 'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
    'QDS_ASYNC_QUEUE'
)
AND waiting_tasks_count > 0
ORDER BY wait_time_ms DESC;

INSERT INTO #PerfBaseline (Category, MetricName, CurrentValue)
SELECT TOP 20
    'Wait Stats',
    wait_type,
    'TotalWait=' + CAST(wait_time_ms AS VARCHAR(20)) + 'ms, Count=' + CAST(waiting_tasks_count AS VARCHAR(20))
FROM sys.dm_os_wait_stats
WHERE wait_type NOT IN (
    'CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'RESOURCE_QUEUE',
    'SLEEP_TASK', 'SLEEP_SYSTEMTASK', 'SQLTRACE_BUFFER_FLUSH',
    'WAITFOR', 'LOGMGR_QUEUE', 'CHECKPOINT_QUEUE',
    'REQUEST_FOR_DEADLOCK_SEARCH', 'XE_TIMER_EVENT',
    'BROKER_TO_FLUSH', 'BROKER_TASK_STOP', 'CLR_MANUAL_EVENT',
    'CLR_AUTO_EVENT', 'DISPATCHER_QUEUE_SEMAPHORE',
    'FT_IFTS_SCHEDULER_IDLE_WAIT', 'XE_DISPATCHER_WAIT',
    'XE_DISPATCHER_JOIN', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
    'ONDEMAND_TASK_QUEUE', 'BROKER_EVENTHANDLER',
    'SLEEP_BPOOL_FLUSH', 'DIRTY_PAGE_POLL',
    'HADR_FILESTREAM_IOMGR_IOCOMPLETION', 'SP_SERVER_DIAGNOSTICS_SLEEP',
    'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP', 'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
    'QDS_ASYNC_QUEUE'
)
AND waiting_tasks_count > 0
ORDER BY wait_time_ms DESC;
GO

PRINT '';
PRINT '>> 2b. CPU vs I/O wait breakdown...';
PRINT '';

SELECT
    'CPU (Signal) Waits' AS WaitCategory,
    SUM(signal_wait_time_ms) AS TotalWait_ms,
    CAST(100.0 * SUM(signal_wait_time_ms) / SUM(wait_time_ms) AS DECIMAL(5,2)) AS WaitPct
FROM sys.dm_os_wait_stats
WHERE wait_time_ms > 0
UNION ALL
SELECT
    'Resource (I/O) Waits',
    SUM(wait_time_ms - signal_wait_time_ms),
    CAST(100.0 * SUM(wait_time_ms - signal_wait_time_ms) / SUM(wait_time_ms) AS DECIMAL(5,2))
FROM sys.dm_os_wait_stats
WHERE wait_time_ms > 0;
GO

-- ============================================
-- SECTION 3: Index Usage Statistics
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 3: INDEX USAGE STATISTICS';
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
    PRINT '>> 3a. Index usage for [' + @db + ']...';
    PRINT '';

    SET @sql = N'
    USE [' + @db + N'];
    SELECT TOP 20
        DB_NAME()                               AS DatabaseName,
        s.name + ''.'' + o.name                 AS TableName,
        i.name                                  AS IndexName,
        i.type_desc                             AS IndexType,
        ius.user_seeks                          AS Seeks,
        ius.user_scans                          AS Scans,
        ius.user_lookups                        AS Lookups,
        ius.user_updates                        AS Updates,
        ius.last_user_seek                      AS LastSeek,
        ius.last_user_scan                      AS LastScan,
        CASE
            WHEN ius.user_seeks + ius.user_scans + ius.user_lookups = 0
                 AND ius.user_updates > 0
            THEN ''UNUSED - candidate for removal''
            WHEN ius.user_updates > (ius.user_seeks + ius.user_scans) * 10
            THEN ''HIGH MAINTENANCE - review''
            ELSE ''OK''
        END                                     AS Recommendation
    FROM sys.dm_db_index_usage_stats ius
    INNER JOIN sys.indexes i
        ON ius.object_id = i.object_id AND ius.index_id = i.index_id
    INNER JOIN sys.objects o
        ON i.object_id = o.object_id
    INNER JOIN sys.schemas s
        ON o.schema_id = s.schema_id
    WHERE ius.database_id = DB_ID()
      AND o.is_ms_shipped = 0
      AND i.name IS NOT NULL
    ORDER BY ius.user_seeks + ius.user_scans + ius.user_lookups DESC;
    ';

    EXEC sp_executesql @sql;

    FETCH NEXT FROM db_cursor INTO @db;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;
GO

PRINT '';
PRINT '>> 3b. Unused indexes across all databases...';
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
    SET @sql2 = N'
    USE [' + @db2 + N'];
    SELECT
        DB_NAME()                               AS DatabaseName,
        s.name + ''.'' + o.name                 AS TableName,
        i.name                                  AS IndexName,
        i.type_desc                             AS IndexType,
        ius.user_updates                        AS TotalUpdates,
        ''DROP INDEX ['' + i.name + ''] ON ['' + s.name + ''].['' + o.name + ''];'' AS DropStatement
    FROM sys.dm_db_index_usage_stats ius
    INNER JOIN sys.indexes i
        ON ius.object_id = i.object_id AND ius.index_id = i.index_id
    INNER JOIN sys.objects o
        ON i.object_id = o.object_id
    INNER JOIN sys.schemas s
        ON o.schema_id = s.schema_id
    WHERE ius.database_id = DB_ID()
      AND o.is_ms_shipped = 0
      AND i.type_desc <> ''CLUSTERED''
      AND i.is_primary_key = 0
      AND i.is_unique_constraint = 0
      AND ius.user_seeks = 0
      AND ius.user_scans = 0
      AND ius.user_lookups = 0
      AND ius.user_updates > 100
    ORDER BY ius.user_updates DESC;
    ';

    EXEC sp_executesql @sql2;

    FETCH NEXT FROM db_cursor2 INTO @db2;
END

CLOSE db_cursor2;
DEALLOCATE db_cursor2;
GO

-- ============================================
-- SECTION 4: Missing Index Recommendations
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 4: MISSING INDEX RECOMMENDATIONS';
PRINT '========================================';
PRINT '';

PRINT '>> 4a. Top missing indexes by improvement measure...';
PRINT '';

DECLARE @db3 NVARCHAR(128);
DECLARE @sql3 NVARCHAR(MAX);

DECLARE db_cursor3 CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
      AND state_desc = 'ONLINE';

OPEN db_cursor3;
FETCH NEXT FROM db_cursor3 INTO @db3;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql3 = N'
    USE [' + @db3 + N'];
    INSERT INTO #MissingIndexes (
        DatabaseName, SchemaName, TableName,
        EqualityColumns, InequalityColumns, IncludeColumns,
        UserSeeks, UserScans, AvgUserImpact, CreateStatement
    )
    SELECT TOP 10
        DB_NAME()                                   AS DatabaseName,
        s.name                                      AS SchemaName,
        o.name                                      AS TableName,
        mid.equality_columns,
        mid.inequality_columns,
        mid.included_columns,
        migs.user_seeks,
        migs.user_scans,
        migs.avg_user_impact,
        ''CREATE NONCLUSTERED INDEX [IX_'' + o.name + ''_''
            + REPLACE(REPLACE(REPLACE(ISNULL(mid.equality_columns, ''''), ''['', ''''), '']'', ''''), '', '', ''_'')
            + ''] ON ['' + s.name + ''].['' + o.name + ''] (''
            + ISNULL(mid.equality_columns, '''')
            + CASE WHEN mid.inequality_columns IS NOT NULL
                   THEN '', '' + mid.inequality_columns ELSE '''' END
            + '')''
            + CASE WHEN mid.included_columns IS NOT NULL
                   THEN '' INCLUDE ('' + mid.included_columns + '')'' ELSE '''' END
            + '';''                                  AS CreateStatement
    FROM sys.dm_db_missing_index_groups mig
    INNER JOIN sys.dm_db_missing_index_group_stats migs
        ON mig.index_group_handle = migs.group_handle
    INNER JOIN sys.dm_db_missing_index_details mid
        ON mig.index_handle = mid.index_handle
    INNER JOIN sys.objects o
        ON mid.object_id = o.object_id
    INNER JOIN sys.schemas s
        ON o.schema_id = s.schema_id
    WHERE mid.database_id = DB_ID()
    ORDER BY migs.avg_user_impact * (migs.user_seeks + migs.user_scans) DESC;
    ';

    EXEC sp_executesql @sql3;

    FETCH NEXT FROM db_cursor3 INTO @db3;
END

CLOSE db_cursor3;
DEALLOCATE db_cursor3;

SELECT
    DatabaseName,
    SchemaName + '.' + TableName    AS TableName,
    EqualityColumns,
    InequalityColumns,
    IncludeColumns,
    UserSeeks,
    UserScans,
    CAST(AvgUserImpact AS DECIMAL(5,2)) AS AvgImpactPct,
    CreateStatement
FROM #MissingIndexes
ORDER BY AvgUserImpact * (UserSeeks + UserScans) DESC;
GO

PRINT '';
PRINT '>> 4b. Create missing indexes (review and execute selectively)...';
PRINT '';
PRINT '   NOTE: The CREATE INDEX statements above should be reviewed';
PRINT '   by a DBA before execution. Consider workload patterns and';
PRINT '   index maintenance overhead before adding indexes.';
PRINT '';

-- Uncomment the following block to auto-create top missing indexes:
/*
DECLARE @CreateSQL NVARCHAR(MAX);
DECLARE idx_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT CreateStatement FROM #MissingIndexes
    WHERE AvgUserImpact > 80
    ORDER BY AvgUserImpact * (UserSeeks + UserScans) DESC;

OPEN idx_cursor;
FETCH NEXT FROM idx_cursor INTO @CreateSQL;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT '   Creating: ' + @CreateSQL;
    EXEC sp_executesql @CreateSQL;
    FETCH NEXT FROM idx_cursor INTO @CreateSQL;
END

CLOSE idx_cursor;
DEALLOCATE idx_cursor;
*/
GO

-- ============================================
-- SECTION 5: Update Statistics on All Databases
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 5: UPDATE STATISTICS';
PRINT '========================================';
PRINT '';

DECLARE @db4 NVARCHAR(128);
DECLARE @sql4 NVARCHAR(MAX);
DECLARE @startTime DATETIME;

DECLARE db_cursor4 CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
      AND state_desc = 'ONLINE';

OPEN db_cursor4;
FETCH NEXT FROM db_cursor4 INTO @db4;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @startTime = GETDATE();
    PRINT '>> Updating statistics on [' + @db4 + ']...';

    SET @sql4 = N'USE [' + @db4 + N']; EXEC sp_updatestats;';
    EXEC sp_executesql @sql4;

    PRINT '   Completed in '
        + CAST(DATEDIFF(SECOND, @startTime, GETDATE()) AS VARCHAR(10))
        + ' seconds.';
    PRINT '';

    INSERT INTO #PerfBaseline (Category, MetricName, DatabaseName, CurrentValue)
    VALUES ('Statistics', 'Update Statistics Duration',
            @db4,
            CAST(DATEDIFF(SECOND, @startTime, GETDATE()) AS VARCHAR(10)) + ' seconds');

    FETCH NEXT FROM db_cursor4 INTO @db4;
END

CLOSE db_cursor4;
DEALLOCATE db_cursor4;
GO

-- ============================================
-- SECTION 6: Database Configuration Baseline
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 6: DATABASE CONFIGURATION';
PRINT '========================================';
PRINT '';

PRINT '>> 6a. Database-level configuration settings...';
PRINT '';

SELECT
    d.name                                  AS DatabaseName,
    d.compatibility_level                   AS CompatLevel,
    d.recovery_model_desc                   AS RecoveryModel,
    d.is_auto_create_stats_on               AS AutoCreateStats,
    d.is_auto_update_stats_on               AS AutoUpdateStats,
    d.is_auto_update_stats_async_on         AS AsyncStatsUpdate,
    d.is_query_store_on                     AS QueryStoreOn,
    d.page_verify_option_desc               AS PageVerify,
    d.is_read_committed_snapshot_on         AS RCSI,
    d.is_auto_shrink_on                     AS AutoShrink
FROM sys.databases d
WHERE d.name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

INSERT INTO #PerfBaseline (Category, MetricName, DatabaseName, CurrentValue)
SELECT
    'Configuration',
    'CompatLevel=' + CAST(d.compatibility_level AS VARCHAR(5))
        + ', QS=' + CASE WHEN d.is_query_store_on = 1 THEN 'ON' ELSE 'OFF' END
        + ', RCSI=' + CASE WHEN d.is_read_committed_snapshot_on = 1 THEN 'ON' ELSE 'OFF' END,
    d.name,
    'AutoCreateStats=' + CAST(d.is_auto_create_stats_on AS VARCHAR(1))
        + ', AutoUpdateStats=' + CAST(d.is_auto_update_stats_on AS VARCHAR(1))
        + ', AutoShrink=' + CAST(d.is_auto_shrink_on AS VARCHAR(1))
FROM sys.databases d
WHERE d.name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');
GO

PRINT '';
PRINT '>> 6b. Enabling Query Store (if not already enabled)...';
PRINT '';

DECLARE @db5 NVARCHAR(128);
DECLARE @sql5 NVARCHAR(MAX);

DECLARE db_cursor5 CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases
    WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
      AND state_desc = 'ONLINE'
      AND is_query_store_on = 0;

OPEN db_cursor5;
FETCH NEXT FROM db_cursor5 INTO @db5;

WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT '   Enabling Query Store on [' + @db5 + ']...';

    SET @sql5 = N'ALTER DATABASE [' + @db5 + N'] SET QUERY_STORE = ON (
        OPERATION_MODE = READ_WRITE,
        MAX_STORAGE_SIZE_MB = 1024,
        INTERVAL_LENGTH_MINUTES = 30,
        QUERY_CAPTURE_MODE = AUTO,
        SIZE_BASED_CLEANUP_MODE = AUTO,
        DATA_FLUSH_INTERVAL_SECONDS = 900
    );';
    EXEC sp_executesql @sql5;

    PRINT '   Query Store enabled on [' + @db5 + '].';

    FETCH NEXT FROM db_cursor5 INTO @db5;
END

CLOSE db_cursor5;
DEALLOCATE db_cursor5;
GO

-- ============================================
-- SECTION 7: I/O Performance Baseline
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 7: I/O PERFORMANCE BASELINE';
PRINT '========================================';
PRINT '';

PRINT '>> 7a. File-level I/O latency per database...';
PRINT '';

SELECT
    DB_NAME(vfs.database_id)                        AS DatabaseName,
    mf.name                                         AS LogicalFileName,
    mf.type_desc                                    AS FileType,
    vfs.num_of_reads                                AS Reads,
    vfs.num_of_writes                               AS Writes,
    vfs.num_of_bytes_read / 1048576                 AS ReadMB,
    vfs.num_of_bytes_written / 1048576              AS WriteMB,
    CASE WHEN vfs.num_of_reads > 0
         THEN vfs.io_stall_read_ms / vfs.num_of_reads
         ELSE 0 END                                 AS AvgReadLatency_ms,
    CASE WHEN vfs.num_of_writes > 0
         THEN vfs.io_stall_write_ms / vfs.num_of_writes
         ELSE 0 END                                 AS AvgWriteLatency_ms,
    vfs.io_stall                                    AS TotalIOStall_ms
FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
INNER JOIN sys.master_files mf
    ON vfs.database_id = mf.database_id
   AND vfs.file_id = mf.file_id
WHERE DB_NAME(vfs.database_id) IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
ORDER BY vfs.io_stall DESC;

INSERT INTO #PerfBaseline (Category, MetricName, DatabaseName, CurrentValue)
SELECT
    'I/O Latency',
    mf.name + ' (' + mf.type_desc + ')',
    DB_NAME(vfs.database_id),
    'ReadLatency=' + CAST(
        CASE WHEN vfs.num_of_reads > 0
             THEN vfs.io_stall_read_ms / vfs.num_of_reads
             ELSE 0 END AS VARCHAR(10))
    + 'ms, WriteLatency=' + CAST(
        CASE WHEN vfs.num_of_writes > 0
             THEN vfs.io_stall_write_ms / vfs.num_of_writes
             ELSE 0 END AS VARCHAR(10))
    + 'ms'
FROM sys.dm_io_virtual_file_stats(NULL, NULL) vfs
INNER JOIN sys.master_files mf
    ON vfs.database_id = mf.database_id
   AND vfs.file_id = mf.file_id
WHERE DB_NAME(vfs.database_id) IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');
GO

-- ============================================
-- SECTION 8: Memory and Resource Utilization
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 8: MEMORY & RESOURCE UTILIZATION';
PRINT '========================================';
PRINT '';

PRINT '>> 8a. Buffer pool usage by database...';
PRINT '';

SELECT
    DB_NAME(database_id)                            AS DatabaseName,
    COUNT(*) * 8 / 1024                             AS BufferPoolMB,
    SUM(CASE WHEN is_modified = 1 THEN 1 ELSE 0 END) * 8 / 1024 AS DirtyPagesMB
FROM sys.dm_os_buffer_descriptors
WHERE DB_NAME(database_id) IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
GROUP BY database_id
ORDER BY COUNT(*) DESC;
GO

PRINT '';
PRINT '>> 8b. MI resource utilization (recent)...';
PRINT '';

SELECT TOP 30
    end_time                                        AS SampleTime,
    avg_cpu_percent                                 AS AvgCPU_Pct,
    avg_data_io_percent                             AS AvgDataIO_Pct,
    avg_log_write_percent                           AS AvgLogWrite_Pct,
    avg_memory_usage_percent                        AS AvgMemory_Pct,
    avg_instance_cpu_percent                        AS AvgInstanceCPU_Pct
FROM sys.server_resource_stats
ORDER BY end_time DESC;
GO

-- ============================================
-- SECTION 9: Performance Comparison Framework
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 9: PERFORMANCE COMPARISON FRAMEWORK';
PRINT '========================================';
PRINT '';

PRINT '>> This section defines key metrics to compare between';
PRINT '   source (on-premises) and target (Azure SQL MI).';
PRINT '   Run the source queries on the on-premises server and';
PRINT '   populate the SourceValue column, then compare.';
PRINT '';

INSERT INTO #SourceComparison (Category, MetricName, DatabaseName, TargetValue, Status)
SELECT
    'Database Size',
    'Total Size (MB)',
    d.name,
    CAST((SELECT SUM(size) * 8 / 1024
          FROM sys.master_files mf
          WHERE mf.database_id = d.database_id) AS VARCHAR(20)),
    'BASELINE'
FROM sys.databases d
WHERE d.name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

INSERT INTO #SourceComparison (Category, MetricName, DatabaseName, TargetValue, Status)
SELECT
    'Row Counts',
    s.name + '.' + t.name,
    DB_NAME(),
    CAST(SUM(p.rows) AS VARCHAR(20)),
    'BASELINE'
FROM sys.tables t
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
INNER JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0, 1)
GROUP BY s.name, t.name;

PRINT '>> Comparison framework populated. Update SourceValue with';
PRINT '   on-premises metrics for side-by-side comparison.';
PRINT '';

SELECT
    Category,
    MetricName,
    DatabaseName,
    ISNULL(SourceValue, '-- enter source value --')  AS SourceValue,
    TargetValue,
    Delta,
    Status
FROM #SourceComparison
ORDER BY Category, DatabaseName, MetricName;
GO

-- ============================================
-- SECTION 10: Baseline Summary
-- ============================================
PRINT '';
PRINT '========================================';
PRINT ' SECTION 10: BASELINE SUMMARY';
PRINT '========================================';
PRINT '';

SELECT
    Category,
    MetricName,
    DatabaseName,
    CurrentValue,
    CapturedAt
FROM #PerfBaseline
ORDER BY Category, DatabaseName, MetricName;
GO

PRINT '';
PRINT '================================================================';
PRINT ' Performance baseline capture complete.';
PRINT ' Timestamp: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT '';
PRINT ' Next Steps:';
PRINT '   1. Save these results for future comparison';
PRINT '   2. Review missing index recommendations with DBA';
PRINT '   3. Monitor Query Store for regression detection';
PRINT '   4. Set up Azure Monitor alerts (see 26-MonitoringSetup.ps1)';
PRINT '   5. Schedule regular baseline captures (weekly)';
PRINT '================================================================';
GO

-- Clean up temp tables
DROP TABLE IF EXISTS #PerfBaseline;
DROP TABLE IF EXISTS #MissingIndexes;
DROP TABLE IF EXISTS #SourceComparison;
GO
