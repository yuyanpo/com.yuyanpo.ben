import AppKit
import SwiftUI

struct TranslationPanelView: View {
    @ObservedObject var model: TranslationViewModel
    @ObservedObject private var speech: TextSpeechController
    @State private var dictionaryContentHeight: CGFloat = 280
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
                    Text(model.displayedProvider.title)
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
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .buttonStyle(PanelToolButtonStyle(circular: false, filled: false))
                    .fixedSize()
                    .help("识别不准确时，可手动选择原文语种")
                }
                TextEditor(text: $model.inputText)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: inputHeight)
                    .background(Color(nsColor: .textBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.primary.opacity(0.14), lineWidth: 1))
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
                    Button("取消") { model.cancel() }
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .buttonStyle(PanelToolButtonStyle(circular: false))
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
                if let dictionary = result.dictionary {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("词典").font(.system(size: 11)).foregroundStyle(.secondary)
                        ScrollView {
                            dictionaryContent(dictionary)
                                .fixedSize(horizontal: false, vertical: true)
                                .onGeometryChange(for: CGFloat.self) { geometry in
                                    ceil(geometry.size.height)
                                } action: { height in
                                    if height.isFinite, height > 0 {
                                        dictionaryContentHeight = height
                                    }
                                }
                        }
                        .frame(height: min(280, dictionaryContentHeight))
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
            if entry.britishPhonetic != nil || entry.americanPhonetic != nil {
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
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(entry.meanings.enumerated()), id: \.offset) { _, meaning in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if !meaning.partOfSpeech.isEmpty {
                            Text(meaning.partOfSpeech)
                                .font(dictionaryMeaningLabelFont(meaning.partOfSpeech))
                                .foregroundStyle(.secondary.opacity(0.75))
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(minWidth: 26, alignment: .leading)
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
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
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
                SpeechSymbol(active: active)
                    .font(.system(size: 10)).frame(width: 22, height: 22)
            }
            .buttonStyle(PanelToolButtonStyle(active: active, filled: false))
            .help(active ? "停止朗读" : "使用系统语音朗读\(label)音")
            .accessibilityLabel("\(label)音朗读")
        }
    }

    private func dictionaryMeaningLabelFont(_ label: String) -> Font {
        if label.unicodeScalars.allSatisfy({ $0.isASCII }) {
            return .system(size: 12, design: .serif).italic()
        }
        return .system(size: 14)
    }

    private func speechButton(section: TranslationTextSection, text: String, language: String?) -> some View {
        let active = speech.speakingSection == section
        let name = section == .original ? "原文" : "译文"
        let help = active ? "停止朗读\(name)" : "朗读\(name)"
        return Button {
            speech.toggle(text: text, language: language, section: section)
        } label: {
            SpeechSymbol(active: active)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(PanelToolButtonStyle(active: active))
        .help(help).accessibilityLabel(help)
        .accessibilityValue(active ? "正在朗读" : "未播放")
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
        .buttonStyle(PanelToolButtonStyle(circular: false, filled: false))
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

private struct SpeechSymbol: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "speaker.wave.2")
            .symbolEffect(.variableColor.iterative.hideInactiveLayers,
                          options: .repeating, isActive: active && !reduceMotion)
    }
}

private struct PanelToolButtonStyle: ButtonStyle {
    var active = false
    var circular = true
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        PanelButtonFeedback(label: configuration.label, isPressed: configuration.isPressed,
                            active: active, circular: circular, filled: filled)
    }
}

private struct PanelButtonFeedback<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let active: Bool
    let circular: Bool
    let filled: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    private var feedback: Bool { isEnabled && (hovered || isPressed) }
    private var background: Color {
        if active {
            return Color.blue.opacity(isPressed && isEnabled ? 0.24 : (feedback ? 0.18 : 0.12))
        }
        return Color.primary.opacity(isPressed && isEnabled ? 0.14 : (feedback ? 0.08 : (filled ? 0.045 : 0)))
    }

    var body: some View {
        label
            .foregroundStyle(active ? Color.blue : (feedback ? Color.primary : Color.secondary))
            .background {
                if circular {
                    Circle().fill(background)
                } else {
                    RoundedRectangle(cornerRadius: 5).fill(background)
                }
            }
            .scaleEffect(isPressed && isEnabled && !reduceMotion ? 0.93 : 1)
            .opacity(isEnabled ? 1 : 0.35)
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: reduceMotion ? 0 : 0.12), value: hovered)
            .animation(.easeOut(duration: reduceMotion ? 0 : 0.1), value: isPressed)
    }
}
