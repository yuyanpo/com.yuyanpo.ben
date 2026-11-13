import AVFoundation
import Combine
import Foundation

enum TranslationTextSection: Sendable {
    case original, translation
}

/// Uses macOS speech voices; never sends text to a translation service.
@MainActor
final class TextSpeechController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var speakingSection: TranslationTextSection?
    private var synthesizer: AVSpeechSynthesizer?
    private var utteranceID: ObjectIdentifier?

    func toggle(text: String, language: String?, section: TranslationTextSection) {
        if speakingSection == section {
            stop()
            return
        }
        stop()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if synthesizer == nil {
            synthesizer = AVSpeechSynthesizer()
            synthesizer?.delegate = self
        }
        let utterance = AVSpeechUtterance(string: text)
        if let language, language != "auto" {
            let identifier: String
            switch language {
            case "zh", "zh-Hans": identifier = "zh-CN"
            case "zh-Hant": identifier = "zh-TW"
            case "en": identifier = "en-US"
            default: identifier = language
            }
            utterance.voice = AVSpeechSynthesisVoice(language: identifier)
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utteranceID = ObjectIdentifier(utterance)
        speakingSection = section
        synthesizer?.speak(utterance)
    }

    func stop() {
        utteranceID = nil
        speakingSection = nil
        synthesizer?.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }

    private nonisolated func finished(_ id: ObjectIdentifier) {
        Task { @MainActor [weak self] in
            guard let self, self.utteranceID == id else { return }
            self.utteranceID = nil
            self.speakingSection = nil
        }
    }
}
