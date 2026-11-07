import AppKit
import Carbon
import Combine
import SwiftUI

@main
struct OversightIslandApp: App {
    @NSApplicationDelegateAdaptor(IslandAppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

private final class HoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class StatusHoverView: NSView {
    var onHover: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                 options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                 owner: self,
                                 userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            superview?.mouseDown(with: event)
            return
        }
        if let button = superview as? NSStatusBarButton {
            button.performClick(nil)
        } else {
            super.mouseDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        superview?.rightMouseDown(with: event)
    }
}

@MainActor
final class IslandAppDelegate: NSObject, NSApplicationDelegate {
    private let model = IslandModel()
    private var expandedPanel: HoverPanel!
    private var statusItem: NSStatusItem!
    private var priceTimer: Timer?
    private var closeWork: DispatchWorkItem?
    private var manuallyOpened = false
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var localKeyMonitor: Any?
    private var outsideClickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupPanels()
        setupStatusItem()
        setupShortcut()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.closeExpanded(); return nil }
            if let self, self.expandedPanel.isVisible, !event.isARepeat,
               event.modifierFlags.intersection([.shift, .command, .option, .control]) == [.shift],
               let key = event.charactersIgnoringModifiers?.lowercased(),
               key == "b" || key == "s" {
                Task {
                    if await self.model.quickTrade(key == "b" ? "buy" : "sell") {
                        self.closeExpanded()
                    }
                }
                return nil
            }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.closeExpanded()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(reposition),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        Task { await model.connect(); model.setExpanded(false) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        priceTimer?.invalidate()
    }

    private func makePanel() -> HoverPanel {
        let panel = HoverPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.hasShadow = false
        return panel
    }

    private func setupPanels() {
        expandedPanel = makePanel()
        expandedPanel.hasShadow = true
        expandedPanel.contentView = NSHostingView(rootView: IslandExpanded(model: model,
            hover: { [weak self] inside in self?.hoverChanged(inside, expanded: true) },
            close: { [weak self] in self?.closeExpanded() }))
        reposition()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = nil
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        button.toolTip = "Oversight · Option-Space"
        button.target = self
        button.action = #selector(togglePanel)
        let hoverView = StatusHoverView(frame: button.bounds)
        hoverView.autoresizingMask = [.width, .height]
        hoverView.onHover = { [weak self] inside in
            self?.hoverChanged(inside, expanded: false)
        }
        button.addSubview(hoverView)
        updateStatusItem()
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)
        priceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatusItem() }
        }
    }

    private func updateStatusItem() {
        let price = model.compactPrice
        if statusItem.button?.title != price { statusItem.button?.title = price }
        statusItem.button?.setAccessibilityLabel("Oversight price \(price)")
    }

    private func setupShortcut() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<IslandAppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { delegate.togglePanel() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        let identifier = EventHotKeyID(signature: 0x4F564953, id: 1) // OVIS
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), identifier,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func hoverChanged(_ inside: Bool, expanded: Bool) {
        if inside {
            closeWork?.cancel()
            if expanded { manuallyOpened = false }
            openExpanded()
        } else {
            if manuallyOpened { return }
            closeWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.closeExpanded() }
            closeWork = work
            let delay: TimeInterval = expanded ? 0.35 : 0.8
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func openExpanded() {
        closeWork?.cancel()
        guard !expandedPanel.isVisible else { return }
        reposition()
        expandedPanel.orderFrontRegardless()
        model.setExpanded(true)
    }

    private func closeExpanded() {
        closeWork?.cancel()
        manuallyOpened = false
        guard expandedPanel.isVisible else { return }
        expandedPanel.orderOut(nil)
        model.setExpanded(false)
    }

    @objc func togglePanel() {
        if expandedPanel.isVisible { closeExpanded() }
        else { manuallyOpened = true; openExpanded(); expandedPanel.makeKey() }
    }

    @objc private func reposition() {
        guard expandedPanel != nil,
              let screen = NSScreen.screens.first else { return }
        let width = min(800, screen.visibleFrame.width - 24)
        let height: CGFloat = 356
        expandedPanel.setFrame(NSRect(x: screen.visibleFrame.midX - width / 2,
                                      y: screen.visibleFrame.maxY - height - 8,
                                      width: width, height: height), display: true)
    }
}
