# Azure Self-hosted Runner — Copilot Instructions

## Project Overview

IaC project deploying GitHub Actions / Azure DevOps self-hosted runners on Azure. Four deployment scenarios exist under `src/`:

| Platform | VM (Terraform) | AKS (Bicep) |
|---|---|---|
| **GitHub** | `src/github/vm-runner/` | `src/github/aks-runner/` (ARC) |
| **Azure DevOps** | `src/azure-devops/vm-runner/` | `src/azure-devops/aks-runner/` (KEDA) |

Additional utilities under `src/`:
- `src/functions/start-aks/` — Azure Function (Flex Consumption) for scheduled AKS cluster auto-start
- `src/common-scripts/` — PowerShell scripts for SSH key management

Primary use case: **GitHub Copilot Coding Agent** support via AKS runners.

## Quick Reference

### Deploy Commands

```bash
# Bicep (AKS scenarios) — deploys at subscription scope
az deployment sub create --location eastasia --template-file main.bicep --parameters main.bicepparam

# Terraform (VM scenarios)
terraform init && terraform apply

# Post-deploy: install controller
./scripts/install-arc.sh   # GitHub AKS
./scripts/install-keda.sh  # Azure DevOps AKS
```

### Validate Commands

```bash
# Bicep
az bicep build --file main.bicep
az deployment sub validate --location eastasia --template-file main.bicep --parameters main.bicepparam

# Terraform
terraform fmt -check && terraform validate && terraform plan

# Kubernetes YAML
kubectl apply --dry-run=client -f kubernetes/

# Bash scripts
shellcheck scripts/*.sh
```

## Architecture Conventions

### AKS Dual-Pool Design (shared across GitHub & Azure DevOps)

- **System Pool**: 1× B2s (fixed), `CriticalAddonsOnly` taint — hosts K8s system + controller
- **Runner Pool**: 0–10× D4s_v3 Spot VMs (autoscaling), `spot:NoSchedule` taint — hosts runner workloads
- **scaleDownMode**: `Deallocate` — preserves OS disk cache for faster scale-up
- **Network**: Azure CNI Overlay (`networkPluginMode: 'overlay'`), no Network Policy — reduces overhead

### ARC Runner Configuration

- **githubConfigUrl**: Organization-level (`https://github.com/MoneyForge`) — shared across all repos
- **minRunners**: `0` — scale from zero on demand, no idle runners
- **maxRunners**: `45` — burst capacity
- **containerMode**: `dind` (Docker-in-Docker) — supports container jobs
- **Runner Pod**: Must have `nodeSelector: { nodepool-type: runner }` + Spot VM toleration
- **Listener Pod**: Guaranteed QoS (`requests = limits`) — critical component, must not be evicted

### AKS Cluster Rebuild Procedure

Required when changing immutable properties (networkPlugin, networkPolicy, networkPluginMode):

```bash
# 1. Uninstall ARC
helm uninstall arc-runner-set -n arc-runners --no-hooks
helm uninstall arc -n arc-systems --no-hooks

# 2. Delete cluster
az aks delete -g rg-ghrunner-prod -n aks-ghrunner-prod --yes

# 3. Deploy new cluster
az deployment sub create --location eastasia --template-file main.bicep --parameters main.bicepparam

# 4. Get credentials + install ARC
az aks get-credentials -g rg-ghrunner-prod -n aks-ghrunner-prod --overwrite-existing
helm install arc --namespace arc-systems --create-namespace \
  --set "tolerations[0].key=CriticalAddonsOnly" \
  --set "tolerations[0].operator=Exists" \
  --set "tolerations[0].effect=NoSchedule" \
  --wait oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller

# 5. Create secret + install runner
kubectl create ns arc-runners
kubectl create secret generic github-pat-secret -n arc-runners --from-literal=github_token="$GITHUB_PAT"
helm install arc-runner-set -n arc-runners -f kubernetes/arc-runner-values.yaml --wait --timeout 5m \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

### Naming Patterns

**Bicep**: `{resource-prefix}-${projectName}-${environment}` (e.g., `rg-ghrunner-prod`, `aks-ghrunner-prod`)
- ACR names: **no dashes** (Azure restriction), uses `replace()` to strip them

**Terraform**: `${var.prefix}-{resource}` (e.g., `gh-runner-vnet`, `gh-runner-vm`)

### Tags

- Bicep: `{ project, environment, managedBy: 'bicep' }`
- Terraform: `{ Environment, ManagedBy: "Terraform" }`

## Coding Conventions

### Language

- **Code comments & variable descriptions**: Traditional Chinese (繁體中文)
- **Commit messages**: Traditional Chinese, following Conventional Commits (see [commit instructions](.github/instructions/commit.instructions.md))
- **Documentation**: Bilingual (English + 繁體中文), paired files: `README.md` / `README_zh-tw.md`

### Bicep Patterns

- `targetScope = 'subscription'` — creates its own resource group
- Section headers: `// ============================================================================`
- Structure: Parameters → Variables → Resource Group → Modules
- Optional modules guarded by boolean params (`enableMonitoring`, `enableAcr`)
- Decorators: `@description()`, `@minValue()`, `@allowed()` on all parameters
- Modules live in `modules/` subfolder

### Terraform Patterns

- Every variable: `description` + `type` + `default` + `validation` block
- Sensitive vars: `sensitive = true` for tokens and SSH keys
- Validation using `can(regex(...))` and `contains([...], var)`
- Cloud-init via `templatefile()` injecting secrets

### Bash Script Patterns

- `set -e` at top
- Color-coded logging: `log_info` (green), `log_warn` (yellow), `log_error` (red), `log_step` (blue)
- Emoji indicators: ✓ success, ❌ failure
- Environment variables with defaults: `VAR="${VAR:-default}"`
- Step-numbered progress: "步驟 1/4", "步驟 2/4"
- Idempotent K8s operations: `kubectl create ... --dry-run=client -o yaml | kubectl apply -f -`
- `main()` function at bottom with help flag support

### PowerShell Script Patterns

- Console output with color: `Write-Host "..." -ForegroundColor Cyan/Green/Red/Yellow`
- Emoji indicators: ✅ ❌ ⚠️ 📁 📋 🔐
- Error handling with `try/catch`
- User confirmation prompts for destructive operations

### Kubernetes Config Patterns

- ARC namespaces: `arc-systems` (controller), `arc-runners` (runners)
- Node affinity: `nodeSelector: { nodepool-type: runner }`
- Tolerations for Spot VMs and CriticalAddonsOnly taints
- Docker-in-Docker mode: `containerMode.type: "dind"`

## Known Pitfalls

1. **K8s version**: East Asia region may not support latest K8s versions. Run `az aks get-versions --location <location>` before deploying
2. **ARC listenerTemplate**: Must include `containers` section with `name: listener` — otherwise tolerations/nodeSelector are silently ignored
3. **ACR naming**: No dashes allowed (Azure restriction), uses `replace()` to strip them
4. **Spot VM eviction**: Runner Pool uses `scaleSetEvictionPolicy: 'Delete'` — jobs must be idempotent
5. **SSH default**: `ssh_source_address_prefix` defaults to `"*"` — restrict in production
6. **Terraform state**: No remote backend configured — defaults to local state
7. **Bicep deploys at subscription scope** (creates RG); Terraform deploys within existing RG
8. **AKS network config is immutable**: `networkPlugin`, `networkPluginMode`, `networkPolicy` cannot be changed after cluster creation. Must delete and recreate the cluster to change these.
9. **ARC DinD + template.spec.containers conflict**: When `containerMode.type: "dind"` is enabled, do NOT define `containers` in `template.spec` — ARC auto-injects runner + dind containers. Adding custom containers causes `initContainers[0].image: null` validation errors.
10. **ARC uninstall stuck resources**: After `helm uninstall`, ARC CRD resources (AutoscalingRunnerSet, AutoscalingListener, ServiceAccount) may get stuck in `Terminating` due to `actions.github.com/cleanup-protection` finalizer. Fix: `kubectl patch <resource> --type merge -p '{"metadata":{"finalizers":null}}'`
11. **ARC stale scale set ID**: If runner scale set is reinstalled multiple times, GitHub may cache old scale set IDs causing `RunnerScaleSetNotFoundException`. Fix: fully uninstall, clean all orphaned resources, then fresh install.
12. **GitHub PAT for org-level ARC**: Fine-grained PAT needs Organization permission `Self-hosted runners: Read and write` (not just `Administration`) to register runners at organization scope.
13. **AKS stopped cluster**: `kubectl` commands fail with DNS errors when cluster is stopped. Check with `az aks show --query powerState.code` and start with `az aks start`.

## Related Instructions

Detailed guidelines in `.github/instructions/`:
- [General](../.github/instructions/general.instructions.md) — project architecture, deployment workflows, module structure
- [Code Review](../.github/instructions/code-review.instructions.md) — review checklist, TypeScript/Vue/Hono conventions
- [Commit](../.github/instructions/commit.instructions.md) — Conventional Commits in Traditional Chinese
- [Documentation](../.github/instructions/documentation.instructions.md) — bilingual docs, README structure, emoji conventions
- [Testing](../.github/instructions/testing.instructions.md) — Bicep/Terraform/YAML/Bash validation commands

## Documentation Map

| Topic | Location |
|---|---|
| Project overview | `README.md` / `README_zh-tw.md` |
| GitHub AKS runner | `src/github/aks-runner/README.md` |
| GitHub VM runner | `docs/github/vm-runner/` (6 guides) |
| Azure DevOps AKS | `src/azure-devops/aks-runner/README.md` |
| Azure DevOps VM | `src/azure-devops/vm-runner/README.md` |
| Start AKS Function | `src/functions/start-aks/README.md` |
| Troubleshooting | `docs/github/aks-runner/TROUBLESHOOTING.md` |
| SSH key management | `src/common-scripts/*.ps1` |
