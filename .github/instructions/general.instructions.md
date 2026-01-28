---
applyTo: "**"
---
# Azure Self-hosted Runner 專案指引

## 專案架構總覽

這是一個基礎設施即代碼 (IaC) 專案，用於在 Azure 上部署 GitHub Actions 和 Azure DevOps 的 Self-hosted Runners。

### 四種部署方案

1. **GitHub VM Runner** (`src/github/vm-runner/`) - Terraform + VM
2. **GitHub AKS Runner** (`src/github/aks-runner/`) - Bicep + AKS + ARC
3. **Azure DevOps VM Agent** (`src/azure-devops/vm-runner/`) - Terraform + VM  
4. **Azure DevOps AKS Agent** (`src/azure-devops/aks-runner/`) - Bicep + AKS + KEDA

### 技術堆疊對照

| 平台 | VM 方案 | AKS 方案 |
|------|---------|----------|
| GitHub | Terraform | Bicep + ARC (Actions Runner Controller) |
| Azure DevOps | Terraform | Bicep + KEDA |

## 關鍵設計決策

### GitHub AKS Runner 特性
- **支援 GitHub Copilot Coding Agent** - 這是專案的主要使用案例之一
- **使用官方 Runner Image** - `ghcr.io/actions/actions-runner:latest`，無需自訂 container image
- **雙 Pool 架構**:
  - System Pool: 1× B2s (固定), 承載 K8s 系統組件與 ARC controller
  - Runner Pool: 0-10× D4s_v3 Spot VM (自動擴展), 承載 GitHub runner 工作負載

### VM Runner 特性
- **Cloud-init 初始化** - 使用 `cloud-init.yml` 配置 VM
- **Setup Script** - `setup-runners.sh` 負責安裝並啟動多個 runner instances
- **Systemd 管理** - 每個 runner 作為獨立的 systemd service 運行

## 部署工作流程

### Bicep 部署 (AKS 方案)
1. 複製範例參數檔: `cp main.bicepparam.example main.bicepparam`
2. 編輯 `main.bicepparam` 填入必要參數
3. 部署: `az deployment sub create --location eastasia --template-file main.bicep --parameters main.bicepparam`
4. 安裝 controller:
   - GitHub: `./scripts/install-arc.sh` (需要 `GITHUB_PAT` 和 `GITHUB_CONFIG_URL`)
   - Azure DevOps: `./scripts/install-keda.sh`

### Terraform 部署 (VM 方案)
1. 複製範例變數檔: `cp terraform.tfvars.example terraform.tfvars`
2. 編輯 `terraform.tfvars` 填入 token、repo URL 等
3. 初始化: `terraform init`
4. 部署: `terraform apply`

## 模組結構規範

### Bicep 模組 (`modules/`)
- `aks.bicep` - AKS 叢集定義 (System Pool + Spot Runner Pool)
- `acr.bicep` - Azure Container Registry (若需要自訂 image)
- `log.bicep` - Log Analytics Workspace (用於 Container Insights)

### Kubernetes 配置 (`kubernetes/`)
- **GitHub**: `arc-runner-values.yaml` - ARC Helm chart 配置
- **Azure DevOps**: `agent-deployment.yaml` + `agent-values.yaml` - KEDA ScaledJob 配置

## 腳本規範

### Bash Scripts
所有腳本遵循以下慣例:
- 使用 `set -e` (遇錯立即中止)
- 定義顏色輸出函數: `log_info`, `log_warn`, `log_error`, `log_step`
- 透過環境變數接收配置 (如 `GITHUB_PAT`, `GITHUB_CONFIG_URL`)
- 提供預設值與驗證邏輯

### PowerShell Scripts
位於 `src/common-scripts/`:
- `Backup-SSHKey.ps1` - 備份 SSH key 到 OneDrive
- `Import-SSHKey.ps1` - 從 OneDrive 匯入 SSH key
- `Restore-SSHKey.ps1` - 還原 SSH key

## 文件組織

### 雙語文件
所有主要文件提供繁體中文與英文版本:
- `README.md` (英文) + `README_zh-tw.md` (繁中)
- 使用語言切換連結: `🌏 Language / 語言: [English](README.md) | [繁體中文](README_zh-tw.md)`

### 文件位置
- **專案根目錄**: 總覽文件
- **`src/*/` 目錄**: 技術部署文件 (Terraform/Bicep)
- **`docs/*/` 目錄**: 使用者導向文件 (快速開始、故障排除、SSH 金鑰指南等)

## 成本與資源規劃

### 命名慣例
使用參數 `projectName` + `environment` 組合:
- Resource Group: `${projectName}-${environment}-rg`
- AKS: `${projectName}-${environment}-aks`
- ACR: `${projectName}${environment}acr` (無破折號，因 ACR 限制)

### Spot VM 使用
- GitHub AKS Runner: Spot D4s_v3 (節省 60-80% 成本)
- Azure DevOps AKS Agent: Spot D4s_v3 (節省 60-80% 成本)
- VM Runner: 可選 Spot VM (節省 70-90% 成本)

## 自我審查流程
當你執行完畢之後，請先自我審查一次，確認你是否滿意。若不滿意，請進行修正，直到你確定百分之百滿意為止。
