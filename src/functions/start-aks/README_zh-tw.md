🌏 Language / 語言: [English](README.md) | [繁體中文](README_zh-tw.md)

---

# Start AKS — 定時自動啟動/停止 AKS 叢集

一個 Azure Function，每天依排程自動啟動（並可選擇性地停止）AKS 叢集。適用於公司政策在半夜強制關閉叢集的環境。

## ✅ 支援功能

| 功能 | 支援 | 說明 |
|------|:----:|------|
| 排程啟動 | ✅ | 單一 Timer Trigger `startAks`，預設 `0 25,40 16 * * *`（UTC，台北時間 00:25/00:40） |
| 排程停止 | ✅（預設停用，fail-closed） | `stopAks` Timer Trigger，預設 `0 0 14 * * *`（UTC）；需 `AKS_STOP_ENABLED` 精確為 `"true"`（不分大小寫、自動 trim）才會實際執行，否則在任何 Azure 呼叫之前就會被跳過 |
| 排程可設定 | ✅ | 透過 `AKS_START_SCHEDULE_UTC` / `AKS_STOP_SCHEDULE_UTC` app setting 覆寫（皆為 UTC NCRONTAB）；未設定時回退為程式碼內建的相同預設值 |
| 多叢集支援 | ✅ | 同時啟動/停止多個 AKS 叢集 |
| 跨訂閱 | ✅ | 叢集可分佈在不同 Azure 訂閱 |
| Managed Identity | ✅ | 透過系統指派 MI 無密碼認證 |
| 冪等操作 | ✅ | 只對精確符合的電源狀態動作，其餘一律跳過 |
| 錯誤隔離 | ✅ | `AKS_CLUSTERS` 中單筆格式錯誤的項目（逐項驗證）與單一叢集的 Azure API 失敗（try/catch）皆互相隔離 —— 一筆錯誤絕不會擋住其餘項目 |

## 🏗️ 架構概覽

```
┌───────────────────────────────────────────────────┐
│                Azure Function App                  │
│         (Linux Flex Consumption, Node.js 22)        │
│                                                     │
│  Timer: startAks（預設 0 25,40 16 * * * UTC =       │
│          台北時間隔天 00:25 與 00:40）                │
│  Timer: stopAks（預設 0 0 14 * * * UTC =            │
│          台北時間當天 22:00 —— 由 AKS_STOP_ENABLED   │
│          把關，fail-closed）                         │
│         │                                           │
│         ▼                                           │
│  src/functions/*.ts —— 僅負責裝配 (wiring)：          │
│  由環境變數建立 credential/clientFactory/logger，     │
│  註冊 UTC Timer，委派給 src/aksOperations.ts          │
│         │                                           │
│         ▼                                           │
│  src/aksOperations.ts —— 可測試的執行邏輯：            │
│   1. 僅 stopAks：於任何動作之前先檢查                 │
│      AKS_STOP_ENABLED === "true"（trim、不分大小寫）  │
│      不符合即記錄並返回，零 Azure 呼叫                │
│   2. 解析並驗證 AKS_CLUSTERS（src/aksPower.ts）：      │
│      全域 JSON/陣列/空陣列失敗 ⇒ 中止；               │
│      否則逐項獨立驗證，無效項目記錄並跳過，            │
│      有效項目繼續處理                                │
│         │                                           │
│         ▼                                           │
│  逐一處理每個有效叢集（try/catch，錯誤互相隔離）:      │
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
| `AKS_CLUSTERS` | 目標叢集 JSON 陣列（必填，須為**非空**陣列） | 無預設值；缺少/無效 JSON/非陣列/空陣列 ⇒ 明確記錄錯誤且不呼叫任何 Azure API |
| `AKS_START_SCHEDULE_UTC` | `startAks` Timer 的 NCRONTAB 排程（**UTC**） | `0 25,40 16 * * *`（UTC） |
| `AKS_STOP_SCHEDULE_UTC` | `stopAks` Timer 的 NCRONTAB 排程（**UTC**） | `0 0 14 * * *`（UTC） |
| `AKS_STOP_ENABLED` | **啟用停止排程的唯一真實來源**。去除前後空白後，只有「精確等於」(不分大小寫) 字串 `"true"` 才視為啟用；缺少、空白、`"false"`，或任何其他值 ⇒ 停用 (fail-closed) | 未設定（⇒ 停用） |

所有排程值皆在程式碼中解析（`src/aksPower.ts` → `resolveSchedule`）：app setting 去除前後空白後若非空字串即採用，否則回退到程式碼內建的上述預設值。這代表僅部署程式碼、尚未套用 Bicep app settings 的情境，仍會以相同預設值正確索引與執行。

### ⏰ 時區與排程（僅支援 UTC）

Flex Consumption 的 Timer Trigger **一律以 UTC 解讀** NCRONTAB 表示式，本方案不支援 `WEBSITE_TIME_ZONE` / `TZ` 來調整解讀時區。參考：
- https://learn.microsoft.com/en-us/azure/azure-functions/errors-diagnostics/diagnostic-events/azfd0010
- https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-timer#time-zones

對操作者的影響：
- 預設值（啟動 `0 25,40 16 * * *`／停止 `0 0 14 * * *`，皆為 UTC）分別對應**台北時間 (UTC+8) 00:25 與 00:40／22:00**。啟動嘗試實際於相對於當地時間的「前一個 UTC 曆日」16:25/16:40 觸發（例如 UTC 週一 16:25/16:40 → 台北時間週二 00:25/00:40）。
- 兩次啟動嘗試保留公司約 00:05 強制停機後的 fast-restart 意圖：00:25 為主要嘗試，00:40 則在停止完成或設定傳播延遲時提供重試韌性。不另設無關的 06:00 fallback。
- **星期欄位會跨越 UTC 曆日邊界。** 若需要以「特定當地星期」為錨點的排程（例如「每週一台北時間 00:25/00:40」），須注意台北時間週一 00:25/00:40 = UTC **週日** 16:25/16:40 —— 星期欄位必須以 UTC 的星期表示，而非當地星期。
- **不會自動調整日光節約時間 (DST)。** 若目標時區實施 DST，操作者需自行在偏移量變動時更新 UTC NCRONTAB 表示式（`AKS_START_SCHEDULE_UTC` / `AKS_STOP_SCHEDULE_UTC`）；Azure Functions 不會自動平移。

### AKS_CLUSTERS 格式

必須為**非空 JSON 陣列**。陣列本身須合法：缺少/無效 JSON、非陣列型別（例如物件）、或空陣列，屬於**全域**失敗 —— 會被明確記錄錯誤且**完全不呼叫任何 Azure API**。

只要陣列本身合法且非空，**每筆項目各自獨立驗證**（per-cluster isolation）：缺少/欄位為空字串的 `subscriptionId`、`resourceGroup`、或 `name` 項目，會依其索引記錄錯誤（例如 `AKS_CLUSTERS 第 1 筆項目缺少有效的 subscriptionId/resourceGroup/name...`）並跳過，但**絕不**因此拒絕陣列中其餘合法項目 —— 這些項目仍會正常處理。合法項目的三個字串欄位會被 trim。若全部項目皆無效，該次執行僅會處理零個叢集（並記錄每筆原因），而非直接判定整體失敗。

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

| `powerState.code` | `startAks` | `stopAks` |
|---|---|---|
| `Stopped` | ✅ 呼叫 `beginStartAndWait` | ⏭️ 跳過（已停止） |
| `Running` | ⏭️ 跳過（已運行） | ✅ 呼叫 `beginStopAndWait` |
| `Starting` | ⏭️ 跳過（轉換中） | ⏭️ 跳過（轉換中） |
| `Stopping` | ⏭️ 跳過（轉換中） | ⏭️ 跳過（轉換中） |
| `undefined` | ⏭️ 跳過（狀態未知） | ⏭️ 跳過（狀態未知） |
| 其他任意值 | ⏭️ 跳過（無法識別） | ⏭️ 跳過（無法識別） |

每個叢集皆在獨立的 `try/catch` 中處理；單一叢集失敗（例如權限錯誤、API 限流）會被記錄，且**不會**阻擋同一次執行中後續叢集的處理。

## 🔐 停止排程的安全機制 —— 預設 Fail-Closed

`stopAks` Timer Trigger 仍會依排程觸發，但**其實際的停止邏輯由程式碼把關、預設停用**：

- Bicep 參數 `enableStopSchedule` 預設為 `false`，會一對一映射為 app setting `AKS_STOP_ENABLED: string(enableStopSchedule)`。
- **程式碼本身**（`src/aksOperations.ts` → `runStopAks`，使用 `src/aksPower.ts` → `isStopScheduleEnabled`）會在**第一步**就檢查 `AKS_STOP_ENABLED`，早於解析 `AKS_CLUSTERS`、早於建立任何 credential/client、早於任何 Azure API 呼叫。只有去除前後空白後精確等於（不分大小寫）`"true"` 的值才會繼續執行；其餘 —— 缺少、空白、`"false"`、拼字錯誤 —— 皆會記錄明確訊息並立即返回，零 Azure 呼叫。
- 這是刻意採用**程式碼層級、fail-closed** 的把關機制，而非僅依賴 Azure Functions Host 層級的 `AzureWebJobs.<name>.Disabled` 機制：若該 app setting 缺失/設定錯誤，或該機制本身在 Host 層有非預期行為，先前的實作方式仍有函式繼續執行的風險。`AKS_STOP_ENABLED` 是**唯一的真實來源** —— 沒有第二個旗標需要保持同步。
- 若要啟用，請在 `main.bicepparam` 中將 `enableStopSchedule = true` 並重新部署；app setting 會變為 `"true"`。

## ⚠️ 操作注意事項

- **冪等，但非同步佇列**：`beginStartAndWait`/`beginStopAndWait` 會在函式執行期間等待 ARM 長時間執行作業完成，因此若排程觸發時叢集正處於轉換中狀態，該次觸發僅會被跳過（見上表），不會被排隊或自動重試。
- **不具跨次執行鎖定機制**：若透過其他方式（例如手動 `az aks start/stop`）同時操作叢集，下一次排程執行只會依當下觀察到的 `powerState.code` 決定動作。
- **Managed Identity 權限**：啟動與停止皆需要目標 Resource Group 上的 "Azure Kubernetes Service Contributor"（或相當）角色 —— 既有的角色指派同時涵蓋啟動與停止。
- **僅支援 UTC 排程**：兩個 Timer 排程皆嚴格以 UTC 解讀（見上方「時區與排程」）—— 沒有任何時區 app setting 可以平移排程。

## 💰 成本估算

| 資源 | SKU | 月費 |
|------|-----|------|
| Function App | Flex Consumption (FC1) | ~$0（每天數次執行） |
| Storage Account | Standard LRS | ~$0.01 |
| **Function App 合計** | | **~$0.01/月** |

> ⚠️ **計費注意事項**：停止 AKS 叢集會反配置 (deallocate) 控制平面與 Agent Node 的 VM，因此可省下這些節點的運算費用 —— 詳見 [Microsoft Learn: 啟動及停止 AKS 叢集](https://learn.microsoft.com/en-us/azure/aks/start-stop-cluster)。該頁面並未列舉所有可能持續產生的費用，也未保證停止後的叢集總成本為零。與叢集相關的其他 Azure 資源（例如磁碟、負載平衡器/公用 IP、Container Registry、Log Analytics、Private Endpoint、本 Function App 本身等）可能不受叢集電源狀態影響而持續計費。請自行檢視您的資源清單與帳單，勿假設停止 AKS 即可消除全部成本。

## 🔍 故障排除

### Function 沒有觸發

1. 請記得排程僅支援 UTC（見上方「時區與排程」）—— 請再次確認 `AKS_START_SCHEDULE_UTC` / `AKS_STOP_SCHEDULE_UTC` 是以 UTC（而非當地時間）表示
2. 檢查 Function App 是否運行中：`az functionapp show -g rg-startaks-prod -n func-startaks-prod --query state`
3. 針對 `stopAks`：若預期它應該實際執行停止動作，請確認 `AKS_STOP_ENABLED` 精確為 `"true"`（即已部署 `enableStopSchedule=true`）—— Timer 本身仍會依排程觸發，但除非此值精確為 `"true"`，程式碼會立即返回、不呼叫任何 Azure API

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
2. 確認 `AKS_CLUSTERS` JSON 格式正確 —— 陣列本身必須是合法的非空 JSON 陣列（缺少/非陣列/空陣列屬於全域失敗），但合法陣列內個別無效項目只會被記錄並跳過，不會造成全域失敗
3. 確認叢集的 `powerState.code` 是否符合函式預期的精確值（見上方電源狀態表）——任何非預期的精確值皆會依設計被跳過
4. 嘗試手動啟動/停止：`az aks start -g <rg> -n <aks-name>` / `az aks stop -g <rg> -n <aks-name>`
