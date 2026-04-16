# ============================================
# Connection String Update for Azure SQL MI
# Lakeview Medical Center
# Updates application connection strings from
# on-premises SQL Server to the Azure SQL
# Managed Instance endpoint. Stores updated
# connection strings securely in Azure Key Vault.
# ============================================
# Prerequisites:
#   - Az.KeyVault module installed
#   - Az.Sql module installed (for MI validation)
#   - Authenticated to Azure (Connect-AzAccount)
#   - Key Vault access policy or RBAC granting
#     Secret Get/Set to the executing identity
#   - MI endpoint reachable from this machine
# ============================================

#Requires -Modules Az.KeyVault, Az.Sql, Az.Accounts

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$ManagedInstanceName,

    [Parameter(Mandatory = $true,
        HelpMessage = "FQDN of the Azure SQL MI (e.g., myinstance.abc123.database.windows.net)")]
    [string]$MIEndpoint,

    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $false,
        HelpMessage = "On-premises SQL Server hostname to replace in connection strings")]
    [string]$OnPremServerName = "<ON-PREM-SQL-SERVER>",

    [Parameter(Mandatory = $false)]
    [string[]]$DatabaseNames = @("PatientDB", "BillingDB", "SchedulingDB", "ReportingDB"),

    [Parameter(Mandatory = $false,
        HelpMessage = "App Service names whose connection strings should be updated")]
    [string[]]$AppServiceNames = @(),

    [Parameter(Mandatory = $false)]
    [string]$AppServiceResourceGroup = "",

    [Parameter(Mandatory = $false,
        HelpMessage = "Skip connectivity test to MI endpoint")]
    [switch]$SkipConnectivityTest,

    [Parameter(Mandatory = $false,
        HelpMessage = "Generate rollback script")]
    [switch]$GenerateRollback
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " Lakeview Medical Center - Connection String Update"             -ForegroundColor Cyan
Write-Host " Date    : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"           -ForegroundColor Cyan
Write-Host " Target  : $MIEndpoint"                                          -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# --------------------------------------------------
# 1. Validate Azure SQL Managed Instance
# --------------------------------------------------
Write-Host ">> Step 1: Validating Managed Instance..." -ForegroundColor Yellow

$mi = Get-AzSqlInstance `
    -ResourceGroupName $ResourceGroupName `
    -Name $ManagedInstanceName `
    -ErrorAction Stop

if ($mi.State -ne 'Ready') {
    throw "Managed Instance '$ManagedInstanceName' is not in Ready state. Current state: $($mi.State)"
}

$miFqdn = $mi.FullyQualifiedDomainName
Write-Host "   MI Name   : $ManagedInstanceName" -ForegroundColor Green
Write-Host "   MI FQDN   : $miFqdn" -ForegroundColor Green
Write-Host "   MI State  : $($mi.State)" -ForegroundColor Green
Write-Host "   MI SKU    : $($mi.Sku.Name) ($($mi.Sku.Tier))" -ForegroundColor Green
Write-Host ""

# --------------------------------------------------
# 2. Test connectivity to the MI endpoint
# --------------------------------------------------
if (-not $SkipConnectivityTest) {
    Write-Host ">> Step 2: Testing connectivity to MI endpoint..." -ForegroundColor Yellow

    $port = 1433
    try {
        $tcpTest = Test-NetConnection -ComputerName $MIEndpoint -Port $port -WarningAction SilentlyContinue
        if ($tcpTest.TcpTestSucceeded) {
            Write-Host "   TCP connection to ${MIEndpoint}:${port} succeeded." -ForegroundColor Green
        } else {
            Write-Host "   WARNING: TCP connection to ${MIEndpoint}:${port} failed." -ForegroundColor Red
            Write-Host "   Ensure the MI is accessible from this network (VPN/ExpressRoute/public endpoint)." -ForegroundColor Red
            Write-Host "   Continuing anyway — connection may work from the application network." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "   WARNING: Could not test connectivity: $_" -ForegroundColor Yellow
    }
    Write-Host ""
} else {
    Write-Host ">> Step 2: Connectivity test SKIPPED." -ForegroundColor Yellow
    Write-Host ""
}

# --------------------------------------------------
# 3. Validate Key Vault access
# --------------------------------------------------
Write-Host ">> Step 3: Validating Key Vault access..." -ForegroundColor Yellow

$kv = Get-AzKeyVault -VaultName $KeyVaultName -ErrorAction Stop

Write-Host "   Key Vault : $KeyVaultName" -ForegroundColor Green
Write-Host "   Location  : $($kv.Location)" -ForegroundColor Green
Write-Host ""

# --------------------------------------------------
# 4. Build new connection strings
# --------------------------------------------------
Write-Host ">> Step 4: Building new connection strings..." -ForegroundColor Yellow
Write-Host ""

$connectionStrings = @{}

foreach ($dbName in $DatabaseNames) {
    # ADO.NET connection string for Azure SQL MI
    $connStr = "Server=tcp:${MIEndpoint},1433;" +
               "Initial Catalog=${dbName};" +
               "Persist Security Info=False;" +
               "MultipleActiveResultSets=False;" +
               "Encrypt=True;" +
               "TrustServerCertificate=False;" +
               "Connection Timeout=30;" +
               "Authentication=Active Directory Default;"

    $connectionStrings[$dbName] = $connStr

    Write-Host "   $dbName :" -ForegroundColor Cyan
    Write-Host "     $connStr" -ForegroundColor Gray
    Write-Host ""
}

# Also build a SQL-auth template for services that require it
$sqlAuthTemplate = @{}
foreach ($dbName in $DatabaseNames) {
    $connStr = "Server=tcp:${MIEndpoint},1433;" +
               "Initial Catalog=${dbName};" +
               "Persist Security Info=False;" +
               "User ID=<SQL-USERNAME>;" +
               "Password=<SQL-PASSWORD>;" +
               "MultipleActiveResultSets=False;" +
               "Encrypt=True;" +
               "TrustServerCertificate=False;" +
               "Connection Timeout=30;"

    $sqlAuthTemplate[$dbName] = $connStr
}

# --------------------------------------------------
# 5. Store connection strings in Azure Key Vault
# --------------------------------------------------
Write-Host ">> Step 5: Storing connection strings in Key Vault..." -ForegroundColor Yellow
Write-Host ""

$secretsCreated = @()

foreach ($dbName in $DatabaseNames) {
    # Store AAD-auth connection string
    $secretName = "ConnectionString-$dbName"
    $secretValue = ConvertTo-SecureString -String $connectionStrings[$dbName] -AsPlainText -Force

    if ($PSCmdlet.ShouldProcess($secretName, "Set Key Vault secret")) {
        Set-AzKeyVaultSecret `
            -VaultName $KeyVaultName `
            -Name $secretName `
            -SecretValue $secretValue `
            -ContentType "text/plain" `
            -Tag @{
                Purpose     = "SQL MI connection string"
                Database    = $dbName
                Environment = "Production"
                UpdatedBy   = "23-ConnectionStringUpdate.ps1"
                UpdatedAt   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                AuthType    = "AAD"
            } | Out-Null

        $secretsCreated += $secretName
        Write-Host "   Stored: $secretName (AAD auth)" -ForegroundColor Green
    }

    # Store SQL-auth template
    $sqlSecretName = "ConnectionString-$dbName-SQLAuth"
    $sqlSecretValue = ConvertTo-SecureString -String $sqlAuthTemplate[$dbName] -AsPlainText -Force

    if ($PSCmdlet.ShouldProcess($sqlSecretName, "Set Key Vault secret")) {
        Set-AzKeyVaultSecret `
            -VaultName $KeyVaultName `
            -Name $sqlSecretName `
            -SecretValue $sqlSecretValue `
            -ContentType "text/plain" `
            -Tag @{
                Purpose     = "SQL MI connection string (SQL auth template)"
                Database    = $dbName
                Environment = "Production"
                UpdatedBy   = "23-ConnectionStringUpdate.ps1"
                UpdatedAt   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                AuthType    = "SQL"
                Note        = "Replace <SQL-USERNAME> and <SQL-PASSWORD> with actual credentials"
            } | Out-Null

        $secretsCreated += $sqlSecretName
        Write-Host "   Stored: $sqlSecretName (SQL auth template)" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "   Total secrets created/updated: $($secretsCreated.Count)" -ForegroundColor Green
Write-Host ""

# --------------------------------------------------
# 6. Store old connection string references for
#    rollback (if requested)
# --------------------------------------------------
if ($GenerateRollback) {
    Write-Host ">> Step 6: Generating rollback references..." -ForegroundColor Yellow
    Write-Host ""

    foreach ($dbName in $DatabaseNames) {
        $rollbackSecretName = "ConnectionString-$dbName-OnPrem-Rollback"
        $rollbackConnStr = "Server=${OnPremServerName};" +
                           "Initial Catalog=${dbName};" +
                           "Integrated Security=True;" +
                           "Encrypt=False;" +
                           "Connection Timeout=30;"

        $rollbackSecretValue = ConvertTo-SecureString -String $rollbackConnStr -AsPlainText -Force

        if ($PSCmdlet.ShouldProcess($rollbackSecretName, "Set Key Vault secret (rollback)")) {
            Set-AzKeyVaultSecret `
                -VaultName $KeyVaultName `
                -Name $rollbackSecretName `
                -SecretValue $rollbackSecretValue `
                -ContentType "text/plain" `
                -Tag @{
                    Purpose     = "Rollback connection string (on-premises)"
                    Database    = $dbName
                    Environment = "OnPremises-Rollback"
                    UpdatedBy   = "23-ConnectionStringUpdate.ps1"
                    UpdatedAt   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                } | Out-Null

            Write-Host "   Stored rollback: $rollbackSecretName" -ForegroundColor Yellow
        }
    }
    Write-Host ""
} else {
    Write-Host ">> Step 6: Rollback reference generation SKIPPED (use -GenerateRollback to enable)." -ForegroundColor Yellow
    Write-Host ""
}

# --------------------------------------------------
# 7. Update Azure App Service connection strings
#    (if app service names provided)
# --------------------------------------------------
if ($AppServiceNames.Count -gt 0) {
    Write-Host ">> Step 7: Updating App Service connection strings..." -ForegroundColor Yellow
    Write-Host ""

    $appRg = if ($AppServiceResourceGroup) { $AppServiceResourceGroup } else { $ResourceGroupName }

    foreach ($appName in $AppServiceNames) {
        Write-Host "   --- $appName ---" -ForegroundColor Cyan

        try {
            $webApp = Get-AzWebApp -ResourceGroupName $appRg -Name $appName -ErrorAction Stop

            # Build connection string hashtable for all databases
            $newConnStrings = @{}
            foreach ($dbName in $DatabaseNames) {
                $newConnStrings[$dbName] = @{
                    Type  = "SQLAzure"
                    Value = $connectionStrings[$dbName]
                }
            }

            if ($PSCmdlet.ShouldProcess($appName, "Update App Service connection strings")) {
                Set-AzWebApp `
                    -ResourceGroupName $appRg `
                    -Name $appName `
                    -ConnectionStrings $newConnStrings | Out-Null

                Write-Host "   Updated connection strings for: $appName" -ForegroundColor Green
            }
        } catch {
            Write-Host "   ERROR updating ${appName}: $_" -ForegroundColor Red
        }
        Write-Host ""
    }
} else {
    Write-Host ">> Step 7: App Service update SKIPPED (no App Services specified)." -ForegroundColor Yellow
    Write-Host "   To update App Services, pass -AppServiceNames @('app1', 'app2')." -ForegroundColor Gray
    Write-Host ""
}

# --------------------------------------------------
# 8. Generate Key Vault reference URIs for apps
# --------------------------------------------------
Write-Host ">> Step 8: Key Vault Reference URIs..." -ForegroundColor Yellow
Write-Host ""
Write-Host "   Use these Key Vault references in App Service configuration," -ForegroundColor Gray
Write-Host "   Azure Functions, or other services that support KV references:" -ForegroundColor Gray
Write-Host ""

foreach ($dbName in $DatabaseNames) {
    $secretName = "ConnectionString-$dbName"
    $kvUri = "@Microsoft.KeyVault(VaultName=${KeyVaultName};SecretName=${secretName})"
    Write-Host "   $dbName :" -ForegroundColor Cyan
    Write-Host "     $kvUri" -ForegroundColor White
    Write-Host ""
}

# --------------------------------------------------
# 9. Verification summary
# --------------------------------------------------
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " CONNECTION STRING UPDATE — SUMMARY"                              -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  MI Endpoint      : $MIEndpoint"
Write-Host "  Key Vault        : $KeyVaultName"
Write-Host "  Databases        : $($DatabaseNames -join ', ')"
Write-Host "  Secrets Created  : $($secretsCreated.Count)"
Write-Host "  App Services     : $(if ($AppServiceNames.Count -gt 0) { $AppServiceNames -join ', ' } else { 'None (manual update)' })"
Write-Host ""
Write-Host "  Key Vault Secrets:" -ForegroundColor Cyan
foreach ($s in $secretsCreated) {
    Write-Host "    - $s" -ForegroundColor Green
}
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " Next Steps"                                                       -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  1. Verify Key Vault secrets:"
Write-Host "     Get-AzKeyVaultSecret -VaultName $KeyVaultName | Where-Object { `$_.Name -like 'ConnectionString-*' }"
Write-Host ""
Write-Host "  2. Update application configurations to use Key Vault references"
Write-Host "     or retrieve secrets at runtime."
Write-Host ""
Write-Host "  3. If using App Configuration, add the Key Vault references there."
Write-Host ""
Write-Host "  4. Restart application services to pick up new connection strings."
Write-Host ""
Write-Host "  5. Verify application connectivity to each database on the MI."
Write-Host ""
Write-Host "  6. Monitor application logs for connection errors."
Write-Host ""
Write-Host "  7. Follow 24-CutoverChecklist.md for remaining post-cutover tasks."
Write-Host ""
if ($GenerateRollback) {
    Write-Host "  ROLLBACK: To revert to on-premises connection strings:" -ForegroundColor Yellow
    Write-Host "    foreach (`$db in @($($DatabaseNames | ForEach-Object { "'$_'" } | Join-String -Separator ', '))) {" -ForegroundColor Yellow
    Write-Host "        `$secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name `"ConnectionString-`$db-OnPrem-Rollback`"" -ForegroundColor Yellow
    Write-Host "        # Apply the rollback connection string to your applications" -ForegroundColor Yellow
    Write-Host "    }" -ForegroundColor Yellow
    Write-Host ""
}
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " Connection string update complete."                               -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
