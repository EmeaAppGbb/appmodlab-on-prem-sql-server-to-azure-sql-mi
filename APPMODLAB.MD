---
title: "SQL Server to Azure SQL MI"
description: "Migrate on-premises SQL Server databases to Azure SQL Managed Instance with minimal downtime using Azure DMS"
authors: ["marconsilva"]
category: "Data Modernization"
industry: "Healthcare & Life Sciences"
services: ["Azure SQL Managed Instance", "Azure Database Migration Service"]
languages: ["SQL", "T-SQL", "C#"]
frameworks: [".NET"]
modernizationTools: ["Azure Migrate", "Data Migration Assistant"]
agenticTools: []
tags: ["sql-server", "managed-instance", "database-migration", "dms", "clr", "service-broker"]
extensions: ["github.copilot"]
thumbnail: "https://raw.githubusercontent.com/EmeaAppGbb/appmodlab-on-prem-sql-server-to-azure-sql-mi/main/assets/thumbnail-gpt-image.png"
video: ""
version: "1.0.0"
---

## Lab Architecture

The architecture overview shows the 4-database Lakeview Medical system with 30 tables, migration blockers, and MI compatibility assessment.

[View: Architecture Overview](assets/screenshots/00-lab-architecture-overview.html)

*Open the HTML file in a browser to view the syntax-highlighted rendering.*

## Legacy Database Analysis

### Patient Tables Schema

The PatientDB contains 16 tables with legacy patterns including TEXT columns, unencrypted SSN fields, and denormalized addresses — all requiring remediation before migration to Managed Instance.

[View: PatientDB Tables Schema](assets/screenshots/01-patient-tables-schema.html)

*Open the HTML file in a browser to view the syntax-highlighted rendering.*

### Cross-Database Stored Procedures

BillingDB stored procedures execute cross-database queries to PatientDB using three-part names. This is a key migration blocker since Azure SQL MI does not support cross-database queries.

[View: Cross-Database Stored Procedures](assets/screenshots/02-cross-database-stored-procs.html)

*Open the HTML file in a browser to view the syntax-highlighted rendering.*

### CLR Assembly — Medical Calculations

The system uses C# .NET CLR functions for drug interaction checks, GFR calculations, and HL7 message parsing. CLR assemblies are supported on MI but require `PERMISSION_SET` adjustments.

[View: CLR Assembly Medical Calculations](assets/screenshots/03-clr-assembly-medical-calcs.html)

*Open the HTML file in a browser to view the syntax-highlighted rendering.*

## Migration Blockers

### Linked Servers Configuration

Four linked servers connect to external Pharmacy, Insurance, Lab, and Radiology PACS systems. Linked servers are not supported on Azure SQL MI and must be replaced with alternative connectivity patterns.

[View: Linked Servers Configuration](assets/screenshots/04-linked-servers-config.html)

*Open the HTML file in a browser to view the syntax-highlighted rendering.*

### Service Broker Messaging

Asynchronous messaging between PatientDB and BillingDB uses Service Broker with activation procedures. Service Broker is supported on MI within a single instance, but cross-instance messaging requires redesign.

[View: Service Broker Messaging](assets/screenshots/05-service-broker-messaging.html)

*Open the HTML file in a browser to view the syntax-highlighted rendering.*

### SQL Agent Jobs

Seven automated jobs handle billing cycles, claims processing, data archival, and backups, plus 4 monitoring alerts. SQL Agent is supported on MI with minor syntax differences.

[View: SQL Agent Jobs](assets/screenshots/06-sql-agent-jobs.html)

*Open the HTML file in a browser to view the syntax-highlighted rendering.*

## Lab Environment

### Docker Compose Setup

The lab runs in a 3-container Docker environment: a main SQL Server instance plus simulated pharmacy and insurance external systems for linked server testing.

[View: Docker Compose Environment](assets/screenshots/07-docker-compose-environment.html)

*Open the HTML file in a browser to view the syntax-highlighted rendering.*

## Screenshots

Visual walkthroughs of the lab's key database objects and migration challenges. Open the HTML files in a browser for syntax-highlighted, screenshot-ready views.

| # | Screenshot | Description |
|---|-----------|-------------|
| 0 | [Architecture Overview](assets/screenshots/00-lab-architecture-overview.html) | Dashboard showing 4 databases, 30 tables, migration blockers, and MI compatibility |
| 1 | [PatientDB Tables](assets/screenshots/01-patient-tables-schema.html) | 16-table schema with legacy patterns highlighted (TEXT columns, unencrypted SSN, denormalized addresses) |
| 2 | [Cross-Database Stored Procs](assets/screenshots/02-cross-database-stored-procs.html) | BillingDB procedures with cross-database queries to PatientDB — migration blocker |
| 3 | [CLR Assembly](assets/screenshots/03-clr-assembly-medical-calcs.html) | C# .NET CLR functions: drug interactions, GFR calculation, HL7 parser |
| 4 | [Linked Servers](assets/screenshots/04-linked-servers-config.html) | 4 linked servers (Pharmacy, Insurance, Lab, Radiology PACS) — not supported on MI |
| 5 | [Service Broker](assets/screenshots/05-service-broker-messaging.html) | Async messaging between PatientDB and BillingDB with activation procedures |
| 6 | [SQL Agent Jobs](assets/screenshots/06-sql-agent-jobs.html) | 7 automated jobs (billing, claims, archival, backups) + 4 monitoring alerts |
| 7 | [Docker Compose](assets/screenshots/07-docker-compose-environment.html) | 3-container lab environment: main SQL Server + pharmacy + insurance systems |

## Solution Walkthrough

The complete migration solution is available on the `solution-final` branch with each step tagged for easy navigation. All code changes were generated using **GitHub Copilot CLI** (`gh copilot`).

### How to Use

```bash
# View the full solution
git checkout solution-final

# Jump to a specific step
git checkout step-01-assessment   # Step 1: Assessment scripts
git checkout step-05-start-migration  # Step 5: Migration scripts
```

### Steps, Prompts, and Outputs

| Step | Tag | Description | CLI Prompt Summary | Output File |
|------|-----|-------------|-------------------|-------------|
| 01 | `step-01-assessment` | Assess Current Environment | Create DMA assessment, compatibility report, and inventory scripts for all 4 databases | `assets/outputs/step-01-assessment.txt` |
| 02 | `step-02-provision-mi` | Provision Managed Instance | Create Bicep IaC for VNet, SQL MI, DMS, and deployment script | `assets/outputs/step-02-provision-mi.txt` |
| 03 | `step-03-tde-certificates` | Prepare TDE Certificates | Create TDE certificate export, import, and validation scripts | `assets/outputs/step-03-tde-certificates.txt` |
| 04 | `step-04-configure-dms` | Configure DMS | Create DMS project config JSON, PowerShell migration script, and pre-checks | `assets/outputs/step-04-configure-dms.txt` |
| 05 | `step-05-start-migration` | Start Migration | Create backup/restore, log shipping, and migration monitoring scripts | `assets/outputs/step-05-start-migration.txt` |
| 06 | `step-06-agent-jobs` | Migrate Agent Jobs | Recreate Agent jobs with MI-compatible syntax, validation, and mapping doc | `assets/outputs/step-06-agent-jobs.txt` |
| 07 | `step-07-linked-servers` | Reconfigure Linked Servers | Reconfigure linked servers for cloud endpoints with validation | `assets/outputs/step-07-linked-servers.txt` |
| 08 | `step-08-clr-service-broker` | Validate CLR & Service Broker | Deploy CLR assemblies and Service Broker config on MI with validation | `assets/outputs/step-08-clr-service-broker.txt` |
| 09 | `step-09-cutover` | Cutover | Final cutover procedure, connection string update, and checklist | `assets/outputs/step-09-cutover.txt` |
| 10 | `step-10-post-migration` | Post-Migration | Performance baseline, monitoring setup, SSRS migration guide | `assets/outputs/step-10-post-migration.txt` |

### CLI Command Pattern

Each step was executed using:

```powershell
gh copilot -- -p "<STEP PROMPT>" --allow-all-tools --yolo
```

### Migration Scripts Created (Migration/ directory)

| # | File | Purpose |
|---|------|---------|
| 01 | `01-DMA-Assessment.sql` | Data Migration Assistant assessment for all 4 databases |
| 02 | `02-CompatibilityReport.sql` | MI compatibility report with blockers and recommendations |
| 03 | `03-InventoryAssessment.sql` | Database object inventory across all databases |
| 04 | `04-ExportTDECertificates.sql` | Export TDE certificates from source SQL Server |
| 05 | `05-ImportTDECertificates.sql` | Import TDE certificates into Azure SQL MI |
| 06 | `06-TDEValidation.sql` | Validate TDE configuration post-migration |
| 07 | `07-DMSProjectSetup.json` | DMS project configuration for online migration |
| 08 | `08-DMSMigrationConfig.ps1` | PowerShell DMS migration setup script |
| 09 | `09-DMSPreChecks.sql` | Pre-migration readiness checklist |
| 10 | `10-BackupAndRestore.sql` | Full backup and restore with NORECOVERY |
| 11 | `11-LogShipping.sql` | Continuous log shipping to Azure Blob |
| 12 | `12-MigrationMonitoring.sql` | Migration progress monitoring dashboard |
| 13 | `13-MigrateAgentJobs.sql` | Recreate Agent jobs on MI |
| 14 | `14-AgentJobValidation.sql` | Validate migrated Agent jobs |
| 15 | `15-AgentJobMapping.md` | Source-to-target job mapping document |
| 16 | `16-ReconfigureLinkedServers.sql` | Linked server cloud endpoint reconfiguration |
| 17 | `17-LinkedServerValidation.sql` | Linked server connectivity validation |
| 18 | `18-LinkedServerAlternatives.md` | Alternative connectivity patterns guide |
| 19 | `19-CLRMigration.sql` | Deploy CLR assemblies on MI |
| 20 | `20-ServiceBrokerMigration.sql` | Service Broker configuration on MI |
| 21 | `21-CLRServiceBrokerValidation.sql` | CLR and Service Broker validation |
| 22 | `22-CutoverProcedure.sql` | Final cutover with integrity checks |
| 23 | `23-ConnectionStringUpdate.ps1` | Connection string update with Key Vault |
| 24 | `24-CutoverChecklist.md` | Detailed cutover checklist with rollback plan |
| 25 | `25-PerformanceBaseline.sql` | Performance baseline and comparison framework |
| 26 | `26-MonitoringSetup.ps1` | Azure Monitor and SQL Analytics setup |
| 27 | `27-SSRSMigration.md` | SSRS to Power BI migration guide |
| 28 | `28-PostMigrationValidation.sql` | Comprehensive post-migration validation |

### Infrastructure as Code (Infrastructure/ directory)

| File | Purpose |
|------|---------|
| `main.bicep` | Main orchestrator for all Azure resources |
| `modules/vnet.bicep` | VNet with MI-delegated subnet and NSG rules |
| `modules/sqlmi.bicep` | Azure SQL Managed Instance (GP, 8 vCores) |
| `modules/dms.bicep` | Azure Database Migration Service |
| `parameters.json` | Parameter file with lab defaults |
| `deploy.sh` | Deployment script using Azure CLI |
