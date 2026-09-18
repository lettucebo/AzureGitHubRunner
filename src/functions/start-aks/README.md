🌏 Language / 語言: [English](README.md) | [繁體中文](README_zh-tw.md)

---

# Start AKS — Scheduled AKS Cluster Auto-Start/Stop

An Azure Function that automatically starts (and, optionally, stops) AKS clusters on a daily schedule. Designed for environments where company policies force-stop clusters at night.

## ✅ Features

| Feature | Support | Description |
|---------|:------:|-------------|
| Scheduled Start | ✅ | Two timer triggers (`startAks` at 00:25/00:40, `startAksFallback` at 06:00 Taipei time) |
| Scheduled Stop | ✅ (disabled by default) | `stopAks` timer trigger, must be explicitly enabled via `enableStopSchedule=true` |
| Configurable Schedules | ✅ | Override via `AKS_START_SCHEDULE` / `AKS_START_FALLBACK_SCHEDULE` / `AKS_STOP_SCHEDULE` app settings; falls back to the same defaults in code when unset |
| Multiple Clusters | ✅ | Support starting/stopping multiple AKS clusters simultaneously |
| Cross-Subscription | ✅ | Clusters can be in different Azure subscriptions |
| Managed Identity | ✅ | Passwordless authentication via System-assigned MI |
| Idempotent | ✅ | Only acts on the exact expected power state; skips everything else |
| Error Isolation | ✅ | One cluster failure doesn't affect others (per-cluster try/catch) |

## 🏗️ Architecture

```
┌───────────────────────────────────────────────────┐
│                Azure Function App                  │
│         (Linux Flex Consumption, Node.js 22)        │
│                                                     │
│  Timer: startAks (00:25 & 00:40 Taipei, default)    │
│  Timer: startAksFallback (06:00 Taipei, default)    │
│  Timer: stopAks (20:00 Taipei, default — DISABLED   │
│          by default via AzureWebJobs.stopAks.       │
│          Disabled=true / enableStopSchedule=false)  │
│         │                                           │
│         ▼                                           │
│  Read & validate AKS_CLUSTERS env var (must be a     │
│  nonempty JSON array of {subscriptionId,             │
│  resourceGroup,name}) — src/aksPower.ts              │
│         │                                           │
│         ▼                                           │
│  For each cluster (try/catch, isolated failures):    │
│  ┌───────────────────────────────────────────┐       │
│  │ Check exact powerState.code                │       │
│  │  start: only 'Stopped' → beginStartAndWait │──── Managed ──▶ AKS Cluster 1
│  │  stop:  only 'Running' → beginStopAndWait  │       Identity  ──▶ AKS Cluster 2
│  │  everything else (Starting/Stopping/       │                 ──▶ AKS Cluster N
│  │  undefined/unknown) → skip + log reason    │
│  └───────────────────────────────────────────┘
└───────────────────────────────────────────────────┘
```

## 🔧 Prerequisites

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)
- [Azure Functions Core Tools v4](https://docs.microsoft.com/azure/azure-functions/functions-run-local)
- [Node.js 22](https://nodejs.org/) (or 20+)
- [Bicep CLI](https://docs.microsoft.com/azure/azure-resource-manager/bicep/install)

## 🚀 Quick Start

### 1. Deploy Infrastructure

```bash
# Copy and edit parameter file
cp main.bicepparam.example main.bicepparam

# Deploy (subscription scope)
az deployment sub create --location eastasia \
  --template-file main.bicep --parameters main.bicepparam
```

### 2. Deploy Function Code

```bash
# Install dependencies and build
npm install
npm run build

# Deploy to Azure
func azure functionapp publish func-startaks-prod --javascript
```

### 3. Verify

```bash
# Check Function App status
az functionapp show -g rg-startaks-prod -n func-startaks-prod --query state

# Check AKS cluster power state
az aks show -g rg-ghrunner-prod -n aks-ghrunner-prod --query powerState.code
```

## 📋 Configuration

### Environment Variables (App Settings)

| Variable | Description | Default (when unset) |
|----------|-------------|-----------------------|
| `AKS_CLUSTERS` | JSON array of target clusters (required, must be a **nonempty** array) | — (no default; missing/invalid/empty ⇒ explicit error, no Azure calls) |
| `WEBSITE_TIME_ZONE` | IANA timezone name (Linux), applies to all timer schedules below | `Asia/Taipei` |
| `AKS_START_SCHEDULE` | NCRONTAB schedule for the primary `startAks` timer | `0 25,40 0 * * *` |
| `AKS_START_FALLBACK_SCHEDULE` | NCRONTAB schedule for the `startAksFallback` timer | `0 0 6 * * *` |
| `AKS_STOP_SCHEDULE` | NCRONTAB schedule for the `stopAks` timer | `0 0 20 * * *` |
| `AzureWebJobs.stopAks.Disabled` | Official Azure Functions setting to disable a specific function. **Set to `true` by default** (via Bicep `enableStopSchedule=false`) so the stop schedule never runs unless explicitly enabled | `true` |

All schedule values are resolved in code (`src/aksPower.ts` → `resolveSchedule`): the app setting is trimmed and used if non-empty, otherwise the literal default above is used. This means a code-only deployment (no Bicep app settings applied yet) still indexes and runs correctly with the same defaults as before this change.

### AKS_CLUSTERS Format

Must be a **nonempty JSON array**; each item requires nonempty string `subscriptionId`, `resourceGroup`, and `name`. Missing/invalid JSON, a non-array value (e.g. an object), an empty array, or any item missing/empty fields is rejected with an explicit logged error and **no Azure API calls are made**.

```json
[
  {
    "subscriptionId": "00000000-0000-0000-0000-000000000000",
    "resourceGroup": "rg-ghrunner-prod",
    "name": "aks-ghrunner-prod"
  },
  {
    "subscriptionId": "00000000-0000-0000-0000-000000000000",
    "resourceGroup": "rg-devops-agent-prod",
    "name": "aks-devops-agent-prod"
  }
]
```

### Power-State Handling

Both functions read the cluster's exact `powerState.code` and only act on the one expected value; every other state is explicitly skipped and logged with a reason (never silently ignored):

| `powerState.code` | `startAks` / `startAksFallback` | `stopAks` |
|---|---|---|
| `Stopped` | ✅ calls `beginStartAndWait` | ⏭️ skip (already stopped) |
| `Running` | ⏭️ skip (already running) | ✅ calls `beginStopAndWait` |
| `Starting` | ⏭️ skip (transitioning) | ⏭️ skip (transitioning) |
| `Stopping` | ⏭️ skip (transitioning) | ⏭️ skip (transitioning) |
| `undefined` | ⏭️ skip (state unknown) | ⏭️ skip (state unknown) |
| any other value | ⏭️ skip (unrecognized) | ⏭️ skip (unrecognized) |

Each cluster is processed in its own `try/catch`; one cluster's failure (e.g. permission error, API throttling) is logged and does **not** prevent later clusters in the same run from being processed.

## 🔐 Stop Schedule Safety (Disabled by Default)

The `stopAks` timer trigger is **disabled out of the box**:

- Bicep parameter `enableStopSchedule` defaults to `false`.
- This renders the official app setting `AzureWebJobs.stopAks.Disabled = string(!enableStopSchedule)`, i.e. `"true"` by default — the Azure Functions host will not invoke `stopAks` at all.
- To enable, set `enableStopSchedule = true` in your `main.bicepparam` and redeploy; the Function App setting flips to `"false"`.
- There is intentionally **no second custom "enable" flag** — `enableStopSchedule` is the single source of truth, mapped 1:1 to the official disable mechanism.

## ⚠️ Operational Caveats

- **Idempotent, not synchronous**: `beginStartAndWait`/`beginStopAndWait` wait for the ARM long-running operation to finish within the function's own execution, so overlapping timer firings on a cluster mid-transition are simply skipped (see table above), not queued or retried.
- **No cross-invocation locking**: if you run `startAks`/`stopAks` concurrently by other means (e.g. manual `az aks start/stop`), the next scheduled run reflects whatever `powerState.code` is observed at that moment.
- **Managed Identity permissions**: both start and stop require "Azure Kubernetes Service Contributor" (or equivalent) on each target resource group — the same role assignments already used for start now also cover stop.
- **Time zone**: all three schedules are interpreted under `WEBSITE_TIME_ZONE` (default `Asia/Taipei`); changing the time zone shifts all schedules together.

## 💰 Cost Estimate

| Resource | SKU | Monthly Cost |
|----------|-----|-------------|
| Function App | Flex Consumption (FC1) | ~$0 (a few executions/day) |
| Storage Account | Standard LRS | ~$0.01 |
| **Function App total** | | **~$0.01/month** |

> ⚠️ **Billing caveat**: stopping an AKS cluster deallocates the control plane and agent node VMs, which stops compute billing for those nodes — see [Microsoft Learn: Start and stop an AKS cluster](https://learn.microsoft.com/en-us/azure/aks/start-stop-cluster). That page does not enumerate every charge that may continue, and does not promise the total cost of a stopped cluster is zero. Other Azure resources associated with the cluster (e.g. disks, load balancers/public IPs, Container Registry, Log Analytics, Private Endpoints, this Function App itself) may continue to incur charges independently of the cluster's power state. Review your own resource inventory and billing rather than assuming stopping AKS alone eliminates all cost.

## 🔍 Troubleshooting

### Function doesn't trigger

1. Verify `WEBSITE_TIME_ZONE` is set to your intended IANA timezone (default `Asia/Taipei`)
2. Check Function App is running: `az functionapp show -g rg-startaks-prod -n func-startaks-prod --query state`
3. For `stopAks` specifically: confirm `AzureWebJobs.stopAks.Disabled` is `"false"` (i.e. `enableStopSchedule=true` was deployed) if you expect it to run

### Permission denied when starting/stopping AKS

1. Verify Managed Identity has "Azure Kubernetes Service Contributor" role on the target resource group
2. Check principal ID: `az functionapp identity show -g rg-startaks-prod -n func-startaks-prod --query principalId`
3. Manually assign if needed:
   ```bash
   az role assignment create --assignee <principalId> \
     --role "Azure Kubernetes Service Contributor" \
     --scope /subscriptions/<subId>/resourceGroups/<rgName>
   ```

### AKS cluster still stopped / still running

1. Check Function App logs: `az functionapp log tail -g rg-startaks-prod -n func-startaks-prod`
2. Verify `AKS_CLUSTERS` JSON format is correct (nonempty array, all fields nonempty strings)
3. Confirm the cluster's `powerState.code` matches what the function expects (see the power-state table above) — anything other than the exact expected value is skipped by design
4. Try manual start/stop: `az aks start -g <rg> -n <aks-name>` / `az aks stop -g <rg> -n <aks-name>`
