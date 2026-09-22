#!/usr/bin/env bash
# ============================================================================
# 查詢 actions/runner release 並更新 runner-version.env
#
# 使用方式:
#   ./update-runner-version.sh            # 最新版
#   ./update-runner-version.sh 2.330.0    # 指定版本
# ============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="${SCRIPT_DIR}/../runner-image/runner-version.env"
ARCH="linux-x64"

usage() {
    cat <<'EOF'
用法: update-runner-version.sh [VERSION]

  VERSION   選填。actions/runner 版本 (例如 2.330.0)。省略時查詢最新 release。

更新 runner-image/runner-version.env 的 RUNNER_VERSION 與 RUNNER_SHA256。
EOF
}

resolve_version() {
    local requested="${1:-}"
    if [ -n "${requested}" ]; then
        echo "${requested}"
        return
    fi
    curl -fsSL "https://api.github.com/repos/actions/runner/releases/latest" \
        | python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))'
}

main() {
    if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
        usage
        exit 0
    fi

    log_step "步驟 1/3: 解析 runner 版本..."
    local version
    version="$(resolve_version "${1:-}")"
    if [ -z "${version}" ]; then
        log_error "❌ 無法解析 runner 版本"
        exit 1
    fi
    log_info "✓ 版本 ${version}"

    log_step "步驟 2/3: 取得 SHA256..."
    local asset_name="actions-runner-${ARCH}-${version}.tar.gz"
    local api_url="https://api.github.com/repos/actions/runner/releases/tags/v${version}"
    local sha
    sha="$(curl -fsSL "${api_url}" \
        | python3 -c 'import json, sys; data = json.load(sys.stdin); asset_name = sys.argv[1]; digest = next((asset.get("digest", "") for asset in data.get("assets", []) if asset.get("name") == asset_name), ""); digest or sys.exit(1); print(digest.split(":", 1)[1] if digest.startswith("sha256:") else digest)' "${asset_name}")"
    log_info "✓ SHA256 ${sha}"

    log_step "步驟 3/3: 寫入 ${VERSION_FILE}..."
    cat > "${VERSION_FILE}" <<EOF
# 由 scripts/update-runner-version.sh 產生，請勿手動編輯
RUNNER_VERSION=${version}
RUNNER_SHA256=${sha}
EOF
    log_info "✓ 完成"
}

main "$@"
