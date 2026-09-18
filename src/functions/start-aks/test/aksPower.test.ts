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
  isStopScheduleEnabled,
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
      assert.deepEqual(result.errors, []);
    }
  });

  test('trims subscriptionId/resourceGroup/name 前後空白', () => {
    const result = parseAksClusters(
      JSON.stringify([{ subscriptionId: '  sub-1  ', resourceGroup: ' rg-1 ', name: ' aks-1 ' }]),
    );
    assert.equal(result.ok, true);
    if (result.ok) {
      assert.deepEqual(result.clusters[0], { subscriptionId: 'sub-1', resourceGroup: 'rg-1', name: 'aks-1' });
    }
  });

  test('未設定 (undefined) 時回傳明確錯誤 (全域失敗)', () => {
    const result = parseAksClusters(undefined);
    assert.equal(result.ok, false);
    if (!result.ok) {
      assert.match(result.error, /未設定/);
    }
  });

  test('空白字串時回傳明確錯誤 (全域失敗)', () => {
    const result = parseAksClusters('   ');
    assert.equal(result.ok, false);
  });

  test('無效 JSON 時回傳明確錯誤 (全域失敗)', () => {
    const result = parseAksClusters('{not valid json');
    assert.equal(result.ok, false);
    if (!result.ok) {
      assert.match(result.error, /JSON/);
    }
  });

  test('合法 JSON 但非陣列 (物件) 時回傳明確錯誤 (全域失敗) — 既有 bug 修正', () => {
    const result = parseAksClusters(
      JSON.stringify({ subscriptionId: 'sub-1', resourceGroup: 'rg-1', name: 'aks-1' }),
    );
    assert.equal(result.ok, false);
    if (!result.ok) {
      assert.match(result.error, /陣列/);
    }
  });

  test('合法 JSON 但非陣列 (字串) 時回傳明確錯誤 (全域失敗)', () => {
    const result = parseAksClusters(JSON.stringify('aks-1'));
    assert.equal(result.ok, false);
  });

  test('合法 JSON 但非陣列 (數字) 時回傳明確錯誤 (全域失敗)', () => {
    const result = parseAksClusters('123');
    assert.equal(result.ok, false);
  });

  test('空陣列時回傳明確錯誤且不視為合法目標 (全域失敗)', () => {
    const result = parseAksClusters('[]');
    assert.equal(result.ok, false);
    if (!result.ok) {
      assert.match(result.error, /空陣列/);
    }
  });

  test('單一項目缺少欄位時: ok=true，該項目記錄於 errors 且不產生 clusters — 既有 bug 修正', () => {
    const result = parseAksClusters(JSON.stringify([{ subscriptionId: 'sub-1', resourceGroup: 'rg-1' }]));
    assert.equal(result.ok, true);
    if (result.ok) {
      assert.deepEqual(result.clusters, []);
      assert.equal(result.errors.length, 1);
      assert.match(result.errors[0], /第 0 筆/);
    }
  });

  test('項目欄位為空字串時記錄於 errors，不影響 ok', () => {
    const result = parseAksClusters(
      JSON.stringify([{ subscriptionId: '', resourceGroup: 'rg-1', name: 'aks-1' }]),
    );
    assert.equal(result.ok, true);
    if (result.ok) {
      assert.deepEqual(result.clusters, []);
      assert.equal(result.errors.length, 1);
    }
  });

  test('項目欄位型別錯誤 (數字) 時記錄於 errors，不影響 ok', () => {
    const result = parseAksClusters(
      JSON.stringify([{ subscriptionId: 123, resourceGroup: 'rg-1', name: 'aks-1' }]),
    );
    assert.equal(result.ok, true);
    if (result.ok) {
      assert.equal(result.clusters.length, 0);
      assert.equal(result.errors.length, 1);
    }
  });

  test('陣列項目本身為非物件 (字串) 時記錄於 errors，不影響 ok', () => {
    const result = parseAksClusters(JSON.stringify(['aks-1']));
    assert.equal(result.ok, true);
    if (result.ok) {
      assert.equal(result.clusters.length, 0);
      assert.equal(result.errors.length, 1);
    }
  });

  test('混合合法與非法項目: 有效項目被保留，無效項目各自記錄於 errors (per-cluster isolation)', () => {
    const result = parseAksClusters(
      JSON.stringify([
        { subscriptionId: 'sub-1', resourceGroup: 'rg-1', name: 'aks-1' },
        { subscriptionId: 'sub-2' },
        { subscriptionId: 'sub-3', resourceGroup: 'rg-3', name: 'aks-3' },
      ]),
    );
    assert.equal(result.ok, true);
    if (result.ok) {
      assert.equal(result.clusters.length, 2);
      assert.deepEqual(result.clusters[0], { subscriptionId: 'sub-1', resourceGroup: 'rg-1', name: 'aks-1' });
      assert.deepEqual(result.clusters[1], { subscriptionId: 'sub-3', resourceGroup: 'rg-3', name: 'aks-3' });
      assert.equal(result.errors.length, 1);
      assert.match(result.errors[0], /第 1 筆/);
    }
  });

  test('全部項目皆無效時: ok=true，clusters 為空陣列，errors 包含所有原因', () => {
    const result = parseAksClusters(
      JSON.stringify([{ subscriptionId: 'sub-1' }, { resourceGroup: 'rg-1' }]),
    );
    assert.equal(result.ok, true);
    if (result.ok) {
      assert.deepEqual(result.clusters, []);
      assert.equal(result.errors.length, 2);
    }
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
    assert.equal(resolveSchedule('0 0 14 * * *', '0 0 22 * * *'), '0 0 14 * * *');
  });
  test('未設定 (undefined) 時使用預設值', () => {
    assert.equal(resolveSchedule(undefined, '0 0 22 * * *'), '0 0 22 * * *');
  });
  test('空白字串時使用預設值', () => {
    assert.equal(resolveSchedule('   ', '0 0 22 * * *'), '0 0 22 * * *');
  });
  test('前後有空白時會自動 trim', () => {
    assert.equal(resolveSchedule('  0 0 14 * * *  ', '0 0 22 * * *'), '0 0 14 * * *');
  });
});

describe('isStopScheduleEnabled — fail-closed 開關', () => {
  test('undefined -> false (fail closed)', () => {
    assert.equal(isStopScheduleEnabled(undefined), false);
  });
  test('空字串 -> false', () => {
    assert.equal(isStopScheduleEnabled(''), false);
  });
  test('空白字串 -> false', () => {
    assert.equal(isStopScheduleEnabled('   '), false);
  });
  test('"false" -> false', () => {
    assert.equal(isStopScheduleEnabled('false'), false);
  });
  test('任意拼字錯誤值 -> false', () => {
    assert.equal(isStopScheduleEnabled('tru'), false);
    assert.equal(isStopScheduleEnabled('yes'), false);
    assert.equal(isStopScheduleEnabled('1'), false);
  });
  test('"true" -> true', () => {
    assert.equal(isStopScheduleEnabled('true'), true);
  });
  test('大小寫不敏感: "TRUE"/"True" -> true', () => {
    assert.equal(isStopScheduleEnabled('TRUE'), true);
    assert.equal(isStopScheduleEnabled('True'), true);
  });
  test('前後空白會被 trim: "  true  " -> true', () => {
    assert.equal(isStopScheduleEnabled('  true  '), true);
  });
  test('非精確匹配 (含額外字元) -> false', () => {
    assert.equal(isStopScheduleEnabled('true '.repeat(2)), false);
    assert.equal(isStopScheduleEnabled('istrue'), false);
  });
});
