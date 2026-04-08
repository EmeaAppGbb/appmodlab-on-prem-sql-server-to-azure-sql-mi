-- ============================================
-- SQL Agent Job: Statistics Update
-- Lakeview Medical Center
-- Runs daily at 3:00 AM
-- ============================================
USE msdb;
GO

IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = N'LMC - Daily Statistics Update')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'LMC - Daily Statistics Update', @delete_unused_schedule = 1;
END
GO

DECLARE @jobId BINARY(16);

EXEC msdb.dbo.sp_add_job 
    @job_name = N'LMC - Daily Statistics Update',
    @enabled = 1,
    @notify_level_eventlog = 0,
    @description = N'Updates statistics on all user tables across PatientDB, BillingDB, and SchedulingDB. Uses SAMPLE 30% on weekdays, FULLSCAN on weekends.',
    @category_name = N'[Uncategorized (Local)]',
    @owner_login_name = N'sa',
    @job_id = @jobId OUTPUT;

-- Step 1: Update PatientDB statistics
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Daily Statistics Update',
    @step_name = N'Update PatientDB Statistics',
    @step_id = 1,
    @subsystem = N'TSQL',
    @command = N'
        -- Use FULLSCAN on weekends, SAMPLE on weekdays
        DECLARE @FullScan BIT = CASE WHEN DATEPART(WEEKDAY, GETDATE()) IN (1, 7) THEN 1 ELSE 0 END;
        EXEC PatientDB.dbo.usp_UpdateStatistics @FullScan = @FullScan;
    ',
    @database_name = N'PatientDB',
    @retry_attempts = 1,
    @retry_interval = 5,
    @on_success_action = 2,
    @on_fail_action = 2;

-- Step 2: Update BillingDB statistics
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Daily Statistics Update',
    @step_name = N'Update BillingDB Statistics',
    @step_id = 2,
    @subsystem = N'TSQL',
    @command = N'
        DECLARE @TableName NVARCHAR(256);
        DECLARE @SQL NVARCHAR(500);
        DECLARE @FullScan BIT = CASE WHEN DATEPART(WEEKDAY, GETDATE()) IN (1, 7) THEN 1 ELSE 0 END;
        
        DECLARE stat_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT QUOTENAME(s.name) + ''.'' + QUOTENAME(t.name)
            FROM sys.tables t
            INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
            WHERE t.is_ms_shipped = 0;
        
        OPEN stat_cursor;
        FETCH NEXT FROM stat_cursor INTO @TableName;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            BEGIN TRY
                IF @FullScan = 1
                    SET @SQL = N''UPDATE STATISTICS '' + @TableName + N'' WITH FULLSCAN'';
                ELSE
                    SET @SQL = N''UPDATE STATISTICS '' + @TableName + N'' WITH SAMPLE 30 PERCENT'';
                EXEC sp_executesql @SQL;
            END TRY
            BEGIN CATCH
                PRINT ''Error on '' + @TableName + '': '' + ERROR_MESSAGE();
            END CATCH
            FETCH NEXT FROM stat_cursor INTO @TableName;
        END
        
        CLOSE stat_cursor;
        DEALLOCATE stat_cursor;
    ',
    @database_name = N'BillingDB',
    @retry_attempts = 1,
    @retry_interval = 5,
    @on_success_action = 2,
    @on_fail_action = 2;

-- Step 3: Update SchedulingDB statistics
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Daily Statistics Update',
    @step_name = N'Update SchedulingDB Statistics',
    @step_id = 3,
    @subsystem = N'TSQL',
    @command = N'
        EXEC sp_updatestats;
        PRINT ''SchedulingDB statistics updated.'';
    ',
    @database_name = N'SchedulingDB',
    @retry_attempts = 0,
    @on_success_action = 1,
    @on_fail_action = 2;

-- Schedule: Daily at 3:00 AM
EXEC msdb.dbo.sp_add_jobschedule 
    @job_name = N'LMC - Daily Statistics Update',
    @name = N'Daily at 3AM',
    @enabled = 1,
    @freq_type = 4,
    @freq_interval = 1,
    @active_start_time = 030000;

PRINT 'SQL Agent Job "LMC - Daily Statistics Update" created.';
GO
