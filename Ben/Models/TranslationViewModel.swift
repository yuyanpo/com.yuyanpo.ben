import AppKit
import SwiftUI
@preconcurrency import Translation

@MainActor
final class TranslationViewModel: ObservableObject {
    @Published var inputText = ""
    @Published private(set) var result: TranslationResult?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isBusy = false
    @Published private(set) var translationPhase = TranslationPhase.checkingModels
    @Published private(set) var request: TranslationRequest?
    @Published var configuration: TranslationSession.Configuration?
    @Published var shortcutError: String?
    @Published var copied = false
    @Published private(set) var sourceLanguage = SourceLanguage.automatic

    var detectedSourceLanguage: String? {
        sourceLanguage.identifier ?? LanguageDetection.sourceLanguage(for: inputText)
    }

    func selectSourceLanguage(_ value: SourceLanguage) {
        guard value != sourceLanguage else { return }
        let shouldRetranslate = isBusy || result != nil || errorMessage != nil
        sourceLanguage = value
        if shouldRetranslate { beginTranslation() }
    }

    private(set) var direction: TranslationDirection {
        get {
            TranslationDirection(rawValue: UserDefaults.standard.string(forKey: "translationDirection") ?? "") ?? .automatic
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "translationDirection") }
    }

    func beginTranslation(text: String? = nil) {
        if text != nil { sourceLanguage = .automatic }
        let value = (text ?? inputText).trimmingCharacters(in: .whitespacesAndNewlines)
        let previousConfiguration = configuration
        cancel()
        inputText = value
        result = nil
        errorMessage = nil
        copied = false
        guard !value.isEmpty else { show(error: BenError.emptyText); return }
        guard value.count <= 5_000 else { show(error: BenError.textTooLong); return }
        let source = sourceLanguage.identifier ?? LanguageDetection.sourceLanguage(for: value)
        let target = direction.targetLanguage(for: source)
        if LanguageDetection.sameLanguage(source, target) {
            result = TranslationResult(
                originalText: value, translatedText: value, sourceLanguage: source ?? target,
                targetLanguage: target, providerID: TranslationProviderID.apple.rawValue
            )
            errorMessage = "原文已是目标语言。"
            return
        }
        request = TranslationRequest(text: value, sourceLanguage: source, targetLanguage: target)
        translationPhase = .checkingModels
        isBusy = true
        let next = TranslationSession.Configuration(
            source: source.map { Locale.Language(identifier: $0) },
            target: Locale.Language(identifier: target)
        )
        if var previousConfiguration, previousConfiguration.source == next.source, previousConfiguration.target == next.target {
            previousConfiguration.invalidate()
            configuration = previousConfiguration
        } else {
            configuration = next
        }
    }

    func performTranslation(using session: TranslationSession) async {
        guard let activeRequest = request else { return }
        // Prevent a task from an old language configuration from claiming a newer request.
        let configuredSource = activeRequest.sourceLanguage.map { Locale.Language(identifier: $0) }
        guard session.sourceLanguage == configuredSource,
              session.targetLanguage == Locale.Language(identifier: activeRequest.targetLanguage) else { return }
        do {
            let provider = AppleTranslationProvider(session: session) { [weak self] phase in
                guard let self, self.request?.id == activeRequest.id,
                      self.isBusy, !Task.isCancelled else { return }
                self.translationPhase = phase
            }
            let translated = try await provider.translate(activeRequest)
            guard request?.id == activeRequest.id, !Task.isCancelled else { return }
            result = translated
            errorMessage = nil
            isBusy = false
        } catch {
            guard request?.id == activeRequest.id else { return }
            isBusy = false
            if error is CancellationError || Task.isCancelled {
                errorMessage = "翻译已取消，可以重试。"
            } else {
                errorMessage = error.localizedDescription
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
        request = nil
        isBusy = false
        configuration = nil
    }

    func copyResult() {
        guard let result else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.translatedText, forType: .string)
        copied = true
    }
}
