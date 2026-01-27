// ============================================================================
// AKS Module - Azure Kubernetes Service
// ============================================================================

param clusterName string
param location string
param kubernetesVersion string

param systemNodeVmSize string
param systemNodeCount int

param agentNodeVmSize string
param agentNodeMinCount int
param agentNodeMaxCount int

param enableMonitoring bool
param logWorkspaceId string

param tags object

// ============================================================================
// AKS Cluster
// ============================================================================

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: clusterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: '${clusterName}-dns'
    
    // System Node Pool (固定，不使用 Spot)
    agentPoolProfiles: [
      {
        name: 'system'
        count: systemNodeCount
        vmSize: systemNodeVmSize
        osType: 'Linux'
        osSKU: 'Ubuntu'
        mode: 'System'
        type: 'VirtualMachineScaleSets'
        enableAutoScaling: false
        availabilityZones: []
        nodeTaints: [
          'CriticalAddonsOnly=true:NoSchedule'
        ]
        nodeLabels: {
          'workload': 'system'
        }
      }
    ]
    
    // Network Configuration
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
    }
    
    // RBAC
    enableRBAC: true
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }
    
    // Add-ons
    addonProfiles: enableMonitoring ? {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logWorkspaceId
        }
      }
    } : {}
    
    // Auto-upgrade
    autoUpgradeProfile: {
      upgradeChannel: 'patch'
    }
  }
}

// ============================================================================
// Agent Node Pool (Spot VM, 可自動擴展)
// ============================================================================

resource agentNodePool 'Microsoft.ContainerService/managedClusters/agentPools@2024-02-01' = {
  parent: aksCluster
  name: 'agents'
  properties: {
    count: agentNodeMinCount
    vmSize: agentNodeVmSize
    osType: 'Linux'
    osSKU: 'Ubuntu'
    mode: 'User'
    type: 'VirtualMachineScaleSets'
    
    // Auto-scaling
    enableAutoScaling: true
    minCount: agentNodeMinCount
    maxCount: agentNodeMaxCount
    
    // Spot Instance 設定
    scaleSetPriority: 'Spot'
    scaleSetEvictionPolicy: 'Delete'
    spotMaxPrice: -1 // 使用市場價格
    
    // Node labels and taints
    nodeLabels: {
      'workload': 'agent'
      'pool': 'spot'
    }
    nodeTaints: [
      'kubernetes.azure.com/scalesetpriority=spot:NoSchedule'
    ]
  }
}

// ============================================================================
// Outputs
// ============================================================================

output clusterName string = aksCluster.name
output clusterId string = aksCluster.id
output clusterFqdn string = aksCluster.properties.fqdn
output kubeletIdentity string = aksCluster.properties.identityProfile.kubeletidentity.objectId
output systemNodePoolName string = aksCluster.properties.agentPoolProfiles[0].name
output agentNodePoolName string = agentNodePool.name
