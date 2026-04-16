// =============================================================================
// Module: Azure SQL Managed Instance
// =============================================================================
// Deploys a General Purpose tier SQL MI with:
//   - 8 vCores, 256 GB storage
//   - VNet integration via delegated subnet
//   - Microsoft Entra ID (Azure AD) administrator
//   - Transparent Data Encryption with service-managed keys
//   - Public endpoint disabled by default
// =============================================================================

@description('Azure region for the SQL MI')
param location string

@description('Base name prefix for resources')
param namePrefix string

@description('Resource ID of the MI-delegated subnet')
param miSubnetId string

@description('Administrator login name for SQL authentication')
@secure()
param administratorLogin string

@description('Administrator login password for SQL authentication')
@secure()
param administratorLoginPassword string

@description('Microsoft Entra ID (Azure AD) admin display name')
param aadAdminDisplayName string

@description('Object ID of the Microsoft Entra ID admin (user or group)')
param aadAdminObjectId string

@description('Tenant ID for Microsoft Entra ID authentication')
param aadTenantId string = subscription().tenantId

@description('SQL MI SKU name (GP_Gen5 for General Purpose Gen5)')
@allowed([
  'GP_Gen5'
  'GP_Gen8IM'
  'GP_Gen8IH'
  'BC_Gen5'
  'BC_Gen8IM'
  'BC_Gen8IH'
])
param skuName string = 'GP_Gen5'

@description('Number of vCores')
@allowed([4, 8, 16, 24, 32, 40, 64, 80])
param vCores int = 8

@description('Maximum storage size in GB')
param storageSizeInGB int = 256

@description('Backup retention period in days')
@minValue(1)
@maxValue(35)
param backupRetentionDays int = 7

@description('License type (BasePrice = Azure Hybrid Benefit, LicenseIncluded = pay-as-you-go)')
@allowed([
  'BasePrice'
  'LicenseIncluded'
])
param licenseType string = 'LicenseIncluded'

@description('Whether to allow public endpoint access')
param publicDataEndpointEnabled bool = false

@description('Collation for the managed instance')
param collation string = 'SQL_Latin1_General_CP1_CI_AS'

@description('Timezone ID for the managed instance')
param timezoneId string = 'UTC'

@description('Tags to apply to all resources')
param tags object = {}

// ---------------------------------------------------------------------------
// Azure SQL Managed Instance
// ---------------------------------------------------------------------------

resource sqlmi 'Microsoft.Sql/managedInstances@2023-08-01-preview' = {
  name: '${namePrefix}-sqlmi'
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuName == 'GP_Gen5' || startsWith(skuName, 'GP_') ? 'GeneralPurpose' : 'BusinessCritical'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    subnetId: miSubnetId
    vCores: vCores
    storageSizeInGB: storageSizeInGB
    licenseType: licenseType
    collation: collation
    timezoneId: timezoneId
    publicDataEndpointEnabled: publicDataEndpointEnabled
    minimalTlsVersion: '1.2'
    requestedBackupStorageRedundancy: 'Local'
    zoneRedundant: false
  }
}

// ---------------------------------------------------------------------------
// Microsoft Entra ID (Azure AD) Administrator
// ---------------------------------------------------------------------------

resource aadAdmin 'Microsoft.Sql/managedInstances/administrators@2023-08-01-preview' = {
  parent: sqlmi
  name: 'ActiveDirectory'
  properties: {
    administratorType: 'ActiveDirectory'
    login: aadAdminDisplayName
    sid: aadAdminObjectId
    tenantId: aadTenantId
  }
}

// ---------------------------------------------------------------------------
// Transparent Data Encryption (service-managed keys — enabled by default)
// ---------------------------------------------------------------------------
// TDE is enabled by default on SQL MI with service-managed keys.
// This resource is declared explicitly for visibility and IaC completeness.

resource tdeProtector 'Microsoft.Sql/managedInstances/encryptionProtector@2023-08-01-preview' = {
  parent: sqlmi
  name: 'current'
  properties: {
    serverKeyType: 'ServiceManaged'
    serverKeyName: 'ServiceManaged'
  }
}

// ---------------------------------------------------------------------------
// Backup Short-Term Retention Policy
// ---------------------------------------------------------------------------

resource backupPolicy 'Microsoft.Sql/managedInstances/backupShortTermRetentionPolicies@2023-08-01-preview' = {
  parent: sqlmi
  name: 'default'
  properties: {
    retentionDays: backupRetentionDays
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the SQL Managed Instance')
output sqlmiId string = sqlmi.id

@description('Name of the SQL Managed Instance')
output sqlmiName string = sqlmi.name

@description('FQDN of the SQL Managed Instance')
output sqlmiFqdn string = sqlmi.properties.fullyQualifiedDomainName

@description('System-assigned managed identity principal ID')
output sqlmiPrincipalId string = sqlmi.identity.principalId
