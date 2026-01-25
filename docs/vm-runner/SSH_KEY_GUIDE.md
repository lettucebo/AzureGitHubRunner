[繁體中文](SSH_KEY_GUIDE_zh-tw.md) | **English**

---

# Complete SSH Key Guide

> 📂 **Path Description**: This document explains how to set up SSH Keys for VM Runner.
> - Terraform configuration files are located at: `src/vm-runner/`
> - Backup scripts are located at: `src/common-scripts/`

## 📚 What is an SSH Key?

An SSH Key is a pair of cryptographic keys used to securely connect to remote servers:

```
SSH Key Pair
├── Private Key  → id_rsa         ⚠️ Keep Secret (like a password)
└── Public Key   → id_rsa.pub     ✅ Can be public (place on servers)
```

**How it works**:
1. Public key is placed on the server (Azure VM)
2. Private key is kept on your computer
3. When connecting, the server verifies you have the matching private key
4. Secure login without passwords

## 🔐 Step 1: Generate SSH Key

### Execute in PowerShell:

```powershell
# 1. Open PowerShell (regular user access is sufficient)

# 2. Create .ssh directory (if it doesn't exist)
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.ssh"

# 3. Generate SSH key pair
ssh-keygen -t rsa -b 4096 -C "your_email@example.com" -f "$env:USERPROFILE\.ssh\id_rsa"
```

### Prompts during execution:

```
Generating public/private rsa key pair.
Enter passphrase (empty for no passphrase): 
```

**🔒 Recommended to enter a passphrase to protect the private key:**
- If the private key is stolen, the passphrase is still required to use it
- No characters will be displayed when typing (this is normal)
- Remember this password!

```
Enter same passphrase again:
```

Enter the same passphrase again to confirm.

### Upon completion, you'll see:

```
Your identification has been saved in C:\Users\tzyu\.ssh\id_rsa
Your public key has been saved in C:\Users\tzyu\.ssh\id_rsa.pub
The key fingerprint is:
SHA256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx your_email@example.com
```

## 📂 Step 2: Check Generated Files

```powershell
# List files in .ssh directory
Get-ChildItem "$env:USERPROFILE\.ssh"
```

You should see:

```
Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
-a----        2026/1/23   PM 02:30           3381 id_rsa          ⚠️ Private Key
-a----        2026/1/23   PM 02:30            742 id_rsa.pub      ✅ Public Key
```

### View public key content:

```powershell
# Display public key (this goes into Terraform configuration)
Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub"
```

Example output:
```
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx...long string...xxxxx your_email@example.com
```

## 💾 Step 3: Backup to OneDrive

### Option A: Manual Backup (Recommended for beginners)

```powershell
# 1. Create OneDrive backup directory
$BackupPath = "$env:OneDrive\SSH-Keys-Backup"
New-Item -ItemType Directory -Force -Path $BackupPath

# 2. Copy keys to OneDrive
Copy-Item "$env:USERPROFILE\.ssh\id_rsa" -Destination "$BackupPath\id_rsa"
Copy-Item "$env:USERPROFILE\.ssh\id_rsa.pub" -Destination "$BackupPath\id_rsa.pub"

# 3. Create documentation file
@"
SSH Key Backup
Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

File descriptions:
- id_rsa      → Private key (Keep Secret!)
- id_rsa.pub  → Public key (Can be public)

How to use:
1. On a new computer, copy these two files to C:\Users\<your-username>\.ssh\
2. Set private key permissions (see commands below)
3. Ready to use

Important reminders:
⚠️ Private key (id_rsa) - Never share with anyone
⚠️ Don't upload to GitHub, email, or other public places
⚠️ Update backups regularly
"@ | Out-File -FilePath "$BackupPath\README.txt" -Encoding UTF8

# 4. Confirm backup
Write-Host "✅ Backup complete!" -ForegroundColor Green
Write-Host "Backup location: $BackupPath" -ForegroundColor Cyan
explorer $BackupPath
```

### Option B: Create Automated Backup Script

Create a PowerShell script for future updates:

```powershell
# Create backup script
$ScriptContent = @'
# SSH Key Backup Script
$SourcePath = "$env:USERPROFILE\.ssh"
$BackupPath = "$env:OneDrive\SSH-Keys-Backup"
$BackupDate = Get-Date -Format "yyyy-MM-dd_HHmmss"

# Create dated backup
$DateBackupPath = "$BackupPath\backup_$BackupDate"
New-Item -ItemType Directory -Force -Path $DateBackupPath | Out-Null

# Copy files
Copy-Item "$SourcePath\id_rsa" -Destination "$DateBackupPath\id_rsa"
Copy-Item "$SourcePath\id_rsa.pub" -Destination "$DateBackupPath\id_rsa.pub"

# Also keep latest version in root directory
Copy-Item "$SourcePath\id_rsa" -Destination "$BackupPath\id_rsa" -Force
Copy-Item "$SourcePath\id_rsa.pub" -Destination "$BackupPath\id_rsa.pub" -Force

Write-Host "✅ SSH Key backed up to: $DateBackupPath" -ForegroundColor Green
'@

$ScriptPath = "$env:OneDrive\SSH-Keys-Backup\Backup-SSHKey.ps1"
New-Item -ItemType Directory -Force -Path "$env:OneDrive\SSH-Keys-Backup" | Out-Null
$ScriptContent | Out-File -FilePath $ScriptPath -Encoding UTF8

Write-Host "✅ Backup script created: $ScriptPath" -ForegroundColor Green
Write-Host "Run this script later to update backups" -ForegroundColor Cyan
```

## 🔄 Step 4: Using Backed-up Keys on Another Computer

### Restore SSH Key on a new computer:

```powershell
# 1. Confirm OneDrive is synced

# 2. Create .ssh directory
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.ssh"

# 3. Copy keys from OneDrive
Copy-Item "$env:OneDrive\SSH-Keys-Backup\id_rsa" -Destination "$env:USERPROFILE\.ssh\id_rsa"
Copy-Item "$env:OneDrive\SSH-Keys-Backup\id_rsa.pub" -Destination "$env:USERPROFILE\.ssh\id_rsa.pub"

# 4. Set private key file permissions (Important!)
# Windows requires removing access permissions for other users
icacls "$env:USERPROFILE\.ssh\id_rsa" /inheritance:r
icacls "$env:USERPROFILE\.ssh\id_rsa" /grant:r "$env:USERNAME:(R)"

# 5. Verify permissions
icacls "$env:USERPROFILE\.ssh\id_rsa"

Write-Host "✅ SSH Key restored!" -ForegroundColor Green
```

## 🚀 Step 5: Connect to Azure VM Using SSH Key

### Test connection:

```powershell
# Format: ssh <username>@<VM IP address>
ssh azureuser@20.x.x.x

# If passphrase was set, you'll be prompted to enter it
Enter passphrase for key 'C:\Users\tzyu\.ssh\id_rsa':
```

### First connection prompt:

```
The authenticity of host '20.x.x.x (20.x.x.x)' can't be established.
ECDSA key fingerprint is SHA256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

Type `yes` and press Enter.

## 📝 Step 6: Add Public Key to Terraform Configuration

```powershell
# 1. Copy public key content to clipboard
Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub" | Set-Clipboard

Write-Host "✅ Public key copied to clipboard!" -ForegroundColor Green
Write-Host "You can now paste it into terraform.tfvars" -ForegroundColor Cyan
```

### 2. Edit terraform.tfvars:

```powershell
# Navigate to VM Runner directory
cd src/vm-runner
```

```hcl
# src/vm-runner/terraform.tfvars

# Paste the public key you just copied (entire line, from ssh-rsa to email)
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDxxxxxx...long string...xxxxx your_email@example.com"
```

## 🔐 Security Best Practices

### ✅ What you SHOULD do:

1. **Use passphrase to protect private key**
   - Even if the private key is stolen, it can't be used without the passphrase

2. **Regular backups**
   ```powershell
   # Run backup script
   & "$env:OneDrive\SSH-Keys-Backup\Backup-SSHKey.ps1"
   ```

3. **Set correct file permissions**
   - Only you should be able to read the private key
   - Other users should have no permissions

4. **Use different keys for different purposes**
   ```powershell
   # You can create multiple keys
   ssh-keygen -t rsa -b 4096 -C "work@company.com" -f "$env:USERPROFILE\.ssh\id_rsa_work"
   ssh-keygen -t rsa -b 4096 -C "personal@email.com" -f "$env:USERPROFILE\.ssh\id_rsa_personal"
   ```

### ❌ What you should NOT do:

1. **❌ Don't share the private key**
   - The private key is like a password, it belongs only to you

2. **❌ Don't upload private key to GitHub**
   - Public key is fine, private key absolutely not

3. **❌ Don't send private key via Email**
   - Email is not secure

4. **❌ Don't use your private key on public computers**
   - It could be stolen

## 🛠️ Troubleshooting

### Q1: Forgot the passphrase, what should I do?

**Answer**: Cannot be recovered, you must generate a new key pair. That's why it's important to remember your passphrase!

### Q2: Can I skip setting a passphrase?

**Answer**: Yes, but not recommended. Just press Enter when prompted during generation.

### Q3: How do I view my public key fingerprint?

```powershell
ssh-keygen -lf "$env:USERPROFILE\.ssh\id_rsa.pub"
```

### Q4: Is OneDrive backup secure?

**Answer**:
- ✅ Public key backup is completely fine
- ⚠️ Private key backup requires attention:
  - Ensure OneDrive account has strong password and 2FA
  - Best to use passphrase to protect private key
  - Consider encrypting the entire backup folder

### Encrypt OneDrive backup folder (Advanced):

```powershell
# Encrypt backup folder using Windows EFS
$BackupPath = "$env:OneDrive\SSH-Keys-Backup"
(Get-Item $BackupPath).Encrypt()

Write-Host "✅ Backup folder encrypted!" -ForegroundColor Green
Write-Host "Only your Windows account can decrypt" -ForegroundColor Cyan
```

### Q5: Getting "Permission denied" when connecting via SSH

**Checklist**:
1. Is the public key correctly copied to terraform.tfvars?
2. Are the private key permissions correct?
3. Are you using the correct username?

```powershell
# Reset private key permissions
icacls "$env:USERPROFILE\.ssh\id_rsa" /inheritance:r
icacls "$env:USERPROFILE\.ssh\id_rsa" /grant:r "$env:USERNAME:(R)"
```

## 📋 Complete Checklist

Before deploying Azure VM:

- [ ] Generated SSH key pair
- [ ] Set passphrase (recommended)
- [ ] Backed up to OneDrive
- [ ] Copied public key to terraform.tfvars
- [ ] Verified public key content is correct (starts with `ssh-rsa`)
- [ ] Set correct private key permissions
- [ ] Created backup script (optional)

## 🎯 Quick Reference Commands

```powershell
# Generate new key
ssh-keygen -t rsa -b 4096 -C "your_email@example.com" -f "$env:USERPROFILE\.ssh\id_rsa"

# View public key
Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub"

# Copy public key to clipboard
Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub" | Set-Clipboard

# Backup to OneDrive
Copy-Item "$env:USERPROFILE\.ssh\*" -Destination "$env:OneDrive\SSH-Keys-Backup\" -Force

# Restore from OneDrive
Copy-Item "$env:OneDrive\SSH-Keys-Backup\id_rsa*" -Destination "$env:USERPROFILE\.ssh\" -Force

# Set permissions
icacls "$env:USERPROFILE\.ssh\id_rsa" /inheritance:r
icacls "$env:USERPROFILE\.ssh\id_rsa" /grant:r "$env:USERNAME:(R)"

# SSH connect
ssh azureuser@<VM-IP>

# View SSH key fingerprint
ssh-keygen -lf "$env:USERPROFILE\.ssh\id_rsa.pub"
```

## 🎓 Next Steps

After completing SSH key setup:

1. ✅ Add public key to `ssh_public_key` parameter in `src/vm-runner/terraform.tfvars`
2. ✅ Navigate to `src/vm-runner` directory and run `terraform apply` to deploy VM
3. ✅ Test connection using `ssh azureuser@<VM-IP>`
4. ✅ Run backup script regularly

---

**Congratulations!** 🎉 You now master SSH key usage and management!
