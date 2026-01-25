# SSH Key 完整使用指南

> 📂 **路徑說明**: 本文件說明如何為 VM Runner 設定 SSH Key。
> - Terraform 設定檔位於：`src/vm-runner/`
> - 備份腳本位於：`src/common-scripts/`

## 📚 什麼是 SSH Key？

SSH Key 是一對加密金鑰，用於安全地連線到遠端伺服器：

```
SSH Key Pair（金鑰對）
├── 私鑰 (Private Key)  → id_rsa         ⚠️ 絕對保密，像密碼一樣
└── 公鑰 (Public Key)   → id_rsa.pub     ✅ 可以公開，放在伺服器上
```

**運作原理**：
1. 公鑰放在伺服器上（Azure VM）
2. 私鑰保存在您的電腦上
3. 連線時，伺服器用公鑰驗證您持有對應的私鑰
4. 無需密碼即可安全登入

## 🔐 Step 1: 生成 SSH Key

### 在 PowerShell 中執行：

```powershell
# 1. 開啟 PowerShell（以一般使用者身份即可）

# 2. 建立 .ssh 目錄（如果不存在）
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.ssh"

# 3. 生成 SSH key pair
ssh-keygen -t rsa -b 4096 -C "your_email@example.com" -f "$env:USERPROFILE\.ssh\id_rsa"
```

### 執行過程中的提示：

```
Generating public/private rsa key pair.
Enter passphrase (empty for no passphrase): 
```

**🔒 建議輸入密碼（passphrase）保護私鑰：**
- 如果私鑰被盜，還需要密碼才能使用
- 輸入時不會顯示任何字元（這是正常的）
- 記住這個密碼！

```
Enter same passphrase again:
```

再次輸入相同密碼確認。

### 完成後會顯示：

```
Your identification has been saved in C:\Users\tzyu\.ssh\id_rsa
Your public key has been saved in C:\Users\tzyu\.ssh\id_rsa.pub
The key fingerprint is:
SHA256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx your_email@example.com
```

## 📂 Step 2: 檢查生成的檔案

```powershell
# 列出 .ssh 目錄的檔案
Get-ChildItem "$env:USERPROFILE\.ssh"
```

您應該會看到：

```
Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
-a----        2026/1/23   下午 02:30           3381 id_rsa          ⚠️ 私鑰
-a----        2026/1/23   下午 02:30            742 id_rsa.pub      ✅ 公鑰
```

### 查看公鑰內容：

```powershell
# 顯示公鑰（這個要放到 Terraform 配置中）
Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub"
```

輸出範例：
```
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx...很長的字串...xxxxx your_email@example.com
```

## 💾 Step 3: 備份到 OneDrive

### 方案 A: 手動備份（推薦新手）

```powershell
# 1. 建立 OneDrive 備份目錄
$BackupPath = "$env:OneDrive\SSH-Keys-Backup"
New-Item -ItemType Directory -Force -Path $BackupPath

# 2. 複製金鑰到 OneDrive
Copy-Item "$env:USERPROFILE\.ssh\id_rsa" -Destination "$BackupPath\id_rsa"
Copy-Item "$env:USERPROFILE\.ssh\id_rsa.pub" -Destination "$BackupPath\id_rsa.pub"

# 3. 建立說明檔案
@"
SSH Key 備份
建立日期: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

檔案說明:
- id_rsa      → 私鑰（絕對保密！）
- id_rsa.pub  → 公鑰（可以公開）

使用方式:
1. 在新電腦上複製這兩個檔案到 C:\Users\<你的使用者名稱>\.ssh\
2. 設定私鑰權限（見下方指令）
3. 即可使用

重要提醒:
⚠️ 私鑰 (id_rsa) 不要分享給任何人
⚠️ 不要上傳到 GitHub、Email 等公開位置
⚠️ 定期更新備份
"@ | Out-File -FilePath "$BackupPath\README.txt" -Encoding UTF8

# 4. 確認備份
Write-Host "✅ 備份完成！" -ForegroundColor Green
Write-Host "備份位置: $BackupPath" -ForegroundColor Cyan
explorer $BackupPath
```

### 方案 B: 建立自動備份腳本

建立一個 PowerShell 腳本以便日後更新：

```powershell
# 建立備份腳本
$ScriptContent = @'
# SSH Key 備份腳本
$SourcePath = "$env:USERPROFILE\.ssh"
$BackupPath = "$env:OneDrive\SSH-Keys-Backup"
$BackupDate = Get-Date -Format "yyyy-MM-dd_HHmmss"

# 建立帶日期的備份
$DateBackupPath = "$BackupPath\backup_$BackupDate"
New-Item -ItemType Directory -Force -Path $DateBackupPath | Out-Null

# 複製檔案
Copy-Item "$SourcePath\id_rsa" -Destination "$DateBackupPath\id_rsa"
Copy-Item "$SourcePath\id_rsa.pub" -Destination "$DateBackupPath\id_rsa.pub"

# 也保留最新版本在根目錄
Copy-Item "$SourcePath\id_rsa" -Destination "$BackupPath\id_rsa" -Force
Copy-Item "$SourcePath\id_rsa.pub" -Destination "$BackupPath\id_rsa.pub" -Force

Write-Host "✅ SSH Key 已備份到: $DateBackupPath" -ForegroundColor Green
'@

$ScriptPath = "$env:OneDrive\SSH-Keys-Backup\Backup-SSHKey.ps1"
New-Item -ItemType Directory -Force -Path "$env:OneDrive\SSH-Keys-Backup" | Out-Null
$ScriptContent | Out-File -FilePath $ScriptPath -Encoding UTF8

Write-Host "✅ 備份腳本已建立: $ScriptPath" -ForegroundColor Green
Write-Host "之後執行此腳本即可更新備份" -ForegroundColor Cyan
```

## 🔄 Step 4: 在其他電腦上使用備份的 Key

### 在新電腦上還原 SSH Key：

```powershell
# 1. 確認 OneDrive 已同步

# 2. 建立 .ssh 目錄
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.ssh"

# 3. 從 OneDrive 複製金鑰
Copy-Item "$env:OneDrive\SSH-Keys-Backup\id_rsa" -Destination "$env:USERPROFILE\.ssh\id_rsa"
Copy-Item "$env:OneDrive\SSH-Keys-Backup\id_rsa.pub" -Destination "$env:USERPROFILE\.ssh\id_rsa.pub"

# 4. 設定私鑰檔案權限（重要！）
# Windows 需要移除其他使用者的存取權限
icacls "$env:USERPROFILE\.ssh\id_rsa" /inheritance:r
icacls "$env:USERPROFILE\.ssh\id_rsa" /grant:r "$env:USERNAME:(R)"

# 5. 驗證權限
icacls "$env:USERPROFILE\.ssh\id_rsa"

Write-Host "✅ SSH Key 已還原！" -ForegroundColor Green
```

## 🚀 Step 5: 使用 SSH Key 連線到 Azure VM

### 測試連線：

```powershell
# 格式: ssh <使用者名稱>@<VM IP 位址>
ssh azureuser@20.x.x.x

# 如果設定了 passphrase，會要求輸入
Enter passphrase for key 'C:\Users\tzyu\.ssh\id_rsa':
```

### 第一次連線的提示：

```
The authenticity of host '20.x.x.x (20.x.x.x)' can't be established.
ECDSA key fingerprint is SHA256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

輸入 `yes` 並按 Enter。

## 📝 Step 6: 將公鑰加入 Terraform 配置

```powershell
# 1. 複製公鑰內容到剪貼簿
Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub" | Set-Clipboard

Write-Host "✅ 公鑰已複製到剪貼簿！" -ForegroundColor Green
Write-Host "現在可以貼到 terraform.tfvars 中" -ForegroundColor Cyan
```

### 2. 編輯 terraform.tfvars：

```powershell
# 進入 VM Runner 目錄
cd src/vm-runner
```

```hcl
# src/vm-runner/terraform.tfvars

# 貼上剛才複製的公鑰（整行，包含 ssh-rsa 開頭和 email 結尾）
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDxxxxxx...很長的字串...xxxxx your_email@example.com"
```

## 🔐 安全性最佳實踐

### ✅ 應該做的：

1. **使用 passphrase 保護私鑰**
   - 即使私鑰被盜，沒有密碼也無法使用

2. **定期備份**
   ```powershell
   # 執行備份腳本
   & "$env:OneDrive\SSH-Keys-Backup\Backup-SSHKey.ps1"
   ```

3. **設定正確的檔案權限**
   - 私鑰只有您能讀取
   - 其他使用者不應有任何權限

4. **為不同用途使用不同的 key**
   ```powershell
   # 可以建立多個 key
   ssh-keygen -t rsa -b 4096 -C "work@company.com" -f "$env:USERPROFILE\.ssh\id_rsa_work"
   ssh-keygen -t rsa -b 4096 -C "personal@email.com" -f "$env:USERPROFILE\.ssh\id_rsa_personal"
   ```

### ❌ 不應該做的：

1. **❌ 不要分享私鑰**
   - 私鑰就像密碼，只屬於您

2. **❌ 不要將私鑰上傳到 GitHub**
   - 公鑰可以，私鑰絕對不行

3. **❌ 不要用 Email 傳送私鑰**
   - Email 不安全

4. **❌ 不要在公共電腦上使用您的私鑰**
   - 可能被竊取

## 🛠️ 常見問題排解

### Q1: 忘記 passphrase 怎麼辦？

**答**：無法復原，必須重新生成新的 key pair。這就是為什麼要記住 passphrase！

### Q2: 可以不設定 passphrase 嗎？

**答**：可以，但不建議。生成時直接按 Enter 跳過即可。

### Q3: 如何查看我的公鑰指紋（fingerprint）？

```powershell
ssh-keygen -lf "$env:USERPROFILE\.ssh\id_rsa.pub"
```

### Q4: OneDrive 備份安全嗎？

**答**：
- ✅ 公鑰備份完全沒問題
- ⚠️ 私鑰備份需注意：
  - 確保 OneDrive 帳號有強密碼和 2FA
  - 最好使用 passphrase 保護私鑰
  - 考慮加密整個備份資料夾

### 加密 OneDrive 備份資料夾（進階）：

```powershell
# 使用 Windows EFS 加密備份資料夾
$BackupPath = "$env:OneDrive\SSH-Keys-Backup"
(Get-Item $BackupPath).Encrypt()

Write-Host "✅ 備份資料夾已加密！" -ForegroundColor Green
Write-Host "只有您的 Windows 帳號能解密" -ForegroundColor Cyan
```

### Q5: SSH 連線時出現 "Permission denied"

**檢查清單**：
1. 公鑰是否正確複製到 terraform.tfvars？
2. 私鑰權限是否正確？
3. 是否使用正確的使用者名稱？

```powershell
# 重新設定私鑰權限
icacls "$env:USERPROFILE\.ssh\id_rsa" /inheritance:r
icacls "$env:USERPROFILE\.ssh\id_rsa" /grant:r "$env:USERNAME:(R)"
```

## 📋 完整檢查清單

部署 Azure VM 前：

- [ ] 已生成 SSH key pair
- [ ] 已設定 passphrase（建議）
- [ ] 已備份到 OneDrive
- [ ] 已複製公鑰到 terraform.tfvars
- [ ] 已測試公鑰內容正確（以 `ssh-rsa` 開頭）
- [ ] 已設定私鑰正確權限
- [ ] 已建立備份腳本（可選）

## 🎯 快速參考指令

```powershell
# 生成新 key
ssh-keygen -t rsa -b 4096 -C "your_email@example.com" -f "$env:USERPROFILE\.ssh\id_rsa"

# 查看公鑰
Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub"

# 複製公鑰到剪貼簿
Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub" | Set-Clipboard

# 備份到 OneDrive
Copy-Item "$env:USERPROFILE\.ssh\*" -Destination "$env:OneDrive\SSH-Keys-Backup\" -Force

# 從 OneDrive 還原
Copy-Item "$env:OneDrive\SSH-Keys-Backup\id_rsa*" -Destination "$env:USERPROFILE\.ssh\" -Force

# 設定權限
icacls "$env:USERPROFILE\.ssh\id_rsa" /inheritance:r
icacls "$env:USERPROFILE\.ssh\id_rsa" /grant:r "$env:USERNAME:(R)"

# SSH 連線
ssh azureuser@<VM-IP>

# 查看 SSH key 指紋
ssh-keygen -lf "$env:USERPROFILE\.ssh\id_rsa.pub"
```

## 🎓 下一步

完成 SSH key 設定後：

1. ✅ 將公鑰填入 `src/vm-runner/terraform.tfvars` 的 `ssh_public_key` 參數
2. ✅ 進入 `src/vm-runner` 目錄，執行 `terraform apply` 部署 VM
3. ✅ 使用 `ssh azureuser@<VM-IP>` 連線測試
4. ✅ 定期執行備份腳本

---

**恭喜！** 🎉 您現在已經掌握 SSH key 的使用和管理！
