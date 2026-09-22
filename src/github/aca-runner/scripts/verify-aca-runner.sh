#!/usr/bin/env bash
# ============================================================================
# ACA Runner 部署後驗證
#
# 使用方式:
#   export RESOURCE_GROUP="rg-acarunner-prod"
#   export JOB_NAME="caj-acarunner-general-prod"
#   ./verify-aca-runner.sh
# ============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

RESOURCE_GROUP="${RESOURCE_GROUP:-}"
JOB_NAME="${JOB_NAME:-}"
failures=0
JOB_JSON=""

usage() {
    cat <<'EOF'
用法: verify-aca-runner.sh

必要環境變數:
  RESOURCE_GROUP   ACA runner 的 resource group
  JOB_NAME         Container Apps Job 名稱

說明:
  1. 檢查 triggerType、minExecutions、noDefaultLabels、runnerScope
  2. 確認掛載的 UAMI 之 identitySettings lifecycle 為 None
     (main container 不得透過 identity endpoint 取得該身分並重新讀取 Key Vault PAT)
  3. 確認 image 使用明確且非 latest 的 tag，或 @sha256 digest
  4. 列出 executions 供人工檢視
EOF
}

require_command() {
    local command_name="$1"
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        log_error "❌ 找不到 ${command_name}，請先安裝"
        exit 1
    fi
}

to_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

check_equal() {
    local name="$1"
    local expected="$2"
    local actual="$3"

    if [ "$(to_lower "${expected}")" = "$(to_lower "${actual}")" ]; then
        log_info "✓ ${name}: ${actual}"
    else
        log_error "❌ ${name}: 預期 '${expected}'，實際 '${actual}'"
        failures=$((failures + 1))
    fi
}

extract_job_field() {
    local field_name="$1"
    local filter="$2"
    local value

    if ! value="$(printf '%s' "${JOB_JSON}" | jq -er "${filter}")"; then
        log_error "❌ 解析 ${field_name} 失敗"
        return 1
    fi

    printf '%s' "${value}"
}

# 確認 Job 掛載的 UAMI 之 identitySettings lifecycle 為 None。
# 以 .identity.userAssignedIdentities 實際掛載的 identity 為準做對應，
# 不得只檢查 identitySettings 清單中任意一筆，避免漏掉真正被掛載但設定錯誤的身分。
check_identity_lifecycle() {
    local identity_key
    local lifecycle

    if ! identity_key="$(printf '%s' "${JOB_JSON}" | jq -er '.identity.userAssignedIdentities | keys[0] // empty')"; then
        log_error "❌ Job 未掛載任何 user-assigned managed identity"
        failures=$((failures + 1))
        return
    fi

    if ! lifecycle="$(printf '%s' "${JOB_JSON}" | jq -er --arg key "$(to_lower "${identity_key}")" '
        (.properties.configuration.identitySettings // [])
        | map(select((.identity | ascii_downcase) == $key))
        | (.[0].lifecycle // "MISSING")
    ')"; then
        log_error "❌ 解析 identitySettings 失敗"
        failures=$((failures + 1))
        return
    fi

    check_equal "identitySettings[UAMI].lifecycle" "None" "${lifecycle}"
}

check_image_reference() {
    local image="$1"
    local last_segment
    local tag
    local image_lower
    local image_name
    local digest

    if [ -z "${image}" ]; then
        log_error "❌ image 不可為空"
        failures=$((failures + 1))
        return
    fi

    if [[ "${image}" == *@sha256:* ]]; then
        image_name="${image%@sha256:*}"
        digest="${image##*@sha256:}"
        if [ -n "${image_name}" ] && [ -n "${digest}" ]; then
            log_info "✓ image: ${image}"
        else
            log_error "❌ image digest 格式無效: ${image}"
            failures=$((failures + 1))
        fi
        return
    fi

    last_segment="${image##*/}"
    if [[ "${last_segment}" != *:* ]]; then
        log_error "❌ image 必須指定明確 tag 或 @sha256 digest: ${image}"
        failures=$((failures + 1))
        return
    fi

    tag="${last_segment##*:}"
    image_lower="$(to_lower "${tag}")"
    if [ -z "${tag}" ]; then
        log_error "❌ image tag 不可為空: ${image}"
        failures=$((failures + 1))
    elif [ "${image_lower}" = "latest" ]; then
        log_error "❌ image 禁止使用 latest tag: ${image}"
        failures=$((failures + 1))
    else
        log_info "✓ image: ${image}"
    fi
}

main() {
    if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
        usage
        exit 0
    fi

    require_command az
    require_command jq

    if [ -z "${RESOURCE_GROUP}" ] || [ -z "${JOB_NAME}" ]; then
        log_error "❌ 必須設定 RESOURCE_GROUP 與 JOB_NAME"
        exit 1
    fi

    log_step "步驟 1/4: 讀取 Job 設定..."
    if ! JOB_JSON="$(az containerapp job show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${JOB_NAME}" \
        --only-show-errors \
        -o json)"; then
        log_error "❌ 讀取 Job 設定失敗"
        exit 1
    fi

    local trigger_type
    local min_executions
    local no_default_labels
    local runner_scope
    local image

    if ! trigger_type="$(extract_job_field "triggerType" '.properties.configuration.triggerType')"; then exit 1; fi
    check_equal "triggerType" "Event" "${trigger_type}"

    if ! min_executions="$(extract_job_field "minExecutions" '.properties.configuration.eventTriggerConfig.scale.minExecutions')"; then exit 1; fi
    check_equal "minExecutions" "0" "${min_executions}"

    if ! no_default_labels="$(extract_job_field "noDefaultLabels" '.properties.configuration.eventTriggerConfig.scale.rules[0].metadata.noDefaultLabels')"; then exit 1; fi
    check_equal "noDefaultLabels" "true" "${no_default_labels}"

    if ! runner_scope="$(extract_job_field "runnerScope" '.properties.configuration.eventTriggerConfig.scale.rules[0].metadata.runnerScope')"; then exit 1; fi
    check_equal "runnerScope" "org" "${runner_scope}"

    log_step "步驟 2/4: 確認 UAMI identitySettings lifecycle 為 None..."
    check_identity_lifecycle

    log_step "步驟 3/4: 檢查 image 是否避免 latest..."
    if ! image="$(extract_job_field "image" '.properties.template.containers[0].image')"; then exit 1; fi
    check_image_reference "${image}"

    log_step "步驟 4/4: 列出 executions..."
    if ! az containerapp job execution list \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${JOB_NAME}" \
        --only-show-errors \
        --output table \
        --query '[].{Name:name, Status:properties.status, StartTime:properties.startTime, EndTime:properties.endTime}'; then
        log_warn "⚠️ 無法取得 executions 清單（不影響整體驗證）"
    fi

    if [ "${failures}" -gt 0 ]; then
        log_error "❌ 驗證失敗，共 ${failures} 項"
        exit 1
    fi

    log_info "✓ 驗證全部通過"
}

main "$@"
