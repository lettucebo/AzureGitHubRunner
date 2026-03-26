// ============================================================================
// Azure Function — 定時啟動 AKS 叢集
//
// 部署一個 Azure Function App (Linux Flex Consumption Plan)，使用 Timer Trigger
// 每天台北時間 06:00 自動啟動指定的 AKS 叢集。
//
// 透過 Managed Identity 認證，支援以 JSON 陣列參數同時啟動多台 AKS。
// 使用 VNet Integration + Private Endpoint 存取 Storage Account，
// 不需開啟 publicNetworkAccess，符合公司 Azure Policy。
//
// 部署指令:
//   az deployment sub create --location eastasia \
//     --template-file main.bicep --parameters main.bicepparam
// ============================================================================

targetScope = 'subscription'

// ============================================================================
// 參數定義
// ============================================================================

@description('專案名稱，用於資源命名')
param projectName string = 'startaks'

@description('部署環境')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'prod'

@description('部署區域')
param location string = 'eastasia'

@description('要啟動的 AKS 叢集清單')
param aksTargets array = [
  // {
  //   subscriptionId: 'your-subscription-id'
  //   resourceGroup: 'rg-ghrunner-prod'
  //   name: 'aks-ghrunner-prod'
  // }
]

@description('標籤')
param tags object = {
  project: 'start-aks'
  environment: environment
  managedBy: 'bicep'
}

// ============================================================================
// 變數
// ============================================================================

var resourceGroupName = 'rg-${projectName}-${environment}'
var functionAppName = 'func-${projectName}-${environment}'
var storageAccountName = replace('st${projectName}${environment}', '-', '')
var vnetName = 'vnet-${projectName}-${environment}'

// 將 aksTargets 陣列序列化為 JSON 字串，供 Function App 使用
var aksClustersJson = string(aksTargets)

// 收集不重複的目標 Resource Group 名稱（用於角色指派）
var targetResourceGroups = [for target in aksTargets: target.resourceGroup]

// 部署用 blob container 名稱
var deploymentStorageContainerName = 'app-package-${take(functionAppName, 32)}'

// ============================================================================
// Resource Group
// ============================================================================

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ============================================================================
// Storage Account — 供 Function App 使用
// 獨立於 Function App 模組，讓 network 模組可引用建立 Private Endpoint
// ============================================================================

module storage 'modules/storage.bicep' = {
  name: 'deploy-storage'
  scope: rg
  params: {
    storageAccountName: storageAccountName
    location: location
    deploymentStorageContainerName: deploymentStorageContainerName
    tags: tags
  }
}

// ============================================================================
// 網路模組 — VNet + Private Endpoint + Private DNS Zone
// ============================================================================

module network 'modules/network.bicep' = {
  name: 'deploy-network'
  scope: rg
  params: {
    location: location
    vnetName: vnetName
    storageAccountId: storage.outputs.storageAccountId
    storageAccountName: storageAccountName
    tags: tags
  }
}

// ============================================================================
// Function App 模組
// ============================================================================

module functionApp 'modules/functionApp.bicep' = {
  name: 'deploy-function-app'
  scope: rg
  params: {
    functionAppName: functionAppName
    location: location
    storageAccountName: storageAccountName
    aksClustersJson: aksClustersJson
    funcSubnetId: network.outputs.funcSubnetId
    tags: tags
  }
}

// ============================================================================
// 角色指派 — 對每個目標 AKS Resource Group 授予權限
// ============================================================================

module roleAssignments 'modules/roleAssignment.bicep' = [
  for (rgName, index) in targetResourceGroups: {
    name: 'deploy-role-${index}'
    scope: resourceGroup(rgName)
    params: {
      principalId: functionApp.outputs.principalId
      roleAssignmentSuffix: rgName
    }
  }
]

// ============================================================================
// 輸出
// ============================================================================

@description('Function App 名稱')
output functionAppName string = functionApp.outputs.functionAppName

@description('Managed Identity Principal ID（用於手動授權）')
output principalId string = functionApp.outputs.principalId

@description('Resource Group 名稱')
output resourceGroupName string = rg.name
