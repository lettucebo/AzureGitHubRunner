# Azure DevOps AKS Runner (Bicep + KEDA)

使用 Bicep 在 AKS 上部署 Azure DevOps Self-hosted Agents，搭配 KEDA 實現自動擴展。

## 📋 功能特色

- ✅ **自動擴展**: 根據 Pipeline 隊列自動調整 Agent 數量 (0-N)
- ✅ **Spot VM**: 使用 Spot Instance 節省 60-80% 成本
- ✅ **容器化**: 使用 Microsoft 官方 Agent 容器映像
- ✅ **KEDA 驅動**: 事件驅動的自動擴展
- ✅ **高可用性**: Kubernetes 自動管理 Pod 生命週期

## 🏗️ 架構說明

```
AKS Cluster
├── System Node Pool (B2s, 固定 1 台)
│   ├── Kubernetes 系統組件
│   └── KEDA Controller
└── Agent Node Pool (D4s_v3, Spot VM, 0-10 台)
    └── Azure DevOps Agent Pods (自動擴展)
```

**自動擴展邏輯**:
- 有 Pipeline Job 排隊 → 自動增加 Agent Pods
- Pipeline Job 完成 → 自動縮減 Agent Pods
- 無任務時 → 縮減至 0 (不產生費用)

## 📦 前置需求

1. **Azure 訂閱**
2. **Azure CLI** >= 2.50.0
3. **kubectl**
4. **Helm** >= 3.0
5. **Azure DevOps 組織和 PAT Token**
   - 需要權限: Agent Pools (Read & manage)

## 🚀 快速開始

### 1. 建立配置檔

```bash
cd src/azure-devops/aks-runner
cp main.bicepparam.example main.bicepparam
```

### 2. 編輯 main.bicepparam

```bicep
using './main.bicep'

param environment = 'prod'
param projectName = 'adoagent'
param location = 'eastasia'
param kubernetesVersion = '1.33'

// System Pool (固定)
param systemNodeVmSize = 'Standard_B2s'
param systemNodeCount = 1

// Agent Pool (Spot VM, 自動擴展)
param agentNodeVmSize = 'Standard_D4s_v3'
param agentNodeMinCount = 0    // 無任務時縮減至 0
param agentNodeMaxCount = 5    // 最多 5 台

param enableMonitoring = true
param enableAcr = false
```

### 3. 部署 AKS

```bash
# 登入 Azure
az login

# 建立部署
az deployment sub create \
  --location eastasia \
  --template-file main.bicep \
  --parameters main.bicepparam

# 取得 AKS 憑證
az aks get-credentials \
  --resource-group rg-adoagent-prod \
  --name aks-adoagent-prod
```

### 4. 安裝 KEDA

```bash
# 執行 KEDA 安裝腳本
chmod +x scripts/install-keda.sh
./scripts/install-keda.sh

# 驗證 KEDA 安裝
kubectl get pods -n keda
```

### 5. 配置 Azure DevOps Agent

```bash
cd kubernetes

# 編輯 agent-deployment.yaml
# 更新以下欄位:
# - AZP_URL: https://dev.azure.com/your-organization
# - AZP_TOKEN: your-pat-token-here
# - AZP_POOL: Default (或您的 Pool 名稱)
```

### 6. 部署 Agent

```bash
# 建立 namespace
kubectl apply -f namespaces.yaml

# 部署 Agent
kubectl apply -f agent-deployment.yaml

# 檢查部署狀態
kubectl get pods -n azdevops-agents
kubectl get scaledobject -n azdevops-agents
```

## 📊 成本估算

| 項目 | 規格 | 數量 | 一般價格 | Spot 價格 |
|------|------|------|---------|----------|
| System Pool | B2s | 1 固定 | ~$30/月 | - |
| Agent Pool | D4s_v3 | 0-5 動態 | ~$140/月/台 | ~$29/月/台 |
| Storage | Managed Disk | - | ~$10/月 | ~$10/月 |
| **閒置時總計** | | | **~$40/月** | **~$40/月** |
| **滿載時總計** | | | **~$740/月** | **~$185/月** |

💡 **關鍵優勢**: 無任務時縮減至 0，只需支付 System Pool 費用！

## 🔧 管理指令

### 檢查 Agent 狀態
```bash
# 查看 Pods
kubectl get pods -n azdevops-agents

# 查看自動擴展狀態
kubectl get scaledobject -n azdevops-agents

# 查看 HPA (Horizontal Pod Autoscaler)
kubectl get hpa -n azdevops-agents
```

### 查看日誌
```bash
# 查看 Agent Pod 日誌
kubectl logs -n azdevops-agents -l app=azdevops-agent -f

# 查看 KEDA 日誌
kubectl logs -n keda -l app=keda-operator -f
```

### 手動調整副本數
```bash
# 暫時調整副本數 (會被 KEDA 覆蓋)
kubectl scale deployment azdevops-agent -n azdevops-agents --replicas=3

# 查看副本數
kubectl get deployment azdevops-agent -n azdevops-agents
```

### 更新 Agent 配置
```bash
# 編輯 ConfigMap
kubectl edit configmap azdevops-agent-config -n azdevops-agents

# 編輯 Secret
kubectl edit secret azdevops-agent-secret -n azdevops-agents

# 重啟 Pods 以套用變更
kubectl rollout restart deployment azdevops-agent -n azdevops-agents
```

## 🎯 KEDA 自動擴展說明

KEDA 會根據 Azure Pipelines 隊列中的待處理 Job 數量自動調整 Agent 數量：

| 待處理 Jobs | Agent Pods | 說明 |
|------------|-----------|------|
| 0 | 0 | 無任務，縮減至 0 |
| 1-3 | 1-3 | 每個 Job 一個 Pod |
| 4-10 | 4-10 | 最多擴展至 maxReplicas |
| >10 | 10 | 達到上限 |

調整參數 (在 `agent-deployment.yaml`):
```yaml
spec:
  minReplicaCount: 0           # 最小副本數
  maxReplicaCount: 10          # 最大副本數
  pollingInterval: 30          # 輪詢間隔 (秒)
  cooldownPeriod: 300          # 冷卻時間 (秒)
  targetPipelinesQueueLength: "1"  # 每個 Agent 處理的 Job 數
```

## 🔐 安全建議

1. **使用 Kubernetes Secret 儲存 PAT Token**
   ```bash
   kubectl create secret generic azdevops-agent-secret \
     --from-literal=AZP_TOKEN=<your-pat-token> \
     -n azdevops-agents
   ```

2. **啟用 Azure AD RBAC**
   - 已在 Bicep 中啟用: `enableAzureRBAC: true`

3. **限制網路存取**
   - 考慮使用 Network Policy 限制 Pod 間通訊

4. **定期更新 Agent 映像**
   ```bash
   kubectl set image deployment/azdevops-agent \
     agent=mcr.microsoft.com/azure-pipelines/vsts-agent:ubuntu-22.04 \
     -n azdevops-agents
   ```

## 📈 監控與警報

### 查看 Container Insights (如已啟用)
```bash
# 在 Azure Portal 中查看
# AKS Cluster → Insights → Containers
```

### 設定 Azure Monitor 警報
```bash
# 範例: CPU 使用率過高
az monitor metrics alert create \
  --name aks-cpu-alert \
  --resource-group rg-adoagent-prod \
  --scopes <aks-cluster-id> \
  --condition "avg Percentage CPU > 80" \
  --description "AKS CPU usage is high"
```

## 🧪 測試自動擴展

### 觸發 Pipeline 測試
1. 在 Azure DevOps 中建立測試 Pipeline
2. 指定使用您的 Agent Pool
3. 排隊多個 Pipeline runs
4. 觀察 Pods 自動增加:
   ```bash
   watch kubectl get pods -n azdevops-agents
   ```

### 驗證縮減至 0
1. 等待所有 Pipeline 完成
2. 等待 cooldownPeriod (預設 5 分鐘)
3. 確認 Pods 縮減至 0:
   ```bash
   kubectl get pods -n azdevops-agents
   # 應該顯示 No resources found
   ```

## 🧹 清理資源

```bash
# 刪除 Kubernetes 資源
kubectl delete namespace azdevops-agents
kubectl delete namespace keda

# 刪除 AKS 和相關資源
az group delete --name rg-adoagent-prod --yes --no-wait
```

## 📚 更多資訊

- [KEDA 官方文件](https://keda.sh/)
- [KEDA Azure Pipelines Scaler](https://keda.sh/docs/scalers/azure-pipelines/)
- [Azure DevOps Agent Container](https://learn.microsoft.com/azure/devops/pipelines/agents/docker)
- [AKS 最佳實踐](https://learn.microsoft.com/azure/aks/best-practices)

## ❓ 疑難排解

### KEDA 無法連線到 Azure DevOps
```bash
# 檢查 Secret
kubectl get secret azdevops-agent-secret -n azdevops-agents -o yaml

# 檢查 KEDA logs
kubectl logs -n keda -l app=keda-operator
```

### Agent 無法註冊
```bash
# 檢查 Pod logs
kubectl logs -n azdevops-agents <pod-name>

# 常見問題:
# 1. PAT Token 權限不足
# 2. Pool 名稱錯誤
# 3. Organization URL 格式錯誤
```

### Spot Node 被回收
```bash
# 檢查 node 狀態
kubectl get nodes

# Spot node 被回收時，Kubernetes 會自動在新 node 上重建 Pods
# 確保 minCount > 0 以維持可用性
```

### Pods 卡在 Pending 狀態
```bash
# 檢查 Pod 詳情
kubectl describe pod <pod-name> -n azdevops-agents

# 常見原因:
# 1. Node 資源不足 → 增加 maxCount
# 2. Toleration 設定錯誤 → 檢查 tolerations
# 3. Image pull 失敗 → 檢查網路連線
```
