-- ============================================
-- Master Deployment Script
-- Lakeview Medical Center
-- Deploys all databases, objects, and seed data
-- Run with SQLCMD mode enabled in SSMS
-- ============================================

/*
  DEPLOYMENT INSTRUCTIONS:
  ========================
  1. Open this file in SSMS with SQLCMD mode enabled
     (Query menu > SQLCMD Mode)
  2. Update the :setvar variables below for your environment
  3. Execute the entire script
  4. Review output for any errors
  
  PREREQUISITES:
  - SQL Server 2016 or later
  - sysadmin role membership
  - C:\SQLData directory must exist (or update paths)
  - Sufficient disk space (minimum 10 GB recommended)
*/

-- ============================================
-- Environment Variables (SQLCMD)
-- ============================================
:setvar ScriptPath "C:\code\gbb\appmodlabs\appmodlab-on-prem-sql-server-to-azure-sql-mi"
:setvar DataPath "C:\SQLData"

SET NOCOUNT ON;
GO

PRINT '╔══════════════════════════════════════════════════╗';
PRINT '║  LAKEVIEW MEDICAL CENTER - DATABASE DEPLOYMENT  ║';
PRINT '║  Version: 1.0                                    ║';
PRINT '║  Target: SQL Server 2016 (Compat Level 130)      ║';
PRINT '╚══════════════════════════════════════════════════╝';
PRINT '';
PRINT 'Deployment started: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT '';
GO

-- ============================================
-- Pre-flight checks
-- ============================================
PRINT '--- PRE-FLIGHT CHECKS ---';

-- Check SQL Server version
DECLARE @Version NVARCHAR(200);
SELECT @Version = @@VERSION;
PRINT 'SQL Server: ' + LEFT(@Version, CHARINDEX(CHAR(10), @Version) - 1);

-- Check available disk space
PRINT 'Checking prerequisites...';

-- Ensure data directory exists
EXEC xp_create_subdir '$(DataPath)';
PRINT 'Data directory verified: $(DataPath)';
PRINT '';
GO

-- ============================================
-- PHASE 1: Create Databases
-- ============================================
PRINT '=== PHASE 1: CREATE DATABASES ===';
PRINT '';

PRINT '>> Creating PatientDB...';
:r $(ScriptPath)\Databases\PatientDB\01-CreateDatabase.sql

PRINT '>> Creating BillingDB...';
:r $(ScriptPath)\Databases\BillingDB\01-CreateDatabase.sql

PRINT '>> Creating SchedulingDB...';
:r $(ScriptPath)\Databases\SchedulingDB\01-CreateDatabase.sql

PRINT '>> Creating ReportingDB...';
:r $(ScriptPath)\Databases\ReportingDB\01-CreateDatabase.sql

PRINT 'Phase 1 complete.';
PRINT '';
GO

-- ============================================
-- PHASE 2: Create Tables
-- ============================================
PRINT '=== PHASE 2: CREATE TABLES ===';
PRINT '';

PRINT '>> Creating PatientDB tables...';
:r $(ScriptPath)\Databases\PatientDB\02-Tables.sql

PRINT '>> Creating BillingDB tables...';
:r $(ScriptPath)\Databases\BillingDB\02-Tables.sql

PRINT '>> Creating SchedulingDB tables...';
:r $(ScriptPath)\Databases\SchedulingDB\02-Tables.sql

PRINT 'Phase 2 complete.';
PRINT '';
GO

-- ============================================
-- PHASE 3: Create Views
-- ============================================
PRINT '=== PHASE 3: CREATE VIEWS ===';
PRINT '';

PRINT '>> Creating PatientDB views...';
:r $(ScriptPath)\Databases\PatientDB\03-Views.sql

PRINT '>> Creating ReportingDB views (cross-database)...';
:r $(ScriptPath)\Databases\ReportingDB\02-Views.sql

PRINT 'Phase 3 complete.';
PRINT '';
GO

-- ============================================
-- PHASE 4: Create Stored Procedures and Functions
-- ============================================
PRINT '=== PHASE 4: CREATE PROGRAMMABILITY OBJECTS ===';
PRINT '';

PRINT '>> Creating PatientDB stored procedures...';
:r $(ScriptPath)\Databases\PatientDB\04-StoredProcedures.sql

PRINT '>> Creating PatientDB functions...';
:r $(ScriptPath)\Databases\PatientDB\05-Functions.sql

PRINT '>> Creating BillingDB stored procedures...';
:r $(ScriptPath)\Databases\BillingDB\03-StoredProcedures.sql

PRINT 'Phase 4 complete.';
PRINT '';
GO

-- ============================================
-- PHASE 5: Service Broker Setup
-- ============================================
PRINT '=== PHASE 5: SERVICE BROKER ===';
PRINT '';

PRINT '>> Setting up Service Broker messaging...';
:r $(ScriptPath)\ServiceBroker\01-ServiceBrokerSetup.sql

PRINT 'Phase 5 complete.';
PRINT '';
GO

-- ============================================
-- PHASE 6: CLR Assemblies
-- ============================================
PRINT '=== PHASE 6: CLR ASSEMBLIES ===';
PRINT '';

PRINT '>> Deploying CLR assembly configuration...';
:r $(ScriptPath)\CLRAssemblies\DeployCLR.sql

PRINT 'Phase 6 complete.';
PRINT '';
GO

-- ============================================
-- PHASE 7: Linked Servers
-- ============================================
PRINT '=== PHASE 7: LINKED SERVERS ===';
PRINT '';

PRINT '>> Creating linked server definitions...';
:r $(ScriptPath)\LinkedServers\01-CreateLinkedServers.sql

PRINT 'Phase 7 complete.';
PRINT '';
GO

-- ============================================
-- PHASE 8: SQL Agent Jobs and Alerts
-- ============================================
PRINT '=== PHASE 8: SQL AGENT CONFIGURATION ===';
PRINT '';

PRINT '>> Creating nightly billing job...';
:r $(ScriptPath)\SQLAgent\Jobs\01-NightlyBilling.sql

PRINT '>> Creating insurance claims job...';
:r $(ScriptPath)\SQLAgent\Jobs\02-InsuranceClaims.sql

PRINT '>> Creating data archival job...';
:r $(ScriptPath)\SQLAgent\Jobs\03-DataArchival.sql

PRINT '>> Creating statistics update job...';
:r $(ScriptPath)\SQLAgent\Jobs\04-StatisticsUpdate.sql

PRINT '>> Creating backup jobs...';
:r $(ScriptPath)\SQLAgent\Jobs\05-BackupJob.sql

PRINT '>> Creating alerts and monitors...';
:r $(ScriptPath)\SQLAgent\Alerts\01-DiskSpaceAlert.sql

PRINT 'Phase 8 complete.';
PRINT '';
GO

-- ============================================
-- PHASE 9: Seed Data
-- ============================================
PRINT '=== PHASE 9: SEED DATA ===';
PRINT '';

PRINT '>> Inserting sample data...';
:r $(ScriptPath)\SeedData\01-InsertSampleData.sql

PRINT 'Phase 9 complete.';
PRINT '';
GO

-- ============================================
-- PHASE 10: Validation
-- ============================================
PRINT '=== PHASE 10: DEPLOYMENT VALIDATION ===';
PRINT '';

-- Verify databases
SELECT name, state_desc, compatibility_level, recovery_model_desc, is_broker_enabled
FROM sys.databases
WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB')
ORDER BY name;

-- Verify table counts
PRINT '';
PRINT 'Object counts by database:';

DECLARE @db NVARCHAR(50);
DECLARE @sql NVARCHAR(500);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.databases WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @db;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = 'SELECT ''' + @db + ''' AS DatabaseName, type_desc, COUNT(*) AS ObjectCount 
                FROM ' + @db + '.sys.objects WHERE is_ms_shipped = 0 
                GROUP BY type_desc ORDER BY type_desc';
    EXEC sp_executesql @sql;
    FETCH NEXT FROM db_cursor INTO @db;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

-- Verify SQL Agent jobs
PRINT '';
PRINT 'SQL Agent Jobs:';
SELECT name, enabled, date_created
FROM msdb.dbo.sysjobs
WHERE name LIKE 'LMC -%'
ORDER BY name;

-- Verify linked servers
PRINT '';
PRINT 'Linked Servers:';
SELECT name, provider, data_source
FROM sys.servers
WHERE is_linked = 1;

PRINT '';
PRINT '╔══════════════════════════════════════════════════╗';
PRINT '║  DEPLOYMENT COMPLETE                             ║';
PRINT '║  Finished: ' + CONVERT(VARCHAR(20), GETDATE(), 120) + '            ║';
PRINT '╚══════════════════════════════════════════════════╝';
GO
