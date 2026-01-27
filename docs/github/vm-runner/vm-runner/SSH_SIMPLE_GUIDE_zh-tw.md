**繁體中文** | [English](SSH_SIMPLE_GUIDE.md)

---

# SSH Key 簡易使用指南

> 📂 **路徑說明**: 本文件說明如何為 VM Runner 設定 SSH Key。
> - Terraform 設定檔位於:`src/vm-runner/`
> - 備份腳本位於:`src/common-scripts/`

## 📦 備份 SSH Key(手動,只做一次)

SSH key 已生成在:`C:\Users\tzyu\.ssh\`

**只需要複製這兩個檔案到 OneDrive:**

```powershell
# 在 OneDrive 建立 .ssh 資料夾
New-Item -ItemType Directory -Force -Path "$env:OneDrive\.ssh"

# 複製檔案到 OneDrive(手動備份)
Copy-Item "$env:USERPROFILE\.ssh\id_rsa" -Destination "$env:OneDrive\.ssh\id_rsa" -Force
Copy-Item "$env:USERPROFILE\.ssh\id_rsa.pub" -Destination "$env:OneDrive\.ssh\id_rsa.pub" -Force

Write-Host "✅ 已備份到: $env:OneDrive\.ssh" -ForegroundColor Green
explorer "$env:OneDrive\.ssh"
```

完成!您的 SSH key 現在已安全備份在 OneDrive。

---

## 💻 在新電腦上匯入 SSH Key

**只需執行一個腳本:**

```powershell
# 從專案根目錄執行
.\src\common-scripts\Import-SSHKey.ps1
```

就完成了!

---

## 📋 使用公鑰(部署 Azure VM)

### 方法 1: 自動複製到剪貼簿

```powershell
Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub" | Set-Clipboard
```

然後直接貼到 `src/vm-runner/terraform.tfvars` 的 `ssh_public_key` 欄位。

### 方法 2: 直接查看

```powershell
Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub"
```

複製整行內容(從 `ssh-rsa` 開頭到 email 結尾)。

---

## 🔐 檔案說明

```
OneDrive\.ssh\
├── id_rsa      → 私鑰(⚠️ 保密!)
└── id_rsa.pub  → 公鑰(✅ 可公開)
```

**重要**:
- 私鑰 = 你的密碼,不要分享
- 公鑰 = 可以放在伺服器上

---

## ✅ 就這麼簡單!

1. **第一次**:手動複製到 OneDrive(上面的指令)
2. **新電腦**:執行 `src/common-scripts/Import-SSHKey.ps1`
3. **使用**:複製公鑰到 `src/vm-runner/terraform.tfvars`

沒有複雜的備份流程,一切都很直覺!
