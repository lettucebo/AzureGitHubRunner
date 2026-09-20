// ============================================================================
// Event-driven GitHub Runner Job 模組
//
// 以 KEDA github-runner scaler 依 queued job 標籤觸發，runner 單次執行後結束。
// general 與 copilot 兩個 Job 共用本模組，只差 runnerLabel 與 replicaTimeout；
// 網路、image、身分、secret 來源與併發上限完全相同。
//
// 正確性設定：
//   - noDefaultLabels=true：不搶走一般 runs-on: self-hosted 的 job
//   - labels=<runnerLabel>：只計算指定標籤的 queued job
//   - repos 明確列出：避免列舉整個 org 造成 API 呼叫暴增
//   - enableEtags=true：304 回應不計入 rate limit
//   - 省略 githubApiURL：使用 scaler 預設值，避免 metadata 大小寫歧義
// ============================================================================

@description('部署位置')
param location string

@description('Job 名稱')
param jobName string

@description('Container Apps Environment 資源 ID')
param environmentId string

@description('Workload profile 名稱')
param workloadProfileName string = 'Consumption'

@description('User-assigned Managed Identity 資源 ID')
param identityResourceId string

@description('ACR login server')
param acrLoginServer string

@description('完整 runner image 參考，必須帶不可變 tag，禁止 latest')
param runnerImage string

@description('GitHub organization 名稱')
param githubOwner string

@description('scaler 監看的 repository 清單')
@minLength(1)
param repositories array

@description('Runner 標籤，同時用於 scaler 過濾與 runner 註冊')
param runnerLabel string

@description('GitHub runner group 名稱。GitHub Free 只有 Default 群組，故預設留空')
param runnerGroup string = ''

@description('Key Vault 中 GitHub PAT secret 的完整 URI')
param githubPatSecretUri string

@description('replica 最長存活秒數，必須大於實測 p99 並保留至少 25% 餘裕')
@minValue(300)
@maxValue(86400)
param replicaTimeoutSeconds int = 3600

@description('同一 polling 週期最多併發的 job execution 數')
@minValue(1)
@maxValue(30)
param maxExecutions int = 20

@description('scaler 輪詢間隔秒數，低於 30 有 GitHub API rate limit 風險')
@minValue(30)
@maxValue(300)
param pollingIntervalSeconds int = 30

@description('runner 容器 vCPU。注意 vCPU <= 1 時 ephemeral storage 只有 4 GiB')
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
param tags object = {}

resource runnerJob 'Microsoft.App/jobs@2024-03-01' = {
  name: jobName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityResourceId}': {}
    }
  }
  properties: {
    environmentId: environmentId
    workloadProfileName: workloadProfileName
    configuration: {
      triggerType: 'Event'
      replicaTimeout: replicaTimeoutSeconds
      replicaRetryLimit: 0
      eventTriggerConfig: {
        parallelism: 1
        replicaCompletionCount: 1
        scale: {
          minExecutions: 0
          maxExecutions: maxExecutions
          pollingInterval: pollingIntervalSeconds
          rules: [
            {
              name: 'github-runner'
              type: 'github-runner'
              metadata: {
                owner: githubOwner
                runnerScope: 'org'
                repos: join(repositories, ',')
                labels: runnerLabel
                noDefaultLabels: 'true'
                enableEtags: 'true'
                targetWorkflowQueueLength: '1'
              }
              auth: [
                {
                  secretRef: 'github-pat'
                  triggerParameter: 'personalAccessToken'
                }
              ]
            }
          ]
        }
      }
      secrets: [
        {
          name: 'github-pat'
          keyVaultUrl: githubPatSecretUri
          identity: identityResourceId
        }
      ]
      registries: [
        {
          server: acrLoginServer
          identity: identityResourceId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'runner'
          image: runnerImage
          resources: {
            cpu: json(runnerCpu)
            memory: runnerMemory
          }
          env: [
            {
              name: 'GITHUB_OWNER'
              value: githubOwner
            }
            {
              name: 'GITHUB_PAT'
              secretRef: 'github-pat'
            }
            {
              name: 'RUNNER_LABELS'
              value: runnerLabel
            }
            {
              name: 'RUNNER_GROUP'
              value: runnerGroup
            }
          ]
        }
      ]
    }
  }
}

@description('Job 名稱')
output jobName string = runnerJob.name
