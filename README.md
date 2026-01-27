🌏 Language / 語言: [English](README.md) | [繁體中文](README_zh-tw.md)

---

# Azure Self-hosted Runner Solution

A complete solution for deploying Self-hosted Runners/Agents on Azure, supporting **GitHub Actions** and **Azure DevOps Pipelines**.

## 🎯 Supported Platforms

| Platform | VM Runner | AKS Runner |
|----------|:---------:|:----------:|
| **GitHub Actions** | ✅ | ✅ |
| **Azure DevOps** | ✅ | ✅ |

---

## 📦 Four Deployment Options

### GitHub Actions Runners

| Solution | Use Case | Technology | Scalability | Cost |
|----------|----------|------------|-------------|------|
| **[GitHub VM Runner](src/github/vm-runner/)** | Simple projects, fixed workload | Terraform | Fixed instances | 💰 |
| **[GitHub AKS Runner](src/github/aks-runner/)** | Copilot Agent, dynamic workload | Bicep + ARC | Auto-scale 0-N | 💰💰 |

### Azure DevOps Pipeline Agents

| Solution | Use Case | Technology | Scalability | Cost |
|----------|----------|------------|-------------|------|
| **[Azure DevOps VM Agent](src/azure-devops/vm-runner/)** | Simple pipelines, fixed workload | Terraform | Fixed instances | 💰 |
| **[Azure DevOps AKS Agent](src/azure-devops/aks-runner/)** | Dynamic workload, auto-scaling | Bicep + KEDA | Auto-scale 0-N | 💰💰 |

---

## 🖥️ GitHub VM Runner (Terraform)

Suitable for **simple GitHub Actions projects**, running multiple Runners on a single VM.

```
src/github/vm-runner/    # Terraform infrastructure
├── main.tf              # Main configuration
├── variables.tf         # Variable definitions
└── scripts/             # Initialization scripts
```

### Features
- ✅ Simple to use, multiple Runners on one VM
- ✅ Spot VM saves 70-90% cost
- ✅ Pre-installed .NET SDK, Node.js, Docker
- ❌ Does not support Copilot Coding Agent

📖 **Documentation**: [docs/github/vm-runner/](docs/github/vm-runner/)

---

## ☸️ GitHub AKS Runner (Bicep + ARC)

Suitable for **GitHub Copilot Coding Agent** and scenarios requiring auto-scaling.

```
src/github/aks-runner/   # Bicep infrastructure
├── main.bicep           # Main deployment
├── modules/             # AKS/ACR/Log modules
├── kubernetes/          # K8s configurations
└── scripts/             # ARC installation scripts
```

### Features
- ✅ **Supports GitHub Copilot Coding Agent**
- ✅ Auto-scaling (0-N instances)
- ✅ Spot VM saves 60-80% cost
- ✅ Uses official GitHub Runner Image

📖 **Documentation**: [docs/github/aks-runner/](docs/github/aks-runner/)

---

## 🖥️ Azure DevOps VM Agent (Terraform)

Suitable for **simple Azure Pipelines projects**, running multiple Agents on a single VM.

```
src/azure-devops/vm-runner/   # Terraform infrastructure
├── main.tf                   # Main configuration
├── variables.tf              # Variable definitions
└── scripts/                  # Initialization scripts
```

### Features
- ✅ Simple to use, multiple Agents on one VM
- ✅ Spot VM saves 70-90% cost
- ✅ Pre-installed .NET SDK, Node.js, Docker, Azure CLI, PowerShell
- ✅ Support organization and project-level pools

📖 **Documentation**: [src/azure-devops/vm-runner/README.md](src/azure-devops/vm-runner/README.md)

---

## ☸️ Azure DevOps AKS Agent (Bicep + KEDA)

Suitable for **dynamic Azure Pipelines workload** requiring auto-scaling.

```
src/azure-devops/aks-runner/  # Bicep infrastructure
├── main.bicep                # Main deployment
├── modules/                  # AKS/ACR/Log modules
├── kubernetes/               # K8s configurations
└── scripts/                  # KEDA installation scripts
```

### Features
- ✅ **Auto-scaling based on Pipeline queue** (via KEDA)
- ✅ Scale to zero when idle (0-N instances)
- ✅ Spot VM saves 60-80% cost
- ✅ Uses Microsoft official Agent container image

📖 **Documentation**: [src/azure-devops/aks-runner/README.md](src/azure-devops/aks-runner/README.md)

---

## 📁 Project Structure

```
.
├── README.md                        # This file
├── LICENSE
├── .github/
│   └── workflows/
│       ├── ci-vm.yml               # VM Runner CI
│       └── ci-aks.yml              # AKS Runner CI
├── src/
│   ├── github/                     # GitHub Actions Solutions
│   │   ├── vm-runner/              # Terraform VM runner
│   │   └── aks-runner/             # Bicep AKS runner (ARC)
│   ├── azure-devops/               # Azure DevOps Solutions
│   │   ├── vm-runner/              # Terraform VM agent
│   │   └── aks-runner/             # Bicep AKS agent (KEDA)
│   └── common-scripts/             # Common utility scripts
└── docs/
    ├── github/                     # GitHub solutions documentation
    │   ├── vm-runner/
    │   └── aks-runner/
    └── azure-devops/               # Azure DevOps solutions documentation
        ├── vm-runner/
        └── aks-runner/
```

---

## 🚀 Quick Start

### GitHub VM Runner (Simple)

```bash
cd src/github/vm-runner
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your GitHub PAT and repo URL
terraform init
terraform apply
```

### GitHub AKS Runner (Copilot Agent)

```bash
cd src/github/aks-runner
cp main.bicepparam.example main.bicepparam
# Edit main.bicepparam
az deployment sub create --location eastasia --template-file main.bicep --parameters main.bicepparam
# Install ARC
./scripts/install-arc.sh
```

### Azure DevOps VM Agent (Simple)

```bash
cd src/azure-devops/vm-runner
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Azure DevOps PAT and organization URL
terraform init
terraform apply
```

### Azure DevOps AKS Agent (Auto-scaling)

```bash
cd src/azure-devops/aks-runner
cp main.bicepparam.example main.bicepparam
# Edit main.bicepparam
az deployment sub create --location eastasia --template-file main.bicep --parameters main.bicepparam
# Install KEDA
./scripts/install-keda.sh
# Deploy agents
kubectl apply -f kubernetes/
```

---

## 📊 Solution Comparison

| Feature | GitHub VM | GitHub AKS | Azure DevOps VM | Azure DevOps AKS |
|---------|:---------:|:----------:|:---------------:|:----------------:|
| Platform | GitHub Actions | GitHub Actions | Azure Pipelines | Azure Pipelines |
| Technology | Terraform | Bicep + ARC | Terraform | Bicep + KEDA |
| Auto-scaling | ❌ | ✅ | ❌ | ✅ |
| Scale to Zero | ❌ | ✅ | ❌ | ✅ |
| Copilot Agent | ❌ | ✅ | N/A | N/A |
| Spot VM Support | ✅ | ✅ | ✅ | ✅ |
| Idle Cost | ~$29/mo | ~$60/mo | ~$29/mo | ~$40/mo |
| Complexity | Simple | Moderate | Simple | Moderate |

---

## 🔗 Related Resources

### GitHub
- [GitHub Self-hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [GitHub Copilot Coding Agent](https://docs.github.com/en/copilot/using-github-copilot/using-copilot-coding-agent-to-work-on-tasks)
- [Actions Runner Controller (ARC)](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller)

### Azure DevOps
- [Azure Pipelines Agents](https://learn.microsoft.com/azure/devops/pipelines/agents/agents)
- [Self-hosted Linux Agents](https://learn.microsoft.com/azure/devops/pipelines/agents/linux-agent)
- [KEDA Azure Pipelines Scaler](https://keda.sh/docs/scalers/azure-pipelines/)

### Azure
- [Azure Spot VMs](https://learn.microsoft.com/azure/virtual-machines/spot-vms)
- [Azure Kubernetes Service (AKS)](https://learn.microsoft.com/azure/aks/)
- [KEDA - Kubernetes Event-driven Autoscaling](https://keda.sh/)

---

## 📝 License

MIT License
