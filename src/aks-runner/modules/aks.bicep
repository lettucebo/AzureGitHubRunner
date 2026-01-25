// ============================================================================
// Azure Kubernetes Service (AKS) Module
// 雙 Pool 設計：System Pool + Spot Runner Pool
// ============================================================================

@description('AKS 叢集名稱')
param clusterName string

@description('部署位置')
param location string = resourceGroup().location

@description('Kubernetes 版本')
param kubernetesVersion string = '1.29'

@description('DNS 前綴')
param dnsPrefix string = clusterName

// System Pool 配置
@description('System Pool VM 大小')
param systemNodeVmSize string = 'Standard_B2s'

@description('System Pool 節點數量')
@minValue(1)
@maxValue(3)
param systemNodeCount int = 1

// Runner Pool 配置 (Spot VM)
@description('Runner Pool VM 大小')
param runnerNodeVmSize string = 'Standard_D4s_v3'

@description('Runner Pool 最小節點數')
@minValue(0)
param runnerNodeMinCount int = 0

@description('Runner Pool 最大節點數，每個節點可運行多個 Runner Pod')
@minValue(1)
@maxValue(10)
param runnerNodeMaxCount int = 5

@description('Spot VM 最高競標價格 (-1 表示隨選價格)')
param spotMaxPrice int = -1

// 整合配置
@description('Log Analytics Workspace ID (用於 Container Insights)')
param logAnalyticsWorkspaceId string = ''

@description('ACR Resource ID (用於 Image Pull)')
param acrId string = ''

@description('標籤')
param tags object = {}

// ============================================================================
// Resources
// ============================================================================

resource aks 'Microsoft.ContainerService/managedClusters@2024-01-01' = {
  name: clusterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: dnsPrefix
    kubernetesVersion: kubernetesVersion
    enableRBAC: true
    
    // Network 配置
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
    }

    // System Node Pool - 固定小型 VM
    agentPoolProfiles: [
      {
        name: 'system'
        count: systemNodeCount
        vmSize: systemNodeVmSize
        osType: 'Linux'
        osSKU: 'Ubuntu'
        mode: 'System'
        enableAutoScaling: false
        type: 'VirtualMachineScaleSets'
        availabilityZones: []
        nodeTaints: [
          'CriticalAddonsOnly=true:NoSchedule'
        ]
        nodeLabels: {
          'nodepool-type': 'system'
          'workload': 'system'
        }
        tags: tags
      }
    ]

    // Container Insights (如果提供 Log Analytics)
    addonProfiles: !empty(logAnalyticsWorkspaceId) ? {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      }
    } : {}

    // Auto-upgrade 設定
    autoUpgradeProfile: {
      upgradeChannel: 'stable'
    }
  }
}

// Runner Node Pool - Spot VM with Autoscaling
resource runnerNodePool 'Microsoft.ContainerService/managedClusters/agentPools@2024-01-01' = {
  parent: aks
  name: 'runner'
  properties: {
    count: runnerNodeMinCount
    vmSize: runnerNodeVmSize
    osType: 'Linux'
    osSKU: 'Ubuntu'
    mode: 'User'
    
    // Spot VM 配置
    scaleSetPriority: 'Spot'
    scaleSetEvictionPolicy: 'Delete'
    spotMaxPrice: spotMaxPrice
    
    // 自動擴展配置
    enableAutoScaling: true
    minCount: runnerNodeMinCount
    maxCount: runnerNodeMaxCount
    
    type: 'VirtualMachineScaleSets'
    availabilityZones: []
    
    // Node Labels & Taints for Runner workload
    nodeLabels: {
      'nodepool-type': 'runner'
      'workload': 'github-runner'
      'kubernetes.azure.com/scalesetpriority': 'spot'
    }
    nodeTaints: [
      'kubernetes.azure.com/scalesetpriority=spot:NoSchedule'
    ]
    
    tags: tags
  }
}

// ACR Pull 權限 (如果提供 ACR)
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(acrId)) {
  name: guid(aks.id, acrId, 'acrpull')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // AcrPull
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('AKS Cluster ID')
output clusterId string = aks.id

@description('AKS Cluster 名稱')
output clusterName string = aks.name

@description('AKS Cluster FQDN')
output clusterFqdn string = aks.properties.fqdn

@description('Kubelet Identity Object ID')
output kubeletIdentityObjectId string = aks.properties.identityProfile.kubeletidentity.objectId

@description('AKS Node Resource Group')
output nodeResourceGroup string = aks.properties.nodeResourceGroup

@description('用於連接 AKS 的 Azure CLI 命令')
output connectCommand string = 'az aks get-credentials --resource-group ${resourceGroup().name} --name ${clusterName}'
