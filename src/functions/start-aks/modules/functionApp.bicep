// ============================================================================
// Function App 模組 — 定時啟動 AKS 叢集
// 包含 App Service Plan (Flex Consumption) 與 Function App
// Flex Consumption 使用 Linux + Managed Identity，不依賴 Azure Files，
// 因此與公司禁用 Storage shared key access 的 Policy 相容。
//
// Storage Account 由 main.bicep 建立，本模組透過 existing 引用。
// ============================================================================

// ============================================================================
// 參數定義
// ============================================================================

@description('Function App 名稱')
param functionAppName string

@description('部署位置')
param location string

@description('Storage Account 名稱（由 main.bicep 建立）')
param storageAccountName string

@description('AKS 叢集 JSON 設定（會寫入 App Setting）')
param aksClustersJson string

@description('Function App VNet Integration 用的 Subnet ID')
param funcSubnetId string

@description('標籤')
param tags object = {}

@description('啟動排程 (NCRONTAB，UTC)')
param startScheduleUtc string = '0 25,40 16 * * *'

@description('停止排程 (NCRONTAB，UTC)')
param stopScheduleUtc string = '0 0 14 * * *'

@description('是否啟用定時停止排程；映射為 app setting AKS_STOP_ENABLED，由程式碼 (src/aksOperations.ts) 於執行前 fail-closed 檢查，false/缺失/其他值一律視為停用')
param enableStopSchedule bool = false

// ============================================================================
// 變數
// ============================================================================

var deploymentStorageContainerName = 'app-package-${take(functionAppName, 32)}'

// ============================================================================
// 引用由 main.bicep 建立的 Storage Account
// ============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

// ============================================================================
// App Service Plan (Flex Consumption FC1)
// ============================================================================

resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: '${functionAppName}-plan'
  location: location
  kind: 'functionapp'
  sku: {
    tier: 'FlexConsumption'
    name: 'FC1'
  }
  properties: {
    reserved: true
  }
  tags: tags
}

// ============================================================================
// Function App (Linux, Flex Consumption, Node.js 22)
// ============================================================================

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    virtualNetworkSubnetId: funcSubnetId
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storageAccount.properties.primaryEndpoints.blob}${deploymentStorageContainerName}'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 100
        instanceMemoryMB: 2048
      }
      runtime: {
        name: 'node'
        version: '22'
      }
    }
  }
  tags: tags

  resource configAppSettings 'config' = {
    name: 'appsettings'
    properties: {
      AzureWebJobsStorage__accountName: storageAccount.name
      AKS_CLUSTERS: aksClustersJson
      AKS_START_SCHEDULE_UTC: startScheduleUtc
      AKS_STOP_SCHEDULE_UTC: stopScheduleUtc
      // 唯一的停止開關來源：程式碼 (src/aksOperations.ts) 在解析
      // AKS_CLUSTERS、建立 credential/client、發出任何 Azure 呼叫之前，
      // 檢查此值是否去除前後空白後精確等於 (不分大小寫) 'true'。
      // 刻意不再依賴 Azure Functions 官方 AzureWebJobs.<name>.Disabled
      // 機制，避免兩套旗標並存造成 fail-open 風險。
      AKS_STOP_ENABLED: string(enableStopSchedule)
    }
  }
}

// ============================================================================
// Storage Account 角色指派 — 讓 Function App MI 可存取 Storage
// ============================================================================

// Storage Blob Data Owner: b7e6dc6d-f1e8-4753-8033-0f276bb0955b
resource storageBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Queue Data Contributor: 974c5e8b-45b9-4653-ba55-5f855dd0fb88
resource storageQueueRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Table Data Contributor: 0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3
resource storageTableRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// 輸出
// ============================================================================

@description('Function App 的 Managed Identity Principal ID')
output principalId string = functionApp.identity.principalId

@description('Function App 名稱')
output functionAppName string = functionApp.name
