// ============================================================================
// Managed Identity 模組
//
// 建立 User-assigned Managed Identity 並授予：
//   - AcrPull：讓 ACA 平台拉取 runner image
//   - Key Vault Secrets User：讓 ACA 平台解析 github-pat secret
//
// 另可選擇性把 Key Vault Secrets Officer 指派給部署者，
// 因為啟用 RBAC 的 Key Vault 不會自動賦予 Owner data-plane 寫入權限。
// ============================================================================

@description('部署位置')
param location string

@description('Managed Identity 名稱')
param identityName string

@description('ACR 資源 ID')
param acrId string

@description('Key Vault 資源 ID')
param keyVaultId string

@description('選填。要授予 Key Vault Secrets Officer 的部署者 principal ID，留空則不指派')
param secretsOfficerPrincipalId string = ''

@description('標籤')
param tags object = {}

var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'
var keyVaultSecretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: last(split(acrId, '/'))
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: last(split(keyVaultId, '/'))
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acrId, identity.id, acrPullRoleId)
  scope: acr
  properties: {
    principalId: identity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalType: 'ServicePrincipal'
  }
}

resource keyVaultSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVaultId, identity.id, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    principalId: identity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalType: 'ServicePrincipal'
  }
}

resource deployerSecretsOfficer 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(secretsOfficerPrincipalId)) {
  name: guid(keyVaultId, secretsOfficerPrincipalId, keyVaultSecretsOfficerRoleId)
  scope: keyVault
  properties: {
    principalId: secretsOfficerPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsOfficerRoleId)
  }
}

@description('Managed Identity 資源 ID')
output identityResourceId string = identity.id

@description('Managed Identity Principal ID')
output identityPrincipalId string = identity.properties.principalId
