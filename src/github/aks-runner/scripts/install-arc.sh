#!/bin/bash
# ============================================================================
# ARC (Actions Runner Controller) 安裝腳本
# ============================================================================
#
# 📌 特點:
#   - 使用 GitHub 官方 Runner Image (ghcr.io/actions/actions-runner)
#   - 無需自訂 image，開箱即用
#   - 支援 GitHub Actions 和 Copilot Coding Agent
#
# 📖 使用方式:
#   export GITHUB_PAT="ghp_xxxxxxxxxxxx"
#   export GITHUB_CONFIG_URL="https://github.com/your-org/your-repo"
#   ./install-arc.sh
#
# ============================================================================

set -e

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# ============================================================================
# 配置參數 (可透過環境變數覆寫)
# ============================================================================

# GitHub 配置 (必填)
GITHUB_CONFIG_URL="${GITHUB_CONFIG_URL:-}"
GITHUB_PAT="${GITHUB_PAT:-}"

# 可選配置
RUNNER_SCALE_SET_NAME="${RUNNER_SCALE_SET_NAME:-arc-runner-set}"
ARC_NAMESPACE="${ARC_NAMESPACE:-arc-systems}"
RUNNER_NAMESPACE="${RUNNER_NAMESPACE:-arc-runners}"
MIN_RUNNERS="${MIN_RUNNERS:-0}"
MAX_RUNNERS="${MAX_RUNNERS:-45}"

# 容器模式: "dind" (Docker-in-Docker) 或留空 (不需要 Docker)
CONTAINER_MODE="${CONTAINER_MODE:-dind}"

# ============================================================================
# 前置檢查
# ============================================================================

check_prerequisites() {
    log_step "步驟 1/4: 檢查前置條件..."
    
    local missing=0
    
    # 檢查 kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "❌ kubectl 未安裝"
        missing=1
    else
        log_info "✓ kubectl installed"
    fi
    
    # 檢查 helm
    if ! command -v helm &> /dev/null; then
        log_error "❌ helm 未安裝"
        missing=1
    else
        log_info "✓ helm installed"
    fi
    
    # 檢查 kubectl 連線
    if ! kubectl cluster-info &> /dev/null; then
        log_error "❌ 無法連接到 Kubernetes 叢集"
        log_error "   請先執行: az aks get-credentials --resource-group <rg> --name <aks>"
        missing=1
    else
        log_info "✓ Kubernetes 叢集連線正常"
    fi
    
    # 檢查必要環境變數
    if [[ -z "$GITHUB_CONFIG_URL" ]]; then
        log_error "❌ 未設定 GITHUB_CONFIG_URL"
        log_error "   範例: export GITHUB_CONFIG_URL=\"https://github.com/your-org/your-repo\""
        missing=1
    else
        log_info "✓ GITHUB_CONFIG_URL: $GITHUB_CONFIG_URL"
    fi
    
    if [[ -z "$GITHUB_PAT" ]]; then
        log_error "❌ 未設定 GITHUB_PAT"
        log_error "   範例: export GITHUB_PAT=\"ghp_xxxxxxxxxxxx\""
        missing=1
    else
        log_info "✓ GITHUB_PAT: ****${GITHUB_PAT: -4}"
    fi
    
    if [[ $missing -eq 1 ]]; then
        log_error ""
        log_error "請修正上述問題後重新執行"
        exit 1
    fi
    
    log_info "前置條件檢查通過 ✓"
    echo ""
}

# ============================================================================
# 安裝 ARC Controller
# ============================================================================

install_arc_controller() {
    log_step "步驟 2/4: 安裝 ARC Controller..."
    
    # 建立 namespace
    kubectl create namespace "${ARC_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    
    # 安裝/升級 ARC Controller (使用 GitHub 官方 Helm chart)
    # 注意: System Pool 有 CriticalAddonsOnly taint，需要添加 toleration
    log_info "安裝 gha-runner-scale-set-controller..."
    helm upgrade --install arc \
        --namespace "${ARC_NAMESPACE}" \
        --set "tolerations[0].key=CriticalAddonsOnly" \
        --set "tolerations[0].operator=Exists" \
        --set "tolerations[0].effect=NoSchedule" \
        --wait \
        oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller
    
    # 等待 controller 就緒
    log_info "等待 Controller 就緒..."
    sleep 10
    kubectl get pods -n "${ARC_NAMESPACE}"
    
    log_info "ARC Controller 安裝完成 ✓"
    echo ""
}

# ============================================================================
# 安裝 Runner Scale Set
# ============================================================================

install_runner_scale_set() {
    log_step "步驟 3/4: 安裝 Runner Scale Set..."
    
    # 建立 namespace
    kubectl create namespace "${RUNNER_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    
    # 建立 GitHub PAT Secret
    log_info "建立 GitHub PAT Secret..."
    kubectl create secret generic github-pat-secret \
        --namespace "${RUNNER_NAMESPACE}" \
        --from-literal=github_token="${GITHUB_PAT}" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_info "Runner Scale Set 設定:"
    log_info "  - 名稱: ${RUNNER_SCALE_SET_NAME}"
    log_info "  - 最小 Runners: ${MIN_RUNNERS}"
    log_info "  - 最大 Runners: ${MAX_RUNNERS}"
    log_info "  - 容器模式: ${CONTAINER_MODE:-'無 (標準)'}"
    
    # 生成 values 檔案 (Listener Pod 需要完整的 listenerTemplate 配置)
    local values_file="/tmp/arc-runner-values.yaml"
    cat > "${values_file}" <<EOF
# ARC Runner Scale Set 配置
githubConfigUrl: "${GITHUB_CONFIG_URL}"
githubConfigSecret: "github-pat-secret"
minRunners: ${MIN_RUNNERS}
maxRunners: ${MAX_RUNNERS}
runnerScaleSetName: "${RUNNER_SCALE_SET_NAME}"

# Runner Pod 配置 (在 Spot VM Pool 執行)
template:
  spec:
    nodeSelector:
      nodepool-type: runner
    tolerations:
      - key: "kubernetes.azure.com/scalesetpriority"
        operator: "Equal"
        value: "spot"
        effect: "NoSchedule"

# Listener Pod 配置 (在 System Pool 執行)
# 注意: listenerTemplate 必須包含 containers，否則無法設定 tolerations
listenerTemplate:
  spec:
    containers:
      - name: listener
        resources: {}
    tolerations:
      - key: "CriticalAddonsOnly"
        operator: "Exists"
        effect: "NoSchedule"
EOF
    
    # 如果啟用 Docker-in-Docker 模式，添加到 values
    if [[ "${CONTAINER_MODE}" == "dind" ]]; then
        log_info "啟用 Docker-in-Docker 模式..."
        cat >> "${values_file}" <<EOF

# Docker-in-Docker 模式 (支援 container jobs)
containerMode:
  type: "dind"
EOF
    fi
    
    log_info "使用 values 檔案: ${values_file}"
    cat "${values_file}"
    echo ""
    
    # 安裝/升級 Runner Scale Set
    helm upgrade --install "${RUNNER_SCALE_SET_NAME}" \
        --namespace "${RUNNER_NAMESPACE}" \
        -f "${values_file}" \
        --wait \
        oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
    
    # 清理暫存檔案
    rm -f "${values_file}"
    
    log_info "Runner Scale Set 安裝完成 ✓"
    echo ""
}

# ============================================================================
# 驗證安裝
# ============================================================================

verify_installation() {
    log_step "步驟 4/4: 驗證安裝..."
    
    echo ""
    echo "=== ARC Controller Pods ==="
    kubectl get pods -n "${ARC_NAMESPACE}"
    
    echo ""
    echo "=== Runner Namespace Pods ==="
    kubectl get pods -n "${RUNNER_NAMESPACE}"
    
    echo ""
    echo "=========================================="
    echo -e "${GREEN}🎉 安裝完成！${NC}"
    echo "=========================================="
    echo ""
    echo "📋 重要資訊:"
    echo "   Runner Scale Set 名稱: ${RUNNER_SCALE_SET_NAME}"
    echo "   GitHub 配置 URL: ${GITHUB_CONFIG_URL}"
    echo "   使用的 Runner Image: ghcr.io/actions/actions-runner:latest (官方)"
    echo ""
    echo "📝 下一步 - 更新您的 GitHub workflow:"
    echo ""
    echo "   jobs:"
    echo "     build:"
    echo "       runs-on: ${RUNNER_SCALE_SET_NAME}  # <-- 使用這個名稱"
    echo "       steps:"
    echo "         - uses: actions/checkout@v4"
    echo "         # ... 其他步驟"
    echo ""
    echo "🔍 監控 Runner Pods:"
    echo "   kubectl get pods -n ${RUNNER_NAMESPACE} -w"
    echo ""
    echo "📊 查看 Runner 狀態:"
    echo "   kubectl get autoscalingrunnersets -n ${RUNNER_NAMESPACE}"
    echo ""
}

# ============================================================================
# 顯示說明
# ============================================================================

show_help() {
    echo "ARC (Actions Runner Controller) 安裝腳本"
    echo ""
    echo "使用方式:"
    echo "  export GITHUB_PAT=\"ghp_xxxxxxxxxxxx\""
    echo "  export GITHUB_CONFIG_URL=\"https://github.com/your-org/your-repo\""
    echo "  ./install-arc.sh"
    echo ""
    echo "環境變數:"
    echo "  GITHUB_CONFIG_URL    GitHub repository/org URL (必填)"
    echo "  GITHUB_PAT           GitHub Personal Access Token (必填)"
    echo "  RUNNER_SCALE_SET_NAME  Runner 名稱 (預設: arc-runner-set)"
    echo "  MIN_RUNNERS          最小 runner 數量 (預設: 0)"
    echo "  MAX_RUNNERS          最大 runner 數量 (預設: 45)"
    echo "  CONTAINER_MODE       容器模式: dind 或留空 (預設: dind)"
    echo ""
}

# ============================================================================
# 主程式
# ============================================================================

main() {
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        show_help
        exit 0
    fi
    
    echo ""
    echo "============================================"
    echo "  ARC (Actions Runner Controller) 安裝程式"
    echo "  使用 GitHub 官方 Runner Image"
    echo "============================================"
    echo ""
    
    check_prerequisites
    install_arc_controller
    install_runner_scale_set
    verify_installation
}

# 執行主程式
main "$@"
