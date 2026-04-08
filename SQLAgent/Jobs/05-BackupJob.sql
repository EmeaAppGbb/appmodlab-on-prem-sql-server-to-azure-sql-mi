-- ============================================
-- SQL Agent Job: Database Backup
-- Lakeview Medical Center
-- Full backup daily at 11 PM, differential every 4 hours,
-- transaction log every 15 minutes
-- ============================================
USE msdb;
GO

-- ============================================
-- JOB 1: Full Backup (Nightly)
-- ============================================
IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = N'LMC - Full Database Backup')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'LMC - Full Database Backup', @delete_unused_schedule = 1;
END
GO

DECLARE @jobId BINARY(16);

EXEC msdb.dbo.sp_add_job 
    @job_name = N'LMC - Full Database Backup',
    @enabled = 1,
    @notify_level_eventlog = 2,
    @notify_level_email = 2,
    @description = N'Full backup of PatientDB, BillingDB, SchedulingDB, and ReportingDB. Backups stored on network share with 30-day retention.',
    @category_name = N'Database Maintenance',
    @owner_login_name = N'sa',
    @job_id = @jobId OUTPUT;

-- Step 1: Full backup of all databases
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Full Database Backup',
    @step_name = N'Full Backup All Databases',
    @step_id = 1,
    @subsystem = N'TSQL',
    @command = N'
        DECLARE @BackupPath NVARCHAR(500) = N''\\BACKUP-SERVER\SQLBackups\LakeviewMedical\'';
        DECLARE @DateSuffix NVARCHAR(20) = FORMAT(GETDATE(), ''yyyyMMdd_HHmmss'');
        DECLARE @BackupFile NVARCHAR(500);
        DECLARE @DatabaseName NVARCHAR(128);
        
        -- Legacy: cursor over database list
        DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT name FROM sys.databases 
            WHERE name IN (''PatientDB'', ''BillingDB'', ''SchedulingDB'', ''ReportingDB'')
            ORDER BY name;
        
        OPEN db_cursor;
        FETCH NEXT FROM db_cursor INTO @DatabaseName;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @BackupFile = @BackupPath + @DatabaseName + ''\'' + @DatabaseName + ''_FULL_'' + @DateSuffix + ''.bak'';
            
            BEGIN TRY
                BACKUP DATABASE @DatabaseName
                TO DISK = @BackupFile
                WITH 
                    COMPRESSION,
                    CHECKSUM,
                    STATS = 10,
                    FORMAT,
                    INIT,
                    NAME = @DatabaseName,
                    DESCRIPTION = ''Full backup'';
                
                -- Verify backup
                RESTORE VERIFYONLY FROM DISK = @BackupFile WITH CHECKSUM;
                
                PRINT ''Full backup completed and verified: '' + @DatabaseName;
            END TRY
            BEGIN CATCH
                PRINT ''ERROR backing up '' + @DatabaseName + '': '' + ERROR_MESSAGE();
                -- Continue to next database even on error
            END CATCH
            
            FETCH NEXT FROM db_cursor INTO @DatabaseName;
        END
        
        CLOSE db_cursor;
        DEALLOCATE db_cursor;
    ',
    @database_name = N'master',
    @retry_attempts = 2,
    @retry_interval = 15,
    @on_success_action = 2,
    @on_fail_action = 2;

-- Step 2: Cleanup old backups (30 days)
EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Full Database Backup',
    @step_name = N'Cleanup Old Backups',
    @step_id = 2,
    @subsystem = N'TSQL',
    @command = N'
        DECLARE @CleanupDate DATETIME = DATEADD(DAY, -30, GETDATE());
        
        -- Clean up old full backups
        EXEC xp_delete_files N''\\BACKUP-SERVER\SQLBackups\LakeviewMedical\PatientDB\'', N''bak'', @CleanupDate;
        EXEC xp_delete_files N''\\BACKUP-SERVER\SQLBackups\LakeviewMedical\BillingDB\'', N''bak'', @CleanupDate;
        EXEC xp_delete_files N''\\BACKUP-SERVER\SQLBackups\LakeviewMedical\SchedulingDB\'', N''bak'', @CleanupDate;
        EXEC xp_delete_files N''\\BACKUP-SERVER\SQLBackups\LakeviewMedical\ReportingDB\'', N''bak'', @CleanupDate;
        
        PRINT ''Old backup files cleaned up (older than 30 days).'';
    ',
    @database_name = N'master',
    @retry_attempts = 0,
    @on_success_action = 1,
    @on_fail_action = 2;

-- Schedule: Daily at 11:00 PM
EXEC msdb.dbo.sp_add_jobschedule 
    @job_name = N'LMC - Full Database Backup',
    @name = N'Nightly Full Backup',
    @enabled = 1,
    @freq_type = 4,
    @freq_interval = 1,
    @active_start_time = 230000;

PRINT 'SQL Agent Job "LMC - Full Database Backup" created.';
GO

-- ============================================
-- JOB 2: Transaction Log Backup (Every 15 minutes)
-- ============================================
IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = N'LMC - Transaction Log Backup')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'LMC - Transaction Log Backup', @delete_unused_schedule = 1;
END
GO

DECLARE @jobId2 BINARY(16);

EXEC msdb.dbo.sp_add_job 
    @job_name = N'LMC - Transaction Log Backup',
    @enabled = 1,
    @notify_level_eventlog = 2,
    @description = N'Transaction log backup every 15 minutes for PatientDB, BillingDB, and SchedulingDB (FULL recovery model databases).',
    @category_name = N'Database Maintenance',
    @owner_login_name = N'sa',
    @job_id = @jobId2 OUTPUT;

EXEC msdb.dbo.sp_add_jobstep 
    @job_name = N'LMC - Transaction Log Backup',
    @step_name = N'Backup Transaction Logs',
    @step_id = 1,
    @subsystem = N'TSQL',
    @command = N'
        DECLARE @BackupPath NVARCHAR(500) = N''\\BACKUP-SERVER\SQLBackups\LakeviewMedical\'';
        DECLARE @DateSuffix NVARCHAR(20) = FORMAT(GETDATE(), ''yyyyMMdd_HHmmss'');
        DECLARE @BackupFile NVARCHAR(500);
        DECLARE @DatabaseName NVARCHAR(128);
        
        DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT name FROM sys.databases 
            WHERE name IN (''PatientDB'', ''BillingDB'', ''SchedulingDB'')
              AND recovery_model_desc = ''FULL''
            ORDER BY name;
        
        OPEN db_cursor;
        FETCH NEXT FROM db_cursor INTO @DatabaseName;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @BackupFile = @BackupPath + @DatabaseName + ''\'' + @DatabaseName + ''_LOG_'' + @DateSuffix + ''.trn'';
            
            BEGIN TRY
                BACKUP LOG @DatabaseName
                TO DISK = @BackupFile
                WITH 
                    COMPRESSION,
                    STATS = 10,
                    NOFORMAT,
                    INIT;
                
                PRINT ''Log backup completed: '' + @DatabaseName;
            END TRY
            BEGIN CATCH
                PRINT ''ERROR backing up log for '' + @DatabaseName + '': '' + ERROR_MESSAGE();
            END CATCH
            
            FETCH NEXT FROM db_cursor INTO @DatabaseName;
        END
        
        CLOSE db_cursor;
        DEALLOCATE db_cursor;
    ',
    @database_name = N'master',
    @retry_attempts = 1,
    @retry_interval = 2,
    @on_success_action = 1,
    @on_fail_action = 2;

-- Schedule: Every 15 minutes, 24/7
EXEC msdb.dbo.sp_add_jobschedule 
    @job_name = N'LMC - Transaction Log Backup',
    @name = N'Every 15 Minutes',
    @enabled = 1,
    @freq_type = 4,           -- Daily
    @freq_interval = 1,
    @freq_subday_type = 4,    -- Minutes
    @freq_subday_interval = 15,
    @active_start_time = 0,
    @active_end_time = 235959;

PRINT 'SQL Agent Job "LMC - Transaction Log Backup" created.';
GO
