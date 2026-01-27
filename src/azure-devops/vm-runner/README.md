# Azure DevOps VM Runner (Terraform)

使用 Terraform 在 Azure VM 上部署 Azure DevOps Self-hosted Agents。

## 📋 功能特色

- ✅ 單一 VM 運行多個 Azure DevOps Agents
- ✅ 支援 Spot VM，節省 70-90% 成本
- ✅ 預裝 .NET SDK, Node.js, Docker, Azure CLI, PowerShell
- ✅ 使用 systemd 管理 Agent 服務
- ✅ 自動化部署，一鍵完成

## 🏗️ 架構說明

```
Azure VM (Ubuntu 22.04)
├── azdevops-agent-1 (systemd service)
├── azdevops-agent-2 (systemd service)
└── azdevops-agent-3 (systemd service)
```

每個 Agent 都作為獨立的 systemd 服務運行，可以同時處理多個 pipeline jobs。

## 📦 前置需求

1. **Azure 訂閱**
2. **Terraform** >= 1.0
3. **Azure CLI**
4. **Azure DevOps 組織和 PAT Token**
   - 需要權限: Agent Pools (Read & manage)
   - 建立 PAT: https://dev.azure.com/your-org/_usersSettings/tokens

## 🚀 快速開始

### 1. 準備 SSH 金鑰

```bash
# 產生 SSH 金鑰對
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"

# 取得公鑰內容
cat ~/.ssh/id_rsa.pub
```

### 2. 建立配置檔

```bash
cd src/azure-devops/vm-runner
cp terraform.tfvars.example terraform.tfvars
```

### 3. 編輯 terraform.tfvars

```hcl
# Azure 基礎設定
resource_group_name = "AzureDevOps-Runners"
location            = "eastasia"
prefix              = "ado-runner"

# VM 配置
vm_size             = "Standard_D4s_v5"  # 4 vCPU, 16GB RAM
use_spot_instance   = true               # 使用 Spot VM 節省成本

# SSH 配置
admin_username      = "azureuser"
ssh_public_key      = "ssh-rsa AAAAB3NzaC1... your-key-here"

# Azure DevOps 配置
azure_devops_url        = "https://dev.azure.com/your-organization"
azure_devops_token      = "your-pat-token-here"
azure_devops_pool_name  = "Default"

# Agent 數量
runner_count = 3
```

### 4. 部署

```bash
# 初始化 Terraform
terraform init

# 檢視執行計劃
terraform plan

# 執行部署
terraform apply
```

### 5. 驗證部署

```bash
# 取得 VM IP
terraform output public_ip_address

# SSH 連線到 VM
ssh azureuser@<VM_IP>

# 檢查 Agent 狀態
sudo systemctl status vsts.agent.*.service

# 檢視 Agent 日誌
sudo journalctl -u vsts.agent.*.azure-agent-1.service -f
```

## 📊 成本估算

| 項目 | 規格 | 一般價格 | Spot 價格 | 節省 |
|------|------|---------|----------|------|
| VM | Standard_D4s_v5 | ~$140/月 | ~$14-42/月 | 70-90% |
| Storage | 128GB Premium SSD | ~$20/月 | ~$20/月 | - |
| **總計** | | **~$160/月** | **~$34-62/月** | **~70%** |

## 🔧 管理指令

### 檢查 Agent 狀態
```bash
# 列出所有 Agent 服務
sudo systemctl list-units vsts.agent.* --all

# 檢查特定 Agent
sudo systemctl status vsts.agent.*.azure-agent-1.service
```

### 重啟 Agent
```bash
# 重啟特定 Agent
cd /opt/azdevops-agent-1
sudo ./svc.sh restart
```

### 查看日誌
```bash
# 即時查看日誌
sudo journalctl -u vsts.agent.*.azure-agent-1.service -f

# 查看最近 100 行日誌
sudo journalctl -u vsts.agent.*.azure-agent-1.service -n 100
```

### 移除 Agent
```bash
cd /opt/azdevops-agent-1
sudo ./svc.sh stop
sudo ./svc.sh uninstall
./config.sh remove --auth pat --token <your-pat-token>
```

## ⚙️ 變數說明

| 變數 | 說明 | 預設值 |
|------|------|--------|
| `resource_group_name` | Resource Group 名稱 | `AzureDevOps` |
| `location` | Azure 區域 | `eastasia` |
| `prefix` | 資源名稱前綴 | `ado-runner` |
| `vm_size` | VM 規格 | `Standard_D4s_v5` |
| `use_spot_instance` | 使用 Spot Instance | `true` |
| `azure_devops_url` | Azure DevOps 組織 URL | - |
| `azure_devops_token` | PAT Token | - |
| `azure_devops_pool_name` | Agent Pool 名稱 | `Default` |
| `runner_count` | Agent 數量 | `3` |

## 🔐 安全建議

1. **不要將 PAT Token 提交到版本控制**
   - 使用 `.gitignore` 排除 `terraform.tfvars`
   - 或使用 Azure Key Vault 儲存敏感資訊

2. **限制 SSH 來源 IP**
   ```hcl
   ssh_source_address_prefix = "1.2.3.4/32"  # 只允許特定 IP
   ```

3. **使用最小權限原則**
   - PAT Token 只需要 `Agent Pools (Read & manage)` 權限

4. **定期更新 VM**
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

## 🧹 清理資源

```bash
# 刪除所有資源
terraform destroy

# 確認刪除
# 輸入 'yes' 確認
```

## 📚 更多資訊

- [Azure DevOps Agent 官方文件](https://learn.microsoft.com/azure/devops/pipelines/agents/agents)
- [Azure Spot VMs 介紹](https://learn.microsoft.com/azure/virtual-machines/spot-vms)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

## ❓ 疑難排解

### Agent 無法連線到 Azure DevOps
1. 檢查 PAT Token 是否正確
2. 確認 PAT Token 權限包含 `Agent Pools (Read & manage)`
3. 檢查網路連線: `curl https://dev.azure.com`

### Spot VM 被回收
- Spot VM 可能會被 Azure 回收
- 檢查 VM 狀態: `az vm list -d -g <resource-group>`
- 如需穩定性，將 `use_spot_instance` 設為 `false`

### Agent 服務無法啟動
```bash
# 檢查服務狀態
sudo systemctl status vsts.agent.*.service

# 檢查日誌
sudo journalctl -u vsts.agent.*.service -n 100
```
