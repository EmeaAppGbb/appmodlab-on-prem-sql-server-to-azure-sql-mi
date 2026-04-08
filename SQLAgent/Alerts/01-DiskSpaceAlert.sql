-- ============================================
-- SQL Agent Alert: Disk Space Monitoring
-- Lakeview Medical Center
-- Alerts when disk space falls below thresholds
-- ============================================
USE msdb;
GO

-- ============================================
-- Create operators for alert notification
-- ============================================
IF NOT EXISTS (SELECT * FROM msdb.dbo.sysoperators WHERE name = N'DBA Team')
BEGIN
    EXEC msdb.dbo.sp_add_operator 
        @name = N'DBA Team',
        @enabled = 1,
        @email_address = N'dba-team@lakeviewmedical.org',
        @pager_address = N'dba-oncall@lakeviewmedical.org';
    PRINT 'Operator "DBA Team" created.';
END
GO

-- ============================================
-- Alert 1: Disk Space Warning (< 20% free)
-- ============================================
IF EXISTS (SELECT * FROM msdb.dbo.sysalerts WHERE name = N'LMC - Disk Space Warning')
    EXEC msdb.dbo.sp_delete_alert @name = N'LMC - Disk Space Warning';
GO

EXEC msdb.dbo.sp_add_alert 
    @name = N'LMC - Disk Space Warning',
    @message_id = 0,
    @severity = 0,
    @enabled = 1,
    @delay_between_responses = 3600,  -- 1 hour between alerts
    @notification_message = N'WARNING: Disk space is below 20% on the SQL Server data drive. Investigate immediately to prevent database growth failures.',
    @performance_condition = N'LogicalDisk|% Free Space|C:|<|20',
    @job_id = 0x0;

EXEC msdb.dbo.sp_add_notification 
    @alert_name = N'LMC - Disk Space Warning',
    @operator_name = N'DBA Team',
    @notification_method = 1;  -- Email

PRINT 'Alert "LMC - Disk Space Warning" created.';
GO

-- ============================================
-- Alert 2: Disk Space Critical (< 10% free)
-- ============================================
IF EXISTS (SELECT * FROM msdb.dbo.sysalerts WHERE name = N'LMC - Disk Space Critical')
    EXEC msdb.dbo.sp_delete_alert @name = N'LMC - Disk Space Critical';
GO

EXEC msdb.dbo.sp_add_alert 
    @name = N'LMC - Disk Space Critical',
    @message_id = 0,
    @severity = 0,
    @enabled = 1,
    @delay_between_responses = 900,  -- 15 minutes between alerts
    @notification_message = N'CRITICAL: Disk space is below 10% on the SQL Server data drive! Immediate action required to prevent database failures.',
    @performance_condition = N'LogicalDisk|% Free Space|C:|<|10',
    @job_id = 0x0;

EXEC msdb.dbo.sp_add_notification 
    @alert_name = N'LMC - Disk Space Critical',
    @operator_name = N'DBA Team',
    @notification_method = 7;  -- Email + Pager + Net Send

PRINT 'Alert "LMC - Disk Space Critical" created.';
GO

-- ============================================
-- Alert 3: Database Error Severity 17-25
-- ============================================
DECLARE @severity INT = 17;
WHILE @severity <= 25
BEGIN
    DECLARE @alertName NVARCHAR(100) = N'LMC - Severity ' + CAST(@severity AS NVARCHAR(2)) + ' Error';
    
    IF EXISTS (SELECT * FROM msdb.dbo.sysalerts WHERE name = @alertName)
        EXEC msdb.dbo.sp_delete_alert @name = @alertName;
    
    EXEC msdb.dbo.sp_add_alert 
        @name = @alertName,
        @message_id = 0,
        @severity = @severity,
        @enabled = 1,
        @delay_between_responses = 300,
        @notification_message = N'A high-severity SQL Server error has occurred. Review error log immediately.',
        @include_event_description_in = 1;
    
    EXEC msdb.dbo.sp_add_notification 
        @alert_name = @alertName,
        @operator_name = N'DBA Team',
        @notification_method = 1;
    
    SET @severity = @severity + 1;
END

PRINT 'Severity 17-25 alerts created.';
GO

-- ============================================
-- Alert 4: Transaction Log Full (Error 9002)
-- ============================================
IF EXISTS (SELECT * FROM msdb.dbo.sysalerts WHERE name = N'LMC - Transaction Log Full')
    EXEC msdb.dbo.sp_delete_alert @name = N'LMC - Transaction Log Full';
GO

EXEC msdb.dbo.sp_add_alert 
    @name = N'LMC - Transaction Log Full',
    @message_id = 9002,
    @severity = 0,
    @enabled = 1,
    @delay_between_responses = 300,
    @notification_message = N'CRITICAL: Transaction log is full. Applications may fail. Run log backup immediately.',
    @include_event_description_in = 1;

EXEC msdb.dbo.sp_add_notification 
    @alert_name = N'LMC - Transaction Log Full',
    @operator_name = N'DBA Team',
    @notification_method = 7;

PRINT 'Alert "LMC - Transaction Log Full" created.';
GO

-- ============================================
-- Alert 5: Blocking Alert (custom check job)
-- ============================================
IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = N'LMC - Blocking Monitor')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'LMC - Blocking Monitor', @delete_unused_schedule = 1;
END
GO

DECLARE @jobId BINARY(16);

EXEC msdb.dbo.sp_add_job 
    @job_name = N'LMC - Blocking Monitor',
    @enabled = 1,
    @notify_level_eventlog = 0,
    @description = N'Checks for blocking chains longer than 30 seconds and logs them.',
    @category_name = N'[Uncategorized (Local)]',
    @owner_login_name = N'sa',
    @job_id = @jobId OUTPUT;

EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Blocking Monitor',
    @step_name = N'Check for Blocking',
    @step_id = 1,
    @subsystem = N'TSQL',
    @command = N'
        IF EXISTS (
            SELECT 1 FROM sys.dm_exec_requests r
            WHERE r.blocking_session_id <> 0
              AND r.wait_time > 30000  -- 30 seconds
        )
        BEGIN
            -- Log blocking details
            INSERT INTO PatientDB.dbo.AuditLog (TableName, RecordID, Action, NewValues, ChangedBy)
            SELECT ''BLOCKING'', r.session_id, ''BLOCKING_DETECTED'',
                   ''Blocked by session '' + CAST(r.blocking_session_id AS VARCHAR) + 
                   '' for '' + CAST(r.wait_time/1000 AS VARCHAR) + ''s. '' +
                   ''Wait type: '' + ISNULL(r.wait_type, ''N/A'') +
                   ''. Command: '' + ISNULL(SUBSTRING(st.text, 1, 200), ''N/A''),
                   ''BlockingMonitor''
            FROM sys.dm_exec_requests r
            CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) st
            WHERE r.blocking_session_id <> 0
              AND r.wait_time > 30000;
            
            -- Send alert email via Database Mail
            DECLARE @body NVARCHAR(MAX) = ''Blocking detected on Lakeview Medical SQL Server.'';
            
            SELECT @body = @body + CHAR(13) + CHAR(10) +
                ''Session '' + CAST(r.session_id AS VARCHAR) + 
                '' blocked by '' + CAST(r.blocking_session_id AS VARCHAR) +
                '' for '' + CAST(r.wait_time/1000 AS VARCHAR) + '' seconds''
            FROM sys.dm_exec_requests r
            WHERE r.blocking_session_id <> 0 AND r.wait_time > 30000;
            
            EXEC msdb.dbo.sp_send_dbmail
                @profile_name = ''DBA Mail Profile'',
                @recipients = ''dba-team@lakeviewmedical.org'',
                @subject = ''[LMC SQL] Blocking Detected'',
                @body = @body;
        END
    ',
    @database_name = N'master',
    @retry_attempts = 0,
    @on_success_action = 1,
    @on_fail_action = 1;

-- Schedule: Every 2 minutes during business hours
EXEC msdb.dbo.sp_add_jobschedule 
    @job_name = N'LMC - Blocking Monitor',
    @name = N'Every 2 Minutes',
    @enabled = 1,
    @freq_type = 4,
    @freq_interval = 1,
    @freq_subday_type = 4,
    @freq_subday_interval = 2,
    @active_start_time = 060000,
    @active_end_time = 220000;

PRINT 'SQL Agent Job "LMC - Blocking Monitor" created.';
GO

PRINT '========================================';
PRINT 'All SQL Agent alerts and monitors created.';
PRINT '========================================';
GO
