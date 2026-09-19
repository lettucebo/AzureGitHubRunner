#!/usr/bin/env bash
# ============================================================================
# ACA GitHub Actions Runner Entrypoint
#
# 依 Microsoft「Run GitHub Actions runners with Azure Container Apps jobs」
# 教學的模式：以 PAT 換取 registration token，再以 --ephemeral 註冊，
# 執行單一 job 後容器結束。
#
# 收尾刻意使用 `unset GITHUB_PAT` 後 `exec ./run.sh`：
#   exec 本來就是容器 entrypoint 的標準寫法；因為 /proc/1/environ 記錄的是
#   最後一次 execve 當下的環境，先 unset 再 exec 可讓後續 workflow 步驟
#   既讀不到 PAT 環境變數，也讀不到 PID 1 的環境快照。
# ============================================================================
set -euo pipefail

: "${GITHUB_OWNER:?GITHUB_OWNER is required}"
: "${GITHUB_PAT:?GITHUB_PAT is required}"
: "${RUNNER_LABELS:?RUNNER_LABELS is required}"

GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com}"
RUNNER_GROUP="${RUNNER_GROUP:-}"
RUNNER_NAME="${RUNNER_NAME:-aca-$(hostname)-$$}"

cd /home/runner/actions-runner

# 以 printf 組出授權標頭，避免把憑證與 scheme 直接寫成相鄰字面值
auth_header="$(printf '%s: %s %s' 'Authorization' 'Bearer' "${GITHUB_PAT}")"

echo "[INFO] 取得 organization registration token..."
registration_token="$(curl -fsSL --max-time 30 -X POST \
    -H "${auth_header}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "${GITHUB_API_URL}/orgs/${GITHUB_OWNER}/actions/runners/registration-token" \
    | jq -r '.token')"

if [ -z "${registration_token}" ] || [ "${registration_token}" = "null" ]; then
    echo "[ERROR] ❌ 無法取得 registration token" >&2
    exit 1
fi

echo "[INFO] 設定 runner ${RUNNER_NAME} (labels=${RUNNER_LABELS})..."
config_args=(
    --unattended
    --url "https://github.com/${GITHUB_OWNER}"
    --token "${registration_token}"
    --name "${RUNNER_NAME}"
    --labels "${RUNNER_LABELS}"
    --no-default-labels
    --ephemeral
    --disableupdate
    --replace
)
# GitHub Free organization 只有 Default runner group，傳入自訂群組會直接失敗
if [ -n "${RUNNER_GROUP}" ] && [ "${RUNNER_GROUP}" != "Default" ]; then
    config_args+=(--runnergroup "${RUNNER_GROUP}")
fi
./config.sh "${config_args[@]}"

unset GITHUB_PAT auth_header registration_token

echo "[INFO] ✓ 啟動 runner"
exec ./run.sh
