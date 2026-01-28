---
applyTo: "**/*.{test,spec}.{ts,sh,ps1}"
---
# 測試與驗證指引

## Bicep 驗證
```bash
az bicep build --file main.bicep
az deployment sub validate --location eastasia --template-file main.bicep --parameters main.bicepparam
az deployment sub what-if --location eastasia --template-file main.bicep --parameters main.bicepparam
```

## Terraform 驗證
```bash
terraform fmt -check
terraform validate
terraform plan
```

## YAML 驗證
```bash
kubectl apply --dry-run=client -f kubernetes/
python3 -c "import yaml; yaml.safe_load(open('scripts/cloud-init.yml'))"
```

## 手動驗證清單
- [ ] 語法檢查通過
- [ ] Validation/What-if 正常
- [ ] 實際部署成功
- [ ] Runner/Agent pods/services 運行中
- [ ] 能接收並執行 jobs

### 使用 tflint
```bash
# 安裝 tflint
winget install tflint

# 執行 lint
tflint --init
tflint
```

## Bash Script 測試

### ShellCheck 靜態分析
```bash
# 安裝 shellcheck
sudo apt install shellcheck

# 檢查腳本
shellcheck scripts/*.sh
```

### 語法檢查
```bash
# Bash 語法檢查
bash -n scripts/install-arc.sh

# 執行 dry run (如果腳本支援)
DRY_RUN=true bash scripts/install-arc.sh
```

## YAML 驗證

### Kubernetes YAML
```bash
# 使用 kubectl 驗證
kubectl apply --dry-run=client -f kubernetes/

# 使用 yamllint
yamllint kubernetes/*.yaml
```

### Cloud-init YAML
```bash
# 檢查 YAML 語法
python3 -c "import yaml; yaml.safe_load(open('scripts/cloud-init.yml'))"

# 使用 cloud-init 工具驗證
cloud-init devel schema --config-file scripts/cloud-init.yml
```

## CI/CD 驗證

### GitHub Actions Workflow
```yaml
# .github/workflows/ci-bicep.yml
name: Bicep Validation

on: [push, pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Azure CLI
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      
      - name: Validate Bicep
        run: |
          cd src/github/aks-runner
          az bicep build --file main.bicep
          
      - name: Bicep What-if
        run: |
          cd src/github/aks-runner
          az deployment sub what-if \
            --location eastasia \
            --template-file main.bicep \
            --parameters main.bicepparam.example
```

### Terraform Workflow
```yaml
# .github/workflows/ci-terraform.yml
name: Terraform Validation

on: [push, pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
      
      - name: Terraform Format
        run: |
          cd src/github/vm-runner
          terraform fmt -check
      
      - name: Terraform Validate
        run: |
          cd src/github/vm-runner
          terraform init -backend=false
          terraform validate
```

## 手動部署測試

### 測試檢查清單

#### Bicep 部署
- [ ] Bicep 語法檢查通過
- [ ] What-if 分析正常
- [ ] Validation 通過
- [ ] 實際部署成功
- [ ] AKS cluster 可連線
- [ ] Runner/Agent pods 正常運行
- [ ] Runner/Agent 能接收 jobs

#### Terraform 部署
- [ ] Terraform 格式檢查通過
- [ ] Terraform validate 通過
- [ ] Terraform plan 正常
- [ ] Terraform apply 成功
- [ ] VM 可 SSH 連線
- [ ] Runners/Agents systemd service 運行中
- [ ] Runners/Agents 顯示在 GitHub/Azure DevOps

### 驗證腳本範例

#### 驗證 AKS Runner
```bash
#!/bin/bash
# verify-aks-runner.sh

set -e

echo "🔍 驗證 AKS Runner 部署..."

# 1. 檢查 AKS 連線
echo "檢查 AKS 連線..."
kubectl get nodes

# 2. 檢查 namespace
echo "檢查 namespace..."
kubectl get ns arc-systems arc-runners

# 3. 檢查 ARC controller
echo "檢查 ARC controller..."
kubectl get pods -n arc-systems

# 4. 檢查 Runner pods
echo "檢查 Runner pods..."
kubectl get pods -n arc-runners

# 5. 檢查 Runner scale set
echo "檢查 Runner scale set..."
kubectl get runners -n arc-runners

echo "✅ 驗證完成"
```

#### 驗證 VM Runner
```bash
#!/bin/bash
# verify-vm-runner.sh

set -e

echo "🔍 驗證 VM Runner 部署..."

# 1. 檢查 systemd services
echo "檢查 systemd services..."
systemctl list-units --type=service --state=running | grep runner

# 2. 檢查 runner 進程
echo "檢查 runner 進程..."
ps aux | grep Runner.Listener

# 3. 檢查 runner 日誌
echo "檢查最近日誌..."
for i in {1..3}; do
    echo "=== Runner $i ==="
    journalctl -u actions.runner.*.runner-$i.service --no-pager -n 10
done

echo "✅ 驗證完成"
```

## 故障排除驗證

### 常見檢查命令

#### AKS
```bash
# 檢查 pod 狀態
kubectl get pods -A

# 檢查 pod 日誌
kubectl logs -n arc-runners <pod-name>

# 檢查 events
kubectl get events -n arc-runners --sort-by='.lastTimestamp'

# 檢查 node 狀態
kubectl describe node <node-name>
```

#### VM
```bash
# 檢查 cloud-init 日誌
sudo cat /var/log/cloud-init-output.log

# 檢查 systemd service 狀態
systemctl status actions.runner.*.service

# 檢查 runner 日誌
journalctl -u actions.runner.*.runner-1.service -f
```

## 效能測試

### 負載測試 (可選)
```bash
# 觸發多個 workflow jobs 測試自動擴展
for i in {1..10}; do
  gh workflow run ci.yml
done

# 監控 pod 擴展
watch kubectl get pods -n arc-runners
```

### 成本監控
```bash
# 檢查 Spot VM 搶佔情況
az vm list -d --query "[?powerState=='VM deallocated'].{name:name, reason:reason}"

# 監控 AKS 節點數量
az aks show --resource-group <rg> --name <aks> --query "agentPoolProfiles[].count"
```
