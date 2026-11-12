import Foundation
// Apple's Swift 5 Translation interface does not annotate session transfer; the view task owns it.
@preconcurrency import Translation

enum TranslationProviderID: String, CaseIterable, Identifiable, Sendable {
    case apple, thirdParty, largeLanguageModel
    var id: String { rawValue }
    var title: String {
        switch self {
        case .apple: "macOS 系统翻译"
        case .thirdParty: "第三方翻译 API"
        case .largeLanguageModel: "大模型翻译"
        }
    }
}

struct TranslationProviderDescriptor: Sendable {
    let id: TranslationProviderID
    let runsOnDevice: Bool
    let isAvailable: Bool
    let supportsStreaming: Bool
}

/// Providers do not own UI state. Apple's session is supplied by the active SwiftUI task.
@MainActor
protocol TranslationProvider {
    var descriptor: TranslationProviderDescriptor { get }
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
}

@MainActor
struct AppleTranslationProvider: TranslationProvider {
    let session: TranslationSession
    var updatePhase: (TranslationPhase) -> Void = { _ in }
    let descriptor = TranslationProviderDescriptor(
        id: .apple, runsOnDevice: true, isAvailable: true, supportsStreaming: false
    )

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let availability = LanguageAvailability()
        let target = Locale.Language(identifier: request.targetLanguage)
        let status: LanguageAvailability.Status
        if let source = request.sourceLanguage {
            status = await availability.status(from: Locale.Language(identifier: source), to: target)
        } else {
            status = try await availability.status(for: request.text, to: target)
        }
        guard status != .unsupported else { throw BenError.unsupportedPair }
        try Task.checkCancellation()
        if status == .supported {
            updatePhase(.preparingModels)
            // Ask the system to prepare only when this pair isn't installed.
            // This may show download consent; no download progress is available.
            try await session.prepareTranslation()
            try Task.checkCancellation()
        }
        updatePhase(.translating)
        let response = try await session.translate(request.text)
        try Task.checkCancellation()
        return TranslationResult(
            originalText: response.sourceText,
            translatedText: response.targetText,
            sourceLanguage: response.sourceLanguage.minimalIdentifier,
            targetLanguage: response.targetLanguage.minimalIdentifier,
            providerID: descriptor.id.rawValue
        )
    }
}

/// Extension points only: no network calls or fake translations in the initial project.
@MainActor
struct ThirdPartyTranslationProvider: TranslationProvider {
    let descriptor = TranslationProviderDescriptor(
        id: .thirdParty, runsOnDevice: false, isAvailable: false, supportsStreaming: false
    )
    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        throw BenError.providerNotConfigured(descriptor.id.title)
    }
}

@MainActor
struct LargeLanguageModelProvider: TranslationProvider {
    let descriptor = TranslationProviderDescriptor(
        id: .largeLanguageModel, runsOnDevice: false, isAvailable: false, supportsStreaming: true
    )
    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        throw BenError.providerNotConfigured(descriptor.id.title)
    }
}
