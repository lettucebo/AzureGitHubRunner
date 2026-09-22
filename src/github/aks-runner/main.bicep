// ============================================================================
// AKS + ARC + Spot VM 架構
// GitHub Self-hosted Runner for Copilot Coding Agent
// ============================================================================
// 
// 架構說明：
// - System Pool: 最小型 VM (B2s), 1 台固定, 負責 K8s 系統組件與 ARC controller
// - Runner Pool: Spot VM (D4s_v3), 0-5 台自動擴展, 承載一般 CI/CD 與 Copilot Coding Agent
// - Android Pool: 一般 VM (D8as_v5), 0-8 台自動擴展, 承載原生 Android build (需大量磁碟)
// 
// 成本估算 (East Asia, USD, 單價由 Azure Retail Prices API 實測)：
// - 閒置時: ~$130-150/月 (System Pool 無法縮到 0；Container Insights 目前約 15.6 GB/月)
// - 實際費用取決於 Runner/Android Pool 的使用時數，兩者閒置時皆為 0 節點
// - 詳細成本表請見 README.md
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
param projectName string = 'ghrunner'

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

// Runner Pool 配置
@description('Runner Pool VM 大小')
param runnerNodeVmSize string = 'Standard_D4s_v3'

@description('Runner Pool 最小節點數')
@minValue(0)
param runnerNodeMinCount int = 0

@description('Runner Pool 最大節點數，每個節點可運行多個 Runner Pod')
@minValue(1)
@maxValue(10)
param runnerNodeMaxCount int = 5

// Android Pool 配置
@description('是否建立 Android Pool (原生 Android build 專用，供 arc-android runner scale set 使用)')
param enableAndroidPool bool = true

@description('Android Pool VM 大小')
param androidNodeVmSize string = 'Standard_D8as_v5'

@description('Android Pool 最小節點數')
@minValue(0)
param androidNodeMinCount int = 0

@description('Android Pool 最大節點數')
@minValue(1)
@maxValue(10)
param androidNodeMaxCount int = 8

@description('Android Pool OS 磁碟大小 (GB)')
@minValue(128)
param androidNodeOsDiskSizeGb int = 256

// 可選功能
@description('是否啟用 Container Insights 監控')
param enableMonitoring bool = true

@description('是否建立 ACR')
param enableAcr bool = false

@description('Log 保留天數')
param logRetentionDays int = 30

@description('標籤')
param tags object = {
  project: 'github-runner'
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

// Log Analytics Workspace (Optional)
module logAnalytics 'modules/log.bicep' = if (enableMonitoring) {
  name: 'deploy-log-analytics'
  scope: rg
  params: {
    workspaceName: logWorkspaceName
    location: location
    retentionInDays: logRetentionDays
    tags: tags
  }
}

// Azure Container Registry (Optional)
module acr 'modules/acr.bicep' = if (enableAcr) {
  name: 'deploy-acr'
  scope: rg
  params: {
    acrName: acrName
    location: location
    sku: 'Basic'
    tags: tags
  }
}

// AKS Cluster with System + Runner Pools
module aks 'modules/aks.bicep' = {
  name: 'deploy-aks'
  scope: rg
  params: {
    clusterName: aksClusterName
    location: location
    kubernetesVersion: kubernetesVersion
    
    // System Pool
    systemNodeVmSize: systemNodeVmSize
    systemNodeCount: systemNodeCount
    
    // Runner Pool (Spot)
    runnerNodeVmSize: runnerNodeVmSize
    runnerNodeMinCount: runnerNodeMinCount
    runnerNodeMaxCount: runnerNodeMaxCount
    
    // Android Pool (原生 Android build)
    enableAndroidPool: enableAndroidPool
    androidNodeVmSize: androidNodeVmSize
    androidNodeMinCount: androidNodeMinCount
    androidNodeMaxCount: androidNodeMaxCount
    androidNodeOsDiskSizeGb: androidNodeOsDiskSizeGb

    // Integrations
    logAnalyticsWorkspaceId: enableMonitoring && logAnalytics != null ? logAnalytics.outputs.workspaceId : ''
    acrId: enableAcr && acr != null ? acr.outputs.acrId : ''
    
    tags: tags
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Resource Group 名稱')
output resourceGroupName string = rg.name

@description('AKS Cluster 名稱')
output aksClusterName string = aks.outputs.clusterName

@description('AKS Cluster FQDN')
output aksClusterFqdn string = aks.outputs.clusterFqdn

@description('連接 AKS 的命令')
output aksConnectCommand string = aks.outputs.connectCommand

@description('ACR Login Server')
output acrLoginServer string = enableAcr && acr != null ? acr.outputs.loginServer : 'N/A'

@description('Log Analytics Workspace ID')
output logWorkspaceId string = enableMonitoring && logAnalytics != null ? logAnalytics.outputs.workspaceId : 'N/A'

// ============================================================================
// 部署後步驟提示
// ============================================================================
// 1. 連接 AKS: az aks get-credentials --resource-group <rg> --name <aks>
// 2. 安裝 cert-manager 和 ARC: ./scripts/install-arc.sh
// 3. 建立 RunnerScaleSet: kubectl apply -f kubernetes/runner-scale-set.yaml
// 4. 更新 GitHub workflow 使用新的 runner
// ============================================================================
