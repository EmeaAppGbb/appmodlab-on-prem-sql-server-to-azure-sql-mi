# Lakeview Medical Center - Local Development Setup

## Quick Start

### Prerequisites
- Docker Desktop installed
- SQL Server Management Studio (SSMS) or Azure Data Studio
- Minimum 8GB RAM available for Docker

### Start the Environment

1. **Start SQL Server containers:**
   ```bash
   docker-compose up -d
   ```

2. **Wait for SQL Server to be ready (about 30 seconds):**
   ```bash
   docker logs lakeview-sqlserver -f
   ```
   Wait until you see "SQL Server is now ready for client connections"

3. **Deploy the databases:**
   ```bash
   docker exec -it lakeview-sqlserver /opt/mssql-tools/bin/sqlcmd -S localhost -U sa -P "LakeviewMedical2024!" -i /scripts/00-DeployAll.sql
   ```

   Or use PowerShell:
   ```powershell
   cd Deployment
   .\Deploy-Databases.ps1
   ```

### Connection Information

**Main SQL Server:**
- Server: `localhost,1433` or `127.0.0.1,1433`
- Username: `sa`
- Password: `LakeviewMedical2024!`
- Databases: `PatientDB`, `BillingDB`, `SchedulingDB`, `ReportingDB`

**Pharmacy System (Linked Server):**
- Server: `localhost,1434`
- Username: `sa`
- Password: `Pharmacy2024!`

**Insurance System (Linked Server):**
- Server: `localhost,1435`
- Username: `sa`
- Password: `Insurance2024!`

### Manual Deployment Steps

If you prefer to deploy manually:

```sql
-- Connect to localhost,1433 with SSMS
-- Execute scripts in order:
:r C:\path\to\Databases\PatientDB\01-CreateDatabase.sql
:r C:\path\to\Databases\PatientDB\02-Tables.sql
:r C:\path\to\Databases\PatientDB\03-Views.sql
:r C:\path\to\Databases\PatientDB\04-StoredProcedures.sql
:r C:\path\to\Databases\PatientDB\05-Functions.sql

-- Repeat for BillingDB, SchedulingDB, ReportingDB
-- Then deploy Service Broker, CLR, Linked Servers, SQL Agent Jobs
```

### Verify Deployment

```sql
-- Check databases exist
SELECT name, state_desc, recovery_model_desc, compatibility_level
FROM sys.databases
WHERE name IN ('PatientDB', 'BillingDB', 'SchedulingDB', 'ReportingDB');

-- Check cross-database views work
SELECT * FROM ReportingDB.dbo.vw_HospitalCensus;

-- Check Service Broker is enabled
SELECT name, is_broker_enabled FROM sys.databases WHERE name = 'PatientDB';

-- Check SQL Agent jobs (if running on Windows)
EXEC msdb.dbo.sp_help_job;
```

### Test Cross-Database Queries

```sql
-- Patient with billing summary (crosses PatientDB and BillingDB)
SELECT 
    p.MRN,
    CONCAT(p.FirstName, ' ', p.LastName) AS PatientName,
    COUNT(bc.ChargeId) AS TotalCharges,
    SUM(bc.ChargeAmount) AS TotalBilled
FROM PatientDB.dbo.Patients p
LEFT JOIN BillingDB.dbo.BillingCharges bc ON p.PatientId = bc.PatientId
WHERE p.PatientId = 1
GROUP BY p.PatientId, p.MRN, p.FirstName, p.LastName;
```

### Test Service Broker

```sql
-- Send a test message
USE BillingDB;
EXEC dbo.usp_SendBillingNotification @EncounterId = 1;

-- Check queue
SELECT * FROM PatientDB.dbo.BillingNotificationQueue;
SELECT * FROM PatientDB.dbo.AuditLog WHERE TableName = 'ServiceBroker';
```

### Stop the Environment

```bash
docker-compose down
```

To remove all data:
```bash
docker-compose down -v
```

## Troubleshooting

### SQL Server won't start
- Check Docker has enough memory (8GB minimum)
- Check port 1433 is not in use: `netstat -an | findstr 1433`
- View logs: `docker logs lakeview-sqlserver`

### CLR assembly deployment fails
- CLR assemblies require special permissions in SQL Server 2016+
- Enable CLR: `sp_configure 'clr enabled', 1; RECONFIGURE;`
- For EXTERNAL_ACCESS: Require TRUSTWORTHY database or signed assemblies

### Cross-database queries fail
- Verify all databases are created
- Check database context with `SELECT DB_NAME()`
- Use fully qualified names: `DatabaseName.SchemaName.ObjectName`

### Service Broker not working
- Verify broker enabled: `ALTER DATABASE PatientDB SET ENABLE_BROKER;`
- Check queue status: `SELECT * FROM sys.service_queues;`
- Monitor conversations: `SELECT * FROM sys.conversation_endpoints;`

## Database Schema Overview

### PatientDB (Core Clinical Data)
- 16 tables: Patients, Physicians, Departments, Encounters, Orders, Medications, LabResults, etc.
- 8 views: Active patients, inpatient census, pending labs, critical results
- 8 stored procedures: Register patient, create encounter, discharge, order medication
- 9 functions: Calculate age/BMI, format names, get encounters/medications

### BillingDB (Financial Data)
- 9 tables: Charges, Claims, Line Items, Payments, Invoices, Collections
- Cross-database stored procedures querying PatientDB
- Linked server integration for insurance claim submission

### SchedulingDB (Appointments & Resources)
- 5 tables: Appointments, Rooms, Room Assignments, Staff Schedules, Waiting List
- Room occupancy tracking

### ReportingDB (Analytics)
- 5 cross-database views spanning all databases
- Financial summaries, census reports, productivity metrics

## Migration Lab Scenarios

This database is designed for the "On-Prem SQL Server to Azure SQL MI" migration lab:

1. **Assessment:** Run DMA to identify compatibility issues
2. **Pre-Migration:** Export TDE certificates, configure linked servers
3. **Migration:** Use Azure DMS for online migration
4. **Post-Migration:** Migrate SQL Agent jobs, validate cross-DB queries, test CLR
5. **Cutover:** Switch connection strings, verify Service Broker, monitor performance
