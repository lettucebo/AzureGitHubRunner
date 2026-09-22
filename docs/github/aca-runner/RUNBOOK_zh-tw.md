🌏 Language / 語言: [English](RUNBOOK.md) | [繁體中文](RUNBOOK_zh-tw.md)

---

# GitHub ACA Runner — 運維 Runbook

本 Runbook 為 ACA runner 導入的每個階段設立 Gate：PoC、Copilot 切換，以及**唯有在未來另外取得核准時**才適用的 AKS 長期停機。本文件本身不構成任何動作的授權；每個 Gate 都必須附證據勾選完成，對應階段才能繼續。

> ⚠️ **目前狀態的硬性限制**：live AKS 叢集（`src/github/aks-runner/`）在整個 ACA 導入期間必須**持續運行、完全不變更**，是現行的 fallback 平台。本文件任何內容都不構成停機、卸載或修改 AKS 的授權。本文件末段的**「AKS 長期停機順序」屬於尚未核准的未來選項（deferred）**，詳見該段落前的警示框。

## 導入策略

ACA 採**逐 repo、逐 workflow**漸進導入，而非一次性切換：

1. 先在一個 repository 中，把一個低風險、無 Docker 需求的 workflow 導向 `aca-general`。
2. 依下方「PoC 驗收記錄表」觀察通過後，才逐步加入更多 workflow。
3. 唯有 `aca-general` 穩定後，Gate B 才評估是否將 Copilot cloud agent 流量導向 `aca-copilot`。
4. 在整個驗證期間，AKS/ARC（`runs-on: arc-runner-set`）持續作為每個 workflow 可用的 fallback `runs-on` 目標；驗證 ACA 期間不要求 workflow 移除這個選項。

## Gate A — ACA PoC 前置

- [ ] 建立 org fine-grained PAT：`Self-hosted runners: Read and write`、`Actions: Read`、`Metadata: Read`，並記錄到期日
- [ ] 部署者具備目標 Key Vault 的 `Key Vault Secrets Officer`，或已填入 `secretsOfficerPrincipalId`
- [ ] 已核准開始產生 Azure 費用（預估 ≤ $7/月）

## Gate B — Copilot 切換前置

- [ ] 已量測現行完整 Copilot session（setup + agent）duration p95/p99
- [ ] `copilotReplicaTimeoutSeconds` ≥ p99 × 1.25 且已實測 ACA 接受該值
- [ ] 已明確接受「不做 egress 過濾」的決策與其殘留風險（見下方安全說明）

## Gate C — AKS 停機前置（僅控制 Task 16 的實際停機動作）

- [ ] 一般 CI 與 Copilot 已在 ACA 穩定運作 ≥ 14 天
- [ ] **Task 15 已完成且選擇 (a) 或 (b)，並附 worst-case 驗證證據**（若選 (c)，停機路徑結束，不適用本 Gate）
- [ ] Docker 工作已改在 workflow 直接指定 `ubuntu-latest` 並驗證通過
- [ ] 已確認並接受停機殘留成本 ≈ $44/月

> 本 Gate 僅控制本文件稍後所述的停機動作是否可在 Task 16 下被執行。通過本 Gate **不代表**該動作已獲授權執行 —— 詳見停機順序前的警示框。

## 安全說明（必須逐項接受）

- [ ] self-hosted Copilot 必須關閉 GitHub 內建 firewall
- [ ] 本方案**不做**網路 egress 過濾，Copilot job 可自由連往公開網際網路（與 GitHub-hosted runner 相同）
- [ ] 補償措施：平台代管網路不連接任何自有 VNet（無內部網路存取）、`--ephemeral` 單次執行、僅服務 private repos、PAT 最小權限並定期輪替
- [ ] runner Job 掛載的 user-assigned managed identity 已透過 `identitySettings`（`lifecycle: 'None'`，見 `modules/runnerJob.bicep`）限定範圍，runner 的 main container 無法呼叫 Container Apps identity endpoint 換發該身分的 token；該身分僅供平台用於 ACR image pull 與 Key Vault secret 解析

## PoC 驗收記錄表

| 量測項目 | 記錄值 | 通過條件 |
|---|---|---|
| scale-from-zero p95（queued → runner ready） | | ≤ 5 分鐘 |
| general job 實際執行時間 p99 | | < `generalReplicaTimeoutSeconds` × 0.75 |
| peak ephemeral storage | | < 8 GiB |
| `runs-on: self-hosted` 未被 ACA runner 取走 | | true |
| job 內 `printenv` 與 `/proc/1/environ` 皆無 `GITHUB_PAT` | | true |
| 已部署 runner Job 掛載的 UAMI，其 `identitySettings` lifecycle 為 `None`（由 `scripts/verify-aca-runner.sh` 驗證） | | true |
| GitHub API rate limit 用量 | | < 40% |

---

## ⚠️ AKS 長期停機順序 —— 尚未核准的未來選項（Deferred）

**不得執行本節任何步驟。** 本節僅記錄未來**唯有**在下列條件全部成立後才適用的順序：
- Task 15 已選定路徑 (a) 或 (b)（見 Gate C），**且**
- Task 16 已取得使用者明確、獨立的停機核准，**且**
- 上方 Gate C 已附證據全部勾選完成。

在此之前，live AKS 叢集維持現狀持續運行。本節存在的目的，是確保一旦停機日後獲得獨立核准時，步驟不會被跳過或調換順序。

**AKS 長期停機順序（不可跳步，且刻意不含刪除）：**

- [ ] 1. 停用 `startAks` timer（否則每日自動重啟會使停機失效）
- [ ] 2. 確認無 workflow 或 `copilot-setup-steps.yml` 引用 `arc-runner-set` / `arc-android`
- [ ] 3. **保留 ARC 安裝**，不執行 `helm uninstall`，以維持復原能力
- [ ] 4. `az aks stop` 並確認 `powerState.code` 為 `Stopped`
- [ ] 5. 匯出成本基線與設定，記錄於本 runbook
- [ ] 6. 建立每 6 個月一次的「啟動 → 驗證 → 再停機」提醒（停機狀態最多保存 12 個月）
- [ ] 7. 記錄復原程序與已知限制（啟動後 API server IP 可能改變；容量緊張區域可能無法啟動已停止的叢集）
- [ ] 8. 更新雙語文件與本 runbook

## 📖 相關文件

- [English version](RUNBOOK.md)
- [ACA Runner README](../../../src/github/aca-runner/README_zh-tw.md)
- [AKS Runner README](../../../src/github/aks-runner/README_zh-tw.md) — 現行 fallback，維持不變
