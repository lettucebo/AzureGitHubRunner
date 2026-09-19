#!/usr/bin/env bash
# ============================================================================
# 以 az acr build 在雲端建置 runner image（本機不需安裝 Docker）
#
# 使用方式:
#   export ACR_NAME="acracarunnerprodxxxx"
#   ./build-runner-image.sh
# ============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_DIR="${SCRIPT_DIR}/../runner-image"
ACR_NAME="${ACR_NAME:-}"
IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-github-runner}"

usage() {
    cat <<'EOF'
用法: build-runner-image.sh

必要環境變數:
  ACR_NAME            Azure Container Registry 名稱 (不含 .azurecr.io)

選用環境變數:
  IMAGE_REPOSITORY    image repository 名稱 (預設 github-runner)

image tag 使用目前 git commit SHA，禁止使用 latest。
EOF
}

main() {
    if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
        usage
        exit 0
    fi

    log_step "步驟 1/3: 檢查前置條件..."
    if [ -z "${ACR_NAME}" ]; then
        log_error "❌ 未設定 ACR_NAME"
        exit 1
    fi
    if ! command -v az >/dev/null 2>&1; then
        log_error "❌ az CLI 未安裝"
        exit 1
    fi
    # shellcheck source=/dev/null
    source "${IMAGE_DIR}/runner-version.env"
    if [ -z "${RUNNER_VERSION:-}" ] || [ -z "${RUNNER_SHA256:-}" ]; then
        log_error "❌ runner-version.env 不完整，請先執行 update-runner-version.sh"
        exit 1
    fi
    log_info "✓ runner 版本 ${RUNNER_VERSION}"

    log_step "步驟 2/3: 決定 image tag..."
    local tag
    tag="$(git -C "${SCRIPT_DIR}" rev-parse --short=12 HEAD)"
    if [ -n "$(git -C "${SCRIPT_DIR}" status --porcelain -- "${IMAGE_DIR}")" ]; then
        log_warn "⚠️ runner-image 有未提交變更，tag 加上 -dirty"
        tag="${tag}-dirty"
    fi
    log_info "✓ tag ${IMAGE_REPOSITORY}:${tag}"

    log_step "步驟 3/3: 執行 az acr build..."
    az acr build \
        --registry "${ACR_NAME}" \
        --image "${IMAGE_REPOSITORY}:${tag}" \
        --file "${IMAGE_DIR}/Dockerfile" \
        --build-arg "RUNNER_VERSION=${RUNNER_VERSION}" \
        --build-arg "RUNNER_SHA256=${RUNNER_SHA256}" \
        "${IMAGE_DIR}"

    log_info "✓ 完成 ${ACR_NAME}.azurecr.io/${IMAGE_REPOSITORY}:${tag}"
    log_info "  請把此字串填入 main.bicepparam 的 runnerImage 參數"
}

main "$@"
