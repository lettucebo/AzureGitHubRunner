// ============================================================================
// aksOperations — 可測試的執行邏輯 (start/stop AKS 叢集的完整流程)
//
// 刻意獨立於 src/functions/*.ts，透過注入的 client factory / logger / config
// 提供純邏輯層測試，不依賴 @azure/functions (InvocationContext/Timer) 或
// 真實 @azure/arm-containerservice SDK。
//
// src/functions/startAks.ts / stopAks.ts 僅負責：
//   1. 建立一個 DefaultAzureCredential
//   2. 提供轉接 ContainerServiceClient 的 clientFactory
//   3. 將 process.env 轉為此處所需的 config
//   4. 註冊 Timer trigger (UTC schedule)
// 其餘所有邏輯 (含 fail-closed 開關、AKS_CLUSTERS 解析、per-cluster
// 錯誤隔離、電源狀態決策) 皆在本檔案實作與測試。
// ============================================================================

import {
  parseAksClusters,
  decideStartAction,
  decideStopAction,
  isStopScheduleEnabled,
  type AksClusterTarget,
} from './aksPower.js';

// ============================================================================
// 型別定義
// ============================================================================

/** 最小化 logger 介面，由呼叫端 (Azure Functions InvocationContext 或測試 mock) 提供 */
export interface Logger {
  log(message: string): void;
  error(message: string): void;
}

/** @azure/arm-containerservice ManagedCluster 中，本模組實際用到的最小欄位 */
export interface ManagedClusterLike {
  powerState?: { code?: string };
}

/** @azure/arm-containerservice ContainerServiceClient.managedClusters 的最小介面 */
export interface ManagedClustersOperationsLike {
  get(resourceGroupName: string, resourceName: string): Promise<ManagedClusterLike>;
  beginStartAndWait(resourceGroupName: string, resourceName: string): Promise<unknown>;
  beginStopAndWait(resourceGroupName: string, resourceName: string): Promise<unknown>;
}

/** @azure/arm-containerservice ContainerServiceClient 的最小介面 */
export interface ContainerServiceClientLike {
  managedClusters: ManagedClustersOperationsLike;
}

/** 依 subscriptionId 建立對應的 ContainerServiceClient (或相容 mock) */
export type ClientFactory = (subscriptionId: string) => ContainerServiceClientLike;

/** 單一叢集的處理結果 */
export interface ClusterResult {
  cluster: string;
  status: 'started' | 'stopped' | 'skipped' | 'failed';
  message: string;
}

export interface RunStartConfig {
  aksClustersRaw: string | undefined;
}

export interface RunStopConfig {
  aksClustersRaw: string | undefined;
  stopEnabledRaw: string | undefined;
}

// ============================================================================
// 共用工具
// ============================================================================

function clusterDisplayName(cluster: AksClusterTarget): string {
  return `${cluster.resourceGroup}/${cluster.name}`;
}

/** 記錄 parseAksClusters 產生的每一筆項目錯誤 (per-cluster isolation 的錯誤可見性) */
function logClusterErrors(errors: string[], logger: Logger): void {
  for (const error of errors) {
    logger.error(`AKS_CLUSTERS 項目驗證失敗: ${error}`);
  }
}

// ============================================================================
// runStartAks — 啟動排程執行邏輯
// ============================================================================

export async function runStartAks(
  config: RunStartConfig,
  clientFactory: ClientFactory,
  logger: Logger,
): Promise<ClusterResult[]> {
  logger.log('開始執行 AKS 叢集啟動排程');

  const parseResult = parseAksClusters(config.aksClustersRaw);
  if (!parseResult.ok) {
    logger.error(`AKS_CLUSTERS 驗證失敗: ${parseResult.error}`);
    return [];
  }

  logClusterErrors(parseResult.errors, logger);

  const clusters = parseResult.clusters;
  logger.log(`共 ${clusters.length} 個有效叢集待處理 (${parseResult.errors.length} 筆項目因驗證失敗已略過)`);

  const results: ClusterResult[] = [];

  // 逐一處理每個有效叢集（錯誤隔離：單一叢集失敗不影響後續叢集）
  for (const cluster of clusters) {
    const displayName = clusterDisplayName(cluster);
    logger.log(`處理叢集: ${displayName}`);

    try {
      const client = clientFactory(cluster.subscriptionId);
      const aksCluster = await client.managedClusters.get(cluster.resourceGroup, cluster.name);
      const powerState = aksCluster.powerState?.code;
      logger.log(`叢集 ${displayName} 目前狀態: ${powerState}`);

      const decision = decideStartAction(powerState);
      if (decision.action === 'start') {
        logger.log(`正在啟動叢集 ${displayName}... (${decision.reason})`);
        await client.managedClusters.beginStartAndWait(cluster.resourceGroup, cluster.name);
        logger.log(`✓ 叢集 ${displayName} 啟動完成`);
        results.push({ cluster: displayName, status: 'started', message: '啟動完成' });
      } else {
        logger.log(`跳過叢集 ${displayName}: ${decision.reason}`);
        results.push({ cluster: displayName, status: 'skipped', message: decision.reason });
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(`❌ 叢集 ${displayName} 啟動失敗: ${errorMessage}`);
      results.push({ cluster: displayName, status: 'failed', message: errorMessage });
    }
  }

  const started = results.filter((r) => r.status === 'started').length;
  const skipped = results.filter((r) => r.status === 'skipped').length;
  const failed = results.filter((r) => r.status === 'failed').length;
  logger.log(`執行完畢 — 啟動: ${started}, 跳過: ${skipped}, 失敗: ${failed}`);
  if (failed > 0) {
    logger.error('部分叢集啟動失敗，請檢查上方日誌');
  }

  return results;
}

// ============================================================================
// runStopAks — 停止排程執行邏輯 (fail-closed)
// ============================================================================

export async function runStopAks(
  config: RunStopConfig,
  clientFactory: ClientFactory,
  logger: Logger,
): Promise<ClusterResult[]> {
  // Fail-closed 開關檢查必須是第一步：在解析 AKS_CLUSTERS、建立
  // credential/client、或發出任何 Azure 呼叫「之前」就返回，確保
  // AKS_STOP_ENABLED 缺失/錯誤設定時，預設不會執行任何停止操作。
  if (!isStopScheduleEnabled(config.stopEnabledRaw)) {
    logger.log(
      `AKS_STOP_ENABLED 未精確設為 "true" (目前值: ${JSON.stringify(config.stopEnabledRaw ?? null)})，` +
        '停止排程停用，本次不解析 AKS_CLUSTERS、不建立任何 Azure 用戶端、不發出任何呼叫',
    );
    return [];
  }

  logger.log('AKS_STOP_ENABLED=true，開始執行 AKS 叢集停止排程');

  const parseResult = parseAksClusters(config.aksClustersRaw);
  if (!parseResult.ok) {
    logger.error(`AKS_CLUSTERS 驗證失敗: ${parseResult.error}`);
    return [];
  }

  logClusterErrors(parseResult.errors, logger);

  const clusters = parseResult.clusters;
  logger.log(`共 ${clusters.length} 個有效叢集待處理 (${parseResult.errors.length} 筆項目因驗證失敗已略過)`);

  const results: ClusterResult[] = [];

  // 逐一處理每個有效叢集（錯誤隔離：單一叢集失敗不影響後續叢集）
  for (const cluster of clusters) {
    const displayName = clusterDisplayName(cluster);
    logger.log(`處理叢集: ${displayName}`);

    try {
      const client = clientFactory(cluster.subscriptionId);
      const aksCluster = await client.managedClusters.get(cluster.resourceGroup, cluster.name);
      const powerState = aksCluster.powerState?.code;
      logger.log(`叢集 ${displayName} 目前狀態: ${powerState}`);

      const decision = decideStopAction(powerState);
      if (decision.action === 'stop') {
        logger.log(`正在停止叢集 ${displayName}... (${decision.reason})`);
        await client.managedClusters.beginStopAndWait(cluster.resourceGroup, cluster.name);
        logger.log(`✓ 叢集 ${displayName} 停止完成`);
        results.push({ cluster: displayName, status: 'stopped', message: '停止完成' });
      } else {
        logger.log(`跳過叢集 ${displayName}: ${decision.reason}`);
        results.push({ cluster: displayName, status: 'skipped', message: decision.reason });
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(`❌ 叢集 ${displayName} 停止失敗: ${errorMessage}`);
      results.push({ cluster: displayName, status: 'failed', message: errorMessage });
    }
  }

  const stopped = results.filter((r) => r.status === 'stopped').length;
  const skipped = results.filter((r) => r.status === 'skipped').length;
  const failed = results.filter((r) => r.status === 'failed').length;
  logger.log(`執行完畢 — 停止: ${stopped}, 跳過: ${skipped}, 失敗: ${failed}`);
  if (failed > 0) {
    logger.error('部分叢集停止失敗，請檢查上方日誌');
  }

  return results;
}
