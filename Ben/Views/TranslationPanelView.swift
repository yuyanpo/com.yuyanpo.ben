import AppKit
import SwiftUI

struct TranslationPanelView: View {
    @ObservedObject var model: TranslationViewModel
    @ObservedObject private var speech: TextSpeechController
    @Environment(\.colorScheme) private var colorScheme
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
    private var dictionaryTagColor: Color {
        colorScheme == .dark
            ? Color(red: 0.67, green: 0.69, blue: 0.85)
            : Color(red: 0.48, green: 0.51, blue: 0.66)
    }
    private var inputHeight: CGFloat {
        min(128, max(52, textHeight(model.inputText, size: 14) + 18))
    }
    private var resultHeight: CGFloat {
        min(220, max(24, textHeight(model.result?.translatedText ?? "", size: 17) + 4))
    }
    private var dictionaryHeight: CGFloat {
        guard let entry = model.result?.dictionary else { return 0 }
        let meanings = entry.meanings.reduce(CGFloat(0)) { height, meaning in
            height + textHeight(meaning.definitions.joined(separator: "；"), size: 14, width: contentWidth - 48) + 12
        }
        let formSizes = entry.forms.map { form in
            let text = "\(form.label)：\(form.words.joined(separator: "、"))"
            return NSSize(width: textWidth(text, size: 11) + 4, height: 16)
        }
        let forms = entry.forms.isEmpty ? 0 : DictionaryFlowLayout(spacing: 10, rowSpacing: 6)
            .arrangement(sizes: formSizes, width: contentWidth).size.height + 12
        let tagSizes = entry.tags.map { NSSize(width: textWidth($0, size: 10) + 16, height: 22) }
        let tags = entry.tags.isEmpty ? 0 : DictionaryFlowLayout(spacing: 6, rowSpacing: 6)
            .arrangement(sizes: tagSizes, width: contentWidth).size.height + 12
        return min(280, max(80, 76 + meanings + forms + tags))
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
                        Text(result.dictionary == nil ? "译文" : "词典").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(languageName(result.sourceLanguage)) → \(languageName(result.targetLanguage))")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    ScrollView {
                        if let dictionary = result.dictionary {
                            dictionaryContent(dictionary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(result.translatedText)
                                .font(.system(size: 17))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 2)
                        }
                    }
                    .frame(height: result.dictionary == nil ? resultHeight : dictionaryHeight)
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

    private func dictionaryContent(_ entry: DictionaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entry.word)
                .font(.system(size: 20, weight: .semibold))
                .textSelection(.enabled)
            HStack(spacing: 14) {
                if let phonetic = entry.britishPhonetic {
                    pronunciation("英", phonetic: phonetic, word: entry.word,
                                  language: "en-GB", section: .britishPronunciation)
                }
                if let phonetic = entry.americanPhonetic {
                    pronunciation("美", phonetic: phonetic, word: entry.word,
                                  language: "en-US", section: .americanPronunciation)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(entry.meanings.enumerated()), id: \.offset) { _, meaning in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if !meaning.partOfSpeech.isEmpty {
                            Text(meaning.partOfSpeech)
                                .font(.system(size: 12, design: .serif).italic())
                                .foregroundStyle(.secondary.opacity(0.75))
                                .frame(width: 26, alignment: .leading)
                        }
                        Text(meaning.definitions.joined(separator: "；"))
                            .font(.system(size: 14))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if !entry.forms.isEmpty {
                DictionaryFlowLayout(spacing: 10, rowSpacing: 6) {
                    ForEach(Array(entry.forms.enumerated()), id: \.offset) { _, form in
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(form.label)：")
                                .foregroundStyle(.secondary.opacity(0.75))
                            Text(form.words.joined(separator: "、"))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .font(.system(size: 11))
            }
            if !entry.tags.isEmpty {
                DictionaryFlowLayout(spacing: 6, rowSpacing: 6) {
                    ForEach(entry.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(dictionaryTagColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(dictionaryTagColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private func pronunciation(_ label: String, phonetic: String, word: String,
                               language: String, section: TranslationTextSection) -> some View {
        HStack(spacing: 4) {
            Text("\(label) /\(phonetic)/").font(.system(size: 11)).foregroundStyle(.secondary)
            let active = speech.speakingSection == section
            Button {
                speech.toggle(text: word, language: language, section: section)
            } label: {
                Image(systemName: active ? "stop.fill" : "speaker.wave.2")
                    .font(.system(size: 10)).frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(active ? Color.accentColor : Color.secondary)
            .help(active ? "停止朗读" : "使用系统语音朗读\(label)音")
            .accessibilityLabel("\(label)音朗读")
        }
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

    private func textHeight(_ text: String, size: CGFloat, width: CGFloat? = nil) -> CGFloat {
        let rect = ((text.isEmpty ? " " : text) as NSString).boundingRect(
            with: NSSize(width: width ?? contentWidth - 20, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: size)]
        )
        return ceil(rect.height)
    }

    private func textWidth(_ text: String, size: CGFloat) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size)]).width)
    }

    private func languageName(_ identifier: String) -> String {
        if identifier == "auto" { return "自动识别" }
        return Locale(identifier: "zh-Hans").localizedString(forLanguageCode: identifier) ?? identifier
    }
}

/// Keeps related words and tags together, wrapping only between items.
private struct DictionaryFlowLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .greatestFiniteMagnitude
        return arrangement(sizes: sizes(of: subviews, width: width), width: width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = sizes(of: subviews, width: bounds.width)
        let layout = arrangement(sizes: sizes, width: bounds.width)
        for index in subviews.indices {
            let point = layout.origins[index]
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                                  anchor: .topLeading, proposal: ProposedViewSize(sizes[index]))
        }
    }

    private func sizes(of subviews: Subviews, width: CGFloat) -> [CGSize] {
        subviews.map { view in
            let ideal = view.sizeThatFits(.unspecified)
            return ideal.width <= width ? ideal : view.sizeThatFits(ProposedViewSize(width: width, height: nil))
        }
    }

    func arrangement(sizes: [CGSize], width: CGFloat) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for size in sizes {
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            usedWidth = max(usedWidth, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), origins)
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
