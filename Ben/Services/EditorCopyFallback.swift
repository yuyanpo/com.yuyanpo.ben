import AppKit
import Carbon
@preconcurrency import ApplicationServices

/// A single shortcut-triggered copy transaction, never an idle clipboard monitor.
@MainActor
struct EditorCopyFallback {
    let pasteboard: NSPasteboard
    let isCurrentApplication: () -> Bool
    let copy: () -> Bool

    func readSelection() async throws -> String {
        guard isCurrentApplication(), !IsSecureEventInputEnabled() else { throw BenError.selectionUnavailable }
        let originalCount = pasteboard.changeCount
        let originals = try snapshot()
        guard pasteboard.changeCount == originalCount, isCurrentApplication() else { throw BenError.selectionUnavailable }
        guard copy() else { throw BenError.selectionUnavailable }
        var copiedCount: Int? = pasteboard.changeCount != originalCount ? pasteboard.changeCount : nil
        defer {
            // Never overwrite a user's subsequent copy, including during awaits.
            if let copiedCount, pasteboard.changeCount == copiedCount {
                pasteboard.clearContents()
                if !originals.isEmpty { pasteboard.writeObjects(originals) }
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(650))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            guard isCurrentApplication() else { throw BenError.selectionUnavailable }
            if pasteboard.changeCount != originalCount {
                copiedCount = pasteboard.changeCount
                let items = pasteboard.pasteboardItems ?? []
                // Monaco copies the whole line when selection is empty. Only
                // accept its explicit metadata proving a real selection.
                let metadata = items.compactMap(Self.editorMetadata).first
                guard let metadata, metadata["version"] as? Int == 1 else {
                    // This may be a newer copy by the user; leave it intact.
                    copiedCount = nil
                    throw BenError.selectionUnavailable
                }
                guard metadata["isFromEmptySelection"] as? Bool == false,
                      let text = pasteboard.string(forType: .string),
                      pasteboard.changeCount == copiedCount,
                      let selected = try SelectedTextReader.validatedText(text) else {
                    throw BenError.selectionUnavailable
                }
                return selected
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw BenError.selectionUnavailable
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

    static func pressCopy(in application: AXUIElement, isCurrentApplication: () -> Bool) -> Bool {
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value
        }
        guard let menuValue = attribute(application, kAXMenuBarAttribute),
              CFGetTypeID(menuValue) == AXUIElementGetTypeID() else { return false }
        var queue: [(AXUIElement, Int)] = [(unsafeDowncast(menuValue, to: AXUIElement.self), 0)]
        var visited = 0
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !queue.isEmpty, visited < 250, ContinuousClock.now < deadline {
            let (element, depth) = queue.removeFirst()
            visited += 1
            if (attribute(element, kAXMenuItemCmdCharAttribute) as? String)?.lowercased() == "c",
               attribute(element, kAXMenuItemCmdModifiersAttribute) as? Int == 0,
               attribute(element, kAXEnabledAttribute) as? Bool == true {
                guard isCurrentApplication(), !IsSecureEventInputEnabled() else { return false }
                return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
            }
            if depth < 4, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                queue.append(contentsOf: children.map { ($0, depth + 1) })
            }
        }
        return false
    }
}
