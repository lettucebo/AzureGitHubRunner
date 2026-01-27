#!/bin/bash

################################################################################
# Azure DevOps Pipeline Agent Setup Script
# 
# This script sets up multiple Azure DevOps Self-hosted Agents on a single VM
# Each agent runs as a separate systemd service
################################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions for colored output
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check required environment variables
if [ -z "$AZURE_DEVOPS_URL" ]; then
    log_error "AZURE_DEVOPS_URL environment variable is not set"
    exit 1
fi

if [ -z "$AZURE_DEVOPS_TOKEN" ]; then
    log_error "AZURE_DEVOPS_TOKEN environment variable is not set"
    exit 1
fi

if [ -z "$AZURE_DEVOPS_POOL_NAME" ]; then
    log_warn "AZURE_DEVOPS_POOL_NAME not set, defaulting to 'Default'"
    AZURE_DEVOPS_POOL_NAME="Default"
fi

if [ -z "$AGENT_COUNT" ]; then
    log_warn "AGENT_COUNT not set, defaulting to 3"
    AGENT_COUNT=3
fi

# Configuration
AGENT_USER="azdevops"
AGENT_BASE_DIR="/opt"
AGENT_NAME_PREFIX="azure-agent"
AGENT_VERSION="3.236.1"
AGENT_DOWNLOAD_URL="https://vstsagentpackage.azureedge.net/agent/${AGENT_VERSION}/vsts-agent-linux-x64-${AGENT_VERSION}.tar.gz"

log_info "Starting Azure DevOps Pipeline Agent setup"
log_info "Organization URL: $AZURE_DEVOPS_URL"
log_info "Agent Pool: $AZURE_DEVOPS_POOL_NAME"
log_info "Number of agents: $AGENT_COUNT"

# Create agent user if not exists
if ! id "$AGENT_USER" &>/dev/null; then
    log_info "Creating user: $AGENT_USER"
    useradd -m -s /bin/bash "$AGENT_USER"
else
    log_info "User already exists: $AGENT_USER"
fi

# Download agent package
log_info "Downloading Azure DevOps agent package..."
AGENT_TEMP_DIR="/tmp/azdevops-agent"
mkdir -p "$AGENT_TEMP_DIR"
cd "$AGENT_TEMP_DIR"

curl -fsSL -o vsts-agent.tar.gz "$AGENT_DOWNLOAD_URL"

if [ $? -ne 0 ]; then
    log_error "Failed to download agent package from: $AGENT_DOWNLOAD_URL"
    exit 1
fi

log_info "Agent package downloaded successfully"

# Setup each agent
for i in $(seq 1 $AGENT_COUNT); do
    AGENT_DIR="${AGENT_BASE_DIR}/azdevops-agent-${i}"
    AGENT_NAME="${AGENT_NAME_PREFIX}-${i}"
    
    log_info "Setting up agent $i of $AGENT_COUNT: $AGENT_NAME"
    
    # Create agent directory
    if [ -d "$AGENT_DIR" ]; then
        log_warn "Agent directory already exists: $AGENT_DIR. Removing and recreating..."
        rm -rf "$AGENT_DIR"
    fi
    
    mkdir -p "$AGENT_DIR"
    
    # Extract agent package
    log_info "Extracting agent package to $AGENT_DIR"
    tar xzf "$AGENT_TEMP_DIR/vsts-agent.tar.gz" -C "$AGENT_DIR"
    
    # Set ownership
    chown -R $AGENT_USER:$AGENT_USER "$AGENT_DIR"
    
    # Install dependencies
    log_info "Installing agent dependencies..."
    cd "$AGENT_DIR"
    ./bin/installdependencies.sh
    
    # Configure agent
    log_info "Configuring agent: $AGENT_NAME"
    
    # Run configuration as azdevops user
    su - $AGENT_USER -c "cd $AGENT_DIR && ./config.sh \
        --unattended \
        --url $AZURE_DEVOPS_URL \
        --auth pat \
        --token $AZURE_DEVOPS_TOKEN \
        --pool $AZURE_DEVOPS_POOL_NAME \
        --agent $AGENT_NAME \
        --replace \
        --acceptTeeEula"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to configure agent: $AGENT_NAME"
        continue
    fi
    
    log_info "Agent configured successfully: $AGENT_NAME"
    
    # Install and start systemd service
    log_info "Installing systemd service for agent: $AGENT_NAME"
    
    # Use the built-in service installation script
    cd "$AGENT_DIR"
    ./svc.sh install $AGENT_USER
    
    # Start the service
    ./svc.sh start
    
    # Check service status
    sleep 2
    SERVICE_NAME="vsts.agent.$(echo $AZURE_DEVOPS_URL | sed 's|https://||' | sed 's|/||g').${AZURE_DEVOPS_POOL_NAME}.${AGENT_NAME}.service"
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        log_info "Agent service started successfully: $SERVICE_NAME"
    else
        log_error "Agent service failed to start: $SERVICE_NAME"
        log_error "Check logs with: journalctl -u $SERVICE_NAME -n 50"
    fi
    
    echo ""
done

# Cleanup
log_info "Cleaning up temporary files..."
rm -rf "$AGENT_TEMP_DIR"

log_info "=========================================="
log_info "Azure DevOps Pipeline Agent setup completed!"
log_info "=========================================="
log_info "Total agents configured: $AGENT_COUNT"
log_info ""
log_info "To check agent status:"
log_info "  sudo systemctl status vsts.agent.*.service"
log_info ""
log_info "To view logs for a specific agent:"
log_info "  sudo journalctl -u vsts.agent.*.${AGENT_NAME_PREFIX}-1.service -f"
log_info ""
log_info "To restart an agent:"
log_info "  cd ${AGENT_BASE_DIR}/azdevops-agent-1 && sudo ./svc.sh restart"
log_info ""
log_info "Agents are now ready to accept jobs from Azure Pipelines!"
log_info "=========================================="

exit 0
