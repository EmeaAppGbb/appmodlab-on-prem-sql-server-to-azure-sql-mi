# PowerShell deployment script for Lakeview Medical databases
# Run from the Deployment folder

param(
    [string]$ServerInstance = "localhost,1433",
    [string]$Username = "sa",
    [string]$Password = "LakeviewMedical2024!",
    [switch]$UseTrustedConnection = $false
)

$ErrorActionPreference = "Stop"

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "Lakeview Medical Center - Database Deployment" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host ""

# Build connection string
if ($UseTrustedConnection) {
    $connectionString = "Server=$ServerInstance;Database=master;Integrated Security=True;TrustServerCertificate=True;"
} else {
    $connectionString = "Server=$ServerInstance;Database=master;User Id=$Username;Password=$Password;TrustServerCertificate=True;"
}

function Execute-SqlFile {
    param(
        [string]$FilePath,
        [string]$Description
    )
    
    Write-Host "Executing: $Description" -ForegroundColor Yellow
    Write-Host "  File: $FilePath" -ForegroundColor Gray
    
    try {
        if ($UseTrustedConnection) {
            sqlcmd -S $ServerInstance -E -i $FilePath -I
        } else {
            sqlcmd -S $ServerInstance -U $Username -P $Password -i $FilePath -I
        }
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [SUCCESS]" -ForegroundColor Green
        } else {
            Write-Host "  [FAILED] Exit code: $LASTEXITCODE" -ForegroundColor Red
            throw "SQL execution failed"
        }
    } catch {
        Write-Host "  [ERROR] $_" -ForegroundColor Red
        throw
    }
    Write-Host ""
}

# Get script root directory
$scriptRoot = Split-Path -Parent $PSCommandPath
$projectRoot = Split-Path -Parent $scriptRoot

Write-Host "Project Root: $projectRoot" -ForegroundColor Gray
Write-Host "Server: $ServerInstance" -ForegroundColor Gray
Write-Host ""

# Deployment sequence
try {
    Write-Host "Step 1: Creating PatientDB" -ForegroundColor Cyan
    Execute-SqlFile -FilePath "$projectRoot\Databases\PatientDB\01-CreateDatabase.sql" -Description "Create PatientDB"
    Execute-SqlFile -FilePath "$projectRoot\Databases\PatientDB\02-Tables.sql" -Description "Create PatientDB Tables"
    Execute-SqlFile -FilePath "$projectRoot\Databases\PatientDB\03-Views.sql" -Description "Create PatientDB Views"
    Execute-SqlFile -FilePath "$projectRoot\Databases\PatientDB\04-StoredProcedures.sql" -Description "Create PatientDB Stored Procedures"
    Execute-SqlFile -FilePath "$projectRoot\Databases\PatientDB\05-Functions.sql" -Description "Create PatientDB Functions"
    
    Write-Host "Step 2: Creating BillingDB" -ForegroundColor Cyan
    Execute-SqlFile -FilePath "$projectRoot\Databases\BillingDB\01-CreateDatabase.sql" -Description "Create BillingDB"
    Execute-SqlFile -FilePath "$projectRoot\Databases\BillingDB\02-Tables.sql" -Description "Create BillingDB Tables"
    Execute-SqlFile -FilePath "$projectRoot\Databases\BillingDB\03-StoredProcedures.sql" -Description "Create BillingDB Stored Procedures"
    
    Write-Host "Step 3: Creating SchedulingDB" -ForegroundColor Cyan
    Execute-SqlFile -FilePath "$projectRoot\Databases\SchedulingDB\01-CreateDatabase.sql" -Description "Create SchedulingDB"
    Execute-SqlFile -FilePath "$projectRoot\Databases\SchedulingDB\02-Tables.sql" -Description "Create SchedulingDB Tables"
    
    Write-Host "Step 4: Creating ReportingDB" -ForegroundColor Cyan
    Execute-SqlFile -FilePath "$projectRoot\Databases\ReportingDB\01-CreateDatabase.sql" -Description "Create ReportingDB"
    Execute-SqlFile -FilePath "$projectRoot\Databases\ReportingDB\02-Views.sql" -Description "Create ReportingDB Views"
    
    Write-Host "Step 5: Configuring Service Broker" -ForegroundColor Cyan
    Execute-SqlFile -FilePath "$projectRoot\ServiceBroker\01-ServiceBrokerSetup.sql" -Description "Configure Service Broker"
    
    Write-Host "Step 6: Inserting Sample Data" -ForegroundColor Cyan
    Execute-SqlFile -FilePath "$projectRoot\SeedData\01-InsertSampleData.sql" -Description "Insert Sample Data"
    
    Write-Host "Step 7: Creating Linked Servers" -ForegroundColor Cyan
    Execute-SqlFile -FilePath "$projectRoot\LinkedServers\01-CreateLinkedServers.sql" -Description "Create Linked Servers"
    
    Write-Host "Step 8: Deploying SQL Agent Jobs" -ForegroundColor Cyan
    Execute-SqlFile -FilePath "$projectRoot\SQLAgent\Jobs\01-NightlyBilling.sql" -Description "Create Nightly Billing Job"
    Execute-SqlFile -FilePath "$projectRoot\SQLAgent\Jobs\02-InsuranceClaims.sql" -Description "Create Insurance Claims Job"
    Execute-SqlFile -FilePath "$projectRoot\SQLAgent\Jobs\03-DataArchival.sql" -Description "Create Data Archival Job"
    Execute-SqlFile -FilePath "$projectRoot\SQLAgent\Jobs\04-StatisticsUpdate.sql" -Description "Create Statistics Update Job"
    Execute-SqlFile -FilePath "$projectRoot\SQLAgent\Jobs\05-BackupJob.sql" -Description "Create Backup Job"
    
    Write-Host "Step 9: Creating SQL Agent Alerts" -ForegroundColor Cyan
    Execute-SqlFile -FilePath "$projectRoot\SQLAgent\Alerts\01-DiskSpaceAlert.sql" -Description "Create Disk Space Alert"
    
    Write-Host ""
    Write-Host "=================================================" -ForegroundColor Green
    Write-Host "Deployment Completed Successfully!" -ForegroundColor Green
    Write-Host "=================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Deploy CLR assemblies manually (requires special permissions)" -ForegroundColor Gray
    Write-Host "  2. Configure Database Mail for notifications" -ForegroundColor Gray
    Write-Host "  3. Set up SQL Agent job schedules" -ForegroundColor Gray
    Write-Host "  4. Configure TDE encryption (optional)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Connection Info:" -ForegroundColor Yellow
    Write-Host "  Server: $ServerInstance" -ForegroundColor Gray
    Write-Host "  Databases: PatientDB, BillingDB, SchedulingDB, ReportingDB" -ForegroundColor Gray
    Write-Host ""
    
} catch {
    Write-Host ""
    Write-Host "=================================================" -ForegroundColor Red
    Write-Host "Deployment Failed!" -ForegroundColor Red
    Write-Host "=================================================" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host ""
    exit 1
}
