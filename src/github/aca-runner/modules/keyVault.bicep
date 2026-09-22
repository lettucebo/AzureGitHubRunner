// ============================================================================
// Key Vault 模組 — 存放 GitHub PAT
//
// RBAC 授權模式。PAT 不透過 Bicep 參數傳入，必須在部署後以
// az keyvault secret set 寫入，避免機密進入部署歷程。
//
// 刻意不啟用 purge protection：PoC 階段若需重建，purge protection 會讓
// 同名 vault 在 soft-delete 期滿前無法清除。名稱已含 uniqueString。
// ============================================================================

@description('部署位置')
param location string

@description('Key Vault 名稱')
@minLength(3)
@maxLength(24)
param keyVaultName string

@description('標籤')
param tags object = {}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
  }
}

@description('Key Vault 名稱')
output keyVaultName string = keyVault.name

@description('Key Vault 資源 ID')
output keyVaultId string = keyVault.id

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri
