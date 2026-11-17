import Foundation

@main
struct BaiduTranslationChecks {
    static func frame(_ body: [String: Any], errno: Int = 0) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["errno": errno, "data": body])
        return "event: message\r\ndata: " + String(decoding: data, as: UTF8.self) + "\r\n\r\n"
    }
    static func main() async throws {
        let request = TranslationRequest(text: "word", sourceLanguage: "en", targetLanguage: "zh-Hans", providerID: .baidu)
        let dictionary: [String: Any] = ["simple_means": ["word_name": "word", "symbols": [["ph_en": "wɜːd", "ph_am": "wɜrd", "parts": [["part": "n.", "means": ["词", ["word_mean": "单词"]]]]]], "exchange": ["word_pl": ["words"]], "tags": ["core": ["CET4", "CET4"], "other": ["高考"]]]]
        let stream = try [frame(["event": "StartTranslation", "from": "en"]),
                          frame(["event": "Translating", "list": [["paraIdx": 1, "dst": "第二行"], ["paraIdx": 0, "dst": "第一"]]]),
                          frame(["event": "Translating", "list": [["paraIdx": 0, "dst": "行"]]]),
                          frame(["event": "GetDictSucceed", "dictResult": dictionary]),
                          frame(["event": "Finished"])].joined()
        let result = try BaiduTranslationProvider.parse(Data(stream.utf8), request: request)
        precondition(result.translatedText == "第一行\n第二行")
        precondition(result.dictionary?.tags == ["CET4", "高考"])
        precondition(result.dictionary?.meanings.first?.definitions == ["词", "单词"])
        precondition(result.dictionary?.forms.first?.words == ["words"])
        for (body, expected) in [(try frame([:], errno: 995), "security"), (try frame(["event": "Translating", "list": [["dst": "x"]]]), "truncated"), ("data: broken\n\n", "malformed")] {
            do {
                _ = try BaiduTranslationProvider.parse(Data(body.utf8), request: request)
                fatalError("Expected error: \(expected)")
            } catch let error as TranslationServiceError {
                if expected == "security" { if case .baiduRejected = error {} else { fatalError() } }
                if expected == "truncated" { if case .incompleteResponse = error {} else { fatalError() } }
            }
        }
        let cancelled = Task { try await OnlineTranslationProvider().translate(request) }
        cancelled.cancel()
        do { _ = try await cancelled.value; fatalError("Cancellation not propagated") } catch is CancellationError {}
        print("SSE parsing, dictionary fields, errors and cancellation passed")
        if CommandLine.arguments.contains("--live") {
            let provider = OnlineTranslationProvider()
            let samples: [(String, String, String, Bool)] = [
                ("plate", "en", "zh-Hans", true),
                ("debug", "en", "zh-Hans", true),
                ("The small application stays in the menu bar.\nIt translates selected text.", "en", "zh-Hans", false),
                ("轻量的 macOS 翻译工具", "zh-Hans", "en", false)
            ]
            for (index, sample) in samples.enumerated() {
                let request = TranslationRequest(text: sample.0, sourceLanguage: sample.1, targetLanguage: sample.2, providerID: .baidu)
                let result = try await provider.translate(request)
                precondition(!result.translatedText.isEmpty && result.providerID == "baidu")
                if sample.3 { precondition(result.dictionary?.meanings.isEmpty == false) }
                let repeated = try await provider.translate(request)
                precondition(result.translatedText == repeated.translatedText)
                print("Live case \(index) passed; dictionary=\(result.dictionary != nil)")
            }
        }
    }
}
