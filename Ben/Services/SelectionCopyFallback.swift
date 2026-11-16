import AppKit
import Carbon
@preconcurrency import ApplicationServices

/// A single shortcut-triggered copy transaction, never an idle clipboard monitor.
@MainActor
struct SelectionCopyFallback {
    private static var transactionInProgress = false
    let pasteboard: NSPasteboard
    let isCurrentApplication: () -> Bool
    let requiresEditorMetadata: Bool
    let copy: () -> Bool

    func readSelection() async throws -> String {
        // A cancelled request may still have a Copy event in flight. Serialize
        // transactions so its cleanup cannot replace the next request's clipboard.
        while Self.transactionInProgress {
            try Task.checkCancellation()
            guard isCurrentApplication() else { throw BenError.selectionUnavailable }
            try await Task.sleep(for: .milliseconds(20))
        }
        Self.transactionInProgress = true
        defer { Self.transactionInProgress = false }
        guard try await Self.waitForShortcutRelease(isCurrentApplication: isCurrentApplication) else {
            throw BenError.selectionUnavailable
        }
        guard isCurrentApplication(), !IsSecureEventInputEnabled() else { throw BenError.selectionUnavailable }
        let originalCount = pasteboard.changeCount
        let originals = try snapshot()
        guard pasteboard.changeCount == originalCount, isCurrentApplication() else { throw BenError.selectionUnavailable }
        var copiedCount: Int?
        defer {
            // Never overwrite a user's subsequent copy, including during awaits.
            if let copiedCount, pasteboard.changeCount == copiedCount {
                pasteboard.clearContents()
                if !originals.isEmpty { pasteboard.writeObjects(originals) }
            }
        }
        guard copy() else { throw BenError.selectionUnavailable }
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(800))
        while ContinuousClock.now < deadline {
            // Capture our completed copy before checking cancellation so its
            // clipboard can still be restored if a newer request replaces it.
            if copiedCount == nil, pasteboard.changeCount != originalCount {
                copiedCount = pasteboard.changeCount
            }
            // If cancelled after dispatch, drain the in-flight Copy within the
            // same deadline before releasing the transaction to a new request.
            if Task.isCancelled || !isCurrentApplication() {
                if copiedCount != nil { break }
                // Task.sleep throws immediately in a cancelled task; use an
                // uncancelled sleeper to avoid spinning on the main actor.
                await Self.cleanupDelay()
                continue
            }
            if let observedCount = copiedCount {
                guard pasteboard.changeCount == observedCount else {
                    throw BenError.selectionUnavailable
                }
                let items = pasteboard.pasteboardItems ?? []
                // Monaco copies the whole line when selection is empty. Only
                // accept its explicit metadata proving a real selection.
                let metadata = items.compactMap(Self.editorMetadata).first
                if requiresEditorMetadata || metadata != nil {
                    guard let metadata, metadata["version"] as? Int == 1,
                          metadata["isFromEmptySelection"] as? Bool == false else {
                        throw BenError.selectionUnavailable
                    }
                }
                guard let text = pasteboard.string(forType: .string),
                      pasteboard.changeCount == observedCount,
                      let selected = try SelectedTextReader.validatedText(text) else {
                    throw BenError.selectionUnavailable
                }
                return selected
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        try Task.checkCancellation()
        throw BenError.selectionUnavailable
    }

    private static func cleanupDelay() async {
        await Task.detached { try? await Task.sleep(for: .milliseconds(20)) }.value
    }

    private func snapshot() throws -> [NSPasteboardItem] {
        var total = 0
        return try (pasteboard.pasteboardItems ?? []).map { original in
            let clone = NSPasteboardItem()
            for type in original.types {
                guard let data = original.data(forType: type) else { throw BenError.selectionUnavailable }
                total += data.count
                // Skip fallback if we cannot safely preserve a large clipboard.
                guard total <= 16 * 1_048_576, clone.setData(data, forType: type) else {
                    throw BenError.selectionUnavailable
                }
            }
            return clone
        }
    }

    static func editorMetadata(_ item: NSPasteboardItem) -> [String: Any]? {
        guard let data = item.data(forType: NSPasteboard.PasteboardType("org.chromium.web-custom-data")),
              data.count <= 1_048_576,
              let encoded = chromiumData(data)["vscode-editor-data"],
              let metadata = try? JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any] else { return nil }
        return metadata
    }

    /// Chromium serializes custom clipboard MIME data as an IPC Pickle of UTF-16 pairs.
    static func chromiumData(_ data: Data) -> [String: String] {
        let bytes = [UInt8](data)
        var offset = 0
        func integer() -> Int? {
            guard offset <= bytes.count - 4 else { return nil }
            let value = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
            offset += 4
            return Int(value)
        }
        func string() -> String? {
            guard let count = integer(), count <= 1_048_576, count <= (bytes.count - offset) / 2 else { return nil }
            let units = (0..<count).map { UInt16(bytes[offset + $0 * 2]) | UInt16(bytes[offset + $0 * 2 + 1]) << 8 }
            offset += count * 2
            offset = (offset + 3) & ~3
            guard offset <= bytes.count else { return nil }
            return String(decoding: units, as: UTF16.self)
        }
        guard let payload = integer(), payload == bytes.count - 4,
              let count = integer(), count <= 100 else { return [:] }
        var result: [String: String] = [:]
        for _ in 0..<count {
            guard let key = string(), let value = string() else { return [:] }
            result[key] = value
        }
        return result
    }

    /// Prefer the app's explicit Copy command, independent of UI language.
    private static func pressCopyMenu(in application: AXUIElement, isCurrentApplication: () -> Bool) -> Bool? {
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value
        }
        guard let menuValue = attribute(application, kAXMenuBarAttribute),
              CFGetTypeID(menuValue) == AXUIElementGetTypeID() else { return nil }
        var queue: [(AXUIElement, Int)] = [(unsafeDowncast(menuValue, to: AXUIElement.self), 0)]
        var visited = 0
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !queue.isEmpty, visited < 250, ContinuousClock.now < deadline {
            let (element, depth) = queue.removeFirst()
            visited += 1
            if (attribute(element, kAXMenuItemCmdCharAttribute) as? String)?.lowercased() == "c",
               attribute(element, kAXMenuItemCmdModifiersAttribute) as? Int == 0 {
                guard attribute(element, kAXEnabledAttribute) as? Bool == true else { return false }
                guard isCurrentApplication(), !IsSecureEventInputEnabled() else { return false }
                return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success ? true : nil
            }
            if depth < 4, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                queue.append(contentsOf: children.map { ($0, depth + 1) })
            }
        }
        return nil
    }

    private static func waitForShortcutRelease(isCurrentApplication: () -> Bool) async throws -> Bool {
        // The triggering Option+C must be released before synthesizing Command+C.
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(700))
        let modifiers: CGEventFlags = [.maskAlternate, .maskControl, .maskShift, .maskCommand]
        while !CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty {
            try Task.checkCancellation()
            guard isCurrentApplication(), ContinuousClock.now < deadline else { return false }
            try await Task.sleep(for: .milliseconds(20))
        }
        try Task.checkCancellation()
        return isCurrentApplication()
    }

    static func pressCopy(in application: AXUIElement, processIdentifier: pid_t,
                          isCurrentApplication: () -> Bool) -> Bool {
        guard isCurrentApplication(), !IsSecureEventInputEnabled() else { return false }
        if let performed = pressCopyMenu(in: application, isCurrentApplication: isCurrentApplication) {
            return performed
        }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false),
              isCurrentApplication(), !IsSecureEventInputEnabled() else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        // Target the captured PID, never whichever app happens to be foreground later.
        down.postToPid(processIdentifier)
        up.postToPid(processIdentifier)
        return true
    }
}
