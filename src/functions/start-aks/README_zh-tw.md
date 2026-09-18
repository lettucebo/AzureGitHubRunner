🌏 Language / 語言: [English](README.md) | [繁體中文](README_zh-tw.md)

---

# Start AKS — 定時自動啟動/停止 AKS 叢集

一個 Azure Function，每天依排程自動啟動（並可選擇性地停止）AKS 叢集。適用於公司政策在半夜強制關閉叢集的環境。

## ✅ 支援功能

| 功能 | 支援 | 說明 |
|------|:----:|------|
| 排程啟動 | ✅ | 兩個 Timer Trigger（`startAks` 00:25/00:40，`startAksFallback` 06:00，皆台北時間） |
| 排程停止 | ✅（預設停用） | `stopAks` Timer Trigger，需明確設定 `enableStopSchedule=true` 才會啟用 |
| 排程可設定 | ✅ | 透過 `AKS_START_SCHEDULE` / `AKS_START_FALLBACK_SCHEDULE` / `AKS_STOP_SCHEDULE` app setting 覆寫；未設定時回退為程式碼內建的相同預設值 |
| 多叢集支援 | ✅ | 同時啟動/停止多個 AKS 叢集 |
| 跨訂閱 | ✅ | 叢集可分佈在不同 Azure 訂閱 |
| Managed Identity | ✅ | 透過系統指派 MI 無密碼認證 |
| 冪等操作 | ✅ | 只對精確符合的電源狀態動作，其餘一律跳過 |
| 錯誤隔離 | ✅ | 單一叢集失敗不影響其他叢集（各自獨立 try/catch） |

## 🏗️ 架構概覽

```
┌───────────────────────────────────────────────────┐
│                Azure Function App                  │
│         (Linux Flex Consumption, Node.js 22)        │
│                                                     │
│  Timer: startAks（00:25 與 00:40 台北時間，預設）    │
│  Timer: startAksFallback（06:00 台北時間，預設）      │
│  Timer: stopAks（20:00 台北時間，預設 —— 預設停用，   │
│          透過 AzureWebJobs.stopAks.Disabled=true /   │
│          enableStopSchedule=false）                  │
│         │                                           │
│         ▼                                           │
│  讀取並驗證 AKS_CLUSTERS 環境變數（須為非空 JSON      │
│  陣列，每筆含 subscriptionId/resourceGroup/name）     │
│  — src/aksPower.ts                                   │
│         │                                           │
│         ▼                                           │
│  逐一處理每個叢集（try/catch，錯誤互相隔離）:          │
│  ┌───────────────────────────────────────────┐       │
│  │ 檢查精確 powerState.code                    │       │
│  │  啟動：僅 'Stopped' → beginStartAndWait     │──── Managed ──▶ AKS 叢集 1
│  │  停止：僅 'Running' → beginStopAndWait      │       Identity  ──▶ AKS 叢集 2
│  │  其餘 (Starting/Stopping/undefined/         │                 ──▶ AKS 叢集 N
│  │  未知值) → 跳過並記錄原因                    │
│  └───────────────────────────────────────────┘
└───────────────────────────────────────────────────┘
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

### 環境變數（App Settings）

| 變數 | 說明 | 預設值（未設定時） |
|------|------|---------------------|
| `AKS_CLUSTERS` | 目標叢集 JSON 陣列（必填，須為**非空**陣列） | 無預設值；缺少/無效/空陣列 ⇒ 明確記錄錯誤且不呼叫任何 Azure API |
| `WEBSITE_TIME_ZONE` | IANA 時區名稱 (Linux)，套用於下列所有 Timer 排程 | `Asia/Taipei` |
| `AKS_START_SCHEDULE` | 主要 `startAks` Timer 的 NCRONTAB 排程 | `0 25,40 0 * * *` |
| `AKS_START_FALLBACK_SCHEDULE` | `startAksFallback` Timer 的 NCRONTAB 排程 | `0 0 6 * * *` |
| `AKS_STOP_SCHEDULE` | `stopAks` Timer 的 NCRONTAB 排程 | `0 0 20 * * *` |
| `AzureWebJobs.stopAks.Disabled` | 官方 Azure Functions 停用特定函式的 app setting。**預設為 `true`**（由 Bicep `enableStopSchedule=false` 產生），確保停止排程未經明確啟用不會執行 | `true` |

所有排程值皆在程式碼中解析（`src/aksPower.ts` → `resolveSchedule`）：app setting 去除前後空白後若非空字串即採用，否則回退到程式碼內建的上述預設值。這代表僅部署程式碼、尚未套用 Bicep app settings 的情境，仍會以相同預設值正確索引與執行。

### AKS_CLUSTERS 格式

必須為**非空 JSON 陣列**；每筆項目的 `subscriptionId`、`resourceGroup`、`name` 皆須為非空字串。無效/缺少 JSON、非陣列型別（例如物件）、空陣列，或任何項目缺少/為空字串的欄位，皆會被拒絕並明確記錄錯誤，**且不會呼叫任何 Azure API**。

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

### 電源狀態處理

兩個函式皆讀取叢集精確的 `powerState.code`，僅對唯一預期的狀態值採取動作；其餘所有狀態皆明確跳過並記錄原因（絕不靜默忽略）：

| `powerState.code` | `startAks` / `startAksFallback` | `stopAks` |
|---|---|---|
| `Stopped` | ✅ 呼叫 `beginStartAndWait` | ⏭️ 跳過（已停止） |
| `Running` | ⏭️ 跳過（已運行） | ✅ 呼叫 `beginStopAndWait` |
| `Starting` | ⏭️ 跳過（轉換中） | ⏭️ 跳過（轉換中） |
| `Stopping` | ⏭️ 跳過（轉換中） | ⏭️ 跳過（轉換中） |
| `undefined` | ⏭️ 跳過（狀態未知） | ⏭️ 跳過（狀態未知） |
| 其他任意值 | ⏭️ 跳過（無法識別） | ⏭️ 跳過（無法識別） |

每個叢集皆在獨立的 `try/catch` 中處理；單一叢集失敗（例如權限錯誤、API 限流）會被記錄，且**不會**阻擋同一次執行中後續叢集的處理。

## 🔐 停止排程的安全機制（預設停用）

`stopAks` Timer Trigger **預設為停用狀態**：

- Bicep 參數 `enableStopSchedule` 預設為 `false`。
- 此參數會產生官方 app setting `AzureWebJobs.stopAks.Disabled = string(!enableStopSchedule)`，預設即為 `"true"` —— Azure Functions Host 完全不會呼叫 `stopAks`。
- 若要啟用，請在 `main.bicepparam` 中將 `enableStopSchedule = true` 並重新部署；Function App 的 app setting 會翻轉為 `"false"`。
- 刻意**不新增第二個自訂啟用旗標** —— `enableStopSchedule` 是唯一的真實來源，與官方停用機制一對一對應。

## ⚠️ 操作注意事項

- **冪等，但非同步佇列**：`beginStartAndWait`/`beginStopAndWait` 會在函式執行期間等待 ARM 長時間執行作業完成，因此若排程觸發時叢集正處於轉換中狀態，該次觸發僅會被跳過（見上表），不會被排隊或自動重試。
- **不具跨次執行鎖定機制**：若透過其他方式（例如手動 `az aks start/stop`）同時操作叢集，下一次排程執行只會依當下觀察到的 `powerState.code` 決定動作。
- **Managed Identity 權限**：啟動與停止皆需要目標 Resource Group 上的 "Azure Kubernetes Service Contributor"（或相當）角色 —— 既有的角色指派同時涵蓋啟動與停止。
- **時區**：三個排程皆依 `WEBSITE_TIME_ZONE`（預設 `Asia/Taipei`）解讀；變更時區會讓所有排程一併平移。

## 💰 成本估算

| 資源 | SKU | 月費 |
|------|-----|------|
| Function App | Flex Consumption (FC1) | ~$0（每天數次執行） |
| Storage Account | Standard LRS | ~$0.01 |
| **Function App 合計** | | **~$0.01/月** |

> ⚠️ **計費注意事項**：停止 AKS 叢集會反配置 (deallocate) 控制平面與 Agent Node 的 VM，因此可省下這些節點的運算費用 —— 詳見 [Microsoft Learn: 啟動及停止 AKS 叢集](https://learn.microsoft.com/en-us/azure/aks/start-stop-cluster)。該頁面並未列舉所有可能持續產生的費用，也未保證停止後的叢集總成本為零。與叢集相關的其他 Azure 資源（例如磁碟、負載平衡器/公用 IP、Container Registry、Log Analytics、Private Endpoint、本 Function App 本身等）可能不受叢集電源狀態影響而持續計費。請自行檢視您的資源清單與帳單，勿假設停止 AKS 即可消除全部成本。

## 🔍 故障排除

### Function 沒有觸發

1. 確認 `WEBSITE_TIME_ZONE` 已設定為您預期的 IANA 時區（預設 `Asia/Taipei`）
2. 檢查 Function App 是否運行中：`az functionapp show -g rg-startaks-prod -n func-startaks-prod --query state`
3. 針對 `stopAks`：若預期它應該執行，請確認 `AzureWebJobs.stopAks.Disabled` 為 `"false"`（即已部署 `enableStopSchedule=true`）

### 啟動/停止 AKS 時權限不足

1. 確認 Managed Identity 在目標 Resource Group 上有 "Azure Kubernetes Service Contributor" 角色
2. 查詢 Principal ID：`az functionapp identity show -g rg-startaks-prod -n func-startaks-prod --query principalId`
3. 手動指派角色：
   ```bash
   az role assignment create --assignee <principalId> \
     --role "Azure Kubernetes Service Contributor" \
     --scope /subscriptions/<subId>/resourceGroups/<rgName>
   ```

### AKS 叢集仍然停止／仍然運行

1. 查看 Function App 日誌：`az functionapp log tail -g rg-startaks-prod -n func-startaks-prod`
2. 確認 `AKS_CLUSTERS` JSON 格式正確（非空陣列，所有欄位皆為非空字串）
3. 確認叢集的 `powerState.code` 是否符合函式預期的精確值（見上方電源狀態表）——任何非預期的精確值皆會依設計被跳過
4. 嘗試手動啟動/停止：`az aks start -g <rg> -n <aks-name>` / `az aks stop -g <rg> -n <aks-name>`
