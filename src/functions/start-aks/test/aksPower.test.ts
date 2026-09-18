// ============================================================================
// aksPower 單元測試 — Node.js 內建測試執行器 (node:test)
//
// 放在 test/ (非 src/functions/) 底下，因 package.json 的 "main" 欄位
// 為 "dist/src/functions/*.js"，若測試放在 src/functions 下編譯後
// 會被 Azure Functions Host 當成函式索引/部署。
// ============================================================================

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  parseAksClusters,
  decideStartAction,
  decideStopAction,
  resolveSchedule,
} from '../src/aksPower.js';

describe('parseAksClusters', () => {
  test('解析合法的非空 JSON 陣列', () => {
    const result = parseAksClusters(
      JSON.stringify([
        { subscriptionId: 'sub-1', resourceGroup: 'rg-1', name: 'aks-1' },
        { subscriptionId: 'sub-2', resourceGroup: 'rg-2', name: 'aks-2' },
      ]),
    );
    assert.equal(result.ok, true);
    if (result.ok) {
      assert.equal(result.clusters.length, 2);
      assert.deepEqual(result.clusters[0], { subscriptionId: 'sub-1', resourceGroup: 'rg-1', name: 'aks-1' });
    }
  });

  test('未設定 (undefined) 時回傳明確錯誤', () => {
    const result = parseAksClusters(undefined);
    assert.equal(result.ok, false);
    if (!result.ok) {
      assert.match(result.error, /未設定/);
    }
  });

  test('空白字串時回傳明確錯誤', () => {
    const result = parseAksClusters('   ');
    assert.equal(result.ok, false);
  });

  test('無效 JSON 時回傳明確錯誤', () => {
    const result = parseAksClusters('{not valid json');
    assert.equal(result.ok, false);
    if (!result.ok) {
      assert.match(result.error, /JSON/);
    }
  });

  test('合法 JSON 但非陣列 (物件) 時回傳明確錯誤 — 既有 bug 修正', () => {
    const result = parseAksClusters(
      JSON.stringify({ subscriptionId: 'sub-1', resourceGroup: 'rg-1', name: 'aks-1' }),
    );
    assert.equal(result.ok, false);
    if (!result.ok) {
      assert.match(result.error, /陣列/);
    }
  });

  test('合法 JSON 但非陣列 (字串) 時回傳明確錯誤', () => {
    const result = parseAksClusters(JSON.stringify('aks-1'));
    assert.equal(result.ok, false);
  });

  test('合法 JSON 但非陣列 (數字) 時回傳明確錯誤', () => {
    const result = parseAksClusters('123');
    assert.equal(result.ok, false);
  });

  test('空陣列時回傳明確錯誤且不視為合法目標', () => {
    const result = parseAksClusters('[]');
    assert.equal(result.ok, false);
    if (!result.ok) {
      assert.match(result.error, /空陣列/);
    }
  });

  test('項目缺少欄位時回傳明確錯誤', () => {
    const result = parseAksClusters(JSON.stringify([{ subscriptionId: 'sub-1', resourceGroup: 'rg-1' }]));
    assert.equal(result.ok, false);
    if (!result.ok) {
      assert.match(result.error, /第 0 筆/);
    }
  });

  test('項目欄位為空字串時回傳明確錯誤', () => {
    const result = parseAksClusters(
      JSON.stringify([{ subscriptionId: '', resourceGroup: 'rg-1', name: 'aks-1' }]),
    );
    assert.equal(result.ok, false);
  });

  test('項目欄位型別錯誤 (數字) 時回傳明確錯誤', () => {
    const result = parseAksClusters(
      JSON.stringify([{ subscriptionId: 123, resourceGroup: 'rg-1', name: 'aks-1' }]),
    );
    assert.equal(result.ok, false);
  });

  test('陣列項目本身為非物件 (字串) 時回傳明確錯誤', () => {
    const result = parseAksClusters(JSON.stringify(['aks-1']));
    assert.equal(result.ok, false);
  });
});

describe('decideStartAction', () => {
  test('Stopped -> start', () => {
    assert.equal(decideStartAction('Stopped').action, 'start');
  });
  test('Running -> skip', () => {
    assert.equal(decideStartAction('Running').action, 'skip');
  });
  test('Starting -> skip', () => {
    assert.equal(decideStartAction('Starting').action, 'skip');
  });
  test('Stopping -> skip', () => {
    assert.equal(decideStartAction('Stopping').action, 'skip');
  });
  test('undefined -> skip', () => {
    const decision = decideStartAction(undefined);
    assert.equal(decision.action, 'skip');
    assert.match(decision.reason, /undefined/);
  });
  test('未知狀態 -> skip', () => {
    const decision = decideStartAction('SomethingElse');
    assert.equal(decision.action, 'skip');
    assert.match(decision.reason, /SomethingElse/);
  });
});

describe('decideStopAction', () => {
  test('Running -> stop', () => {
    assert.equal(decideStopAction('Running').action, 'stop');
  });
  test('Stopped -> skip', () => {
    assert.equal(decideStopAction('Stopped').action, 'skip');
  });
  test('Starting -> skip', () => {
    assert.equal(decideStopAction('Starting').action, 'skip');
  });
  test('Stopping -> skip', () => {
    assert.equal(decideStopAction('Stopping').action, 'skip');
  });
  test('undefined -> skip', () => {
    const decision = decideStopAction(undefined);
    assert.equal(decision.action, 'skip');
    assert.match(decision.reason, /undefined/);
  });
  test('未知狀態 -> skip', () => {
    const decision = decideStopAction('SomethingElse');
    assert.equal(decision.action, 'skip');
    assert.match(decision.reason, /SomethingElse/);
  });
});

describe('resolveSchedule', () => {
  test('有設定值時使用該值', () => {
    assert.equal(resolveSchedule('0 0 20 * * *', '0 0 6 * * *'), '0 0 20 * * *');
  });
  test('未設定 (undefined) 時使用預設值', () => {
    assert.equal(resolveSchedule(undefined, '0 0 6 * * *'), '0 0 6 * * *');
  });
  test('空白字串時使用預設值', () => {
    assert.equal(resolveSchedule('   ', '0 0 6 * * *'), '0 0 6 * * *');
  });
  test('前後有空白時會自動 trim', () => {
    assert.equal(resolveSchedule('  0 0 20 * * *  ', '0 0 6 * * *'), '0 0 20 * * *');
  });
});
