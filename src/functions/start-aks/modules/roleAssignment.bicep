// ============================================================================
// 角色指派模組 — 授予 Function App Managed Identity 啟動 AKS 的權限
// 在目標 AKS 所屬 Resource Group 上授予 Azure Kubernetes Service Contributor 角色
// ============================================================================

// ============================================================================
// 參數定義
// ============================================================================

@description('Function App Managed Identity 的 Principal ID')
param principalId string

@description('角色指派的唯一識別後綴（用於產生確定性 GUID）')
param roleAssignmentSuffix string

// ============================================================================
// 角色指派
// ============================================================================

// Azure Kubernetes Service Contributor: ed7f3fbd-7b88-4dd4-9017-9adb7ce333f8
var aksContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ed7f3fbd-7b88-4dd4-9017-9adb7ce333f8')

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId, aksContributorRoleId, roleAssignmentSuffix)
  properties: {
    roleDefinitionId: aksContributorRoleId
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
