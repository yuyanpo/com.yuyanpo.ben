import AppKit
import SwiftUI

struct TranslationPanelView: View {
    @ObservedObject var model: TranslationViewModel
    @ObservedObject private var speech: TextSpeechController
    let close: () -> Void
    let openSettings: () -> Void
    let resize: (CGFloat) -> Void

    init(model: TranslationViewModel, close: @escaping () -> Void,
         openSettings: @escaping () -> Void, resize: @escaping (CGFloat) -> Void) {
        self.model = model
        speech = model.speech
        self.close = close
        self.openSettings = openSettings
        self.resize = resize
    }

    private var hasInput: Bool {
        !model.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let contentWidth: CGFloat = 372
    private var inputHeight: CGFloat {
        min(128, max(52, textHeight(model.inputText, size: 14) + 18))
    }
    private var resultHeight: CGFloat {
        min(220, max(24, textHeight(model.result?.translatedText ?? "", size: 17) + 4))
    }
    private var sourceTitle: String {
        let name = model.detectedSourceLanguage.map(languageName) ?? "语种"
        return model.sourceLanguage == .automatic ? "自动 · \(name)" : name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image("BrandMark").resizable().scaledToFit().frame(width: 26, height: 26)
                    Text("Ben").font(.system(size: 14, weight: .semibold))
                    Text("\(model.displayedProvider.title) · \(model.displayedProvider.kind)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .pointerStyle(.image(
                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right"),
                    hotSpot: .center
                ))
                .help("拖动以移动窗口")
                iconButton("gearshape", help: "设置", action: openSettings)
                iconButton("xmark", help: "关闭 · Esc", action: close)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("原文").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Picker("原文语种", selection: Binding(
                            get: { model.sourceLanguage },
                            set: { model.selectSourceLanguage($0) }
                        )) {
                            ForEach(SourceLanguage.allCases) { value in
                                Text(value.title).tag(value)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(sourceTitle)
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("识别不准确时，可手动选择原文语种")
                }
                TextEditor(text: $model.inputText)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: inputHeight)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.65),
                                in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.06)))
                    .overlay(alignment: .topLeading) {
                        if model.inputText.isEmpty {
                            Text("输入翻译的文字")
                                .font(.system(size: 14))
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 11)
                                .padding(.top, 6)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel("要翻译的文字")
                HStack(spacing: 8) {
                    speechButton(section: .original, text: model.inputText,
                                 language: model.detectedSourceLanguage)
                        .disabled(!hasInput)
                    toolButton(model.copiedOriginal ? "checkmark" : "doc.on.doc",
                               help: model.copiedOriginal ? "已复制原文" : "复制原文",
                               active: model.copiedOriginal, action: model.copyOriginal)
                        .disabled(!hasInput)
                    toolButton("trash", help: "清空原文和译文", action: model.clearText)
                        .disabled(!hasInput && model.result == nil && model.errorMessage == nil && !model.isBusy)
                    Spacer()
                    Text("选词 ⌥C · 翻译 ⌘↵")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }

            if model.isBusy {
                Divider()
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在使用\(model.displayedProvider.title)翻译…")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button("取消") { model.cancel() }.controlSize(.small)
                }
            } else if let result = model.result {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("译文").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(languageName(result.sourceLanguage)) → \(languageName(result.targetLanguage))")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    ScrollView {
                        Text(result.translatedText)
                            .font(.system(size: 17))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                    }
                    .frame(height: resultHeight)
                    HStack(spacing: 8) {
                        speechButton(section: .translation, text: result.translatedText,
                                     language: result.targetLanguage)
                        toolButton(model.copied ? "checkmark" : "doc.on.doc",
                                   help: model.copied ? "已复制译文" : "复制译文",
                                   active: model.copied, action: model.copyResult)
                        Spacer()
                        if let message = model.errorMessage {
                            Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else if let error = model.errorMessage {
                Divider()
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 400, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { resize(geometry.size.height) }
                    .onChange(of: geometry.size.height) { _, height in resize(height) }
            }
        }
        .onExitCommand(perform: close)
    }

    private func speechButton(section: TranslationTextSection, text: String, language: String?) -> some View {
        let active = speech.speakingSection == section
        let name = section == .original ? "原文" : "译文"
        return toolButton(active ? "stop.fill" : "speaker.wave.2",
                          help: active ? "停止朗读\(name)" : "朗读\(name)", active: active) {
            speech.toggle(text: text, language: language, section: section)
        }
    }

    private func toolButton(_ symbol: String, help: String, active: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(PanelToolButtonStyle(active: active))
        .help(help).accessibilityLabel(help)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12))
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(.secondary)
        .help(help).accessibilityLabel(help)
    }

    private func textHeight(_ text: String, size: CGFloat) -> CGFloat {
        let rect = ((text.isEmpty ? " " : text) as NSString).boundingRect(
            with: NSSize(width: contentWidth - 20, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: size)]
        )
        return ceil(rect.height)
    }

    private func languageName(_ identifier: String) -> String {
        if identifier == "auto" { return "自动识别" }
        return Locale(identifier: "zh-Hans").localizedString(forLanguageCode: identifier) ?? identifier
    }
}

private struct PanelToolButtonStyle: ButtonStyle {
    let active: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(active ? Color.accentColor : Color.secondary)
            .background {
                Circle().fill(active ? Color.accentColor.opacity(0.12) : Color.primary.opacity(configuration.isPressed ? 0.12 : 0.045))
            }
            .opacity(isEnabled ? 1 : 0.35)
    }
}
