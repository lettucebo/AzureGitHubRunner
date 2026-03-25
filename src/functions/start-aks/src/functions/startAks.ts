import { app, InvocationContext, Timer } from '@azure/functions';
import { DefaultAzureCredential } from '@azure/identity';
import { ContainerServiceClient } from '@azure/arm-containerservice';

// ============================================================================
// 型別定義
// ============================================================================

interface AksClusterTarget {
  subscriptionId: string;
  resourceGroup: string;
  name: string;
}

interface StartResult {
  cluster: string;
  status: 'started' | 'already-running' | 'failed';
  message: string;
}

// ============================================================================
// Timer Trigger — 定時啟動 AKS 叢集
// ============================================================================

async function startAks(myTimer: Timer, context: InvocationContext): Promise<void> {
  context.log('開始執行 AKS 叢集啟動排程');

  // 讀取叢集設定
  const clustersJson = process.env.AKS_CLUSTERS;
  if (!clustersJson) {
    context.error('環境變數 AKS_CLUSTERS 未設定');
    return;
  }

  let clusters: AksClusterTarget[];
  try {
    clusters = JSON.parse(clustersJson) as AksClusterTarget[];
  } catch {
    context.error('AKS_CLUSTERS 格式錯誤，請提供有效的 JSON 陣列');
    return;
  }

  if (clusters.length === 0) {
    context.warn('AKS_CLUSTERS 陣列為空，無叢集需要啟動');
    return;
  }

  context.log(`共 ${clusters.length} 個叢集待處理`);

  const credential = new DefaultAzureCredential();
  const results: StartResult[] = [];

  // 逐一處理每個叢集（錯誤隔離）
  for (const cluster of clusters) {
    const clusterDisplayName = `${cluster.resourceGroup}/${cluster.name}`;
    context.log(`處理叢集: ${clusterDisplayName}`);

    try {
      const client = new ContainerServiceClient(credential, cluster.subscriptionId);

      // 檢查叢集電源狀態
      const aksCluster = await client.managedClusters.get(cluster.resourceGroup, cluster.name);
      const powerState = aksCluster.powerState?.code;
      context.log(`叢集 ${clusterDisplayName} 目前狀態: ${powerState}`);

      if (powerState === 'Stopped') {
        context.log(`正在啟動叢集 ${clusterDisplayName}...`);
        await client.managedClusters.beginStartAndWait(cluster.resourceGroup, cluster.name);
        context.log(`✓ 叢集 ${clusterDisplayName} 啟動完成`);
        results.push({ cluster: clusterDisplayName, status: 'started', message: '啟動完成' });
      } else {
        context.log(`叢集 ${clusterDisplayName} 已在運行中 (${powerState})，跳過`);
        results.push({ cluster: clusterDisplayName, status: 'already-running', message: `目前狀態: ${powerState}` });
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      context.error(`❌ 叢集 ${clusterDisplayName} 啟動失敗: ${errorMessage}`);
      results.push({ cluster: clusterDisplayName, status: 'failed', message: errorMessage });
    }
  }

  // 彙整結果
  const started = results.filter(r => r.status === 'started').length;
  const alreadyRunning = results.filter(r => r.status === 'already-running').length;
  const failed = results.filter(r => r.status === 'failed').length;

  context.log(`執行完畢 — 啟動: ${started}, 已運行: ${alreadyRunning}, 失敗: ${failed}`);

  if (failed > 0) {
    context.error('部分叢集啟動失敗，請檢查上方日誌');
  }
}

// 每天台北時間 06:00 觸發（搭配 WEBSITE_TIME_ZONE=Asia/Taipei）
app.timer('startAks', {
  schedule: '0 0 6 * * *',
  handler: startAks,
});
