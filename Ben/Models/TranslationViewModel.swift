import AppKit
import SwiftUI

@MainActor
final class TranslationViewModel: ObservableObject {
    @Published var inputText = "" {
        didSet {
            if inputText != oldValue {
                resetCopyFeedback(for: .original)
                speech.stop()
            }
        }
    }
    @Published private(set) var result: TranslationResult?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isBusy = false
    @Published private(set) var request: TranslationRequest?
    @Published private(set) var copied = false
    @Published private(set) var copiedOriginal = false
    @Published private(set) var sourceLanguage = SourceLanguage.automatic
    @Published private(set) var selectedProvider: TranslationProviderID

    private let provider: any TranslationProvider
    private let defaults: UserDefaults
    private var translationTask: Task<Void, Never>?
    private var originalCopyResetTask: Task<Void, Never>?
    private var translationCopyResetTask: Task<Void, Never>?
    private enum CopySection { case original, translation }
    let speech = TextSpeechController()

    init(provider: any TranslationProvider = OnlineTranslationProvider(), defaults: UserDefaults = .standard) {
        self.provider = provider
        self.defaults = defaults
        selectedProvider = TranslationProviderID(rawValue: defaults.string(forKey: "translationProvider") ?? "") ?? .microsoft
    }

    var displayedProvider: TranslationProviderID {
        result.flatMap { TranslationProviderID(rawValue: $0.providerID) } ?? request?.providerID ?? selectedProvider
    }

    var detectedSourceLanguage: String? {
        sourceLanguage.identifier ?? LanguageDetection.sourceLanguage(for: inputText)
    }

    func selectProvider(_ value: TranslationProviderID) {
        guard value != selectedProvider else { return }
        cancel()
        selectedProvider = value
        defaults.set(value.rawValue, forKey: "translationProvider")
        result = nil
        errorMessage = nil
        copied = false
        // A settings change never uploads text. The next explicit translation uses this service.
    }

    func selectSourceLanguage(_ value: SourceLanguage) {
        guard value != sourceLanguage else { return }
        let shouldRetranslate = isBusy || result != nil || errorMessage != nil
        sourceLanguage = value
        if shouldRetranslate { beginTranslation() }
    }

    var direction: TranslationDirection {
        TranslationDirection(rawValue: defaults.string(forKey: "translationDirection") ?? "") ?? .automatic
    }

    func beginTranslation(text: String? = nil) {
        if text != nil { sourceLanguage = .automatic }
        let value = (text ?? inputText).trimmingCharacters(in: .whitespacesAndNewlines)
        cancel()
        inputText = value
        result = nil
        errorMessage = nil
        copied = false
        guard !value.isEmpty else { errorMessage = BenError.emptyText.localizedDescription; return }
        guard value.count <= 5_000 else { errorMessage = BenError.textTooLong.localizedDescription; return }
        let source = sourceLanguage.identifier ?? LanguageDetection.sourceLanguage(for: value)
        let target = direction.targetLanguage(for: source)
        if LanguageDetection.sameLanguage(source, target) {
            result = TranslationResult(
                originalText: value, translatedText: value, sourceLanguage: source ?? target,
                targetLanguage: target, providerID: selectedProvider.rawValue
            )
            errorMessage = "原文已是目标语言。"
            return
        }
        let activeRequest = TranslationRequest(text: value, sourceLanguage: source, targetLanguage: target, providerID: selectedProvider)
        request = activeRequest
        isBusy = true
        let provider = self.provider
        translationTask = Task { [weak self] in
            do {
                let translated = try await provider.translate(activeRequest)
                guard let self, self.request?.id == activeRequest.id, !Task.isCancelled else { return }
                self.result = translated
                self.errorMessage = nil
                self.isBusy = false
                self.translationTask = nil
            } catch {
                guard let self, self.request?.id == activeRequest.id, !Task.isCancelled else { return }
                self.isBusy = false
                self.translationTask = nil
                self.errorMessage = error is CancellationError ? "翻译已取消，可以重试。" : error.localizedDescription
            }
        }
    }

    func show(error: Error) {
        cancel()
        result = nil
        inputText = ""
        errorMessage = error.localizedDescription
        copied = false
    }

    func cancel() {
        speech.stop()
        resetCopyFeedback(for: .original)
        resetCopyFeedback(for: .translation)
        translationTask?.cancel()
        translationTask = nil
        request = nil
        isBusy = false
    }

    func copyResult() {
        guard let result else { return }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(result.translatedText, forType: .string) {
            showCopyFeedback(for: .translation)
        }
    }

    func copyOriginal() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(inputText, forType: .string) {
            showCopyFeedback(for: .original)
        }
    }

    private func showCopyFeedback(for section: CopySection) {
        resetCopyFeedback(for: section)
        switch section {
        case .original: copiedOriginal = true
        case .translation: copied = true
        }
        // Each click restarts its own feedback interval; cancelled tasks cannot reset a newer copy.
        let task = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            switch section {
            case .original:
                self.copiedOriginal = false
                self.originalCopyResetTask = nil
            case .translation:
                self.copied = false
                self.translationCopyResetTask = nil
            }
        }
        switch section {
        case .original: originalCopyResetTask = task
        case .translation: translationCopyResetTask = task
        }
    }

    private func resetCopyFeedback(for section: CopySection) {
        switch section {
        case .original:
            originalCopyResetTask?.cancel()
            originalCopyResetTask = nil
            copiedOriginal = false
        case .translation:
            translationCopyResetTask?.cancel()
            translationCopyResetTask = nil
            copied = false
        }
    }

    func clearText() {
        cancel()
        inputText = ""
        result = nil
        errorMessage = nil
        sourceLanguage = .automatic
        copied = false
        copiedOriginal = false
    }
}
