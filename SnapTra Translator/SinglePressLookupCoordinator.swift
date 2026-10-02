import CoreGraphics
import Foundation

nonisolated struct SinglePressLookupRequest: Equatable, Sendable {
    let lookupID: UUID
    let mouseLocation: CGPoint
    let supportsSelectedText: Bool
    let selectedTextEnabled: Bool
    let hasAccessibilityPermission: Bool
    let selectedTextProbeRequest: SelectedTextProbeRequest?

    init(
        lookupID: UUID,
        mouseLocation: CGPoint,
        supportsSelectedText: Bool,
        selectedTextEnabled: Bool,
        hasAccessibilityPermission: Bool,
        selectedTextProbeRequest: SelectedTextProbeRequest? = nil
    ) {
        self.lookupID = lookupID
        self.mouseLocation = mouseLocation
        self.supportsSelectedText = supportsSelectedText
        self.selectedTextEnabled = selectedTextEnabled
        self.hasAccessibilityPermission = hasAccessibilityPermission
        self.selectedTextProbeRequest = selectedTextProbeRequest
    }

    var executionPolicy: SinglePressLookupExecutionPolicy {
        guard supportsSelectedText,
              selectedTextEnabled,
              hasAccessibilityPermission else {
            return .ocrOnly
        }

        return .selectionFirst
    }
}

nonisolated enum SinglePressLookupExecutionPolicy: Equatable, Sendable {
    case ocrOnly
    case selectionFirst
}

nonisolated struct SinglePressLookupResolution: Sendable {
    let intent: SinglePressLookupIntent
}

nonisolated enum SinglePressLookupDecision<Candidate: Sendable>: Sendable {
    case selectedText(SelectedTextSnapshot)
    case ocr(Candidate)
    case cancelled
}

nonisolated enum SinglePressLookupResolvedRoute: Equatable, Sendable {
    case selectedText
    case ocr
}

nonisolated enum SinglePressLookupCoordinator {
    @MainActor
    static func resolve<Candidate: Sendable>(
        request: SinglePressLookupRequest,
        accessibilityProbe: @escaping @MainActor @Sendable (
            SinglePressLookupRequest
        ) async -> SinglePressLookupResolution,
        loadOCRCandidate: @escaping @MainActor @Sendable (
            SinglePressLookupRequest
        ) async -> Candidate,
        routeResolved: @escaping @MainActor @Sendable (
            SinglePressLookupResolvedRoute
        ) -> Void
    ) async -> SinglePressLookupDecision<Candidate> {
        guard !Task.isCancelled else { return .cancelled }

        if request.executionPolicy == .selectionFirst {
            let resolution = await accessibilityProbe(request)
            guard !Task.isCancelled else { return .cancelled }

            if case .selectedTextSentence(let snapshot) = resolution.intent {
                routeResolved(.selectedText)
                return .selectedText(snapshot)
            }
        }

        routeResolved(.ocr)
        let candidate = await loadOCRCandidate(request)
        guard !Task.isCancelled else { return .cancelled }
        return .ocr(candidate)
    }
}
