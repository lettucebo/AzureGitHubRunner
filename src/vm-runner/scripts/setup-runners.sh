#!/bin/bash

################################################################################
# GitHub Actions Runner Setup Script
# 
# This script sets up multiple GitHub Self-hosted Runners on a single VM
# Each runner runs as a separate systemd service
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
if [ -z "$GITHUB_TOKEN" ]; then
    log_error "GITHUB_TOKEN environment variable is not set"
    exit 1
fi

if [ -z "$GITHUB_REPO_URL" ]; then
    log_error "GITHUB_REPO_URL environment variable is not set"
    exit 1
fi

if [ -z "$RUNNER_COUNT" ]; then
    log_warn "RUNNER_COUNT not set, defaulting to 3"
    RUNNER_COUNT=3
fi

# Configuration
RUNNER_USER="github-runner"
RUNNER_BASE_DIR="/opt"
RUNNER_ARCHIVE="/opt/actions-runner-temp/actions-runner-linux-x64.tar.gz"
RUNNER_NAME_PREFIX="azure-runner"

log_info "Starting GitHub Actions Runner setup"
log_info "Repository: $GITHUB_REPO_URL"
log_info "Number of runners: $RUNNER_COUNT"

# Detect if this is organization-level or repository-level
REPO_PATH=$(echo "$GITHUB_REPO_URL" | sed 's|https://github.com/||' | sed 's|/$||')
SLASH_COUNT=$(echo "$REPO_PATH" | tr -cd '/' | wc -c)

if [ "$SLASH_COUNT" -eq 0 ]; then
    # Organization-level runner
    RUNNER_LEVEL="organization"
    ORG_NAME="$REPO_PATH"
    API_ENDPOINT="orgs/$ORG_NAME/actions/runners/registration-token"
    log_info "Detected: Organization-level runner"
    log_info "Organization: $ORG_NAME"
else
    # Repository-level runner
    RUNNER_LEVEL="repository"
    OWNER=$(echo "$REPO_PATH" | cut -d'/' -f1)
    REPO=$(echo "$REPO_PATH" | cut -d'/' -f2)
    API_ENDPOINT="repos/$OWNER/$REPO/actions/runners/registration-token"
    log_info "Detected: Repository-level runner"
    log_info "Owner: $OWNER, Repo: $REPO"
fi

# Get runner registration token
log_info "Obtaining runner registration token..."

# Get registration token from GitHub API
REGISTRATION_TOKEN=$(curl -s -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/$API_ENDPOINT" \
    | jq -r '.token')

if [ -z "$REGISTRATION_TOKEN" ] || [ "$REGISTRATION_TOKEN" = "null" ]; then
    log_error "Failed to obtain registration token. Please check your GitHub token permissions."
    if [ "$RUNNER_LEVEL" = "organization" ]; then
        log_error "For organization-level runners, required permissions:"
        log_error "  - repo (Full control)"
        log_error "  - admin:org (Full control)"
    else
        log_error "For repository-level runners, required permissions:"
        log_error "  - repo (Full control)"
        log_error "  - admin:org (read:org)"
    fi
    exit 1
fi

log_info "Registration token obtained successfully"

# Setup each runner
for i in $(seq 1 $RUNNER_COUNT); do
    RUNNER_DIR="${RUNNER_BASE_DIR}/actions-runner-${i}"
    RUNNER_NAME="${RUNNER_NAME_PREFIX}-${i}"
    
    log_info "Setting up runner $i of $RUNNER_COUNT: $RUNNER_NAME"
    
    # Create runner directory
    if [ -d "$RUNNER_DIR" ]; then
        log_warn "Runner directory already exists: $RUNNER_DIR. Skipping..."
        continue
    fi
    
    mkdir -p "$RUNNER_DIR"
    
    # Extract runner package
    log_info "Extracting runner package to $RUNNER_DIR"
    tar xzf "$RUNNER_ARCHIVE" -C "$RUNNER_DIR"
    
    # Set ownership
    chown -R $RUNNER_USER:$RUNNER_USER "$RUNNER_DIR"
    
    # Configure runner
    log_info "Configuring runner: $RUNNER_NAME"
    
    # Run configuration as github-runner user
    su - $RUNNER_USER -c "cd $RUNNER_DIR && ./config.sh \
        --url $GITHUB_REPO_URL \
        --token $REGISTRATION_TOKEN \
        --name $RUNNER_NAME \
        --labels self-hosted,linux,x64,azure,runner-$i \
        --work _work \
        --unattended \
        --replace"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to configure runner: $RUNNER_NAME"
        continue
    fi
    
    log_info "Runner configured successfully: $RUNNER_NAME"
    
    # Install and start systemd service
    log_info "Installing systemd service for runner: $RUNNER_NAME"
    
    # Create service file
    cat > "/etc/systemd/system/actions-runner-${i}.service" <<EOF
[Unit]
Description=GitHub Actions Runner ${i}
After=network.target

[Service]
Type=simple
User=$RUNNER_USER
WorkingDirectory=$RUNNER_DIR
ExecStart=$RUNNER_DIR/run.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=actions-runner-${i}

# Environment variables
Environment="DOTNET_CLI_TELEMETRY_OPTOUT=1"
Environment="DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1"
Environment="NVM_DIR=/home/$RUNNER_USER/.nvm"

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd, enable and start service
    systemctl daemon-reload
    systemctl enable "actions-runner-${i}.service"
    systemctl start "actions-runner-${i}.service"
    
    # Check service status
    sleep 2
    if systemctl is-active --quiet "actions-runner-${i}.service"; then
        log_info "Runner service started successfully: actions-runner-${i}.service"
    else
        log_error "Runner service failed to start: actions-runner-${i}.service"
        log_error "Check logs with: journalctl -u actions-runner-${i}.service -n 50"
    fi
    
    echo ""
done

log_info "=========================================="
log_info "GitHub Actions Runner setup completed!"
log_info "=========================================="
log_info "Total runners configured: $RUNNER_COUNT"
log_info ""
log_info "To check runner status:"
log_info "  sudo systemctl status actions-runner-*.service"
log_info ""
log_info "To view logs for a specific runner:"
log_info "  sudo journalctl -u actions-runner-1.service -f"
log_info ""
log_info "To restart a runner:"
log_info "  sudo systemctl restart actions-runner-1.service"
log_info ""
log_info "Runners are now ready to accept jobs from GitHub Actions!"
log_info "=========================================="

exit 0
