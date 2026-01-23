# SSH Key 快速上手指南

## 🚀 三步驟完成 SSH Key 設定

### Step 1: 生成 SSH Key（第一次使用）

開啟 PowerShell，複製並執行：

```powershell
# 生成 SSH key（記得替換成您的 email）
ssh-keygen -t rsa -b 4096 -C "your_email@example.com" -f "$env:USERPROFILE\.ssh\id_rsa"
```

**執行過程：**
1. 會詢問您兩次 passphrase（密碼）
   - ✅ **建議設定**密碼保護私鑰
   - 輸入時不會顯示字元（正常現象）
   - 或直接按 Enter 跳過（不建議）

2. 完成後會顯示成功訊息

### Step 2: 備份到 OneDrive

在專案目錄執行備份腳本：

```powershell
cd "c:\Users\tzyu\Downloads\20260123"
.\Backup-SSHKey.ps1
```

**腳本會自動：**
- ✅ 複製 SSH key 到 OneDrive
- ✅ 建立歷史備份（帶日期）
- ✅ 產生說明檔案
- ✅ 顯示公鑰預覽

### Step 3: 將公鑰加入 Terraform

```powershell
# 複製公鑰到剪貼簿
Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub" | Set-Clipboard
```

然後編輯 `terraform.tfvars`，貼上公鑰：

```hcl
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAA...貼上剛才複製的內容... your_email@example.com"
```

✅ **完成！** 現在可以執行 `terraform apply` 部署 VM 了！

---

## 📱 在其他電腦上使用（還原備份）

當您在新電腦上需要使用 SSH key：

```powershell
cd "c:\Users\tzyu\Downloads\20260123"
.\Restore-SSHKey.ps1
```

**腳本會自動：**
- ✅ 從 OneDrive 複製 SSH key
- ✅ 設定正確的檔案權限
- ✅ 複製公鑰到剪貼簿
- ✅ 顯示測試指令

---

## 🔄 定期備份

每次更新 SSH key 後，執行：

```powershell
.\Backup-SSHKey.ps1
```

會自動建立新的歷史備份，不會覆蓋舊的。

---

## 📚 完整文檔

- **詳細教學**: [SSH_KEY_GUIDE.md](SSH_KEY_GUIDE.md)
- **備份腳本**: [Backup-SSHKey.ps1](Backup-SSHKey.ps1)
- **還原腳本**: [Restore-SSHKey.ps1](Restore-SSHKey.ps1)

---

## 🆘 常見問題

**Q: 我忘記設 passphrase 了，怎麼辦？**  
A: 重新執行 Step 1 生成新的 key，會覆蓋舊的。

**Q: OneDrive 備份安全嗎？**  
A: 只要您的 OneDrive 帳號有強密碼和雙重驗證就安全。更安全的方式是設定 passphrase。

**Q: 可以在多台電腦同時使用同一個 SSH key 嗎？**  
A: 可以！使用還原腳本在每台電腦上還原即可。

**Q: 如何測試 SSH key 是否正常？**  
A: 部署 VM 後，執行 `ssh azureuser@<VM-IP>` 測試連線。

---

## ⚠️ 安全提醒

- ❌ **不要**分享私鑰 (id_rsa)
- ❌ **不要**將私鑰上傳到 GitHub
- ❌ **不要**用 Email 傳送私鑰
- ✅ **要**定期備份
- ✅ **要**使用 passphrase 保護
- ✅ **要**確保 OneDrive 帳號安全

---

**準備好了嗎？** 從 Step 1 開始吧！🚀
