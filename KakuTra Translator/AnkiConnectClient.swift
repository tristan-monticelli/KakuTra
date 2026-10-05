import Foundation

struct AnkiConnectConfiguration: Equatable, Sendable {
    let version: Int
    let deckNames: [String]
    let modelNames: [String]
}

struct AnkiNoteDraft: Equatable, Sendable {
    let deckName: String
    let modelName: String
    let fields: [String: String]
    let tags: [String]

    init(deckName: String, modelName: String, fields: [String: String], tags: [String] = []) {
        self.deckName = deckName
        self.modelName = modelName
        self.fields = fields
        self.tags = tags
    }
}

enum AnkiFieldRole: String, CaseIterable, Identifiable {
    case term
    case reading
    case definition
    case context
    case source

    var id: String { rawValue }
    var title: String {
        switch self {
        case .term: return L("Japanese term")
        case .reading: return L("Reading")
        case .definition: return L("Definition")
        case .context: return L("Example or context")
        case .source: return L("Dictionary source")
        }
    }

    var isRequired: Bool { self == .term || self == .definition }
}

enum AnkiConnectionState: Equatable {
    case checking
    case connected(version: Int)
    case notConnected
    case failed(String)
}

enum AnkiConnectError: Error, LocalizedError, Equatable {
    case unavailable(String)
    case invalidResponse
    case api(String)
    case requestTooLarge
    case responseTooLarge

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .invalidResponse: return L("AnkiConnect returned an invalid response.")
        case .api(let message): return message
        case .requestTooLarge: return L("The AnkiConnect request is too large.")
        case .responseTooLarge: return L("AnkiConnect returned too much data.")
        }
    }
}

private struct AnkiEnvelope<ResultType: Decodable>: Decodable {
    let result: ResultType?
    let error: String?
}

/// Loopback-only client for local AnkiConnect (127.0.0.1:8765).
final class AnkiConnectClient: Sendable {
    static let baseURL = URL(string: "http://127.0.0.1:8765")!
    private static let apiVersion = 6
    private static let allowedActions: Set<String> = [
        "version",
        "deckNames",
        "modelNames",
        "modelFieldNames",
        "canAddNotes",
        "addNote"
    ]
    private static let maximumRequestBytes = 64 * 1024
    private static let maximumResponseBytes = 1024 * 1024

    private let session: URLSession
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 3) {
        session = URLSession(configuration: .ephemeral, delegate: AnkiNoRedirectDelegate(), delegateQueue: nil)
        self.timeout = timeout
    }

    func configuration() async throws -> AnkiConnectConfiguration {
        async let version = apiVersionNumber()
        async let decks = deckNames()
        async let models = modelNames()
        let apiVersion = try await version
        guard apiVersion >= Self.apiVersion else {
            throw AnkiConnectError.api(L("AnkiConnect API version 6 or later is required."))
        }
        return try await AnkiConnectConfiguration(version: apiVersion, deckNames: decks, modelNames: models)
    }

    func apiVersionNumber() async throws -> Int {
        try await result(action: "version", resultType: Int.self)
    }

    func deckNames() async throws -> [String] {
        try await result(action: "deckNames", resultType: [String].self)
    }

    func modelNames() async throws -> [String] {
        try await result(action: "modelNames", resultType: [String].self)
    }

    func modelFieldNames(modelName: String) async throws -> [String] {
        try await result(
            action: "modelFieldNames",
            params: ["modelName": modelName],
            resultType: [String].self
        )
    }

    func canAddNotes(_ notes: [AnkiNoteDraft]) async throws -> [Bool] {
        guard !notes.isEmpty else { return [] }
        let notesPayload = notes.map { draft in
            [
                "deckName": draft.deckName,
                "modelName": draft.modelName,
                "fields": draft.fields,
                "tags": draft.tags
            ] as [String: Any]
        }
        return try await result(
            action: "canAddNotes",
            params: ["notes": notesPayload],
            resultType: [Bool].self
        )
    }

    func addNote(_ note: AnkiNoteDraft) async throws -> Int64 {
        let notePayload: [String: Any] = [
            "deckName": note.deckName,
            "modelName": note.modelName,
            "fields": note.fields,
            "options": [
                "allowDuplicate": false,
                "duplicateScope": "deck"
            ],
            "tags": note.tags
        ]
        return try await result(
            action: "addNote",
            params: ["note": notePayload],
            resultType: Int64.self
        )
    }

    static func buildPayload(action: String, params: [String: Any]? = nil) throws -> Data {
        guard allowedActions.contains(action) else {
            throw AnkiConnectError.invalidResponse
        }
        var payload: [String: Any] = ["action": action, "version": apiVersion]
        if let params = params, !params.isEmpty {
            payload["params"] = params
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard data.count <= maximumRequestBytes else {
            throw AnkiConnectError.requestTooLarge
        }
        return data
    }

    static func decodeResponse<Value: Decodable>(_ data: Data, as type: Value.Type) throws -> Value {
        guard data.count <= maximumResponseBytes else {
            throw AnkiConnectError.responseTooLarge
        }
        let envelope: AnkiEnvelope<Value>
        do {
            envelope = try JSONDecoder().decode(AnkiEnvelope<Value>.self, from: data)
        } catch {
            throw AnkiConnectError.invalidResponse
        }
        if let apiError = envelope.error, !apiError.isEmpty {
            throw AnkiConnectError.api(apiError)
        }
        guard let result = envelope.result else {
            throw AnkiConnectError.invalidResponse
        }
        return result
    }

    private func result<Value: Decodable>(
        action: String,
        params: [String: Any]? = nil,
        resultType: Value.Type
    ) async throws -> Value {
        let body: Data
        do {
            body = try Self.buildPayload(action: action, params: params)
        } catch let error as AnkiConnectError {
            throw error
        } catch {
            throw AnkiConnectError.invalidResponse
        }

        var request = URLRequest(url: Self.baseURL, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body

        do {
            let (bytes, response) = try await session.bytes(for: request)
            try Task.checkCancellation()
            guard response.url?.scheme == "http",
                  response.url?.host == "127.0.0.1",
                  response.url?.port == 8765,
                  let httpResponse = response as? HTTPURLResponse else {
                throw AnkiConnectError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw AnkiConnectError.api("AnkiConnect returned HTTP \(httpResponse.statusCode).")
            }
            if httpResponse.expectedContentLength > Int64(Self.maximumResponseBytes) {
                throw AnkiConnectError.responseTooLarge
            }
            let length = httpResponse.expectedContentLength
            var data = Data()
            data.reserveCapacity(length >= 0 ? min(Int(length), Self.maximumResponseBytes) : 0)
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < Self.maximumResponseBytes else { throw AnkiConnectError.responseTooLarge }
                data.append(byte)
            }

            return try Self.decodeResponse(data, as: Value.self)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AnkiConnectError {
            throw error
        } catch {
            throw AnkiConnectError.unavailable(error.localizedDescription)
        }
    }
}

private final class AnkiNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
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
