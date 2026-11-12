import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = TranslationViewModel()
    private let shortcut = GlobalShortcut()
    private let reader = SelectedTextReader()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private lazy var panel = PanelController(model: model) { [weak self] in self?.showSettings() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--check-accessibility") {
            print(reader.refreshPermission() ? "Accessibility: authorized" : "Accessibility: not authorized")
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        model.shortcutError = shortcut.register()
        NotificationCenter.default.addObserver(
            self, selector: #selector(translateSelection), name: .benTranslateSelection, object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        shortcut.unregister()
        NotificationCenter.default.removeObserver(self)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = Self.menuBarMark()
            button.image?.isTemplate = true
            button.toolTip = "Ben · 选词翻译 ⌥C"
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "翻译文本…", action: #selector(showManualTranslation), keyEquivalent: "")
        menu.addItem(withTitle: "翻译选中文字  ⌥C", action: #selector(translateSelection), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "关于 Ben…", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Ben", action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items { menuItem.target = self }
        item.menu = menu
        statusItem = item
    }

    /// The original logo's foreground, rendered at 1x and 2x without its white tile.
    private static func menuBarMark() -> NSImage {
        let image = NSImage(named: "MenuBarMark") ?? NSImage(size: NSSize(width: 18, height: 18))
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "Ben 翻译"
        return image
    }

    @objc private func translateSelection() {
        let point = NSEvent.mouseLocation
        // Read before presenting our panel, while the original application still owns focus.
        do {
            let selected = try reader.readSelection()
            model.beginTranslation(text: selected)
        } catch {
            model.show(error: error)
        }
        panel.show(near: point)
    }

    @objc private func showManualTranslation() {
        panel.show(near: NSEvent.mouseLocation)
    }

    @objc private func showSettings() {
        reader.refreshPermission()
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 510, height: 590),
                styleMask: [.titled, .closable], backing: .buffered, defer: false
            )
            window.title = "Ben 设置"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(
                model: model, reader: reader,
                retryShortcut: { [weak self] in
                    guard let self else { return }
                    self.model.shortcutError = self.shortcut.register()
                }
            ))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func showAbout() {
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
        // Use the original brand image to avoid the system's App icon decoration.
        // AppKit reuses its native panel and reads version/copyright from the bundle.
        var options: [NSApplication.AboutPanelOptionKey: Any] = [.credits: description]
        if let logo = NSImage(named: "BrandMark") {
            options[.applicationIcon] = logo
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
