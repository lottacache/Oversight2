import AppKit
import Foundation
import SwiftUI

struct Candle: Identifiable {
    let time: Double
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    var id: Double { time }

    init?(_ raw: [String: Any]) {
        guard let time = (raw["time"] as? NSNumber)?.doubleValue,
              let open = (raw["open"] as? NSNumber)?.doubleValue,
              let high = (raw["high"] as? NSNumber)?.doubleValue,
              let low = (raw["low"] as? NSNumber)?.doubleValue,
              let close = (raw["close"] as? NSNumber)?.doubleValue else { return nil }
        self.time = time
        self.open = open
        self.high = high
        self.low = low
        self.close = close
    }
}

struct ChartPane {
    var symbol = "TradingView"
    var timeframe = ""
    var bars: [Candle] = []
    var chartBars: [Candle] = []
    var visibleFrom: Double?
    var visibleTo: Double?
    var tickSize: Double?
    var timezone: String?
    var lastPrice: Double? { bars.last?.close }
}

@MainActor
final class IslandModel: ObservableObject {
    @Published private(set) var pane = ChartPane()
    @Published private(set) var status = "Connecting to TradingView…"
    @Published private(set) var connected = false
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var busy = false
    @Published private(set) var tradeBusy = false
    @Published private(set) var tradeError: String?

    private var bridge: BridgeClient?
    private var targetId: String?
    private var refreshTask: Task<Void, Never>?
    private var expanded = false

    var displaySymbol: String { pane.symbol.split(separator: ":").last.map(String.init) ?? pane.symbol }
    var compactPrice: String { pane.lastPrice.map { Self.price($0, tickSize: pane.tickSize) } ?? "—" }
    var isStale: Bool { guard let lastUpdate else { return true }; return Date().timeIntervalSince(lastUpdate) > 25 }
    var canQuickTrade: Bool {
        connected && !tradeBusy && lastUpdate.map { Date().timeIntervalSince($0) < 8 } == true
    }

    static func price(_ value: Double, tickSize: Double? = nil) -> String {
        let decimals: Int
        if let tickSize, tickSize > 0 {
            let tick = String(format: "%.8f", tickSize)
            decimals = min(8, tick.split(separator: ".").last.map { $0.reversed().drop(while: { $0 == "0" }).count } ?? 0)
        } else {
            decimals = value >= 100 ? 2 : 4
        }
        return value.formatted(.number.precision(.fractionLength(decimals)))
    }

    func connect() async {
        busy = true
        defer { busy = false }
        do {
            if bridge == nil { bridge = try BridgeClient() }
            guard let bridge else { return }
            let data = try await bridge.send(["action": "health"])
            pane.symbol = data["symbol"] as? String ?? pane.symbol
            pane.timeframe = data["timeframe"] as? String ?? pane.timeframe
            targetId = data["targetId"] as? String
            connected = true
            status = "Connected · following the active TradingView chart"
            await refresh(full: true)
        } catch {
            connected = false
            status = Self.statusMessage(error)
        }
    }

    func setExpanded(_ value: Bool) {
        expanded = value
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            if !self.connected { await self.connect() }
            else if value { await self.refresh(full: true) }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
                if self.connected { await self.refresh(full: false) }
                else { await self.connect() }
            }
        }
    }

    func refresh(full: Bool) async {
        guard let bridge, connected else { return }
        do {
            let data = try await bridge.send([
                "action": "snapshot", "count": 300, "latestOnly": !full
            ])
            let symbol = data["symbol"] as? String ?? pane.symbol
            let timeframe = data["timeframe"] as? String ?? pane.timeframe
            let newTarget = data["targetId"] as? String
            let changedChart = symbol != pane.symbol || timeframe != pane.timeframe || newTarget != targetId
            if changedChart && !full {
                pane.symbol = symbol
                pane.timeframe = timeframe
                targetId = newTarget
                await refresh(full: true)
                return
            }
            let range = data["visibleRange"] as? [String: Any]
            let visibleFrom = (range?["from"] as? NSNumber)?.doubleValue
            let visibleTo = (range?["to"] as? NSNumber)?.doubleValue
            let changedRange = visibleFrom != pane.visibleFrom || visibleTo != pane.visibleTo
            if changedRange && !full {
                await refresh(full: true)
                return
            }
            guard let rawBars = data["bars"] as? [[String: Any]] else {
                throw NSError(domain: "OversightIsland", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "TradingView returned no chart bars"])
            }
            let incoming = rawBars.compactMap(Candle.init)
            guard !incoming.isEmpty else {
                throw NSError(domain: "OversightIsland", code: 4,
                              userInfo: [NSLocalizedDescriptionKey: "TradingView chart data is still loading"])
            }
            pane.symbol = symbol
            pane.timeframe = timeframe
            targetId = newTarget
            pane.visibleFrom = visibleFrom
            pane.visibleTo = visibleTo
            pane.tickSize = (data["tickSize"] as? NSNumber)?.doubleValue
            pane.timezone = data["timezone"] as? String
            if full {
                pane.bars = incoming
                let viewport = (data["visibleBars"] as? [[String: Any]])?.compactMap(Candle.init) ?? []
                pane.chartBars = viewport.isEmpty ? incoming : viewport
            }
            else if let bar = incoming.last {
                if pane.bars.last?.time == bar.time { pane.bars[pane.bars.count - 1] = bar }
                else { pane.bars.append(bar); pane.bars = Array(pane.bars.suffix(300)) }
                if pane.chartBars.last?.time == bar.time {
                    pane.chartBars[pane.chartBars.count - 1] = bar
                } else if (pane.visibleTo ?? bar.time) >= bar.time,
                          bar.time > (pane.chartBars.last?.time ?? 0) {
                    pane.chartBars.append(bar)
                    pane.chartBars = Array(pane.chartBars.suffix(300))
                }
            }
            lastUpdate = Date()
            status = "Connected · following the active TradingView chart"
        } catch {
            connected = false
            status = Self.statusMessage(error)
        }
    }

    func openInTradingView() {
        NSWorkspace.shared.runningApplications.first { $0.localizedName == "TradingView" }?.activate()
    }

    @discardableResult
    func quickTrade(_ side: String) async -> Bool {
        guard !tradeBusy else { return false }
        guard connected, let targetId, let lastUpdate,
              Date().timeIntervalSince(lastUpdate) < 8 else {
            tradeError = "Chart data is stale. Refresh before trading."
            return false
        }
        tradeError = nil
        tradeBusy = true
        defer { tradeBusy = false }
        do {
            guard let bridge else { throw NSError(domain: "OversightIsland", code: 5,
                userInfo: [NSLocalizedDescriptionKey: "TradingView is not connected"]) }
            _ = try await bridge.send([
                "action": "quickTrade", "side": side,
                "expectedTargetId": targetId,
                "expectedSymbol": pane.symbol,
                "expectedTimeframe": pane.timeframe
            ])
            openInTradingView()
            return true
        } catch {
            tradeError = error.localizedDescription
            return false
        }
    }

    private static func statusMessage(_ error: Error) -> String {
        let message = error.localizedDescription
        if message.contains("CDP is unavailable") || message.contains("fetch failed") {
            return "TradingView not connected · relaunch with CDP port 9222"
        }
        return message
    }
}
