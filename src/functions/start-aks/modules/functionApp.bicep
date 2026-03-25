// ============================================================================
// Function App 模組 — 定時啟動 AKS 叢集
// 包含 Storage Account、App Service Plan (Flex Consumption) 與 Function App
// Flex Consumption 使用 Linux + Managed Identity，不依賴 Azure Files，
// 因此與公司禁用 Storage shared key access 的 Policy 相容。
// ============================================================================

// ============================================================================
// 參數定義
// ============================================================================

@description('Function App 名稱')
param functionAppName string

@description('部署位置')
param location string

@description('Storage Account 名稱')
param storageAccountName string

@description('AKS 叢集 JSON 設定（會寫入 App Setting）')
param aksClustersJson string

@description('標籤')
param tags object = {}

// ============================================================================
// 變數
// ============================================================================

var deploymentStorageContainerName = 'app-package-${take(functionAppName, 32)}'

// ============================================================================
// Storage Account
// ============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
  tags: tags

  resource blobServices 'blobServices' = {
    name: 'default'
    resource deploymentContainer 'containers' = {
      name: deploymentStorageContainerName
      properties: {
        publicAccess: 'None'
      }
    }
  }
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
// Function App (Linux, Flex Consumption, Node.js 20)
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
      WEBSITE_TIME_ZONE: 'Asia/Taipei'
      AKS_CLUSTERS: aksClustersJson
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
