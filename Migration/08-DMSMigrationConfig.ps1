# ============================================
# Azure DMS Migration Configuration
# Lakeview Medical Center
# Creates and configures an Azure Database
# Migration Service project for online migration
# of PatientDB, BillingDB, SchedulingDB, and
# ReportingDB from SQL Server 2016 to Azure SQL MI.
# ============================================
# Prerequisites:
#   - Az.DataMigration module installed
#   - Authenticated to Azure (Connect-AzAccount)
#   - DMS instance already provisioned
#   - Source SQL Server reachable from DMS via
#     VPN/ExpressRoute or public endpoint
# ============================================

#Requires -Modules Az.DataMigration, Az.Accounts

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$DmsServiceName,

    [Parameter(Mandatory = $true)]
    [string]$SourceServerName,

    [Parameter(Mandatory = $true)]
    [string]$SourceUserName,

    [Parameter(Mandatory = $true)]
    [securestring]$SourcePassword,

    [Parameter(Mandatory = $true)]
    [string]$TargetMIFqdn,

    [Parameter(Mandatory = $true)]
    [string]$TargetUserName,

    [Parameter(Mandatory = $true)]
    [securestring]$TargetPassword,

    [Parameter(Mandatory = $true)]
    [string]$BackupFileSharePath,

    [Parameter(Mandatory = $true)]
    [string]$StorageAccountResourceId,

    [Parameter(Mandatory = $false)]
    [string]$ProjectName = "lakeview-medical-sqlmi-migration",

    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus2"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " Lakeview Medical Center - DMS Online Migration Setup"          -ForegroundColor Cyan
Write-Host " Date    : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"          -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# --------------------------------------------------
# 1. Validate the DMS service is running
# --------------------------------------------------
Write-Host ">> Step 1: Validating DMS service status..." -ForegroundColor Yellow

$dmsService = Get-AzDataMigrationService `
    -ResourceGroupName $ResourceGroupName `
    -Name $DmsServiceName

if ($dmsService.ProvisioningState -ne 'Succeeded') {
    throw "DMS service '$DmsServiceName' is not in a healthy state. Current state: $($dmsService.ProvisioningState)"
}
Write-Host "   DMS service '$DmsServiceName' is healthy." -ForegroundColor Green
Write-Host ""

# --------------------------------------------------
# 2. Build source connection info
# --------------------------------------------------
Write-Host ">> Step 2: Configuring source connection..." -ForegroundColor Yellow

$sourceConnInfo = New-AzDataMigrationConnectionInfo -ServerType SQL
$sourceConnInfo.DataSource = $SourceServerName
$sourceConnInfo.Authentication = "SqlAuthentication"
$sourceConnInfo.TrustServerCertificate = $true
$sourceConnInfo.EncryptConnection = $true

$sourceCred = New-Object System.Management.Automation.PSCredential(
    $SourceUserName, $SourcePassword
)

Write-Host "   Source: $SourceServerName (SQL Authentication)" -ForegroundColor Green
Write-Host ""

# --------------------------------------------------
# 3. Build target connection info
# --------------------------------------------------
Write-Host ">> Step 3: Configuring target connection..." -ForegroundColor Yellow

$targetConnInfo = New-AzDataMigrationConnectionInfo -ServerType SQLMI
$targetConnInfo.DataSource = $TargetMIFqdn
$targetConnInfo.Authentication = "SqlAuthentication"
$targetConnInfo.EncryptConnection = $true

$targetCred = New-Object System.Management.Automation.PSCredential(
    $TargetUserName, $TargetPassword
)

Write-Host "   Target: $TargetMIFqdn (SQL MI)" -ForegroundColor Green
Write-Host ""

# --------------------------------------------------
# 4. Create the DMS project
# --------------------------------------------------
Write-Host ">> Step 4: Creating DMS project '$ProjectName'..." -ForegroundColor Yellow

$existingProject = Get-AzDataMigrationProject `
    -ResourceGroupName $ResourceGroupName `
    -ServiceName $DmsServiceName `
    -Name $ProjectName `
    -ErrorAction SilentlyContinue

if ($existingProject) {
    Write-Host "   Project '$ProjectName' already exists. Reusing." -ForegroundColor Yellow
} else {
    $existingProject = New-AzDataMigrationProject `
        -ResourceGroupName $ResourceGroupName `
        -ServiceName $DmsServiceName `
        -Name $ProjectName `
        -Location $Location `
        -SourceType SQL `
        -TargetType SQLMI

    Write-Host "   Project '$ProjectName' created." -ForegroundColor Green
}
Write-Host ""

# --------------------------------------------------
# 5. Configure backup file share
# --------------------------------------------------
Write-Host ">> Step 5: Configuring backup file share..." -ForegroundColor Yellow

$backupFileShare = New-AzDataMigrationFileShare `
    -Path $BackupFileSharePath `
    -Credential $sourceCred

Write-Host "   Backup share: $BackupFileSharePath" -ForegroundColor Green
Write-Host ""

# --------------------------------------------------
# 6. Configure selected databases and create tasks
# --------------------------------------------------
Write-Host ">> Step 6: Creating online migration tasks for each database..." -ForegroundColor Yellow
Write-Host ""

$databases = @("PatientDB", "BillingDB", "SchedulingDB", "ReportingDB")

foreach ($dbName in $databases) {
    Write-Host "   --- $dbName ---" -ForegroundColor Cyan
    $taskName = "migrate-$($dbName.ToLower())-online"

    # Database mapping: source -> target (same name)
    $selectedDb = New-AzDataMigrationSelectedDB `
        -MigrationPlatform "SqlServerSqlMI" `
        -Name $dbName `
        -TargetDatabaseName $dbName `
        -BackupFileShare $backupFileShare

    # Create the online migration task
    $migrationTask = New-AzDataMigrationTask `
        -ResourceGroupName $ResourceGroupName `
        -ServiceName $DmsServiceName `
        -ProjectName $ProjectName `
        -TaskName $taskName `
        -TaskType "MigrateSqlServerSqlMISync" `
        -SourceConnection $sourceConnInfo `
        -SourceCred $sourceCred `
        -TargetConnection $targetConnInfo `
        -TargetCred $targetCred `
        -SelectedDatabase $selectedDb `
        -BackupBlobShare @{
            SasUri = (New-AzStorageAccountSASToken `
                -Service Blob `
                -ResourceType Container, Object `
                -Permission "rwdl" `
                -ExpiryTime (Get-Date).AddDays(30) `
                -Context (Get-AzStorageAccount `
                    -ResourceGroupName $ResourceGroupName `
                    -Name ($StorageAccountResourceId -split '/')[-1]
                ).Context
            )
            StorageAccountResourceId = $StorageAccountResourceId
        }

    Write-Host "   Task '$taskName' created. State: $($migrationTask.Properties.State)" -ForegroundColor Green
    Write-Host ""
}

# --------------------------------------------------
# 7. Display migration status summary
# --------------------------------------------------
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " Migration Tasks Summary"                                        -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$tasks = Get-AzDataMigrationTask `
    -ResourceGroupName $ResourceGroupName `
    -ServiceName $DmsServiceName `
    -ProjectName $ProjectName

foreach ($task in $tasks) {
    $state = $task.Properties.State
    $color = switch ($state) {
        'Running'   { 'Green' }
        'Succeeded' { 'Green' }
        'Failed'    { 'Red' }
        default     { 'Yellow' }
    }
    Write-Host ("  {0,-40} {1}" -f $task.Name, $state) -ForegroundColor $color
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " Next Steps"                                                      -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Monitor each migration task until initial backup restore"
Write-Host "     completes and continuous sync begins."
Write-Host "  2. Validate data integrity on the target SQL MI."
Write-Host "  3. When ready for cutover, stop application writes to source."
Write-Host "  4. Wait for final log backup to apply, then initiate cutover:"
Write-Host ""
Write-Host '     Invoke-AzDataMigrationCommand \'
Write-Host '       -ResourceGroupName $ResourceGroupName \'
Write-Host '       -ServiceName $DmsServiceName \'
Write-Host '       -ProjectName $ProjectName \'
Write-Host '       -TaskName "migrate-patientdb-online" \'
Write-Host '       -CommandType CompleteSqlMiSync \'
Write-Host '       -DatabaseName "PatientDB"'
Write-Host ""
Write-Host "  5. Repeat cutover for each database."
Write-Host "  6. Update application connection strings to the SQL MI endpoint."
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " DMS configuration complete."                                     -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
