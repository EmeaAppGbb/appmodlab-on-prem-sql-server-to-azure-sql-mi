-- ============================================================================
-- Migration Script 14: SQL Agent Job Validation
-- Lakeview Medical Center
--
-- Validates that migrated Agent jobs on Azure SQL MI match the source
-- configuration, including schedules, steps, and execution status.
-- Run this AFTER executing 13-MigrateAgentJobs.sql.
-- ============================================================================
USE msdb;
GO

PRINT '========================================';
PRINT 'SQL Agent Job Migration Validation';
PRINT 'Execution Time: ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT '========================================';
PRINT '';
GO

-- ============================================================================
-- SECTION 1: Verify All Expected Jobs Exist
-- ============================================================================
PRINT '--- Section 1: Job Existence Check ---';
GO

DECLARE @ExpectedJobs TABLE (
    JobName NVARCHAR(128),
    ExpectedEnabled BIT,
    Category NVARCHAR(50)
);

INSERT INTO @ExpectedJobs VALUES 
    (N'LMC - Nightly Billing Batch',    1, N'Business'),
    (N'LMC - Daily Claims Submission',   1, N'Business'),
    (N'LMC - Monthly Data Archival',     1, N'Business'),
    (N'LMC - Daily Statistics Update',   1, N'Maintenance'),
    (N'LMC - Full Database Backup',      0, N'Backup - DISABLED'),
    (N'LMC - Transaction Log Backup',    0, N'Backup - DISABLED'),
    (N'LMC - Blocking Monitor',          1, N'Monitoring');

DECLARE @MissingCount INT = 0;
DECLARE @MismatchCount INT = 0;

SELECT 
    ej.JobName,
    ej.Category,
    CASE WHEN j.job_id IS NOT NULL THEN 'EXISTS' ELSE '*** MISSING ***' END AS [Status],
    ej.ExpectedEnabled AS [Expected Enabled],
    j.enabled AS [Actual Enabled],
    CASE 
        WHEN j.job_id IS NULL THEN '*** JOB NOT FOUND ***'
        WHEN j.enabled <> ej.ExpectedEnabled THEN '*** ENABLED STATE MISMATCH ***'
        ELSE 'OK'
    END AS [Validation]
FROM @ExpectedJobs ej
LEFT JOIN msdb.dbo.sysjobs j ON j.name = ej.JobName
ORDER BY ej.JobName;

SELECT @MissingCount = COUNT(*)
FROM @ExpectedJobs ej
LEFT JOIN msdb.dbo.sysjobs j ON j.name = ej.JobName
WHERE j.job_id IS NULL;

SELECT @MismatchCount = COUNT(*)
FROM @ExpectedJobs ej
INNER JOIN msdb.dbo.sysjobs j ON j.name = ej.JobName
WHERE j.enabled <> ej.ExpectedEnabled;

PRINT '';
IF @MissingCount > 0
    PRINT '*** FAIL: ' + CAST(@MissingCount AS VARCHAR) + ' job(s) missing! ***';
ELSE
    PRINT 'PASS: All 7 expected jobs exist.';

IF @MismatchCount > 0
    PRINT '*** FAIL: ' + CAST(@MismatchCount AS VARCHAR) + ' job(s) have incorrect enabled state! ***';
ELSE
    PRINT 'PASS: All jobs have correct enabled/disabled state.';
GO

-- ============================================================================
-- SECTION 2: Verify Job Step Counts
-- ============================================================================
PRINT '';
PRINT '--- Section 2: Job Step Count Validation ---';
GO

DECLARE @ExpectedSteps TABLE (
    JobName NVARCHAR(128),
    ExpectedStepCount INT
);

INSERT INTO @ExpectedSteps VALUES 
    (N'LMC - Nightly Billing Batch',    3),
    (N'LMC - Daily Claims Submission',   3),
    (N'LMC - Monthly Data Archival',     4),
    (N'LMC - Daily Statistics Update',   3),
    (N'LMC - Full Database Backup',      1),
    (N'LMC - Transaction Log Backup',    1),
    (N'LMC - Blocking Monitor',          1);

SELECT 
    es.JobName,
    es.ExpectedStepCount AS [Expected Steps],
    ISNULL(actual.StepCount, 0) AS [Actual Steps],
    CASE 
        WHEN actual.StepCount IS NULL THEN '*** JOB NOT FOUND ***'
        WHEN actual.StepCount <> es.ExpectedStepCount THEN '*** STEP COUNT MISMATCH ***'
        ELSE 'OK'
    END AS [Validation]
FROM @ExpectedSteps es
LEFT JOIN (
    SELECT j.name AS JobName, COUNT(*) AS StepCount
    FROM msdb.dbo.sysjobs j
    INNER JOIN msdb.dbo.sysjobsteps s ON j.job_id = s.job_id
    GROUP BY j.name
) actual ON actual.JobName = es.JobName
ORDER BY es.JobName;

DECLARE @StepMismatch INT;
SELECT @StepMismatch = COUNT(*)
FROM @ExpectedSteps es
LEFT JOIN (
    SELECT j.name AS JobName, COUNT(*) AS StepCount
    FROM msdb.dbo.sysjobs j
    INNER JOIN msdb.dbo.sysjobsteps s ON j.job_id = s.job_id
    GROUP BY j.name
) actual ON actual.JobName = es.JobName
WHERE ISNULL(actual.StepCount, 0) <> es.ExpectedStepCount;

IF @StepMismatch > 0
    PRINT '*** FAIL: ' + CAST(@StepMismatch AS VARCHAR) + ' job(s) have incorrect step count! ***';
ELSE
    PRINT 'PASS: All jobs have correct step counts.';
GO

-- ============================================================================
-- SECTION 3: Verify Schedules
-- ============================================================================
PRINT '';
PRINT '--- Section 3: Schedule Validation ---';
GO

DECLARE @ExpectedSchedules TABLE (
    JobName NVARCHAR(128),
    ScheduleName NVARCHAR(128),
    FreqType INT,
    FreqInterval INT,
    StartTime INT,
    SubdayType INT,
    SubdayInterval INT
);

INSERT INTO @ExpectedSchedules VALUES 
    (N'LMC - Nightly Billing Batch',   N'Nightly at 2AM',       4, 1, 020000, NULL, NULL),
    (N'LMC - Daily Claims Submission',  N'Morning Claims Run',   4, 1, 060000, NULL, NULL),
    (N'LMC - Daily Claims Submission',  N'Evening Claims Run',   4, 1, 180000, NULL, NULL),
    (N'LMC - Monthly Data Archival',    N'First Sunday Monthly', 32, 1, 010000, NULL, NULL),
    (N'LMC - Daily Statistics Update',  N'Daily at 3AM',         4, 1, 030000, NULL, NULL),
    (N'LMC - Blocking Monitor',         N'Every 2 Minutes',      4, 1, 060000, 4, 2);

SELECT 
    es.JobName,
    es.ScheduleName,
    CASE es.FreqType 
        WHEN 4 THEN 'Daily' 
        WHEN 32 THEN 'Monthly Relative' 
        ELSE CAST(es.FreqType AS VARCHAR) 
    END AS [Expected Frequency],
    STUFF(STUFF(RIGHT('000000' + CAST(es.StartTime AS VARCHAR), 6), 3, 0, ':'), 6, 0, ':') AS [Expected Start],
    CASE 
        WHEN sch.schedule_id IS NULL THEN '*** SCHEDULE MISSING ***'
        WHEN sch.freq_type <> es.FreqType THEN '*** FREQ TYPE MISMATCH ***'
        WHEN sch.active_start_time <> es.StartTime THEN '*** START TIME MISMATCH ***'
        WHEN es.SubdayType IS NOT NULL AND sch.freq_subday_type <> es.SubdayType THEN '*** SUBDAY MISMATCH ***'
        WHEN es.SubdayInterval IS NOT NULL AND sch.freq_subday_interval <> es.SubdayInterval THEN '*** SUBDAY INTERVAL MISMATCH ***'
        ELSE 'OK'
    END AS [Validation]
FROM @ExpectedSchedules es
LEFT JOIN msdb.dbo.sysjobs j ON j.name = es.JobName
LEFT JOIN msdb.dbo.sysjobschedules js ON j.job_id = js.job_id
LEFT JOIN msdb.dbo.sysschedules sch ON js.schedule_id = sch.schedule_id AND sch.name = es.ScheduleName
ORDER BY es.JobName, es.ScheduleName;

DECLARE @SchedFail INT;
SELECT @SchedFail = COUNT(*)
FROM @ExpectedSchedules es
LEFT JOIN msdb.dbo.sysjobs j ON j.name = es.JobName
LEFT JOIN msdb.dbo.sysjobschedules js ON j.job_id = js.job_id
LEFT JOIN msdb.dbo.sysschedules sch ON js.schedule_id = sch.schedule_id AND sch.name = es.ScheduleName
WHERE sch.schedule_id IS NULL;

IF @SchedFail > 0
    PRINT '*** FAIL: ' + CAST(@SchedFail AS VARCHAR) + ' schedule(s) missing! ***';
ELSE
    PRINT 'PASS: All expected schedules exist with correct configuration.';
GO

-- ============================================================================
-- SECTION 4: Verify Job Step Details (database targets and subsystems)
-- ============================================================================
PRINT '';
PRINT '--- Section 4: Job Step Detail Validation ---';
GO

SELECT 
    j.name AS [Job Name],
    s.step_id AS [Step],
    s.step_name AS [Step Name],
    s.subsystem AS [Subsystem],
    s.database_name AS [Target Database],
    s.retry_attempts AS [Retries],
    CASE s.on_success_action 
        WHEN 1 THEN 'Quit Success'
        WHEN 2 THEN 'Quit Failure'
        WHEN 3 THEN 'Next Step'
        WHEN 4 THEN 'Go To Step'
        ELSE CAST(s.on_success_action AS VARCHAR)
    END AS [On Success],
    CASE s.on_fail_action
        WHEN 1 THEN 'Quit Success'
        WHEN 2 THEN 'Quit Failure'
        WHEN 3 THEN 'Next Step'
        WHEN 4 THEN 'Go To Step'
        ELSE CAST(s.on_fail_action AS VARCHAR)
    END AS [On Failure]
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobsteps s ON j.job_id = s.job_id
WHERE j.name LIKE N'LMC -%'
ORDER BY j.name, s.step_id;

-- Check for TSQL subsystem (MI only supports TSQL and SSIS)
DECLARE @NonTSQL INT;
SELECT @NonTSQL = COUNT(*)
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobsteps s ON j.job_id = s.job_id
WHERE j.name LIKE N'LMC -%'
  AND s.subsystem NOT IN (N'TSQL');

IF @NonTSQL > 0
    PRINT '*** WARNING: ' + CAST(@NonTSQL AS VARCHAR) + ' step(s) use non-TSQL subsystem. Verify MI compatibility. ***';
ELSE
    PRINT 'PASS: All job steps use TSQL subsystem (MI-compatible).';
GO

-- ============================================================================
-- SECTION 5: Verify Alerts
-- ============================================================================
PRINT '';
PRINT '--- Section 5: Alert Validation ---';
GO

DECLARE @ExpectedAlerts TABLE (
    AlertName NVARCHAR(128),
    ExpectedSeverity INT,
    ExpectedMessageId INT
);

-- Severity 17-25 alerts
DECLARE @sev INT = 17;
WHILE @sev <= 25
BEGIN
    INSERT INTO @ExpectedAlerts VALUES (N'LMC - Severity ' + CAST(@sev AS NVARCHAR(2)) + ' Error', @sev, 0);
    SET @sev = @sev + 1;
END

-- Message-based alert
INSERT INTO @ExpectedAlerts VALUES (N'LMC - Transaction Log Full', 0, 9002);

SELECT 
    ea.AlertName,
    CASE 
        WHEN a.id IS NULL THEN '*** MISSING ***'
        WHEN a.severity <> ea.ExpectedSeverity THEN '*** SEVERITY MISMATCH ***'
        WHEN a.message_id <> ea.ExpectedMessageId THEN '*** MESSAGE_ID MISMATCH ***'
        WHEN a.enabled <> 1 THEN '*** DISABLED ***'
        ELSE 'OK'
    END AS [Validation],
    a.enabled AS [Enabled],
    CASE WHEN n.alert_id IS NOT NULL THEN 'Yes' ELSE '*** NO NOTIFICATION ***' END AS [Has Notification]
FROM @ExpectedAlerts ea
LEFT JOIN msdb.dbo.sysalerts a ON a.name = ea.AlertName
LEFT JOIN msdb.dbo.sysnotifications n ON a.id = n.alert_id
ORDER BY ea.AlertName;

DECLARE @AlertFail INT;
SELECT @AlertFail = COUNT(*)
FROM @ExpectedAlerts ea
LEFT JOIN msdb.dbo.sysalerts a ON a.name = ea.AlertName
WHERE a.id IS NULL;

IF @AlertFail > 0
    PRINT '*** FAIL: ' + CAST(@AlertFail AS VARCHAR) + ' alert(s) missing! ***';
ELSE
    PRINT 'PASS: All 10 expected alerts exist.';
GO

-- ============================================================================
-- SECTION 6: Verify Operator Configuration
-- ============================================================================
PRINT '';
PRINT '--- Section 6: Operator Validation ---';
GO

SELECT 
    name AS [Operator],
    enabled AS [Enabled],
    email_address AS [Email],
    CASE 
        WHEN enabled = 1 AND email_address IS NOT NULL THEN 'OK'
        WHEN enabled = 0 THEN '*** DISABLED ***'
        WHEN email_address IS NULL THEN '*** NO EMAIL ***'
        ELSE '*** CHECK CONFIG ***'
    END AS [Validation]
FROM msdb.dbo.sysoperators
WHERE name = N'DBA Team';

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysoperators WHERE name = N'DBA Team' AND enabled = 1)
    PRINT '*** FAIL: DBA Team operator missing or disabled! ***';
ELSE
    PRINT 'PASS: DBA Team operator exists and is enabled.';
GO

-- ============================================================================
-- SECTION 7: Test Job Execution (dry run of enabled jobs)
-- ============================================================================
PRINT '';
PRINT '--- Section 7: Job Execution Test ---';
PRINT 'Starting enabled jobs for validation. Monitor via sp_help_jobactivity.';
GO

-- Only test the blocking monitor as it is lightweight and non-destructive
DECLARE @testJobName NVARCHAR(128) = N'LMC - Blocking Monitor';

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = @testJobName AND enabled = 1)
BEGIN
    EXEC msdb.dbo.sp_start_job @job_name = @testJobName;
    PRINT 'Started test execution of "' + @testJobName + '".';
    
    WAITFOR DELAY '00:00:10';
    
    SELECT 
        j.name AS [Job Name],
        CASE ja.run_requested_date 
            WHEN NULL THEN 'Never Run'
            ELSE CONVERT(VARCHAR, ja.run_requested_date, 120)
        END AS [Last Run Requested],
        CASE 
            WHEN ja.run_requested_date IS NOT NULL AND ja.stop_execution_date IS NOT NULL THEN 'Completed'
            WHEN ja.run_requested_date IS NOT NULL AND ja.stop_execution_date IS NULL THEN 'Running'
            ELSE 'Not Started'
        END AS [Status]
    FROM msdb.dbo.sysjobs j
    LEFT JOIN msdb.dbo.sysjobactivity ja ON j.job_id = ja.job_id
    LEFT JOIN msdb.dbo.syssessions sess ON ja.session_id = sess.session_id
    WHERE j.name = @testJobName
      AND sess.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions);
    
    PRINT 'Check job history for execution results:';
    PRINT '  EXEC msdb.dbo.sp_help_jobhistory @job_name = N''' + @testJobName + ''', @mode = N''FULL'';';
END
ELSE
    PRINT 'SKIP: Test job "' + @testJobName + '" not found or disabled.';
GO

-- ============================================================================
-- SECTION 8: Recent Job History Check
-- ============================================================================
PRINT '';
PRINT '--- Section 8: Recent Job Execution History ---';
GO

SELECT 
    j.name AS [Job Name],
    h.step_id AS [Step],
    h.step_name AS [Step Name],
    CASE h.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Cancelled'
        WHEN 4 THEN 'In Progress'
        ELSE 'Unknown'
    END AS [Status],
    msdb.dbo.agent_datetime(h.run_date, h.run_time) AS [Run DateTime],
    STUFF(STUFF(RIGHT('000000' + CAST(h.run_duration AS VARCHAR), 6), 3, 0, ':'), 6, 0, ':') AS [Duration (HH:MM:SS)],
    h.message AS [Message]
FROM msdb.dbo.sysjobhistory h
INNER JOIN msdb.dbo.sysjobs j ON h.job_id = j.job_id
WHERE j.name LIKE N'LMC -%'
  AND msdb.dbo.agent_datetime(h.run_date, h.run_time) >= DATEADD(DAY, -1, GETDATE())
ORDER BY msdb.dbo.agent_datetime(h.run_date, h.run_time) DESC;

PRINT 'If no rows returned, no jobs have run in the last 24 hours (expected for first migration).';
GO

-- ============================================================================
-- SECTION 9: MI Compatibility Checks
-- ============================================================================
PRINT '';
PRINT '--- Section 9: MI Compatibility Verification ---';
GO

-- Check for unsupported features in job step commands
PRINT 'Checking job steps for MI-incompatible patterns...';

DECLARE @IncompatiblePatterns TABLE (Pattern NVARCHAR(100), Description NVARCHAR(200));
INSERT INTO @IncompatiblePatterns VALUES 
    (N'%xp_cmdshell%',        N'xp_cmdshell is restricted on MI'),
    (N'%xp_delete_files%',    N'xp_delete_files is not available on MI'),
    (N'%OPENQUERY%',          N'Linked server OPENQUERY may require reconfiguration'),
    (N'%\\\\%BACKUP-SERVER%', N'UNC path to on-premises backup server is not accessible'),
    (N'%BACKUP DATABASE%',    N'User-initiated BACKUP is not supported on MI (automated)'),
    (N'%BACKUP LOG%',         N'User-initiated LOG BACKUP is not supported on MI (automated)'),
    (N'%RESTORE%',            N'RESTORE operations have restrictions on MI');

SELECT 
    j.name AS [Job Name],
    s.step_name AS [Step Name],
    ip.Description AS [Potential Issue]
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobsteps s ON j.job_id = s.job_id
CROSS JOIN @IncompatiblePatterns ip
WHERE j.name LIKE N'LMC -%'
  AND j.enabled = 1
  AND s.command LIKE ip.Pattern;

DECLARE @IncompatCount INT;
SELECT @IncompatCount = COUNT(*)
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobsteps s ON j.job_id = s.job_id
CROSS JOIN @IncompatiblePatterns ip
WHERE j.name LIKE N'LMC -%'
  AND j.enabled = 1
  AND s.command LIKE ip.Pattern;

IF @IncompatCount > 0
    PRINT '*** WARNING: ' + CAST(@IncompatCount AS VARCHAR) + ' potential MI compatibility issue(s) found in ENABLED jobs! ***';
ELSE
    PRINT 'PASS: No MI-incompatible patterns found in enabled job steps.';
GO

-- ============================================================================
-- SECTION 10: Validation Summary
-- ============================================================================
PRINT '';
PRINT '========================================';
PRINT 'Validation Summary';
PRINT '========================================';
GO

DECLARE @TotalJobs INT, @EnabledJobs INT, @DisabledJobs INT;
DECLARE @TotalAlerts INT, @TotalSchedules INT;

SELECT @TotalJobs = COUNT(*),
       @EnabledJobs = SUM(CASE WHEN enabled = 1 THEN 1 ELSE 0 END),
       @DisabledJobs = SUM(CASE WHEN enabled = 0 THEN 1 ELSE 0 END)
FROM msdb.dbo.sysjobs
WHERE name LIKE N'LMC -%';

SELECT @TotalAlerts = COUNT(*)
FROM msdb.dbo.sysalerts
WHERE name LIKE N'LMC -%';

SELECT @TotalSchedules = COUNT(*)
FROM msdb.dbo.sysjobs j
INNER JOIN msdb.dbo.sysjobschedules js ON j.job_id = js.job_id
WHERE j.name LIKE N'LMC -%';

PRINT 'Total LMC Jobs:       ' + CAST(@TotalJobs AS VARCHAR) + ' (expected: 7)';
PRINT '  Enabled:            ' + CAST(@EnabledJobs AS VARCHAR) + ' (expected: 5)';
PRINT '  Disabled (backups): ' + CAST(@DisabledJobs AS VARCHAR) + ' (expected: 2)';
PRINT 'Total LMC Alerts:     ' + CAST(@TotalAlerts AS VARCHAR) + ' (expected: 10)';
PRINT 'Total Schedules:      ' + CAST(@TotalSchedules AS VARCHAR) + ' (expected: 7)';
PRINT '';

IF @TotalJobs = 7 AND @EnabledJobs = 5 AND @DisabledJobs = 2 AND @TotalAlerts = 10 AND @TotalSchedules = 7
    PRINT '*** ALL VALIDATIONS PASSED ***';
ELSE
    PRINT '*** SOME VALIDATIONS FAILED - Review output above ***';

PRINT '';
PRINT '========================================';
PRINT 'Validation Complete: ' + CONVERT(VARCHAR, GETDATE(), 120);
PRINT '========================================';
GO
