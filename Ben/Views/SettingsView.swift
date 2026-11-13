import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: TranslationViewModel
    @ObservedObject var reader: SelectedTextReader
    @AppStorage("translationDirection") private var direction = TranslationDirection.automatic.rawValue
    let retryShortcut: () -> Void

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
                LabeledContent("选词翻译", value: "⌥ C")
                if let error = model.shortcutError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                    Button("重试注册", action: retryShortcut)
                } else {
                    Text("已注册 Option + C。自定义快捷键将在后续版本加入。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("辅助功能权限") {
                Label(reader.hasPermission ? "已授权" : "尚未授权", systemImage: reader.hasPermission ? "checkmark.circle" : "lock")
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
        .frame(width: 510, height: 590)
        .onAppear { reader.refreshPermission() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            reader.refreshPermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            reader.refreshPermission()
        }
    }
}
