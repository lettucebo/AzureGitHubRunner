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
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

RESOURCE_GROUP="${RESOURCE_GROUP:-}"
JOB_NAME="${JOB_NAME:-}"
failures=0
last_query_failed=0

usage() {
    cat <<'EOF'
用法: verify-aca-runner.sh

必要環境變數:
  RESOURCE_GROUP   ACA runner 的 resource group
  JOB_NAME         Container Apps Job 名稱

說明:
  1. 檢查 triggerType、minExecutions、noDefaultLabels、runnerScope
  2. 確認 image 不可使用 latest
  3. 列出 executions 供人工檢視
EOF
}

require_command() {
    local command_name="$1"
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        log_error "❌ 找不到 ${command_name}，請先安裝"
        exit 1
    fi
}

query_az() {
    local description="$1"
    shift

    local output
    last_query_failed=0
    if ! output="$("$@" 2>&1)"; then
        log_error "❌ ${description} 失敗: ${output}"
        failures=$((failures + 1))
        last_query_failed=1
        printf ''
        return 0
    fi

    printf '%s' "${output}"
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

main() {
    if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
        usage
        exit 0
    fi

    require_command az

    if [ -z "${RESOURCE_GROUP}" ] || [ -z "${JOB_NAME}" ]; then
        log_error "❌ 必須設定 RESOURCE_GROUP 與 JOB_NAME"
        exit 1
    fi

    log_step "步驟 1/3: 讀取 Job 設定..."
    local trigger_type
    local min_executions
    local no_default_labels
    local runner_scope
    local image

    trigger_type="$(
        query_az \
            "triggerType" \
            az containerapp job show \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${JOB_NAME}" \
            --only-show-errors \
            --query 'properties.configuration.triggerType' \
            -o tsv
    )"
    if [ "${last_query_failed}" -eq 0 ]; then
        check_equal "triggerType" "Event" "${trigger_type}"
    fi

    min_executions="$(
        query_az \
            "minExecutions" \
            az containerapp job show \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${JOB_NAME}" \
            --only-show-errors \
            --query 'properties.configuration.eventTriggerConfig.scale.minExecutions' \
            -o tsv
    )"
    if [ "${last_query_failed}" -eq 0 ]; then
        check_equal "minExecutions" "0" "${min_executions}"
    fi

    no_default_labels="$(
        query_az \
            "noDefaultLabels" \
            az containerapp job show \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${JOB_NAME}" \
            --only-show-errors \
            --query 'properties.configuration.eventTriggerConfig.scale.rules[0].metadata.noDefaultLabels' \
            -o tsv
    )"
    if [ "${last_query_failed}" -eq 0 ]; then
        check_equal "noDefaultLabels" "true" "${no_default_labels}"
    fi

    runner_scope="$(
        query_az \
            "runnerScope" \
            az containerapp job show \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${JOB_NAME}" \
            --only-show-errors \
            --query 'properties.configuration.eventTriggerConfig.scale.rules[0].metadata.runnerScope' \
            -o tsv
    )"
    if [ "${last_query_failed}" -eq 0 ]; then
        check_equal "runnerScope" "org" "${runner_scope}"
    fi

    log_step "步驟 2/3: 檢查 image 是否避免 latest..."
    image="$(
        query_az \
            "image" \
            az containerapp job show \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${JOB_NAME}" \
            --only-show-errors \
            --query 'properties.template.containers[0].image' \
            -o tsv
    )"
    if [ "${last_query_failed}" -eq 0 ]; then
        if [[ "${image}" == *":latest" ]]; then
            log_error "❌ image 使用 latest tag: ${image}"
            failures=$((failures + 1))
        else
            log_info "✓ image: ${image}"
        fi
    fi

    log_step "步驟 3/3: 列出 executions..."
    if ! az containerapp job execution list \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${JOB_NAME}" \
        --only-show-errors \
        --output table \
        --query '[].{Name:name, Status:properties.status, StartTime:properties.startTime, EndTime:properties.endTime}'; then
        log_error "❌ 列出 executions 失敗"
        failures=$((failures + 1))
    fi

    if [ "${failures}" -gt 0 ]; then
        log_error "❌ 驗證失敗，共 ${failures} 項"
        exit 1
    fi

    log_info "✓ 驗證全部通過"
}

main "$@"
