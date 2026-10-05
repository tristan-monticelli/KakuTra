import CoreGraphics
import Foundation
import NaturalLanguage
import OSLog
import Vision

struct RecognizedWord: Equatable {
    var text: String
    var boundingBox: CGRect
}

struct RecognizedTextLine: Equatable {
    var text: String
    var boundingBox: CGRect
}

struct RecognizedParagraph: Equatable {
    var text: String
    var lines: [RecognizedTextLine]
    var boundingBox: CGRect
}

final class OCRService {
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "KakuTra",
        category: "OCR"
    )

    func recognizeWords(in image: CGImage, language: String) async throws -> [RecognizedWord] {
        let observations = try await recognizeObservations(in: image, language: language)
        return OCRService.extractWords(from: observations, language: language)
    }

    /// Returns grouped paragraphs and raw text lines for language detection.
    func recognizeParagraphsWithRawLines(
        in image: CGImage,
        language: String,
        reportsPerformance: Bool = false
    ) async throws -> (
        paragraphs: [RecognizedParagraph],
        lines: [RecognizedTextLine]
    ) {
        let observations = try await recognizeObservations(
            in: image,
            language: language,
            reportsPerformance: reportsPerformance
        )
        let lines = OCRService.extractLines(from: observations)
        return (OCRService.groupParagraphs(from: lines), lines)
    }

    private func recognizeObservations(
        in image: CGImage,
        language: String,
        reportsPerformance: Bool = false
    ) async throws -> [VNRecognizedTextObservation] {
        try Task.checkCancellation()

        let normalizationStart = ProcessInfo.processInfo.systemUptime
        let visionImage = Self.normalizedImageForVision(image)
        let normalizationMilliseconds = (ProcessInfo.processInfo.systemUptime - normalizationStart) * 1_000
        if reportsPerformance {
            Self.logger.info(
                "OCR image prepared width=\(visionImage.width, privacy: .public) height=\(visionImage.height, privacy: .public) normalizationMs=\(normalizationMilliseconds, privacy: .public)"
            )
        } else {
            Self.logger.debug(
                "OCR start width=\(visionImage.width, privacy: .public) height=\(visionImage.height, privacy: .public) sourceLanguage=\(language, privacy: .public) normalizationMs=\(normalizationMilliseconds, privacy: .public)"
            )
        }

        return try await withThrowingTaskGroup(of: [VNRecognizedTextObservation].self) { group in
            group.addTask(priority: .userInitiated) {
                try Task.checkCancellation()

                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                if VNRecognizeTextRequest.supportedRevisions.contains(VNRecognizeTextRequest.currentRevision) {
                    request.revision = VNRecognizeTextRequest.currentRevision
                }
                request.automaticallyDetectsLanguage = true

                let preferredLanguages = Self.preferredRecognitionLanguages(for: language)
                if let supportedLanguages = try? request.supportedRecognitionLanguages() {
                    let supported = preferredLanguages.filter(supportedLanguages.contains)
                    if !supported.isEmpty {
                        request.recognitionLanguages = supported
                    }
                }

                do {
                    let visionStart = ProcessInfo.processInfo.systemUptime
                    let handler = VNImageRequestHandler(cgImage: visionImage)
                    try handler.perform([request])
                    let visionMilliseconds = (ProcessInfo.processInfo.systemUptime - visionStart) * 1_000
                    let results = request.results ?? []
                    if reportsPerformance {
                        Self.logger.info(
                            "Vision OCR finished observations=\(results.count, privacy: .public) recognitionMs=\(visionMilliseconds, privacy: .public)"
                        )
                    } else {
                        Self.logger.debug(
                            "Vision OCR finished observations=\(results.count, privacy: .public) recognitionMs=\(visionMilliseconds, privacy: .public)"
                        )
                    }
                } catch {
                    Self.logger.error(
                        "OCR Vision request failed domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code, privacy: .public) description=\(error.localizedDescription, privacy: .public)"
                    )
                    throw error
                }
                try Task.checkCancellation()

                return request.results ?? []
            }

            let observations = try await group.next() ?? []
            group.cancelAll()
            return observations
        }
    }

    private static func normalizedImageForVision(_ image: CGImage) -> CGImage {
        guard image.width > 0, image.height > 0 else {
            logger.error("OCR received an invalid image size")
            return image
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)

        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            logger.error("OCR image normalization could not create bitmap context")
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: bounds)
        guard let normalizedImage = context.makeImage() else {
            logger.error("OCR image normalization could not create CGImage")
            return image
        }

        return normalizedImage
    }

    nonisolated private static func preferredRecognitionLanguages(for _: String) -> [String] {
        ["ja-JP", "zh-Hans", "zh-Hant", "ko-KR"]
    }

    nonisolated private static func extractWords(
        from observations: [VNRecognizedTextObservation],
        language: String?
    ) -> [RecognizedWord] {
        #if DEBUG
        print("[OCR] ========== New OCR Result ==========")
        print("[OCR] Total observations: \(observations.count)")
        #endif

        var words: [RecognizedWord] = []
        for (obsIndex, observation) in observations.enumerated() {
            guard let candidate = observation.topCandidates(1).first else {
                continue
            }
            let text = candidate.string
            let detectedLanguage = LanguageClassificationService.supportedOCRLanguage(for: text) ?? language
            let refinedRanges = tokenRanges(
                in: text,
                language: detectedLanguage,
                candidate: candidate
            )

            #if DEBUG
            print("[OCR] Observation \(obsIndex): '\(text)', tokenized into \(refinedRanges.count) parts")
            for (i, range) in refinedRanges.enumerated() {
                print("[OCR]   Token \(i): '\(text[range])'")
            }
            #endif

            words.append(contentsOf: recognizedWords(
                from: observation,
                candidate: candidate,
                refinedRanges: refinedRanges,
                language: detectedLanguage
            ))
        }
        return words
    }

    nonisolated private static func recognizedWords(
        from observation: VNRecognizedTextObservation,
        candidate: VNRecognizedText,
        refinedRanges: [Range<String.Index>],
        language: String?
    ) -> [RecognizedWord] {
        let text = candidate.string
        let textBoundingBox = observation.boundingBox
        let allowsFallbackDrift = containsHanAndLatin(in: text)

        return refinedRanges.compactMap { refinedRange in
            let substring = text[refinedRange]
            guard containsLetter(in: substring) else {
                return nil
            }

            let preciseBox = preciseBoundingBox(for: refinedRange, in: candidate)
            let fallbackBox = boundingBoxByCharacterRatio(textBoundingBox, text: text, for: refinedRange)
            guard let boundingBox = resolvedTokenBoundingBox(
                preciseBox: preciseBox,
                fallbackBox: fallbackBox,
                parentBox: textBoundingBox,
                isSubrange: refinedRange != text.startIndex..<text.endIndex,
                allowsFallbackDrift: allowsFallbackDrift
            ) else {
                return nil
            }

            #if DEBUG
            print("[OCR]   '\(substring)' box: x=\(String(format: "%.4f", boundingBox.minX)), w=\(String(format: "%.4f", boundingBox.width))")
            #endif

            let lookupText = normalizedTextForTokenization(String(substring), language: language).text
            return RecognizedWord(text: lookupText, boundingBox: boundingBox)
        }
    }

    nonisolated static func extractLines(from observations: [VNRecognizedTextObservation]) -> [RecognizedTextLine] {
        observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }

            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return nil
            }

            return RecognizedTextLine(text: text, boundingBox: observation.boundingBox)
        }
    }

    nonisolated private static func isCompatibleSubrangeBoundingBox(
        _ box: CGRect,
        fallbackBox: CGRect,
        parentBox: CGRect,
        allowsFallbackDrift: Bool
    ) -> Bool {
        guard box.width > 0, fallbackBox.width > 0, parentBox.width > 0 else {
            return false
        }

        let coversMostOfParent = box.width >= parentBox.width * 0.8
        if coversMostOfParent && box.width > fallbackBox.width * 1.8 {
            return false
        }

        if allowsFallbackDrift {
            return box.width <= fallbackBox.width * 1.5
        }

        let horizontalEdgeTolerance = max(parentBox.width * 0.01, fallbackBox.width * 0.35)
        guard box.minX >= fallbackBox.minX - horizontalEdgeTolerance,
              box.maxX <= fallbackBox.maxX + horizontalEdgeTolerance else {
            return false
        }

        let horizontalOverlap = max(0, min(box.maxX, fallbackBox.maxX) - max(box.minX, fallbackBox.minX))
        let horizontalOverlapRatio = horizontalOverlap / min(box.width, fallbackBox.width)

        return horizontalOverlapRatio >= 0.35
    }

    nonisolated private static func isTokenCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { tokenCharacterSet.contains($0) }
    }


    nonisolated private static func shouldSplitCamelCase(previous: Character, current: Character, next: Character?) -> Bool {
        let previousIsLowercase = isLowercaseLetter(previous)
        let previousIsUppercase = isUppercaseLetter(previous)
        let currentIsUppercase = isUppercaseLetter(current)
        let nextIsLowercase = next.map(isLowercaseLetter) ?? false

        if previousIsLowercase && currentIsUppercase {
            return true
        }

        if previousIsUppercase && currentIsUppercase && nextIsLowercase {
            return true
        }

        return false
    }

    nonisolated private static func isUppercaseLetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.uppercaseLetters.contains($0) }
    }

    nonisolated private static func isLowercaseLetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { CharacterSet.lowercaseLetters.contains($0) }
    }

    nonisolated private static func containsLetter(in token: Substring) -> Bool {
        token.unicodeScalars.contains { letterSet.contains($0) || $0.properties.isIdeographic }
    }

    nonisolated private static func containsHanAndLatin(in text: String) -> Bool {
        var hasHan = false
        var hasLatin = false

        for scalar in text.unicodeScalars {
            if scalar.properties.isIdeographic {
                hasHan = true
            }
            if tokenCharacterSet.contains(scalar) {
                hasLatin = true
            }
            if hasHan && hasLatin {
                return true
            }
        }

        return false
    }

    nonisolated private static func mergeHorizontallyAdjacentLineFragments(
        in lines: [RecognizedTextLine]
    ) -> [RecognizedTextLine] {
        let sortedLines = lines
            .map {
                RecognizedTextLine(
                    text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    boundingBox: $0.boundingBox
                )
            }
            .filter { !$0.text.isEmpty }
            .sorted { lhs, rhs in
                if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.005 {
                    return lhs.boundingBox.midY > rhs.boundingBox.midY
                }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }

        var mergedLines: [RecognizedTextLine] = []

        for line in sortedLines {
            if var previous = mergedLines.last,
               shouldMergeLineFragments(previous: previous, next: line) {
                previous.text = mergedLineText(previous.text, line.text)
                previous.boundingBox = previous.boundingBox.union(line.boundingBox)
                mergedLines[mergedLines.count - 1] = previous
            } else {
                mergedLines.append(line)
            }
        }

        return mergedLines
    }

    nonisolated private static func shouldMergeLineFragments(
        previous: RecognizedTextLine,
        next: RecognizedTextLine
    ) -> Bool {
        let previousHeight = previous.boundingBox.height
        let nextHeight = next.boundingBox.height
        let minHeight = min(previousHeight, nextHeight)
        let maxHeight = max(previousHeight, nextHeight)
        guard minHeight > 0 else { return false }

        let heightRatio = maxHeight / minHeight
        guard heightRatio <= 1.35 else { return false }

        let verticalOverlap = max(
            0,
            min(previous.boundingBox.maxY, next.boundingBox.maxY)
                - max(previous.boundingBox.minY, next.boundingBox.minY)
        )
        let verticalOverlapRatio = verticalOverlap / minHeight
        guard verticalOverlapRatio >= 0.7 else { return false }

        let horizontalGap = next.boundingBox.minX - previous.boundingBox.maxX
        let allowedGap = max(maxHeight * 1.8, 0.018)
        guard horizontalGap >= -maxHeight * 0.2, horizontalGap <= allowedGap else {
            return false
        }

        return true
    }

    nonisolated private static func mergedLineText(
        _ previous: String,
        _ next: String
    ) -> String {
        let lhs = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let rhs = next.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !lhs.isEmpty else { return rhs }
        guard !rhs.isEmpty else { return lhs }

        if shouldInsertSpaceBetweenLineFragments(previous: lhs, next: rhs) {
            return "\(lhs) \(rhs)"
        }

        return lhs + rhs
    }

    nonisolated private static func shouldInsertSpaceBetweenLineFragments(
        previous: String,
        next: String
    ) -> Bool {
        guard let previousScalar = previous.unicodeScalars.last,
              let nextScalar = next.unicodeScalars.first else {
            return false
        }

        let asciiWordCharacterSet = CharacterSet.alphanumerics
        let insertsAfter = asciiWordCharacterSet.contains(previousScalar)
            || ",.;:!?)]}\"'".unicodeScalars.contains(previousScalar)
        let insertsBefore = asciiWordCharacterSet.contains(nextScalar)

        return previousScalar.isASCII && nextScalar.isASCII && insertsAfter && insertsBefore
    }

    nonisolated private static func shouldJoinParagraph(
        previous: RecognizedTextLine,
        next: RecognizedTextLine
    ) -> Bool {
        let previousHeight = previous.boundingBox.height
        let nextHeight = next.boundingBox.height
        let minHeight = min(previousHeight, nextHeight)
        let maxHeight = max(previousHeight, nextHeight)
        guard minHeight > 0 else { return false }

        // Lines with very different heights are likely different elements (e.g. heading vs body).
        // However, a bold line followed by regular body text can have heightRatio up to ~1.6
        // because bold glyphs occupy more vertical space in Vision's bounding box.
        // True heading+body pairs are distinguished by a larger vertical gap, so we relax
        // the height gate to 2.0 and rely on the vertical gap check to prevent mis-merges.
        let heightRatio = maxHeight / minHeight
        guard heightRatio <= 2.0 else { return false }

        // Vertical gap must be within normal line-spacing range.
        // When heightRatio is large (e.g. bold line before normal body), tighten the gap
        // threshold to avoid merging a true heading with the paragraph below it.
        let verticalGap = max(previous.boundingBox.minY - next.boundingBox.maxY, 0)
        let gapThreshold: CGFloat = heightRatio > 1.4 ? maxHeight * 0.5 : maxHeight * 0.8
        guard verticalGap <= gapThreshold else { return false }

        // Require meaningful horizontal overlap OR left-edge alignment to join lines.
        //
        // Pure overlap check fails for paragraph lines that wrap differently due to
        // an adjacent column or sidebar occluding part of the line — Vision may assign
        // different right-edge extents to each line, yielding zero overlap even though
        // the lines share the same left margin and clearly belong to the same paragraph.
        //
        // Strategy:
        //   1. If horizontal overlap ≥ 25 % of the shorter line → join (original rule).
        //   2. Otherwise, if both lines' left edges are within 2× line-height of each
        //      other AND the shorter line's right edge does not extend clearly to the
        //      left of the longer line's start → treat as left-aligned continuation.
        let prevMinX = previous.boundingBox.minX
        let prevMaxX = previous.boundingBox.maxX
        let nextMinX = next.boundingBox.minX
        let nextMaxX = next.boundingBox.maxX
        let overlapWidth = max(0, min(prevMaxX, nextMaxX) - max(prevMinX, nextMinX))
        let minWidth = min(previous.boundingBox.width, next.boundingBox.width)
        let horizontalOverlapRatio = minWidth > 0 ? overlapWidth / minWidth : 0

        if horizontalOverlapRatio >= 0.25 {
            return true
        }

        // Left-alignment fallback: lines share a left margin (within 2× line height)
        // and neither line starts significantly to the right of the other's left edge.
        let leftEdgeDelta = abs(prevMinX - nextMinX)
        let leftAlignThreshold = maxHeight * 2.0
        let leftAligned = leftEdgeDelta <= leftAlignThreshold

        // Reject if the lines are clearly side-by-side (right edge of one line is to
        // the left of the start of the other line by more than a small tolerance).
        let sideBySide = (prevMaxX + maxHeight < nextMinX) || (nextMaxX + maxHeight < prevMinX)

        return leftAligned && !sideBySide
    }

    nonisolated private static func normalizedParagraphText(from lines: [RecognizedTextLine]) -> String {
        lines
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func containsLikelyParagraphContent(_ text: String) -> Bool {
        text.unicodeScalars.contains { letterSet.contains($0) || $0.properties.isIdeographic }
    }

    /// Estimates the display font size for a paragraph based on its line heights
    nonisolated static func estimatedDisplayFontSize(for paragraph: RecognizedParagraph, in captureRect: CGRect) -> CGFloat {
        guard !paragraph.lines.isEmpty else {
            return 14.0 // Default fallback
        }

        // Calculate average line height in normalized coordinates
        let avgNormalizedHeight = paragraph.lines.map { $0.boundingBox.height }.reduce(0, +) / CGFloat(paragraph.lines.count)

        // Convert to screen coordinates
        let screenHeight = avgNormalizedHeight * captureRect.height

        // Font size is typically ~0.7-0.8 of line height
        return screenHeight * 0.75
    }

    nonisolated static func selectWord(from words: [RecognizedWord], normalizedPoint: CGPoint) -> RecognizedWord? {
        if let strictMatch = nearestWord(from: words, normalizedPoint: normalizedPoint, tolerance: 0) {
            return strictMatch
        }

        return nearestWord(from: words, normalizedPoint: normalizedPoint, tolerance: 0.004)
    }

    nonisolated private static func nearestWord(
        from words: [RecognizedWord],
        normalizedPoint: CGPoint,
        tolerance: CGFloat
    ) -> RecognizedWord? {
        let candidates = words.filter { word in
            let hitBox = word.boundingBox.insetBy(dx: -tolerance, dy: -tolerance)
            return hitBox.contains(normalizedPoint)
        }

        guard !candidates.isEmpty else { return nil }

        return candidates.min { lhs, rhs in
            let lhsDistance = hypot(lhs.boundingBox.midX - normalizedPoint.x, lhs.boundingBox.midY - normalizedPoint.y)
            let rhsDistance = hypot(rhs.boundingBox.midX - normalizedPoint.x, rhs.boundingBox.midY - normalizedPoint.y)
            return lhsDistance < rhsDistance
        }
    }
}
