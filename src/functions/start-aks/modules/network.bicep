// ============================================================================
// 網路模組 — VNet + Private Endpoint + Private DNS Zone
//
// 建立 VNet 與 Subnets，讓 Function App 透過 VNet Integration 存取
// Storage Account 的 Private Endpoint，不需開啟 publicNetworkAccess。
// ============================================================================

// ============================================================================
// 參數定義
// ============================================================================

@description('部署位置')
param location string

@description('VNet 名稱')
param vnetName string

@description('Storage Account 資源 ID（用於建立 Private Endpoint）')
param storageAccountId string

@description('Storage Account 名稱（用於 Private Endpoint 命名）')
param storageAccountName string

@description('VNet 位址空間')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Function App Subnet 位址範圍')
param subnetFuncPrefix string = '10.0.0.0/24'

@description('Private Endpoint Subnet 位址範圍')
param subnetPePrefix string = '10.0.1.0/24'

@description('標籤')
param tags object = {}

// ============================================================================
// VNet + Subnets
// ============================================================================

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
  }
  tags: tags

  // Function App VNet Integration 用 Subnet
  // Flex Consumption 需要 delegation 到 Microsoft.App/environments
  resource subnetFunc 'subnets' = {
    name: 'snet-func'
    properties: {
      addressPrefix: subnetFuncPrefix
      delegations: [
        {
          name: 'delegation-app-environment'
          properties: {
            serviceName: 'Microsoft.App/environments'
          }
        }
      ]
    }
  }

  // Private Endpoint 用 Subnet
  resource subnetPe 'subnets' = {
    name: 'snet-pe'
    dependsOn: [subnetFunc]
    properties: {
      addressPrefix: subnetPePrefix
    }
  }
}

// ============================================================================
// Private Endpoint — Blob / Queue / Table
// ============================================================================

var privateEndpointConfigs = [
  { suffix: 'blob', groupId: 'blob', dnsZoneName: 'privatelink.blob.${environment().suffixes.storage}' }
  { suffix: 'queue', groupId: 'queue', dnsZoneName: 'privatelink.queue.${environment().suffixes.storage}' }
  { suffix: 'table', groupId: 'table', dnsZoneName: 'privatelink.table.${environment().suffixes.storage}' }
]

resource privateEndpoints 'Microsoft.Network/privateEndpoints@2024-01-01' = [
  for config in privateEndpointConfigs: {
    name: 'pe-${storageAccountName}-${config.suffix}'
    location: location
    properties: {
      subnet: {
        id: vnet::subnetPe.id
      }
      privateLinkServiceConnections: [
        {
          name: 'psc-${storageAccountName}-${config.suffix}'
          properties: {
            privateLinkServiceId: storageAccountId
            groupIds: [
              config.groupId
            ]
          }
        }
      ]
    }
    tags: tags
  }
]

// ============================================================================
// Private DNS Zone + VNet Link + DNS Zone Group
// ============================================================================

resource privateDnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [
  for config in privateEndpointConfigs: {
    name: config.dnsZoneName
    location: 'global'
    tags: tags
  }
]

resource dnsZoneVnetLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [
  for (config, index) in privateEndpointConfigs: {
    name: 'link-${vnet.name}'
    parent: privateDnsZones[index]
    location: 'global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnet.id
      }
    }
  }
]

resource dnsZoneGroups 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = [
  for (config, index) in privateEndpointConfigs: {
    name: 'default'
    parent: privateEndpoints[index]
    properties: {
      privateDnsZoneConfigs: [
        {
          name: config.suffix
          properties: {
            privateDnsZoneId: privateDnsZones[index].id
          }
        }
      ]
    }
  }
]

// ============================================================================
// 輸出
// ============================================================================

@description('Function App VNet Integration 用的 Subnet ID')
output funcSubnetId string = vnet::subnetFunc.id
