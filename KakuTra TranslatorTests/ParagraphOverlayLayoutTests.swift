import XCTest
@testable import KakuTra

final class ParagraphOverlayLayoutTests: XCTestCase {
    func testResolveKeepsPanelBelowWhenBelowSideFitsNaturalHeight() {
        let result = ParagraphOverlayLayout.resolve(
            naturalPanelHeight: 240,
            spaceBelow: 520,
            spaceAbove: 180
        )

        XCTAssertEqual(result.placement, .below)
        XCTAssertEqual(
            result.maxPanelHeight,
            520 - ParagraphOverlayLayout.gap - ParagraphOverlayLayout.edgeInset,
            accuracy: 0.001
        )
    }

    func testResolveUsesAboveWhenOnlyAboveSideFitsNaturalHeight() {
        let result = ParagraphOverlayLayout.resolve(
            naturalPanelHeight: 240,
            spaceBelow: 180,
            spaceAbove: 520
        )

        XCTAssertEqual(result.placement, .above)
        XCTAssertEqual(
            result.maxPanelHeight,
            520 - ParagraphOverlayLayout.gap - ParagraphOverlayLayout.edgeInset,
            accuracy: 0.001
        )
    }

    func testResolveChoosesLargerSideWhenNeitherSideFitsNaturalHeight() {
        let result = ParagraphOverlayLayout.resolve(
            naturalPanelHeight: 640,
            spaceBelow: 420,
            spaceAbove: 300
        )

        XCTAssertEqual(result.placement, .below)
        XCTAssertEqual(
            result.maxPanelHeight,
            420 - ParagraphOverlayLayout.gap - ParagraphOverlayLayout.edgeInset,
            accuracy: 0.001
        )
    }

    func testAttributedBuilderUsesHangingIndentForListItems() throws {
        let attributedText = ParagraphTextAttributedStringBuilder.build(
            text: "• Unlimited multi-agent parallel execution",
            font: .systemFont(ofSize: 13, weight: .medium),
            textColor: .labelColor,
            preferredLineHeight: 20
        )

        let style = try XCTUnwrap(
            attributedText.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        )

        XCTAssertEqual(style.firstLineHeadIndent, 0, accuracy: 0.001)
        XCTAssertGreaterThan(style.headIndent, 0)
    }

    func testAttributedBuilderKeepsPlainParagraphZeroIndent() throws {
        let attributedText = ParagraphTextAttributedStringBuilder.build(
            text: "Visual interface combined with command-line power",
            font: .systemFont(ofSize: 13, weight: .medium),
            textColor: .labelColor,
            preferredLineHeight: 20
        )

        let style = try XCTUnwrap(
            attributedText.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        )

        XCTAssertEqual(style.firstLineHeadIndent, 0, accuracy: 0.001)
        XCTAssertEqual(style.headIndent, 0, accuracy: 0.001)
    }

    func testParagraphFontSizingAllowsLimitedUpsizingFromPreferredSize() {
        let fontSize = ParagraphFontSizing.optimalFontSize(
            preferredFontSize: 14,
            originalText: "Master Plan",
            containerWidth: 520,
            horizontalPadding: 18
        )

        XCTAssertEqual(
            fontSize,
            min(14 * ParagraphFontSizing.preferredUpscaleFactor, ParagraphFontSizing.maxFontSize),
            accuracy: 0.01
        )
    }

    func testParagraphFontSizingKeepsOriginalLongestLineWithinAvailableWidth() {
        let originalText = "This original line should cap the display size before it wraps in the panel"
        let targetFontSize = min(18 * ParagraphFontSizing.preferredUpscaleFactor, ParagraphFontSizing.maxFontSize)
        let targetWidth = ParagraphFontSizing.maximumLineWidth(
            for: originalText,
            font: .systemFont(ofSize: targetFontSize, weight: .medium)
        )
        let availableWidth = floor(targetWidth * 0.7)
        let containerWidth = availableWidth + 36

        let fontSize = ParagraphFontSizing.optimalFontSize(
            preferredFontSize: 18,
            originalText: originalText,
            containerWidth: containerWidth,
            horizontalPadding: 18
        )

        XCTAssertLessThan(fontSize, targetFontSize)

        let measuredWidth = ParagraphFontSizing.maximumLineWidth(
            for: originalText,
            font: .systemFont(ofSize: fontSize, weight: .medium)
        )
        XCTAssertLessThanOrEqual(measuredWidth, availableWidth + 0.5)
    }

    func testParagraphFontSizingIgnoresTranslationLengthWhenUpsizingOriginalText() {
        let shortOriginal = "Master Plan"
        let fontSize = ParagraphFontSizing.optimalFontSize(
            preferredFontSize: 14,
            originalText: shortOriginal,
            containerWidth: 520,
            horizontalPadding: 18
        )

        XCTAssertGreaterThan(fontSize, 14)
    }

    func testOutsideClickPolicyDismissesPinnedParagraphOverlayOutsideProtectedFrames() {
        let shouldDismiss = ParagraphOutsideClickDismissalPolicy.shouldDismiss(
            mouseLocation: CGPoint(x: 500, y: 500),
            isSentenceTranslationPresented: true,
            isParagraphOverlayPinned: true,
            protectedFrames: [
                CGRect(x: 100, y: 100, width: 200, height: 120),
                CGRect(x: 320, y: 100, width: 120, height: 40),
            ]
        )

        XCTAssertTrue(shouldDismiss)
    }

    func testOutsideClickPolicyKeepsOverlayClicks() {
        let shouldDismiss = ParagraphOutsideClickDismissalPolicy.shouldDismiss(
            mouseLocation: CGPoint(x: 150, y: 150),
            isSentenceTranslationPresented: true,
            isParagraphOverlayPinned: true,
            protectedFrames: [CGRect(x: 100, y: 100, width: 200, height: 120)]
        )

        XCTAssertFalse(shouldDismiss)
    }

    func testOutsideClickPolicyKeepsParagraphRegionClicks() {
        let paragraphRect = CGRect(x: 320, y: 100, width: 120, height: 40)

        let shouldDismiss = ParagraphOutsideClickDismissalPolicy.shouldDismiss(
            mouseLocation: CGPoint(x: 315, y: 118),
            isSentenceTranslationPresented: true,
            isParagraphOverlayPinned: true,
            protectedFrames: [
                CGRect(x: 100, y: 100, width: 200, height: 120),
                paragraphRect,
            ]
        )

        XCTAssertFalse(shouldDismiss)
    }

    func testOutsideClickPolicyOnlyDismissesPinnedParagraphOverlay() {
        XCTAssertFalse(ParagraphOutsideClickDismissalPolicy.shouldDismiss(
            mouseLocation: CGPoint(x: 500, y: 500),
            isSentenceTranslationPresented: false,
            isParagraphOverlayPinned: true,
            protectedFrames: []
        ))

        XCTAssertFalse(ParagraphOutsideClickDismissalPolicy.shouldDismiss(
            mouseLocation: CGPoint(x: 500, y: 500),
            isSentenceTranslationPresented: true,
            isParagraphOverlayPinned: false,
            protectedFrames: []
        ))
    }



    func testPersistentOverlayApplicationActivationPolicyDismissesForAnotherApplication() {
        XCTAssertTrue(PersistentOverlayApplicationActivationPolicy.shouldDismiss(
            isPersistentOverlayPresented: true,
            sourceApplicationProcessIdentifier: 100,
            activatedApplicationProcessIdentifier: 200,
            ownApplicationProcessIdentifier: 300
        ))
    }

    func testPersistentOverlayApplicationActivationPolicyKeepsSourceApplication() {
        XCTAssertFalse(PersistentOverlayApplicationActivationPolicy.shouldDismiss(
            isPersistentOverlayPresented: true,
            sourceApplicationProcessIdentifier: 100,
            activatedApplicationProcessIdentifier: 100,
            ownApplicationProcessIdentifier: 300
        ))
    }

    func testPersistentOverlayApplicationActivationPolicyKeepsKakuTraActivation() {
        XCTAssertFalse(PersistentOverlayApplicationActivationPolicy.shouldDismiss(
            isPersistentOverlayPresented: true,
            sourceApplicationProcessIdentifier: 100,
            activatedApplicationProcessIdentifier: 300,
            ownApplicationProcessIdentifier: 300
        ))
    }

    func testPersistentOverlayApplicationActivationPolicyIgnoresTemporaryOverlay() {
        XCTAssertFalse(PersistentOverlayApplicationActivationPolicy.shouldDismiss(
            isPersistentOverlayPresented: false,
            sourceApplicationProcessIdentifier: 100,
            activatedApplicationProcessIdentifier: 200,
            ownApplicationProcessIdentifier: 300
        ))
    }

    func testTapKeptOverlayPersistenceDismissesAfterThresholdMovementOutsideOverlay() {
        let shouldDismiss = TapKeptOverlayPersistencePolicy.shouldDismissOnMouseMove(
            startLocation: CGPoint(x: 100, y: 100),
            currentLocation: CGPoint(x: 140, y: 100),
            overlayFrame: CGRect(x: 200, y: 200, width: 180, height: 120),
            movementThreshold: 16
        )

        XCTAssertTrue(shouldDismiss)
    }

    func testTapKeptOverlayPersistenceKeepsMovementInsideOverlayFrame() {
        let shouldDismiss = TapKeptOverlayPersistencePolicy.shouldDismissOnMouseMove(
            startLocation: CGPoint(x: 100, y: 100),
            currentLocation: CGPoint(x: 220, y: 220),
            overlayFrame: CGRect(x: 200, y: 200, width: 180, height: 120),
            movementThreshold: 16
        )

        XCTAssertFalse(shouldDismiss)
    }

    func testTapKeptOverlayPersistenceKeepsVerticalMovementTowardOffsetOverlay() {
        let shouldDismiss = TapKeptOverlayPersistencePolicy.shouldDismissOnMouseMove(
            startLocation: CGPoint(x: 100, y: 100),
            currentLocation: CGPoint(x: 100, y: 84),
            overlayFrame: CGRect(x: 112, y: 20, width: 180, height: 80),
            movementThreshold: 16
        )

        XCTAssertFalse(shouldDismiss)
    }

    func testEscapeMonitoringPolicyCoversPersistentParagraphAndTapKeptOverlays() {
        XCTAssertTrue(OverlayEscapeDismissalPolicy.shouldMonitor(
            isParagraphOverlayPresented: true,
            isTapKeptOverlayPresented: false
        ))

        XCTAssertTrue(OverlayEscapeDismissalPolicy.shouldMonitor(
            isParagraphOverlayPresented: false,
            isTapKeptOverlayPresented: true
        ))

        XCTAssertFalse(OverlayEscapeDismissalPolicy.shouldMonitor(
            isParagraphOverlayPresented: false,
            isTapKeptOverlayPresented: false
        ))
    }

    func testParagraphOverlayControlPolicyShowsCloseForTapKeptOverlay() {
        XCTAssertTrue(ParagraphOverlayControlPolicy.showsPinButton(
            isParagraphOverlayMode: true,
            isParagraphOverlayPinned: false,
            isTapKeptOverlay: false
        ))

        XCTAssertFalse(ParagraphOverlayControlPolicy.showsPinButton(
            isParagraphOverlayMode: true,
            isParagraphOverlayPinned: false,
            isTapKeptOverlay: true
        ))

        XCTAssertFalse(ParagraphOverlayControlPolicy.showsPinButton(
            isParagraphOverlayMode: true,
            isParagraphOverlayPinned: true,
            isTapKeptOverlay: false
        ))
    }

    func testWordOverlayHeaderLayoutReservesControlsOutsideIdentityGroup() {
        let metrics = WordOverlayHeaderLayoutPolicy.resolve(
            panelWidth: 380,
            horizontalPadding: 18,
            controlGroupWidth: 54,
            gapBetweenIdentityAndControls: 12
        )

        XCTAssertEqual(metrics.identityGroupMaxWidth, 278, accuracy: 0.001)
        XCTAssertEqual(metrics.titleMaxWidth, 278, accuracy: 0.001)
    }

    func testWordOverlayHeaderLayoutKeepsPhoneticBadgeReadable() {
        let metrics = WordOverlayHeaderLayoutPolicy.resolve(
            panelWidth: 380,
            horizontalPadding: 18,
            controlGroupWidth: 54,
            gapBetweenIdentityAndControls: 12
        )

        XCTAssertFalse(metrics.allowsPhoneticBadgeHorizontalCompression)
    }

    func testWordOverlayHeaderLayoutNormalizesDisplayedPhonetic() {
        XCTAssertEqual(
            WordOverlayHeaderLayoutPolicy.displayedPhonetic("  pəˈtɪkjʊlə  "),
            "pəˈtɪkjʊlə"
        )
        XCTAssertNil(WordOverlayHeaderLayoutPolicy.displayedPhonetic(" \n\t "))
        XCTAssertNil(WordOverlayHeaderLayoutPolicy.displayedPhonetic(nil))
    }

    func testKatakanaOCRHeadwordIsPreservedWhenDictionaryMatchesHiraganaForm() {
        XCTAssertEqual(
            WordOverlayHeaderLayoutPolicy.displayedHeadword(
                ocrText: "カタカナ",
                dictionaryTerm: "かたかな"
            ),
            "カタカナ"
        )
    }

    func testDictionaryHeadwordRemainsCanonicalWhenItIsNotKanaEquivalent() {
        XCTAssertEqual(
            WordOverlayHeaderLayoutPolicy.displayedHeadword(
                ocrText: "コーヒー",
                dictionaryTerm: "珈琲"
            ),
            "珈琲"
        )
    }

    func testKanaHeadwordDoesNotShowUnrelatedOCRLineAsItsReading() {
        let fullOCRLine = "ザットビットベターオンユアオウン"
        XCTAssertNil(
            WordOverlayHeaderLayoutPolicy.displayedDictionaryReading(
                reading: fullOCRLine,
                for: "ざっと",
                sourceLanguageIdentifier: "ja"
            )
        )
    }

    func testKanaHeadwordKeepsEquivalentKatakanaReading() {
        XCTAssertEqual(
            WordOverlayHeaderLayoutPolicy.displayedDictionaryReading(
                reading: "ザット",
                for: "ざっと",
                sourceLanguageIdentifier: "ja"
            ),
            "ザット"
        )
    }

    func testKanjiHeadwordKeepsDictionaryReading() {
        XCTAssertEqual(
            WordOverlayHeaderLayoutPolicy.displayedDictionaryReading(
                reading: "たべる",
                for: "食べる",
                sourceLanguageIdentifier: "ja"
            ),
            "たべる"
        )
    }

    func testLatinTranscriptionUsesJapaneseDictionaryReadingForRomaji() {
        XCTAssertEqual(
            WordOverlayHeaderLayoutPolicy.latinTranscription(
                for: "食べる",
                sourceLanguageIdentifier: "ja",
                dictionaryReading: "たべる"
            ),
            "taberu"
        )
    }

    func testLatinTranscriptionDoesNotMisreadJapaneseKanjiAsMandarin() {
        XCTAssertNil(
            WordOverlayHeaderLayoutPolicy.latinTranscription(
                for: "日本語",
                sourceLanguageIdentifier: "ja",
                dictionaryReading: nil
            )
        )
    }

    func testLatinTranscriptionUsesLanguageAppropriateAppleTransforms() {
        XCTAssertEqual(
            WordOverlayHeaderLayoutPolicy.latinTranscription(
                for: "你好",
                sourceLanguageIdentifier: "zh-Hans",
                dictionaryReading: nil
            ),
            "nǐ hǎo"
        )
        XCTAssertEqual(
            WordOverlayHeaderLayoutPolicy.latinTranscription(
                for: "안녕하세요",
                sourceLanguageIdentifier: "ko",
                dictionaryReading: nil
            ),
            "annyeonghaseyo"
        )
    }

    func testLatinTranscriptionIsOmittedForLatinTextAndUnsupportedLanguages() {
        XCTAssertNil(
            WordOverlayHeaderLayoutPolicy.latinTranscription(
                for: "hello",
                sourceLanguageIdentifier: "en",
                dictionaryReading: nil
            )
        )
        XCTAssertNil(
            WordOverlayHeaderLayoutPolicy.latinTranscription(
                for: "hello",
                sourceLanguageIdentifier: "ja",
                dictionaryReading: nil
            )
        )
    }

    func testOriginalVisibilityShowsEditableOriginalWhenHideSettingIsOffAndOverlayIsPinned() {
        let decision = ParagraphOriginalVisibilityPolicy.resolve(
            hasOriginalText: true,
            isParagraphOverlayPinned: true,
            hidesOriginalTextSetting: false,
            isOriginalEditorExpanded: false,
            isManualInputFallback: false
        )

        XCTAssertTrue(decision.showsOriginalTextRegion)
        XCTAssertTrue(decision.usesEditableOriginalText)
        XCTAssertFalse(decision.showsOriginalEditorToggle)
        XCTAssertFalse(decision.hidesOriginalTextRegion)
    }

    func testOriginalVisibilityHidesOriginalWhenHideSettingIsOnAndPinnedEditorIsCollapsed() {
        let decision = ParagraphOriginalVisibilityPolicy.resolve(
            hasOriginalText: true,
            isParagraphOverlayPinned: true,
            hidesOriginalTextSetting: true,
            isOriginalEditorExpanded: false,
            isManualInputFallback: false
        )

        XCTAssertFalse(decision.showsOriginalTextRegion)
        XCTAssertFalse(decision.usesEditableOriginalText)
        XCTAssertTrue(decision.showsOriginalEditorToggle)
        XCTAssertTrue(decision.hidesOriginalTextRegion)
    }

    func testOriginalVisibilityShowsEditableFallbackWhenHideSettingIsOnAndPinnedOriginalTextIsMissing() {
        let decision = ParagraphOriginalVisibilityPolicy.resolve(
            hasOriginalText: false,
            isParagraphOverlayPinned: true,
            hidesOriginalTextSetting: true,
            isOriginalEditorExpanded: false,
            isManualInputFallback: false
        )

        XCTAssertTrue(decision.showsOriginalTextRegion)
        XCTAssertTrue(decision.usesEditableOriginalText)
        XCTAssertFalse(decision.showsOriginalEditorToggle)
        XCTAssertFalse(decision.hidesOriginalTextRegion)
    }

    func testOriginalVisibilityKeepsManualInputFallbackVisibleAfterTextEntry() {
        let decision = ParagraphOriginalVisibilityPolicy.resolve(
            hasOriginalText: true,
            isParagraphOverlayPinned: true,
            hidesOriginalTextSetting: true,
            isOriginalEditorExpanded: false,
            isManualInputFallback: true
        )

        XCTAssertTrue(decision.showsOriginalTextRegion)
        XCTAssertTrue(decision.usesEditableOriginalText)
        XCTAssertFalse(decision.showsOriginalEditorToggle)
        XCTAssertFalse(decision.hidesOriginalTextRegion)
    }

    func testOriginalVisibilityShowsEditableOriginalWhenHideSettingIsOnAndPinnedEditorIsExpanded() {
        let decision = ParagraphOriginalVisibilityPolicy.resolve(
            hasOriginalText: true,
            isParagraphOverlayPinned: true,
            hidesOriginalTextSetting: true,
            isOriginalEditorExpanded: true,
            isManualInputFallback: false
        )

        XCTAssertTrue(decision.showsOriginalTextRegion)
        XCTAssertTrue(decision.usesEditableOriginalText)
        XCTAssertTrue(decision.showsOriginalEditorToggle)
        XCTAssertFalse(decision.hidesOriginalTextRegion)
    }

    func testOriginalVisibilityHidesOriginalWhenHideSettingIsOnAndOverlayIsNotPinned() {
        let decision = ParagraphOriginalVisibilityPolicy.resolve(
            hasOriginalText: true,
            isParagraphOverlayPinned: false,
            hidesOriginalTextSetting: true,
            isOriginalEditorExpanded: true,
            isManualInputFallback: false
        )

        XCTAssertFalse(decision.showsOriginalTextRegion)
        XCTAssertFalse(decision.usesEditableOriginalText)
        XCTAssertFalse(decision.showsOriginalEditorToggle)
        XCTAssertTrue(decision.hidesOriginalTextRegion)
    }

    func testOriginalVisibilityShowsOriginalWhenNoTranslationOutputExists() {
        let decision = ParagraphOriginalVisibilityPolicy.resolve(
            hasOriginalText: true,
            isParagraphOverlayPinned: false,
            hidesOriginalTextSetting: true,
            isOriginalEditorExpanded: false,
            isManualInputFallback: false,
            hasTranslationOutput: false
        )

        XCTAssertTrue(decision.showsOriginalTextRegion)
        XCTAssertFalse(decision.usesEditableOriginalText)
        XCTAssertFalse(decision.showsOriginalEditorToggle)
        XCTAssertFalse(decision.hidesOriginalTextRegion)
    }
}
