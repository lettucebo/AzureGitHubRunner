🌏 Language / 語言: [English](README.md) | [繁體中文](README_zh-tw.md)

---

# Azure GitHub Runner

在 Azure 上建立 GitHub Self-hosted Runners 的完整解決方案，支援 GitHub Actions 和 Copilot Coding Agent。

## 📦 兩種部署方案

| 方案 | 適用場景 | 技術 | 擴展性 | 成本 |
|------|---------|------|--------|------|
| **[VM Runner](src/vm-runner/)** | 簡單專案、固定負載 | Terraform | 固定台數 | 💰 |
| **[AKS Runner](src/aks-runner/)** | Copilot Agent、動態負載 | Bicep + ARC | 自動擴展 0-N | 💰💰 |

---

## 🖥️ VM Runner (Terraform)

適合**簡單專案**，使用單一 VM 執行多個 Runner。

```
src/vm-runner/          # Terraform 基礎設施
├── main.tf             # 主配置
├── variables.tf        # 變數定義
└── scripts/            # 初始化腳本
```

### 特點
- ✅ 簡單易用，一個 VM 多個 Runner
- ✅ Spot VM 節省 70-90% 成本
- ✅ 預裝 .NET SDK、Node.js、Docker
- ❌ 不支援 Copilot Coding Agent

📖 **文件**: [docs/vm-runner/](docs/vm-runner/)

---

## ☸️ AKS Runner (Bicep + ARC)

適合 **Copilot Coding Agent** 和需要自動擴展的場景。

```
src/aks-runner/         # Bicep 基礎設施
├── main.bicep          # 主部署
├── modules/            # AKS/ACR/Log 模組
├── kubernetes/         # K8s 配置
└── scripts/            # ARC 安裝腳本
```

### 特點
- ✅ **支援 GitHub Copilot Coding Agent**
- ✅ 自動擴展 (0-N 台)
- ✅ Spot VM 節省 60-80% 成本
- ✅ 使用 GitHub 官方 Runner Image

📖 **文件**: [docs/aks-runner/](docs/aks-runner/)

---

## 📁 專案結構

```
.
├── README.md                     # 本文件
├── LICENSE
├── .github/
│   └── workflows/
│       ├── ci-vm.yml            # VM Runner CI
│       └── ci-aks.yml           # AKS Runner CI
├── src/
│   ├── vm-runner/               # Terraform VM 方案
│   ├── aks-runner/              # Bicep AKS 方案
│   └── common-scripts/          # 共用腳本
└── docs/
    ├── vm-runner/               # VM 方案文件
    └── aks-runner/              # AKS 方案文件
```

---

## 🚀 快速開始

### VM Runner (簡單)

```bash
cd src/vm-runner
cp terraform.tfvars.example terraform.tfvars
# 編輯 terraform.tfvars
terraform init
terraform apply
```

### AKS Runner (Copilot Agent)

```bash
cd src/aks-runner
cp main.bicepparam.example main.bicepparam
# 編輯 main.bicepparam
az deployment sub create --location eastasia --template-file main.bicep --parameters main.bicepparam
```

---

## 📊 方案比較

| 功能 | VM Runner | AKS Runner |
|------|:---------:|:----------:|
| GitHub Actions | ✅ | ✅ |
| Copilot Coding Agent | ❌ | ✅ |
| 自動擴展 | ❌ | ✅ |
| 閒置成本 | ~$29/月 | ~$60/月 |
| 部署複雜度 | 簡單 | 中等 |
| IaC 工具 | Terraform | Bicep |

---

## 🔗 相關資源

- [GitHub Self-hosted Runners](https://docs.github.com/en/actions/hosting-your-own-runners)
- [GitHub Copilot Coding Agent](https://docs.github.com/en/copilot/using-github-copilot/using-copilot-coding-agent-to-work-on-tasks)
- [Actions Runner Controller (ARC)](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller)
- [Azure Spot VM](https://learn.microsoft.com/en-us/azure/virtual-machines/spot-vms)

---

## 📝 授權

MIT License
