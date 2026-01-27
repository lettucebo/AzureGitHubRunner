[繁體中文](SSH_QUICKSTART_zh-tw.md) | **English**

---

# SSH Key Quick Start Guide

> 📁 **Source Code Location**: `src/vm-runner/`

## 🚀 Complete SSH Key Setup in Three Steps

### Step 1: Generate SSH Key (First Time)

Open PowerShell and run:

```powershell
# Generate SSH key (remember to replace with your email)
ssh-keygen -t rsa -b 4096 -C "your_email@example.com" -f "$env:USERPROFILE\.ssh\id_rsa"
```

**During execution:**
1. You'll be asked twice for a passphrase (password)
   - ✅ **Recommended** to set a password to protect the private key
   - No characters will be displayed when typing (this is normal)
   - Or press Enter to skip (not recommended)

2. Success message will be displayed upon completion

### Step 2: Backup to OneDrive

Run the backup script from the project root directory:

```powershell
# Execute from project root directory
.\src\common-scripts\Backup-SSHKey.ps1
```

**The script automatically:**
- ✅ Copies SSH key to OneDrive
- ✅ Creates historical backup (with date)
- ✅ Generates documentation file
- ✅ Displays public key preview

### Step 3: Add Public Key to Terraform

```powershell
# Copy public key to clipboard
Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub" | Set-Clipboard
```

Then edit `src/vm-runner/terraform.tfvars` and paste the public key:

```hcl
# src/vm-runner/terraform.tfvars
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAA...paste the content you just copied... your_email@example.com"
```

✅ **Done!** You can now navigate to the `src/vm-runner` directory and run `terraform apply` to deploy the VM!

---

## 📱 Using on Another Computer (Restore Backup)

When you need to use the SSH key on a new computer:

```powershell
# Execute from project root directory
.\src\common-scripts\Restore-SSHKey.ps1
```

**The script automatically:**
- ✅ Copies SSH key from OneDrive
- ✅ Sets correct file permissions
- ✅ Copies public key to clipboard
- ✅ Displays test commands

---

## 🔄 Regular Backups

After updating your SSH key, run:

```powershell
# Execute from project root directory
.\src\common-scripts\Backup-SSHKey.ps1
```

It will automatically create a new historical backup without overwriting the old one.

---

## 📚 Complete Documentation

- **Detailed Tutorial**: [SSH_KEY_GUIDE.md](SSH_KEY_GUIDE.md)
- **Backup Script**: [Backup-SSHKey.ps1](../../src/common-scripts/Backup-SSHKey.ps1)
- **Restore Script**: [Restore-SSHKey.ps1](../../src/common-scripts/Restore-SSHKey.ps1)

---

## 🆘 Common Questions

**Q: I forgot to set a passphrase, what should I do?**  
A: Re-run Step 1 to generate a new key, it will overwrite the old one.

**Q: Is OneDrive backup secure?**  
A: Yes, as long as your OneDrive account has a strong password and two-factor authentication. For extra security, set a passphrase.

**Q: Can I use the same SSH key on multiple computers simultaneously?**  
A: Yes! Use the restore script to restore it on each computer.

**Q: How do I test if the SSH key is working properly?**  
A: After deploying the VM, run `ssh azureuser@<VM-IP>` to test the connection.

---

## ⚠️ Security Reminders

- ❌ **Do NOT** share your private key (id_rsa)
- ❌ **Do NOT** upload your private key to GitHub
- ❌ **Do NOT** send your private key via email
- ✅ **DO** backup regularly
- ✅ **DO** use passphrase protection
- ✅ **DO** ensure your OneDrive account is secure

---

**Ready to start?** Begin with Step 1! 🚀
