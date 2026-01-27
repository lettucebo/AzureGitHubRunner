// ============================================================================
// Azure Container Registry Module
// ============================================================================

param acrName string
param location string
param tags object

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

output acrName string = acr.name
output acrId string = acr.id
output loginServer string = acr.properties.loginServer
