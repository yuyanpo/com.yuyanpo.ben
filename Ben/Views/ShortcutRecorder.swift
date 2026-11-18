import AppKit
import Carbon
import SwiftUI

/// A focused, local recorder; no keyboard monitoring while settings are idle.
struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var shortcuts: GlobalShortcut
    let action: ShortcutAction

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.isBordered = false
        button.focusRingType = .none
        button.setButtonType(.momentaryPushIn)
        button.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        button.setAccessibilityLabel("录入\(action.title)快捷键")
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        let isRecording = shortcuts.recordingAction == action
        button.title = isRecording ? "按下组合键" : shortcuts.shortcut(for: action).display
        button.showsRecording = isRecording
        button.toolTip = "点击后按新的组合键，Esc 取消"
        button.start = { shortcuts.beginRecording(action) }
        button.cancel = { shortcuts.endRecording() }
        button.record = { value in shortcuts.update(value, for: action) }
        if !isRecording { button.stopMonitoring() }
    }

    static func dismantleNSView(_ button: RecorderButton, coordinator: ()) {
        if button.isRecording { button.cancel?() }
        button.stopMonitoring()
    }
}

@MainActor
final class RecorderButton: NSButton {
    var start: (() -> Void)?
    var cancel: (() -> Void)?
    var record: ((KeyboardShortcut) -> Bool)?
    private var monitor: Any?
    var showsRecording = false {
        didSet { needsDisplay = true }
    }
    var isRecording: Bool { monitor != nil }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 24) }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        (showsRecording ? NSColor.controlAccentColor.withAlphaComponent(0.06) : NSColor.controlBackgroundColor).setFill()
        shape.fill()
        (showsRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        shape.lineWidth = showsRecording ? 1.5 : 0.75
        shape.stroke()
        let titleFont = showsRecording ? NSFont.systemFont(ofSize: 12) : NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        let text = NSAttributedString(string: title, attributes: [
            .font: titleFont,
            .foregroundColor: showsRecording ? NSColor.controlAccentColor : NSColor.labelColor
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
        // Preserve a subtle focus cue for keyboard navigation without the oversized system ring.
        if !showsRecording, window?.firstResponder === self {
            NSColor.controlAccentColor.withAlphaComponent(0.6).setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func mouseDown(with event: NSEvent) { begin() }
    override func performClick(_ sender: Any?) { begin() }

    override func keyDown(with event: NSEvent) {
        if !isRecording, event.keyCode == UInt16(kVK_Space) || event.keyCode == UInt16(kVK_Return) {
            begin()
        } else {
            super.keyDown(with: event)
        }
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        if isRecording {
            stopMonitoring(clearFocus: false)
            cancel?()
        }
        return super.resignFirstResponder()
    }

    private func begin() {
        if isRecording { return }
        guard window?.makeFirstResponder(self) == true else { return }
        start?()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if event.isARepeat { return nil }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == UInt16(kVK_Escape) || (event.keyCode == UInt16(kVK_Tab) && modifiers.isEmpty) {
                self.stopMonitoring()
                self.cancel?()
                return event.keyCode == UInt16(kVK_Tab) ? event : nil
            }
            if self.record?(KeyboardShortcut(event: event)) == true { self.stopMonitoring() }
            return nil
        }
    }

    func stopMonitoring(clearFocus: Bool = true) {
        let wasRecording = isRecording || showsRecording
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        showsRecording = false
        if clearFocus, wasRecording, window?.firstResponder === self { window?.makeFirstResponder(nil) }
    }
}
