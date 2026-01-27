// ============================================================================
// Log Analytics Workspace Module
// ============================================================================

param workspaceName string
param location string
param retentionInDays int
param tags object

resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

output workspaceName string = logWorkspace.name
output workspaceId string = logWorkspace.id
output customerId string = logWorkspace.properties.customerId
