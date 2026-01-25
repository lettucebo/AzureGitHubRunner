# AKS + ARC + Spot VM 架構部署指南

使用 Bicep 在 Azure 上建立 AKS 叢集，配合 ARC (Actions Runner Controller) 執行 GitHub Self-hosted Runners。

## ✅ 支援功能

| 功能 | 支援 | 說明 |
|------|:----:|------|
| GitHub Actions | ✅ | 執行 CI/CD workflows |
| GitHub Copilot Coding Agent | ✅ | 執行 Copilot 自動化任務 |
| 使用 GitHub 官方 Runner Image | ✅ | **無需自訂 image** |
| Spot VM 自動擴展 | ✅ | 節省 60-80% 成本 |

---

## 📋 目錄

- [架構概覽](#架構概覽)
- [成本估算](#成本估算)
- [前置需求](#前置需求)
- [快速開始](#快速開始)
- [詳細部署步驟](#詳細部署步驟)
- [故障排除](#故障排除)
- [常見問題](#常見問題)

---

## 🏗️ 架構概覽

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure Kubernetes Service                  │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────┐    ┌────────────────────────────────┐ │
│  │   System Pool    │    │        Runner Pool             │ │
│  │   (B2s × 1 台)   │    │   (Spot VM D4s_v3 × 0-3 台)   │ │
│  │                  │    │                                │ │
│  │  • K8s 系統組件  │    │  • GitHub Runner Pods          │ │
│  │  • ARC Controller│    │  • 使用官方 runner image       │ │
│  │                  │    │  • 自動擴展 (0-3)              │ │
│  └──────────────────┘    └────────────────────────────────┘ │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 關鍵設計決策

| 問題 | 答案 |
|------|------|
| **需要自訂 Runner Image 嗎？** | ❌ 不需要！使用 GitHub 官方 `ghcr.io/actions/actions-runner:latest` |
| **支援 Copilot Coding Agent 嗎？** | ✅ 是的，ARC 是官方建議架構 |
| **支援 GitHub Actions 嗎？** | ✅ 完全支援 |
| **需要 Docker-in-Docker 嗎？** | 視需求而定，如果 workflow 使用 container jobs 則需要 |

---

## 💰 成本估算

### 月度成本 (East Asia 區域)

| 組件 | 規格 | 閒置時 | 滿載時 |
|------|------|--------|--------|
| System Pool | 1× B2s | ~$30 | ~$30 |
| Runner Pool | Spot D4s_v3 (0-3台) | ~$0 | ~$87 |
| Load Balancer | Standard | ~$20 | ~$20 |
| Log Analytics | 基本 | ~$10 | ~$15 |
| **總計** | - | **~$60** | **~$152** |

> 💡 使用 Spot VM 相較一般 VM 節省約 **70%** 成本

---

## 🔧 前置需求

### 1. 安裝必要工具

```powershell
# Windows PowerShell

# 安裝 Azure CLI
winget install Microsoft.AzureCLI

# 安裝 kubectl
az aks install-cli

# 安裝 Helm
winget install Helm.Helm

# 驗證安裝
az --version
kubectl version --client
helm version
```

### 2. 建立 GitHub Personal Access Token

1. 前往 GitHub → Settings → Developer settings → Personal access tokens → **Fine-grained tokens**
2. 點擊 **Generate new token**
3. 設定以下權限：

| Repository permissions | 權限等級 |
|----------------------|---------|
| Administration | Read and write |
| Metadata | Read-only |

4. 複製產生的 token（格式: `github_pat_xxxx` 或 `ghp_xxxx`）

---

## 🚀 快速開始

### 一鍵部署腳本

```powershell
# 1. 登入 Azure
az login
az account set --subscription "<your-subscription-id>"

# 2. 進入 AKS Runner 目錄
cd src/aks-runner

# 3. 複製並編輯參數檔案
Copy-Item main.bicepparam.example -Destination main.bicepparam
# 編輯 main.bicepparam 設定您的參數

# 4. 部署 Azure 基礎設施
az deployment sub create `
  --location eastasia `
  --template-file main.bicep `
  --parameters main.bicepparam

# 5. 取得 AKS 憑證
az aks get-credentials --resource-group rg-ghrunner-dev --name aks-ghrunner-dev

# 6. 安裝 ARC
$env:GITHUB_PAT = "ghp_your_token_here"
$env:GITHUB_CONFIG_URL = "https://github.com/your-org/your-repo"
bash scripts/install-arc.sh

# 7. 驗證安裝
kubectl get pods -n arc-systems
kubectl get pods -n arc-runners
```

---

## 📖 詳細部署步驟

### Step 1: 登入 Azure

```powershell
# 登入 Azure 帳戶
az login

# 列出可用的訂閱
az account list --output table

# 設定要使用的訂閱
az account set --subscription "<subscription-id>"

# 確認目前訂閱
az account show --query name -o tsv
```

### Step 2: 準備參數檔案

```powershell
# 複製範例檔案
Copy-Item main.bicepparam.example -Destination main.bicepparam
```

編輯 `main.bicepparam`，根據需求調整以下參數：

```bicep
using 'main.bicep'

param environment = 'dev'              // 環境名稱
param projectName = 'ghrunner'         // 專案名稱
param location = 'eastasia'            // Azure 區域 (香港)

// System Pool - 固定小型 VM
param systemNodeVmSize = 'Standard_B2s'
param systemNodeCount = 1              // 1 台省錢

// Runner Pool - Spot VM 自動擴展
param runnerNodeVmSize = 'Standard_D4s_v3'
param runnerNodeMinCount = 0           // 閒置時縮到 0
param runnerNodeMaxCount = 3           // 最多 3 台

// 可選功能
param enableMonitoring = true          // Container Insights
param enableAcr = false                // 不需要 ACR（使用官方 image）
```

### Step 3: 部署 Azure 基礎設施

```powershell
# 預覽部署變更 (what-if)
az deployment sub what-if `
  --location eastasia `
  --template-file main.bicep `
  --parameters main.bicepparam

# 確認無誤後，正式部署
az deployment sub create `
  --location eastasia `
  --template-file main.bicep `
  --parameters main.bicepparam `
  --name "aks-deployment-$(Get-Date -Format 'yyyyMMddHHmmss')"
```

部署約需 5-10 分鐘。完成後會看到輸出包含：
- `aksClusterName`: AKS 叢集名稱
- `aksConnectCommand`: 連接命令
- `resourceGroupName`: 資源群組名稱

### Step 4: 連接 AKS 叢集

```powershell
# 取得 AKS 憑證
az aks get-credentials `
  --resource-group rg-ghrunner-dev `
  --name aks-ghrunner-dev

# 驗證連線
kubectl get nodes

# 應該看到類似輸出：
# NAME                            STATUS   ROLES   AGE   VERSION
# aks-system-xxxxxxxx-vmss000000  Ready    agent   5m    v1.29.x
```

### Step 5: 安裝 ARC (Actions Runner Controller)

```powershell
# 設定環境變數
$env:GITHUB_PAT = "ghp_your_token_here"                           # 您的 PAT
$env:GITHUB_CONFIG_URL = "https://github.com/your-org/your-repo"  # 您的 repo URL
$env:MAX_RUNNERS = "45"                                            # 最大 runner 數量 (3 節點 × 15)

# 執行安裝腳本 (使用 Git Bash 或 WSL)
bash scripts/install-arc.sh
```

或者手動安裝：

```powershell
# 1. 安裝 ARC Controller
# 注意: System Pool 有 CriticalAddonsOnly taint，必須添加 toleration
helm upgrade --install arc `
  --namespace arc-systems `
  --create-namespace `
  --set "tolerations[0].key=CriticalAddonsOnly" `
  --set "tolerations[0].operator=Exists" `
  --set "tolerations[0].effect=NoSchedule" `
  --wait `
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller

# 2. 建立 Runner namespace 和 Secret
kubectl create namespace arc-runners --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic github-pat-secret `
  --namespace arc-runners `
  --from-literal=github_token="$env:GITHUB_PAT" `
  --dry-run=client -o yaml | kubectl apply -f -

# 3. 複製並編輯 values 檔案
Copy-Item kubernetes/arc-runner-values.yaml.example -Destination arc-runner-values.yaml
# 編輯 arc-runner-values.yaml 設定 githubConfigUrl

# 4. 安裝 Runner Scale Set (使用官方 image)
# 注意: 必須使用 values 檔案而非 --set，因為 listenerTemplate 需要完整配置
helm upgrade --install arc-runner-set `
  --namespace arc-runners `
  -f arc-runner-values.yaml `
  --wait `
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

> ⚠️ **重要**: Listener Pod 需要 `listenerTemplate` 配置才能添加 toleration。
> 使用 `--set listenerTemplate.spec.tolerations[0]...` 會失敗，因為 `listenerTemplate.spec.containers` 是必填欄位。
> 必須使用 values 檔案 (`-f arc-runner-values.yaml`) 來提供完整配置。

### Step 6: 驗證安裝

```powershell
# 檢查 ARC Controller
kubectl get pods -n arc-systems

# 檢查 Runner Listener
kubectl get pods -n arc-runners

# 查看 Runner Scale Set 狀態
kubectl get autoscalingrunnersets -n arc-runners
```

### Step 7: 更新 GitHub Workflow

修改您的 `.github/workflows/*.yml` 檔案：

```yaml
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    # 使用 ARC runner (名稱與安裝時設定的相同)
    runs-on: arc-runner-set
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Build
        run: echo "Building on self-hosted ARC runner!"
      
      - name: Test
        run: echo "Running tests..."
```

---

## 🔍 故障排除

### ARC Controller Pod 處於 Pending 狀態

System Pool 設有 `CriticalAddonsOnly=true:NoSchedule` taint，需要在安裝時添加 toleration：

```powershell
# 檢查 Controller Pod 狀態
kubectl describe pod -n arc-systems -l app.kubernetes.io/name=gha-rs-controller

# 重新安裝 Controller 並添加 toleration
helm upgrade --install arc --namespace arc-systems `
  --set "tolerations[0].key=CriticalAddonsOnly" `
  --set "tolerations[0].operator=Exists" `
  --set "tolerations[0].effect=NoSchedule" `
  --wait `
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller
```

### Listener Pod 處於 Pending 狀態

Listener Pod 也需要 CriticalAddonsOnly toleration，但**必須使用 values 檔案**：

```powershell
# 檢查 Listener Pod 狀態
kubectl describe pod -n arc-systems -l app.kubernetes.io/component=runner-scale-set-listener

# 如果看到 "untolerated taint {CriticalAddonsOnly: true}"，需要重新安裝
# ⚠️ 注意: 不能只用 --set，因為 listenerTemplate.spec.containers 是必填欄位

# 使用 values 檔案重新安裝
helm upgrade --install arc-runner-set --namespace arc-runners `
  -f kubernetes/arc-runner-values.yaml.example `
  --wait `
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

### Runner Pods 無法調度到 Spot VM Pool

```powershell
# 檢查 runner pool 是否有節點
kubectl get nodes -l nodepool-type=runner

# 如果沒有節點，手動 scale up
az aks nodepool scale `
  --resource-group rg-ghrunner-dev `
  --cluster-name aks-ghrunner-dev `
  --name runner `
  --node-count 1
```

### 查看 ARC Controller 日誌

```powershell
kubectl logs -n arc-systems -l app.kubernetes.io/name=gha-rs-controller -f
```

### 查看 Runner Listener 日誌

```powershell
kubectl logs -n arc-runners -l app.kubernetes.io/component=runner-scale-set-listener -f
```

### GitHub 無法連接到 Runner

1. 確認 PAT token 有正確權限
2. 確認 `githubConfigUrl` 格式正確
3. 檢查 outbound 網路連線

---

## ❓ 常見問題

### Q: 一定要使用自訂 runner image 嗎？

**A: 不需要！** GitHub 官方提供的 `ghcr.io/actions/actions-runner:latest` image 已經包含所有必要組件，可以直接執行 GitHub Actions 和 Copilot Coding Agent。

### Q: 這個架構支援 GitHub Copilot Coding Agent 嗎？

**A: 完全支援！** ARC (Actions Runner Controller) 是 GitHub 官方建議用於執行 Copilot Coding Agent 的架構。Copilot Coding Agent 會在 runner pod 中執行，與一般 GitHub Actions job 相同。

根據 [GitHub 官方文件](https://docs.github.com/en/copilot/using-github-copilot/using-copilot-coding-agent-to-work-on-tasks/about-assigning-tasks-to-copilot):
> Copilot can use a GitHub-hosted runner... If you want to use self-hosted runners... you must use Actions Runner Controller (ARC).

### Q: 為什麼使用 Docker-in-Docker (dind) 模式？

**A:** 如果您的 workflow 使用 `container:` 語法或 Docker actions，需要啟用 dind 模式。如果不需要，可以在安裝時設定 `CONTAINER_MODE=""` 來停用。

### Q: Spot VM 被回收怎麼辦？

**A:** ARC 會自動重新調度 runner pods 到可用節點。正在執行的 job 會失敗並顯示錯誤，GitHub Actions 會根據 retry 設定重試。

---

## 📁 目錄結構

```
src/aks-runner/
├── main.bicep                    # 主部署檔案
├── main.bicepparam.example       # 參數範例
├── README.md                     # 本文件
├── .gitignore
├── modules/
│   ├── aks.bicep                # AKS 模組
│   ├── acr.bicep                # ACR 模組 (可選)
│   └── log.bicep                # Log Analytics 模組
├── kubernetes/
│   ├── namespaces.yaml          # Namespace 定義
│   └── runner-scale-set.yaml    # Runner 配置範例
└── scripts/
    └── install-arc.sh           # ARC 安裝腳本
```

---

## 🔗 相關資源

- [ARC 官方文件](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller)
- [GitHub Copilot Coding Agent](https://docs.github.com/en/copilot/using-github-copilot/using-copilot-coding-agent-to-work-on-tasks)
- [Azure AKS 文件](https://learn.microsoft.com/en-us/azure/aks/)
- [Bicep 文件](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)

---

## 📝 授權

MIT License
