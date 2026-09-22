🌏 Language / 語言: [English](README.md) | [繁體中文](README_zh-tw.md)

---

# GitHub Actions ACA Runner (Container Apps Jobs)

An event-driven, scale-to-zero self-hosted runner for GitHub Actions, built on Azure Container Apps (ACA) Jobs and the KEDA `github-runner` scaler.

> ⚠️ **Current status**: This is a **second, gradually-validated** runner platform. Adoption proceeds **repo-by-repo and workflow-by-workflow**. The existing AKS + ARC runner (**[`src/github/aks-runner/`](../aks-runner/)`**) remains the current fallback and **stays running, unmodified, during this rollout**. See [RUNBOOK.md](../../../docs/github/aca-runner/RUNBOOK.md) for the required approval gates before any live deployment or cutover step.

## ✅ Supported Features

| Feature | Supported | Notes |
|---|:---:|---|
| Scale to zero | ✅ | `minExecutions: 0`, no idle compute charge |
| Ephemeral single-use runners | ✅ | `config.sh --ephemeral` |
| General CI | ✅ | Label `aca-general` |
| GitHub Copilot cloud agent | ✅ | Label `aca-copilot`, same network configuration as general |
| Docker / container jobs / service containers | ❌ | Specify a GitHub-hosted runner directly in the workflow |
| Local disk above 8 GiB | ❌ | Specify a GitHub-hosted larger runner directly in the workflow |
| Network egress filtering | ❌ | Deliberate decision, see RUNBOOK |
| Repository-level runner isolation | ❌ | Requires GitHub Team runner groups |

## 📋 Table of Contents

- [Architecture Overview](#-architecture-overview)
- [Cost Estimate](#-cost-estimate)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Troubleshooting](#-troubleshooting)
- [Directory Structure](#-directory-structure)
- [Related Documentation](#-related-documentation)

## 🏗️ Architecture Overview

```text
GitHub Actions queue
        │  KEDA github-runner scaler
        │  noDefaultLabels=true, enableEtags=true
        ▼
┌─────────────────────────────────────────────┐
│ Container Apps Environment (Workload Profiles)│
│  platform-managed network, no VNet            │
│  ┌──────────────────┐  ┌───────────────────┐ │
│  │ Job: general     │  │ Job: copilot      │ │
│  │ label aca-general│  │ label aca-copilot │ │
│  │ timeout 3600s    │  │ timeout 7200s     │ │
│  └──────────────────┘  └───────────────────┘ │
│  0 → N ephemeral runner replicas              │
└─────────────────────────────────────────────┘
        │ managed identity (platform-level)
        ├── ACR      (runner image, immutable tag)
        └── Key Vault (GitHub PAT)
```

Both jobs share the same environment, managed identity, image, and secret source; they only differ in `runnerLabel` and `replicaTimeout`. There is no Docker daemon in the runner image, so workflows that need Docker/containers must target a GitHub-hosted runner directly instead of relying on any fallback.

The user-assigned managed identity mounted on both Jobs is scoped with `identitySettings` (`lifecycle: 'None'`, see `modules/runnerJob.bicep`) so it is available to the platform only — ACR image pull and Key Vault secret resolution — and is **not** reachable from the runner's main container via the Container Apps identity endpoint. This stops runner workload code from minting its own token for this identity and re-reading the Key Vault GitHub PAT directly. See [Control managed identity availability](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity#control-managed-identity-availability).

## 💰 Cost Estimate

| Component | Basis | Monthly Cost |
|---|---|---|
| ACA compute | ~843.7 min/month @ 2 vCPU / 4 GiB, within the monthly free grant | **$0** |
| ACR Basic | Fixed | ~$5.2 |
| Log Analytics | Job execution logs only | ~$0–2 |
| **Total** | - | **≈ $5–7/month** |

> 💡 Unlike AKS, there is no always-on node pool: ACA Jobs scale to zero and only the ACR + Log Analytics fixed costs remain when idle.

## 🔧 Prerequisites

1. **Azure CLI** with the `containerapp` extension:
   ```bash
   az extension add --name containerapp --upgrade
   ```
2. **GitHub organization fine-grained PAT** with `Self-hosted runners: Read and write`, `Actions: Read`, `Metadata: Read` (see RUNBOOK Gate A for the exact checklist and expiry tracking).
3. **Key Vault data-plane permissions**: the deployer needs `Key Vault Secrets Officer` on the target Key Vault, or `secretsOfficerPrincipalId` must already be set to a principal that has it.

## 🚀 Quick Start

> ⚠️ **Approval required before running any of the commands below against a real subscription or GitHub organization.** This section documents the intended command sequence only. Live deployment must not proceed until RUNBOOK Gate A has been signed off; the Copilot job additionally requires Gate B.

```bash
# 1. Phase A: deploy infrastructure (enableRunnerJobs stays false)
cp main.bicepparam.example main.bicepparam
az deployment sub create --location eastasia \
  --template-file main.bicep --parameters main.bicepparam

# 2. Write the PAT and build the runner image
az keyvault secret set --vault-name <keyVaultName> --name github-pat --value "<PAT>"
export ACR_NAME="<acrName>"
./scripts/build-runner-image.sh

# 3. Phase B: set enableRunnerJobs=true, fill in runnerImage, redeploy
az deployment sub create --location eastasia \
  --template-file main.bicep --parameters main.bicepparam
```

After deployment, run `scripts/verify-aca-runner.sh` (see [Directory Structure](#-directory-structure)) to confirm `triggerType`, `minExecutions`, `noDefaultLabels`, `runnerScope`, the mounted UAMI's `identitySettings` lifecycle (`None`), and the image tag before routing any real workflow traffic.

## 🔍 Troubleshooting

### Runner never gets triggered

- Confirm the workflow's `runs-on` label matches the job's `runnerLabel` (`aca-general` or `aca-copilot`) exactly.
- Check `noDefaultLabels` is `true` on the scale rule; without it, the scaler also reacts to plain `self-hosted` jobs meant for other runners (e.g. AKS/ARC).
  ```bash
  az containerapp job show -g <rg> -n <jobName> \
    --query "properties.configuration.eventTriggerConfig.scale.rules[0].metadata"
  ```

### Image pull failures

- Verify the managed identity has `AcrPull` on the ACR (see `modules/identity.bicep`).
- ACA relies on an ARM token to authenticate to ACR via the identity; if the registry was recreated or the role assignment is missing, pulls fail with `403`/`UNAUTHORIZED`.
  ```bash
  az role assignment list --scope <acrId> --query "[?principalId=='<identityPrincipalId>']"
  ```

### Secret read failures (`github-pat`)

- The managed identity needs `Key Vault Secrets User` (data-plane) on the Key Vault, not just RBAC at the subscription level.
  ```bash
  az role assignment list --scope <keyVaultId> --query "[?principalId=='<identityPrincipalId>']"
  ```

### `az keyvault secret set` returns 403

- The deployer (not the managed identity) is missing `Key Vault Secrets Officer`. Either grant it manually or set `secretsOfficerPrincipalId` in `main.bicepparam` and redeploy.

### `identitySettings` lifecycle drifted from `None`

- `scripts/verify-aca-runner.sh` step 2/4 fails if the mounted UAMI's `identitySettings` lifecycle is not `None`. A non-`None` value would let the runner's main container reach the Container Apps identity endpoint and mint its own token for that identity, then re-read the Key Vault PAT directly.
  ```bash
  az containerapp job show -g <rg> -n <jobName> \
    --query "properties.configuration.identitySettings"
  ```
- Redeploy from `main.bicep`/`modules/runnerJob.bicep` (requires `Microsoft.App/jobs` API version `2025-01-01` or later) to restore `lifecycle: 'None'`. Do not edit this setting manually outside of source control.

### Replica ends before the job finishes

- Compare `replicaTimeoutSeconds` (general: 3600s, copilot: 7200s by default) against the workflow's `timeout-minutes`. If the workflow timeout is longer than the replica timeout, ACA kills the replica first.
- For the Copilot job, `copilotReplicaTimeoutSeconds` must be raised only after measuring real session p99 durations (RUNBOOK Gate B).

## 📁 Directory Structure

```
src/github/aca-runner/
├── main.bicep                    # Subscription-scope, two-phase deployment
├── main.bicepparam.example       # Parameter example
├── modules/
│   ├── log.bicep                 # Log Analytics workspace
│   ├── acr.bicep                 # Container Registry
│   ├── keyVault.bicep            # Key Vault for the GitHub PAT
│   ├── identity.bicep            # User-assigned identity + role assignments
│   ├── containerAppsEnv.bicep    # Container Apps Environment (Consumption)
│   └── runnerJob.bicep           # Shared event-driven runner Job template
├── runner-image/                 # Dockerfile + entrypoint for the ephemeral runner
└── scripts/
    ├── build-runner-image.sh     # az acr build, immutable tag from git SHA
    ├── update-runner-version.sh  # Pin runner version/checksum
    └── verify-aca-runner.sh      # Post-deploy configuration checks
```

## 📖 Related Documentation

- [中文文件](README_zh-tw.md)
- [Operational Runbook](../../../docs/github/aca-runner/RUNBOOK.md) — approval gates, security acceptance, PoC acceptance table, and the (currently unauthorized) AKS shutdown sequence
- [GitHub AKS Runner](../aks-runner/README.md) — current fallback platform, unchanged during this rollout
- [Azure Container Apps jobs tutorial](https://learn.microsoft.com/en-us/azure/container-apps/tutorial-ci-cd-runners-jobs)
- [KEDA github-runner scaler](https://keda.sh/docs/scalers/github-runner/)

---

## 📝 License

MIT License
