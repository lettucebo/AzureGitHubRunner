🌏 Language / 語言: [English](README.md) | [繁體中文](README_zh-tw.md)

---

# Start AKS — Scheduled AKS Cluster Auto-Start

An Azure Function that automatically starts AKS clusters on a daily schedule. Designed for environments where company policies force-stop clusters at night.

## ✅ Features

| Feature | Support | Description |
|---------|:------:|-------------|
| Scheduled Start | ✅ | Timer Trigger at 06:00 Taipei time daily |
| Multiple Clusters | ✅ | Support starting multiple AKS clusters simultaneously |
| Cross-Subscription | ✅ | Clusters can be in different Azure subscriptions |
| Managed Identity | ✅ | Passwordless authentication via System-assigned MI |
| Idempotent | ✅ | Skips clusters that are already running |
| Error Isolation | ✅ | One cluster failure doesn't affect others |

## 🏗️ Architecture

```
┌─────────────────────────────────────────┐
│         Azure Function App              │
│   (Linux Flex Consumption, Node.js 22)  │
│                                         │
│   Timer Trigger (06:00 Taipei Time)     │
│         │                               │
│         ▼                               │
│   Read AKS_CLUSTERS env var             │
│         │                               │
│         ▼                               │
│   For each cluster:                     │
│   ┌─────────────────────┐               │
│   │ Check power state   │               │
│   │   └─ If Stopped     │               │
│   │      └─ Start AKS   │──── Managed ──┼──▶ AKS Cluster 1
│   └─────────────────────┘    Identity    │──▶ AKS Cluster 2
│                                         │──▶ AKS Cluster N
└─────────────────────────────────────────┘
```

## 🔧 Prerequisites

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)
- [Azure Functions Core Tools v4](https://docs.microsoft.com/azure/azure-functions/functions-run-local)
- [Node.js 22](https://nodejs.org/) (or 20+)
- [Bicep CLI](https://docs.microsoft.com/azure/azure-resource-manager/bicep/install)

## 🚀 Quick Start

### 1. Deploy Infrastructure

```bash
# Copy and edit parameter file
cp main.bicepparam.example main.bicepparam

# Deploy (subscription scope)
az deployment sub create --location eastasia \
  --template-file main.bicep --parameters main.bicepparam
```

### 2. Deploy Function Code

```bash
# Install dependencies and build
npm install
npm run build

# Deploy to Azure
func azure functionapp publish func-startaks-prod --javascript
```

### 3. Verify

```bash
# Check Function App status
az functionapp show -g rg-startaks-prod -n func-startaks-prod --query state

# Check AKS cluster power state
az aks show -g rg-ghrunner-prod -n aks-ghrunner-prod --query powerState.code
```

## 📋 Configuration

### Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `AKS_CLUSTERS` | JSON array of target clusters | `[{"subscriptionId":"...","resourceGroup":"rg-ghrunner-prod","name":"aks-ghrunner-prod"}]` |
| `WEBSITE_TIME_ZONE` | IANA timezone name (Linux) | `Asia/Taipei` |

### AKS_CLUSTERS Format

```json
[
  {
    "subscriptionId": "00000000-0000-0000-0000-000000000000",
    "resourceGroup": "rg-ghrunner-prod",
    "name": "aks-ghrunner-prod"
  },
  {
    "subscriptionId": "00000000-0000-0000-0000-000000000000",
    "resourceGroup": "rg-devops-agent-prod",
    "name": "aks-devops-agent-prod"
  }
]
```

## 💰 Cost Estimate

| Resource | SKU | Monthly Cost |
|----------|-----|-------------|
| Function App | Flex Consumption (FC1) | ~$0 (1 execution/day) |
| Storage Account | Standard LRS | ~$0.01 |
| **Total** | | **~$0.01/month** |

## 🔍 Troubleshooting

### Function doesn't trigger

1. Verify `WEBSITE_TIME_ZONE` is set to `Asia/Taipei`
2. Check Function App is running: `az functionapp show -g rg-startaks-prod -n func-startaks-prod --query state`

### Permission denied when starting AKS

1. Verify Managed Identity has "Azure Kubernetes Service Contributor" role on the target resource group
2. Check principal ID: `az functionapp identity show -g rg-startaks-prod -n func-startaks-prod --query principalId`
3. Manually assign if needed:
   ```bash
   az role assignment create --assignee <principalId> \
     --role "Azure Kubernetes Service Contributor" \
     --scope /subscriptions/<subId>/resourceGroups/<rgName>
   ```

### AKS cluster still stopped

1. Check Function App logs: `az functionapp log tail -g rg-startaks-prod -n func-startaks-prod`
2. Verify `AKS_CLUSTERS` JSON format is correct
3. Try manual start: `az aks start -g <rg> -n <aks-name>`
