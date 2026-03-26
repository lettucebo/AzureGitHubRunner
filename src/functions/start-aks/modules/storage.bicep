// ============================================================================
// Storage Account 模組 — Function App 用 Storage
//
// 獨立模組，讓 network 模組可引用 Storage Account ID 建立 Private Endpoint，
// 並讓 functionApp 模組透過 existing 引用。
//
// publicNetworkAccess 設為 Disabled，搭配 VNet + Private Endpoint 使用。
// ============================================================================

// ============================================================================
// 參數定義
// ============================================================================

@description('Storage Account 名稱')
param storageAccountName string

@description('部署位置')
param location string

@description('部署套件用的 blob container 名稱')
param deploymentStorageContainerName string

@description('標籤')
param tags object = {}

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
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
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
// 輸出
// ============================================================================

@description('Storage Account 資源 ID')
output storageAccountId string = storageAccount.id

@description('Storage Account 名稱')
output storageAccountName string = storageAccount.name
