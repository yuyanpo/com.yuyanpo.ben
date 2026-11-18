import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: TranslationViewModel
    @ObservedObject var reader: SelectedTextReader
    @ObservedObject var shortcuts: GlobalShortcut
    @AppStorage("translationDirection") private var direction = TranslationDirection.automatic.rawValue
    @State private var showsShortcutHelp = false

    var body: some View {
        Form {
            Section("翻译") {
                Picker("默认服务", selection: Binding(
                    get: { model.selectedProvider },
                    set: { model.selectProvider($0) }
                )) {
                    ForEach(TranslationProviderID.allCases) { value in
                        Text("\(value.title) · \(value.kind)").tag(value)
                    }
                }
                Text(model.selectedProvider.summary)
                    .font(.caption).foregroundStyle(.secondary)
                Picker("翻译方向", selection: $direction) {
                    ForEach(TranslationDirection.allCases) { value in
                        Text(value.title).tag(value.rawValue)
                    }
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("翻译时会联网，将原文发送给所选服务。切换服务后，下次翻译生效；失败时不会自动切换。")
                    Text("不保存翻译历史，不记录原文和译文。公开免费接口可能限流或调整。")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("全局快捷键") {
                ForEach(ShortcutAction.allCases) { action in
                    shortcutRow(action)
                        .transaction { $0.animation = nil }
                }
                shortcutFeedback
                    .transaction { $0.animation = nil }
            }
            Section("辅助功能权限") {
                HStack(spacing: 4) {
                    Image(systemName: reader.hasPermission ? "checkmark.circle" : "lock")
                    Text(reader.hasPermission ? "已授权" : "尚未授权")
                }
                .foregroundStyle(reader.hasPermission ? Color.green : Color.secondary)
                .accessibilityElement(children: .combine)
                Text("Ben 在你按快捷键时读取其他软件中选中的文字。手动输入不需要此权限。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("请求授权", action: reader.requestPermission)
                    Button("打开系统设置") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("刷新状态") { reader.refreshPermission() }
                }
                if !reader.hasPermission {
                    Text("系统已开启但这里仍未授权时，请退出并重新打开 Ben。若仍无效，请在系统设置中移除旧 Ben，再添加当前应用。开发版本重新构建后可能需要重新授权。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("在 Finder 中显示当前 Ben") {
                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(width: 560, height: 720)
        .onAppear { reader.refreshPermission() }
        .onDisappear { shortcuts.endRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            shortcuts.endRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            shortcuts.endRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            reader.refreshPermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            reader.refreshPermission()
        }
    }

    private func shortcutRow(_ action: ShortcutAction) -> some View {
        HStack(spacing: 12) {
            Text(action.title)
            Spacer(minLength: 12)
            ShortcutRecorder(shortcuts: shortcuts, action: action)
                .frame(width: 120, height: 24)
            Button {
                shortcuts.update(action.defaultShortcut, for: action)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(shortcuts.recordingAction != nil ||
                      (shortcuts.shortcut(for: action) == action.defaultShortcut && shortcuts.isRegistered(action)))
            .help("恢复默认快捷键 \(action.defaultShortcut.display)")
            .accessibilityLabel("恢复\(action.title)默认快捷键")
        }
    }

    private var shortcutError: String? {
        if let action = shortcuts.recordingAction {
            return shortcuts.editErrors[action]
        }
        return ShortcutAction.allCases.compactMap {
            shortcuts.editErrors[$0] ?? shortcuts.registrationErrors[$0]
        }.first
    }

    // Keep the same space in every state, including registration failures on the other shortcut.
    private var shortcutFeedback: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(shortcutError ?? (shortcuts.recordingAction != nil
                ? "按下新的组合键，Esc 取消。"
                : "点击快捷键修改，包含 ⌘、⌥ 或 ⌃。"))
                .font(.caption)
                .foregroundStyle(shortcutError == nil ? Color.secondary : Color.orange)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(shortcutError ?? "点击快捷键后按下新组合，Esc 取消。")
            Button("重试") { shortcuts.register() }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .opacity(!shortcuts.registrationErrors.isEmpty && shortcuts.recordingAction == nil ? 1 : 0)
                .disabled(shortcuts.registrationErrors.isEmpty || shortcuts.recordingAction != nil)
                .accessibilityHidden(shortcuts.registrationErrors.isEmpty || shortcuts.recordingAction != nil)
            Button { showsShortcutHelp.toggle() } label: {
                Image(systemName: "info.circle")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("快捷键与冲突检测说明")
            .accessibilityLabel("快捷键与冲突检测说明")
            .popover(isPresented: $showsShortcutHelp, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("快捷键说明").font(.headline)
                    Text("点击快捷键后按新的组合键，成功后自动保存。按 Esc 或点击其他位置取消。右侧复原按钮恢复默认组合。")
                    Text("保存时检查 Ben、macOS 系统和其他应用独占注册的全局快捷键。检测到冲突会保留原设置。")
                    Text("macOS 无法可靠检测其他应用的非独占快捷键或底层键盘监听。")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(16)
                .frame(width: 300, alignment: .leading)
            }
        }
        .frame(height: 24)
    }
}
