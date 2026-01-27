// ============================================================================
// AKS + KEDA + Spot VM 架構
// Azure DevOps Self-hosted Agent for Azure Pipelines
// ============================================================================
// 
// 架構說明：
// - System Pool: 最小型 VM (B2s), 1 台固定, 負責 K8s 系統組件與 KEDA controller
// - Agent Pool: Spot VM (D4s_v3), 0-10 台自動擴展, 承載 Azure DevOps agent 工作負載
// 
// 成本估算：
// - System Pool: ~$30 USD/月 (1x B2s)
// - Agent Pool: ~$29 USD/月/台 (Spot VM)
// - 總計閒置時: ~$70 USD/月, 滿載時: ~$350 USD/月
// ============================================================================

targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@description('部署環境')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string = 'prod'

@description('專案名稱前綴')
param projectName string = 'adoagent'

@description('部署位置')
param location string = 'eastasia'

@description('Kubernetes 版本。注意: 部分區域不支援較新版本 (如 East Asia 不支援 1.35+)，部署前請執行 az aks get-versions --location <location> 確認支援的版本')
param kubernetesVersion string = '1.33'

// System Pool 配置
@description('System Pool VM 大小')
param systemNodeVmSize string = 'Standard_B2s'

@description('System Pool 節點數量 (1 台省錢, 2 台高可用)')
@minValue(1)
@maxValue(3)
param systemNodeCount int = 1

// Agent Pool 配置
@description('Agent Pool VM 大小')
param agentNodeVmSize string = 'Standard_D4s_v3'

@description('Agent Pool 最小節點數')
@minValue(0)
param agentNodeMinCount int = 0

@description('Agent Pool 最大節點數，每個節點可運行多個 Agent Pod')
@minValue(1)
@maxValue(10)
param agentNodeMaxCount int = 5

// 可選功能
@description('是否啟用 Container Insights 監控')
param enableMonitoring bool = true

@description('是否建立 ACR')
param enableAcr bool = false

@description('Log 保留天數')
param logRetentionDays int = 30

@description('標籤')
param tags object = {
  project: 'azure-devops-agent'
  environment: environment
  managedBy: 'bicep'
}

// ============================================================================
// Variables
// ============================================================================

var resourceGroupName = 'rg-${projectName}-${environment}'
var aksClusterName = 'aks-${projectName}-${environment}'
var acrName = replace('acr${projectName}${environment}${uniqueString(subscription().id)}', '-', '')
var logWorkspaceName = 'log-${projectName}-${environment}'

// ============================================================================
// Resource Group
// ============================================================================

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ============================================================================
// Modules
// ============================================================================

// Log Analytics Workspace
module logWorkspace 'modules/log.bicep' = if (enableMonitoring) {
  scope: rg
  name: 'log-workspace-deployment'
  params: {
    workspaceName: logWorkspaceName
    location: location
    retentionInDays: logRetentionDays
    tags: tags
  }
}

// Container Registry (Optional)
module acr 'modules/acr.bicep' = if (enableAcr) {
  scope: rg
  name: 'acr-deployment'
  params: {
    acrName: acrName
    location: location
    tags: tags
  }
}

// AKS Cluster
module aks 'modules/aks.bicep' = {
  scope: rg
  name: 'aks-deployment'
  params: {
    clusterName: aksClusterName
    location: location
    kubernetesVersion: kubernetesVersion
    systemNodeVmSize: systemNodeVmSize
    systemNodeCount: systemNodeCount
    agentNodeVmSize: agentNodeVmSize
    agentNodeMinCount: agentNodeMinCount
    agentNodeMaxCount: agentNodeMaxCount
    enableMonitoring: enableMonitoring
    logWorkspaceId: enableMonitoring ? logWorkspace.outputs.workspaceId : ''
    tags: tags
  }
}

// ============================================================================
// Outputs
// ============================================================================

output resourceGroupName string = rg.name
output aksClusterName string = aks.outputs.clusterName
output aksClusterId string = aks.outputs.clusterId
output acrName string = enableAcr ? acr.outputs.acrName : ''
output acrLoginServer string = enableAcr ? acr.outputs.loginServer : ''
output logWorkspaceName string = enableMonitoring ? logWorkspace.outputs.workspaceName : ''
output logWorkspaceId string = enableMonitoring ? logWorkspace.outputs.workspaceId : ''
