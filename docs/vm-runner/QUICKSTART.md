# Azure VM for GitHub Self-hosted Runners - 快速開始指南

> 📁 **原始碼位置**: `src/vm-runner/`
>
> 所有 Terraform 命令請在 `src/vm-runner/` 目錄下執行。

## 📋 前置需求

在開始之前，請確保您已經：

1. ✅ 安裝 [Terraform](https://www.terraform.io/downloads) (版本 >= 1.0)
2. ✅ 安裝 [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)
3. ✅ 擁有 Azure 訂閱帳號
4. ✅ 擁有 GitHub 帳號並準備好 Personal Access Token

## 🚀 快速開始（5 分鐘部署）

### 步驟 0: 進入專案目錄

```bash
cd src/vm-runner
```

### 步驟 1: 準備 SSH 金鑰

如果您還沒有 SSH 金鑰，請執行：

```bash
# 產生新的 SSH 金鑰
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"

# 檢視公鑰內容（稍後需要複製到 terraform.tfvars）
cat ~/.ssh/id_rsa.pub
```

### 步驟 2: 取得 GitHub Personal Access Token

1. 前往 GitHub: https://github.com/settings/tokens/new
2. 設定 Token 名稱（例如：Azure VM Runner Token）
3. 選擇權限：
   - ✅ `repo` (Full control of private repositories)
   - ✅ `admin:org` > `read:org` (Read org and team membership)
4. 點擊 "Generate token" 並**立即複製** Token（只會顯示一次！）

### 步驟 3: 登入 Azure

```bash
# 登入 Azure
az login

# 查看可用的訂閱
az account list --output table

# 設定要使用的訂閱
az account set --subscription "YOUR-SUBSCRIPTION-ID"
```

### 步驟 4: 配置 Terraform 變數

```bash
# 複製範例檔案
cp terraform.tfvars.example terraform.tfvars

# 編輯變數檔案（使用您喜歡的編輯器）
code terraform.tfvars  # 或使用 vim, nano 等
```

**必須修改的重要參數：**

```hcl
# 替換為您的 SSH 公鑰
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC..."

# 替換為您的 GitHub Token
github_token = "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# 替換為您的 GitHub Repository URL
github_repo_url = "https://github.com/your-username/your-repository"

# 選擇要建立的 Runner 數量（建議 2-3 個）
runner_count = 3
```

### 步驟 5: 部署！

```bash
# 初始化 Terraform
terraform init

# 檢視執行計畫（確認要建立的資源）
terraform plan

# 執行部署（輸入 'yes' 確認）
terraform apply
```

⏱️ **部署時間約 5-10 分鐘**

### 步驟 6: 驗證部署

部署完成後，您會看到輸出資訊：

```
Outputs:

public_ip_address = "20.x.x.x"
ssh_command = "ssh azureuser@20.x.x.x"
runner_count = 3
runner_services = [
  "actions-runner-1.service",
  "actions-runner-2.service",
  "actions-runner-3.service",
]
```

使用 SSH 連線到 VM：

```bash
ssh azureuser@<public_ip_address>
```

檢查 Runners 狀態：

```bash
# 檢查所有 runner 服務
sudo systemctl status actions-runner-*.service

# 檢視特定 runner 的日誌
sudo journalctl -u actions-runner-1.service -f
```

### 步驟 7: 在 GitHub 上驗證

1. 前往您的 GitHub Repository
2. 點擊 `Settings` > `Actions` > `Runners`
3. 您應該會看到 3 個 "azure-runner-1", "azure-runner-2", "azure-runner-3"，狀態為 **Idle** 🟢

## 🎯 測試 Runner

建立一個簡單的 GitHub Actions workflow 來測試：

```yaml
# .github/workflows/test-runner.yml
name: Test Self-hosted Runner

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  test-dotnet:
    runs-on: [self-hosted, linux, azure]
    steps:
      - uses: actions/checkout@v4
      
      - name: Check .NET version
        run: dotnet --version
      
      - name: Check Node.js versions
        run: |
          export NVM_DIR="$HOME/.nvm"
          [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
          nvm list
          
      - name: Test Docker
        run: docker --version

  test-parallel:
    runs-on: [self-hosted, linux, azure]
    strategy:
      matrix:
        node-version: [20, 22, 24]
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Node.js ${{ matrix.node-version }}
        run: |
          export NVM_DIR="$HOME/.nvm"
          [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
          nvm use ${{ matrix.node-version }}
          node --version
```

## 🔧 常見問題排解

### Q1: Runner 無法註冊到 GitHub

**檢查：**
```bash
# 查看 runner 日誌
sudo journalctl -u actions-runner-1.service -n 100

# 檢查 GitHub Token 權限
# 確保 Token 有 'repo' 和 'admin:org' 權限
```

### Q2: 無法 SSH 連線到 VM

**檢查：**
```bash
# 驗證 SSH 公鑰是否正確
cat ~/.ssh/id_rsa.pub

# 檢查 NSG 規則
az network nsg rule list --resource-group rg-github-runners --nsg-name gh-runner-nsg --output table
```

### Q3: Node.js 版本找不到

**解決方法：**
```bash
# SSH 到 VM 後，切換到 github-runner 使用者
sudo su - github-runner

# 檢查 nvm
nvm list

# 手動安裝缺少的版本
nvm install 24
```

## 📊 監控與維護

### 查看資源使用情況

```bash
# CPU 和記憶體使用
htop

# 磁碟使用
df -h

# 檢查 runner 工作目錄大小
du -sh /opt/actions-runner-*/_work
```

### 定期維護

```bash
# 更新系統套件
sudo apt update && sudo apt upgrade -y

# 清理 Docker 資源
docker system prune -af

# 清理舊的 runner 工作檔案
sudo find /opt/actions-runner-*/_work -type f -mtime +7 -delete
```

## 💰 成本優化建議

1. **使用 Reserved Instances**: 節省 40-60% 成本
2. **設定自動關機**: 非工作時間自動關閉 VM
3. **使用 Spot Instances**: 適合非關鍵性工作負載（可節省 70-90%）

## 🗑️ 清理資源

當不再需要時，執行：

```bash
# 刪除所有 Terraform 建立的資源
terraform destroy

# 輸入 'yes' 確認
```

## 📚 進階主題

- [自訂 Runner Labels](./docs/custom-labels.md)
- [整合 Azure Monitor](./docs/monitoring.md)
- [使用 Azure Key Vault 管理 Secrets](./docs/key-vault.md)
- [設定自動擴展](./docs/auto-scaling.md)

## 🤝 需要協助？

- 查看完整文檔：[README.md](README.md)
- GitHub Issues：[提交問題](https://github.com/your-repo/issues)
- Azure 支援：[Azure 文件](https://docs.microsoft.com/azure)

---

**恭喜！** 🎉 您已成功部署 GitHub Self-hosted Runners！
