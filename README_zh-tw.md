🌏 Language / 語言: [English](README.md) | [繁體中文](README_zh-tw.md)

---

# Azure 自建 Runner 解決方案

完整的解決方案，用於在 Azure 上部署自建 Runner/Agent，支援 **GitHub Actions** 和 **Azure DevOps Pipelines**。

## 🎯 支援平台

| 平台 | VM Runner | AKS Runner |
|----------|:---------:|:----------:|
| **GitHub Actions** | ✅ | ✅ |
| **Azure DevOps** | ✅ | ✅ |

---

## 📦 部署選項

### GitHub Actions Runners

| 解決方案 | 使用情境 | 技術 | 可擴展性 | 成本 |
|----------|----------|------------|-------------|------|
| **[GitHub VM Runner](src/github/vm-runner/)** | 簡單專案，固定工作負載 | Terraform | 固定實例 | 💰 |
| **[GitHub AKS Runner](src/github/aks-runner/)** | Copilot Agent，動態工作負載 —— **現行 fallback 平台，持續運行** | Bicep + ARC | 自動擴展 0-N | 💰💰 |
| **[GitHub ACA Runner](src/github/aca-runner/)** | 一般 CI 與 Copilot cloud agent，逐 repo、逐 workflow 漸進驗證（無 Docker 需求） | Bicep + Container Apps Jobs | 自動擴展 0-N，event-driven，可縮到零 | 💰 |

### Azure DevOps Pipeline Agents

| 解決方案 | 使用情境 | 技術 | 可擴展性 | 成本 |
|----------|----------|------------|-------------|------|
| **[Azure DevOps VM Agent](src/azure-devops/vm-runner/)** | 簡單管線，固定工作負載 | Terraform | 固定實例 | 💰 |
| **[Azure DevOps AKS Agent](src/azure-devops/aks-runner/)** | 動態工作負載，自動擴展 | Bicep + KEDA | 自動擴展 0-N | 💰💰 |

---

## 🖥️ GitHub VM Runner (Terraform)

適合**簡單的 GitHub Actions 專案**，在單一 VM 上執行多個 Runners。

```
src/github/vm-runner/    # Terraform 基礎設施
├── main.tf              # 主要配置
├── variables.tf         # 變數定義
└── scripts/             # 初始化腳本
```

### 功能特色
- ✅ 使用簡單，單一 VM 運行多個 Runners
- ✅ Spot VM 節省 70-90% 成本
- ✅ 預裝 .NET SDK, Node.js, Docker
- ❌ 不支援 Copilot Coding Agent

📖 **文件**: [docs/github/vm-runner/](docs/github/vm-runner/)

---

## ☸️ GitHub AKS Runner (Bicep + ARC)

適合 **GitHub Copilot Coding Agent** 和需要自動擴展的情境。

```
src/github/aks-runner/   # Bicep 基礎設施
├── main.bicep           # 主要部署
├── modules/             # AKS/ACR/Log 模組
├── kubernetes/          # K8s 配置
└── scripts/             # ARC 安裝腳本
```

### 功能特色
- ✅ **支援 GitHub Copilot Coding Agent**
- ✅ 自動擴展 (0-N 實例)
- ✅ Spot VM 節省 60-80% 成本
- ✅ 使用 GitHub 官方 Runner 映像

📖 **文件**: [docs/github/aks-runner/](docs/github/aks-runner/)

---

## ⚡ GitHub ACA Runner (Bicep + Container Apps Jobs)

事件驅動、可縮到零的替代方案，正**逐 repo、逐 workflow 漸進**導入。上方的 AKS Runner 目前仍是現行 fallback，在整個導入期間持續運行、不做變更 —— 任何 live 部署或切換前請先閱讀 runbook。

```
src/github/aca-runner/   # Bicep 基礎設施
├── main.bicep           # 兩階段部署（先建基礎設施，再開啟 runner jobs）
├── modules/              # ACR/Key Vault/Identity/ACA env/runner job 模組
├── runner-image/         # ephemeral runner 的 Dockerfile 與 entrypoint
└── scripts/              # 建置、版本釘選、部署後驗證腳本
```

### 功能特色
- ✅ 可縮到零（`minExecutions: 0`），無閒置計算費用
- ✅ 支援一般 CI（`aca-general`）與 GitHub Copilot cloud agent（`aca-copilot`）
- ❌ 不支援 Docker/container jobs，本地磁碟上限 8 GiB —— 超出者需改用 GitHub-hosted runner
- ⚠️ 任何 live 部署或 Copilot 切換前，須先完成 RUNBOOK Gate A/B 核准

📖 **文件**: [src/github/aca-runner/README_zh-tw.md](src/github/aca-runner/README_zh-tw.md) · [Runbook](docs/github/aca-runner/RUNBOOK_zh-tw.md)

---

## 🖥️ Azure DevOps VM Agent (Terraform)

適合**簡單的 Azure Pipelines 專案**，在單一 VM 上執行多個 Agents。

```
src/azure-devops/vm-runner/   # Terraform 基礎設施
├── main.tf                   # 主要配置
├── variables.tf              # 變數定義
└── scripts/                  # 初始化腳本
```

### 功能特色
- ✅ 使用簡單，單一 VM 運行多個 Agents
- ✅ Spot VM 節省 70-90% 成本
- ✅ 預裝 .NET SDK, Node.js, Docker, Azure CLI, PowerShell
- ✅ 支援組織和專案層級的 Agent Pool

📖 **文件**: [src/azure-devops/vm-runner/README.md](src/azure-devops/vm-runner/README.md)

---

## ☸️ Azure DevOps AKS Agent (Bicep + KEDA)

適合需要自動擴展的**動態 Azure Pipelines 工作負載**。

```
src/azure-devops/aks-runner/  # Bicep 基礎設施
├── main.bicep                # 主要部署
├── modules/                  # AKS/ACR/Log 模組
├── kubernetes/               # K8s 配置
└── scripts/                  # KEDA 安裝腳本
```

### 功能特色
- ✅ **根據 Pipeline 隊列自動擴展** (透過 KEDA)
- ✅ 無任務時縮減至零 (0-N 實例)
- ✅ Spot VM 節省 60-80% 成本
- ✅ 使用 Microsoft 官方 Agent 容器映像

📖 **文件**: [src/azure-devops/aks-runner/README.md](src/azure-devops/aks-runner/README.md)

---

## 📁 專案結構

```
.
├── README.md                        # 本檔案
├── LICENSE
├── .github/
│   └── workflows/
│       ├── ci-vm.yml               # VM Runner CI
│       └── ci-aks.yml              # AKS Runner CI
├── src/
│   ├── github/                     # GitHub Actions 解決方案
│   │   ├── vm-runner/              # Terraform VM runner
│   │   ├── aks-runner/             # Bicep AKS runner (ARC) —— 現行 fallback
│   │   └── aca-runner/             # Bicep ACA runner (Container Apps Jobs) —— 漸進導入
│   ├── azure-devops/               # Azure DevOps 解決方案
│   │   ├── vm-runner/              # Terraform VM agent
│   │   └── aks-runner/             # Bicep AKS agent (KEDA)
│   ├── functions/                  # 工具型 Azure Functions
│   │   └── start-aks/              # 定時啟動 AKS (Flex Consumption)
│   └── common-scripts/             # 共用工具腳本
└── docs/
    ├── github/                     # GitHub 解決方案文件
    │   ├── vm-runner/
    │   ├── aks-runner/
    │   └── aca-runner/              # RUNBOOK.md / RUNBOOK_zh-tw.md
    └── azure-devops/               # Azure DevOps 解決方案文件
        ├── vm-runner/
        └── aks-runner/
```

---

## 🚀 快速開始

### GitHub VM Runner (簡單)

```bash
cd src/github/vm-runner
cp terraform.tfvars.example terraform.tfvars
# 編輯 terraform.tfvars，填入您的 GitHub PAT 和 repo URL
terraform init
terraform apply
```

### GitHub AKS Runner (Copilot Agent)

```bash
cd src/github/aks-runner
cp main.bicepparam.example main.bicepparam
# 編輯 main.bicepparam
az deployment sub create --location eastasia --template-file main.bicep --parameters main.bicepparam
# 安裝 ARC
./scripts/install-arc.sh
```

### GitHub ACA Runner (漸進導入，需先核准)

> ⚠️ 此非「現在就能執行」的快速開始。Live 部署前須先完成 RUNBOOK Gate A 核准（Copilot 另需 Gate B）。完整核准流程請見 [src/github/aca-runner/README_zh-tw.md](src/github/aca-runner/README_zh-tw.md) 與 [docs/github/aca-runner/RUNBOOK_zh-tw.md](docs/github/aca-runner/RUNBOOK_zh-tw.md)。

```bash
cd src/github/aca-runner
cp main.bicepparam.example main.bicepparam
# 階段 A：僅部署基礎設施 (enableRunnerJobs=false)
az deployment sub create --location eastasia --template-file main.bicep --parameters main.bicepparam
# 寫入 PAT、建置 runner image，再進行 enableRunnerJobs=true 的階段 B
```

### Azure DevOps VM Agent (簡單)

```bash
cd src/azure-devops/vm-runner
cp terraform.tfvars.example terraform.tfvars
# 編輯 terraform.tfvars，填入您的 Azure DevOps PAT 和組織 URL
terraform init
terraform apply
```

### Azure DevOps AKS Agent (自動擴展)

```bash
cd src/azure-devops/aks-runner
cp main.bicepparam.example main.bicepparam
# 編輯 main.bicepparam
az deployment sub create --location eastasia --template-file main.bicep --parameters main.bicepparam
# 安裝 KEDA
./scripts/install-keda.sh
# 部署 agents
kubectl apply -f kubernetes/
```

---

## 📊 解決方案比較

| 功能 | GitHub VM | GitHub AKS | GitHub ACA | Azure DevOps VM | Azure DevOps AKS |
|---------|:---------:|:----------:|:----------:|:---------------:|:----------------:|
| 平台 | GitHub Actions | GitHub Actions | GitHub Actions | Azure Pipelines | Azure Pipelines |
| 技術 | Terraform | Bicep + ARC | Bicep + Container Apps Jobs | Terraform | Bicep + KEDA |
| 自動擴展 | ❌ | ✅ | ✅（event-driven） | ❌ | ✅ |
| 縮減至零 | ❌ | ❌（system pool 固定） | ✅ | ❌ | ✅ |
| Copilot Agent | ❌ | ✅（現行 fallback） | ✅（漸進導入，見 RUNBOOK） | N/A | N/A |
| Docker/container jobs | ✅ | ✅ | ❌ | ✅ | ✅ |
| Spot VM 支援 | ✅ | ✅ | N/A | ✅ | ✅ |
| 閒置成本 | ~$29/月 | ~$130–150/月 | ~$5–7/月 | ~$29/月 | ~$40/月 |
| 複雜度 | 簡單 | 中等 | 中等 | 簡單 | 中等 |

---

## 🔗 相關資源

### GitHub
- [GitHub Self-hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [GitHub Copilot Coding Agent](https://docs.github.com/en/copilot/using-github-copilot/using-copilot-coding-agent-to-work-on-tasks)
- [Actions Runner Controller (ARC)](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller)

### Azure DevOps
- [Azure Pipelines Agents](https://learn.microsoft.com/zh-tw/azure/devops/pipelines/agents/agents)
- [Self-hosted Linux Agents](https://learn.microsoft.com/zh-tw/azure/devops/pipelines/agents/linux-agent)
- [KEDA Azure Pipelines Scaler](https://keda.sh/docs/scalers/azure-pipelines/)

### Azure
- [Azure Spot VMs](https://learn.microsoft.com/zh-tw/azure/virtual-machines/spot-vms)
- [Azure Kubernetes Service (AKS)](https://learn.microsoft.com/zh-tw/azure/aks/)
- [KEDA - Kubernetes Event-driven Autoscaling](https://keda.sh/)

---

## 📝 授權

MIT License
