// ============================================================================
// Azure Container Registry Module
// 用於存放自製 Runner Image
// ============================================================================

@description('ACR 名稱 (必須全域唯一)')
param acrName string

@description('部署位置')
param location string = resourceGroup().location

@description('ACR SKU')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param sku string = 'Basic'

@description('是否啟用 admin 帳號')
param adminUserEnabled bool = false

@description('標籤')
param tags object = {}

// ============================================================================
// Resources
// ============================================================================

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    adminUserEnabled: adminUserEnabled
    publicNetworkAccess: 'Enabled'
    policies: {
      retentionPolicy: {
        days: 7
        status: 'disabled'
      }
      trustPolicy: {
        type: 'Notary'
        status: 'disabled'
      }
    }
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('ACR Resource ID')
output acrId string = acr.id

@description('ACR 名稱')
output acrName string = acr.name

@description('ACR Login Server')
output loginServer string = acr.properties.loginServer
