🌏 Language / 語言: [English](RUNBOOK.md) | [繁體中文](RUNBOOK_zh-tw.md)

---

# GitHub ACA Runner — Operational Runbook

This runbook gates every stage of the ACA runner rollout: PoC, Copilot cutover, and — only if a separate future approval is granted — long-term AKS shutdown. It does not authorize any action by itself; each gate must be checked off with evidence before the corresponding stage proceeds.

> ⚠️ **Hard current-state constraint**: The live AKS cluster (`src/github/aks-runner/`) must keep running, unchanged, for the entire duration of the ACA rollout. It is the current fallback platform. Nothing in this document authorizes stopping, uninstalling, or otherwise modifying AKS. The **AKS Long-term Shutdown Sequence** near the end of this runbook is a **deferred, not-yet-authorized future option** — see the callout before that section.

## Rollout Strategy

ACA adoption proceeds **repo-by-repo and workflow-by-workflow**, not as a single cutover:

1. Route one low-risk, non-Docker workflow in one repository to `aca-general` first.
2. Observe it against the PoC Acceptance Record Table below before adding more workflows.
3. Only after `aca-general` is stable does Gate B evaluate moving Copilot cloud agent traffic to `aca-copilot`.
4. AKS/ARC (`runs-on: arc-runner-set`) remains available as the fallback `runs-on` target for every workflow throughout this process; workflows are not required to remove it while ACA is being validated.

## Gate A — ACA PoC Prerequisites

- [ ] Create an org fine-grained PAT: `Self-hosted runners: Read and write`, `Actions: Read`, `Metadata: Read`, and record its expiry date
- [ ] The deployer has `Key Vault Secrets Officer` on the target Key Vault, or `secretsOfficerPrincipalId` is already set
- [ ] Approval obtained to start incurring Azure cost (estimated ≤ $7/month)

## Gate B — Copilot Cutover Prerequisites

- [ ] Measured p95/p99 duration of a full current Copilot session (setup + agent)
- [ ] `copilotReplicaTimeoutSeconds` ≥ p99 × 1.25 and this value has been tested and accepted by ACA
- [ ] The decision to **not** perform egress filtering, and its residual risk (see Security Notes below), has been explicitly accepted

## Gate C — AKS Shutdown Prerequisites (controls only the actual shutdown action in Task 16)

- [ ] General CI and Copilot have run stably on ACA for ≥ 14 days
- [ ] **Task 15 is complete and option (a) or (b) was chosen, with worst-case validation evidence attached** (if option (c) was chosen, the shutdown path ends here and this gate does not apply)
- [ ] Docker workloads have been moved to directly specify `ubuntu-latest` in their workflows and validated
- [ ] The residual shutdown cost of ≈ $44/month has been confirmed and accepted

> This gate only controls whether the shutdown action described later in this runbook may ever be executed under Task 16. Reaching Gate C does **not** by itself authorize execution — see the callout before the shutdown sequence.

## Security Notes (each item must be accepted individually)

- [ ] Self-hosted Copilot requires disabling GitHub's built-in firewall
- [ ] This design does **not** perform network egress filtering; a Copilot job can reach the public internet freely (same as a GitHub-hosted runner)
- [ ] Compensating controls: the platform-managed network is not attached to any own VNet (no internal network access), `--ephemeral` single-use execution, private repositories only, PAT has minimal scope and is rotated regularly

## PoC Acceptance Record Table

| Measurement | Recorded Value | Pass Criteria |
|---|---|---|
| Scale-from-zero p95 (queued → runner ready) | | ≤ 5 minutes |
| General job actual execution time p99 | | < `generalReplicaTimeoutSeconds` × 0.75 |
| Peak ephemeral storage | | < 8 GiB |
| `runs-on: self-hosted` jobs are not intercepted by the ACA runner | | true |
| `printenv` and `/proc/1/environ` inside the job contain no `GITHUB_PAT` | | true |
| GitHub API rate limit usage | | < 40% |

---

## ⚠️ AKS Long-term Shutdown Sequence — Deferred, Unauthorized Future Option

**Do not execute any step in this section.** It documents the sequence that *would* apply only after all of the following are true:
- Task 15 has selected option (a) or (b) (see Gate C), **and**
- Task 16 has received explicit, separate user approval to perform the shutdown, **and**
- Gate C above is fully checked off with evidence.

Until then, the live AKS cluster stays running exactly as-is. This section exists so that, if and when shutdown is separately authorized, the steps are not skipped or reordered.

**AKS Long-term Shutdown Sequence (steps must not be skipped, and deliberately does not include deletion):**

- [ ] 1. Disable the `startAks` timer (otherwise the daily auto-start will undo the shutdown)
- [ ] 2. Confirm no workflow or `copilot-setup-steps.yml` still references `arc-runner-set` / `arc-android`
- [ ] 3. **Keep the ARC installation in place** — do not run `helm uninstall` — to preserve recovery capability
- [ ] 4. Run `az aks stop` and confirm `powerState.code` is `Stopped`
- [ ] 5. Export the cost baseline and configuration, and record it in this runbook
- [ ] 6. Create a recurring reminder every 6 months to "start → validate → stop again" (a stopped cluster should not be left untouched for more than 12 months)
- [ ] 7. Document the recovery procedure and known limitations (the API server IP may change after a start; capacity-constrained regions may fail to start a stopped cluster)
- [ ] 8. Update the bilingual documentation and this runbook

## 📖 Related Documentation

- [中文版](RUNBOOK_zh-tw.md)
- [ACA Runner README](../../../src/github/aca-runner/README.md)
- [AKS Runner README](../../../src/github/aks-runner/README.md) — current fallback, unchanged
