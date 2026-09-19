// ============================================================================
// aksOperations 單元測試 — Node.js 內建測試執行器 (node:test)
//
// 測試 runStartAks / runStopAks 這兩個「可測試的執行邏輯」：
// 透過注入的 client factory / logger 驗證零呼叫、per-cluster 隔離、
// 以及 stopAks 的 fail-closed 開關行為，完全不依賴 @azure/functions
// 或真實 Azure SDK。
// ============================================================================

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  runStartAks,
  runStopAks,
  type ClientFactory,
  type ContainerServiceClientLike,
  type Logger,
} from '../src/aksOperations.js';

function createLogger(): Logger & { logs: string[]; errors: string[] } {
  const logs: string[] = [];
  const errors: string[] = [];
  return {
    logs,
    errors,
    log: (message: string) => logs.push(message),
    error: (message: string) => errors.push(message),
  };
}

interface FakeClientCall {
  method: 'get' | 'beginStartAndWait' | 'beginStopAndWait';
  resourceGroup: string;
  name: string;
}

function createFakeClientFactory(
  powerStates: Record<string, string | undefined>,
): { factory: ClientFactory; calls: FakeClientCall[]; factoryCalls: string[] } {
  const calls: FakeClientCall[] = [];
  const factoryCalls: string[] = [];
  const factory: ClientFactory = (subscriptionId: string): ContainerServiceClientLike => {
    factoryCalls.push(subscriptionId);
    return {
      managedClusters: {
        get: async (resourceGroup: string, name: string) => {
          calls.push({ method: 'get', resourceGroup, name });
          return { powerState: { code: powerStates[name] } };
        },
        beginStartAndWait: async (resourceGroup: string, name: string) => {
          calls.push({ method: 'beginStartAndWait', resourceGroup, name });
        },
        beginStopAndWait: async (resourceGroup: string, name: string) => {
          calls.push({ method: 'beginStopAndWait', resourceGroup, name });
        },
      },
    };
  };
  return { factory, calls, factoryCalls };
}

describe('runStartAks', () => {
  test('AKS_CLUSTERS 全域失敗時記錄錯誤、不建立任何 client', async () => {
    const logger = createLogger();
    const { factory, calls, factoryCalls } = createFakeClientFactory({});

    const results = await runStartAks({ aksClustersRaw: undefined }, factory, logger);

    assert.equal(results.length, 0);
    assert.equal(factoryCalls.length, 0);
    assert.equal(calls.length, 0);
    assert.ok(logger.errors.some((message) => message.includes('AKS_CLUSTERS')));
  });

  test('混合有效/無效叢集: 記錄每筆項目錯誤，僅對有效叢集呼叫 get + beginStartAndWait', async () => {
    const logger = createLogger();
    const { factory, calls, factoryCalls } = createFakeClientFactory({
      'aks-1': 'Stopped',
      'aks-3': 'Stopped',
    });

    const raw = JSON.stringify([
      { subscriptionId: 'sub-1', resourceGroup: 'rg-1', name: 'aks-1' },
      { subscriptionId: 'sub-2' },
      { subscriptionId: 'sub-3', resourceGroup: 'rg-3', name: 'aks-3' },
    ]);

    const results = await runStartAks({ aksClustersRaw: raw }, factory, logger);

    assert.equal(factoryCalls.length, 2);
    assert.deepEqual(factoryCalls, ['sub-1', 'sub-3']);
    assert.equal(calls.filter((c) => c.method === 'get').length, 2);
    assert.equal(calls.filter((c) => c.method === 'beginStartAndWait').length, 2);
    assert.equal(results.length, 2);
    assert.ok(results.every((r) => r.status === 'started'));
    assert.ok(logger.errors.some((message) => message.includes('第 1 筆')));
  });

  test('全部項目皆無效時: 記錄所有項目錯誤，且不建立任何 client (無有效目標可處理)', async () => {
    const logger = createLogger();
    const { factory, calls, factoryCalls } = createFakeClientFactory({});

    const raw = JSON.stringify([{ subscriptionId: 'sub-1' }, { resourceGroup: 'rg-1' }]);
    const results = await runStartAks({ aksClustersRaw: raw }, factory, logger);

    assert.equal(results.length, 0);
    assert.equal(factoryCalls.length, 0);
    assert.equal(calls.length, 0);
    assert.equal(logger.errors.filter((message) => message.includes('第')).length, 2);
  });
});

describe('runStopAks — fail-closed 開關', () => {
  test('AKS_STOP_ENABLED 未設定 (absent/default): 不解析叢集、不建立 client、零呼叫', async () => {
    const logger = createLogger();
    const { factory, calls, factoryCalls } = createFakeClientFactory({ 'aks-1': 'Running' });

    const results = await runStopAks(
      {
        aksClustersRaw: JSON.stringify([{ subscriptionId: 'sub-1', resourceGroup: 'rg-1', name: 'aks-1' }]),
        stopEnabledRaw: undefined,
      },
      factory,
      logger,
    );

    assert.equal(results.length, 0);
    assert.equal(factoryCalls.length, 0);
    assert.equal(calls.length, 0);
    assert.ok(logger.logs.some((message) => message.includes('AKS_STOP_ENABLED')));
  });

  test('AKS_STOP_ENABLED=false: 不解析叢集、不建立 client、零呼叫', async () => {
    const logger = createLogger();
    const { factory, calls, factoryCalls } = createFakeClientFactory({ 'aks-1': 'Running' });

    const results = await runStopAks(
      {
        aksClustersRaw: JSON.stringify([{ subscriptionId: 'sub-1', resourceGroup: 'rg-1', name: 'aks-1' }]),
        stopEnabledRaw: 'false',
      },
      factory,
      logger,
    );

    assert.equal(results.length, 0);
    assert.equal(factoryCalls.length, 0);
    assert.equal(calls.length, 0);
  });

  test('AKS_STOP_ENABLED 為無效的 AKS_CLUSTERS 仍不解析叢集 (開關檢查先於解析)', async () => {
    const logger = createLogger();
    const { factory, calls, factoryCalls } = createFakeClientFactory({});

    const results = await runStopAks(
      { aksClustersRaw: '{not valid json', stopEnabledRaw: undefined },
      factory,
      logger,
    );

    assert.equal(results.length, 0);
    assert.equal(factoryCalls.length, 0);
    assert.equal(calls.length, 0);
    // 不應出現 AKS_CLUSTERS JSON 解析錯誤訊息，因為根本沒有執行到解析步驟
    assert.ok(!logger.errors.some((message) => message.includes('JSON')));
  });

  test('AKS_STOP_ENABLED=true + Running: 呼叫 get + beginStopAndWait', async () => {
    const logger = createLogger();
    const { factory, calls, factoryCalls } = createFakeClientFactory({ 'aks-1': 'Running' });

    const results = await runStopAks(
      {
        aksClustersRaw: JSON.stringify([{ subscriptionId: 'sub-1', resourceGroup: 'rg-1', name: 'aks-1' }]),
        stopEnabledRaw: 'true',
      },
      factory,
      logger,
    );

    assert.equal(factoryCalls.length, 1);
    assert.equal(calls.filter((c) => c.method === 'get').length, 1);
    assert.equal(calls.filter((c) => c.method === 'beginStopAndWait').length, 1);
    assert.equal(results.length, 1);
    assert.equal(results[0].status, 'stopped');
  });

  test('AKS_STOP_ENABLED=true + 混合有效/無效叢集: 兩個有效叢集皆收到 get + beginStopAndWait', async () => {
    const logger = createLogger();
    const { factory, calls, factoryCalls } = createFakeClientFactory({
      'aks-1': 'Running',
      'aks-3': 'Running',
    });

    const raw = JSON.stringify([
      { subscriptionId: 'sub-1', resourceGroup: 'rg-1', name: 'aks-1' },
      { subscriptionId: 'sub-2' },
      { subscriptionId: 'sub-3', resourceGroup: 'rg-3', name: 'aks-3' },
    ]);

    const results = await runStopAks({ aksClustersRaw: raw, stopEnabledRaw: 'true' }, factory, logger);

    assert.equal(factoryCalls.length, 2);
    assert.equal(calls.filter((c) => c.method === 'get').length, 2);
    assert.equal(calls.filter((c) => c.method === 'beginStopAndWait').length, 2);
    assert.equal(results.length, 2);
    assert.ok(results.every((r) => r.status === 'stopped'));
    assert.ok(logger.errors.some((message) => message.includes('第 1 筆')));
  });

  test('AKS_STOP_ENABLED=true + 電源狀態非 Running: 只呼叫 get，不呼叫 beginStopAndWait', async () => {
    const logger = createLogger();
    const { factory, calls, factoryCalls } = createFakeClientFactory({ 'aks-1': 'Stopped' });

    const results = await runStopAks(
      {
        aksClustersRaw: JSON.stringify([{ subscriptionId: 'sub-1', resourceGroup: 'rg-1', name: 'aks-1' }]),
        stopEnabledRaw: 'true',
      },
      factory,
      logger,
    );

    assert.equal(factoryCalls.length, 1);
    assert.equal(calls.filter((c) => c.method === 'get').length, 1);
    assert.equal(calls.filter((c) => c.method === 'beginStopAndWait').length, 0);
    assert.equal(results.length, 1);
    assert.equal(results[0].status, 'skipped');
  });

  test('單一叢集發生例外時: 錯誤被隔離記錄，不拋出、不影響回傳陣列', async () => {
    const logger = createLogger();
    const factory: ClientFactory = () => {
      throw new Error('boom');
    };

    const results = await runStopAks(
      {
        aksClustersRaw: JSON.stringify([{ subscriptionId: 'sub-1', resourceGroup: 'rg-1', name: 'aks-1' }]),
        stopEnabledRaw: 'true',
      },
      factory,
      logger,
    );

    assert.equal(results.length, 1);
    assert.equal(results[0].status, 'failed');
    assert.ok(logger.errors.some((message) => message.includes('boom')));
  });
});
