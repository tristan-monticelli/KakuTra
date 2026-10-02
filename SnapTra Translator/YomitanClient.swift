import Foundation

struct YomitanTermResult: Equatable, Identifiable, Sendable {
    let term: String
    let reading: String?
    let dictionary: String
    let glosses: [String]

    var id: String { "\(dictionary)|\(term)|\(reading ?? "")|\(glosses.joined(separator: "\u{1f}"))" }
}

struct YomitanToken: Equatable, Sendable {
    let text: String
    let reading: String?
    let entries: [YomitanTermResult]
}

struct YomitanStatus: Equatable, Sendable {
    let serverVersion: Int
    let extensionVersion: String?
}

enum YomitanClientError: Error, LocalizedError, Equatable {
    case invalidJapaneseText
    case requestTooLarge
    case responseTooLarge
    case invalidResponse
    case httpStatus(Int)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidJapaneseText: return "Enter Japanese text to search in Yomitan."
        case .requestTooLarge: return "The Yomitan request is too large."
        case .responseTooLarge: return "Yomitan returned too much data."
        case .invalidResponse: return "Yomitan returned an invalid response."
        case .httpStatus(let status): return "Yomitan returned HTTP \(status)."
        case .unavailable(let message): return message
        }
    }
}

/// Small, loopback-only adapter for https://github.com/yomidevs/yomitan-api.
/// The API's structured dictionary content is treated as untrusted data and reduced to plain text.
final class YomitanClient: Sendable {
    static let baseURL = URL(string: "http://127.0.0.1:19633")!
    static let maximumRequestBytes = 256 * 1024
    static let maximumResponseBytes = 8 * 1024 * 1024

    private let session: URLSession
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 3) {
        self.session = URLSession(
            configuration: .ephemeral,
            delegate: NoRedirectDelegate(),
            delegateQueue: nil
        )
        self.timeout = timeout
    }

    func status() async throws -> YomitanStatus {
        let serverData = try await post(path: "serverVersion", body: EmptyRequest())
        let serverObject = try jsonObject(serverData)
        guard let serverVersion = serverObject["version"] as? Int else {
            throw YomitanClientError.invalidResponse
        }
        guard serverVersion == 1 else {
            throw YomitanClientError.unavailable("Unsupported Yomitan API server version \(serverVersion).")
        }

        let extensionVersion: String?
        do {
            let data = try await post(path: "yomitanVersion", body: EmptyRequest())
            let value = try Self.jsonValue(data)
            if let object = value as? [String: Any] {
                extensionVersion = (object["version"] as? String) ?? (object["version"] as? NSNumber)?.stringValue
            } else {
                extensionVersion = value as? String
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Some compatible API versions do not expose the extension version.
            extensionVersion = nil
        }

        return YomitanStatus(serverVersion: serverVersion, extensionVersion: extensionVersion)
    }

    func lookup(term: String) async throws -> [YomitanTermResult] {
        let query = japaneseOnlyText(term, maximumScalars: 64)
        guard !query.isEmpty else { throw YomitanClientError.invalidJapaneseText }
        let data = try await post(path: "termEntries", body: TermRequest(term: query))
        return try Self.decodeTermEntries(data)
    }

    func tokenizeJapaneseText(_ text: String, scanLength: Int = 10) async throws -> [YomitanToken] {
        let query = japaneseOnlyText(text, maximumScalars: 256)
        guard !query.isEmpty else { throw YomitanClientError.invalidJapaneseText }
        let data = try await post(
            path: "tokenize",
            body: TokenizeRequest(text: query, scanLength: min(max(scanLength, 1), 16), parser: "scanning-parser")
        )
        let segments = try Self.decodeTokens(data)
        var seenTerms = Set<String>()
        let uniqueTerms = segments.map(\.text).filter { !$0.isEmpty && seenTerms.insert($0).inserted }.prefix(32)
        guard !uniqueTerms.isEmpty else { return [] }
        let termsData = try await post(path: "termEntries", body: TermRequest(term: Array(uniqueTerms)))
        let groupedResults = try Self.decodeTermEntriesByIndex(termsData, expectedCount: uniqueTerms.count)
        let entriesByTerm = Dictionary(uniqueKeysWithValues: zip(uniqueTerms, groupedResults))
        return segments.map { segment in
            YomitanToken(
                text: segment.text,
                reading: segment.reading,
                entries: entriesByTerm[segment.text] ?? segment.entries
            )
        }
    }

    private func post<Body: Encodable>(path: String, body: Body) async throws -> Data {
        guard ["serverVersion", "yomitanVersion", "termEntries", "tokenize"].contains(path) else {
            throw YomitanClientError.invalidResponse
        }
        let bodyData = try JSONEncoder().encode(body)
        guard bodyData.count <= Self.maximumRequestBytes else { throw YomitanClientError.requestTooLarge }
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = bodyData

        do {
            let (bytes, response) = try await session.bytes(for: request)
            try Task.checkCancellation()
            guard response.url?.scheme == "http",
                  response.url?.host == "127.0.0.1",
                  response.url?.port == 19633,
                  let httpResponse = response as? HTTPURLResponse else {
                throw YomitanClientError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw YomitanClientError.httpStatus(httpResponse.statusCode)
            }
            if httpResponse.expectedContentLength > Int64(Self.maximumResponseBytes) {
                throw YomitanClientError.responseTooLarge
            }
            var data = Data()
            let expectedLength = httpResponse.expectedContentLength
            let initialCapacity = expectedLength >= 0 ? min(Int(expectedLength), Self.maximumResponseBytes) : 0
            data.reserveCapacity(initialCapacity)
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < Self.maximumResponseBytes else {
                    throw YomitanClientError.responseTooLarge
                }
                data.append(byte)
            }
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as YomitanClientError {
            throw error
        } catch {
            throw YomitanClientError.unavailable(error.localizedDescription)
        }
    }

    private func japaneseOnlyText(_ text: String, maximumScalars: Int) -> String {
        let scalars = text.unicodeScalars.filter { scalar in
            let value = scalar.value
            return (0x3040...0x30FF).contains(value)
                || (0x3400...0x4DBF).contains(value)
                || (0x4E00...0x9FFF).contains(value)
                || (0x20000...0x323AF).contains(value)
                || (0xF900...0xFAFF).contains(value)
                || (0xFF66...0xFF9D).contains(value)
        }
        return String(String.UnicodeScalarView(scalars.prefix(maximumScalars)))
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try Self.jsonValue(data) as? [String: Any] else {
            throw YomitanClientError.invalidResponse
        }
        return object
    }

    static func decodeTermEntries(_ data: Data) throws -> [YomitanTermResult] {
        let objects = try responseObjects(data)
        return objects.flatMap { decodeResults(in: $0) }
    }

    private static func decodeTermEntriesByIndex(_ data: Data, expectedCount: Int) throws -> [[YomitanTermResult]] {
        let objects = try responseObjects(data)
        if expectedCount == 1, let object = objects.first, object["index"] == nil {
            return [decodeResults(in: object)]
        }
        var results = Array(repeating: [YomitanTermResult](), count: expectedCount)
        for object in objects {
            guard let index = object["index"] as? Int, results.indices.contains(index) else { continue }
            results[index] = decodeResults(in: object)
        }
        return results
    }

    private static func decodeResults(in object: [String: Any]) -> [YomitanTermResult] {
        guard let dictionaryEntries = object["dictionaryEntries"] as? [[String: Any]] else { return [] }
        return dictionaryEntries.flatMap { dictionaryEntry -> [YomitanTermResult] in
            let definitions = dictionaryEntry["definitions"] as? [[String: Any]] ?? []
            return definitions.flatMap { definition -> [YomitanTermResult] in
                let dictionary = (definition["dictionaryAlias"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? (definition["dictionary"] as? String)
                    ?? (dictionaryEntry["dictionaryAlias"] as? String)
                    ?? "Yomitan"
                let glosses = (definition["entries"] as? [[String: Any]] ?? []).flatMap { entry in
                    extractGlosses(entry["content"])
                }.filter { !$0.isEmpty }
                let headwords = dictionaryEntry["headwords"] as? [[String: Any]] ?? []
                return headwords.compactMap { headword in
                    guard let term = headword["term"] as? String, !term.isEmpty else { return nil }
                    return YomitanTermResult(
                        term: term,
                        reading: (headword["reading"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                        dictionary: dictionary,
                        glosses: glosses
                    )
                }
            }
        }
    }

    private static func extractGlosses(_ value: Any?) -> [String] {
        guard let value else { return [] }
        if let text = value as? String { return [text.trimmingCharacters(in: .whitespacesAndNewlines)] }
        if let values = value as? [Any] { return values.flatMap(extractGlosses) }
        guard let object = value as? [String: Any] else { return [] }
        let data = object["data"] as? [String: Any]
        if data?["content"] as? String == "glossary", let content = object["content"] {
            if let items = content as? [Any] {
                let glosses = items.compactMap { item -> String? in
                    guard let item = item as? [String: Any], item["tag"] as? String == "li" else { return nil }
                    let text = flattenText(item["content"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return text.isEmpty ? nil : text
                }
                if !glosses.isEmpty { return glosses }
            }
            return flattenText(content).split(whereSeparator: \.isNewline).map(String.init)
        }
        return extractGlosses(object["content"])
    }

    private static func flattenText(_ value: Any) -> String {
        if let text = value as? String { return text }
        if let values = value as? [Any] { return values.map(flattenText).joined(separator: " ") }
        guard let object = value as? [String: Any] else { return "" }
        guard let content = object["content"] else { return "" }
        return flattenText(content)
    }

    private static func decodeTokens(_ data: Data) throws -> [ParsedSegment] {
        guard let results = try jsonValue(data) as? [[String: Any]] else {
            throw YomitanClientError.invalidResponse
        }
        return results.flatMap { result -> [ParsedSegment] in
            guard let groups = result["content"] as? [[Any]] else { return [] }
            return groups.compactMap { group in
                guard let first = group.first as? [String: Any], let text = first["text"] as? String else { return nil }
                let headwordGroups = first["headwords"] as? [[[String: Any]]] ?? []
                let entries = headwordGroups.flatMap { words in
                    words.compactMap { word -> YomitanTermResult? in
                        guard let term = word["term"] as? String else { return nil }
                        let dictionary = (word["sources"] as? [[String: Any]])?.compactMap { $0["dictionary"] as? String }.first ?? "Yomitan"
                        return YomitanTermResult(term: term, reading: word["reading"] as? String, dictionary: dictionary, glosses: [])
                    }
                }
                return ParsedSegment(text: text, reading: first["reading"] as? String, entries: entries)
            }
        }
    }

    private static func responseObjects(_ data: Data) throws -> [[String: Any]] {
        let value = try jsonValue(data)
        if let object = value as? [String: Any] { return [object] }
        if let objects = value as? [[String: Any]] { return objects }
        throw YomitanClientError.invalidResponse
    }

    private static func jsonValue(_ data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw YomitanClientError.invalidResponse
        }
    }

    private struct ParsedSegment {
        let text: String
        let reading: String?
        let entries: [YomitanTermResult]
        var hasEntries: Bool { !entries.isEmpty }
    }

    private struct EmptyRequest: Encodable {}
    private struct TermRequest: Encodable {
        let term: TermValue
        init(term: String) { self.term = .one(term) }
        init(term: [String]) { self.term = .many(term) }
    }
    private enum TermValue: Encodable {
        case one(String)
        case many([String])
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .one(let value): try container.encode(value)
            case .many(let values): try container.encode(values)
            }
        }
    }
    private struct TokenizeRequest: Encodable {
        let text: String
        let scanLength: Int
        let parser: String
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
