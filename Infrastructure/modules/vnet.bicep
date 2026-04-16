// =============================================================================
// Module: Virtual Network for Azure SQL Managed Instance
// =============================================================================
// Deploys a VNet with three subnets:
//   - MI Subnet: Delegated to Microsoft.Sql/managedInstances (required for MI)
//   - Management Subnet: For jump boxes, DMS, and management tooling
//   - GatewaySubnet: For VPN/ExpressRoute gateway connectivity
// Also deploys NSG rules required by SQL Managed Instance.
// =============================================================================

@description('Azure region for all resources')
param location string

@description('Base name prefix for all resources')
param namePrefix string

@description('Address space for the virtual network')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Address prefix for the SQL MI subnet')
param miSubnetPrefix string = '10.0.0.0/24'

@description('Address prefix for the management subnet')
param managementSubnetPrefix string = '10.0.1.0/24'

@description('Address prefix for the gateway subnet')
param gatewaySubnetPrefix string = '10.0.2.0/27'

@description('Tags to apply to all resources')
param tags object = {}

// ---------------------------------------------------------------------------
// NSG for the SQL Managed Instance subnet
// ---------------------------------------------------------------------------
// SQL MI requires specific inbound/outbound rules for management traffic,
// health probes, and internal communication.

resource miNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${namePrefix}-mi-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      // Inbound: Allow Azure management traffic (required for MI control plane)
      {
        name: 'allow-management-inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'SqlManagement'
          sourcePortRange: '*'
          destinationAddressPrefix: miSubnetPrefix
          destinationPortRanges: [
            '9000'
            '9003'
            '1438'
            '1440'
            '1452'
          ]
        }
      }
      // Inbound: Azure Load Balancer health probes
      {
        name: 'allow-health-probe-inbound'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: miSubnetPrefix
          destinationPortRange: '*'
        }
      }
      // Inbound: Internal MI subnet communication
      {
        name: 'allow-mi-subnet-inbound'
        properties: {
          priority: 300
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: miSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: miSubnetPrefix
          destinationPortRange: '*'
        }
      }
      // Inbound: TDS endpoint from management subnet (for DMS and admin access)
      {
        name: 'allow-tds-from-management'
        properties: {
          priority: 400
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: managementSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: miSubnetPrefix
          destinationPortRanges: [
            '1433'
            '11000-11999'
          ]
        }
      }
      // Outbound: Azure AD authentication
      {
        name: 'allow-aad-outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: miSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureActiveDirectory'
          destinationPortRanges: [
            '80'
            '443'
          ]
        }
      }
      // Outbound: Azure management traffic
      {
        name: 'allow-management-outbound'
        properties: {
          priority: 200
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: miSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureCloud'
          destinationPortRanges: [
            '443'
            '12000'
          ]
        }
      }
      // Outbound: MI subnet internal communication
      {
        name: 'allow-mi-subnet-outbound'
        properties: {
          priority: 300
          direction: 'Outbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: miSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: miSubnetPrefix
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// NSG for the Management Subnet
// ---------------------------------------------------------------------------

resource mgmtNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: '${namePrefix}-mgmt-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'allow-rdp-inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: managementSubnetPrefix
          destinationPortRange: '3389'
        }
      }
      {
        name: 'allow-ssh-inbound'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: managementSubnetPrefix
          destinationPortRange: '22'
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Route Table for SQL MI Subnet (required for proper traffic routing)
// ---------------------------------------------------------------------------

resource miRouteTable 'Microsoft.Network/routeTables@2023-11-01' = {
  name: '${namePrefix}-mi-rt'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false
  }
}

// ---------------------------------------------------------------------------
// Virtual Network
// ---------------------------------------------------------------------------

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: '${namePrefix}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      // MI Subnet — delegated to Microsoft.Sql/managedInstances
      {
        name: 'mi-subnet'
        properties: {
          addressPrefix: miSubnetPrefix
          networkSecurityGroup: {
            id: miNsg.id
          }
          routeTable: {
            id: miRouteTable.id
          }
          delegations: [
            {
              name: 'mi-delegation'
              properties: {
                serviceName: 'Microsoft.Sql/managedInstances'
              }
            }
          ]
        }
      }
      // Management Subnet — for DMS, jump boxes, tooling
      {
        name: 'management-subnet'
        properties: {
          addressPrefix: managementSubnetPrefix
          networkSecurityGroup: {
            id: mgmtNsg.id
          }
        }
      }
      // Gateway Subnet — for VPN/ExpressRoute (must be named 'GatewaySubnet')
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: gatewaySubnetPrefix
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the virtual network')
output vnetId string = vnet.id

@description('Name of the virtual network')
output vnetName string = vnet.name

@description('Resource ID of the MI subnet')
output miSubnetId string = vnet.properties.subnets[0].id

@description('Resource ID of the management subnet')
output managementSubnetId string = vnet.properties.subnets[1].id

@description('Resource ID of the gateway subnet')
output gatewaySubnetId string = vnet.properties.subnets[2].id
