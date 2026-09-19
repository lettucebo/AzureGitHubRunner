// ============================================================================
// Container Apps Environment 模組
//
// 採 Workload Profiles environment，只保留 Consumption profile。
// 使用平台代管網路，因此刻意不建立 VNet / NSG / NAT Gateway / Load Balancer。
// 也不使用 Flex / Dedicated profile；後續資源需求分流由上層 job module 處理。
// ============================================================================

@description('部署位置')
param location string

@description('Container Apps Environment 名稱')
param environmentName string

@description('Log Analytics workspace 名稱')
param logAnalyticsWorkspaceName string

@description('標籤')
param tags object = {}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource environment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
        minimumCount: 0
        maximumCount: 10
      }
    ]
    zoneRedundant: false
  }
}

@description('Container Apps Environment 資源 ID')
output environmentId string = environment.id

@description('Container Apps Environment 名稱')
output environmentName string = environment.name

@description('Runner Job 使用的 workload profile 名稱')
output workloadProfileName string = 'Consumption'
