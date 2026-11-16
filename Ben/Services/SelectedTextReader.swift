import AppKit
import Combine
@preconcurrency import ApplicationServices

@MainActor
final class SelectedTextReader: ObservableObject {
    @Published private(set) var hasPermission = AXIsProcessTrusted()
    private let applicationProvider: () -> NSRunningApplication?

    init(applicationProvider: @escaping () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication }) {
        self.applicationProvider = applicationProvider
    }

    // Monaco editors can copy a whole line without selection. Their copy
    // fallback must include explicit non-empty-selection metadata.
    static let editorBundleIDs: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92"
    ]

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

    func readSelection() async throws -> String {
        guard refreshPermission() else { throw BenError.permissionRequired }
        guard let application = applicationProvider(),
              application.bundleIdentifier != Bundle.main.bundleIdentifier else {
            throw BenError.selectionUnavailable
        }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        // Bound unresponsive-app IPC so a shortcut cannot freeze Ben indefinitely.
        AXUIElementSetMessagingTimeout(appElement, 0.2)
        let isEditor = Self.editorBundleIDs.contains(application.bundleIdentifier ?? "")
        let isChrome = application.bundleIdentifier == "com.google.Chrome"
        #if DEBUG
        // Exercise the actual signed process's copy fallback without translation.
        let attempts = CommandLine.arguments.contains("--check-selection") &&
            CommandLine.arguments.contains("--check-copy-selection") ? 0 : 2
        #else
        let attempts = 2
        #endif
        for attempt in 0..<attempts {
            try Task.checkCancellation()
            guard applicationProvider()?.processIdentifier == application.processIdentifier,
                  !application.isTerminated else { throw BenError.selectionUnavailable }
            if let focused = Self.elementAttribute(appElement, kAXFocusedUIElementAttribute) {
                // Embedded web views can focus a deeply nested node while exposing
                // selection only on its AXWebArea. Stay on the focus chain.
                var candidates = [focused]
                let deadline = ContinuousClock.now.advanced(by: .seconds(1))
                for _ in 0..<8 {
                    guard ContinuousClock.now < deadline else { break }
                    let current = candidates.last!
                    let role = Self.stringAttribute(current, kAXRoleAttribute)
                    // An editable field owns its selection, even when empty.
                    // Do not fall through from the omnibox to an old page selection.
                    if Self.isTextInput(role) || role == "AXWebArea" || role == kAXWindowRole as String { break }
                    guard let parent = Self.elementAttribute(current, kAXParentAttribute),
                          !candidates.contains(where: { CFEqual($0, parent) }) else { break }
                    candidates.append(parent)
                }
                if candidates.contains(where: { Self.stringAttribute($0, kAXSubroleAttribute) == kAXSecureTextFieldSubrole as String }) {
                    throw BenError.secureInput
                }
                for element in candidates {
                    if let selected = try Self.selectedText(in: element) {
                        try Task.checkCancellation()
                        guard applicationProvider()?.processIdentifier == application.processIdentifier else {
                            throw BenError.selectionUnavailable
                        }
                        return selected
                    }
                }
            }
            if attempt == 0 {
                // Electron exposes this attribute for assistive clients. Ask
                // only when supported; never enable unrelated OS settings.
                let manual = "AXManualAccessibility" as CFString
                var manuallySettable = DarwinBoolean(false)
                if AXUIElementIsAttributeSettable(appElement, manual, &manuallySettable) == .success,
                   manuallySettable.boolValue,
                   (Self.attribute(appElement, "AXManualAccessibility") as? Bool) != true {
                    AXUIElementSetAttributeValue(appElement, manual, kCFBooleanTrue)
                }
                var enabledChromeAccessibility = false
                if isChrome {
                    // Chromium lazily enables its complete accessibility tree.
                    // Request it only when needed, without changing OS settings.
                    let name = "AXEnhancedUserInterface" as CFString
                    var settable = DarwinBoolean(false)
                    if AXUIElementIsAttributeSettable(appElement, name, &settable) == .success,
                       settable.boolValue,
                       (Self.attribute(appElement, "AXEnhancedUserInterface") as? Bool) != true {
                        enabledChromeAccessibility = AXUIElementSetAttributeValue(appElement, name, kCFBooleanTrue) == .success
                    }
                }
                // Chromium debounces its first complete-tree request for two seconds.
                // Await it without activating Ben or blocking the main run loop.
                try await Task.sleep(for: .milliseconds(enabledChromeAccessibility ? 2_200 : 80))
            }
        }
        return try await SelectionCopyFallback(
            pasteboard: .general,
            isCurrentApplication: {
                self.applicationProvider()?.processIdentifier == application.processIdentifier &&
                NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier &&
                !application.isTerminated
            },
            requiresEditorMetadata: isEditor,
            copy: {
                SelectionCopyFallback.pressCopy(in: appElement, processIdentifier: application.processIdentifier) {
                    self.applicationProvider()?.processIdentifier == application.processIdentifier &&
                    NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier &&
                    !application.isTerminated
                }
            }
        ).readSelection()
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    private static func isTextInput(_ role: String?) -> Bool {
        role == kAXTextFieldRole as String || role == kAXTextAreaRole as String || role == kAXComboBoxRole as String
    }

    private static func selectedText(in element: AXUIElement) throws -> String? {
        if let text = stringAttribute(element, kAXSelectedTextAttribute),
           let selected = try validatedText(text) { return selected }
        if let selected = try selectedMarkerText(in: element) { return selected }
        guard let value = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let selection = unsafeDowncast(value, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(selection) == .cfRange,
              AXValueGetValue(selection, .cfRange, &range), range.location >= 0, range.length > 0 else { return nil }
        // Swift Character may contain several UTF-16 code units. Apply the
        // actual 5,000-character limit after extraction; still bound IPC size.
        guard range.length <= 100_000 else { throw BenError.textTooLong }
        var text: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                       selection, &text) == .success,
           let text = text as? String { return try validatedText(text) }
        guard let value = stringAttribute(element, kAXValueAttribute), value.utf16.count <= 1_048_576,
              let selected = substring(value, range: range) else { return nil }
        return try validatedText(selected)
    }

    private static func selectedMarkerText(in element: AXUIElement) throws -> String? {
        // Web selections use opaque text markers and may span multiple DOM nodes.
        // Pass the marker back to AX; never interpret its internal bytes as a range.
        guard stringAttribute(element, kAXRoleAttribute) == "AXWebArea",
              let range = attribute(element, "AXSelectedTextMarkerRange") else { return nil }
        var lengthValue: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(element, "AXLengthForTextMarkerRange" as CFString,
                                                       range, &lengthValue) == .success,
           let length = lengthValue as? NSNumber {
            guard length.intValue > 0 else { return nil }
            guard length.intValue <= 100_000 else { throw BenError.textTooLong }
        }
        var text: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString,
                                                        range, &text) == .success,
              let text = text as? String else { return nil }
        return try validatedText(text)
    }

    static func validatedText(_ text: String) throws -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= 5_000 else { throw BenError.textTooLong }
        return trimmed
    }

    /// AX ranges use UTF-16 offsets, not Swift Character offsets.
    static func substring(_ text: String, range: CFRange) -> String? {
        let length = text.utf16.count
        guard range.location >= 0, range.length > 0, range.location <= length,
              range.length <= length - range.location else { return nil }
        let nsRange = NSRange(location: range.location, length: range.length)
        guard let swiftRange = Range(nsRange, in: text),
              swiftRange.lowerBound.samePosition(in: text.unicodeScalars) != nil,
              swiftRange.upperBound.samePosition(in: text.unicodeScalars) != nil else { return nil }
        return String(text[swiftRange])
    }
}
