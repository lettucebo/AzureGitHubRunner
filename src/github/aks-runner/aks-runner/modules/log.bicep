// ============================================================================
// Log Analytics Workspace Module
// 用於 AKS Container Insights 監控
// ============================================================================

@description('Log Analytics workspace 名稱')
param workspaceName string

@description('部署位置')
param location string = resourceGroup().location

@description('資料保留天數')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('SKU 定價層級')
@allowed([
  'Free'
  'PerGB2018'
  'Standalone'
])
param sku string = 'PerGB2018'

@description('標籤')
param tags object = {}

// ============================================================================
// Resources
// ============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: sku
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: -1 // 無限制
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Container Insights Solution
resource containerInsightsSolution 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'ContainerInsights(${logAnalyticsWorkspace.name})'
  location: location
  tags: tags
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
  }
  plan: {
    name: 'ContainerInsights(${logAnalyticsWorkspace.name})'
    product: 'OMSGallery/ContainerInsights'
    publisher: 'Microsoft'
    promotionCode: ''
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Log Analytics Workspace ID')
output workspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics Workspace 名稱')
output workspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics Workspace Customer ID (用於 agent 配置)')
output customerId string = logAnalyticsWorkspace.properties.customerId
