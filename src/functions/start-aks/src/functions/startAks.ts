import { app, InvocationContext, Timer } from '@azure/functions';
import { DefaultAzureCredential } from '@azure/identity';
import { ContainerServiceClient } from '@azure/arm-containerservice';
import { parseAksClusters, decideStartAction, resolveSchedule, AksClusterTarget } from '../aksPower.js';

// ============================================================================
// 型別定義
// ============================================================================

interface StartResult {
  cluster: string;
  status: 'started' | 'skipped' | 'failed';
  message: string;
}

// ============================================================================
// Timer Trigger — 定時啟動 AKS 叢集
// ============================================================================

async function startAks(myTimer: Timer, context: InvocationContext): Promise<void> {
  context.log('開始執行 AKS 叢集啟動排程');

  const parseResult = parseAksClusters(process.env.AKS_CLUSTERS);
  if (!parseResult.ok) {
    context.error(`AKS_CLUSTERS 驗證失敗: ${parseResult.error}`);
    return;
  }
  const clusters: AksClusterTarget[] = parseResult.clusters;

  context.log(`共 ${clusters.length} 個叢集待處理`);

  const credential = new DefaultAzureCredential();
  const results: StartResult[] = [];

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

      const decision = decideStartAction(powerState);
      if (decision.action === 'start') {
        context.log(`正在啟動叢集 ${clusterDisplayName}... (${decision.reason})`);
        await client.managedClusters.beginStartAndWait(cluster.resourceGroup, cluster.name);
        context.log(`✓ 叢集 ${clusterDisplayName} 啟動完成`);
        results.push({ cluster: clusterDisplayName, status: 'started', message: '啟動完成' });
      } else {
        context.log(`跳過叢集 ${clusterDisplayName}: ${decision.reason}`);
        results.push({ cluster: clusterDisplayName, status: 'skipped', message: decision.reason });
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      context.error(`❌ 叢集 ${clusterDisplayName} 啟動失敗: ${errorMessage}`);
      results.push({ cluster: clusterDisplayName, status: 'failed', message: errorMessage });
    }
  }

  // 彙整結果
  const started = results.filter(r => r.status === 'started').length;
  const skipped = results.filter(r => r.status === 'skipped').length;
  const failed = results.filter(r => r.status === 'failed').length;

  context.log(`執行完畢 — 啟動: ${started}, 跳過: ${skipped}, 失敗: ${failed}`);

  if (failed > 0) {
    context.error('部分叢集啟動失敗，請檢查上方日誌');
  }
}

// 排程觸發時間（搭配 WEBSITE_TIME_ZONE=Asia/Taipei；已實測生效：舊 06:00 排程於 22:00Z 觸發 = 06:00 台北）
// 公司強制每日 00:05 台北停機（~2.5 分完成，~00:08）。為最小化停機視窗：
//   - 主要：00:25 與 00:40（停機後 ~17/32 分再啟動，完全落在 AKS 官方「停機後等 15–30 分」建議區間；
//     兩次嘗試涵蓋反配置延遲；停機視窗由 ~6h 縮到 ~20 分）
//   - fallback：06:00（保底，維持原行為，萬一前兩次都失敗也不會比原本更差）
// handler 具冪等性（powerState 非 Stopped 即 skip），故多次觸發安全。
// 排程可透過 AKS_START_SCHEDULE / AKS_START_FALLBACK_SCHEDULE app setting 覆寫；
// 未設定時回退為以下預設值 (與既有純程式碼部署行為一致，不會因缺少 app setting 而索引失敗)。
app.timer('startAks', {
  schedule: resolveSchedule(process.env.AKS_START_SCHEDULE, '0 25,40 0 * * *'),
  handler: startAks,
});

app.timer('startAksFallback', {
  schedule: resolveSchedule(process.env.AKS_START_FALLBACK_SCHEDULE, '0 0 6 * * *'),
  handler: startAks,
});
