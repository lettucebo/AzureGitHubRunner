🌏 Language / 語言: [English](README.md) | [繁體中文](README_zh-tw.md)

---

# Start AKS — Scheduled AKS Cluster Auto-Start/Stop

An Azure Function that automatically starts (and, optionally, stops) AKS clusters on a daily schedule. Designed for environments where company policies force-stop clusters at night.

## ✅ Features

| Feature | Support | Description |
|---------|:------:|-------------|
| Scheduled Start | ✅ | Single timer trigger `startAks`, default `0 25,40 16 * * *` UTC (00:25/00:40 Asia/Taipei) |
| Scheduled Stop | ✅ (disabled by default, fail-closed) | `stopAks` timer trigger, default `0 0 14 * * *` UTC; requires `AKS_STOP_ENABLED` to be exactly `"true"` (case-insensitive, trimmed) or it is skipped before any Azure call |
| Configurable Schedules | ✅ | Override via `AKS_START_SCHEDULE_UTC` / `AKS_STOP_SCHEDULE_UTC` app settings (UTC NCRONTAB); falls back to the same defaults in code when unset |
| Multiple Clusters | ✅ | Support starting/stopping multiple AKS clusters simultaneously |
| Cross-Subscription | ✅ | Clusters can be in different Azure subscriptions |
| Managed Identity | ✅ | Passwordless authentication via System-assigned MI |
| Idempotent | ✅ | Only acts on the exact expected power state; skips everything else |
| Error Isolation | ✅ | Both malformed `AKS_CLUSTERS` items (per-item validation) and per-cluster Azure API failures (try/catch) are isolated — one bad entry never blocks the rest |

## 🏗️ Architecture

```
┌───────────────────────────────────────────────────┐
│                Azure Function App                  │
│         (Linux Flex Consumption, Node.js 22)        │
│                                                     │
│  Timer: startAks (default 0 25,40 16 * * * UTC =    │
│          00:25 & 00:40 Taipei next day)             │
│  Timer: stopAks (default 0 0 14 * * * UTC =         │
│          22:00 Taipei same day — gated by           │
│          AKS_STOP_ENABLED, fail-closed)             │
│         │                                           │
│         ▼                                           │
│  src/functions/*.ts — thin wiring only:              │
│  build credential/clientFactory/logger from env,     │
│  register UTC timer, delegate to src/aksOperations.ts│
│         │                                           │
│         ▼                                           │
│  src/aksOperations.ts — testable execution logic:    │
│   1. stopAks only: check AKS_STOP_ENABLED === "true" │
│      (trimmed, case-insensitive) BEFORE anything else│
│      else log + return, zero Azure calls             │
│   2. Parse & validate AKS_CLUSTERS (src/aksPower.ts): │
│      global JSON/array/empty failures ⇒ abort;        │
│      otherwise each item validated independently,     │
│      invalid items logged + skipped, valid ones kept  │
│         │                                           │
│         ▼                                           │
│  For each valid cluster (try/catch, isolated failures):│
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
| `AKS_CLUSTERS` | JSON array of target clusters (required, must be a **nonempty** array) | — (no default; missing/invalid JSON/non-array/empty array ⇒ explicit error, no Azure calls) |
| `AKS_START_SCHEDULE_UTC` | NCRONTAB schedule (**UTC**) for the `startAks` timer | `0 25,40 16 * * *` (UTC) |
| `AKS_STOP_SCHEDULE_UTC` | NCRONTAB schedule (**UTC**) for the `stopAks` timer | `0 0 14 * * *` (UTC) |
| `AKS_STOP_ENABLED` | **The single source of truth** for enabling the stop schedule. Only a value that, after trimming whitespace, is *exactly* (case-insensitively) `"true"` enables it. Missing, empty, `"false"`, or any other value ⇒ disabled (fail-closed) | unset (⇒ disabled) |

All schedule values are resolved in code (`src/aksPower.ts` → `resolveSchedule`): the app setting is trimmed and used if non-empty, otherwise the literal default above is used. This means a code-only deployment (no Bicep app settings applied yet) still indexes and runs correctly with the same defaults as before this change.

### ⏰ Time Zone and Scheduling (UTC only)

Flex Consumption Timer Triggers are **always interpreted in UTC** — there is no `WEBSITE_TIME_ZONE` / `TZ` support for adjusting the NCRONTAB evaluation on this plan. See:
- https://learn.microsoft.com/en-us/azure/azure-functions/errors-diagnostics/diagnostic-events/azfd0010
- https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-timer#time-zones

Implications for operators:
- The defaults (`0 25,40 16 * * *` start / `0 0 14 * * *` stop, both UTC) correspond to **00:25 and 00:40 / 22:00 Asia/Taipei (UTC+8)**. The start attempts fire at UTC 16:25/16:40 on the **previous UTC calendar day** relative to the local times they produce (e.g. UTC Monday 16:25/16:40 → Taipei Tuesday 00:25/00:40).
- The two start attempts preserve the fast-restart intent after the company-enforced stop around 00:05: 00:25 is the primary attempt, while 00:40 provides retry resilience for stop completion or configuration propagation delays. There is no unrelated 06:00 fallback.
- **Day-of-week fields cross UTC calendar boundaries.** If you need a schedule anchored to a specific *local* weekday (e.g. "every local Monday 00:25/00:40"), remember that Asia/Taipei Monday 00:25/00:40 = UTC **Sunday** 16:25/16:40 — you must express the day-of-week field in UTC terms, not local terms.
- **DST is not automatically adjusted.** If your target time zone observes Daylight Saving Time, you are responsible for updating the UTC NCRONTAB expression (`AKS_START_SCHEDULE_UTC` / `AKS_STOP_SCHEDULE_UTC`) yourself when the offset changes; Azure Functions will not shift it for you.

### AKS_CLUSTERS Format

Must be a **nonempty JSON array**. The array itself must be valid: missing/invalid JSON, a non-array value (e.g. an object), or an empty array is a **global** failure — rejected with an explicit logged error and **no Azure API calls are made at all**.

Once the array itself is valid and nonempty, **each item is validated independently** (per-cluster isolation): an item missing/empty `subscriptionId`, `resourceGroup`, or `name` is logged with its zero-based index (log messages follow the repository's Traditional Chinese convention, e.g. `AKS_CLUSTERS 第 1 筆項目缺少有效的 subscriptionId/resourceGroup/name...`) and skipped, but this **never** rejects other, valid items in the same array — they are still processed normally. Valid items have their three string fields trimmed. If every item happens to be invalid, the run simply processes zero clusters (after logging every reason) rather than failing outright.

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

| `powerState.code` | `startAks` | `stopAks` |
|---|---|---|
| `Stopped` | ✅ calls `beginStartAndWait` | ⏭️ skip (already stopped) |
| `Running` | ⏭️ skip (already running) | ✅ calls `beginStopAndWait` |
| `Starting` | ⏭️ skip (transitioning) | ⏭️ skip (transitioning) |
| `Stopping` | ⏭️ skip (transitioning) | ⏭️ skip (transitioning) |
| `undefined` | ⏭️ skip (state unknown) | ⏭️ skip (state unknown) |
| any other value | ⏭️ skip (unrecognized) | ⏭️ skip (unrecognized) |

Each cluster is processed in its own `try/catch`; one cluster's failure (e.g. permission error, API throttling) is logged and does **not** prevent later clusters in the same run from being processed.

## 🔐 Stop Schedule Safety — Fail-Closed by Default

The `stopAks` timer trigger fires on schedule regardless, but **its actual stop logic is gated code-side and disabled out of the box**:

- Bicep parameter `enableStopSchedule` defaults to `false`, which maps 1:1 to the app setting `AKS_STOP_ENABLED: string(enableStopSchedule)`.
- The **code itself** (`src/aksOperations.ts` → `runStopAks`, using `src/aksPower.ts` → `isStopScheduleEnabled`) checks `AKS_STOP_ENABLED` as the **very first step**, before parsing `AKS_CLUSTERS`, before constructing any credential/client, before any Azure API call. Only a value that, after trimming, is exactly `"true"` (case-insensitive) proceeds; anything else — missing, empty, `"false"`, typos — logs a clear message and returns immediately with zero Azure calls.
- This is intentionally a **code-level, fail-closed** gate rather than relying solely on the Azure Functions host-level `AzureWebJobs.<name>.Disabled` mechanism: a missing/misconfigured app setting, or a host-level regression in how that mechanism is applied, would previously risk the function still running. `AKS_STOP_ENABLED` is the **single source of truth** — there is no second flag to keep in sync.
- To enable, set `enableStopSchedule = true` in your `main.bicepparam` and redeploy; the app setting flips to `"true"`.

## ⚠️ Operational Caveats

- **Idempotent, not synchronous**: `beginStartAndWait`/`beginStopAndWait` wait for the ARM long-running operation to finish within the function's own execution, so overlapping timer firings on a cluster mid-transition are simply skipped (see table above), not queued or retried.
- **No cross-invocation locking**: if you run `startAks`/`stopAks` concurrently by other means (e.g. manual `az aks start/stop`), the next scheduled run reflects whatever `powerState.code` is observed at that moment.
- **Managed Identity permissions**: both start and stop require "Azure Kubernetes Service Contributor" (or equivalent) on each target resource group — the same role assignments already used for start now also cover stop.
- **UTC-only scheduling**: both timer schedules are interpreted strictly in UTC (see "Time Zone and Scheduling" above) — there is no time zone app setting that shifts them.

## 💰 Cost Estimate

| Resource | SKU | Monthly Cost |
|----------|-----|-------------|
| Function App | Flex Consumption (FC1) | ~$0 (a few executions/day) |
| Storage Account | Standard LRS | ~$0.01 |
| **Function App total** | | **~$0.01/month** |

> ⚠️ **Billing caveat**: stopping an AKS cluster deallocates the control plane and agent node VMs, which stops compute billing for those nodes — see [Microsoft Learn: Start and stop an AKS cluster](https://learn.microsoft.com/en-us/azure/aks/start-stop-cluster). That page does not enumerate every charge that may continue, and does not promise the total cost of a stopped cluster is zero. Other Azure resources associated with the cluster (e.g. disks, load balancers/public IPs, Container Registry, Log Analytics, Private Endpoints, this Function App itself) may continue to incur charges independently of the cluster's power state. Review your own resource inventory and billing rather than assuming stopping AKS alone eliminates all cost.

## 🔍 Troubleshooting

### Function doesn't trigger

1. Remember schedules are UTC-only (see "Time Zone and Scheduling" above) — double check `AKS_START_SCHEDULE_UTC` / `AKS_STOP_SCHEDULE_UTC` are expressed in UTC, not local time
2. Check Function App is running: `az functionapp show -g rg-startaks-prod -n func-startaks-prod --query state`
3. For `stopAks` specifically: confirm `AKS_STOP_ENABLED` is exactly `"true"` (i.e. `enableStopSchedule=true` was deployed) if you expect the stop action to actually run — the timer itself fires regardless, but the code returns immediately without any Azure call unless this is `"true"`

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
2. Verify `AKS_CLUSTERS` JSON format is correct — the array itself must be a valid nonempty JSON array (a malformed/non-array/empty `AKS_CLUSTERS` is a global failure), but individual invalid items inside a valid array are just logged and skipped, not a global failure
3. Confirm the cluster's `powerState.code` matches what the function expects (see the power-state table above) — anything other than the exact expected value is skipped by design
4. Try manual start/stop: `az aks start -g <rg> -n <aks-name>` / `az aks stop -g <rg> -n <aks-name>`
