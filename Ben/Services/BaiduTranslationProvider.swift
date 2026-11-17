import Foundation

/// Baidu's anonymous session is kept separately from the other providers, in memory only.
actor BaiduTranslationProvider: TranslationProvider {
    private let session: URLSession
    private var cookies: [HTTPCookie] = []
    private static let page = URL(string: "https://fanyi.baidu.com/mtpe-individual/transText")!
    private static let endpoint = URL(string: "https://fanyi.baidu.com/ait/text/translate")!

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 35
            self.session = URLSession(configuration: configuration)
        }
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let from = try Self.language(request.sourceLanguage)
        let to = try Self.language(request.targetLanguage)
        // Bound bootstrap and translation together. No automatic replay on a security rejection.
        return try await withThrowingTaskGroup(of: TranslationResult.self) { group in
            group.addTask { try await self.perform(request, from: from, to: to) }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                throw TranslationServiceError.timedOut
            }
            defer { group.cancelAll() }
            do {
                return try await group.next()!
            } catch {
                if error is CancellationError || Task.isCancelled || (error as? URLError)?.code == .cancelled {
                    throw CancellationError()
                }
                if let error = error as? TranslationServiceError { throw error }
                if (error as? URLError)?.code == .timedOut { throw TranslationServiceError.timedOut }
                throw TranslationServiceError.networkUnavailable
            }
        }
    }

    private func perform(_ translation: TranslationRequest, from: String, to: String) async throws -> TranslationResult {
        try Task.checkCancellation()
        cookies.removeAll { ($0.expiresDate ?? .distantFuture) <= Date() }
        if !cookies.contains(where: { $0.name == "BAIDUID" }) {
            try await bootstrap()
        }
        try Task.checkCancellation()
        let baiduid = cookies.first(where: { $0.name == "BAIDUID" })?.value ?? ""
        guard !baiduid.isEmpty else { throw TranslationServiceError.baiduRejected }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("https://fanyi.baidu.com", forHTTPHeaderField: "Origin")
        request.setValue(Self.page.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(BaiduRequestToken.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(HTTPCookie.requestHeaderFields(with: cookies)["Cookie"], forHTTPHeaderField: "Cookie")
        request.setValue(try BaiduRequestToken.make(baiduid: baiduid), forHTTPHeaderField: "Acs-Token")
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": translation.text, "from": from, "to": to, "domain": "common",
            "reference": "", "corpusIds": [], "needPhonetic": true,
            "needNewlineCombine": false, "disableCache": false, "isAi": false,
            "isIncognitoAI": false, "detectLang": "", "sseStartTime": now, "milliTimestamp": now,
        ] as [String: Any])
        let data = try await OnlineTranslationProvider.download(request, session: session)
        try Task.checkCancellation()
        return try Self.parse(data, request: translation)
    }

    private func bootstrap() async throws {
        var request = URLRequest(url: Self.page, timeoutInterval: 8)
        request.setValue(BaiduRequestToken.userAgent, forHTTPHeaderField: "User-Agent")
        // Only headers are needed; cancel the body stream instead of loading the web page.
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw TranslationServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw TranslationServiceError.http(http.statusCode, retryAfter: nil)
        }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, item in
            if let name = item.key as? String { result[name] = String(describing: item.value) }
        }
        cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: Self.page)
            .filter { $0.domain == "fanyi.baidu.com" || $0.domain == ".baidu.com" || $0.domain == "baidu.com" }
    }

    static func language(_ code: String?) throws -> String {
        guard let code, code != "auto" else { return "auto" }
        switch code {
        case "zh", "zh-Hans", "zh-CN": return "zh"
        case "zh-Hant", "zh-TW": return "cht"
        case "en": return "en"
        case "ja": return "jp"
        case "ko": return "kor"
        case "fr": return "fra"
        case "es": return "spa"
        case "ar": return "ara"
        case "de", "nl", "tr", "ru", "pt", "it", "th", "vi": return code
        default: throw TranslationServiceError.unsupportedLanguage
        }
    }

    private static func nativeLanguage(_ code: String) -> String {
        switch code {
        case "zh": "zh-Hans"
        case "cht": "zh-Hant"
        case "jp": "ja"
        case "kor": "ko"
        case "fra": "fr"
        case "spa": "es"
        case "ara": "ar"
        default: code
        }
    }

    static func parse(_ data: Data, request: TranslationRequest) throws -> TranslationResult {
        let text = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var objects: [[String: Any]] = []
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            objects = [object]
        } else {
            for frame in text.components(separatedBy: "\n\n") {
                let lines = frame.components(separatedBy: "\n").compactMap { line -> String? in
                    guard line.hasPrefix("data:") else { return nil }
                    let value = String(line.dropFirst(5))
                    return value.hasPrefix(" ") ? String(value.dropFirst()) : value
                }
                guard !lines.isEmpty else { continue }
                guard let object = try? JSONSerialization.jsonObject(with: Data(lines.joined(separator: "\n").utf8)) as? [String: Any] else {
                    throw TranslationServiceError.invalidResponse
                }
                objects.append(object)
            }
        }
        var paragraphs: [Int: String] = [:]
        var dictionary: DictionaryEntry?
        var source = request.sourceLanguage ?? "auto"
        var finished = false
        for object in objects {
            guard let errno = object["errno"] as? Int else { throw TranslationServiceError.invalidResponse }
            if errno != 0 {
                if errno == 995 { throw TranslationServiceError.baiduRejected }
                throw TranslationServiceError.invalidResponse
            }
            guard let body = object["data"] as? [String: Any], let event = body["event"] as? String else { continue }
            switch event {
            case "StartTranslation":
                if let from = body["from"] as? String { source = nativeLanguage(from) }
            case "Translating":
                guard let list = body["list"] as? [[String: Any]] else { throw TranslationServiceError.invalidResponse }
                for segment in list {
                    guard let value = segment["dst"] as? String else { continue }
                    let index = segment["paraIdx"] as? Int ?? paragraphs.count
                    paragraphs[index, default: ""] += value
                }
            case "GetDictSucceed":
                if let value = body["dictResult"] as? [String: Any] { dictionary = parseDictionary(value) }
            case "Finished": finished = true
            default: break
            }
        }
        guard finished else { throw TranslationServiceError.incompleteResponse }
        let translated = paragraphs.keys.sorted().compactMap { paragraphs[$0] }.joined(separator: "\n")
        guard !translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationServiceError.invalidResponse
        }
        return TranslationResult(originalText: request.text, translatedText: translated, sourceLanguage: source,
                                 targetLanguage: request.targetLanguage, providerID: request.providerID.rawValue,
                                 dictionary: dictionary)
    }

    private static func parseDictionary(_ value: [String: Any]) -> DictionaryEntry? {
        guard let simple = value["simple_means"] as? [String: Any],
              let word = simple["word_name"] as? String, !word.isEmpty,
              let symbols = simple["symbols"] as? [[String: Any]] else { return nil }
        var meanings: [DictionaryEntry.Meaning] = []
        for symbol in symbols.prefix(4) {
            for part in (symbol["parts"] as? [[String: Any]] ?? []).prefix(16) {
                let definitions = (part["means"] as? [Any] ?? []).prefix(32).compactMap { value -> String? in
                    if let text = value as? String { return text }
                    return (value as? [String: Any])?["word_mean"] as? String
                }.filter { !$0.isEmpty }
                if !definitions.isEmpty {
                    meanings.append(.init(partOfSpeech: part["part"] as? String ?? part["part_name"] as? String ?? "",
                                          definitions: definitions))
                }
            }
        }
        guard !meanings.isEmpty else { return nil }
        let exchange = simple["exchange"] as? [String: Any] ?? [:]
        let labels = [("word_pl", "复数"), ("word_third", "第三人称单数"), ("word_ing", "现在分词"),
                      ("word_past", "过去式"), ("word_done", "过去分词"), ("word_er", "比较级"), ("word_est", "最高级")]
        let forms = labels.compactMap { key, label -> DictionaryEntry.WordForm? in
            let words = (exchange[key] as? [String] ?? []).filter { !$0.isEmpty }
            return words.isEmpty ? nil : .init(label: label, words: Array(words.prefix(8)))
        }
        let tags = simple["tags"] as? [String: Any] ?? [:]
        let names = (tags["core"] as? [String] ?? []) + (tags["other"] as? [String] ?? [])
        var unique = Set<String>()
        return DictionaryEntry(word: word,
                               britishPhonetic: symbols.compactMap { $0["ph_en"] as? String }.first(where: { !$0.isEmpty }),
                               americanPhonetic: symbols.compactMap { $0["ph_am"] as? String }.first(where: { !$0.isEmpty }),
                               meanings: meanings, forms: forms,
                               tags: Array(names.filter { !$0.isEmpty && unique.insert($0).inserted }.prefix(16)))
    }
}
