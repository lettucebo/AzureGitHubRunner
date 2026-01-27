#!/bin/bash

################################################################################
# KEDA Installation Script for Azure DevOps Agents
# This script installs KEDA (Kubernetes Event Driven Autoscaling) into AKS
################################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_info "=========================================="
log_info "Installing KEDA for Azure DevOps Agents"
log_info "=========================================="

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl is not installed. Please install kubectl first."
    exit 1
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    log_error "Helm is not installed. Please install Helm first."
    exit 1
fi

# Add KEDA Helm repository
log_info "Adding KEDA Helm repository..."
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

# Create namespace for KEDA
log_info "Creating keda namespace..."
kubectl create namespace keda --dry-run=client -o yaml | kubectl apply -f -

# Install KEDA
log_info "Installing KEDA..."
helm upgrade --install keda kedacore/keda \
    --namespace keda \
    --version 2.14.0 \
    --set watchNamespace="" \
    --wait

if [ $? -ne 0 ]; then
    log_error "Failed to install KEDA"
    exit 1
fi

log_info "KEDA installed successfully!"

# Verify KEDA installation
log_info "Verifying KEDA installation..."
kubectl get pods -n keda

log_info "=========================================="
log_info "KEDA Installation Complete!"
log_info "=========================================="
log_info ""
log_info "Next steps:"
log_info "1. Create Azure DevOps agent pool and PAT token"
log_info "2. Update kubernetes/agent-values.yaml with your Azure DevOps configuration"
log_info "3. Run: kubectl apply -f kubernetes/"
log_info ""

exit 0
