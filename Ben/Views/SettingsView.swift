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
                LabeledContent("默认服务", value: "macOS 系统翻译")
                Picker("翻译方向", selection: $direction) {
                    ForEach(TranslationDirection.allCases) { value in
                        Text(value.title).tag(value.rawValue)
                    }
                }
                Text("在设备上翻译。首次使用某个语言组合时，系统可能需要联网下载模型；安装后可离线使用。")
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
            Section("后续服务") {
                Text("第三方翻译 API · 大模型翻译")
                Text("接口结构已预留，当前版本尚未接入。系统翻译失败时不会自动上传文本到其他服务。")
                    .font(.caption).foregroundStyle(.secondary)
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
