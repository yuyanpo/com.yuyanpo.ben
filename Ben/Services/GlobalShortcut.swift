import AppKit
import Carbon
import SwiftUI

private let benHotKeySignature: OSType = 0x42454E31 // BEN1

private func benHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == benHotKeySignature,
          let action = ShortcutAction(rawValue: hotKeyID.id) else {
        return OSStatus(eventNotHandledErr)
    }
    Task { @MainActor in
        NotificationCenter.default.post(name: action.notification, object: nil)
    }
    return noErr
}

extension Notification.Name {
    static let benTranslateSelection = Notification.Name("com.yuyanpo.ben.translate-selection")
    static let benTranslateText = Notification.Name("com.yuyanpo.ben.translate-text")
}

enum ShortcutAction: UInt32, CaseIterable, Identifiable {
    case text = 2
    case selection = 1

    var id: UInt32 { rawValue }
    var title: String { self == .text ? "翻译文本" : "翻译选中文字" }
    var notification: Notification.Name { self == .text ? .benTranslateText : .benTranslateSelection }
    var storageKey: String { "globalShortcut.\(rawValue)" }
    var defaultShortcut: KeyboardShortcut {
        KeyboardShortcut(keyCode: UInt32(self == .text ? kVK_ANSI_Z : kVK_ANSI_C), modifiers: UInt32(optionKey))
    }
}

struct KeyboardShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let modifierMask = UInt32(cmdKey | optionKey | controlKey | shiftKey)

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.modifierMask
    }

    init(event: NSEvent) {
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    var display: String {
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols + (Self.specialKeys[keyCode]?.display ?? layoutCharacter?.uppercased() ?? "?")
    }

    var menuKeyEquivalent: String {
        Self.specialKeys[keyCode]?.equivalent ?? layoutCharacter?.lowercased() ?? ""
    }

    var validationError: String? {
        guard modifiers & ~Self.modifierMask == 0,
              modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 else {
            return "请包含 ⌘、⌥ 或 ⌃ 中至少一个修饰键。"
        }
        guard !menuKeyEquivalent.isEmpty, keyCode != UInt32(kVK_Escape) else {
            return "请选择字母、数字、符号、方向键或功能键；Esc 用于取消录入。"
        }
        if modifiers == UInt32(cmdKey),
           [UInt32(kVK_ANSI_Q), UInt32(kVK_ANSI_Comma), UInt32(kVK_Return), UInt32(kVK_ANSI_KeypadEnter)].contains(keyCode) {
            return "\(display) 已用于 Ben 的退出、设置或发起翻译，请选择其他组合。"
        }
        return nil
    }

    // Translate the physical key without modifiers, so Option doesn't produce an accented character.
    private var layoutCharacter: String? {
        guard Self.printableKeyCodes.contains(keyCode),
              let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(
            layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, characters.count, &length, &characters
        )
        guard status == noErr, length > 0 else { return nil }
        let value = String(utf16CodeUnits: characters, count: length)
        return value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) } ? value : nil
    }

    private static let printableKeyCodes: Set<UInt32> = Set([
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
        22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 37, 38, 39, 40,
        41, 42, 43, 44, 45, 46, 47, 50, 65, 67, 69, 75, 78, 81, 82, 83, 84, 85,
        86, 87, 88, 89, 91, 92, 93, 94, 95, 102
    ])

    private static let specialKeys: [UInt32: (display: String, equivalent: String)] = {
        var keys: [UInt32: (String, String)] = [
            UInt32(kVK_Space): ("空格", " "), UInt32(kVK_Tab): ("⇥", "\t"),
            UInt32(kVK_Return): ("↵", "\r"), UInt32(kVK_ANSI_KeypadEnter): ("⌤", "\u{3}"),
            UInt32(kVK_Delete): ("⌫", "\u{8}"), UInt32(kVK_ForwardDelete): ("⌦", "\u{F728}"),
            UInt32(kVK_LeftArrow): ("←", "\u{F702}"), UInt32(kVK_RightArrow): ("→", "\u{F703}"),
            UInt32(kVK_UpArrow): ("↑", "\u{F700}"), UInt32(kVK_DownArrow): ("↓", "\u{F701}"),
            UInt32(kVK_Home): ("↖", "\u{F729}"), UInt32(kVK_End): ("↘", "\u{F72B}"),
            UInt32(kVK_PageUp): ("⇞", "\u{F72C}"), UInt32(kVK_PageDown): ("⇟", "\u{F72D}")
        ]
        let functionCodes = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
                             kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
                             kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (index, code) in functionCodes.enumerated() {
            keys[UInt32(code)] = ("F\(index + 1)", String(UnicodeScalar(0xF704 + index)!))
        }
        return keys
    }()
}

@MainActor
final class GlobalShortcut: ObservableObject {
    @Published private(set) var shortcuts: [ShortcutAction: KeyboardShortcut] = [:]
    @Published private(set) var registrationErrors: [ShortcutAction: String] = [:]
    @Published private(set) var editErrors: [ShortcutAction: String] = [:]
    @Published private(set) var recordingAction: ShortcutAction?
    private let defaults: UserDefaults
    private var hotKeys: [ShortcutAction: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for action in ShortcutAction.allCases {
            let saved = defaults.data(forKey: action.storageKey)
                .flatMap { try? JSONDecoder().decode(KeyboardShortcut.self, from: $0) }
            shortcuts[action] = saved?.validationError == nil ? saved ?? action.defaultShortcut : action.defaultShortcut
        }
    }

    func shortcut(for action: ShortcutAction) -> KeyboardShortcut {
        shortcuts[action] ?? action.defaultShortcut
    }

    func isRegistered(_ action: ShortcutAction) -> Bool { hotKeys[action] != nil }

    func register() {
        guard recordingAction == nil else { return }
        for action in ShortcutAction.allCases where hotKeys[action] == nil {
            let value = shortcut(for: action)
            if let error = conflictError(value, for: action) ?? installHandler() {
                registrationErrors[action] = error
                continue
            }
            switch registerHotKey(value, for: action) {
            case .success(let ref):
                hotKeys[action] = ref
                registrationErrors[action] = nil
            case .failure(let error): registrationErrors[action] = error.message
            }
        }
    }

    func beginRecording(_ action: ShortcutAction) {
        if recordingAction != nil { endRecording() }
        recordingAction = action
        editErrors[action] = nil
        // Release Ben's own shortcuts so they reach the recorder instead of opening the panel.
        releaseHotKeys()
    }

    func endRecording() {
        guard recordingAction != nil else { return }
        recordingAction = nil
        register()
    }

    @discardableResult
    func update(_ value: KeyboardShortcut, for action: ShortcutAction) -> Bool {
        if let error = conflictError(value, for: action) ?? installHandler() {
            editErrors[action] = error
            return false
        }
        if value != shortcut(for: action) || hotKeys[action] == nil {
            // Register the candidate before releasing the old binding. Failure preserves the old configuration.
            switch registerHotKey(value, for: action) {
            case .failure(let error):
                editErrors[action] = error.message
                return false
            case .success(let ref):
                if let oldRef = hotKeys[action] { UnregisterEventHotKey(oldRef) }
                hotKeys[action] = ref
            }
        }
        shortcuts[action] = value
        defaults.set(try? JSONEncoder().encode(value), forKey: action.storageKey)
        editErrors[action] = nil
        registrationErrors[action] = nil
        endRecording()
        return true
    }

    func unregister() {
        recordingAction = nil
        releaseHotKeys()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }

    private func releaseHotKeys() {
        for ref in hotKeys.values { UnregisterEventHotKey(ref) }
        hotKeys.removeAll()
    }

    private func conflictError(_ value: KeyboardShortcut, for action: ShortcutAction) -> String? {
        if let error = value.validationError { return error }
        if let other = ShortcutAction.allCases.first(where: { $0 != action && shortcut(for: $0) == value }) {
            return "\(value.display) 已用于「\(other.title)」，请选择其他组合。"
        }
        var symbolicKeys: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&symbolicKeys)
        guard status == noErr, let keys = symbolicKeys?.takeRetainedValue() as? [[String: Any]] else {
            return "无法检查系统快捷键（\(status)），请重试。"
        }
        let conflict = keys.contains { key in
            (key[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true &&
            (key[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value == value.keyCode &&
            ((key[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value ?? 0) & KeyboardShortcut.modifierMask == value.modifiers
        }
        return conflict ? "\(value.display) 与 macOS 系统快捷键冲突，请选择其他组合。" : nil
    }

    private func installHandler() -> String? {
        guard eventHandler == nil else { return nil }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(), benHotKeyHandler, 1, &eventType, nil, &eventHandler
        )
        return status == noErr ? nil : "快捷键监听初始化失败（\(status)），请重试。"
    }

    private struct RegistrationError: Error { let message: String }

    private func registerHotKey(_ value: KeyboardShortcut, for action: ShortcutAction) -> Result<EventHotKeyRef, RegistrationError> {
        var ref: EventHotKeyRef?
        // Exclusive registration rejects another exclusive owner. macOS may still allow existing non-exclusive listeners.
        let status = RegisterEventHotKey(
            value.keyCode, value.modifiers, EventHotKeyID(signature: benHotKeySignature, id: action.rawValue),
            GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref
        )
        guard status == noErr, let ref else {
            let message = status == OSStatus(eventHotKeyExistsErr)
                ? "\(value.display) 已被其他应用的全局快捷键占用，请更换组合或关闭冲突快捷键后重试。"
                : "\(value.display) 注册失败（\(status)），请更换组合或重试。"
            return .failure(RegistrationError(message: message))
        }
        return .success(ref)
    }
}
