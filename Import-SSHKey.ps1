# SSH Key 匯入腳本（從 OneDrive）
# 執行此腳本即可在新電腦上匯入 SSH key

# 從 OneDrive 複製檔案到 .ssh 目錄
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.ssh" | Out-Null
Copy-Item "$env:OneDrive\.ssh\id_rsa*" -Destination "$env:USERPROFILE\.ssh\" -Force

# 設定私鑰權限
icacls "$env:USERPROFILE\.ssh\id_rsa" /inheritance:r | Out-Null
icacls "$env:USERPROFILE\.ssh\id_rsa" /grant:r "${env:USERNAME}:(R)" | Out-Null

# 完成
Write-Host "✅ SSH Key 已匯入！" -ForegroundColor Green
Write-Host ""
Write-Host "你的公鑰:" -ForegroundColor Cyan
Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub"
Write-Host ""
Write-Host "公鑰已複製到剪貼簿，可直接貼到 terraform.tfvars" -ForegroundColor Yellow
Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub" | Set-Clipboard
