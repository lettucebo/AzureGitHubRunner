// ============================================================================
// aksPower — 純函式共用邏輯 (AKS_CLUSTERS 解析 / 電源狀態決策 / 排程設定解析)
//
// 刻意獨立於 src/functions/*.ts 之外，且不依賴 @azure/functions 或
// @azure/arm-containerservice，方便撰寫不需 mock Azure SDK 的單元測試。
// 對應測試位於 test/aksPower.test.ts (package.json main 只會索引
// dist/src/functions/*.js，因此測試檔不可放在 src/functions 底下)。
// ============================================================================

/** 單一 AKS 叢集目標設定 */
export interface AksClusterTarget {
  subscriptionId: string;
  resourceGroup: string;
  name: string;
}

/** 解析 AKS_CLUSTERS 環境變數的結果 */
export type ParseAksClustersResult =
  | { ok: true; clusters: AksClusterTarget[] }
  | { ok: false; error: string };

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function isValidTarget(item: unknown): item is AksClusterTarget {
  if (typeof item !== 'object' || item === null) {
    return false;
  }
  const candidate = item as Record<string, unknown>;
  return (
    isNonEmptyString(candidate.subscriptionId) &&
    isNonEmptyString(candidate.resourceGroup) &&
    isNonEmptyString(candidate.name)
  );
}

/**
 * 安全解析 AKS_CLUSTERS 環境變數。
 * 必須是「非空 JSON 陣列」，且每筆項目的 subscriptionId/resourceGroup/name
 * 皆須為非空字串，否則回傳明確的錯誤原因、不進行任何 Azure 呼叫。
 *
 * 修正既有錯誤: 舊實作只做 `JSON.parse` 後直接當作陣列使用，
 * 若設定成合法但「非陣列」的 JSON (例如物件、字串、數字)，
 * 會繞過原本的長度檢查而在後續程式碼中造成非預期行為。
 */
export function parseAksClusters(raw: string | undefined): ParseAksClustersResult {
  if (!isNonEmptyString(raw)) {
    return { ok: false, error: 'AKS_CLUSTERS 環境變數未設定或為空白' };
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return { ok: false, error: 'AKS_CLUSTERS 格式錯誤，無法解析為 JSON' };
  }

  if (!Array.isArray(parsed)) {
    return { ok: false, error: 'AKS_CLUSTERS 必須是 JSON 陣列，而非其他型別' };
  }

  if (parsed.length === 0) {
    return { ok: false, error: 'AKS_CLUSTERS 為空陣列，沒有任何叢集可處理' };
  }

  const clusters: AksClusterTarget[] = [];
  for (let index = 0; index < parsed.length; index += 1) {
    const item = parsed[index];
    if (!isValidTarget(item)) {
      return {
        ok: false,
        error: `AKS_CLUSTERS 第 ${index} 筆項目缺少有效的 subscriptionId/resourceGroup/name (需為非空字串)`,
      };
    }
    clusters.push(item);
  }

  return { ok: true, clusters };
}

/** 對單一叢集要採取的動作 */
export type ClusterAction = 'start' | 'stop' | 'skip';

export interface ActionDecision {
  action: ClusterAction;
  reason: string;
}

/**
 * 判斷是否應該啟動叢集。只有精確等於 'Stopped' 才會啟動，
 * 其餘狀態 (含 undefined / 未知字串) 一律跳過並附上明確原因。
 */
export function decideStartAction(powerState: string | undefined): ActionDecision {
  if (powerState === 'Stopped') {
    return { action: 'start', reason: '叢集電源狀態為 Stopped，將執行啟動' };
  }
  if (powerState === undefined) {
    return { action: 'skip', reason: '無法取得叢集電源狀態 (undefined)，跳過啟動' };
  }
  if (powerState === 'Running') {
    return { action: 'skip', reason: '叢集已在運行中 (Running)，跳過啟動' };
  }
  if (powerState === 'Starting') {
    return { action: 'skip', reason: '叢集正在啟動中 (Starting)，跳過啟動' };
  }
  if (powerState === 'Stopping') {
    return { action: 'skip', reason: '叢集正在停止中 (Stopping)，跳過啟動' };
  }
  return { action: 'skip', reason: `叢集電源狀態為未知值 (${powerState})，跳過啟動` };
}

/**
 * 判斷是否應該停止叢集。只有精確等於 'Running' 才會停止，
 * 其餘狀態 (含 undefined / 未知字串) 一律跳過並附上明確原因。
 */
export function decideStopAction(powerState: string | undefined): ActionDecision {
  if (powerState === 'Running') {
    return { action: 'stop', reason: '叢集電源狀態為 Running，將執行停止' };
  }
  if (powerState === undefined) {
    return { action: 'skip', reason: '無法取得叢集電源狀態 (undefined)，跳過停止' };
  }
  if (powerState === 'Stopped') {
    return { action: 'skip', reason: '叢集已為 Stopped，跳過停止' };
  }
  if (powerState === 'Starting') {
    return { action: 'skip', reason: '叢集正在啟動中 (Starting)，跳過停止' };
  }
  if (powerState === 'Stopping') {
    return { action: 'skip', reason: '叢集正在停止中 (Stopping)，跳過停止' };
  }
  return { action: 'skip', reason: `叢集電源狀態為未知值 (${powerState})，跳過停止` };
}

/**
 * 解析排程 app setting: 去除前後空白後若為非空字串則使用，
 * 否則回退到程式碼內建的預設值，確保未設定該 app setting 時
 * 既有的純程式碼部署 (無 Bicep app settings) 仍可正常索引/執行。
 */
export function resolveSchedule(envValue: string | undefined, fallback: string): string {
  const trimmed = envValue?.trim();
  return isNonEmptyString(trimmed) ? trimmed : fallback;
}
