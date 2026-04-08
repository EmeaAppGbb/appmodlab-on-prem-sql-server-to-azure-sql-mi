# 🎮 SQL SERVER → AZURE SQL MI 🚀

```
██████╗  █████╗ ████████╗ █████╗     ██╗    ██╗ █████╗ ██████╗ ██████╗ 
██╔══██╗██╔══██╗╚══██╔══╝██╔══██╗    ██║    ██║██╔══██╗██╔══██╗██╔══██╗
██║  ██║███████║   ██║   ███████║    ██║ █╗ ██║███████║██████╔╝██████╔╝
██║  ██║██╔══██║   ██║   ██╔══██║    ██║███╗██║██╔══██║██╔══██╗██╔═══╝ 
██████╔╝██║  ██║   ██║   ██║  ██║    ╚███╔███╔╝██║  ██║██║  ██║██║     
╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝     ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     
                                                                          
           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
           █  MAINFRAME → CLOUD  |  ZERO DOWNTIME MODE  █
           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
```

## 🌐 OVERVIEW

**SYSTEM STATUS:** 🟢 ONLINE | **DATABASE WARP ENABLED** ⚡

Welcome to the **Lakeview Medical Center** data migration mission! 🏥 Your objective: teleport a complex on-premises SQL Server 2016 system — complete with CLR assemblies, cross-database queries, Service Broker messaging, and 25+ SQL Agent jobs — into the Azure cloud at **warp speed** with minimal downtime. 

This isn't your basic lift-and-shift! 🛠️ We're dealing with **four interconnected databases**, encrypted patient records (TDE), linked servers to pharmacy and insurance systems, and enough stored procedures to fill a server rack. 📡

Azure SQL Managed Instance is the **ultimate compatibility mode** — offering near-100% SQL Server parity so your complex enterprise workloads can migrate without massive rewrites. 🎯

```
┌─────────────────────────────────────────────────────────────┐
│  QUERY EXECUTING... ⏳                                       │
│  [████████████████████████░░░░░░░░] 75%                     │
│  Migrating 4 databases, 80+ tables, 200+ sprocs...          │
│  ETA: 6-8 hours                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎓 WHAT YOU'LL LEARN

**SKILL TREE UNLOCKED:** 🌟

- 🔍 **Pre-flight Diagnostics** — Run Data Migration Assistant (DMA) to assess compatibility and identify blockers
- 🚀 **Zero-Downtime Teleportation** — Use Azure Database Migration Service (DMS) for online migration with continuous log shipping
- 🔐 **Encryption Key Transfer** — Export and import TDE certificates without breaking encryption
- 🤖 **Agent Job Migration** — Move 25+ SQL Server Agent jobs to Managed Instance
- 🔗 **Link Re-establishment** — Reconfigure linked servers to cloud endpoints
- ⚙️ **CLR Assembly Warp** — Migrate C# CLR assemblies with PERMISSION_SET adjustments
- 📡 **Service Broker Messaging** — Validate async messaging between databases post-migration
- 📊 **Post-Migration Tuning** — Performance baseline, monitoring, and SSRS → Power BI migration
- 🛡️ **VNet Integration** — Private endpoint configuration for secure connectivity

---

## ⚡ PREREQUISITES

**SYSTEM REQUIREMENTS:** 🖥️

Before initiating the data warp sequence, ensure your workstation has:

- ✅ **SQL Server DBA Experience** — T-SQL, Agent jobs, backup/restore mastery
- ✅ **Azure Subscription** — Contributor access or higher
- ✅ **Azure CLI** — Command-line warp drive engaged
- ✅ **Azure Data Studio** — Modern cross-platform SQL IDE
- ✅ **SQL Server Management Studio (SSMS)** — Classic GUI for legacy systems
- ✅ **Networking Knowledge** — VNets, NSGs, and private endpoints
- ✅ **GitHub Copilot CLI** — AI pair programmer for accelerated migration
- ✅ **4-8 hours of lab time** — Grab your energy drink! ⚡☕

---

## 🎮 QUICK START

**INITIATE LAUNCH SEQUENCE:** 🚀

```powershell
# STEP 1: CLONE THE MISSION CONTROL REPO
git clone https://github.com/EmeaAppGbb/appmodlab-on-prem-sql-server-to-azure-sql-mi.git
cd appmodlab-on-prem-sql-server-to-azure-sql-mi

# STEP 2: CHECKOUT THE LEGACY BRANCH (RETRO MODE ACTIVATED)
git checkout legacy

# STEP 3: SPIN UP THE ON-PREM SQL SERVER (DOCKER CONTAINER)
docker-compose up -d

# STEP 4: LOAD THE DATABASE SCHEMA & DATA
sqlcmd -S localhost,1433 -U sa -P YourStr0ngP@ssw0rd -i ./setup-legacy-environment.sql

# STEP 5: VERIFY 4 DATABASES ARE ONLINE
sqlcmd -S localhost,1433 -U sa -P YourStr0ngP@ssw0rd -Q "SELECT name FROM sys.databases WHERE name LIKE '%DB'"

# STEP 6: CHECKOUT STEP-BY-STEP BRANCHES
git checkout step-1-assessment
# Follow the APPMODLAB.md guide for detailed walkthrough!

# 🎯 BONUS: ASK COPILOT CLI FOR HELP
gh copilot suggest "How do I assess SQL Server for Azure SQL MI compatibility?"
```

---

## 📁 PROJECT STRUCTURE

**FILE SYSTEM MAP:** 🗺️

```
appmodlab-on-prem-sql-server-to-azure-sql-mi/
│
├── 📜 README.md                              # ← YOU ARE HERE
├── 📘 APPMODLAB.md                           # Step-by-step lab guide
│
├── 🗄️ Databases/
│   ├── PatientDB/                            # 80+ patient tables
│   │   ├── Tables/
│   │   ├── Views/                            # Cross-database views
│   │   ├── StoredProcedures/                 # 200+ sprocs
│   │   ├── Functions/                        # UDFs + CLR functions
│   │   ├── CLRAssemblies/                    # C# assemblies for medical calcs
│   │   │   └── DrugInteractionCheck.cs       # CLR source code
│   │   └── ServiceBroker/                    # Message types, queues
│   ├── BillingDB/                            # Insurance claims & invoices
│   │   ├── Tables/
│   │   ├── StoredProcedures/                 # Billing with cross-DB queries
│   │   └── LinkedServerQueries/              # Insurance linked server queries
│   ├── SchedulingDB/                         # Appointments & staff schedules
│   └── ReportingDB/                          # Reporting views spanning all DBs
│
├── 🤖 SQLAgent/
│   ├── Jobs/
│   │   ├── NightlyBilling.sql                # Nightly billing batch
│   │   ├── InsuranceClaims.sql               # Daily claims submission
│   │   ├── DataArchival.sql                  # Monthly archival
│   │   ├── StatisticsUpdate.sql              # Weekly maintenance
│   │   └── BackupJob.sql                     # Full/diff backup schedule
│   └── Alerts/
│       └── DiskSpaceAlert.sql                # Disk monitoring
│
├── 🔗 LinkedServers/
│   ├── PharmacyLink.sql                      # Pharmacy system link
│   └── InsuranceLink.sql                     # Insurance portal link
│
├── 📊 SSRS/
│   ├── PatientSummary.rdl
│   ├── BillingReport.rdl
│   └── OccupancyReport.rdl
│
├── 🚀 Migration/
│   ├── assessment-scripts.sql                # DMA queries
│   ├── dms-config.json                       # DMS configuration
│   ├── tde-certificate-export.sql            # TDE cert export
│   ├── agent-job-migration.sql               # Job recreation scripts
│   └── post-migration-validation.sql         # Validation tests
│
├── 🏗️ Infrastructure/
│   ├── bicep/
│   │   ├── main.bicep                        # Main deployment template
│   │   ├── sql-mi.bicep                      # SQL Managed Instance
│   │   ├── vnet.bicep                        # VNet with subnets
│   │   └── dms.bicep                         # Database Migration Service
│   └── parameters/
│       └── production.parameters.json
│
├── 🧪 Tests/
│   ├── cross-database-query-test.sql         # Validate cross-DB queries
│   ├── clr-assembly-test.sql                 # CLR function tests
│   └── service-broker-test.sql               # Async messaging tests
│
└── 🐳 docker-compose.yml                      # Local SQL Server 2016 setup
```

---

## 🕹️ LEGACY STACK

**MAINFRAME SPECIFICATIONS:** 🖥️💾

```
┌─────────────────────────────────────────────────────────────┐
│  🔴 LEGACY ENVIRONMENT DETECTED                              │
│  ╔══════════════════════════════════════════════════════╗   │
│  ║  SQL Server 2016 SP3 Enterprise Edition             ║   │
│  ║  Windows Server 2016                                ║   │
│  ║  4 Databases | 80+ Tables | 200+ Stored Procedures  ║   │
│  ║  25+ SQL Agent Jobs | CLR Assemblies Loaded         ║   │
│  ║  Service Broker: ENABLED                            ║   │
│  ║  TDE Encryption: ACTIVE 🔐                          ║   │
│  ╚══════════════════════════════════════════════════════╝   │
└─────────────────────────────────────────────────────────────┘
```

### 🏥 Lakeview Medical Center — Business Domain

This hospital patient management system is a **beast** 🦖:

- **4 Interconnected Databases**: PatientDB, BillingDB, SchedulingDB, ReportingDB
- **Cross-Database Queries**: `SELECT FROM PatientDB..Patients JOIN BillingDB..BillingCharges`
- **CLR Assemblies**: C# code for drug interaction checks & ICD validation
- **Service Broker**: Async messaging between PatientDB and BillingDB
- **Linked Servers**: External pharmacy and insurance system connections
- **SQL Server Agent**: 25+ scheduled jobs (billing, claims, archival, backups)
- **TDE Encryption**: Certificate-based encryption on PatientDB
- **SSRS Reports**: Embedded SQL queries for patient summaries
- **Windows Authentication**: AD group-based security
- **Database Mail**: Automated job failure notifications

### ⚠️ DEADLOCK DETECTED 💀 — Legacy Anti-Patterns

**WARNING SIGNS:** 🚨

- ❌ **Cross-DB queries** — Not compatible with Azure SQL Database (but OK in Managed Instance!)
- ❌ **CLR with UNSAFE permissions** — Requires PERMISSION_SET adjustment
- ❌ **Linked servers with hardcoded IPs** — Need cloud endpoint reconfiguration
- ❌ **Service Broker on default ports** — May conflict with MI networking
- ❌ **Filestream for imaging** — Limited support in Managed Instance
- ❌ **Unmanaged TDE certs** — Must export and import to MI

---

## 🌌 TARGET ARCHITECTURE

**CLOUD WARP DESTINATION:** ☁️✨

```
┌─────────────────────────────────────────────────────────────┐
│  🟢 AZURE SQL MANAGED INSTANCE                               │
│  ╔══════════════════════════════════════════════════════╗   │
│  ║  🚀 Near-100% SQL Server Compatibility               ║   │
│  ║  ✅ Cross-Database Queries: SUPPORTED                ║   │
│  ║  ✅ SQL Agent Jobs: NATIVE SUPPORT                   ║   │
│  ║  ✅ CLR Assemblies: SUPPORTED                        ║   │
│  ║  ✅ Service Broker: SUPPORTED                        ║   │
│  ║  ✅ Linked Servers: SUPPORTED                        ║   │
│  ║  ✅ TDE: Service-Managed Keys (or BYOK)              ║   │
│  ║  🔐 VNet Integration: PRIVATE ENDPOINTS              ║   │
│  ║  📊 Azure Monitor: BUILT-IN TELEMETRY                ║   │
│  ║  🛡️ Automated Backups: 7-35 DAY RETENTION           ║   │
│  ╚══════════════════════════════════════════════════════╝   │
└─────────────────────────────────────────────────────────────┘
```

### 🎯 Why Azure SQL Managed Instance?

**COMPATIBILITY MATRIX:** 🧮

| Feature                  | SQL Database | SQL Managed Instance | On-Prem SQL Server |
|-------------------------|--------------|----------------------|--------------------|
| Cross-DB Queries        | ❌           | ✅                   | ✅                 |
| SQL Agent Jobs          | ❌           | ✅                   | ✅                 |
| CLR Assemblies          | ❌           | ✅                   | ✅                 |
| Service Broker          | ❌           | ✅                   | ✅                 |
| Linked Servers          | ❌           | ✅                   | ✅                 |
| TDE                     | ✅           | ✅                   | ✅                 |
| VNet Integration        | ✅           | ✅                   | N/A                |

**VERDICT:** For complex enterprise SQL Server workloads with Agent jobs, CLR, and cross-database dependencies, **Managed Instance is the only path forward**. 🛤️

### 🏗️ Architecture Components

- **Azure SQL Managed Instance** — General Purpose (dev/test) or Business Critical (production)
- **Azure Database Migration Service (DMS)** — Online migration with minimal downtime
- **Virtual Network** — Private VNet with delegated subnet for Managed Instance
- **Private Endpoint** — Secure, private connectivity from on-premises
- **Azure Key Vault** — Customer-managed TDE keys (optional)
- **Azure Monitor + SQL Analytics** — Performance monitoring and alerts
- **Power BI** — Modern replacement for SSRS reports
- **GitHub Actions** — CI/CD for infrastructure and validation tests

---

## 🎯 LAB WALKTHROUGH USING COPILOT CLI

**MISSION CONTROL SEQUENCE:** 🧑‍🚀

### 🔍 Phase 1: Pre-Flight Assessment

```powershell
# ASK COPILOT: How do I assess SQL Server compatibility for Azure SQL MI?
gh copilot suggest "assess SQL Server database for Azure SQL Managed Instance migration"

# Run Data Migration Assistant (DMA)
# - Identifies compatibility issues
# - Checks deprecated features
# - Validates CLR assembly permissions
# - Reviews cross-database dependencies

# ✅ ROWS AFFECTED: 0 blockers detected for Managed Instance!
```

### 🏗️ Phase 2: Provision Managed Instance

```powershell
# ASK COPILOT: Deploy Azure SQL Managed Instance with Bicep
gh copilot suggest "deploy Azure SQL Managed Instance using Bicep with VNet integration"

# Deploy infrastructure
az deployment group create \
  --resource-group rg-lakeview-prod \
  --template-file ./Infrastructure/bicep/main.bicep \
  --parameters @./Infrastructure/parameters/production.parameters.json

# ⏳ QUERY EXECUTING... (Managed Instance creation takes 4-6 hours!)
# 💡 TIP: Start this early, work on other tasks while it provisions
```

### 🔐 Phase 3: TDE Certificate Migration

```powershell
# ASK COPILOT: Export TDE certificate from SQL Server
gh copilot suggest "export TDE certificate from SQL Server for migration to Azure SQL MI"

# Export TDE certificate and private key
BACKUP CERTIFICATE TDECert
TO FILE = 'C:\Certs\TDECert.cer'
WITH PRIVATE KEY (
    FILE = 'C:\Certs\TDECert.pvk',
    ENCRYPTION BY PASSWORD = 'StrongPassword123!'
)

# Import to Managed Instance (via Azure Portal or SSMS)
# ✅ TRANSACTION COMMITTED — TDE encryption preserved!
```

### 🚀 Phase 4: Online Migration with DMS

```powershell
# ASK COPILOT: Configure Azure Database Migration Service
gh copilot suggest "set up Azure Database Migration Service for online SQL Server migration"

# 1️⃣ Initial full backup restore
# 2️⃣ Continuous transaction log shipping
# 3️⃣ Minimal lag (< 1 minute) maintained
# 4️⃣ Ready for cutover when lag is minimal

# Monitor migration progress
az dms project task show \
  --resource-group rg-lakeview-prod \
  --service-name dms-lakeview \
  --project-name migration-project \
  --name PatientDB-migration

# ⏳ ROWS AFFECTED: ∞ (streaming transaction logs...)
```

### 🤖 Phase 5: SQL Agent Job Migration

```powershell
# ASK COPILOT: Migrate SQL Server Agent jobs to Azure SQL MI
gh copilot suggest "recreate SQL Server Agent jobs on Azure SQL Managed Instance"

# Script out existing jobs on source
# Recreate on Managed Instance (SQL Agent is natively supported!)
# Update job steps with new connection strings

# ✅ 25 jobs migrated successfully!
```

### 🔗 Phase 6: Reconfigure Linked Servers

```powershell
# ASK COPILOT: Update linked server endpoints for cloud
gh copilot suggest "reconfigure SQL Server linked servers for Azure cloud endpoints"

# Update linked server definitions
EXEC sp_addlinkedserver 
    @server = 'PharmacyLink',
    @srvproduct = '',
    @provider = 'SQLNCLI',
    @datasrc = 'pharmacy-api.cloudprovider.com'

# ✅ LINK ESTABLISHED — Pharmacy and insurance systems online!
```

### ⚙️ Phase 7: Validate CLR & Service Broker

```powershell
# ASK COPILOT: Test CLR assemblies after migration
gh copilot suggest "validate CLR assemblies work correctly on Azure SQL MI"

# Test CLR function
SELECT dbo.CheckDrugInteraction('Aspirin', 'Warfarin')
# ✅ Returns interaction warning — CLR working!

# Test Service Broker messaging
EXEC dbo.SendBillingMessage @PatientId = 12345
# ✅ Message queued and processed — Service Broker operational!
```

### 🎬 Phase 8: Cutover & Validation

```powershell
# ASK COPILOT: Perform final migration cutover
gh copilot suggest "complete database migration cutover with minimal downtime"

# 1️⃣ Stop application traffic
# 2️⃣ Wait for final log sync (< 1 min)
# 3️⃣ Complete cutover in DMS
# 4️⃣ Update app connection strings
# 5️⃣ Resume traffic to Managed Instance

# Run validation tests
sqlcmd -S mi-lakeview.public.abc123.database.windows.net \
       -U sqladmin -P <password> \
       -i ./Tests/cross-database-query-test.sql

# ✅ TRANSACTION COMMITTED — Migration complete! 🎉
```

### 📊 Phase 9: Post-Migration Optimization

```powershell
# ASK COPILOT: Optimize Azure SQL MI performance
gh copilot suggest "performance tuning and monitoring setup for Azure SQL Managed Instance"

# Set up Azure Monitor alerts
# Configure query performance insights
# Migrate SSRS reports to Power BI
# Establish performance baseline

# 🚀 ROWS AFFECTED: ∞ — System running at warp speed!
```

---

## ⏱️ DURATION

**ESTIMATED MISSION TIME:** 🕐

- **Infrastructure Provisioning**: 4-6 hours (Managed Instance creation — runs in background)
- **Assessment & Planning**: 1 hour
- **TDE Certificate Migration**: 30 minutes
- **DMS Configuration**: 1 hour
- **Database Migration (Initial Load)**: 2-4 hours (depends on size)
- **Agent Job Migration**: 1 hour
- **Linked Server Reconfiguration**: 30 minutes
- **Validation & Testing**: 1 hour
- **Cutover**: 30 minutes
- **Post-Migration Tuning**: 1 hour

**💥 TOTAL: 6-8 hours** (active hands-on time, excluding MI provisioning wait)

**🎮 PRO TIP:** Start the Managed Instance provisioning first thing, then work through assessment and prep tasks while it deploys!

---

## 📚 RESOURCES

**KNOWLEDGE DATABASE:** 📡

### 🔗 Official Microsoft Docs

- [Azure SQL Managed Instance Overview](https://learn.microsoft.com/azure/azure-sql/managed-instance/sql-managed-instance-paas-overview)
- [Migration Guide: SQL Server to Azure SQL MI](https://learn.microsoft.com/azure/azure-sql/migration-guides/managed-instance/sql-server-to-managed-instance-guide)
- [Azure Database Migration Service](https://learn.microsoft.com/azure/dms/tutorial-sql-server-managed-instance-online)
- [TDE Certificate Migration](https://learn.microsoft.com/azure/azure-sql/managed-instance/tde-certificate-migrate)
- [SQL Agent Jobs in Managed Instance](https://learn.microsoft.com/azure/azure-sql/managed-instance/job-automation-managed-instance)

### 🛠️ Tools

- [Data Migration Assistant (DMA)](https://www.microsoft.com/download/details.aspx?id=53595)
- [Azure Data Studio](https://docs.microsoft.com/sql/azure-data-studio/download)
- [SQL Server Management Studio (SSMS)](https://docs.microsoft.com/sql/ssms/download-sql-server-management-studio-ssms)
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)

### 🎓 Learning Paths

- [Migrate SQL workloads to Azure](https://learn.microsoft.com/training/paths/migrate-sql-workloads-azure/)
- [Plan and implement data platform resources](https://learn.microsoft.com/training/paths/plan-implement-data-platform-resources/)

### 🌐 Community

- [Azure SQL Community](https://techcommunity.microsoft.com/t5/azure-sql-blog/bg-p/AzureSQLBlog)
- [SQL Server Migration GitHub Discussions](https://github.com/microsoft/sql-server-samples/discussions)

---

## 🎮 GAME OVER... OR GAME START?

```
┌─────────────────────────────────────────────────────────────┐
│  ✅ MISSION COMPLETE!                                        │
│                                                              │
│  🏆 ACHIEVEMENTS UNLOCKED:                                   │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   │
│  ⭐ Database Migration Master                               │
│  ⭐ Zero-Downtime Champion                                  │
│  ⭐ Cloud Architect Elite                                   │
│  ⭐ SQL Compatibility Wizard                                │
│                                                              │
│  📊 FINAL STATS:                                            │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   │
│  Databases Migrated: 4/4                                    │
│  Agent Jobs Recreated: 25/25                                │
│  CLR Assemblies: OPERATIONAL                                │
│  Service Broker: MESSAGING ACTIVE                           │
│  TDE Encryption: PRESERVED                                  │
│  Downtime: < 5 MINUTES! 🔥                                  │
│                                                              │
│  🚀 YOUR DATA IS NOW IN THE CLOUD!                          │
│                                                              │
│  Press START to continue to the next lab...                 │
└─────────────────────────────────────────────────────────────┘

              [CONTINUE] 🎮        [EXIT] 🚪
```

---

**🎵 INSERT COIN TO CONTINUE** 🪙

Need help? Ask **GitHub Copilot CLI**:
```powershell
gh copilot suggest "What's the best way to optimize Azure SQL MI performance?"
```

**Built with 💜 by the EmeaAppGbb Squad** | **Powered by ⚡ Azure & GitHub Copilot**

---

### 📝 License

MIT License — Fork it, clone it, modernize it! 🚀

### 🤝 Contributing

Found a bug? Have a cool optimization tip? Open an issue or PR! We accept contributions in the form of:
- 🐛 Bug fixes
- 📚 Documentation improvements
- ✨ New migration scenarios
- 🎨 More retro ASCII art!

---

**REMEMBER:** With great SQL power comes great migration responsibility! 🕷️💾

```
   _____ ____  __       __  ______
  / ___// __ \/ /      /  |/  /  _/
  \__ \/ / / / /      / /|_/ // /  
 ___/ / /_/ / /___   / /  / // /   
/____/\___\_\____/  /_/  /_/___/   
                                    
   WARP DRIVE: ENGAGED ⚡
```
