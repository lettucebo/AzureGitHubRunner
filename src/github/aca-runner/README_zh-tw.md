🌏 Language / 語言: [English](README.md) | [繁體中文](README_zh-tw.md)

---

# GitHub Actions ACA Runner (Container Apps Jobs)

以 Azure Container Apps（ACA）Jobs 與 KEDA `github-runner` scaler 建置的事件驅動、可縮到零的 GitHub Actions self-hosted runner。

> ⚠️ **目前狀態**：這是**第二個、採漸進式驗證**的 runner 平台。導入方式為**逐 repo、逐 workflow**。既有的 AKS + ARC runner（**[`src/github/aks-runner/`](../aks-runner/)**）目前仍是現行 fallback，**在整個導入過程中持續運行、不做變更**。任何 live 部署或切換步驟前，請先確認 [RUNBOOK.md](../../../docs/github/aca-runner/RUNBOOK.md) 所列的核准 Gate。

## ✅ 支援功能

| Feature | Supported | Notes |
|---|:---:|---|
| Scale to zero | ✅ | `minExecutions: 0`, no idle compute charge |
| Ephemeral single-use runners | ✅ | `config.sh --ephemeral` |
| General CI | ✅ | Label `aca-general` |
| GitHub Copilot cloud agent | ✅ | Label `aca-copilot`, same network configuration as general |
| Docker / container jobs / service containers | ❌ | Specify a GitHub-hosted runner directly in the workflow |
| Local disk above 8 GiB | ❌ | Specify a GitHub-hosted larger runner directly in the workflow |
| Network egress filtering | ❌ | Deliberate decision, see RUNBOOK |
| Repository-level runner isolation | ❌ | Requires GitHub Team runner groups |

## 📋 目錄

- [架構概覽](#-架構概覽)
- [成本估算](#-成本估算)
- [前置需求](#-前置需求)
- [快速開始](#-快速開始)
- [故障排除](#-故障排除)
- [目錄結構](#-目錄結構)
- [相關文件](#-相關文件)

## 🏗️ 架構概覽

```text
GitHub Actions queue
        │  KEDA github-runner scaler
        │  noDefaultLabels=true, enableEtags=true
        ▼
┌─────────────────────────────────────────────┐
│ Container Apps Environment (Workload Profiles)│
│  platform-managed network, no VNet            │
│  ┌──────────────────┐  ┌───────────────────┐ │
│  │ Job: general     │  │ Job: copilot      │ │
│  │ label aca-general│  │ label aca-copilot │ │
│  │ timeout 3600s    │  │ timeout 7200s     │ │
│  └──────────────────┘  └───────────────────┘ │
│  0 → N ephemeral runner replicas              │
└─────────────────────────────────────────────┘
        │ managed identity (platform-level)
        ├── ACR      (runner image, immutable tag)
        └── Key Vault (GitHub PAT)
```

兩個 Job 共用同一個 environment、managed identity、image 與 secret 來源，只差 `runnerLabel` 與 `replicaTimeout`。Runner image 內沒有 Docker daemon，需要 Docker/container 的 workflow 必須直接指定 GitHub-hosted runner，不應假設有任何自動 fallback。

## 💰 成本估算

| 組件 | 計算基礎 | 月成本 |
|---|---|---|
| ACA compute | 約 843.7 分鐘/月 @ 2 vCPU/4 GiB，落在每月免費額度內 | **$0** |
| ACR Basic | 固定費用 | ~$5.2 |
| Log Analytics | 僅 Job execution logs | ~$0–2 |
| **總計** | - | **約 $5–7/月** |

> 💡 與 AKS 不同，ACA Jobs 沒有常駐 node pool；可縮到零，閒置時只剩 ACR 與 Log Analytics 的固定費用。

## 🔧 前置需求

1. **Azure CLI** 並安裝 `containerapp` extension：
   ```bash
   az extension add --name containerapp --upgrade
   ```
2. **GitHub organization fine-grained PAT**，需具備 `Self-hosted runners: Read and write`、`Actions: Read`、`Metadata: Read`（詳細檢查清單與到期日追蹤見 RUNBOOK Gate A）。
3. **Key Vault data-plane 權限**：部署者需具備目標 Key Vault 的 `Key Vault Secrets Officer`，或 `secretsOfficerPrincipalId` 已設定為已具備該權限的 principal。

## 🚀 快速開始

> ⚠️ **在對實際訂閱或 GitHub organization 執行以下任何指令前，必須先取得核准。** 本節僅記錄預期的指令順序。在 RUNBOOK Gate A 完成簽核前，不得進行 live 部署；Copilot Job 另外需要完成 Gate B。

```bash
# 1. 階段 A：部署基礎設施（enableRunnerJobs 保持 false）
cp main.bicepparam.example main.bicepparam
az deployment sub create --location eastasia \
  --template-file main.bicep --parameters main.bicepparam

# 2. 寫入 PAT 並建置 image
az keyvault secret set --vault-name <keyVaultName> --name github-pat --value "<PAT>"
export ACR_NAME="<acrName>"
./scripts/build-runner-image.sh

# 3. 階段 B：enableRunnerJobs=true 並填入 runnerImage 後重新部署
az deployment sub create --location eastasia \
  --template-file main.bicep --parameters main.bicepparam
```

部署完成後，先執行 `scripts/verify-aca-runner.sh`（見[目錄結構](#-目錄結構)）確認 `triggerType`、`minExecutions`、`noDefaultLabels`、`runnerScope` 與 image tag，再導入任何實際 workflow 流量。

## 🔍 故障排除

### Runner 未被觸發

- 確認 workflow 的 `runs-on` label 與 Job 的 `runnerLabel`（`aca-general` 或 `aca-copilot`）完全一致。
- 檢查 scale rule 的 `noDefaultLabels` 是否為 `true`；若非，scaler 也會誤判其他 runner（例如 AKS/ARC）用的一般 `self-hosted` job。
  ```bash
  az containerapp job show -g <rg> -n <jobName> \
    --query "properties.configuration.eventTriggerConfig.scale.rules[0].metadata"
  ```

### Image pull 失敗

- 確認 managed identity 已具備 ACR 的 `AcrPull`（見 `modules/identity.bicep`）。
- ACA 透過 identity 換取 ARM token 才能拉取 ACR image；若 registry 被重建或 role assignment 遺失，會出現 `403`/`UNAUTHORIZED`。
  ```bash
  az role assignment list --scope <acrId> --query "[?principalId=='<identityPrincipalId>']"
  ```

### Secret（`github-pat`）讀取失敗

- managed identity 需要 Key Vault 的 `Key Vault Secrets User`（data-plane），僅有 subscription 層級 RBAC 不足以讀取 secret。
  ```bash
  az role assignment list --scope <keyVaultId> --query "[?principalId=='<identityPrincipalId>']"
  ```

### `az keyvault secret set` 回傳 403

- 部署者（而非 managed identity）缺少 `Key Vault Secrets Officer`。可手動授予，或在 `main.bicepparam` 設定 `secretsOfficerPrincipalId` 後重新部署。

### Replica 在 job 完成前提早結束

- 比對 `replicaTimeoutSeconds`（general 預設 3600 秒、copilot 預設 7200 秒）與 workflow 的 `timeout-minutes`。若 workflow timeout 大於 replica timeout，ACA 會先終止 replica。
- Copilot Job 的 `copilotReplicaTimeoutSeconds` 必須先實測真實 session p99 時長後才能調高（見 RUNBOOK Gate B）。

## 📁 目錄結構

```
src/github/aca-runner/
├── main.bicep                    # Subscription scope，兩階段部署
├── main.bicepparam.example       # 參數範例
├── modules/
│   ├── log.bicep                 # Log Analytics workspace
│   ├── acr.bicep                 # Container Registry
│   ├── keyVault.bicep             # 存放 GitHub PAT 的 Key Vault
│   ├── identity.bicep             # User-assigned identity 與角色指派
│   ├── containerAppsEnv.bicep     # Container Apps Environment (Consumption)
│   └── runnerJob.bicep            # 共用的事件驅動 runner Job 樣板
├── runner-image/                 # ephemeral runner 的 Dockerfile 與 entrypoint
└── scripts/
    ├── build-runner-image.sh     # az acr build，image tag 使用 git SHA
    ├── update-runner-version.sh  # 更新 runner 版本與 checksum
    └── verify-aca-runner.sh      # 部署後設定檢查
```

## 📖 相關文件

- [English README](README.md)
- [運維 Runbook](../../../docs/github/aca-runner/RUNBOOK.md) — 核准 Gate、安全接受事項、PoC 驗收記錄表，以及（目前尚未核准的）AKS 停機順序
- [GitHub AKS Runner](../aks-runner/README_zh-tw.md) — 現行 fallback 平台，導入期間維持不變
- [Azure Container Apps jobs tutorial](https://learn.microsoft.com/zh-tw/azure/container-apps/tutorial-ci-cd-runners-jobs)
- [KEDA github-runner scaler](https://keda.sh/docs/scalers/github-runner/)

---

## 📝 授權

MIT License
