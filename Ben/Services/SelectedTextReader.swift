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

    // Monaco editors can omit their AX selection. Only these editors may use
    // the copy fallback with their explicit selection metadata.
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
        for attempt in 0..<(isEditor ? 2 : 1) {
            try Task.checkCancellation()
            guard applicationProvider()?.processIdentifier == application.processIdentifier,
                  !application.isTerminated else { throw BenError.selectionUnavailable }
            if let focused = Self.elementAttribute(appElement, kAXFocusedUIElementAttribute) {
                // Some editors focus a child of their text element. Search only
                // its short ancestor chain, never windows or the document tree.
                var candidates = [focused]
                for _ in 0..<3 {
                    guard let parent = Self.elementAttribute(candidates.last!, kAXParentAttribute),
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
            if attempt == 0, isEditor {
                // Give the editor time to expose its updated tree without
                // activating Ben or blocking the main run loop.
                try await Task.sleep(for: .milliseconds(80))
            }
        }
        if isEditor {
            return try await EditorCopyFallback(
                pasteboard: .general,
                isCurrentApplication: { self.applicationProvider()?.processIdentifier == application.processIdentifier },
                copy: {
                    EditorCopyFallback.pressCopy(in: appElement) {
                        self.applicationProvider()?.processIdentifier == application.processIdentifier
                    }
                }
            ).readSelection()
        }
        throw BenError.selectionUnavailable
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

    private static func selectedText(in element: AXUIElement) throws -> String? {
        if let text = stringAttribute(element, kAXSelectedTextAttribute),
           let selected = try validatedText(text) { return selected }
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
