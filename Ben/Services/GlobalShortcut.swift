import Carbon
import Foundation

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
    guard status == noErr, hotKeyID.signature == benHotKeySignature, hotKeyID.id == 1 else {
        return OSStatus(eventNotHandledErr)
    }
    Task { @MainActor in
        NotificationCenter.default.post(name: .benTranslateSelection, object: nil)
    }
    return noErr
}

extension Notification.Name {
    static let benTranslateSelection = Notification.Name("com.yuyanpo.ben.translate-selection")
}

@MainActor
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func register() -> String? {
        unregister()
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(), benHotKeyHandler, 1, &eventType, nil, &eventHandler
        )
        guard handlerStatus == noErr else {
            return "快捷键监听初始化失败（\(handlerStatus)），可以使用菜单栏手动翻译。"
        }
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_C), UInt32(optionKey),
            EventHotKeyID(signature: benHotKeySignature, id: 1), GetApplicationEventTarget(), 0, &hotKey
        )
        guard status == noErr else {
            unregister()
            return "Option + C 注册失败，可能已被百度翻译等软件占用。请关闭冲突快捷键后重试。（\(status)）"
        }
        return nil
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKey = nil
        eventHandler = nil
    }
}
