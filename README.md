🌏 Language / 語言: [English](README.md) | [繁體中文](README_zh-tw.md)

---

# Azure GitHub Runner

A complete solution for deploying GitHub Self-hosted Runners on Azure, supporting GitHub Actions and Copilot Coding Agent.

## 📦 Two Deployment Options

| Solution | Use Case | Technology | Scalability | Cost |
|----------|----------|------------|-------------|------|
| **[VM Runner](src/vm-runner/)** | Simple projects, fixed workload | Terraform | Fixed instances | 💰 |
| **[AKS Runner](src/aks-runner/)** | Copilot Agent, dynamic workload | Bicep + ARC | Auto-scale 0-N | 💰💰 |

---

## 🖥️ VM Runner (Terraform)

Suitable for **simple projects**, running multiple Runners on a single VM.

```
src/vm-runner/          # Terraform infrastructure
├── main.tf             # Main configuration
├── variables.tf        # Variable definitions
└── scripts/            # Initialization scripts
```

### Features
- ✅ Simple to use, multiple Runners on one VM
- ✅ Spot VM saves 70-90% cost
- ✅ Pre-installed .NET SDK, Node.js, Docker
- ❌ Does not support Copilot Coding Agent

📖 **Documentation**: [docs/vm-runner/](docs/vm-runner/)

---

## ☸️ AKS Runner (Bicep + ARC)

Suitable for **Copilot Coding Agent** and scenarios requiring auto-scaling.

```
src/aks-runner/         # Bicep infrastructure
├── main.bicep          # Main deployment
├── modules/            # AKS/ACR/Log modules
├── kubernetes/         # K8s configurations
└── scripts/            # ARC installation scripts
```

### Features
- ✅ **Supports GitHub Copilot Coding Agent**
- ✅ Auto-scaling (0-N instances)
- ✅ Spot VM saves 60-80% cost
- ✅ Uses official GitHub Runner Image

📖 **Documentation**: [docs/aks-runner/](docs/aks-runner/)

---

## 📁 Project Structure

```
.
├── README.md                     # This file
├── LICENSE
├── .github/
│   └── workflows/
│       ├── ci-vm.yml            # VM Runner CI
│       └── ci-aks.yml           # AKS Runner CI
├── src/
│   ├── vm-runner/               # Terraform VM solution
│   ├── aks-runner/              # Bicep AKS solution
│   └── common-scripts/          # Common scripts
└── docs/
    ├── vm-runner/               # VM solution documentation
    └── aks-runner/              # AKS solution documentation
```

---

## 🚀 Quick Start

### VM Runner (Simple)

```bash
cd src/vm-runner
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars
terraform init
terraform apply
```

### AKS Runner (Copilot Agent)

```bash
cd src/aks-runner
cp main.bicepparam.example main.bicepparam
# Edit main.bicepparam
az deployment sub create --location eastasia --template-file main.bicep --parameters main.bicepparam
```

---

## 📊 Solution Comparison

| Feature | VM Runner | AKS Runner |
|---------|:---------:|:----------:|
| GitHub Actions | ✅ | ✅ |
| Copilot Coding Agent | ❌ | ✅ |
| Auto-scaling | ❌ | ✅ |
| Idle Cost | ~$29/mo | ~$60/mo |
| Deployment Complexity | Simple | Moderate |
| IaC Tool | Terraform | Bicep |

---

## 🔗 Related Resources

- [GitHub Self-hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [GitHub Copilot Coding Agent](https://docs.github.com/en/copilot/using-github-copilot/using-copilot-coding-agent-to-work-on-tasks)
- [Actions Runner Controller (ARC)](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller)
- [Azure Spot VM](https://learn.microsoft.com/en-us/azure/virtual-machines/spot-vms)

---

## 📝 License

MIT License
