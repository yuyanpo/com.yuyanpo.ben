import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = TranslationViewModel()
    private let shortcut = GlobalShortcut()
    private let reader = SelectedTextReader()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var selectionTask: Task<Void, Never>?
    private var selectionID: UUID?
    private var shortcutMenuItems: [ShortcutAction: NSMenuItem] = [:]
    private var shortcutSubscription: AnyCancellable?
    private lazy var panel = PanelController(model: model, shortcuts: shortcut) { [weak self] in self?.showSettings() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--check-accessibility") {
            print(reader.refreshPermission() ? "Accessibility: authorized" : "Accessibility: not authorized")
            NSApp.terminate(nil)
            return
        }
        #if DEBUG
        if CommandLine.arguments.contains("--check-selection") {
            NSApp.setActivationPolicy(.accessory)
            selectionTask = Task { [weak self] in
                guard let self else { return }
                let diagnosticReader: SelectedTextReader
                if let flag = CommandLine.arguments.firstIndex(of: "--selection-app"),
                   CommandLine.arguments.indices.contains(flag + 1) {
                    let bundleID = CommandLine.arguments[flag + 1]
                    diagnosticReader = SelectedTextReader {
                        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
                    }
                } else {
                    diagnosticReader = self.reader
                }
                do {
                    let text = try await diagnosticReader.readSelection()
                    print("Selection: available (\(text.count) characters)")
                } catch {
                    print("Selection: unavailable (\(error.localizedDescription))")
                }
                NSApp.terminate(nil)
            }
            return
        }
        #endif
        NSApp.setActivationPolicy(.accessory)
        NotificationCenter.default.addObserver(
            self, selector: #selector(translateSelection), name: .benTranslateSelection, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(showManualTranslation), name: .benTranslateText, object: nil
        )
        shortcut.register()
        configureStatusItem()
        shortcutSubscription = shortcut.$shortcuts.sink { [weak self] values in
            self?.updateShortcutMenuItems(values)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        selectionTask?.cancel()
        model.cancel()
        shortcut.unregister()
        NotificationCenter.default.removeObserver(self)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = Self.menuBarMark()
            button.toolTip = "Ben · 选词翻译 \(shortcut.shortcut(for: .selection).display)"
        }
        let menu = NSMenu()
        shortcutMenuItems[.text] = menu.addItem(withTitle: "翻译文本", action: #selector(showManualTranslation), keyEquivalent: "")
        shortcutMenuItems[.selection] = menu.addItem(withTitle: "翻译选中文字", action: #selector(translateSelection), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "关于 Ben", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Ben", action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items { menuItem.target = self }
        item.menu = menu
        statusItem = item
        updateShortcutMenuItems(shortcut.shortcuts)
    }

    private func updateShortcutMenuItems(_ values: [ShortcutAction: KeyboardShortcut]) {
        for (action, item) in shortcutMenuItems {
            let value = values[action] ?? action.defaultShortcut
            // AppKit places the shortcut in its native, gray trailing column.
            item.keyEquivalent = value.menuKeyEquivalent
            item.keyEquivalentModifierMask = value.modifierFlags
        }
        statusItem?.button?.toolTip = "Ben · 选词翻译 \((values[.selection] ?? ShortcutAction.selection.defaultShortcut).display)"
    }

    /// A 16pt foreground inside an 18pt transparent template, rendered at 1x and 2x.
    private static func menuBarMark() -> NSImage {
        let image = NSImage(resource: .menuBarMark)
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "Ben 翻译"
        return image
    }

    @objc private func translateSelection() {
        guard shortcut.recordingAction == nil else { return }
        let point = NSEvent.mouseLocation
        selectionTask?.cancel()
        model.cancel()
        let id = UUID()
        selectionID = id
        // Read before presenting our panel, while the original application still owns focus.
        selectionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let selected = try await self.reader.readSelection()
                guard self.selectionID == id, !Task.isCancelled else { return }
                self.model.beginTranslation(text: selected)
            } catch {
                guard self.selectionID == id, !Task.isCancelled else { return }
                self.model.show(error: error)
            }
            self.selectionTask = nil
            self.panel.show(near: point)
        }
    }

    @objc private func showManualTranslation() {
        guard shortcut.recordingAction == nil else { return }
        cancelSelection()
        panel.show(near: NSEvent.mouseLocation, focusInput: true)
    }

    @objc private func showSettings() {
        cancelSelection()
        reader.refreshPermission()
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
                styleMask: [.titled, .closable], backing: .buffered, defer: false
            )
            window.title = "Ben 设置"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(
                model: model, reader: reader, shortcuts: shortcut
            ))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showAbout() {
        cancelSelection()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let description = NSAttributedString(
            string: "轻量的 macOS 翻译工具",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
        )
        NSApp.activate(ignoringOtherApps: true)
        // Use the current blue brand image without the system's App icon decoration.
        // AppKit reuses its native panel and reads version/copyright from the bundle.
        let logo = NSImage(resource: .brandMark)
        logo.isTemplate = false
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .credits: description,
            .applicationIcon: logo
        ]
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func cancelSelection() {
        selectionTask?.cancel()
        selectionTask = nil
        selectionID = nil
    }
}
