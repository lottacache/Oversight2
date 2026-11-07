#!/usr/bin/env node
// Local JSON-lines bridge for the active TradingView Desktop chart.
// Responses contain only locally read chart data; nothing is saved to disk.
import readline from 'node:readline';
import CDP from 'chrome-remote-interface';
import * as connection from '../connection.js';
import { assertTradeTarget, dispatchTradeShortcut } from './trade.js';

let queue = Promise.resolve();

async function chartTargets() {
  let response;
  try {
    response = await fetch(`http://${connection.CDP_HOST}:${connection.CDP_PORT}/json/list`);
  } catch {
    throw new Error(`TradingView CDP is unavailable on ${connection.CDP_HOST}:${connection.CDP_PORT}. Relaunch TradingView with --remote-debugging-port=${connection.CDP_PORT}`);
  }
  if (!response.ok) throw new Error(`TradingView CDP returned HTTP ${response.status}`);
  return (await response.json()).filter(target =>
    target.type === 'page' && /tradingview\.com\/chart/i.test(target.url));
}

async function activeTarget() {
  const targets = await chartTargets();
  if (targets.length === 0) throw new Error('Open a chart in TradingView Desktop');
  for (const target of targets) {
    let client;
    try {
      client = await CDP({ host: connection.CDP_HOST, port: connection.CDP_PORT, target: target.id });
      const result = await client.Runtime.evaluate({ expression: 'document.visibilityState', returnByValue: true });
      if (result.result?.value === 'visible') return target;
    } catch { /* a tab may be loading or closing */ }
    finally { await client?.close().catch(() => {}); }
  }
  // TradingView may be minimized. Keep reading the last bound chart if it is still open.
  const previous = await connection.getTargetInfo().catch(() => null);
  return targets.find(target => target.id === previous?.id) || targets[0];
}

async function bindActiveChart() {
  const target = await activeTarget();
  const current = await connection.getTargetInfo().catch(() => null);
  if (current?.id !== target.id) await connection.reconnectTo(target.id);
  return target;
}

async function health() {
  const target = await bindActiveChart();
  const chart = await connection.evaluate(`(function() {
    var c = window.TradingViewApi._activeChartWidgetWV.value();
    return { symbol: c.symbol(), timeframe: c.resolution() };
  })()`);
  return { connected: true, targetId: target.id, ...chart };
}

async function snapshot(input = {}) {
  const target = await bindActiveChart();
  const count = input.latestOnly ? 1 : Math.max(1, Math.min(300, Number(input.count) || 300));
  const chart = await connection.evaluate(`(function() {
    var c = window.TradingViewApi._activeChartWidgetWV.value();
    var series = c._chartWidget.model().mainSeries();
    var source = series.bars();
    var info = series.symbolInfo?.() || c.symbolExt?.() || {};
    var visibleRange = null;
    try { visibleRange = c.getVisibleRange(); } catch (e) {}
    var tickSize = Number(info.minmov) / Number(info.pricescale);
    if (!Number.isFinite(tickSize) || tickSize <= 0) tickSize = null;
    var end = source.lastIndex();
    var start = Math.max(source.firstIndex(), end - ${count} + 1);
    var bars = [];
    for (var i = start; i <= end; i++) {
      var v = source.valueAt(i);
      if (v) bars.push({ time: v[0], open: v[1], high: v[2], low: v[3], close: v[4], volume: v[5] || 0 });
    }
    var visibleBars = null;
    if (!${Boolean(input.latestOnly)}) {
      var visibleEnd = end;
      if (visibleRange && Number.isFinite(visibleRange.to)) {
        visibleEnd = source.firstIndex();
        for (var j = end; j >= source.firstIndex(); j--) {
          var candidate = source.valueAt(j);
          if (candidate && candidate[0] <= visibleRange.to) { visibleEnd = j; break; }
        }
      }
      visibleBars = [];
      for (var k = Math.max(source.firstIndex(), visibleEnd - 299); k <= visibleEnd; k++) {
        var vv = source.valueAt(k);
        if (vv) visibleBars.push({ time: vv[0], open: vv[1], high: vv[2], low: vv[3], close: vv[4] });
      }
    }
    return { symbol: c.symbol(), timeframe: c.resolution(), bars: bars,
      visibleBars: visibleBars, visibleRange: visibleRange,
      tickSize: tickSize, timezone: c.getTimezone?.() || info.timezone || null };
  })()`);
  if (!chart || !Array.isArray(chart.bars) || chart.bars.length === 0) {
    throw new Error('The active TradingView chart has no price bars yet');
  }
  return { targetId: target.id, capturedAt: Date.now(), ...chart };
}

async function quickTrade(request) {
  const target = await bindActiveChart();
  const chart = await connection.evaluate(`(function() {
    var c = window.TradingViewApi._activeChartWidgetWV.value();
    var focused = document.activeElement;
    var editing = focused && (focused.matches?.('input, textarea, [contenteditable="true"]') ||
      focused.closest?.('[contenteditable="true"]'));
    return { symbol: c.symbol(), timeframe: c.resolution(), editing: !!editing };
  })()`);
  assertTradeTarget(request, { targetId: target.id, ...chart });
  if (chart.editing) throw new Error('Finish editing in TradingView before using Quick Trade');
  const client = await connection.getClient();
  await dispatchTradeShortcut(client, request.side);
  return { shortcutDispatched: true, side: request.side, targetId: target.id };
}

async function handle(request) {
  switch (request.action) {
    case 'health': return health();
    case 'snapshot': return snapshot(request);
    case 'quickTrade': return quickTrade(request);
    default: throw new Error(`Unknown action: ${request.action}`);
  }
}

const lines = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
lines.on('line', line => {
  queue = queue.then(async () => {
    let request;
    try {
      request = JSON.parse(line);
      const data = await handle(request);
      process.stdout.write(JSON.stringify({ id: request.id, ok: true, data }) + '\n');
    } catch (error) {
      process.stdout.write(JSON.stringify({ id: request?.id ?? null, ok: false, error: error.message }) + '\n');
    }
  });
});
lines.on('close', () => { queue.finally(() => connection.disconnect()); });
