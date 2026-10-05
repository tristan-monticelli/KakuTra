import XCTest
@testable import KakuTra

final class SinglePressLookupRequestTests: XCTestCase {
    func testRequestKeepsTriggerPointWhenLaterPointChanges() {
        let triggerPoint = CGPoint(x: 120, y: 240)
        let request = makeRequest(mouseLocation: triggerPoint)
        let laterPoint = CGPoint(x: 800, y: 600)

        XCTAssertNotEqual(laterPoint, triggerPoint)
        XCTAssertEqual(request.mouseLocation, triggerPoint)
    }

    func testEachContinuousLookupCanFreezeItsOwnPoint() {
        let first = makeRequest(mouseLocation: CGPoint(x: 100, y: 200))
        let second = makeRequest(mouseLocation: CGPoint(x: 140, y: 260))

        XCTAssertNotEqual(first.lookupID, second.lookupID)
        XCTAssertEqual(first.mouseLocation, CGPoint(x: 100, y: 200))
        XCTAssertEqual(second.mouseLocation, CGPoint(x: 140, y: 260))
    }

    func testRequestKeepsSelectedTextProbeContextFrozen() {
        let probeRequest = SelectedTextProbeRequest(
            mouseLocation: CGPoint(x: 120, y: 240),
            frontmostApplicationProcessIdentifier: 42,
            sourceAppIdentifier: "com.example.source",
            globalScreenMaxY: 1_080
        )
        let request = SinglePressLookupRequest(
            lookupID: UUID(),
            mouseLocation: probeRequest.mouseLocation,
            supportsSelectedText: true,
            selectedTextEnabled: true,
            hasAccessibilityPermission: true,
            selectedTextProbeRequest: probeRequest
        )

        XCTAssertEqual(request.selectedTextProbeRequest, probeRequest)
    }

    func testUnsupportedChannelUsesOCROnlyPolicy() {
        let request = makeRequest(supportsSelectedText: false)

        XCTAssertEqual(request.executionPolicy, .ocrOnly)
    }

    func testDisabledSelectedTextUsesOCROnlyPolicy() {
        let request = makeRequest(selectedTextEnabled: false)

        XCTAssertEqual(request.executionPolicy, .ocrOnly)
    }

    func testMissingAccessibilityUsesOCROnlyPolicy() {
        let request = makeRequest(hasAccessibilityPermission: false)

        XCTAssertEqual(request.executionPolicy, .ocrOnly)
    }

    func testSelectedTextPolicyTriesAccessibilityBeforeOCR() {
        XCTAssertEqual(makeRequest().executionPolicy, .selectionFirst)
    }

    private func makeRequest(
        mouseLocation: CGPoint = CGPoint(x: 120, y: 240),
        supportsSelectedText: Bool = true,
        selectedTextEnabled: Bool = true,
        hasAccessibilityPermission: Bool = true
    ) -> SinglePressLookupRequest {
        SinglePressLookupRequest(
            lookupID: UUID(),
            mouseLocation: mouseLocation,
            supportsSelectedText: supportsSelectedText,
            selectedTextEnabled: selectedTextEnabled,
            hasAccessibilityPermission: hasAccessibilityPermission
        )
    }
}

final class SelectedTextProbePolicyTests: XCTestCase {
    func testKnownRangeFastPathDoesNotReadMarkerAttributedOrBounds() throws {
        let calls = ProbeCallRecorder()
        let candidate = makeCandidate(
            calls: calls,
            directText: "Hello",
            range: NSRange(location: 3, length: 5),
            rangeText: "unused",
            markerText: "unused",
            attributedText: "unused",
            bounds: CGRect(x: 10, y: 20, width: 50, height: 18)
        )

        let snapshot = try XCTUnwrap(resolve(candidate))

        XCTAssertEqual(snapshot.text, "Hello")
        XCTAssertEqual(snapshot.selectedRange, NSRange(location: 3, length: 5))
        XCTAssertNil(snapshot.bounds)
        XCTAssertEqual(calls.values, ["selectedText", "selectedRange"])
    }

    func testRangeStringSuccessDoesNotEnterMarkerPhase() throws {
        let calls = ProbeCallRecorder()
        let candidate = makeCandidate(
            calls: calls,
            directText: nil,
            range: NSRange(location: 8, length: 5),
            rangeText: "Hello",
            markerText: "unused",
            attributedText: "unused",
            bounds: CGRect(x: 10, y: 20, width: 50, height: 18)
        )

        let snapshot = try XCTUnwrap(resolve(candidate))

        XCTAssertEqual(snapshot.text, "Hello")
        XCTAssertNil(snapshot.bounds)
        XCTAssertEqual(
            calls.values,
            ["selectedText", "selectedRange", "rangeString"]
        )
    }

    func testMarkerStringSuccessDoesNotReadAttributedString() throws {
        let calls = ProbeCallRecorder()
        let candidate = makeCandidate(
            calls: calls,
            directText: nil,
            range: nil,
            rangeText: nil,
            markerText: "Hello",
            attributedText: "unused",
            bounds: CGRect(x: 10, y: 20, width: 50, height: 18)
        )

        let snapshot = try XCTUnwrap(resolve(candidate))

        XCTAssertEqual(snapshot.text, "Hello")
        XCTAssertFalse(calls.values.contains("markerAttributedString"))
        XCTAssertEqual(
            calls.values,
            [
                "selectedText",
                "selectedRange",
                "markerRange",
                "markerString",
                "markerBounds",
            ]
        )
    }

    func testUnknownRangeReadsBoundsForGeometryConfidence() throws {
        let calls = ProbeCallRecorder()
        let candidate = makeCandidate(
            calls: calls,
            directText: "Hello",
            range: nil,
            rangeText: nil,
            markerText: "unused",
            attributedText: "unused",
            bounds: CGRect(x: 10, y: 20, width: 50, height: 18)
        )

        let snapshot = try XCTUnwrap(resolve(candidate))

        XCTAssertEqual(snapshot.selectedRange.location, NSNotFound)
        XCTAssertEqual(snapshot.bounds, CGRect(x: 10, y: 20, width: 50, height: 18))
        XCTAssertTrue(calls.values.contains("markerBounds"))
        XCTAssertFalse(calls.values.contains("markerString"))
        XCTAssertFalse(calls.values.contains("markerAttributedString"))
    }

    func testFirstHoveredCandidateSuccessDoesNotEnumerateFocusedCandidates() throws {
        let calls = ProbeCallRecorder()
        let first = makeCandidate(
            calls: calls,
            directText: "Hello",
            range: NSRange(location: 0, length: 5),
            rangeText: nil,
            markerText: nil,
            attributedText: nil,
            bounds: nil
        )
        var requestedCandidates = 0
        let candidates = AnySequence {
            AnyIterator<SelectedTextProbeCandidate> {
                requestedCandidates += 1
                switch requestedCandidates {
                case 1:
                    return first
                case 2:
                    XCTFail("fast path should not request the focused candidate")
                    return self.makeCandidate(
                        calls: calls,
                        directText: "Focused",
                        range: NSRange(location: 0, length: 7),
                        rangeText: nil,
                        markerText: nil,
                        attributedText: nil,
                        bounds: nil
                    )
                default:
                    return nil
                }
            }
        }

        let snapshot = try XCTUnwrap(
            SelectedTextProbePolicy.snapshot(
                candidates: candidates,
                sourceAppIdentifier: "com.apple.TextEdit",
                normalizeBounds: { $0 },
                diagnostics: SelectedTextDiagnostics(isEnabled: false)
            )
        )

        XCTAssertEqual(snapshot.text, "Hello")
        XCTAssertEqual(requestedCandidates, 1)
    }

    func testSoftBudgetDoesNotChangeSelectionResult() throws {
        let expected = SelectedTextSnapshot(
            text: "Hello",
            selectedRange: NSRange(location: 0, length: 5),
            bounds: nil,
            sourceAppIdentifier: "com.apple.TextEdit"
        )
        var observation: SelectedTextProbeObservation?

        let result = SelectedTextProbeSoftBudget.observe(
            expected,
            durationNanoseconds: SelectedTextProbeObservation.softBudgetNanoseconds + 1,
            observer: { observation = $0 }
        )

        XCTAssertEqual(result, expected)
        XCTAssertTrue(try XCTUnwrap(observation).exceededSoftBudget)
    }

    func testDisabledDiagnosticsDoesNotEvaluateMessageAutoclosure() {
        let diagnostics = SelectedTextDiagnostics(isEnabled: false)
        var evaluationCount = 0

        diagnostics.log({
            evaluationCount += 1
            return "expensive AX debug summary"
        }())

        XCTAssertEqual(evaluationCount, 0)
    }

    private func resolve(
        _ candidate: SelectedTextProbeCandidate
    ) -> SelectedTextSnapshot? {
        SelectedTextProbePolicy.snapshot(
            candidates: AnySequence([candidate]),
            sourceAppIdentifier: "com.apple.TextEdit",
            normalizeBounds: { $0 },
            diagnostics: SelectedTextDiagnostics(isEnabled: false)
        )
    }

    private func makeCandidate(
        calls: ProbeCallRecorder,
        directText: String?,
        range: NSRange?,
        rangeText: String?,
        markerText: String?,
        attributedText: String?,
        bounds: CGRect?
    ) -> SelectedTextProbeCandidate {
        SelectedTextProbeCandidate(
            context: "candidate[0] hovered#0",
            debugSummary: {
                calls.record("debugSummary")
                return "debug"
            },
            selectedText: {
                calls.record("selectedText")
                return directText
            },
            selectedRange: {
                calls.record("selectedRange")
                guard let range else { return nil }
                return SelectedTextProbeRange(
                    range: range,
                    string: {
                        calls.record("rangeString")
                        return rangeText
                    },
                    bounds: {
                        calls.record("rangeBounds")
                        return bounds
                    }
                )
            },
            selectedTextMarkerRange: {
                calls.record("markerRange")
                guard markerText != nil || attributedText != nil || bounds != nil else {
                    return nil
                }
                return SelectedTextProbeMarkerRange(
                    string: {
                        calls.record("markerString")
                        return markerText
                    },
                    attributedString: {
                        calls.record("markerAttributedString")
                        return attributedText.map(NSAttributedString.init(string:))
                    },
                    bounds: {
                        calls.record("markerBounds")
                        return bounds
                    }
                )
            }
        )
    }
}

final class SelectedTextProbeExecutorTests: XCTestCase {
    func testConcurrentProbesRunWithMaximumConcurrencyOfOne() async throws {
        let executor = SelectedTextProbeExecutor(label: #function)
        let concurrency = ProbeConcurrencyRecorder()

        async let first: Int = executor.execute { _ in
            concurrency.enter()
            Thread.sleep(forTimeInterval: 0.04)
            concurrency.leave()
            return 1
        }
        async let second: Int = executor.execute { _ in
            concurrency.enter()
            Thread.sleep(forTimeInterval: 0.04)
            concurrency.leave()
            return 2
        }

        let values = try await [first, second]
        XCTAssertEqual(Set(values), [1, 2])
        XCTAssertEqual(concurrency.maximum, 1)
    }

    func testProbeWorkDoesNotRunOnMainThread() async throws {
        let executor = SelectedTextProbeExecutor(label: #function)

        let ranOnMainThread = try await executor.execute { _ in
            Thread.isMainThread
        }

        XCTAssertFalse(ranOnMainThread)
    }

    func testCancellationStopsBeforeTheNextProbePhase() async {
        let executor = SelectedTextProbeExecutor(label: #function)
        let didStart = expectation(description: "probe phase started")
        let mayContinue = DispatchSemaphore(value: 0)
        let calls = ProbeCallRecorder()

        let task = Task {
            try await executor.execute { cancellation -> SelectedTextSnapshot? in
                let candidate = SelectedTextProbeCandidate(
                    context: "candidate",
                    debugSummary: { "debug" },
                    selectedText: {
                        calls.record("selectedText")
                        didStart.fulfill()
                        mayContinue.wait()
                        return "Hello"
                    },
                    selectedRange: {
                        calls.record("selectedRange")
                        return SelectedTextProbeRange(
                            range: NSRange(location: 0, length: 5),
                            string: { nil },
                            bounds: { nil }
                        )
                    },
                    selectedTextMarkerRange: {
                        calls.record("markerRange")
                        return nil
                    }
                )
                return SelectedTextProbePolicy.snapshot(
                    candidates: AnySequence([candidate]),
                    sourceAppIdentifier: nil,
                    normalizeBounds: { $0 },
                    diagnostics: SelectedTextDiagnostics(isEnabled: false),
                    isCancelled: { cancellation.isCancelled }
                )
            }
        }

        await fulfillment(of: [didStart], timeout: 1)
        task.cancel()
        mayContinue.signal()

        do {
            _ = try await task.value
            XCTFail("cancelled probe should throw CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        XCTAssertEqual(calls.values, ["selectedText"])
    }
}

@MainActor
final class SinglePressLookupCoordinatorTests: XCTestCase {
    func testKnownAccessibilitySelectionWinsWithoutLoadingOCR() async {
        let request = makeRequest()
        let snapshot = accessibilitySnapshot(text: "Known selection")

        let decision: SinglePressLookupDecision<String> = await SinglePressLookupCoordinator.resolve(
            request: request,
            accessibilityProbe: { _ in
                SinglePressLookupResolution(intent: .selectedTextSentence(snapshot))
            },
            loadOCRCandidate: { _ in "unexpected OCR" },
            routeResolved: { _ in }
        )

        guard case .selectedText(let resolvedSnapshot) = decision else {
            return XCTFail("known Accessibility selection should be used")
        }
        XCTAssertEqual(resolvedSnapshot, snapshot)
    }

    func testRejectedAccessibilitySelectionFallsBackToOCR() async {
        let request = makeRequest()

        let decision: SinglePressLookupDecision<String> = await SinglePressLookupCoordinator.resolve(
            request: request,
            accessibilityProbe: { _ in
                SinglePressLookupResolution(intent: .ocrWord)
            },
            loadOCRCandidate: { _ in "OCR candidate" },
            routeResolved: { _ in }
        )

        guard case .ocr(let candidate) = decision else {
            return XCTFail("rejected selection should fall back to OCR")
        }
        XCTAssertEqual(candidate, "OCR candidate")
    }

    func testOCROnlyPolicyDoesNotProbeAccessibility() async {
        let request = makeRequest(supportsSelectedText: false)

        let decision: SinglePressLookupDecision<String> = await SinglePressLookupCoordinator.resolve(
            request: request,
            accessibilityProbe: { _ in
                XCTFail("OCR-only lookup must not probe Accessibility")
                return SinglePressLookupResolution(intent: .ocrWord)
            },
            loadOCRCandidate: { _ in "OCR candidate" },
            routeResolved: { _ in }
        )

        guard case .ocr(let candidate) = decision else {
            return XCTFail("OCR-only request should use OCR")
        }
        XCTAssertEqual(candidate, "OCR candidate")
    }

    private func makeRequest(
        mouseLocation: CGPoint = CGPoint(x: 120, y: 240),
        supportsSelectedText: Bool = true,
        selectedTextEnabled: Bool = true,
        hasAccessibilityPermission: Bool = true
    ) -> SinglePressLookupRequest {
        SinglePressLookupRequest(
            lookupID: UUID(),
            mouseLocation: mouseLocation,
            supportsSelectedText: supportsSelectedText,
            selectedTextEnabled: selectedTextEnabled,
            hasAccessibilityPermission: hasAccessibilityPermission
        )
    }

    private func accessibilitySnapshot(text: String) -> SelectedTextSnapshot {
        SelectedTextSnapshot(
            text: text,
            selectedRange: NSRange(location: 0, length: text.utf16.count),
            bounds: nil,
            sourceAppIdentifier: "com.apple.TextEdit"
        )
    }
}

private final class ProbeCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [String] = []

    var values: [String] {
        lock.withLock { recordedValues }
    }

    func record(_ value: String) {
        lock.withLock {
            recordedValues.append(value)
        }
    }
}

private final class ProbeConcurrencyRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var currentValue = 0
    private var maximumValue = 0

    var maximum: Int {
        lock.withLock { maximumValue }
    }

    func enter() {
        lock.withLock {
            currentValue += 1
            maximumValue = max(maximumValue, currentValue)
        }
    }

    func leave() {
        lock.withLock {
            currentValue -= 1
        }
    }
}
