// =============================================================================
// Module: Azure Database Migration Service
// =============================================================================
// Deploys Azure DMS (Standard SKU) with VNet integration for migrating
// on-premises SQL Server databases to Azure SQL Managed Instance.
// The DMS is placed in the management subnet to access both the source
// SQL Server (via VPN/ExpressRoute) and the target SQL MI.
// =============================================================================

@description('Azure region for the DMS resource')
param location string

@description('Base name prefix for resources')
param namePrefix string

@description('Resource ID of the management subnet for VNet integration')
param managementSubnetId string

@description('SKU for the Database Migration Service')
@allowed([
  'Standard_1vCores'
  'Standard_2vCores'
  'Standard_4vCores'
  'Premium_4vCores'
])
param skuName string = 'Standard_2vCores'

@description('Tags to apply to all resources')
param tags object = {}

// ---------------------------------------------------------------------------
// Azure Database Migration Service
// ---------------------------------------------------------------------------

resource dms 'Microsoft.DataMigration/services@2021-06-30' = {
  name: '${namePrefix}-dms'
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: contains(skuName, 'Premium') ? 'Premium' : 'Standard'
    size: skuName
  }
  properties: {
    virtualSubnetId: managementSubnetId
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the Database Migration Service')
output dmsId string = dms.id

@description('Name of the Database Migration Service')
output dmsName string = dms.name
