import { app, InvocationContext, Timer } from '@azure/functions';
import { DefaultAzureCredential } from '@azure/identity';
import { ContainerServiceClient } from '@azure/arm-containerservice';
import { runStartAks, type ClientFactory, type Logger } from '../aksOperations.js';
import { DEFAULT_START_SCHEDULE_UTC, resolveSchedule } from '../aksPower.js';

// ============================================================================
// Timer Trigger — 定時啟動 AKS 叢集
//
// 本檔案只負責 Azure Functions 相關的裝配 (wiring):
//   1. 建立一個 DefaultAzureCredential (跨多次呼叫重用)
//   2. 提供轉接 ContainerServiceClient 的 clientFactory
//   3. 將 InvocationContext 轉為 aksOperations.Logger
//   4. 將 process.env 轉為 aksOperations 所需的 config
//   5. 註冊 Timer trigger (UTC schedule — Flex Consumption 僅支援 UTC，
//      詳見 README.md「時區與排程」章節)
// 所有實際執行邏輯 (AKS_CLUSTERS 解析、per-cluster 錯誤隔離、電源狀態
// 決策、Azure SDK 呼叫順序) 皆在 src/aksOperations.ts 實作與測試。
// ============================================================================

const credential = new DefaultAzureCredential();

const clientFactory: ClientFactory = (subscriptionId: string) =>
  new ContainerServiceClient(credential, subscriptionId);

async function startAks(myTimer: Timer, context: InvocationContext): Promise<void> {
  const logger: Logger = {
    log: (message: string) => context.log(message),
    error: (message: string) => context.error(message),
  };

  await runStartAks({ aksClustersRaw: process.env.AKS_CLUSTERS }, clientFactory, logger);
}

// 預設 UTC 排程 0 25,40 16 * * * = 每日 UTC 16:25/16:40，對應台北時間
// (UTC+8) 隔天 00:25/00:40。公司約 00:05 強制停機後保留兩次嘗試，
// 以涵蓋停止/設定傳播延遲並提供重試韌性。Flex Consumption 的 Timer
// Trigger 一律以 UTC 解讀，詳見 README.md。可透過
// AKS_START_SCHEDULE_UTC app setting 覆寫；未設定時回退為此預設值。
app.timer('startAks', {
  schedule: resolveSchedule(process.env.AKS_START_SCHEDULE_UTC, DEFAULT_START_SCHEDULE_UTC),
  handler: startAks,
});
