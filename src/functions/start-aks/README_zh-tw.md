🌏 Language / 語言: [English](README.md) | [繁體中文](README_zh-tw.md)

---

# Start AKS — 定時自動啟動 AKS 叢集

一個 Azure Function，每天依排程自動啟動 AKS 叢集。適用於公司政策在半夜強制關閉叢集的環境。

## ✅ 支援功能

| 功能 | 支援 | 說明 |
|------|:----:|------|
| 排程啟動 | ✅ | 每天台北時間 06:00 觸發 |
| 多叢集支援 | ✅ | 同時啟動多個 AKS 叢集 |
| 跨訂閱 | ✅ | 叢集可分佈在不同 Azure 訂閱 |
| Managed Identity | ✅ | 透過系統指派 MI 無密碼認證 |
| 冪等操作 | ✅ | 已運行的叢集自動跳過 |
| 錯誤隔離 | ✅ | 單一叢集失敗不影響其他叢集 |

## 🏗️ 架構概覽

```
┌─────────────────────────────────────────┐
│         Azure Function App              │
│   (Linux Flex Consumption, Node.js 22)  │
│                                         │
│   Timer Trigger (06:00 台北時間)         │
│         │                               │
│         ▼                               │
│   讀取 AKS_CLUSTERS 環境變數            │
│         │                               │
│         ▼                               │
│   逐一處理每個叢集:                      │
│   ┌─────────────────────┐               │
│   │ 檢查電源狀態         │               │
│   │   └─ 若為 Stopped   │               │
│   │      └─ 啟動 AKS    │──── Managed ──┼──▶ AKS 叢集 1
│   └─────────────────────┘    Identity    │──▶ AKS 叢集 2
│                                         │──▶ AKS 叢集 N
└─────────────────────────────────────────┘
```

## 🔧 前置需求

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)
- [Azure Functions Core Tools v4](https://docs.microsoft.com/azure/azure-functions/functions-run-local)
- [Node.js 22](https://nodejs.org/)（或20+）
- [Bicep CLI](https://docs.microsoft.com/azure/azure-resource-manager/bicep/install)

## 🚀 快速開始

### 1. 部署基礎設施

```bash
# 複製並編輯參數檔
cp main.bicepparam.example main.bicepparam

# 部署（訂閱層級）
az deployment sub create --location eastasia \
  --template-file main.bicep --parameters main.bicepparam
```

### 2. 部署 Function 程式碼

```bash
# 安裝依賴並建置
npm install
npm run build

# 部署至 Azure
func azure functionapp publish func-startaks-prod --javascript
```

### 3. 驗證

```bash
# 檢查 Function App 狀態
az functionapp show -g rg-startaks-prod -n func-startaks-prod --query state

# 檢查 AKS 叢集電源狀態
az aks show -g rg-ghrunner-prod -n aks-ghrunner-prod --query powerState.code
```

## 📋 設定說明

### 環境變數

| 變數 | 說明 | 範例 |
|------|------|------|
| `AKS_CLUSTERS` | 目標叢集 JSON 陣列 | `[{"subscriptionId":"...","resourceGroup":"rg-ghrunner-prod","name":"aks-ghrunner-prod"}]` |
| `WEBSITE_TIME_ZONE` | IANA 時區名稱 (Linux) | `Asia/Taipei` |

### AKS_CLUSTERS 格式

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

## 💰 成本估算

| 資源 | SKU | 月費 |
|------|-----|------|
| Function App | Flex Consumption (FC1) | ~$0（每天 1 次執行） |
| Storage Account | Standard LRS | ~$0.01 |
| **合計** | | **~$0.01/月** |

## 🔍 故障排除

### Function 沒有觸發

1. 確認 `WEBSITE_TIME_ZONE` 設定為 `Asia/Taipei`
2. 檢查 Function App 是否運行中：`az functionapp show -g rg-startaks-prod -n func-startaks-prod --query state`

### 啟動 AKS 時權限不足

1. 確認 Managed Identity 在目標 Resource Group 上有 "Azure Kubernetes Service Contributor" 角色
2. 查詢 Principal ID：`az functionapp identity show -g rg-startaks-prod -n func-startaks-prod --query principalId`
3. 手動指派角色：
   ```bash
   az role assignment create --assignee <principalId> \
     --role "Azure Kubernetes Service Contributor" \
     --scope /subscriptions/<subId>/resourceGroups/<rgName>
   ```

### AKS 叢集仍然停止

1. 查看 Function App 日誌：`az functionapp log tail -g rg-startaks-prod -n func-startaks-prod`
2. 確認 `AKS_CLUSTERS` JSON 格式正確
3. 嘗試手動啟動：`az aks start -g <rg> -n <aks-name>`
