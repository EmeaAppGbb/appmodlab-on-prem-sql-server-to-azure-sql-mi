// =============================================================================
// Main Orchestrator: Lakeview Medical — Azure SQL Managed Instance Lab
// =============================================================================
// Deploys the complete infrastructure for migrating on-premises SQL Server
// to Azure SQL Managed Instance:
//
//   1. Virtual Network with MI, Management, and Gateway subnets
//   2. Azure SQL Managed Instance (General Purpose, 8 vCores, 256 GB)
//   3. Azure Database Migration Service for online migration
//
// Usage:
//   az deployment group create \
//     --resource-group rg-lakeview-mi-lab \
//     --template-file main.bicep \
//     --parameters @parameters.json \
//     --parameters sqlAdministratorLoginPassword='<secure-password>'
// =============================================================================

targetScope = 'resourceGroup'

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

@description('Azure region for all resources. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Base name prefix applied to all resources for consistent naming')
param namePrefix string = 'lakeview-mi-lab'

@description('SQL administrator login name')
@secure()
param sqlAdministratorLogin string

@description('SQL administrator login password (min 12 characters, must include uppercase, lowercase, number, and special character)')
@secure()
param sqlAdministratorLoginPassword string

@description('Display name of the Microsoft Entra ID (Azure AD) admin user or group')
param aadAdminDisplayName string

@description('Object ID of the Microsoft Entra ID admin user or group')
param aadAdminObjectId string

@description('Tags applied to all resources')
param tags object = {
  project: 'lakeview-medical'
  environment: 'lab'
  purpose: 'sql-mi-migration'
}

// ---------------------------------------------------------------------------
// Module 1: Virtual Network
// ---------------------------------------------------------------------------
// Provisions VNet, subnets (MI-delegated, management, gateway), NSGs,
// and route table required for SQL Managed Instance networking.

module vnet 'modules/vnet.bicep' = {
  name: 'deploy-vnet'
  params: {
    location: location
    namePrefix: namePrefix
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Module 2: Azure SQL Managed Instance
// ---------------------------------------------------------------------------
// Deploys the SQL MI into the delegated subnet. General Purpose tier
// with 8 vCores and 256 GB storage — suitable for the Lakeview Medical
// lab workload. Entra ID admin and TDE are configured.

module sqlmi 'modules/sqlmi.bicep' = {
  name: 'deploy-sqlmi'
  params: {
    location: location
    namePrefix: namePrefix
    miSubnetId: vnet.outputs.miSubnetId
    administratorLogin: sqlAdministratorLogin
    administratorLoginPassword: sqlAdministratorLoginPassword
    aadAdminDisplayName: aadAdminDisplayName
    aadAdminObjectId: aadAdminObjectId
    skuName: 'GP_Gen5'
    vCores: 8
    storageSizeInGB: 256
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Module 3: Azure Database Migration Service
// ---------------------------------------------------------------------------
// DMS is deployed into the management subnet so it can reach both the
// source SQL Server (via VPN/ExpressRoute) and the target SQL MI.

module dms 'modules/dms.bicep' = {
  name: 'deploy-dms'
  params: {
    location: location
    namePrefix: namePrefix
    managementSubnetId: vnet.outputs.managementSubnetId
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Name of the deployed virtual network')
output vnetName string = vnet.outputs.vnetName

@description('Name of the SQL Managed Instance')
output sqlmiName string = sqlmi.outputs.sqlmiName

@description('FQDN of the SQL Managed Instance (use for connection strings)')
output sqlmiFqdn string = sqlmi.outputs.sqlmiFqdn

@description('Name of the Database Migration Service')
output dmsName string = dms.outputs.dmsName

@description('Resource ID of the SQL Managed Instance')
output sqlmiResourceId string = sqlmi.outputs.sqlmiId
