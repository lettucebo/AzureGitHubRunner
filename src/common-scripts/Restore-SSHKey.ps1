# SSH Key 還原腳本
# 用途: 從 OneDrive 還原 SSH key 到新電腦

$BackupPath = "$env:OneDrive\Recovery\SSHKeyBackup"
$DestPath = "$env:USERPROFILE\.ssh"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SSH Key 還原工具" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 檢查 OneDrive 備份是否存在
if (-not (Test-Path "$BackupPath\id_rsa")) {
    Write-Host "❌ 錯誤: 找不到 OneDrive 備份!" -ForegroundColor Red
    Write-Host ""
    Write-Host "請確認:" -ForegroundColor Yellow
    Write-Host "1. OneDrive 已安裝並登入" -ForegroundColor Yellow
    Write-Host "2. OneDrive 已完成同步" -ForegroundColor Yellow
    Write-Host "3. 備份資料夾存在: $BackupPath" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# 檢查是否已有 SSH key
if (Test-Path "$DestPath\id_rsa") {
    Write-Host "⚠️  警告: 此電腦已存在 SSH key!" -ForegroundColor Yellow
    Write-Host "位置: $DestPath\id_rsa" -ForegroundColor Yellow
    Write-Host ""
    $response = Read-Host "是否要覆蓋現有的 SSH key? (y/N)"
    if ($response -ne 'y' -and $response -ne 'Y') {
        Write-Host "❌ 取消還原" -ForegroundColor Red
        exit 0
    }
    Write-Host ""
}

# 建立 .ssh 目錄
Write-Host "📁 建立 .ssh 目錄..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $DestPath | Out-Null

# 複製檔案
Write-Host "📋 從 OneDrive 還原 SSH key..." -ForegroundColor Cyan

try {
    Copy-Item "$BackupPath\id_rsa" -Destination "$DestPath\id_rsa" -Force
    Copy-Item "$BackupPath\id_rsa.pub" -Destination "$DestPath\id_rsa.pub" -Force
    
    Write-Host "✅ 檔案複製完成" -ForegroundColor Green
} catch {
    Write-Host "❌ 還原失敗: $_" -ForegroundColor Red
    exit 1
}

# 設定私鑰權限
Write-Host "🔐 設定私鑰權限..." -ForegroundColor Cyan

try {
    # 移除繼承的權限
    icacls "$DestPath\id_rsa" /inheritance:r | Out-Null
    # 只授予當前使用者讀取權限
    icacls "$DestPath\id_rsa" /grant:r "${env:USERNAME}:(R)" | Out-Null
    
    Write-Host "✅ 權限設定完成" -ForegroundColor Green
} catch {
    Write-Host "⚠️  權限設定可能失敗，但可以手動修正" -ForegroundColor Yellow
}

# 驗證
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  還原摘要" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if (Test-Path "$DestPath\id_rsa" -and Test-Path "$DestPath\id_rsa.pub") {
    Write-Host "✅ 還原成功!" -ForegroundColor Green
    Write-Host ""
    Write-Host "還原的檔案:" -ForegroundColor Cyan
    Get-ChildItem $DestPath -Filter "id_rsa*" | ForEach-Object {
        Write-Host "  ✅ $_" -ForegroundColor Green
    }
    Write-Host ""
    
    # 顯示公鑰
    Write-Host "📋 您的 SSH 公鑰:" -ForegroundColor Cyan
    $PublicKey = Get-Content "$DestPath\id_rsa.pub"
    Write-Host $PublicKey -ForegroundColor White
    Write-Host ""
    
    # 複製公鑰到剪貼簿
    $PublicKey | Set-Clipboard
    Write-Host "✅ 公鑰已複製到剪貼簿！" -ForegroundColor Green
    Write-Host "可以直接貼到 terraform.tfvars 或 GitHub 設定中" -ForegroundColor Cyan
    Write-Host ""
    
    # 顯示權限
    Write-Host "🔐 私鑰權限:" -ForegroundColor Cyan
    icacls "$DestPath\id_rsa"
    Write-Host ""
    
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  測試 SSH 連線" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "要測試 SSH 連線，請執行:" -ForegroundColor Cyan
    Write-Host "ssh azureuser@<VM-IP-位址>" -ForegroundColor White
    Write-Host ""
    Write-Host "例如:" -ForegroundColor Cyan
    Write-Host "ssh azureuser@20.195.123.45" -ForegroundColor White
    Write-Host ""
    
} else {
    Write-Host "❌ 還原失敗" -ForegroundColor Red
}
