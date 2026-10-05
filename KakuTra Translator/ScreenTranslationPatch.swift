import AppKit
import Foundation
import SwiftUI

struct ScreenTranslationCacheKey: Hashable, Sendable {
    let languageIdentifier: String
    let normalizedText: String

    init(languageIdentifier: String, text: String) {
        self.languageIdentifier = languageIdentifier
            .lowercased()
            .split(separator: "-")
            .first
            .map(String.init) ?? languageIdentifier.lowercased()
        let foldedText = text
            .precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        if self.languageIdentifier == "ja" || self.languageIdentifier == "zh" {
            // Japanese and Chinese OCR often inserts arbitrary spaces or varies
            // punctuation between frames. Neither should trigger a new translation.
            self.normalizedText = String(foldedText.unicodeScalars.filter {
                !CharacterSet.whitespacesAndNewlines.contains($0)
                    && !CharacterSet.punctuationCharacters.contains($0)
            })
        } else {
            let punctuationFolded = String(foldedText.unicodeScalars.map { scalar in
                CharacterSet.punctuationCharacters.contains(scalar) ? " " : String(scalar)
            }.joined())
            self.normalizedText = punctuationFolded
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }

    var stableIdentifier: String {
        "\(languageIdentifier):\(normalizedText)"
    }
}

struct ScreenTranslationTextCache: Sendable {
    private struct Entry: Sendable {
        let translation: String
        let expiresAt: Date
    }

    let lifetime: TimeInterval
    private var entries: [ScreenTranslationCacheKey: Entry] = [:]

    init(lifetime: TimeInterval = 30) {
        self.lifetime = max(0, lifetime)
    }

    var count: Int { entries.count }

    func translation(for key: ScreenTranslationCacheKey, now: Date = .now) -> String? {
        guard let entry = entries[key], entry.expiresAt > now else { return nil }
        return entry.translation
    }

    mutating func store(
        _ translation: String,
        for key: ScreenTranslationCacheKey,
        now: Date = .now
    ) {
        guard !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        entries[key] = Entry(translation: translation, expiresAt: now.addingTimeInterval(lifetime))
        if entries.count > 2_000,
           let oldestKey = entries.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
            entries.removeValue(forKey: oldestKey)
        }
    }

    mutating func refreshLifetime(for key: ScreenTranslationCacheKey, now: Date = .now) {
        guard let entry = entries[key] else { return }
        entries[key] = Entry(
            translation: entry.translation,
            expiresAt: now.addingTimeInterval(lifetime)
        )
    }

    mutating func removeExpired(now: Date = .now) {
        entries = entries.filter { $0.value.expiresAt > now }
    }

    mutating func removeAll() {
        entries.removeAll()
    }
}

struct ScreenTranslationPatchContent: Equatable {
    var originalText: String
    var translationState: ScreenTranslationPatchState
    var sourceRect: CGRect
    var bodyFontSize: CGFloat
    var style: ScreenTranslationPatchStyle
    var maximumPatchWidth: CGFloat? = nil
    var maximumPatchHeight: CGFloat? = nil
}

enum ScreenTranslationPatchState: Equatable {
    case loading
    case ready(String)
    case failed(String)
}

struct ScreenTranslationPatchStyle: Equatable {
    var backgroundColor: NSColor
    var foregroundColor: NSColor
    var borderColor: NSColor
}

enum ScreenTranslationPatchStyleResolver {
    private static let defaultStyle = ScreenTranslationPatchStyle(
        backgroundColor: .windowBackgroundColor,
        foregroundColor: .labelColor,
        borderColor: NSColor(calibratedWhite: 0.68, alpha: 1)
    )

    static func resolve(
        captureImage: CGImage?,
        captureRect: CGRect,
        sourceRect: CGRect
    ) -> ScreenTranslationPatchStyle {
        guard let image = captureImage,
              captureRect.width > 0, captureRect.height > 0 else {
            return defaultStyle
        }

        let normalizedX = (sourceRect.minX - captureRect.minX) / captureRect.width
        let normalizedY = (sourceRect.minY - captureRect.minY) / captureRect.height
        let normalizedW = sourceRect.width / captureRect.width
        let normalizedH = sourceRect.height / captureRect.height

        let pixelX = Int(normalizedX * CGFloat(image.width))
        let pixelW = max(1, Int(normalizedW * CGFloat(image.width)))
        let pixelH = max(1, Int(normalizedH * CGFloat(image.height)))

        // Screen coordinates use a bottom-left origin; CGImage pixel coordinates
        // use a top-left origin.
        let pixelY = Int((1 - normalizedY - normalizedH) * CGFloat(image.height))

        let clampedX = max(0, min(pixelX, image.width - 1))
        let clampedY = max(0, min(pixelY, image.height - 1))
        let clampedW = max(1, min(pixelW, image.width - clampedX))
        let clampedH = max(1, min(pixelH, image.height - clampedY))

        let pixelRect = CGRect(x: clampedX, y: clampedY, width: clampedW, height: clampedH)
        guard let averageColor = Self.averageColor(in: pixelRect, image: image) else {
            return defaultStyle
        }

        let luminance = Self.relativeLuminance(for: averageColor)
        let foregroundColor: NSColor = luminance > 0.5
            ? NSColor(calibratedWhite: 0.08, alpha: 1)
            : NSColor(calibratedWhite: 0.96, alpha: 1)

        let backgroundColor: NSColor = luminance > 0.5
            ? NSColor(calibratedWhite: 0.98, alpha: 1)
            : NSColor(calibratedWhite: 0.08, alpha: 1)
        let borderColor: NSColor = luminance > 0.5
            ? NSColor(calibratedWhite: 0.68, alpha: 1)
            : NSColor(calibratedWhite: 0.34, alpha: 1)

        return ScreenTranslationPatchStyle(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            borderColor: borderColor
        )
    }

    private static func averageColor(in pixelRect: CGRect, image: CGImage) -> NSColor? {
        let integralRect = pixelRect.integral.intersection(
            CGRect(x: 0, y: 0, width: image.width, height: image.height)
        )
        guard let croppedImage = image.cropping(to: integralRect) else { return nil }

        let sampleW = min(16, croppedImage.width)
        let sampleH = min(16, croppedImage.height)
        guard sampleW > 0, sampleH > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: sampleW,
            height: sampleH,
            bitsPerComponent: 8,
            bytesPerRow: sampleW * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(croppedImage, in: CGRect(x: 0, y: 0, width: sampleW, height: sampleH))

        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: sampleW * sampleH * 4)

        var totalR: Double = 0
        var totalG: Double = 0
        var totalB: Double = 0
        let count = Double(sampleW * sampleH)

        for row in 0..<sampleH {
            for col in 0..<sampleW {
                let offset = (row * sampleW + col) * 4
                totalR += Double(pixels[offset]) / 255.0
                totalG += Double(pixels[offset + 1]) / 255.0
                totalB += Double(pixels[offset + 2]) / 255.0
            }
        }

        return NSColor(
            calibratedRed: CGFloat(totalR / count),
            green: CGFloat(totalG / count),
            blue: CGFloat(totalB / count),
            alpha: 1
        )
    }

    private static func relativeLuminance(for color: NSColor) -> CGFloat {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
    }
}

struct ScreenTranslationPatchTextFrame: Equatable {
    var origin: CGPoint
    var size: CGSize
}

struct ScreenTranslationPatchLayoutResult: Equatable {
    let fontSize: CGFloat
    let padding: CGFloat
    let cornerRadius: CGFloat
    let patchSize: CGSize
    let textFrame: ScreenTranslationPatchTextFrame
}

enum ScreenTranslationPatchClearance {
    static func maximumRightwardWidth(
        for sourceRect: CGRect,
        protectedRects: [CGRect],
        screenSize: CGSize
    ) -> CGFloat {
        let sourceWidth = max(sourceRect.width, 1)
        let screenLimit = max(sourceWidth, screenSize.width - sourceRect.minX - 8)
        let naturalLimit = max(sourceWidth + 80, sourceWidth * 1.6)
        let protectedBand = sourceRect.insetBy(dx: 0, dy: -8)

        let nearestTextOnRight = protectedRects
            .filter { rect in
                !sourceRect.insetBy(dx: -1, dy: -1).contains(rect)
                    && rect.maxY > protectedBand.minY
                    && rect.minY < protectedBand.maxY
            }
            .map(\.minX)
            .min()

        let obstacleLimit = nearestTextOnRight.map { $0 - sourceRect.minX - 4 } ?? screenLimit
        return max(sourceWidth, min(screenLimit, min(naturalLimit, obstacleLimit)))
    }

    static func maximumDownwardHeight(
        for sourceRect: CGRect,
        maximumWidth: CGFloat,
        protectedRects: [CGRect],
        screenSize: CGSize
    ) -> CGFloat {
        let sourceHeight = max(sourceRect.height, 1)
        let screenLimit = max(sourceHeight, screenSize.height - sourceRect.minY - 8)
        let naturalLimit = max(sourceHeight + 48, sourceHeight * 1.6)
        let expansionBand = CGRect(
            x: sourceRect.minX,
            y: sourceRect.minY,
            width: maximumWidth,
            height: sourceHeight + 8
        )

        let nearestTextBelow = protectedRects
            .filter { rect in
                !sourceRect.insetBy(dx: -1, dy: -1).contains(rect)
                    && rect.minX < expansionBand.maxX
                    && rect.maxX > expansionBand.minX
                    && rect.minY >= sourceRect.maxY - 1
            }
            .map(\.minY)
            .min()

        let obstacleLimit = nearestTextBelow.map { $0 - sourceRect.minY - 4 } ?? screenLimit
        return max(sourceHeight, min(screenLimit, min(naturalLimit, obstacleLimit)))
    }
}

enum ScreenTranslationPatchLayout {
    static func resolve(
        sourceRect: CGRect,
        preferredFontSize: CGFloat,
        translatedText: String,
        maximumPatchWidth: CGFloat? = nil,
        maximumPatchHeight: CGFloat? = nil
    ) -> ScreenTranslationPatchLayoutResult {
        let width = max(sourceRect.width, 1)
        let height = max(sourceRect.height, 1)
        let padding: CGFloat = 3
        let cornerRadius: CGFloat = 3
        var fontSize = max(10, min(22, preferredFontSize))
        let naturalWidthLimit = max(width + 80, width * 1.6)
        let widthLimit = max(width, maximumPatchWidth ?? naturalWidthLimit)
        let textWidthLimit = max(20, widthLimit - padding * 2)
        func measure(_ size: CGFloat) -> CGRect {
            (translatedText as NSString).boundingRect(
                with: CGSize(width: textWidthLimit, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: NSFont.systemFont(ofSize: size, weight: .semibold)],
                context: nil
            )
        }
        let heightLimit = max(height, maximumPatchHeight ?? .greatestFiniteMagnitude)
        var measuredText = measure(fontSize)
        while ceil(measuredText.height) + padding * 2 > heightLimit, fontSize > 8 {
            fontSize -= 1
            measuredText = measure(fontSize)
        }
        let patchWidth = min(widthLimit, max(width, ceil(measuredText.width) + padding * 2))
        let patchHeight = min(heightLimit, max(height, ceil(measuredText.height) + padding * 2))
        let patchSize = CGSize(width: patchWidth, height: patchHeight)
        let textFrame = ScreenTranslationPatchTextFrame(
            origin: CGPoint(x: padding, y: padding),
            size: CGSize(
                width: max(1, patchWidth - padding * 2),
                height: max(1, patchHeight - padding * 2)
            )
        )

        return ScreenTranslationPatchLayoutResult(
            fontSize: fontSize,
            padding: padding,
            cornerRadius: cornerRadius,
            patchSize: patchSize,
            textFrame: textFrame
        )
    }
}

struct ScreenTranslationPatchView: View {
    let content: ScreenTranslationPatchContent

    private var displayText: String {
        switch content.translationState {
        case .loading:
            return L("Translating")
        case .ready(let text):
            return text
        case .failed(let message):
            return L(message)
        }
    }

    private var layout: ScreenTranslationPatchLayoutResult {
        ScreenTranslationPatchLayout.resolve(
            sourceRect: content.sourceRect,
            preferredFontSize: content.bodyFontSize,
            translatedText: displayText,
            maximumPatchWidth: content.maximumPatchWidth,
            maximumPatchHeight: content.maximumPatchHeight
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                .fill(Color(nsColor: content.style.backgroundColor))

            ScreenTranslationPatchTextView(
                text: displayText,
                font: .systemFont(ofSize: layout.fontSize, weight: .semibold),
                textColor: content.style.foregroundColor
            )
            .frame(
                width: layout.textFrame.size.width,
                height: layout.textFrame.size.height,
                alignment: .topLeading
            )
            .position(
                x: layout.textFrame.origin.x + layout.textFrame.size.width / 2,
                y: layout.textFrame.origin.y + layout.textFrame.size.height / 2
            )
        }
    }
}

// MARK: - Selectable Text View

private struct ScreenTranslationPatchTextView: NSViewRepresentable {
    let text: String
    let font: NSFont
    let textColor: NSColor

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.focusRingType = .none
        textView.textContainerInset = .zero
        textView.autoresizingMask = [.width, .height]
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.lineBreakMode = .byWordWrapping
        applyContent(textView)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        applyContent(textView)
    }

    private func applyContent(_ textView: NSTextView) {
        if textView.string == text,
           let storage = textView.textStorage,
           storage.length > 0,
           let existingFont = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
           let existingColor = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
           existingFont.isEqual(font),
           existingColor.isEqual(textColor) {
            return
        }
        textView.textStorage?.setAttributedString(
            NSAttributedString(
                string: text,
                attributes: [.font: font, .foregroundColor: textColor]
            )
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}
