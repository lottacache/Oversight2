# Oversight Island prototype

A local macOS menu bar panel that follows the **active TradingView Desktop chart**. The menu bar item shows its price; the expanded panel shows the symbol, timeframe, price, and recent candles. No matching TradingView layout or extra chart window is required. Change the symbol or timeframe in TradingView and the island follows it.

## Build and run

Requires macOS 13+, Xcode command line tools, Node.js, and TradingView Desktop. From the repository root:

```sh
./mac-app/build-app.sh
open "mac-app/dist/Oversight Island.app"
```

Start TradingView Desktop with CDP enabled **before** opening the island. Quit TradingView normally, then launch it from Terminal:

```sh
/Applications/TradingView.app/Contents/MacOS/TradingView --remote-debugging-port=9222
```

Hover over the price in the right side of the menu bar to expand it. You can also click the price or press Option-Space. Move the pointer away to close the hover panel, or press Escape. A manually opened panel remains until dismissed or used.

The panel reads up to 300 recent bars and up to 300 bars around TradingView's visible chart range on opening or when the chart changes. It reads the latest bar every 1 second (both while expanded and while closed in the menu bar). The mini chart has price and time axes, zoom controls, drag panning, and a **Reset view** button that reloads the current TradingView chart range. Connection errors appear in the expanded panel, and the app retries automatically. It does not save market data to disk.

The **Sell** and **Buy** buttons send TradingView's Shift-S and Shift-B shortcuts to the matching chart. Those keys also work while the island panel has keyboard focus. They use TradingView's connected broker, order preset, and confirmation settings. If one-click trading is enabled, a button or shortcut can send an order immediately. The island refuses to send a shortcut when its chart is stale or TradingView has switched symbols, timeframes, or tabs. The app does not determine the order quantity or execution price.
