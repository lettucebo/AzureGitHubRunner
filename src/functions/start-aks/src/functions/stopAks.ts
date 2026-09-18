import { app, InvocationContext, Timer } from '@azure/functions';
import { DefaultAzureCredential } from '@azure/identity';
import { ContainerServiceClient } from '@azure/arm-containerservice';
import { parseAksClusters, decideStopAction, resolveSchedule, AksClusterTarget } from '../aksPower.js';

// ============================================================================
// 型別定義
// ============================================================================

interface StopResult {
  cluster: string;
  status: 'stopped' | 'skipped' | 'failed';
  message: string;
}

// ============================================================================
// Timer Trigger — 定時停止 AKS 叢集
//
// 預設透過官方 app setting `AzureWebJobs.stopAks.Disabled=true` 停用，
// 需要由 Bicep 參數 `enableStopSchedule=true` 明確開啟，避免誤停正在
// 使用中的叢集。只有電源狀態精確為 'Running' 時才會呼叫 beginStopAndWait，
// 其餘狀態 (Stopped / Stopping / Starting / undefined / 未知值) 一律跳過並記錄原因。
// ============================================================================

async function stopAks(myTimer: Timer, context: InvocationContext): Promise<void> {
  context.log('開始執行 AKS 叢集停止排程');

  const parseResult = parseAksClusters(process.env.AKS_CLUSTERS);
  if (!parseResult.ok) {
    context.error(`AKS_CLUSTERS 驗證失敗: ${parseResult.error}`);
    return;
  }
  const clusters: AksClusterTarget[] = parseResult.clusters;

  context.log(`共 ${clusters.length} 個叢集待處理`);

  const credential = new DefaultAzureCredential();
  const results: StopResult[] = [];

  // 逐一處理每個叢集（錯誤隔離：單一叢集失敗不影響後續叢集）
  for (const cluster of clusters) {
    const clusterDisplayName = `${cluster.resourceGroup}/${cluster.name}`;
    context.log(`處理叢集: ${clusterDisplayName}`);

    try {
      const client = new ContainerServiceClient(credential, cluster.subscriptionId);

      // 檢查叢集電源狀態
      const aksCluster = await client.managedClusters.get(cluster.resourceGroup, cluster.name);
      const powerState = aksCluster.powerState?.code;
      context.log(`叢集 ${clusterDisplayName} 目前狀態: ${powerState}`);

      const decision = decideStopAction(powerState);
      if (decision.action === 'stop') {
        context.log(`正在停止叢集 ${clusterDisplayName}... (${decision.reason})`);
        await client.managedClusters.beginStopAndWait(cluster.resourceGroup, cluster.name);
        context.log(`✓ 叢集 ${clusterDisplayName} 停止完成`);
        results.push({ cluster: clusterDisplayName, status: 'stopped', message: '停止完成' });
      } else {
        context.log(`跳過叢集 ${clusterDisplayName}: ${decision.reason}`);
        results.push({ cluster: clusterDisplayName, status: 'skipped', message: decision.reason });
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      context.error(`❌ 叢集 ${clusterDisplayName} 停止失敗: ${errorMessage}`);
      results.push({ cluster: clusterDisplayName, status: 'failed', message: errorMessage });
    }
  }

  // 彙整結果
  const stopped = results.filter(r => r.status === 'stopped').length;
  const skipped = results.filter(r => r.status === 'skipped').length;
  const failed = results.filter(r => r.status === 'failed').length;

  context.log(`執行完畢 — 停止: ${stopped}, 跳過: ${skipped}, 失敗: ${failed}`);

  if (failed > 0) {
    context.error('部分叢集停止失敗，請檢查上方日誌');
  }
}

// 排程可透過 AKS_STOP_SCHEDULE app setting 覆寫；未設定時回退為預設值。
// 函式本身預設停用 (見 modules/functionApp.bicep 的 AzureWebJobs.stopAks.Disabled)，
// 需由 Bicep 參數 enableStopSchedule=true 明確開啟才會實際觸發。
app.timer('stopAks', {
  schedule: resolveSchedule(process.env.AKS_STOP_SCHEDULE, '0 0 20 * * *'),
  handler: stopAks,
});
