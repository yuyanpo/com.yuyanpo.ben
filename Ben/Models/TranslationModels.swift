import Foundation
import NaturalLanguage

struct TranslationRequest: Identifiable, Sendable {
    let id: UUID
    let text: String
    let sourceLanguage: String?
    let targetLanguage: String
    let providerID: TranslationProviderID

    init(text: String, sourceLanguage: String?, targetLanguage: String, providerID: TranslationProviderID) {
        id = UUID()
        self.text = text
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.providerID = providerID
    }
}

struct TranslationResult: Sendable {
    let originalText: String
    let translatedText: String
    let sourceLanguage: String
    let targetLanguage: String
    let providerID: String
}

enum TranslationDirection: String, CaseIterable, Identifiable {
    case automatic, simplifiedChinese, english

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "自动 · 中文 ↔ 英文"
        case .simplifiedChinese: "译成简体中文"
        case .english: "译成英文"
        }
    }

    func targetLanguage(for source: String?) -> String {
        switch self {
        case .automatic: source?.hasPrefix("zh") == true ? "en" : "zh-Hans"
        case .simplifiedChinese: "zh-Hans"
        case .english: "en"
        }
    }
}

enum LanguageDetection {
    static func sourceLanguage(for text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let letters = value.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return nil }

        // Short Latin words and product names are ambiguous. Ben's primary use
        // is Chinese/English reading, so prefer English for short ASCII input.
        let words = value.split(whereSeparator: { $0.isWhitespace })
        if letters.allSatisfy({ (65...90).contains($0.value) || (97...122).contains($0.value) }),
           letters.count <= 40, words.count <= 3 {
            return "en"
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(value)
        return recognizer.dominantLanguage?.rawValue
    }

    static func sameLanguage(_ lhs: String?, _ rhs: String) -> Bool {
        guard let lhs else { return false }
        return Locale.Language(identifier: lhs).languageCode == Locale.Language(identifier: rhs).languageCode
    }
}

/// Per-panel correction for ambiguous words; a new captured selection resets it.
enum SourceLanguage: String, CaseIterable, Identifiable {
    case automatic, english = "en", chinese = "zh-Hans", japanese = "ja", korean = "ko"
    case french = "fr", german = "de", spanish = "es", dutch = "nl", turkish = "tr"

    var id: String { rawValue }
    var identifier: String? { self == .automatic ? nil : rawValue }
    var title: String {
        if self == .automatic { return "自动识别" }
        return Locale(identifier: "zh-Hans").localizedString(forLanguageCode: rawValue) ?? rawValue
    }
}

enum BenError: LocalizedError {
    case emptyText, textTooLong, permissionRequired, selectionUnavailable
    case secureInput

    var errorDescription: String? {
        switch self {
        case .emptyText: "请输入或选中要翻译的文字。"
        case .textTooLong: "选中文字超过 5,000 字，请缩短内容后重试。"
        case .permissionRequired: "请在设置中开启 Ben 的辅助功能权限，以读取选中文字。你也可以在这里手动输入。"
        case .selectionUnavailable: "未读取到选中文字。请先选中文字；如果当前软件不支持，可以在这里粘贴后翻译。"
        case .secureInput: "Ben 不会读取密码等安全输入字段。"
        }
    }
}
