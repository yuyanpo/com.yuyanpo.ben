import AppKit
import Combine
@preconcurrency import ApplicationServices

@MainActor
final class SelectedTextReader: ObservableObject {
    @Published private(set) var hasPermission = AXIsProcessTrusted()

    @discardableResult
    func refreshPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        if hasPermission != trusted { hasPermission = trusted }
        return trusted
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        refreshPermission()
    }

    func readSelection() throws -> String {
        guard refreshPermission() else { throw BenError.permissionRequired }
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier != Bundle.main.bundleIdentifier else {
            throw BenError.selectionUnavailable
        }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        // Bound unresponsive-app IPC so the shortcut cannot freeze Ben indefinitely.
        AXUIElementSetMessagingTimeout(appElement, 0.4)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            throw BenError.selectionUnavailable
        }
        let focusedElement = unsafeDowncast(focusedValue, to: AXUIElement.self)
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(focusedElement, kAXSubroleAttribute as CFString, &subrole)
        if subrole as? String == kAXSecureTextFieldSubrole as String {
            throw BenError.secureInput
        }
        var selectedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, &selectedValue) == .success,
              let text = selectedValue as? String else {
            throw BenError.selectionUnavailable
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BenError.selectionUnavailable }
        guard trimmed.count <= 5_000 else { throw BenError.textTooLong }
        return trimmed
    }
}
