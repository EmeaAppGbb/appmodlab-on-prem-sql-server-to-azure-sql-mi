# Deployment Guide - Lakeview Medical Center SQL Server

## Overview

This directory contains the deployment scripts for the Lakeview Medical Center on-premises SQL Server 2016 environment. The system consists of **four interconnected databases** with complex dependencies that are representative of real-world enterprise healthcare systems.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  SQL Server 2016                     │
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐      │
│  │ PatientDB│◄►│ BillingDB│  │ SchedulingDB │      │
│  │          │  │          │  │              │      │
│  │ 16 tables│  │ 9 tables │  │   5 tables   │      │
│  │ 8 views  │  │ 5 sprocs │  │              │      │
│  │ 8 sprocs │  │          │  │              │      │
│  │ 9 funcs  │  │          │  │              │      │
│  └─────┬────┘  └────┬─────┘  └──────┬───────┘      │
│        │             │               │               │
│        └─────────────┼───────────────┘               │
│                      │                               │
│              ┌───────▼───────┐                       │
│              │  ReportingDB  │                       │
│              │ 5 cross-db    │                       │
│              │ views         │                       │
│              └───────────────┘                       │
│                                                      │
│  Service Broker (PatientDB ↔ BillingDB)             │
│  CLR Assembly (MedicalCalculations)                  │
│  4 Linked Servers (Pharmacy, Insurance, Lab, PACS)  │
│  7 SQL Agent Jobs + Alerts                          │
└─────────────────────────────────────────────────────┘
```

## Prerequisites

- **SQL Server 2016** (or later) with:
  - Database Engine Services
  - SQL Server Agent
  - Full-Text Search (optional)
- **sysadmin** role membership
- **Disk Space**: Minimum 10 GB on the data drive
- **Data Directory**: `C:\SQLData` (or update paths in scripts)

## Deployment Order

The master deployment script (`00-DeployAll.sql`) handles the correct order automatically. If deploying manually, follow this sequence:

| Phase | Script | Description |
|-------|--------|-------------|
| 1 | `Databases/*/01-CreateDatabase.sql` | Create all four databases |
| 2 | `Databases/*/02-Tables.sql` | Create tables (PatientDB first, then BillingDB, SchedulingDB) |
| 3 | `Databases/*/03-Views.sql` | Create views (PatientDB first, then ReportingDB) |
| 4 | `Databases/PatientDB/04-StoredProcedures.sql` | PatientDB stored procedures |
| 5 | `Databases/PatientDB/05-Functions.sql` | PatientDB functions |
| 6 | `Databases/BillingDB/03-StoredProcedures.sql` | BillingDB stored procedures (depends on PatientDB) |
| 7 | `ServiceBroker/01-ServiceBrokerSetup.sql` | Service Broker messaging |
| 8 | `CLRAssemblies/DeployCLR.sql` | CLR assembly deployment |
| 9 | `LinkedServers/01-CreateLinkedServers.sql` | External system linked servers |
| 10 | `SQLAgent/Jobs/*.sql` | SQL Agent jobs |
| 11 | `SQLAgent/Alerts/*.sql` | Monitoring alerts |
| 12 | `SeedData/01-InsertSampleData.sql` | Sample data |

## Quick Deploy (SQLCMD)

```cmd
sqlcmd -S localhost -E -i "Deployment\00-DeployAll.sql"
```

Or in **SSMS**:
1. Open `Deployment\00-DeployAll.sql`
2. Enable SQLCMD Mode: **Query** → **SQLCMD Mode**
3. Update `:setvar ScriptPath` to your local path
4. Execute (F5)

## Migration-Relevant Features

These features represent common migration challenges when moving to Azure SQL MI:

| Feature | Impact | Notes |
|---------|--------|-------|
| **Cross-database queries** | High | BillingDB → PatientDB, ReportingDB → all databases |
| **Service Broker** | Medium | Async messaging between PatientDB and BillingDB |
| **CLR Assemblies** | Medium | .NET CLR functions for medical calculations |
| **Linked Servers** | High | 4 external system connections (pharmacy, insurance, lab, PACS) |
| **SQL Agent Jobs** | Medium | 7 jobs including nightly billing, backups, archival |
| **TDE Encryption** | Medium | BillingDB uses Transparent Data Encryption |
| **Legacy Data Types** | Low | TEXT, NTEXT, IMAGE columns (deprecated) |
| **TRUSTWORTHY Database** | Low | Required for CLR assembly deployment |
| **Dynamic SQL** | Low | Patient search with dynamic WHERE clauses |
| **Cursors** | Low | Used in discharge, billing, and archival processes |

## Database Credentials

> ⚠️ **Note**: The linked server scripts contain hardcoded passwords for the lab environment. In production, use integrated authentication or Azure Key Vault.

## Troubleshooting

- **Service Broker not enabled**: Run `ALTER DATABASE [DBName] SET ENABLE_BROKER WITH ROLLBACK IMMEDIATE`
- **CLR not enabled**: Run `sp_configure 'clr enabled', 1; RECONFIGURE;`
- **Cross-database queries fail**: Ensure all four databases are deployed before running ReportingDB views
- **Agent jobs fail**: Verify SQL Server Agent is running and the service account has appropriate permissions
