// ============================================================================
// ACR 模組 — 存放自建 runner image
//
// 啟用 azureADAuthenticationAsArmPolicy，讓 ACA 可用 Managed Identity 拉取
// image，不需 admin 帳密。
// ============================================================================

@description('部署位置')
param location string

@description('ACR 名稱，僅允許小寫英數字')
@minLength(5)
@maxLength(50)
param acrName string

@description('標籤')
param tags object = {}

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
    policies: {
      azureADAuthenticationAsArmPolicy: {
        status: 'enabled'
      }
    }
  }
}

@description('ACR login server')
output acrLoginServer string = acr.properties.loginServer

@description('ACR 資源 ID')
output acrId string = acr.id

@description('ACR 名稱')
output acrName string = acr.name
