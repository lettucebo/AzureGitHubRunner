// ============================================================================
// Log Analytics 模組 — Container Apps 日誌
//
// 設定 daily cap 避免 ingestion 費用失控。ACA job 日誌量遠低於
// AKS Container Insights（實測 15.6 GB/月）。
// ============================================================================

@description('部署位置')
param location string

@description('Log Analytics workspace 名稱')
param workspaceName string

@description('日誌保留天數')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('每日擷取量上限 (GB)')
@minValue(1)
param dailyQuotaGb int = 1

@description('標籤')
param tags object = {}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    workspaceCapping: {
      dailyQuotaGb: dailyQuotaGb
    }
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

@description('Workspace 資源 ID')
output workspaceId string = workspace.id

@description('Workspace 名稱')
output workspaceName string = workspace.name
