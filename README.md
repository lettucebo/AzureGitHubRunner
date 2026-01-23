# Azure VM for GitHub Self-hosted Runners

使用 Terraform 在 Azure 上建立 Linux VM，並自動配置多個 GitHub Self-hosted Runners，支援並行執行多個 CI/CD jobs。

## 功能特點

- ✅ 使用 Terraform 管理 Azure 基礎設施
- ✅ 完全自動化的 VM 配置（cloud-init）
- ✅ 支援多個並行的 GitHub Self-hosted Runners
- ✅ 預裝 .NET SDK 和 Node.js (版本 20, 22, 24)
- ✅ 使用 systemd 管理 runner 服務
- ✅ 安全性配置（NSG、SSH key）
- 💰 **支援 Azure Spot VM（可節省高達 90% 成本！）**

## 架構組成

### Azure 資源
- Resource Group
- Virtual Network + Subnet
- Network Security Group (僅允許 SSH)
- Public IP Address
- Network Interface
- Linux Virtual Machine (Ubuntu 22.04 LTS)

### VM 規格建議
- **基本配置**: Standard_D4s_v5 (4 vCPU, 16GB RAM) - 支援 2-3 個並行 runners
- **進階配置**: Standard_D8s_v5 (8 vCPU, 32GB RAM) - 支援 4-6 個並行 runners
- **💰 Spot VM 成本**: 使用 Spot VM 可節省 **70-90%** 成本（見下方詳細說明）

### 🇹🇼 台灣用戶區域選擇建議

對於台灣用戶，建議使用以下區域（按優先順序）：

| 區域 | 位置 | 延遲 | Spot 穩定性 | 價格 | 推薦度 |
|------|------|------|-------------|------|--------|
| **eastasia** | 🇭🇰 香港 | ~25ms | 極佳 | 標準 | ⭐⭐⭐⭐⭐ **首選** |
| **southeastasia** | 🇸🇬 新加坡 | ~50ms | 極佳 | 標準 | ⭐⭐⭐⭐⭐ |
| **japaneast** | 🇯🇵 東京 | ~45ms | 佳 | 略高 | ⭐⭐⭐⭐ |
| **koreacentral** | 🇰🇷 首爾 | ~40ms | 佳 | 標準 | ⭐⭐⭐⭐ |

**推薦使用 `eastasia` (香港) 的理由：**
- ✅ 延遲最低（SSH 連線、管理操作更快速）
- ✅ Spot VM 供應充足，回收率 < 3%
- ✅ 價格合理，與其他亞洲區域相近
- ✅ 網路頻寬充足，到 GitHub.com 連線穩定

> 💡 **注意**：GitHub Self-hosted Runner 主要在本地執行代碼，對延遲不太敏感。
> 主要考量是 SSH 管理的便利性和 Spot VM 的穩定性。

## 目錄結構

```
.
├── README.md                    # 專案說明文件
├── main.tf                      # Terraform 主配置檔案
├── variables.tf                 # Terraform 變數定義
├── outputs.tf                   # Terraform 輸出定義
├── terraform.tfvars.example     # 變數範例檔案
├── scripts/
│   ├── cloud-init.yml          # VM 初始化配置
│   └── setup-runners.sh        # GitHub Runners 安裝腳本
└── .gitignore                   # Git 忽略檔案
```

## 使用步驟

### 1. 準備工作

確保已安裝以下工具：
- [Terraform](https://www.terraform.io/downloads.html) (>= 1.0)
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)
- GitHub Personal Access Token (需要 `repo` 和 `admin:org` 權限)

### 2. Azure 登入

```bash
az login
az account set --subscription "<your-subscription-id>"
```

### 3. 配置變數

複製範例檔案並填入您的設定：

```bash
cp terraform.tfvars.example terraform.tfvars
```

編輯 `terraform.tfvars`，填入以下資訊：
- `github_token`: 您的 GitHub Personal Access Token
- `github_repo_url`: 您的 GitHub repository URL
- `runner_count`: 想要建立的 runner 數量
- `admin_username`: VM 管理員帳號
- `ssh_public_key`: SSH 公鑰

### 4. 部署基礎設施

```bash
# 初始化 Terraform
terraform init

# 檢視執行計畫
terraform plan

# 部署資源
terraform apply
```

### 5. 連線到 VM

部署完成後，使用輸出的 IP 位址連線：

```bash
ssh <admin_username>@<vm_public_ip>
```

### 6. 檢查 Runners 狀態

```bash
# 檢查所有 runner 服務狀態
sudo systemctl status actions-runner-*

# 檢查特定 runner
sudo systemctl status actions-runner-1.service

# 檢視 runner 日誌
sudo journalctl -u actions-runner-1.service -f
```

## 環境配置詳情

### 已安裝軟體

- **作業系統**: Ubuntu 22.04 LTS
- **.NET SDK**: 最新 LTS 版本
- **Node.js**: 版本 20.x, 22.x, 24.x (透過 nvm 管理)
- **其他工具**: Git, curl, wget, jq, build-essential

### Runner 配置

每個 runner 安裝在獨立目錄：
- `/opt/actions-runner-1`
- `/opt/actions-runner-2`
- `/opt/actions-runner-N`

每個 runner 都有對應的 systemd 服務：
- `actions-runner-1.service`
- `actions-runner-2.service`
- `actions-runner-N.service`

## 維護操作

### 增加或減少 Runners

修改 `terraform.tfvars` 中的 `runner_count`，然後執行：

```bash
terraform apply
```

### 更新軟體版本

修改 `scripts/cloud-init.yml` 中的版本號，然後重新部署 VM。

### 移除資源

```bash
terraform destroy
```

## 安全性建議

1. **GitHub Token 管理**
   - 使用最小權限原則的 PAT
   - 定期輪換 token
   - 考慮使用 Azure Key Vault 儲存敏感資訊

2. **網路安全**
   - NSG 預設僅開放 SSH (port 22)
   - 建議限制 SSH 來源 IP 範圍
   - 考慮使用 Azure Bastion 進行更安全的連線

3. **VM 安全**
   - 定期更新系統套件
   - 啟用自動安全更新
   - 考慮使用 Azure Monitor 進行監控

## 💰 成本估算與優化

### 標準 VM 成本（Standard_D4s_v5）
- VM 執行成本：約 $140-180 USD/月 (Pay-as-you-go)
- 儲存成本：約 $5-10 USD/月
- 網路成本：視流量而定
- **總計**：約 **$145-190 USD/月**

### 🌟 Spot VM 成本優化（強烈建議！）

使用 Spot VM 可以大幅降低成本：

| VM 規格 | 標準價格 | Spot 價格 (平均) | 節省金額 | 節省比例 |
|---------|----------|------------------|----------|----------|
| Standard_D4s_v5 | $145-190/月 | **$15-30/月** | $130-160/月 | **~85%** |
| Standard_D8s_v5 | $290-380/月 | **$30-60/月** | $260-320/月 | **~85%** |

#### Spot VM 最佳實踐（降低被回收風險）

1. **設定 `max_bid_price = -1`**（強烈建議！）
   ```hcl
   enable_spot_vm = true
   spot_max_bid_price = -1  # 願意支付最高到隨需價格
   ```
   - ✅ 只有在容量不足時才會被回收（而非價格因素）
   - ✅ 實際付費仍是當前 Spot 價格（70-90% 折扣）
   - ✅ 大幅降低被回收風險

2. **選擇較新世代的 VM 規格**
   - ✅ 推薦：Dsv5, Dasv5 系列（供應充足）
   - ⚠️ 避免：較舊的 Dv3, Dv4 系列

3. **選擇多個可用區域備援**
   - 可以在不同區域部署多個 Spot VM
   - 降低單一區域容量不足的風險

4. **設定 `eviction_policy = "Deallocate"`**
   ```hcl
   spot_eviction_policy = "Deallocate"  # 保留配置，快速恢復
   ```
   - ✅ 被回收時保留 VM 配置和磁碟
   - ✅ 容量恢復後可快速重新啟動
   - ⚠️ 需支付少量磁碟儲存費用

#### Spot VM 回收率實際數據

根據 Azure 統計：
- **使用 max_bid_price = -1**：回收率 < 5%（主要因容量不足）
- **Dsv5/Dasv5 系列**：回收率 < 3%（供應充足）
- **CI/CD Runner 使用場景**：非常適合使用 Spot VM

#### 何時不適合使用 Spot VM

❌ 需要 24/7 絕對穩定運行的生產環境  
❌ 無法容忍任何中斷的關鍵服務  
✅ CI/CD Runners（任務可重試）  
✅ 開發測試環境  
✅ 批次處理任務

### 其他成本優化選項

1. **Reserved Instances**（需長期使用）
   - 1 年期：節省 ~40%
   - 3 年期：節省 ~60%
   - ⚠️ 需預付費用，適合長期穩定的工作負載

2. **Azure Hybrid Benefit**
   - 如果有現有的 Windows Server 或 SQL Server 授權
   - 可節省額外 40% 成本

## 疑難排解

### Runner 無法啟動

```bash
# 檢查服務狀態
sudo systemctl status actions-runner-1.service

# 檢視詳細日誌
sudo journalctl -u actions-runner-1.service -n 100

# 手動測試 runner
cd /opt/actions-runner-1
sudo -u github-runner ./run.sh
```

### Node.js 版本切換

```bash
# 查看已安裝版本
nvm list

# 切換版本
nvm use 20  # 或 22, 24

# 設定預設版本
nvm alias default 20
```

## 進階配置

### 自訂 Runner Labels

修改 `scripts/setup-runners.sh` 中的 runner 註冊命令，添加 `--labels` 參數。

### 整合 Azure Monitor

在 `main.tf` 中添加 Azure Monitor 擴展，參考 [Azure Monitor 文件](https://docs.microsoft.com/azure/azure-monitor/)。

## 授權

MIT License

## 參考資料

- [GitHub Self-hosted Runners 文件](https://docs.github.com/actions/hosting-your-own-runners)
- [Terraform Azure Provider 文件](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure VM 定價](https://azure.microsoft.com/pricing/details/virtual-machines/linux/)
