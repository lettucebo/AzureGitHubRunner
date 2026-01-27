[繁體中文](QUICKSTART_zh-tw.md) | **English**

---

# Azure VM for GitHub Self-hosted Runners - Quick Start Guide

> 📁 **Source Code Location**: `src/vm-runner/`
>
> Execute all Terraform commands in the `src/vm-runner/` directory.

## 📋 Prerequisites

Before you begin, make sure you have:

1. ✅ Installed [Terraform](https://www.terraform.io/downloads) (version >= 1.0)
2. ✅ Installed [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)
3. ✅ An Azure subscription account
4. ✅ A GitHub account with a Personal Access Token ready

## 🚀 Quick Start (5-minute deployment)

### Step 0: Navigate to the project directory

```bash
cd src/vm-runner
```

### Step 1: Prepare SSH Key

If you don't have an SSH key yet, run:

```bash
# Generate a new SSH key
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"

# View public key content (you'll need to copy this to terraform.tfvars)
cat ~/.ssh/id_rsa.pub
```

### Step 2: Get GitHub Personal Access Token

1. Go to GitHub: https://github.com/settings/tokens/new
2. Set Token name (e.g., Azure VM Runner Token)
3. Select permissions:
   - ✅ `repo` (Full control of private repositories)
   - ✅ `admin:org` > `read:org` (Read org and team membership)
4. Click "Generate token" and **copy it immediately** (only shown once!)

### Step 3: Login to Azure

```bash
# Login to Azure
az login

# View available subscriptions
az account list --output table

# Set the subscription to use
az account set --subscription "YOUR-SUBSCRIPTION-ID"
```

### Step 4: Configure Terraform Variables

```bash
# Copy the example file
cp terraform.tfvars.example terraform.tfvars

# Edit the variables file (use your preferred editor)
code terraform.tfvars  # or use vim, nano, etc.
```

**Important parameters you must modify:**

```hcl
# Replace with your SSH public key
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC..."

# Replace with your GitHub Token
github_token = "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# Replace with your GitHub Repository URL
github_repo_url = "https://github.com/your-username/your-repository"

# Choose the number of Runners to create (recommend 2-3)
runner_count = 3
```

### Step 5: Deploy!

```bash
# Initialize Terraform
terraform init

# View the execution plan (confirm resources to be created)
terraform plan

# Execute deployment (enter 'yes' to confirm)
terraform apply
```

⏱️ **Deployment takes approximately 5-10 minutes**

### Step 6: Verify Deployment

After deployment completes, you'll see output information:

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

Connect to the VM using SSH:

```bash
ssh azureuser@<public_ip_address>
```

Check Runner status:

```bash
# Check all runner services
sudo systemctl status actions-runner-*.service

# View logs for a specific runner
sudo journalctl -u actions-runner-1.service -f
```

### Step 7: Verify on GitHub

1. Go to your GitHub Repository
2. Click `Settings` > `Actions` > `Runners`
3. You should see 3 runners named "azure-runner-1", "azure-runner-2", "azure-runner-3" with status **Idle** 🟢

## 🎯 Test the Runners

Create a simple GitHub Actions workflow to test:

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

## 🔧 Troubleshooting

### Q1: Runner cannot register with GitHub

**Check:**
```bash
# View runner logs
sudo journalctl -u actions-runner-1.service -n 100

# Verify GitHub Token permissions
# Ensure Token has 'repo' and 'admin:org' permissions
```

### Q2: Cannot SSH connect to VM

**Check:**
```bash
# Verify SSH public key is correct
cat ~/.ssh/id_rsa.pub

# Check NSG rules
az network nsg rule list --resource-group rg-github-runners --nsg-name gh-runner-nsg --output table
```

### Q3: Node.js version not found

**Solution:**
```bash
# After SSH to VM, switch to github-runner user
sudo su - github-runner

# Check nvm
nvm list

# Manually install missing version
nvm install 24
```

## 📊 Monitoring and Maintenance

### View Resource Usage

```bash
# CPU and memory usage
htop

# Disk usage
df -h

# Check runner working directory size
du -sh /opt/actions-runner-*/_work
```

### Regular Maintenance

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Clean Docker resources
docker system prune -af

# Clean old runner work files
sudo find /opt/actions-runner-*/_work -type f -mtime +7 -delete
```

## 💰 Cost Optimization Recommendations

1. **Use Reserved Instances**: Save 40-60% on costs
2. **Set up auto-shutdown**: Automatically shut down VM during non-working hours
3. **Use Spot Instances**: Suitable for non-critical workloads (save 70-90%)

## 🗑️ Clean Up Resources

When no longer needed, run:

```bash
# Delete all resources created by Terraform
terraform destroy

# Enter 'yes' to confirm
```

## 📚 Advanced Topics

- [Custom Runner Labels](./docs/custom-labels.md)
- [Azure Monitor Integration](./docs/monitoring.md)
- [Managing Secrets with Azure Key Vault](./docs/key-vault.md)
- [Setting up Auto-scaling](./docs/auto-scaling.md)

## 🤝 Need Help?

- View full documentation: [README.md](README.md)
- GitHub Issues: [Submit an issue](https://github.com/your-repo/issues)
- Azure Support: [Azure Documentation](https://docs.microsoft.com/azure)

---

**Congratulations!** 🎉 You've successfully deployed GitHub Self-hosted Runners!
