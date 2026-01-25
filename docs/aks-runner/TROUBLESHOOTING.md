[繁體中文](TROUBLESHOOTING_zh-tw.md) | **English**

---

# AKS + ARC Troubleshooting Guide

Problems and solutions you may encounter during deployment.

---

## Table of Contents

- [AKS + ARC Troubleshooting Guide](#aks--arc-troubleshooting-guide)
  - [Table of Contents](#table-of-contents)
  - [Kubernetes 版本不支援](#kubernetes-版本不支援)
    - [症狀](#症狀)
    - [原因](#原因)
    - [解決方案](#解決方案)
  - [ARC Controller Pod Pending](#arc-controller-pod-pending)
    - [症狀](#症狀-1)
    - [原因](#原因-1)
    - [解決方案](#解決方案-1)
  - [Listener Pod Pending](#listener-pod-pending)
    - [症狀](#症狀-2)
    - [原因](#原因-2)
    - [⚠️ 重要注意事項](#️-重要注意事項)
    - [解決方案](#解決方案-2)
  - [Runner Pod Pending](#runner-pod-pending)
    - [症狀](#症狀-3)
    - [原因 1: Runner Pool 沒有節點](#原因-1-runner-pool-沒有節點)
    - [解決方案 1](#解決方案-1)
    - [原因 2: 缺少 Spot VM toleration](#原因-2-缺少-spot-vm-toleration)
    - [解決方案 2](#解決方案-2)
  - [GitHub 無法連接到 Runner](#github-無法連接到-runner)
    - [症狀](#症狀-4)
    - [檢查步驟](#檢查步驟)
    - [常見原因](#常見原因)
  - [Runner Scale Set 註冊失敗](#runner-scale-set-註冊失敗)
    - [症狀](#症狀-5)
    - [解決方案](#解決方案-3)
  - [有用的診斷命令](#有用的診斷命令)
  - [Runner Startup Too Slow](#runner-startup-too-slow)
    - [Symptoms](#symptoms-6)
    - [Cause](#cause-3)
    - [Solution](#solution-4)

---

## Kubernetes 版本不支援

### 症狀

部署 AKS 時出現錯誤：

```
InvalidParameter: The value of parameter kubernetesVersion is invalid.
```

### 原因

不同 Azure 區域支援的 Kubernetes 版本不同。例如 East Asia 可能不支援 1.35+。

### 解決方案

1. 檢查區域支援的版本：

```powershell
az aks get-versions --location eastasia --output table
```

2. 修改 `main.bicepparam` 中的 `kubernetesVersion` 為支援的版本

3. 重新部署

---

## ARC Controller Pod Pending

### 症狀

```
kubectl get pods -n arc-systems
NAME                                   READY   STATUS    RESTARTS   AGE
arc-gha-rs-controller-xxx              0/1     Pending   0          5m
```

### 原因

System Pool 有 `CriticalAddonsOnly=true:NoSchedule` taint，Controller Pod 沒有對應的 toleration。

### 解決方案

重新安裝 ARC Controller 並添加 toleration：

```powershell
helm upgrade --install arc --namespace arc-systems `
  --set "tolerations[0].key=CriticalAddonsOnly" `
  --set "tolerations[0].operator=Exists" `
  --set "tolerations[0].effect=NoSchedule" `
  --wait `
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller
```

---

## Listener Pod Pending

### 症狀

```
kubectl get pods -n arc-systems
NAME                                   READY   STATUS    RESTARTS   AGE
arc-gha-rs-controller-xxx              1/1     Running   0          5m
arc-runner-set-xxx-listener            0/1     Pending   0          2m
```

使用 `kubectl describe pod` 查看：

```
Warning  FailedScheduling  0/1 nodes are available: 1 node(s) had untolerated taint {CriticalAddonsOnly: true}
```

### 原因

Listener Pod 也需要 CriticalAddonsOnly toleration。

### ⚠️ 重要注意事項

**不能使用 `--set` 添加 Listener toleration**，因為 `listenerTemplate.spec.containers` 是必填欄位。

錯誤示範：
```powershell
# ❌ 這會失敗！
helm upgrade --install arc-runner-set ... `
  --set "listenerTemplate.spec.tolerations[0].key=CriticalAddonsOnly"
```

錯誤訊息：
```
Error: AutoscalingRunnerSet.actions.github.com "arc-runner-set" is invalid: 
spec.listenerTemplate.spec.containers: Required value
```

### 解決方案

**必須使用 values 檔案**：

1. 建立或複製 values 檔案：

```powershell
Copy-Item src/aks-runner/kubernetes/arc-runner-values.yaml.example -Destination arc-runner-values.yaml
```

2. 編輯 `arc-runner-values.yaml`，確保包含完整的 `listenerTemplate`：

```yaml
listenerTemplate:
  spec:
    containers:
      - name: listener
        resources: {}
    tolerations:
      - key: "CriticalAddonsOnly"
        operator: "Exists"
        effect: "NoSchedule"
```

3. 重新安裝：

```powershell
helm upgrade --install arc-runner-set --namespace arc-runners `
  -f arc-runner-values.yaml `
  --wait `
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

---

## Runner Pod Pending

### 症狀

觸發 workflow 後，Runner Pod 卡在 Pending：

```
kubectl get pods -n arc-runners
NAME                           READY   STATUS    RESTARTS   AGE
arc-runner-set-xxx-runner-xxx  0/1     Pending   0          5m
```

### 原因 1: Runner Pool 沒有節點

Spot VM Pool 設定為 min=0，如果沒有 workflow 觸發，不會有節點。

### 解決方案 1

手動 scale up：

```powershell
az aks nodepool scale `
  --resource-group rg-ghrunner-prod `
  --cluster-name aks-ghrunner-prod `
  --name runner `
  --node-count 1
```

### 原因 2: 缺少 Spot VM toleration

Runner Pool 有 `kubernetes.azure.com/scalesetpriority=spot:NoSchedule` taint。

### 解決方案 2

確保 values 檔案中有正確的 toleration：

```yaml
template:
  spec:
    tolerations:
      - key: "kubernetes.azure.com/scalesetpriority"
        operator: "Equal"
        value: "spot"
        effect: "NoSchedule"
```

---

## GitHub 無法連接到 Runner

### 症狀

- GitHub Actions 頁面顯示 "Waiting for a runner to pick up this job..."
- Runner Scale Set 狀態一直是空的

### 檢查步驟

1. 確認 Runner Scale Set 已向 GitHub 註冊：

```powershell
kubectl get autoscalingrunnersets -n arc-runners -o jsonpath='{.items[0].metadata.annotations.runner-scale-set-id}'
```

如果有輸出 ID（如 `1`），表示已註冊成功。

2. 檢查 Listener Pod 日誌：

```powershell
kubectl logs -n arc-systems -l app.kubernetes.io/component=runner-scale-set-listener -f
```

### 常見原因

1. **PAT token 權限不足**
   - 需要 `Administration: Read and write` 權限
   
2. **PAT token 是空的**
   - 確認環境變數有正確設定
   - 檢查 secret：
     ```powershell
     kubectl get secret github-pat-secret -n arc-runners -o jsonpath='{.data.github_token}' | 
       ForEach-Object { [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)).Length }
     ```
   - 應該輸出 token 長度（如 93）

3. **githubConfigUrl 格式錯誤**
   - 正確格式：`https://github.com/owner/repo` 或 `https://github.com/org`

---

## Runner Scale Set 註冊失敗

### 症狀

安裝 Runner Scale Set 時出錯，或 `runner-scale-set-id` annotation 是空的。

### 解決方案

1. 檢查 Controller 日誌：

```powershell
kubectl logs -n arc-systems -l app.kubernetes.io/name=gha-rs-controller --tail=50
```

2. 確認 PAT token 有效：
   - 前往 GitHub → Settings → Developer settings → Personal access tokens
   - 確認 token 沒有過期
   - 確認有正確的 repository 權限

3. 重新建立 secret：

```powershell
kubectl delete secret github-pat-secret -n arc-runners
kubectl create secret generic github-pat-secret `
  --namespace arc-runners `
  --from-literal=github_token="$env:GITHUB_PAT"
```

4. 重啟 Controller：

```powershell
kubectl rollout restart deployment -n arc-systems
```

---

## Runner Startup Too Slow

### Symptoms

Every time a GitHub Actions workflow is triggered, it takes 3-5 minutes before the job starts executing because the Runner needs to start from scratch.

### Cause

The default configuration has `minRunners` set to `0`, which means all Runners scale down to zero when idle. When a new job arrives, the system needs to start a new Pod, including pulling images and initializing containers, causing significant delay.

### Solution

Set `minRunners` to at least `5` to ensure sufficient Runners are always online and ready:

#### Method 1: Update via Helm command

```powershell
helm upgrade arc-runner-set `
  --namespace arc-runners `
  --reuse-values `
  --set minRunners=5 `
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

#### Method 2: Update via values file

Edit `arc-runner-values.yaml`:

```yaml
minRunners: 5      # Keep at least 5 Runners online
maxRunners: 45     # Maximum concurrent Runners
```

Then update:

```powershell
helm upgrade arc-runner-set `
  --namespace arc-runners `
  -f src/aks-runner/kubernetes/arc-runner-values.yaml `
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

#### Verification

```powershell
# Check Runner count
kubectl get pods -n arc-runners

# Verify configuration
helm get values arc-runner-set -n arc-runners
```

#### Cost Considerations

- ✅ **Benefit**: Jobs execute immediately without initialization wait
- ✅ **Benefit**: Consistent CI/CD workflow experience
- 💰 **Cost**: 5 Runners will run continuously (relatively low cost with Spot VMs)
- 💡 **Recommendation**: Adjust `minRunners` based on your actual usage frequency

---

## 有用的診斷命令

```powershell
# 查看所有 ARC 相關資源
kubectl get all -n arc-systems
kubectl get all -n arc-runners

# 查看 AutoScalingRunnerSet 狀態
kubectl get autoscalingrunnersets -n arc-runners -o wide

# 查看 EphemeralRunnerSet
kubectl get ephemeralrunnersets -n arc-runners

# 查看節點和 taints
kubectl get nodes -o custom-columns='NAME:.metadata.name,TAINTS:.spec.taints[*].key'

# 查看特定 Pod 的事件
kubectl describe pod <pod-name> -n <namespace>

# 即時監控 Pods
kubectl get pods -n arc-systems -w
kubectl get pods -n arc-runners -w
```
