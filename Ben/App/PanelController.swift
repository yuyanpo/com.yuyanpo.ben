import AppKit
import SwiftUI

private final class BenPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController {
    private let model: TranslationViewModel
    private let panel: NSPanel
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init(model: TranslationViewModel, openSettings: @escaping () -> Void) {
        self.model = model
        panel = BenPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.title = "Ben"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = true
        // The SwiftUI header uses WindowDragGesture; text and controls stay separate.
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: TranslationPanelView(
            model: model, close: { [weak self] in self?.hide() }, openSettings: openSettings,
            resize: { [weak self] height in self?.resize(to: height) }
        ))
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = 14
        hosting.layer?.masksToBounds = true
        panel.contentView = hosting
    }

    func show(near point: NSPoint) {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        if let bounds = screen?.visibleFrame {
            let size = panel.frame.size
            let x = min(max(point.x + 12, bounds.minX + 12), max(bounds.minX + 12, bounds.maxX - size.width - 12))
            let y = min(max(point.y - size.height - 12, bounds.minY + 12), max(bounds.minY + 12, bounds.maxY - size.height - 12))
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.makeKeyAndOrderFront(nil)
        installDismissMonitors()
    }

    func hide() {
        model.cancel()
        panel.orderOut(nil)
        removeDismissMonitors()
    }

    private func resize(to height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        let nextHeight = ceil(height)
        guard abs(panel.frame.height - nextHeight) > 1 else { return }
        let top = panel.frame.maxY
        panel.setContentSize(NSSize(width: 400, height: nextHeight))
        var origin = NSPoint(x: panel.frame.minX, y: top - nextHeight)
        if let bounds = panel.screen?.visibleFrame {
            origin.x = min(max(origin.x, bounds.minX + 12), bounds.maxX - panel.frame.width - 12)
            origin.y = min(max(origin.y, bounds.minY + 12), bounds.maxY - nextHeight - 12)
        }
        panel.setFrameOrigin(origin)
    }

    private func installDismissMonitors() {
        removeDismissMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.hide()
                return nil
            }
            if event.type != .keyDown, event.window !== self.panel {
                self.hide()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            self.hide()
        }
    }

    private func removeDismissMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }
}
