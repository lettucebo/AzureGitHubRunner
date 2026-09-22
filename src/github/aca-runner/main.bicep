// ============================================================================
// ACA Event-driven GitHub Self-hosted Runner
//
// 架構：
// - Container Apps Environment: Workload Profiles (Consumption)，平台代管網路
// - general Job: 一般 CI，label aca-general
// - copilot Job: Copilot cloud agent，label aca-copilot，較長 replicaTimeout
// - 兩個 Job 的網路、image、身分、secret 來源完全相同
// - runner 以 --ephemeral 單次執行，無跨 job 殘留
// - 無 Docker daemon：需要 Docker 的工作直接在 workflow 指定 GitHub-hosted runner
//
// 成本 (East Asia, USD)：
// - ACA compute: 843.7 分鐘/月 @ 2 vCPU/4 GiB 落在每月免費額度內 → $0
// - 固定成本: ACR Basic ~$5.2 + Log Analytics ~$0-2 → 約 $5-7/月
//
// 兩階段部署：
//   1) enableRunnerJobs=false 部署基礎設施
//   2) 寫入 Key Vault secret 與推送 image
//   3) enableRunnerJobs=true 並填入 runnerImage 後再次部署
//
// 部署指令:
//   az deployment sub create --location eastasia \
//     --template-file main.bicep --parameters main.bicepparam
// ============================================================================

targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@description('部署環境')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string = 'prod'

@description('專案名稱前綴')
@minLength(3)
@maxLength(12)
param projectName string = 'acarunner'

@description('部署位置')
param location string = 'eastasia'

@description('GitHub organization 名稱')
param githubOwner string

@description('scaler 監看的 repository 名稱清單（不含 owner）')
@minLength(1)
param repositories array

@description('GitHub runner group 名稱。GitHub Free 只有 Default 群組，故預設留空')
param runnerGroup string = ''

@description('選填。要授予 Key Vault Secrets Officer 的部署者 principal ID')
param secretsOfficerPrincipalId string = ''

@description('Log 保留天數')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 30

@description('Log Analytics 每日擷取上限 (GB)')
@minValue(1)
param logDailyQuotaGb int = 1

@description('是否建立 runner Jobs。首次部署請保持 false')
param enableRunnerJobs bool = false

@description('是否建立 Copilot runner Job')
param enableCopilotJob bool = false

@description('完整 runner image 參考，enableRunnerJobs=true 時必填，必須帶不可變 tag，禁止 latest')
param runnerImage string = ''

@description('general Job 的 replica 最長存活秒數')
@minValue(300)
@maxValue(86400)
param generalReplicaTimeoutSeconds int = 3600

@description('copilot Job 的 replica 最長存活秒數，須依實測完整 session p99 加 25% 餘裕設定')
@minValue(300)
@maxValue(86400)
param copilotReplicaTimeoutSeconds int = 7200

@description('general Job 最大併發 execution 數')
@minValue(1)
@maxValue(30)
param generalMaxExecutions int = 20

@description('copilot Job 最大併發 execution 數')
@minValue(1)
@maxValue(30)
param copilotMaxExecutions int = 20

@description('runner 容器 vCPU。vCPU <= 1 時 ephemeral storage 只有 4 GiB')
@allowed([
  '1.0'
  '2.0'
  '4.0'
])
param runnerCpu string = '2.0'

@description('runner 容器記憶體，必須為 vCPU 的兩倍 GiB')
@allowed([
  '2.0Gi'
  '4.0Gi'
  '8.0Gi'
])
param runnerMemory string = '4.0Gi'

@description('標籤')
param tags object = {
  project: 'aca-github-runner'
  environment: environment
  managedBy: 'bicep'
}

// ============================================================================
// Variables
// ============================================================================

var resourceGroupName = 'rg-${projectName}-${environment}'
var logWorkspaceName = 'log-${projectName}-${environment}'
var environmentName = 'cae-${projectName}-${environment}'
var acrName = replace(toLower('acr${projectName}${environment}${uniqueString(subscription().id)}'), '-', '')
var keyVaultName = take(toLower('kv-${projectName}${environment}${uniqueString(subscription().id)}'), 24)
var identityName = 'id-${projectName}-${environment}'
var generalJobName = 'caj-${projectName}-general-${environment}'
var copilotJobName = 'caj-${projectName}-copilot-${environment}'
var githubPatSecretName = 'github-pat'
var githubPatSecretUri = '${keyVault.outputs.keyVaultUri}secrets/${githubPatSecretName}'
var runnerImageLooksImmutable = !empty(runnerImage) && contains(runnerImage, ':') && !endsWith(toLower(runnerImage), ':latest')

// ============================================================================
// Resource Group
// ============================================================================

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ============================================================================
// 基礎設施模組（階段 A）
// ============================================================================

module log 'modules/log.bicep' = {
  name: 'deploy-log'
  scope: rg
  params: {
    location: location
    workspaceName: logWorkspaceName
    retentionInDays: logRetentionDays
    dailyQuotaGb: logDailyQuotaGb
    tags: tags
  }
}

module acr 'modules/acr.bicep' = {
  name: 'deploy-acr'
  scope: rg
  params: {
    location: location
    acrName: acrName
    tags: tags
  }
}

module keyVault 'modules/keyVault.bicep' = {
  name: 'deploy-keyvault'
  scope: rg
  params: {
    location: location
    keyVaultName: keyVaultName
    tags: tags
  }
}

module identity 'modules/identity.bicep' = {
  name: 'deploy-identity'
  scope: rg
  params: {
    location: location
    identityName: identityName
    acrId: acr.outputs.acrId
    keyVaultId: keyVault.outputs.keyVaultId
    secretsOfficerPrincipalId: secretsOfficerPrincipalId
    tags: tags
  }
}

module containerAppsEnv 'modules/containerAppsEnv.bicep' = {
  name: 'deploy-aca-env'
  scope: rg
  params: {
    location: location
    environmentName: environmentName
    logAnalyticsWorkspaceName: logWorkspaceName
    tags: tags
  }
  dependsOn: [
    log
  ]
}

resource runnerImageValidation 'Microsoft.Resources/deployments@2024-03-01' = if (enableRunnerJobs) {
  name: 'validate-runner-image'
  location: location
  properties: {
    mode: 'Incremental'
    expressionEvaluationOptions: {
      scope: 'inner'
    }
    parameters: {
      runnerImage: {
        value: runnerImage
      }
      validationState: {
        value: runnerImageLooksImmutable ? 'valid' : 'invalid'
      }
    }
    template: {
      '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        runnerImage: {
          type: 'string'
          minLength: 1
          metadata: {
            description: 'runnerImage must be non-empty when enableRunnerJobs=true.'
          }
        }
        validationState: {
          type: 'string'
          allowedValues: [
            'valid'
          ]
          metadata: {
            description: 'runnerImage must include a non-latest tag or digest.'
          }
        }
      }
      resources: []
    }
  }
}

// ============================================================================
// Runner Jobs（階段 B）
// ============================================================================

module generalJob 'modules/runnerJob.bicep' = if (enableRunnerJobs) {
  name: 'deploy-job-general'
  scope: rg
  params: {
    location: location
    jobName: generalJobName
    environmentId: containerAppsEnv.outputs.environmentId
    workloadProfileName: containerAppsEnv.outputs.workloadProfileName
    identityResourceId: identity.outputs.identityResourceId
    acrLoginServer: acr.outputs.acrLoginServer
    runnerImage: runnerImage
    githubOwner: githubOwner
    repositories: repositories
    runnerLabel: 'aca-general'
    runnerGroup: runnerGroup
    githubPatSecretUri: githubPatSecretUri
    replicaTimeoutSeconds: generalReplicaTimeoutSeconds
    maxExecutions: generalMaxExecutions
    runnerCpu: runnerCpu
    runnerMemory: runnerMemory
    tags: tags
  }
  dependsOn: [
    runnerImageValidation
  ]
}

module copilotJob 'modules/runnerJob.bicep' = if (enableRunnerJobs && enableCopilotJob) {
  name: 'deploy-job-copilot'
  scope: rg
  params: {
    location: location
    jobName: copilotJobName
    environmentId: containerAppsEnv.outputs.environmentId
    workloadProfileName: containerAppsEnv.outputs.workloadProfileName
    identityResourceId: identity.outputs.identityResourceId
    acrLoginServer: acr.outputs.acrLoginServer
    runnerImage: runnerImage
    githubOwner: githubOwner
    repositories: repositories
    runnerLabel: 'aca-copilot'
    runnerGroup: runnerGroup
    githubPatSecretUri: githubPatSecretUri
    replicaTimeoutSeconds: copilotReplicaTimeoutSeconds
    maxExecutions: copilotMaxExecutions
    runnerCpu: runnerCpu
    runnerMemory: runnerMemory
    tags: tags
  }
  dependsOn: [
    runnerImageValidation
  ]
}

// ============================================================================
// Outputs
// ============================================================================

@description('Resource Group 名稱')
output resourceGroupName string = rg.name

@description('ACR 名稱，供 build-runner-image.sh 使用')
output acrName string = acr.outputs.acrName

@description('Key Vault 名稱，供 az keyvault secret set 使用')
output keyVaultName string = keyVault.outputs.keyVaultName

@description('GitHub PAT 的 secret 名稱')
output githubPatSecretName string = githubPatSecretName

@description('Container Apps Environment 名稱')
output environmentName string = containerAppsEnv.outputs.environmentName

@description('General Job 名稱，未啟用時為空字串')
output generalJobName string = enableRunnerJobs ? generalJobName : ''

@description('Copilot Job 名稱，未啟用時為空字串')
output copilotJobNameOut string = enableRunnerJobs && enableCopilotJob ? copilotJobName : ''
