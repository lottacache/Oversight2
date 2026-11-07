export function assertTradeTarget(request, chart) {
  if (!['buy', 'sell'].includes(request.side)) throw new Error('Invalid trade side');
  if (!request.expectedTargetId || !request.expectedSymbol || !request.expectedTimeframe) {
    throw new Error('Refresh the island chart before trading');
  }
  if (request.expectedTargetId !== chart.targetId ||
      request.expectedSymbol !== chart.symbol ||
      request.expectedTimeframe !== chart.timeframe) {
    throw new Error('TradingView chart changed. Refresh the island before trading');
  }
}

// Dispatches TradingView's own Shift+B / Shift+S shortcut. TradingView decides
// whether this opens a ticket or immediately sends an order based on its settings.
export async function dispatchTradeShortcut(client, side) {
  if (!['buy', 'sell'].includes(side)) throw new Error('Invalid trade side');
  const letter = side === 'buy' ? 'B' : 'S';
  const key = { key: letter, code: `Key${letter}`, windowsVirtualKeyCode: letter.charCodeAt(0), modifiers: 8 };
  await client.Input.dispatchKeyEvent({ type: 'keyDown', ...key });
  await client.Input.dispatchKeyEvent({ type: 'keyUp', ...key });
}
