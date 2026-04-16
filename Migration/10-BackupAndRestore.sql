-- ============================================
-- Full Backup and Restore for Online Migration
-- Lakeview Medical Center
-- Takes full backups of all 4 databases on the
-- on-premises SQL Server 2016 to a network share
-- with compression and checksum, then restores
-- them on Azure SQL Managed Instance using
-- RESTORE WITH NORECOVERY for online migration.
-- ============================================
-- Part 1: Run against the on-premises SQL Server
-- Part 2: Run against the Azure SQL MI target
-- Requires: sysadmin or db_backupoperator (source)
--           sysadmin (target MI)
-- Databases: PatientDB, BillingDB, SchedulingDB,
--            ReportingDB
-- ============================================

SET NOCOUNT ON;
GO

PRINT '================================================================';
PRINT ' Lakeview Medical Center - Full Backup & Restore (Online Migration)';
PRINT ' Run Date: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT ' Server  : ' + @@SERVERNAME;
PRINT ' Version : ' + @@VERSION;
PRINT '================================================================';
PRINT '';
GO

-- ============================================
-- CONFIGURATION - Update these values
-- ============================================
DECLARE @BackupShare NVARCHAR(500) = N'\\<FILE-SERVER>\SQLBackups\LakeviewMedical';
DECLARE @BlobBaseUrl NVARCHAR(500) = N'https://<STORAGE-ACCOUNT>.blob.core.windows.net/dms-backups';
DECLARE @Timestamp   NVARCHAR(20)  = REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(20), GETDATE(), 120), '-', ''), ':', ''), ' ', '_');

-- ============================================
-- Target databases
-- ============================================
IF OBJECT_ID('tempdb..#MigrationDatabases') IS NOT NULL
    DROP TABLE #MigrationDatabases;

CREATE TABLE #MigrationDatabases (
    DatabaseName NVARCHAR(128),
    BackupPath   NVARCHAR(500)
);

INSERT INTO #MigrationDatabases (DatabaseName, BackupPath) VALUES
    (N'PatientDB',     @BackupShare + N'\PatientDB_FULL_'     + @Timestamp + N'.bak'),
    (N'BillingDB',     @BackupShare + N'\BillingDB_FULL_'     + @Timestamp + N'.bak'),
    (N'SchedulingDB',  @BackupShare + N'\SchedulingDB_FULL_'  + @Timestamp + N'.bak'),
    (N'ReportingDB',   @BackupShare + N'\ReportingDB_FULL_'   + @Timestamp + N'.bak');
GO

-- ============================================
-- PART 1: FULL BACKUPS (Run on Source SQL Server)
-- ============================================
-- Verify we are running on the on-premises server
IF SERVERPROPERTY('EngineEdition') = 8
BEGIN
    RAISERROR('This part must be run on the ON-PREMISES SQL Server, not on SQL Managed Instance.', 16, 1);
    RETURN;
END
GO

PRINT '================================================================';
PRINT ' PART 1: Full Database Backups (Source SQL Server)';
PRINT '================================================================';
PRINT '';
GO

-- ============================================
-- Pre-flight: Verify all databases exist and
-- are online with FULL recovery model
-- ============================================
DECLARE @ErrorCount INT = 0;

IF OBJECT_ID('tempdb..#BackupValidation') IS NOT NULL
    DROP TABLE #BackupValidation;

CREATE TABLE #BackupValidation (
    DatabaseName    NVARCHAR(128),
    Status          NVARCHAR(20),
    RecoveryModel   NVARCHAR(20),
    Issue           NVARCHAR(500)
);

INSERT INTO #BackupValidation (DatabaseName, Status, RecoveryModel, Issue)
SELECT
    md.DatabaseName,
    ISNULL(d.state_desc, 'MISSING'),
    ISNULL(d.recovery_model_desc, 'N/A'),
    CASE
        WHEN d.database_id IS NULL THEN 'Database does not exist on this server'
        WHEN d.state_desc <> 'ONLINE' THEN 'Database is not ONLINE (state: ' + d.state_desc + ')'
        WHEN d.recovery_model_desc <> 'FULL' THEN 'Recovery model is ' + d.recovery_model_desc + ' — must be FULL for online migration'
        ELSE 'OK'
    END
FROM #MigrationDatabases md
LEFT JOIN sys.databases d ON d.name = md.DatabaseName;

-- Report issues
SELECT @ErrorCount = COUNT(*) FROM #BackupValidation WHERE Issue <> 'OK';

IF @ErrorCount > 0
BEGIN
    PRINT '*** Pre-flight validation FAILED ***';
    SELECT DatabaseName, Status, RecoveryModel, Issue
    FROM #BackupValidation
    WHERE Issue <> 'OK';
    RAISERROR('Fix the above issues before proceeding with backups.', 16, 1);
    RETURN;
END

PRINT 'Pre-flight validation PASSED — all 4 databases are ONLINE with FULL recovery model.';
PRINT '';
GO

-- ============================================
-- Backup PatientDB
-- ============================================
DECLARE @BackupShare NVARCHAR(500) = N'\\<FILE-SERVER>\SQLBackups\LakeviewMedical';
DECLARE @Timestamp   NVARCHAR(20)  = REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(20), GETDATE(), 120), '-', ''), ':', ''), ' ', '_');
DECLARE @BackupPath  NVARCHAR(500);
DECLARE @StartTime   DATETIME;
DECLARE @Duration    INT;

SET @BackupPath = @BackupShare + N'\PatientDB_FULL_' + @Timestamp + N'.bak';

PRINT 'Backing up PatientDB...';
SET @StartTime = GETDATE();

BACKUP DATABASE [PatientDB]
TO DISK = @BackupPath
WITH
    COMPRESSION,
    CHECKSUM,
    FORMAT,
    INIT,
    NAME = N'PatientDB - Full Backup for MI Migration',
    DESCRIPTION = N'Lakeview Medical Center - PatientDB full backup for Azure SQL MI online migration',
    STATS = 10;

SET @Duration = DATEDIFF(SECOND, @StartTime, GETDATE());
PRINT 'PatientDB backup completed in ' + CAST(@Duration AS VARCHAR(10)) + ' seconds.';
PRINT 'Backup path: ' + @BackupPath;
PRINT '';

-- Verify backup integrity
PRINT 'Verifying PatientDB backup integrity...';
RESTORE VERIFYONLY FROM DISK = @BackupPath WITH CHECKSUM;
PRINT 'PatientDB backup verification PASSED.';
PRINT '';
GO

-- ============================================
-- Backup BillingDB
-- ============================================
DECLARE @BackupShare NVARCHAR(500) = N'\\<FILE-SERVER>\SQLBackups\LakeviewMedical';
DECLARE @Timestamp   NVARCHAR(20)  = REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(20), GETDATE(), 120), '-', ''), ':', ''), ' ', '_');
DECLARE @BackupPath  NVARCHAR(500);
DECLARE @StartTime   DATETIME;
DECLARE @Duration    INT;

SET @BackupPath = @BackupShare + N'\BillingDB_FULL_' + @Timestamp + N'.bak';

PRINT 'Backing up BillingDB...';
SET @StartTime = GETDATE();

BACKUP DATABASE [BillingDB]
TO DISK = @BackupPath
WITH
    COMPRESSION,
    CHECKSUM,
    FORMAT,
    INIT,
    NAME = N'BillingDB - Full Backup for MI Migration',
    DESCRIPTION = N'Lakeview Medical Center - BillingDB full backup for Azure SQL MI online migration',
    STATS = 10;

SET @Duration = DATEDIFF(SECOND, @StartTime, GETDATE());
PRINT 'BillingDB backup completed in ' + CAST(@Duration AS VARCHAR(10)) + ' seconds.';
PRINT 'Backup path: ' + @BackupPath;
PRINT '';

PRINT 'Verifying BillingDB backup integrity...';
RESTORE VERIFYONLY FROM DISK = @BackupPath WITH CHECKSUM;
PRINT 'BillingDB backup verification PASSED.';
PRINT '';
GO

-- ============================================
-- Backup SchedulingDB
-- ============================================
DECLARE @BackupShare NVARCHAR(500) = N'\\<FILE-SERVER>\SQLBackups\LakeviewMedical';
DECLARE @Timestamp   NVARCHAR(20)  = REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(20), GETDATE(), 120), '-', ''), ':', ''), ' ', '_');
DECLARE @BackupPath  NVARCHAR(500);
DECLARE @StartTime   DATETIME;
DECLARE @Duration    INT;

SET @BackupPath = @BackupShare + N'\SchedulingDB_FULL_' + @Timestamp + N'.bak';

PRINT 'Backing up SchedulingDB...';
SET @StartTime = GETDATE();

BACKUP DATABASE [SchedulingDB]
TO DISK = @BackupPath
WITH
    COMPRESSION,
    CHECKSUM,
    FORMAT,
    INIT,
    NAME = N'SchedulingDB - Full Backup for MI Migration',
    DESCRIPTION = N'Lakeview Medical Center - SchedulingDB full backup for Azure SQL MI online migration',
    STATS = 10;

SET @Duration = DATEDIFF(SECOND, @StartTime, GETDATE());
PRINT 'SchedulingDB backup completed in ' + CAST(@Duration AS VARCHAR(10)) + ' seconds.';
PRINT 'Backup path: ' + @BackupPath;
PRINT '';

PRINT 'Verifying SchedulingDB backup integrity...';
RESTORE VERIFYONLY FROM DISK = @BackupPath WITH CHECKSUM;
PRINT 'SchedulingDB backup verification PASSED.';
PRINT '';
GO

-- ============================================
-- Backup ReportingDB
-- ============================================
DECLARE @BackupShare NVARCHAR(500) = N'\\<FILE-SERVER>\SQLBackups\LakeviewMedical';
DECLARE @Timestamp   NVARCHAR(20)  = REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(20), GETDATE(), 120), '-', ''), ':', ''), ' ', '_');
DECLARE @BackupPath  NVARCHAR(500);
DECLARE @StartTime   DATETIME;
DECLARE @Duration    INT;

SET @BackupPath = @BackupShare + N'\ReportingDB_FULL_' + @Timestamp + N'.bak';

PRINT 'Backing up ReportingDB...';
SET @StartTime = GETDATE();

BACKUP DATABASE [ReportingDB]
TO DISK = @BackupPath
WITH
    COMPRESSION,
    CHECKSUM,
    FORMAT,
    INIT,
    NAME = N'ReportingDB - Full Backup for MI Migration',
    DESCRIPTION = N'Lakeview Medical Center - ReportingDB full backup for Azure SQL MI online migration',
    STATS = 10;

SET @Duration = DATEDIFF(SECOND, @StartTime, GETDATE());
PRINT 'ReportingDB backup completed in ' + CAST(@Duration AS VARCHAR(10)) + ' seconds.';
PRINT 'Backup path: ' + @BackupPath;
PRINT '';

PRINT 'Verifying ReportingDB backup integrity...';
RESTORE VERIFYONLY FROM DISK = @BackupPath WITH CHECKSUM;
PRINT 'ReportingDB backup verification PASSED.';
PRINT '';
GO

-- ============================================
-- Backup summary report
-- ============================================
PRINT '================================================================';
PRINT ' BACKUP SUMMARY';
PRINT '================================================================';

SELECT
    bs.database_name                                      AS [Database],
    bs.backup_start_date                                  AS [Start Time],
    bs.backup_finish_date                                 AS [End Time],
    DATEDIFF(SECOND, bs.backup_start_date,
             bs.backup_finish_date)                       AS [Duration (sec)],
    CAST(bs.backup_size / 1048576.0 AS DECIMAL(12,2))    AS [Size (MB)],
    CAST(bs.compressed_backup_size / 1048576.0
         AS DECIMAL(12,2))                                AS [Compressed (MB)],
    CAST(100.0 - (bs.compressed_backup_size * 100.0
         / NULLIF(bs.backup_size, 0)) AS DECIMAL(5,1))   AS [Compression %],
    bs.has_backup_checksums                               AS [Checksum],
    bmf.physical_device_name                              AS [Backup File]
FROM msdb.dbo.backupset bs
INNER JOIN msdb.dbo.backupmediafamily bmf
    ON bs.media_set_id = bmf.media_set_id
WHERE bs.database_name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
    AND bs.type = 'D'
    AND bs.backup_start_date >= DATEADD(HOUR, -1, GETDATE())
ORDER BY bs.backup_start_date DESC;
GO

PRINT '';
PRINT '================================================================';
PRINT ' PART 1 COMPLETE - Full backups taken for all 4 databases';
PRINT ' Next: Copy backups to Azure Blob storage (if not using DMS';
PRINT '       file share integration), then run Part 2 on SQL MI.';
PRINT '================================================================';
GO


-- ============================================
-- PART 2: RESTORE WITH NORECOVERY (Run on SQL MI)
-- ============================================
-- *** STOP HERE ***
-- Switch connection to the Azure SQL Managed Instance
-- before running the statements below.
-- ============================================

/*
-- Uncomment and run on SQL Managed Instance

PRINT '================================================================';
PRINT ' PART 2: Restore Databases WITH NORECOVERY (Azure SQL MI)';
PRINT '================================================================';
PRINT '';
GO

-- ============================================
-- CONFIGURATION - Update blob storage URL
-- and credential name for your environment
-- ============================================
-- Prerequisite: Create a credential on the MI for
-- accessing the Azure Blob storage account
-- containing the backup files.
-- ============================================

-- Step 2a: Create credential for blob storage access (if not already created)
IF NOT EXISTS (SELECT 1 FROM sys.credentials WHERE name = N'https://<STORAGE-ACCOUNT>.blob.core.windows.net/dms-backups')
BEGIN
    CREATE CREDENTIAL [https://<STORAGE-ACCOUNT>.blob.core.windows.net/dms-backups]
    WITH IDENTITY = 'SHARED ACCESS SIGNATURE',
    SECRET = '<SAS-TOKEN-WITHOUT-LEADING-QUESTION-MARK>';
    PRINT 'Credential created for blob storage access.';
END
ELSE
    PRINT 'Credential already exists for blob storage.';
GO

-- ============================================
-- Restore PatientDB WITH NORECOVERY
-- ============================================
PRINT 'Restoring PatientDB WITH NORECOVERY...';

RESTORE DATABASE [PatientDB]
FROM URL = N'https://<STORAGE-ACCOUNT>.blob.core.windows.net/dms-backups/PatientDB_FULL_<TIMESTAMP>.bak'
WITH
    NORECOVERY,
    REPLACE,
    STATS = 10;

PRINT 'PatientDB restore (NORECOVERY) completed.';
PRINT '';
GO

-- ============================================
-- Restore BillingDB WITH NORECOVERY
-- ============================================
PRINT 'Restoring BillingDB WITH NORECOVERY...';

RESTORE DATABASE [BillingDB]
FROM URL = N'https://<STORAGE-ACCOUNT>.blob.core.windows.net/dms-backups/BillingDB_FULL_<TIMESTAMP>.bak'
WITH
    NORECOVERY,
    REPLACE,
    STATS = 10;

PRINT 'BillingDB restore (NORECOVERY) completed.';
PRINT '';
GO

-- ============================================
-- Restore SchedulingDB WITH NORECOVERY
-- ============================================
PRINT 'Restoring SchedulingDB WITH NORECOVERY...';

RESTORE DATABASE [SchedulingDB]
FROM URL = N'https://<STORAGE-ACCOUNT>.blob.core.windows.net/dms-backups/SchedulingDB_FULL_<TIMESTAMP>.bak'
WITH
    NORECOVERY,
    REPLACE,
    STATS = 10;

PRINT 'SchedulingDB restore (NORECOVERY) completed.';
PRINT '';
GO

-- ============================================
-- Restore ReportingDB WITH NORECOVERY
-- ============================================
PRINT 'Restoring ReportingDB WITH NORECOVERY...';

RESTORE DATABASE [ReportingDB]
FROM URL = N'https://<STORAGE-ACCOUNT>.blob.core.windows.net/dms-backups/ReportingDB_FULL_<TIMESTAMP>.bak'
WITH
    NORECOVERY,
    REPLACE,
    STATS = 10;

PRINT 'ReportingDB restore (NORECOVERY) completed.';
PRINT '';
GO

-- ============================================
-- Verify restore state on MI
-- ============================================
PRINT '================================================================';
PRINT ' RESTORE STATUS ON MANAGED INSTANCE';
PRINT '================================================================';

SELECT
    d.name              AS [Database],
    d.state_desc        AS [State],
    d.recovery_model_desc AS [Recovery Model],
    d.create_date       AS [Created],
    CASE
        WHEN d.state_desc = 'RESTORING' THEN 'Ready for log restores'
        WHEN d.state_desc = 'ONLINE'    THEN 'WARNING: Database is ONLINE — cannot apply logs'
        ELSE 'Check state: ' + d.state_desc
    END AS [Migration Status]
FROM sys.databases d
WHERE d.name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
ORDER BY d.name;
GO

PRINT '';
PRINT '================================================================';
PRINT ' PART 2 COMPLETE';
PRINT ' All databases restored WITH NORECOVERY on SQL MI.';
PRINT ' Databases are in RESTORING state, ready for log shipping.';
PRINT ' Next: Run 11-LogShipping.sql to begin continuous log backups.';
PRINT '================================================================';
GO

*/
