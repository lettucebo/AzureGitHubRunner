using 'main.bicep'

param projectName = 'ghrunner'
param environment = 'prod'
param location = 'eastasia'

param aksTargets = [
  {
    subscriptionId: 'ffc7fbc7-3840-4835-ad88-4eb5015d7dac'
    resourceGroup: 'rg-ghrunner-prod'
    name: 'aks-ghrunner-prod'
  }
]

param tags = {
  project: 'start-aks'
  environment: 'prod'
  managedBy: 'bicep'
}
