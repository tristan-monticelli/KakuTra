import ApplicationServices
import Dispatch
import Foundation

nonisolated struct SelectedTextSnapshot: Equatable, Sendable {
    let text: String
    let selectedRange: NSRange
    let bounds: CGRect?
    let sourceAppIdentifier: String?

    init(
        text: String,
        selectedRange: NSRange,
        bounds: CGRect?,
        sourceAppIdentifier: String?
    ) {
        self.text = text
        self.selectedRange = selectedRange
        self.bounds = bounds
        self.sourceAppIdentifier = sourceAppIdentifier
    }
}

nonisolated final class SelectedTextService: @unchecked Sendable {
    private let probeExecutor: SelectedTextProbeExecutor
    private let diagnostics: SelectedTextDiagnostics
    private let probeObserver: @Sendable (SelectedTextProbeObservation) -> Void

    init(
        probeExecutor: SelectedTextProbeExecutor = .shared,
        diagnostics: SelectedTextDiagnostics = .system,
        probeObserver: @escaping @Sendable (SelectedTextProbeObservation) -> Void = { _ in }
    ) {
        self.probeExecutor = probeExecutor
        self.diagnostics = diagnostics
        self.probeObserver = probeObserver
    }

    @MainActor
    func currentSelectionSnapshot(mouseLocation: CGPoint) async -> SelectedTextSnapshot? {
        let request = SelectedTextProbeRequest.capture(mouseLocation: mouseLocation)
        return await currentSelectionSnapshot(request: request)
    }

    func currentSelectionSnapshot(request: SelectedTextProbeRequest) async -> SelectedTextSnapshot? {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let snapshot: SelectedTextSnapshot?

        do {
            snapshot = try await probeExecutor.execute { [self] cancellation in
                axSelectionSnapshot(
                    request: request,
                    cancellation: cancellation
                )
            }
        } catch {
            snapshot = nil
        }

        let endedAt = DispatchTime.now().uptimeNanoseconds
        return SelectedTextProbeSoftBudget.observe(
            snapshot,
            durationNanoseconds: endedAt >= startedAt ? endedAt - startedAt : 0,
            observer: probeObserver
        )
    }

    private func axSelectionSnapshot(
        request: SelectedTextProbeRequest,
        cancellation: SelectedTextProbeCancellation
    ) -> SelectedTextSnapshot? {
        guard !cancellation.isCancelled else { return nil }
        let systemWideElement = AXUIElementCreateSystemWide()
        configureMessagingTimeout(for: systemWideElement)

        guard !cancellation.isCancelled else { return nil }
        let frontmostAppElement = request.frontmostApplicationProcessIdentifier.map {
            AXUIElementCreateApplication($0)
        }
        if let frontmostAppElement {
            configureMessagingTimeout(for: frontmostAppElement)
        }

        let candidates = candidateSequence(
            systemWideElement: systemWideElement,
            frontmostAppElement: frontmostAppElement,
            request: request,
            cancellation: cancellation
        )

        debugLog(
            "start mouse=\(describe(point: request.mouseLocation)) frontmostApp=\(request.sourceAppIdentifier ?? "nil")"
        )

        let snapshot = SelectedTextProbePolicy.snapshot(
            candidates: candidates,
            sourceAppIdentifier: request.sourceAppIdentifier,
            normalizeBounds: request.normalizedScreenRect,
            diagnostics: diagnostics,
            isCancelled: { cancellation.isCancelled }
        )
        debugLog(
            snapshot.map {
                "success text=\"\(truncate($0.text))\" bounds=\($0.bounds.map { describe(rect: $0) } ?? "nil")"
            } ?? "no selection snapshot from AXUIElement"
        )
        return snapshot
    }

    private func candidateSequence(
        systemWideElement: AXUIElement,
        frontmostAppElement: AXUIElement?,
        request: SelectedTextProbeRequest,
        cancellation: SelectedTextProbeCancellation,
        maxDepth: Int = 8
    ) -> AnySequence<SelectedTextProbeCandidate> {
        let rootProviders: [(source: String, element: () -> AXUIElement?)] = [
            (
                "frontmostApp-hovered",
                { [self] in
                    guard let frontmostAppElement else { return nil }
                    return element(
                        at: request.accessibilityPoint,
                        from: frontmostAppElement,
                        source: "frontmostApp"
                    )
                }
            ),
            (
                "systemWide-hovered",
                { [self] in
                    element(
                        at: request.accessibilityPoint,
                        from: systemWideElement,
                        source: "systemWide"
                    )
                }
            ),
            (
                "frontmostApp-focusedElement",
                { [self] in
                    guard let frontmostAppElement else { return nil }
                    return focusedElement(from: frontmostAppElement, source: "frontmostApp")
                }
            ),
            (
                "frontmostApp-focusedWindow",
                { [self] in
                    guard let frontmostAppElement else { return nil }
                    return focusedWindow(from: frontmostAppElement)
                }
            ),
            (
                "systemWide-focusedApplication",
                { [self] in focusedApplication(from: systemWideElement) }
            ),
            (
                "systemWide-focusedElement",
                { [self] in focusedElement(from: systemWideElement, source: "systemWide") }
            ),
        ]

        return AnySequence { [self] in
            var rootIndex = 0
            var activeElement: AXUIElement?
            var activeSource = ""
            var activeDepth = 0
            var shouldAdvanceToParent = false
            var seenElements: [AXUIElement] = []
            var candidateIndex = 0

            return AnyIterator<SelectedTextProbeCandidate> { [self] in
                while !cancellation.isCancelled {
                    if shouldAdvanceToParent, let currentElement = activeElement {
                        guard activeDepth + 1 < maxDepth else {
                            activeElement = nil
                            shouldAdvanceToParent = false
                            continue
                        }

                        guard !cancellation.isCancelled else { return nil }
                        guard let parentElement = parent(of: currentElement) else {
                            activeElement = nil
                            shouldAdvanceToParent = false
                            continue
                        }
                        guard !cancellation.isCancelled else { return nil }

                        activeElement = parentElement
                        activeDepth += 1
                    } else {
                        guard rootIndex < rootProviders.count else { return nil }
                        let provider = rootProviders[rootIndex]
                        rootIndex += 1

                        guard !cancellation.isCancelled else { return nil }
                        guard let rootElement = provider.element() else { continue }
                        guard !cancellation.isCancelled else { return nil }

                        activeElement = rootElement
                        activeSource = provider.source
                        activeDepth = 0
                        shouldAdvanceToParent = true
                    }

                    guard let candidateElement = activeElement else { continue }
                    guard !seenElements.contains(where: { CFEqual($0, candidateElement) }) else {
                        continue
                    }
                    seenElements.append(candidateElement)

                    let context = "candidate[\(candidateIndex)] \(activeSource)#\(activeDepth)"
                    candidateIndex += 1
                    return probeCandidate(
                        element: candidateElement,
                        context: context
                    )
                }

                return nil
            }
        }
    }

    private func probeCandidate(
        element: AXUIElement,
        context: String
    ) -> SelectedTextProbeCandidate {
        SelectedTextProbeCandidate(
            context: context,
            debugSummary: { [self] in debugSummary(of: element) },
            selectedText: { [self] in
                selectedText(from: element, debugContext: context)
            },
            selectedRange: { [self] in
                guard let result = selectedRange(
                    from: element,
                    debugContext: context
                ) else {
                    return nil
                }

                return SelectedTextProbeRange(
                    range: result.range,
                    string: { [self] in
                        string(
                            for: result.axValue,
                            in: element,
                            debugContext: context
                        )
                    },
                    bounds: { [self] in
                        bounds(
                            for: result.axValue,
                            in: element,
                            debugContext: context
                        )
                    }
                )
            },
            selectedTextMarkerRange: { [self] in
                guard let markerRange = selectedTextMarkerRange(
                    from: element,
                    debugContext: context
                ) else {
                    return nil
                }

                return SelectedTextProbeMarkerRange(
                    string: { [self] in
                        string(
                            forTextMarkerRange: markerRange,
                            in: element,
                            debugContext: context
                        )
                    },
                    attributedString: { [self] in
                        attributedString(
                            forTextMarkerRange: markerRange,
                            in: element,
                            debugContext: context
                        )
                    },
                    bounds: { [self] in
                        bounds(
                            forTextMarkerRange: markerRange,
                            in: element,
                            debugContext: context
                        )
                    }
                )
            }
        )
    }

    private func focusedElement(from systemWideElement: AXUIElement) -> AXUIElement? {
        focusedElement(from: systemWideElement, source: nil)
    }

    private func focusedElement(from element: AXUIElement, source: String?) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success, let value else {
            if let source {
                debugLog("\(source) AXFocusedUIElement error=\(String(describing: result))")
            }
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            if let source {
                debugLog("\(source) AXFocusedUIElement unexpected type")
            }
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func focusedApplication(from systemWideElement: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedApplicationAttribute as CFString,
            &value
        )
        guard result == .success, let value else {
            debugLog("systemWide AXFocusedApplication error=\(String(describing: result))")
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            debugLog("systemWide AXFocusedApplication unexpected type")
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func focusedWindow(from applicationElement: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &value
        )
        guard result == .success, let value else {
            debugLog("frontmostApp AXFocusedWindow error=\(String(describing: result))")
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            debugLog("frontmostApp AXFocusedWindow unexpected type")
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func element(
        at accessibilityPoint: CGPoint,
        from rootElement: AXUIElement,
        source: String
    ) -> AXUIElement? {
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            rootElement,
            Float(accessibilityPoint.x),
            Float(accessibilityPoint.y),
            &element
        )
        guard result == .success else {
            debugLog(
                "\(source) hovered element lookup failed axPoint=\(describe(point: accessibilityPoint)) error=\(String(describing: result))"
            )
            return nil
        }
        return element
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXParentAttribute as CFString,
            &value
        )
        guard result == .success, let value else {
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func selectedText(from element: AXUIElement, debugContext: String? = nil) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        )
        guard result == .success else {
            if let debugContext {
                debugLog("\(debugContext) AXSelectedText error=\(String(describing: result))")
            }
            return nil
        }
        return value as? String
    }

    private func selectedRange(from element: AXUIElement, debugContext: String? = nil) -> (range: NSRange, axValue: AXValue)? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )
        guard result == .success, let value else {
            if let debugContext {
                debugLog("\(debugContext) AXSelectedTextRange error=\(String(describing: result))")
            }
            return nil
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            if let debugContext {
                debugLog("\(debugContext) AXSelectedTextRange unexpected type")
            }
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else {
            if let debugContext {
                debugLog("\(debugContext) AXSelectedTextRange not cfRange")
            }
            return nil
        }

        var cfRange = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &cfRange), cfRange.length > 0 else {
            if let debugContext {
                debugLog("\(debugContext) AXSelectedTextRange empty or unreadable")
            }
            return nil
        }

        return (
            NSRange(location: cfRange.location, length: cfRange.length),
            axValue
        )
    }

    private func selectedTextMarkerRange(from element: AXUIElement, debugContext: String? = nil) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextMarkerRangeAttribute as CFString,
            &value
        )
        guard result == .success, let value else {
            if let debugContext {
                debugLog("\(debugContext) AXSelectedTextMarkerRange error=\(String(describing: result))")
            }
            return nil
        }
        return value
    }

    private func bounds(for rangeValue: AXValue, in element: AXUIElement, debugContext: String? = nil) -> CGRect? {
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        )
        guard result == .success, let value else {
            if let debugContext {
                debugLog("\(debugContext) AXBoundsForRange error=\(String(describing: result))")
            }
            return nil
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            if let debugContext {
                debugLog("\(debugContext) AXBoundsForRange unexpected type")
            }
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgRect else {
            if let debugContext {
                debugLog("\(debugContext) AXBoundsForRange not cgRect")
            }
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else {
            if let debugContext {
                debugLog("\(debugContext) AXBoundsForRange unreadable")
            }
            return nil
        }

        return rect
    }

    private func string(
        for rangeValue: AXValue,
        in element: AXUIElement,
        debugContext: String? = nil
    ) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        )
        guard result == .success else {
            if let debugContext {
                debugLog("\(debugContext) AXStringForRange error=\(String(describing: result))")
            }
            return nil
        }
        return value as? String
    }

    private func string(
        forTextMarkerRange markerRange: CFTypeRef,
        in element: AXUIElement,
        debugContext: String? = nil
    ) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForTextMarkerRangeParameterizedAttribute as CFString,
            markerRange,
            &value
        )
        guard result == .success else {
            if let debugContext {
                debugLog("\(debugContext) AXStringForTextMarkerRange error=\(String(describing: result))")
            }
            return nil
        }
        return value as? String
    }

    private func attributedString(
        forTextMarkerRange markerRange: CFTypeRef,
        in element: AXUIElement,
        debugContext: String? = nil
    ) -> NSAttributedString? {
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXAttributedStringForTextMarkerRangeParameterizedAttribute as CFString,
            markerRange,
            &value
        )
        guard result == .success else {
            if let debugContext {
                debugLog("\(debugContext) AXAttributedStringForTextMarkerRange error=\(String(describing: result))")
            }
            return nil
        }
        return value as? NSAttributedString
    }

    private func bounds(
        forTextMarkerRange markerRange: CFTypeRef,
        in element: AXUIElement,
        debugContext: String? = nil
    ) -> CGRect? {
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForTextMarkerRangeParameterizedAttribute as CFString,
            markerRange,
            &value
        )
        guard result == .success, let value else {
            if let debugContext {
                debugLog("\(debugContext) AXBoundsForTextMarkerRange error=\(String(describing: result))")
            }
            return nil
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            if let debugContext {
                debugLog("\(debugContext) AXBoundsForTextMarkerRange unexpected type")
            }
            return nil
        }

        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgRect else {
            if let debugContext {
                debugLog("\(debugContext) AXBoundsForTextMarkerRange not cgRect")
            }
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else {
            if let debugContext {
                debugLog("\(debugContext) AXBoundsForTextMarkerRange unreadable")
            }
            return nil
        }

        return rect
    }

    private func configureMessagingTimeout(for element: AXUIElement, timeout: Float = 1.5) {
        let result = AXUIElementSetMessagingTimeout(element, timeout)
        if result != .success {
            debugLog("set timeout failed error=\(String(describing: result)) timeout=\(timeout)")
        }
    }

    private func debugSummary(of element: AXUIElement) -> String {
        let role = stringAttribute(kAXRoleAttribute as CFString, from: element) ?? "nil"
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: element) ?? "nil"
        let identifier = stringAttribute(kAXIdentifierAttribute as CFString, from: element) ?? "nil"
        let title = stringAttribute(kAXTitleAttribute as CFString, from: element) ?? "nil"
        let value = stringAttribute(kAXValueAttribute as CFString, from: element).map { truncate($0) } ?? "nil"
        return "role=\(role) subrole=\(subrole) identifier=\(identifier) title=\(truncate(title)) value=\(value)"
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else {
            return nil
        }
        return value as? String
    }

    private func describe(point: CGPoint) -> String {
        "(\(format(point.x)), \(format(point.y)))"
    }

    private func describe(rect: CGRect) -> String {
        "x=\(format(rect.origin.x)) y=\(format(rect.origin.y)) w=\(format(rect.width)) h=\(format(rect.height))"
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }

    private func truncate(_ text: String, limit: Int = 120) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "..."
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        diagnostics.log(message())
    }
}
