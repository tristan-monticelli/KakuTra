import XCTest
@testable import KakuTra

final class ScreenTranslationPatchLayoutTests: XCTestCase {
    func testResolveKeepsSmallLineReadableAndInsideHeight() {
        let result = ScreenTranslationPatchLayout.resolve(
            sourceRect: CGRect(x: 0, y: 0, width: 180, height: 24),
            preferredFontSize: 18,
            translatedText: "短句翻译"
        )

        XCTAssertEqual(result.padding, 3)
        XCTAssertEqual(result.cornerRadius, 3)
        XCTAssertEqual(result.fontSize, 18)
        XCTAssertGreaterThanOrEqual(result.patchSize.width, 180)
        XCTAssertGreaterThanOrEqual(result.patchSize.height, 24)
    }

    func testResolveExpandsPatchForLongTranslationsWithoutShrinkingFont() {
        let short = ScreenTranslationPatchLayout.resolve(
            sourceRect: CGRect(x: 0, y: 0, width: 420, height: 30),
            preferredFontSize: 18,
            translatedText: "短句翻译"
        )
        let long = ScreenTranslationPatchLayout.resolve(
            sourceRect: CGRect(x: 0, y: 0, width: 420, height: 30),
            preferredFontSize: 18,
            translatedText: String(repeating: "A long translated phrase that needs extra room. ", count: 12)
        )

        XCTAssertEqual(long.fontSize, short.fontSize)
        XCTAssertGreaterThan(long.patchSize.height, short.patchSize.height)
    }

    func testResolveCapsLargeTextAtMaximumFontSize() {
        let result = ScreenTranslationPatchLayout.resolve(
            sourceRect: CGRect(x: 0, y: 0, width: 800, height: 300),
            preferredFontSize: 40,
            translatedText: "Large translation"
        )

        XCTAssertEqual(result.fontSize, 22)
        XCTAssertEqual(result.padding, 3)
        XCTAssertEqual(result.cornerRadius, 3)
    }

    func testResolveExpandsPatchAndKeepsTextInsideIt() {
        let result = ScreenTranslationPatchLayout.resolve(
            sourceRect: CGRect(x: 100, y: 200, width: 300, height: 24),
            preferredFontSize: 18,
            translatedText: "This translation is longer than the original source line."
        )

        XCTAssertGreaterThanOrEqual(result.patchSize.width, 300)
        XCTAssertGreaterThanOrEqual(result.patchSize.height, 24)
        XCTAssertEqual(result.textFrame.origin.x, result.padding, accuracy: 0.001)
        XCTAssertEqual(result.textFrame.origin.y, result.padding, accuracy: 0.001)
        XCTAssertLessThanOrEqual(result.textFrame.origin.x + result.textFrame.size.width, result.patchSize.width)
        XCTAssertLessThanOrEqual(result.textFrame.origin.y + result.textFrame.size.height, result.patchSize.height)
    }

    func testResolveUsesTopLeadingTextPlacement() {
        let result = ScreenTranslationPatchLayout.resolve(
            sourceRect: CGRect(x: 0, y: 0, width: 220, height: 80),
            preferredFontSize: 16,
            translatedText: "Fallback"
        )

        XCTAssertGreaterThanOrEqual(result.textFrame.origin.x, 2)
        XCTAssertGreaterThanOrEqual(result.textFrame.origin.y, 2)
        XCTAssertGreaterThan(result.textFrame.size.width, 180)
        XCTAssertGreaterThan(result.textFrame.size.height, 50)
    }

    func testResolveKeepsLongTranslationCloseToTheRecognizedSourceBounds() {
        let result = ScreenTranslationPatchLayout.resolve(
            sourceRect: CGRect(x: 0, y: 0, width: 140, height: 40),
            preferredFontSize: 16,
            translatedText: "A very long translated sentence that must wrap inside the display bounds.",
            maximumPatchWidth: 148,
            maximumPatchHeight: 48
        )

        XCTAssertGreaterThanOrEqual(result.patchSize.width, 140)
        XCTAssertLessThanOrEqual(result.patchSize.width, 148)
        XCTAssertGreaterThanOrEqual(result.patchSize.height, 40)
        XCTAssertLessThanOrEqual(result.patchSize.height, 48)
    }

    func testResolveDoesNotGrowPatchAcrossTheScreenToFitLongTranslations() {
        let result = ScreenTranslationPatchLayout.resolve(
            sourceRect: CGRect(x: 0, y: 0, width: 140, height: 24),
            preferredFontSize: 18,
            translatedText: String(repeating: "A long translated sentence that needs room. ", count: 8),
            maximumPatchWidth: 148,
            maximumPatchHeight: 32
        )

        XCTAssertLessThanOrEqual(result.patchSize.width, 148)
        XCTAssertLessThanOrEqual(result.patchSize.height, 32)
        XCTAssertLessThan(result.fontSize, 18)
        XCTAssertGreaterThanOrEqual(result.fontSize, 8)
    }

    func testTextCacheReusesTranslationForNormalizedSourceText() {
        let now = Date(timeIntervalSince1970: 100)
        let originalKey = ScreenTranslationCacheKey(languageIdentifier: "ja-JP", text: "  日本語\nの 文  ")
        let equivalentKey = ScreenTranslationCacheKey(languageIdentifier: "ja", text: "日本語 の 文")
        var cache = ScreenTranslationTextCache(lifetime: 30)

        cache.store("Japanese text", for: originalKey, now: now)

        XCTAssertEqual(cache.translation(for: equivalentKey, now: now.addingTimeInterval(10)), "Japanese text")
        XCTAssertEqual(cache.count, 1)
    }

    func testTextCacheExpiresAndCanBeClearedAfterTextLeavesTheDisplay() {
        let now = Date(timeIntervalSince1970: 100)
        let key = ScreenTranslationCacheKey(languageIdentifier: "ko", text: "안녕하세요")
        var cache = ScreenTranslationTextCache(lifetime: 30)

        cache.store("Hello", for: key, now: now)
        XCTAssertEqual(cache.translation(for: key, now: now.addingTimeInterval(29)), "Hello")
        cache.refreshLifetime(for: key, now: now.addingTimeInterval(29))
        XCTAssertEqual(cache.translation(for: key, now: now.addingTimeInterval(58)), "Hello")
        XCTAssertNil(cache.translation(for: key, now: now.addingTimeInterval(59)))

        cache.removeExpired(now: now.addingTimeInterval(59))
        XCTAssertEqual(cache.count, 0)
    }

    func testStyleResolverUsesDarkTextOnLightBackground() {
        let image = makeSolidImage(red: 0.95, green: 0.95, blue: 0.95)
        let style = ScreenTranslationPatchStyleResolver.resolve(
            captureImage: image,
            captureRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            sourceRect: CGRect(x: 10, y: 10, width: 40, height: 30),
        )

        XCTAssertLessThan(style.foregroundColor.relativeTestLuminance, 0.5)
    }

    func testStyleResolverUsesLightTextOnDarkBackground() {
        let image = makeSolidImage(red: 0.05, green: 0.05, blue: 0.05)
        let style = ScreenTranslationPatchStyleResolver.resolve(
            captureImage: image,
            captureRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            sourceRect: CGRect(x: 10, y: 10, width: 40, height: 30),
        )

        XCTAssertGreaterThan(style.foregroundColor.relativeTestLuminance, 0.5)
    }

    func testStyleResolverReturnsOpaqueDefaultsWithoutImage() {
        let style = ScreenTranslationPatchStyleResolver.resolve(
            captureImage: nil,
            captureRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            sourceRect: CGRect(x: 10, y: 10, width: 40, height: 30),
        )

        XCTAssertEqual(style.backgroundColor.alphaComponent, 1, accuracy: 0.001)
        XCTAssertEqual(style.borderColor.alphaComponent, 1, accuracy: 0.001)
    }

    func testStyleResolverUsesOpaqueBackgroundToCoverSourceText() {
        let image = makeSolidImage(red: 0.95, green: 0.95, blue: 0.95)
        let style = ScreenTranslationPatchStyleResolver.resolve(
            captureImage: image,
            captureRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            sourceRect: CGRect(x: 10, y: 10, width: 40, height: 30),
        )

        XCTAssertEqual(style.backgroundColor.alphaComponent, 1, accuracy: 0.001)
        XCTAssertGreaterThan(style.backgroundColor.relativeTestLuminance, 0.9)
    }

    func testStyleResolverSamplesTheSourceRectInsteadOfImageOrigin() {
        let image = makeTopWhiteBottomBlackImage()
        let style = ScreenTranslationPatchStyleResolver.resolve(
            captureImage: image,
            captureRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            sourceRect: CGRect(x: 0, y: 0, width: 100, height: 50),
        )

        XCTAssertGreaterThan(style.foregroundColor.relativeTestLuminance, 0.5)
        XCTAssertLessThan(style.backgroundColor.relativeTestLuminance, 0.2)
    }

}

private func makeSolidImage(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
    let width = 10
    let height = 10
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for index in stride(from: 0, to: pixels.count, by: 4) {
        pixels[index] = UInt8(blue * 255)
        pixels[index + 1] = UInt8(green * 255)
        pixels[index + 2] = UInt8(red * 255)
        pixels[index + 3] = 255
    }
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}

private func makeTopWhiteBottomBlackImage() -> CGImage {
    let width = 10
    let height = 10
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        let value: UInt8 = y < height / 2 ? 255 : 0
        for x in 0..<width {
            let offset = (y * width + x) * 4
            pixels[offset] = value
            pixels[offset + 1] = value
            pixels[offset + 2] = value
            pixels[offset + 3] = 255
        }
    }
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}

private extension NSColor {
    var relativeTestLuminance: CGFloat {
        let color = usingColorSpace(.deviceRGB) ?? self
        return 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
    }
}
