import Combine
import Foundation
import SwiftUI
import Translation


enum TranslationError: Error {
    case unsupportedSystem
    case emptyText
    case timeout
    case invalidResponse
}

struct TranslationRequest {
    let id: UUID
    let source: Locale.Language?
    let target: Locale.Language
    let payload: TranslationRequestPayload
}

enum TranslationRequestPayload {
    case single(text: String, continuation: CheckedContinuation<String, Error>)
    case batch(texts: [String], continuation: CheckedContinuation<[String], Error>)
}

enum TranslationResponsePayload {
    case single(String)
    case batch([String])
}

@MainActor
final class TranslationBridge: ObservableObject {
    @Published private(set) var activeRequest: TranslationRequest?
    private var queuedRequests: [TranslationRequest] = []

    func translate(text: String, source: Locale.Language?, target: Locale.Language, timeout: TimeInterval = 10.0) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslationError.emptyText
        }
        try Task.checkCancellation()

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { continuation in
                    let request = TranslationRequest(
                        id: UUID(),
                        source: source,
                        target: target,
                        payload: .single(text: trimmed, continuation: continuation)
                    )
                    Task { @MainActor in
                        self.enqueue(request)
                    }
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw TranslationError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    func translateBatch(
        texts: [String],
        source: Locale.Language?,
        target: Locale.Language,
        timeout: TimeInterval = 10.0
    ) async throws -> [String] {
        let trimmedTexts = texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmedTexts.isEmpty else {
            throw TranslationError.emptyText
        }
        try Task.checkCancellation()

        return try await withThrowingTaskGroup(of: [String].self) { group in
            group.addTask {
                try Task.checkCancellation()
                return try await withCheckedThrowingContinuation { continuation in
                    let request = TranslationRequest(
                        id: UUID(),
                        source: source,
                        target: target,
                        payload: .batch(texts: trimmedTexts, continuation: continuation)
                    )
                    Task { @MainActor in
                        self.enqueue(request)
                    }
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw TranslationError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    func finishActiveRequest(id: UUID, result: Result<TranslationResponsePayload, Error>) {
        guard activeRequest?.id == id else { return }

        if let activeRequest {
            switch (activeRequest.payload, result) {
            case (.single(_, let continuation), .success(.single(let translatedText))):
                continuation.resume(returning: translatedText)
            case (.batch(_, let continuation), .success(.batch(let translatedTexts))):
                continuation.resume(returning: translatedTexts)
            case (.single(_, let continuation), .failure(let error)):
                continuation.resume(throwing: error)
            case (.batch(_, let continuation), .failure(let error)):
                continuation.resume(throwing: error)
            case (.single(_, let continuation), .success(.batch)):
                continuation.resume(throwing: TranslationError.invalidResponse)
            case (.batch(_, let continuation), .success(.single)):
                continuation.resume(throwing: TranslationError.invalidResponse)
            }
        }

        activeRequest = nil
        promoteNextRequestIfNeeded()
    }

    func cancelAllPendingRequests(with error: Error = CancellationError()) {
        if let activeRequest {
            switch activeRequest.payload {
            case .single(_, let continuation):
                continuation.resume(throwing: error)
            case .batch(_, let continuation):
                continuation.resume(throwing: error)
            }
            self.activeRequest = nil
        }

        for request in queuedRequests {
            switch request.payload {
            case .single(_, let continuation):
                continuation.resume(throwing: error)
            case .batch(_, let continuation):
                continuation.resume(throwing: error)
            }
        }
        queuedRequests.removeAll()
    }

    private func enqueue(_ request: TranslationRequest) {
        queuedRequests.append(request)
        promoteNextRequestIfNeeded()
    }

    private func promoteNextRequestIfNeeded() {
        guard activeRequest == nil, !queuedRequests.isEmpty else { return }
        activeRequest = queuedRequests.removeFirst()
    }
}

@available(macOS 15.0, *)
struct TranslationBridgeView: View {
    @ObservedObject var bridge: TranslationBridge
    @State private var configuration: TranslationSession.Configuration?
    @State private var configurationID = UUID()

    init(bridge: TranslationBridge) {
        self.bridge = bridge
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                syncConfiguration(for: bridge.activeRequest)
            }
            .onChange(of: bridge.activeRequest?.id) { _, _ in
                syncConfiguration(for: bridge.activeRequest)
            }
            .translationTask(configuration) { session in
                guard let request = bridge.activeRequest else {
                    return
                }

                do {
                    switch request.payload {
                    case .single(let text, _):
                        let response = try await session.translate(text)
                        bridge.finishActiveRequest(id: request.id, result: .success(.single(response.targetText)))
                    case .batch(let texts, _):
                        let batch = texts.enumerated().map { index, text in
                            TranslationSession.Request(
                                sourceText: text,
                                clientIdentifier: String(index)
                            )
                        }
                        let responses = try await session.translations(from: batch)
                        let sortedResponses = responses.sorted { lhs, rhs in
                            let lhsIndex = Int(lhs.clientIdentifier ?? "") ?? Int.max
                            let rhsIndex = Int(rhs.clientIdentifier ?? "") ?? Int.max
                            return lhsIndex < rhsIndex
                        }
                        let translatedTexts = sortedResponses.map(\.targetText)

                        guard translatedTexts.count == texts.count else {
                            throw TranslationError.invalidResponse
                        }

                        bridge.finishActiveRequest(id: request.id, result: .success(.batch(translatedTexts)))
                    }
                } catch {
                    bridge.finishActiveRequest(id: request.id, result: .failure(error))
                }
            }
            .id(configurationID)
    }

    private func syncConfiguration(for request: TranslationRequest?) {
        guard let request else {
            configuration = nil
            return
        }

        configurationID = request.id
        configuration = TranslationSession.Configuration(
            source: request.source,
            target: request.target
        )
    }
}
