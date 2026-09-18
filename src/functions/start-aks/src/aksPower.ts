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

/**
 * 解析 AKS_CLUSTERS 環境變數的結果。
 *
 * `ok: false` 僅用於「全域」失敗 (環境變數缺失/空白、JSON 格式錯誤、
 * 非陣列型別、空陣列)，這些情況下沒有任何項目可處理。
 *
 * 只要是「非空陣列」，即視為全域成功 (`ok: true`)：每個項目各自獨立驗證，
 * 無效項目只會被記錄在 `errors` (帶索引的明確原因) 並被排除，
 * 不會因單一項目無效而拒絕陣列中其餘合法的項目 (每叢集錯誤隔離)。
 * 若全部項目皆無效，`clusters` 為空陣列、`errors` 含每筆項目的原因，
 * 但 `ok` 仍為 true (因為陣列本身格式合法)。
 */
export type ParseAksClustersResult =
  | { ok: true; clusters: AksClusterTarget[]; errors: string[] }
  | { ok: false; error: string };

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

/**
 * 驗證並正規化單一項目。合法時回傳去除前後空白後的 AksClusterTarget，
 * 不合法時回傳帶索引的明確錯誤訊息，讓呼叫端可記錄並跳過該筆。
 */
function normalizeTarget(item: unknown, index: number): { target: AksClusterTarget } | { error: string } {
  if (typeof item !== 'object' || item === null) {
    return { error: `AKS_CLUSTERS 第 ${index} 筆項目並非物件，已略過此叢集` };
  }
  const candidate = item as Record<string, unknown>;
  const { subscriptionId, resourceGroup, name } = candidate;
  if (!isNonEmptyString(subscriptionId) || !isNonEmptyString(resourceGroup) || !isNonEmptyString(name)) {
    return {
      error: `AKS_CLUSTERS 第 ${index} 筆項目缺少有效的 subscriptionId/resourceGroup/name (需為非空字串)，已略過此叢集`,
    };
  }
  return {
    target: {
      subscriptionId: subscriptionId.trim(),
      resourceGroup: resourceGroup.trim(),
      name: name.trim(),
    },
  };
}

/**
 * 安全解析 AKS_CLUSTERS 環境變數。
 * 必須是「非空 JSON 陣列」，否則屬全域失敗、回傳明確錯誤原因、
 * 不進行任何 Azure 呼叫。陣列本身合法時，逐一驗證每筆項目，
 * 有效項目正規化 (trim) 後收集於 clusters，無效項目的原因收集於 errors，
 * 兩者互不影響 (per-cluster isolation)。
 *
 * 修正既有錯誤 1: 舊實作只做 `JSON.parse` 後直接當作陣列使用，
 * 若設定成合法但「非陣列」的 JSON (例如物件、字串、數字)，
 * 會繞過原本的長度檢查而在後續程式碼中造成非預期行為。
 *
 * 修正既有錯誤 2: 舊實作只要陣列中「任一筆」項目無效，就會讓整個
 * AKS_CLUSTERS 判定為全域失敗、連同其餘合法項目一併被跳過而不執行
 * 任何動作。現在無效項目只會各自被記錄並排除，其餘合法叢集仍會正常處理。
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
  const errors: string[] = [];
  parsed.forEach((item, index) => {
    const result = normalizeTarget(item, index);
    if ('target' in result) {
      clusters.push(result.target);
    } else {
      errors.push(result.error);
    }
  });

  return { ok: true, clusters, errors };
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

/**
 * Fail-closed 停止排程開關判斷。
 *
 * 唯一的真實來源是 `AKS_STOP_ENABLED` app setting：去除前後空白後，
 * 只有「精確等於」(不分大小寫) 字串 'true' 才視為啟用；缺少、空白、
 * 'false'，或任何其他值 (包含拼字錯誤) 一律視為停用。
 * 呼叫端必須在解析 AKS_CLUSTERS、建立 credential/client、或發出任何
 * Azure 呼叫「之前」呼叫本函式並提前返回，確保設定缺失或錯誤時
 * 預設不會執行任何停止操作 (fail closed)。
 */
export function isStopScheduleEnabled(envValue: string | undefined): boolean {
  return (envValue ?? '').trim().toLowerCase() === 'true';
}
