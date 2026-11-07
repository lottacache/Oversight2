import AppKit
import SwiftUI

private enum Palette {
    static let shell = Color(red: 0.055, green: 0.063, blue: 0.066)
    static let summary = Color(red: 0.81, green: 0.85, blue: 0.81)
    static let chart = Color(red: 0.865, green: 0.855, blue: 0.825)
    static let ink = Color(red: 0.13, green: 0.16, blue: 0.16)
    static let muted = Color(red: 0.37, green: 0.41, blue: 0.41)
    static let up = Color(red: 0.19, green: 0.32, blue: 0.29)
    static let down = Color(red: 0.66, green: 0.32, blue: 0.33)
    static let buy = Color(red: 0.20, green: 0.36, blue: 0.62)
}

private func timeframeLabel(_ value: String) -> String {
    switch value {
    case "60": return "1 hour"
    case "240": return "4 hours"
    case "D", "1D": return "1 day"
    case "W", "1W": return "1 week"
    case "": return "Chart"
    default: return "\(value) min"
    }
}

struct IslandExpanded: View {
    @ObservedObject var model: IslandModel
    var hover: (Bool) -> Void
    var close: () -> Void
    @State private var zoomScale = 1.0
    @State private var panBars = 0

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text("Oversight")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button { Task { await model.connect() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .help("Reconnect to TradingView")
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .help("Close")
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.72))

            if !model.connected || model.isStale {
                HStack(spacing: 6) {
                    Circle().fill(Palette.down).frame(width: 6, height: 6)
                    Text(model.status).lineLimit(1)
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.78))
                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            HStack(spacing: 12) {
                summaryCard
                    .frame(width: 220)
                chartCard
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .background(Palette.shell, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onHover(perform: hover)
        .accessibilityElement(children: .contain)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Market snapshot")
                .font(.system(size: 14, weight: .semibold))
            Text("\(model.displaySymbol) · \(timeframeLabel(model.pane.timeframe))")
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
                .padding(.top, 5)
            Spacer(minLength: 12)
            Text("Last price")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.muted)
            Text(model.compactPrice)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .padding(.top, 3)
            Text("Quick trade")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.muted)
                .padding(.top, 15)
            HStack(spacing: 7) {
                tradeButton("Sell", side: "sell", shortcut: "⇧S", color: Palette.down)
                tradeButton("Buy", side: "buy", shortcut: "⇧B", color: Palette.buy)
            }
            .padding(.top, 6)
            if let error = model.tradeError {
                Text(error).font(.system(size: 9)).foregroundStyle(Palette.down)
                    .lineLimit(2).padding(.top, 5)
            }
            Spacer(minLength: 9)
            Rectangle().fill(Palette.ink.opacity(0.14)).frame(height: 1)
            Button { model.openInTradingView() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.up.right.square")
                    Text("Open in TradingView")
                    Spacer()
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.top, 12)
            }
            .buttonStyle(.plain)
            .disabled(!model.connected)
        }
        .foregroundStyle(Palette.ink)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.summary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func tradeButton(_ title: String, side: String, shortcut: String, color: Color) -> some View {
        Button {
            Task { if await model.quickTrade(side) { close() } }
        } label: {
            HStack(spacing: 4) {
                Text(title.uppercased()).font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 1)
                Text(shortcut).font(.system(size: 9, weight: .medium)).opacity(0.75)
            }
            .padding(.horizontal, 9)
            .frame(height: 29)
            .foregroundStyle(.white)
            .background(color, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!model.canQuickTrade)
        .help("Uses TradingView's \(title) shortcut and order settings")
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Text("Price chart")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(timeframeLabel(model.pane.timeframe))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                Button { zoomScale = max(0.5, zoomScale / 1.4) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }.help("Zoom out")
                Button { zoomScale = min(8, zoomScale * 1.4) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }.help("Zoom in")
                Button {
                    Task {
                        await model.refresh(full: true)
                        zoomScale = 1
                        panBars = 0
                    }
                } label: {
                    Label("Reset view", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .medium))
                }.help("Match the current TradingView chart range")
            }
            .buttonStyle(.plain)
            ChartCanvas(bars: model.pane.chartBars, pane: model.pane,
                        zoomScale: $zoomScale, panBars: $panBars)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("\(timeframeLabel(model.pane.timeframe)) candlestick chart with \(model.pane.chartBars.count) bars")
            HStack {
                Spacer()
                Text(model.pane.bars.last.map {
                    Date(timeIntervalSince1970: $0.time).formatted(date: .abbreviated, time: .shortened)
                } ?? "Waiting for chart")
                .foregroundStyle(Palette.muted)
            }
            .font(.system(size: 9, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(Palette.ink)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.chart, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ChartCanvas: View {
    let bars: [Candle]
    let pane: ChartPane
    @Binding var zoomScale: Double
    @Binding var panBars: Int
    @State private var magnifyStartScale: Double?

    private func window() -> [Candle] {
        guard !bars.isEmpty else { return [] }
        var anchor = bars.count - 1
        var baseCount = min(72, bars.count)
        if let from = pane.visibleFrom, let to = pane.visibleTo, from < to {
            let indices = bars.indices.filter { bars[$0].time >= from && bars[$0].time <= to }
            if let last = indices.last {
                anchor = last
                baseCount = indices.count
            }
        }
        let count = min(bars.count, max(8, Int((Double(baseCount) / zoomScale).rounded())))
        let end = min(bars.count - 1, max(count - 1, anchor - panBars))
        return Array(bars[(end - count + 1)...end])
    }

    private func priceStep(_ span: Double) -> Double {
        let raw = max(span / 3, pane.tickSize ?? 0.0001)
        let magnitude = pow(10, floor(log10(raw)))
        let normalized = raw / magnitude
        let multiplier = [1.0, 2.0, 2.5, 5.0, 10.0].first { $0 >= normalized } ?? 10
        let nice = multiplier * magnitude
        guard let tick = pane.tickSize, tick > 0 else { return nice }
        return max(tick, ceil(nice / tick) * tick)
    }

    private func dateLabel(_ time: Double, span: Double) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = pane.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        let daily = ["D", "1D", "W", "1W", "M", "1M"].contains(pane.timeframe)
        formatter.dateFormat = !daily && span < 86_400 ? "HH:mm" :
            span < 90 * 86_400 ? "MMM d" : "MMM yy"
        return formatter.string(from: Date(timeIntervalSince1970: time))
    }

    var body: some View {
        GeometryReader { geometry in
          Canvas { context, size in
            let visible = window()
            guard !visible.isEmpty else {
                context.draw(Text("Chart loading…").font(.system(size: 11, weight: .medium)).foregroundColor(Palette.muted),
                             at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }
            let dataLow = visible.map(\.low).min() ?? 0
            let dataHigh = visible.map(\.high).max() ?? 1
            let padding = max((dataHigh - dataLow) * 0.08, (pane.tickSize ?? 0.01) * 2)
            let lowest = dataLow - padding
            let highest = dataHigh + padding
            let span = max(highest - lowest, 0.0001)
            let plot = CGRect(x: 3, y: 5, width: max(1, size.width - 66), height: max(1, size.height - 28))
            func y(_ price: Double) -> CGFloat {
                plot.maxY - CGFloat((price - lowest) / span) * plot.height
            }
            let gridColor = Palette.ink.opacity(0.12)
            let axisFont = Font.system(size: 9.5, weight: .medium).monospacedDigit()
            let tickStep = priceStep(span)
            var tick = ceil(lowest / tickStep) * tickStep
            for _ in 0..<8 {
                if tick > highest { break }
                let py = y(tick)
                var path = Path()
                path.move(to: CGPoint(x: plot.minX, y: py))
                path.addLine(to: CGPoint(x: plot.maxX, y: py))
                context.stroke(path, with: .color(gridColor), lineWidth: 0.7)
                context.draw(Text(IslandModel.price(tick, tickSize: pane.tickSize))
                    .font(axisFont).foregroundColor(Palette.muted),
                    at: CGPoint(x: plot.maxX + 7, y: py), anchor: .leading)
                tick += tickStep
            }
            let timeSpan = visible.last!.time - visible.first!.time
            for index in Set([0, visible.count / 2, visible.count - 1]).sorted() {
                let x = plot.minX + plot.width * (CGFloat(index) + 0.5) / CGFloat(visible.count)
                var path = Path()
                path.move(to: CGPoint(x: x, y: plot.minY))
                path.addLine(to: CGPoint(x: x, y: plot.maxY))
                context.stroke(path, with: .color(gridColor.opacity(0.55)), lineWidth: 0.7)
                let anchor: UnitPoint = index == 0 ? .leading : index == visible.count - 1 ? .trailing : .center
                context.draw(Text(dateLabel(visible[index].time, span: timeSpan))
                    .font(axisFont).foregroundColor(Palette.muted),
                    at: CGPoint(x: x, y: plot.maxY + 12), anchor: anchor)
            }
            let step = plot.width / CGFloat(visible.count)
            for (index, bar) in visible.enumerated() {
                let x = plot.minX + step * (CGFloat(index) + 0.5)
                let color = bar.close >= bar.open ? Palette.up : Palette.down
                var wick = Path()
                wick.move(to: CGPoint(x: x, y: y(bar.high)))
                wick.addLine(to: CGPoint(x: x, y: y(bar.low)))
                context.stroke(wick, with: .color(color), lineWidth: 1)
                let top = min(y(bar.open), y(bar.close))
                let body = CGRect(x: x - max(1, step * 0.33), y: top,
                                  width: max(2, step * 0.66), height: max(1.5, abs(y(bar.open) - y(bar.close))))
                context.fill(Path(body), with: .color(color))
            }
          }
          .background(ChartScrollCatcher(onScroll: { delta in
              let factor = pow(1.006, delta)
              zoomScale = min(8.0, max(0.5, zoomScale * factor))
          }))
          .contentShape(Rectangle())
          .simultaneousGesture(
              MagnificationGesture()
                  .onChanged { value in
                      if magnifyStartScale == nil {
                          magnifyStartScale = zoomScale
                      }
                      if let start = magnifyStartScale {
                          zoomScale = min(8.0, max(0.5, start * value))
                      }
                  }
                  .onEnded { _ in
                      magnifyStartScale = nil
                  }
          )
          .gesture(DragGesture(minimumDistance: 8).onEnded { value in
              let step = max(2, (geometry.size.width - 66) / CGFloat(max(1, window().count)))
              panBars += Int((value.translation.width / step).rounded())
          })
        }
    }
}

private struct ChartScrollCatcher: NSViewRepresentable {
    var onScroll: (Double) -> Void

    func makeNSView(context: Context) -> ChartScrollNSView {
        let view = ChartScrollNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ChartScrollNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

private final class ChartScrollNSView: NSView {
    var onScroll: ((Double) -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    guard let self = self, let window = self.window, event.window == window else {
                        return event
                    }
                    let pointInView = self.convert(event.locationInWindow, from: nil)
                    if self.bounds.contains(pointInView) {
                        let delta: Double
                        if event.hasPreciseScrollingDeltas {
                            delta = Double(event.scrollingDeltaY)
                        } else {
                            delta = Double(event.deltaY) * 20.0
                        }
                        if abs(delta) > 0.01 {
                            self.onScroll?(delta)
                            return nil
                        }
                    }
                    return event
                }
            }
        } else {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }

    deinit {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
