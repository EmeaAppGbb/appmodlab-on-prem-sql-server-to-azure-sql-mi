# ============================================
# Step 26 - Azure Monitor & SQL Analytics Setup
# Lakeview Medical Center
# Configures Azure Monitor and SQL Analytics for
# the Azure SQL Managed Instance: creates a Log
# Analytics workspace, enables diagnostic settings,
# and sets up alerts for high CPU, storage,
# deadlocks, and long-running queries.
# ============================================
# Prerequisites:
#   - Az.Monitor module installed
#   - Az.OperationalInsights module installed
#   - Az.Sql module installed
#   - Az.Resources module installed
#   - Authenticated to Azure (Connect-AzAccount)
#   - Contributor role on the resource group
# ============================================

#Requires -Modules Az.Monitor, Az.OperationalInsights, Az.Sql, Az.Resources

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$ManagedInstanceName,

    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus2",

    [Parameter(Mandatory = $false)]
    [string]$WorkspaceName = "law-lakeview-mi-lab",

    [Parameter(Mandatory = $false)]
    [string]$ActionGroupName = "ag-lakeview-dba",

    [Parameter(Mandatory = $false)]
    [string]$AlertEmailAddress = "dba-team@lakeviewmedical.org",

    [Parameter(Mandatory = $false)]
    [string]$AlertEmailName = "DBA Team",

    [Parameter(Mandatory = $false)]
    [int]$WorkspaceRetentionDays = 90,

    [Parameter(Mandatory = $false)]
    [int]$CpuThresholdPercent = 80,

    [Parameter(Mandatory = $false)]
    [int]$StorageThresholdPercent = 85,

    [Parameter(Mandatory = $false)]
    [int]$LongQueryThresholdSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " Lakeview Medical Center - Azure Monitor & SQL Analytics Setup"   -ForegroundColor Cyan
Write-Host " Date    : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"            -ForegroundColor Cyan
Write-Host " Instance: $ManagedInstanceName"                                  -ForegroundColor Cyan
Write-Host " RG      : $ResourceGroupName"                                    -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$DatabaseNames = @("PatientDB", "BillingDB", "SchedulingDB", "ReportingDB")

# --------------------------------------------------
# Step 1. Validate Managed Instance exists
# --------------------------------------------------
Write-Host ">> Step 1: Validating Managed Instance..." -ForegroundColor Yellow

try {
    $mi = Get-AzSqlInstance `
        -ResourceGroupName $ResourceGroupName `
        -Name $ManagedInstanceName

    Write-Host "   MI found: $($mi.FullyQualifiedDomainName)" -ForegroundColor Green
    Write-Host "   State   : $($mi.State)" -ForegroundColor Green
    $miResourceId = $mi.Id
}
catch {
    throw "Managed Instance '$ManagedInstanceName' not found in resource group '$ResourceGroupName'. Error: $_"
}
Write-Host ""

# --------------------------------------------------
# Step 2. Create Log Analytics Workspace
# --------------------------------------------------
Write-Host ">> Step 2: Creating Log Analytics workspace..." -ForegroundColor Yellow

$workspace = Get-AzOperationalInsightsWorkspace `
    -ResourceGroupName $ResourceGroupName `
    -Name $WorkspaceName `
    -ErrorAction SilentlyContinue

if ($null -eq $workspace) {
    if ($PSCmdlet.ShouldProcess($WorkspaceName, "Create Log Analytics Workspace")) {
        $workspace = New-AzOperationalInsightsWorkspace `
            -ResourceGroupName $ResourceGroupName `
            -Name $WorkspaceName `
            -Location $Location `
            -Sku PerGB2018 `
            -RetentionInDays $WorkspaceRetentionDays `
            -Tag @{
                project     = "lakeview-medical"
                environment = "lab"
                purpose     = "sql-mi-monitoring"
            }

        Write-Host "   Workspace created: $WorkspaceName" -ForegroundColor Green
    }
}
else {
    Write-Host "   Workspace already exists: $WorkspaceName" -ForegroundColor Green
}

$workspaceId = $workspace.ResourceId
Write-Host "   Workspace ID: $workspaceId" -ForegroundColor Gray
Write-Host ""

# --------------------------------------------------
# Step 3. Enable SQL Analytics Solution
# --------------------------------------------------
Write-Host ">> Step 3: Enabling SQL Analytics solution..." -ForegroundColor Yellow

$solutionName = "SQLAdvancedThreatProtection($WorkspaceName)"
$existingSolution = Get-AzMonitorLogAnalyticsSolution `
    -ResourceGroupName $ResourceGroupName `
    -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like "AzureSQLAnalytics*" }

if ($null -eq $existingSolution) {
    if ($PSCmdlet.ShouldProcess("AzureSQLAnalytics", "Enable SQL Analytics Solution")) {
        New-AzMonitorLogAnalyticsSolution `
            -ResourceGroupName $ResourceGroupName `
            -WorkspaceResourceId $workspaceId `
            -Type "AzureSQLAnalytics" `
            -ErrorAction SilentlyContinue

        Write-Host "   SQL Analytics solution enabled." -ForegroundColor Green
    }
}
else {
    Write-Host "   SQL Analytics solution already enabled." -ForegroundColor Green
}
Write-Host ""

# --------------------------------------------------
# Step 4. Configure Diagnostic Settings on MI
# --------------------------------------------------
Write-Host ">> Step 4: Configuring diagnostic settings on MI..." -ForegroundColor Yellow

$diagnosticSettingName = "diag-lakeview-mi-loganalytics"

$logCategories = @(
    "SQLInsights",
    "AutomaticTuning",
    "QueryStoreRuntimeStatistics",
    "QueryStoreWaitStatistics",
    "Errors",
    "DatabaseWaitStatistics",
    "Timeouts",
    "Blocks",
    "Deadlocks",
    "ResourceUsageStats",
    "SQLSecurityAuditEvents"
)

$metricCategories = @(
    "Basic",
    "InstanceAndAppAdvanced",
    "WorkloadManagement"
)

if ($PSCmdlet.ShouldProcess($ManagedInstanceName, "Configure Diagnostic Settings")) {
    $logSettings = $logCategories | ForEach-Object {
        New-AzDiagnosticSettingLogSettingsObject `
            -Enabled $true `
            -Category $_
    }

    $metricSettings = $metricCategories | ForEach-Object {
        New-AzDiagnosticSettingMetricSettingsObject `
            -Enabled $true `
            -Category $_
    }

    New-AzDiagnosticSetting `
        -Name $diagnosticSettingName `
        -ResourceId $miResourceId `
        -WorkspaceId $workspaceId `
        -Log $logSettings `
        -Metric $metricSettings `
        -ErrorAction Stop

    Write-Host "   Diagnostic settings configured on MI." -ForegroundColor Green
    Write-Host "   Log categories : $($logCategories -join ', ')" -ForegroundColor Gray
    Write-Host "   Metric categories: $($metricCategories -join ', ')" -ForegroundColor Gray
}
Write-Host ""

# --------------------------------------------------
# Step 5. Configure Diagnostic Settings on Databases
# --------------------------------------------------
Write-Host ">> Step 5: Configuring diagnostic settings on databases..." -ForegroundColor Yellow

foreach ($dbName in $DatabaseNames) {
    Write-Host "   Configuring diagnostics for [$dbName]..." -ForegroundColor Gray

    try {
        $db = Get-AzSqlInstanceDatabase `
            -ResourceGroupName $ResourceGroupName `
            -InstanceName $ManagedInstanceName `
            -Name $dbName `
            -ErrorAction Stop

        $dbDiagName = "diag-$($dbName.ToLower())-loganalytics"

        if ($PSCmdlet.ShouldProcess($dbName, "Configure Database Diagnostic Settings")) {
            $dbLogSettings = $logCategories | ForEach-Object {
                New-AzDiagnosticSettingLogSettingsObject `
                    -Enabled $true `
                    -Category $_
            }

            $dbMetricSettings = $metricCategories | ForEach-Object {
                New-AzDiagnosticSettingMetricSettingsObject `
                    -Enabled $true `
                    -Category $_
            }

            New-AzDiagnosticSetting `
                -Name $dbDiagName `
                -ResourceId $db.Id `
                -WorkspaceId $workspaceId `
                -Log $dbLogSettings `
                -Metric $dbMetricSettings `
                -ErrorAction Stop

            Write-Host "   [$dbName] diagnostics enabled." -ForegroundColor Green
        }
    }
    catch {
        Write-Host "   WARNING: Could not configure diagnostics for [$dbName]: $_" -ForegroundColor Red
    }
}
Write-Host ""

# --------------------------------------------------
# Step 6. Create Action Group for Alerts
# --------------------------------------------------
Write-Host ">> Step 6: Creating action group for alert notifications..." -ForegroundColor Yellow

$existingAg = Get-AzActionGroup `
    -ResourceGroupName $ResourceGroupName `
    -Name $ActionGroupName `
    -ErrorAction SilentlyContinue

if ($null -eq $existingAg) {
    if ($PSCmdlet.ShouldProcess($ActionGroupName, "Create Action Group")) {
        $emailReceiver = New-AzActionGroupEmailReceiverObject `
            -Name $AlertEmailName `
            -EmailAddress $AlertEmailAddress

        $actionGroup = Set-AzActionGroup `
            -ResourceGroupName $ResourceGroupName `
            -Name $ActionGroupName `
            -ShortName "LkviewDBA" `
            -EmailReceiver $emailReceiver `
            -Tag @{
                project     = "lakeview-medical"
                environment = "lab"
                purpose     = "sql-mi-alerts"
            }

        Write-Host "   Action group created: $ActionGroupName" -ForegroundColor Green
        $actionGroupId = $actionGroup.Id
    }
}
else {
    Write-Host "   Action group already exists: $ActionGroupName" -ForegroundColor Green
    $actionGroupId = $existingAg.Id
}
Write-Host ""

# --------------------------------------------------
# Step 7. Create Alert - High CPU Usage
# --------------------------------------------------
Write-Host ">> Step 7: Creating alert rule - High CPU ($CpuThresholdPercent%)..." -ForegroundColor Yellow

$cpuAlertName = "alert-lakeview-mi-high-cpu"

if ($PSCmdlet.ShouldProcess($cpuAlertName, "Create High CPU Alert")) {
    $cpuCondition = New-AzMetricAlertRuleV2Criteria `
        -MetricName "avg_cpu_percent" `
        -MetricNamespace "Microsoft.Sql/managedInstances" `
        -TimeAggregation Average `
        -Operator GreaterThan `
        -Threshold $CpuThresholdPercent

    $actionGroupRef = New-AzActionGroup -ActionGroupId $actionGroupId

    Add-AzMetricAlertRuleV2 `
        -Name $cpuAlertName `
        -ResourceGroupName $ResourceGroupName `
        -WindowSize (New-TimeSpan -Minutes 15) `
        -Frequency (New-TimeSpan -Minutes 5) `
        -TargetResourceId $miResourceId `
        -Condition $cpuCondition `
        -ActionGroup $actionGroupRef `
        -Severity 2 `
        -Description "Alert when MI average CPU exceeds $CpuThresholdPercent% for 15 minutes." `
        -Tag @{ project = "lakeview-medical"; alertType = "cpu" }

    Write-Host "   CPU alert created: threshold = $CpuThresholdPercent%" -ForegroundColor Green
}
Write-Host ""

# --------------------------------------------------
# Step 8. Create Alert - High Storage Usage
# --------------------------------------------------
Write-Host ">> Step 8: Creating alert rule - High Storage ($StorageThresholdPercent%)..." -ForegroundColor Yellow

$storageAlertName = "alert-lakeview-mi-high-storage"

if ($PSCmdlet.ShouldProcess($storageAlertName, "Create High Storage Alert")) {
    $storageCondition = New-AzMetricAlertRuleV2Criteria `
        -MetricName "storage_space_used_mb" `
        -MetricNamespace "Microsoft.Sql/managedInstances" `
        -TimeAggregation Average `
        -Operator GreaterThan `
        -Threshold ($mi.StorageSizeInGB * 1024 * $StorageThresholdPercent / 100)

    Add-AzMetricAlertRuleV2 `
        -Name $storageAlertName `
        -ResourceGroupName $ResourceGroupName `
        -WindowSize (New-TimeSpan -Minutes 30) `
        -Frequency (New-TimeSpan -Minutes 15) `
        -TargetResourceId $miResourceId `
        -Condition $storageCondition `
        -ActionGroup $actionGroupRef `
        -Severity 2 `
        -Description "Alert when MI storage exceeds $StorageThresholdPercent% of allocated capacity." `
        -Tag @{ project = "lakeview-medical"; alertType = "storage" }

    Write-Host "   Storage alert created: threshold = $StorageThresholdPercent%" -ForegroundColor Green
}
Write-Host ""

# --------------------------------------------------
# Step 9. Create Alert - Deadlocks (Log-based)
# --------------------------------------------------
Write-Host ">> Step 9: Creating alert rule - Deadlocks..." -ForegroundColor Yellow

$deadlockAlertName = "alert-lakeview-mi-deadlocks"

if ($PSCmdlet.ShouldProcess($deadlockAlertName, "Create Deadlock Alert")) {
    $deadlockQuery = @"
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.SQL"
| where Category == "Deadlocks"
| where ResourceId contains "$ManagedInstanceName"
| summarize DeadlockCount = count() by bin(TimeGenerated, 15m)
| where DeadlockCount > 0
"@

    $deadlockCondition = New-AzScheduledQueryRuleConditionObject `
        -Query $deadlockQuery `
        -TimeAggregation Count `
        -Operator GreaterThan `
        -Threshold 0 `
        -FailingPeriodNumberOfEvaluationPeriod 1 `
        -FailingPeriodMinFailingPeriodsToAlert 1

    New-AzScheduledQueryRule `
        -Name $deadlockAlertName `
        -ResourceGroupName $ResourceGroupName `
        -Location $Location `
        -DisplayName "Lakeview MI - Deadlock Detected" `
        -Description "Alert when any deadlock is detected on the Managed Instance." `
        -Scope $workspaceId `
        -Severity 1 `
        -WindowSize (New-TimeSpan -Minutes 15) `
        -EvaluationFrequency (New-TimeSpan -Minutes 5) `
        -CriterionAllOf $deadlockCondition `
        -ActionGroupResourceId $actionGroupId `
        -Enabled $true `
        -Tag @{ project = "lakeview-medical"; alertType = "deadlock" }

    Write-Host "   Deadlock alert created." -ForegroundColor Green
}
Write-Host ""

# --------------------------------------------------
# Step 10. Create Alert - Long-Running Queries
# --------------------------------------------------
Write-Host ">> Step 10: Creating alert rule - Long-Running Queries (>${LongQueryThresholdSeconds}s)..." -ForegroundColor Yellow

$longQueryAlertName = "alert-lakeview-mi-long-queries"

if ($PSCmdlet.ShouldProcess($longQueryAlertName, "Create Long-Running Query Alert")) {
    $longQueryKql = @"
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.SQL"
| where Category == "QueryStoreRuntimeStatistics"
| where ResourceId contains "$ManagedInstanceName"
| extend duration_s = todouble(duration_d) / 1000000
| where duration_s > $LongQueryThresholdSeconds
| summarize LongQueryCount = count() by bin(TimeGenerated, 15m)
| where LongQueryCount > 0
"@

    $longQueryCondition = New-AzScheduledQueryRuleConditionObject `
        -Query $longQueryKql `
        -TimeAggregation Count `
        -Operator GreaterThan `
        -Threshold 0 `
        -FailingPeriodNumberOfEvaluationPeriod 1 `
        -FailingPeriodMinFailingPeriodsToAlert 1

    New-AzScheduledQueryRule `
        -Name $longQueryAlertName `
        -ResourceGroupName $ResourceGroupName `
        -Location $Location `
        -DisplayName "Lakeview MI - Long-Running Query Detected" `
        -Description "Alert when queries exceed ${LongQueryThresholdSeconds}s execution time." `
        -Scope $workspaceId `
        -Severity 3 `
        -WindowSize (New-TimeSpan -Minutes 15) `
        -EvaluationFrequency (New-TimeSpan -Minutes 5) `
        -CriterionAllOf $longQueryCondition `
        -ActionGroupResourceId $actionGroupId `
        -Enabled $true `
        -Tag @{ project = "lakeview-medical"; alertType = "long-query" }

    Write-Host "   Long-running query alert created: threshold = ${LongQueryThresholdSeconds}s" -ForegroundColor Green
}
Write-Host ""

# --------------------------------------------------
# Step 11. Create Monitoring Dashboard Queries
# --------------------------------------------------
Write-Host ">> Step 11: Generating useful KQL queries for dashboards..." -ForegroundColor Yellow

$kqlQueries = @{
    "CPU Trend (Last 24h)" = @"
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.SQL"
| where Category == "ResourceUsageStats"
| where ResourceId contains "$ManagedInstanceName"
| extend cpu_pct = todouble(avg_cpu_percent_s)
| summarize AvgCPU = avg(cpu_pct), MaxCPU = max(cpu_pct) by bin(TimeGenerated, 15m)
| order by TimeGenerated desc
"@

    "Top Wait Types" = @"
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.SQL"
| where Category == "DatabaseWaitStatistics"
| where ResourceId contains "$ManagedInstanceName"
| summarize TotalWaitMs = sum(todouble(delta_wait_time_ms_d)) by wait_type_s
| top 20 by TotalWaitMs desc
"@

    "Deadlock Events" = @"
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.SQL"
| where Category == "Deadlocks"
| where ResourceId contains "$ManagedInstanceName"
| project TimeGenerated, deadlock_xml_s
| order by TimeGenerated desc
"@

    "Query Store - Top CPU Consumers" = @"
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.SQL"
| where Category == "QueryStoreRuntimeStatistics"
| where ResourceId contains "$ManagedInstanceName"
| extend cpu_time_ms = todouble(cpu_time_d) / 1000
| summarize TotalCPU = sum(cpu_time_ms), AvgCPU = avg(cpu_time_ms), ExecCount = sum(toint(count_executions_d)) by query_hash_s
| top 25 by TotalCPU desc
"@

    "Storage Usage Trend" = @"
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.SQL"
| where Category == "ResourceUsageStats"
| where ResourceId contains "$ManagedInstanceName"
| extend storage_pct = todouble(storage_space_used_mb_s) / todouble(reserved_storage_mb_s) * 100
| summarize AvgStoragePct = avg(storage_pct) by bin(TimeGenerated, 1h)
| order by TimeGenerated desc
"@
}

foreach ($queryName in $kqlQueries.Keys) {
    Write-Host ""
    Write-Host "   --- $queryName ---" -ForegroundColor Gray
    Write-Host $kqlQueries[$queryName] -ForegroundColor DarkGray
}
Write-Host ""

# --------------------------------------------------
# Summary
# --------------------------------------------------
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " Monitoring Setup Complete"                                       -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host " Resources Created / Configured:"                                -ForegroundColor White
Write-Host "   Log Analytics Workspace : $WorkspaceName"                     -ForegroundColor White
Write-Host "   Diagnostic Settings     : MI + $($DatabaseNames.Count) databases" -ForegroundColor White
Write-Host "   Action Group            : $ActionGroupName ($AlertEmailAddress)"  -ForegroundColor White
Write-Host ""
Write-Host " Alert Rules:"                                                   -ForegroundColor White
Write-Host "   1. High CPU             : > $CpuThresholdPercent% avg over 15 min (Sev 2)" -ForegroundColor White
Write-Host "   2. High Storage         : > $StorageThresholdPercent% capacity (Sev 2)"    -ForegroundColor White
Write-Host "   3. Deadlocks            : Any occurrence (Sev 1)"             -ForegroundColor White
Write-Host "   4. Long-Running Queries : > ${LongQueryThresholdSeconds}s (Sev 3)"         -ForegroundColor White
Write-Host ""
Write-Host " Next Steps:"                                                    -ForegroundColor Yellow
Write-Host "   1. Verify alert emails are received (test with a manual trigger)" -ForegroundColor Yellow
Write-Host "   2. Import KQL queries into Azure Monitor Workbooks"           -ForegroundColor Yellow
Write-Host "   3. Create a shared dashboard in the Azure Portal"             -ForegroundColor Yellow
Write-Host "   4. Tune alert thresholds based on baseline (25-PerformanceBaseline.sql)" -ForegroundColor Yellow
Write-Host "   5. Migrate SSRS reports to Power BI (see 27-SSRSMigration.md)" -ForegroundColor Yellow
Write-Host ""
