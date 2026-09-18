import { app, InvocationContext, Timer } from '@azure/functions';
import { DefaultAzureCredential } from '@azure/identity';
import { ContainerServiceClient } from '@azure/arm-containerservice';
import { runStopAks, type ClientFactory, type Logger } from '../aksOperations.js';
import { resolveSchedule } from '../aksPower.js';

// ============================================================================
// Timer Trigger — 定時停止 AKS 叢集 (fail-closed)
//
// 唯一的啟用開關是 app setting `AKS_STOP_ENABLED`：由 aksOperations.ts 的
// runStopAks 在「解析 AKS_CLUSTERS、建立 credential/client、發出任何 Azure
// 呼叫之前」檢查 (isStopScheduleEnabled)，只有去除前後空白後精確等於
// (不分大小寫) 'true' 才會實際執行；缺少、空白、'false'、或任何其他值
// 一律視為停用並直接返回，確保設定缺失/錯誤時預設不會誤停正在使用中的叢集。
// Bicep 參數 enableStopSchedule (預設 false) 一對一對應到本 app setting，
// 透過 `AKS_STOP_ENABLED: string(enableStopSchedule)` 產生。
//
// ── Flex Consumption Timer Trigger 僅支援 UTC ──────────────────────────────
// Flex Consumption 目前不支援 WEBSITE_TIME_ZONE / TZ 來調整 Timer Trigger
// 的解讀時區，NCRONTAB 一律以 UTC 執行；詳見:
//   https://learn.microsoft.com/en-us/azure/azure-functions/errors-diagnostics/diagnostic-events/azfd0010
//   https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-timer#time-zones
// 因此本專案的排程一律以 UTC cron 表示式設定，操作者需自行換算並在 DST
// (日光節約時間) 切換時手動更新 UTC 表示式 (Azure Functions 不會自動調整)。
// 詳見 README.md「時區與排程」章節。
// ============================================================================

const credential = new DefaultAzureCredential();

const clientFactory: ClientFactory = (subscriptionId: string) =>
  new ContainerServiceClient(credential, subscriptionId);

async function stopAks(myTimer: Timer, context: InvocationContext): Promise<void> {
  const logger: Logger = {
    log: (message: string) => context.log(message),
    error: (message: string) => context.error(message),
  };

  await runStopAks(
    {
      aksClustersRaw: process.env.AKS_CLUSTERS,
      stopEnabledRaw: process.env.AKS_STOP_ENABLED,
    },
    clientFactory,
    logger,
  );
}

// 預設 UTC 排程 0 0 14 * * * = 每日 UTC 14:00，對應台北時間 (UTC+8) 當天
// 22:00。可透過 AKS_STOP_SCHEDULE_UTC app setting 覆寫；未設定時回退為
// 此預設值。排程本身與 AKS_STOP_ENABLED 開關互相獨立：即使排程觸發，
// 若開關未精確為 'true' 仍不會執行任何動作 (見上方 fail-closed 說明)。
app.timer('stopAks', {
  schedule: resolveSchedule(process.env.AKS_STOP_SCHEDULE_UTC, '0 0 14 * * *'),
  handler: stopAks,
});
