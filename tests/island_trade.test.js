import { test } from 'node:test';
import assert from 'node:assert/strict';
import { assertTradeTarget, dispatchTradeShortcut } from '../src/island/trade.js';

const chart = { targetId: 'tab-1', symbol: 'CME_MINI:NQ1!', timeframe: '5' };
const request = { side: 'buy', expectedTargetId: 'tab-1',
  expectedSymbol: 'CME_MINI:NQ1!', expectedTimeframe: '5' };

test('quick trade refuses a changed chart and invalid side', () => {
  assert.doesNotThrow(() => assertTradeTarget(request, chart));
  assert.throws(() => assertTradeTarget(request, { ...chart, symbol: 'NASDAQ:AAPL' }), /changed/);
  assert.throws(() => assertTradeTarget({ ...request, side: 'hold' }, chart), /Invalid trade side/);
});

test('quick trade dispatches the matching TradingView shortcut', async () => {
  const events = [];
  const client = { Input: { dispatchKeyEvent: async event => events.push(event) } };
  await dispatchTradeShortcut(client, 'buy');
  await dispatchTradeShortcut(client, 'sell');
  assert.deepEqual(events.map(event => [event.type, event.key, event.modifiers]), [
    ['keyDown', 'B', 8], ['keyUp', 'B', 8],
    ['keyDown', 'S', 8], ['keyUp', 'S', 8],
  ]);
});
