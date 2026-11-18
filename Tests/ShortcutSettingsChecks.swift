import AppKit
import Carbon
import SwiftUI

@main
struct ShortcutSettingsChecks {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let suite = "com.yuyanpo.ben.settings-render.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let shortcuts = GlobalShortcut(defaults: defaults)
        defer { shortcuts.unregister() }
        let model = TranslationViewModel(defaults: defaults)
        let reader = SelectedTextReader()
        let view = NSHostingView(rootView: SettingsView(model: model, reader: reader, shortcuts: shortcuts))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 560, height: 720)

        func controls(_ parent: NSView) -> [RecorderButton] {
            parent.subviews.flatMap { child in
                (child as? RecorderButton).map { [$0] } ?? controls(child)
            }
        }
        var positions: [NSRect]?
        func render(_ state: String, appearance: NSAppearance.Name = .aqua) throws {
            view.appearance = NSAppearance(named: appearance)
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            view.layoutSubtreeIfNeeded()
            let buttons = controls(view)
            precondition(buttons.count == 2)
            let frames = buttons.map { $0.convert($0.bounds, to: view) }
            if let positions { precondition(positions == frames, "Recorder positions shifted in \(state): \(frames)") }
            else { positions = frames }
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: outputDirectory.appendingPathComponent("settings-\(state).png"))
            print("\(state): recorder frames \(frames)")
        }
        try render("idle")
        controls(view)[0].performClick(nil)
        precondition(shortcuts.recordingAction == .text)
        precondition(controls(view)[0].isRecording)
        precondition(window.firstResponder === controls(view)[0])
        try render("recording")
        precondition(!shortcuts.update(shortcuts.shortcut(for: .selection), for: .text))
        try render("conflict")
        shortcuts.endRecording()
        try render("finished")
        precondition(!controls(view)[0].isRecording)
        precondition(window.firstResponder !== controls(view)[0])
        controls(view)[0].performClick(nil)
        precondition(shortcuts.recordingAction == .text)
        window.makeFirstResponder(nil)
        precondition(shortcuts.recordingAction == nil, "Losing focus must cancel recording")
        precondition(!controls(view)[0].isRecording)
        try render("focus-ended")
        controls(view)[0].performClick(nil)
        let replacement = KeyboardShortcut(keyCode: UInt32(kVK_F20), modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey))
        precondition(shortcuts.update(replacement, for: .text))
        try render("saved")
        precondition(!controls(view)[0].isRecording)
        precondition(window.firstResponder !== controls(view)[0])
        try render("dark", appearance: .darkAqua)
        print("Layout stability and focus cleanup passed across idle, recording, conflict, cancellation, save and dark states")
    }
}
