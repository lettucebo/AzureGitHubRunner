[繁體中文](SSH_SIMPLE_GUIDE_zh-tw.md) | **English**

---

# SSH Key Simple Guide

> 📂 **Path Description**: This document explains how to set up SSH Keys for VM Runner.
> - Terraform configuration files are located at: `src/vm-runner/`
> - Backup scripts are located at: `src/common-scripts/`

## 📦 Backup SSH Key (Manual, One-time)

SSH key is generated at: `C:\Users\tzyu\.ssh\`

**Just copy these two files to OneDrive:**

```powershell
# Create .ssh folder in OneDrive
New-Item -ItemType Directory -Force -Path "$env:OneDrive\.ssh"

# Copy files to OneDrive (manual backup)
Copy-Item "$env:USERPROFILE\.ssh\id_rsa" -Destination "$env:OneDrive\.ssh\id_rsa" -Force
Copy-Item "$env:USERPROFILE\.ssh\id_rsa.pub" -Destination "$env:OneDrive\.ssh\id_rsa.pub" -Force

Write-Host "✅ Backed up to: $env:OneDrive\.ssh" -ForegroundColor Green
explorer "$env:OneDrive\.ssh"
```

Done! Your SSH key is now safely backed up on OneDrive.

---

## 💻 Import SSH Key on a New Computer

**Just run one script:**

```powershell
# Execute from project root directory
.\src\common-scripts\Import-SSHKey.ps1
```

That's it!

---

## 📋 Using the Public Key (Deploy Azure VM)

### Method 1: Automatically Copy to Clipboard

```powershell
Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub" | Set-Clipboard
```

Then paste it directly into the `ssh_public_key` field in `src/vm-runner/terraform.tfvars`.

### Method 2: View Directly

```powershell
Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub"
```

Copy the entire line (from `ssh-rsa` to the email at the end).

---

## 🔐 File Explanation

```
OneDrive\.ssh\
├── id_rsa      → Private key (⚠️ Keep Secret!)
└── id_rsa.pub  → Public key (✅ Can be public)
```

**Important**:
- Private key = Your password, don't share it
- Public key = Can be placed on servers

---

## ✅ It's That Simple!

1. **First Time**: Manually copy to OneDrive (commands above)
2. **New Computer**: Run `src/common-scripts/Import-SSHKey.ps1`
3. **Use**: Copy public key to `src/vm-runner/terraform.tfvars`

No complex backup process, everything is intuitive!
