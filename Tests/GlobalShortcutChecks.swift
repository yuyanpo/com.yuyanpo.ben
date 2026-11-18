import AppKit
import Carbon

@main
struct GlobalShortcutChecks {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        if CommandLine.arguments.contains("--occupy") {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(CommandLine.arguments[2])!, UInt32(CommandLine.arguments[3])!,
                EventHotKeyID(signature: 0x54455354, id: 99), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref
            )
            FileHandle.standardOutput.write(Data("\(status)\n".utf8))
            _ = FileHandle.standardInput.readDataToEndOfFile()
            if let ref { UnregisterEventHotKey(ref) }
            return
        }

        let suite = "com.yuyanpo.ben.shortcut-checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = GlobalShortcut(defaults: defaults)
        defer { manager.unregister() }
        precondition(manager.shortcut(for: .text).display == "⌥Z")
        precondition(manager.shortcut(for: .selection).display == "⌥C")
        precondition(manager.shortcut(for: .text).menuKeyEquivalent == "z")
        precondition(KeyboardShortcut(keyCode: UInt32(kVK_ANSI_Z), modifiers: UInt32(shiftKey)).validationError != nil)
        precondition(KeyboardShortcut(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(cmdKey)).validationError != nil)

        let modifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        let text = KeyboardShortcut(keyCode: UInt32(kVK_F17), modifiers: modifiers)
        let selection = KeyboardShortcut(keyCode: UInt32(kVK_F18), modifiers: modifiers)
        precondition(manager.update(text, for: .text), manager.editErrors[.text] ?? "text registration failed")
        precondition(manager.update(selection, for: .selection), manager.editErrors[.selection] ?? "selection registration failed")
        precondition(manager.isRegistered(.text) && manager.isRegistered(.selection))
        precondition(!manager.update(text, for: .selection))
        precondition(manager.shortcut(for: .selection) == selection && manager.isRegistered(.selection))
        precondition(GlobalShortcut(defaults: defaults).shortcut(for: .text) == text)

        // Hold a global registration in another process while testing Ben's conflict path.
        let occupied = KeyboardShortcut(keyCode: UInt32(kVK_F19), modifiers: modifiers)
        let child = Process()
        let input = Pipe()
        let output = Pipe()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--occupy", String(occupied.keyCode), String(occupied.modifiers)]
        child.standardInput = input
        child.standardOutput = output
        try child.run()
        defer {
            try? input.fileHandleForWriting.close()
            child.waitUntilExit()
        }
        var readiness = Data()
        while !readiness.contains(10) {
            let chunk = output.fileHandleForReading.readData(ofLength: 1)
            precondition(!chunk.isEmpty, "conflict fixture exited")
            readiness.append(chunk)
        }
        precondition(String(decoding: readiness, as: UTF8.self) == "0\n", "conflict fixture registration failed")
        precondition(!manager.update(occupied, for: .text))
        precondition(manager.editErrors[.text]?.contains("其他应用") == true)
        precondition(manager.shortcut(for: .text) == text && manager.isRegistered(.text))
        precondition(GlobalShortcut(defaults: defaults).shortcut(for: .text) == text)

        var symbolicKeys: Unmanaged<CFArray>?
        precondition(CopySymbolicHotKeys(&symbolicKeys) == noErr)
        let keys = symbolicKeys!.takeRetainedValue() as! [[String: Any]]
        let systemShortcut = keys.compactMap { key -> KeyboardShortcut? in
            guard (key[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true,
                  let code = key[kHISymbolicHotKeyCode as String] as? NSNumber,
                  let modifiers = key[kHISymbolicHotKeyModifiers as String] as? NSNumber else { return nil }
            let value = KeyboardShortcut(keyCode: code.uint32Value, modifiers: modifiers.uint32Value)
            return value.validationError == nil ? value : nil
        }.first!
        precondition(!manager.update(systemShortcut, for: .text))
        precondition(manager.editErrors[.text]?.contains("macOS") == true)
        precondition(manager.isRegistered(.text))

        manager.beginRecording(.text)
        precondition(!manager.isRegistered(.text) && !manager.isRegistered(.selection))
        precondition(!manager.update(selection, for: .text))
        precondition(manager.recordingAction == .text)
        manager.endRecording()
        precondition(manager.isRegistered(.text) && manager.isRegistered(.selection))
        manager.beginRecording(.text)
        let replacement = KeyboardShortcut(keyCode: UInt32(kVK_F20), modifiers: modifiers)
        precondition(manager.update(replacement, for: .text))
        precondition(manager.recordingAction == nil)
        precondition(manager.isRegistered(.text) && manager.isRegistered(.selection))
        precondition(GlobalShortcut(defaults: defaults).shortcut(for: .text) == replacement)
        manager.unregister()
        manager.register()
        precondition(manager.isRegistered(.text) && manager.isRegistered(.selection))
        print("Defaults, persistence, duplicate/system/cross-process conflicts, rollback, recording cancellation and re-registration passed")
    }
}
