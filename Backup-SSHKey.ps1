# SSH Key 備份腳本
# 用途: 將 SSH key 備份到 OneDrive

$SourcePath = "$env:USERPROFILE\.ssh"
$BackupPath = "$env:OneDrive\SSH-Keys-Backup"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SSH Key 備份工具" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 檢查 SSH key 是否存在
if (-not (Test-Path "$SourcePath\id_rsa")) {
    Write-Host "❌ 錯誤: 找不到 SSH key!" -ForegroundColor Red
    Write-Host "請先生成 SSH key" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "執行以下指令生成:" -ForegroundColor Cyan
    Write-Host 'ssh-keygen -t rsa -b 4096 -C "your_email@example.com" -f "$env:USERPROFILE\.ssh\id_rsa"' -ForegroundColor White
    exit 1
}

# 檢查 OneDrive 是否存在
if (-not $env:OneDrive) {
    Write-Host "❌ 錯誤: 找不到 OneDrive!" -ForegroundColor Red
    Write-Host "請確認 OneDrive 已安裝並登入" -ForegroundColor Yellow
    exit 1
}

# 建立備份目錄
Write-Host "📁 建立備份目錄..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $BackupPath | Out-Null

# 建立帶日期的備份（保留歷史版本）
$BackupDate = Get-Date -Format "yyyy-MM-dd_HHmmss"
$DateBackupPath = "$BackupPath\backup_$BackupDate"
New-Item -ItemType Directory -Force -Path $DateBackupPath | Out-Null

# 複製檔案
Write-Host "📋 複製 SSH key 到 OneDrive..." -ForegroundColor Cyan

try {
    # 複製到歷史備份
    Copy-Item "$SourcePath\id_rsa" -Destination "$DateBackupPath\id_rsa" -Force
    Copy-Item "$SourcePath\id_rsa.pub" -Destination "$DateBackupPath\id_rsa.pub" -Force
    
    # 也保留最新版本在根目錄（方便快速還原）
    Copy-Item "$SourcePath\id_rsa" -Destination "$BackupPath\id_rsa" -Force
    Copy-Item "$SourcePath\id_rsa.pub" -Destination "$BackupPath\id_rsa.pub" -Force
    
    Write-Host "✅ 備份完成!" -ForegroundColor Green
} catch {
    Write-Host "❌ 備份失敗: $_" -ForegroundColor Red
    exit 1
}

# 建立說明檔案
$ReadmeContent = @"
SSH Key 備份
============

建立時間: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
電腦名稱: $env:COMPUTERNAME
使用者: $env:USERNAME

檔案說明
--------
- id_rsa      → 私鑰（⚠️ 絕對保密！）
- id_rsa.pub  → 公鑰（✅ 可以公開）

在新電腦上還原
--------------
1. 確保 OneDrive 已同步
2. 開啟 PowerShell 執行:

   # 建立 .ssh 目錄
   New-Item -ItemType Directory -Force -Path "`$env:USERPROFILE\.ssh"
   
   # 從 OneDrive 複製金鑰
   Copy-Item "`$env:OneDrive\SSH-Keys-Backup\id_rsa" -Destination "`$env:USERPROFILE\.ssh\id_rsa"
   Copy-Item "`$env:OneDrive\SSH-Keys-Backup\id_rsa.pub" -Destination "`$env:USERPROFILE\.ssh\id_rsa.pub"
   
   # 設定私鑰權限（重要！）
   icacls "`$env:USERPROFILE\.ssh\id_rsa" /inheritance:r
   icacls "`$env:USERPROFILE\.ssh\id_rsa" /grant:r "`$env:USERNAME:(R)"

3. 完成！現在可以使用 SSH 連線

安全提醒
--------
⚠️ 私鑰 (id_rsa) 不要分享給任何人
⚠️ 不要上傳到 GitHub、Email 等公開位置
⚠️ 定期更新備份
⚠️ 確保 OneDrive 帳號有強密碼和雙重驗證

歷史備份
--------
每次執行備份腳本會建立帶日期的備份資料夾（backup_yyyy-MM-dd_HHmmss）
可以保留多個版本以防萬一
"@

$ReadmeContent | Out-File -FilePath "$BackupPath\README.txt" -Encoding UTF8 -Force

# 顯示摘要
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  備份摘要" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "📂 最新備份: $BackupPath" -ForegroundColor White
Write-Host "📂 歷史備份: $DateBackupPath" -ForegroundColor White
Write-Host ""
Write-Host "備份的檔案:" -ForegroundColor Cyan
Get-ChildItem $BackupPath -Filter "id_rsa*" | ForEach-Object {
    Write-Host "  ✅ $_" -ForegroundColor Green
}
Write-Host ""

# 顯示公鑰預覽
Write-Host "📋 您的 SSH 公鑰 (前 80 字元):" -ForegroundColor Cyan
$PublicKey = Get-Content "$BackupPath\id_rsa.pub" -Raw
Write-Host $PublicKey.Substring(0, [Math]::Min(80, $PublicKey.Length)) -ForegroundColor White
Write-Host ""

# 詢問是否開啟備份資料夾
$response = Read-Host "要開啟備份資料夾嗎? (Y/n)"
if ($response -ne 'n' -and $response -ne 'N') {
    explorer $BackupPath
}

Write-Host ""
Write-Host "✅ 備份完成！您的 SSH key 已安全備份到 OneDrive" -ForegroundColor Green
Write-Host ""
Write-Host "下次更新備份時，再執行此腳本即可" -ForegroundColor Cyan
Write-Host "腳本位置: $PSCommandPath" -ForegroundColor White
