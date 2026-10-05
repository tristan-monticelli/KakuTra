import XCTest
@testable import KakuTra

@MainActor
final class SettingsStoreMigrationTests: XCTestCase {
    private var testSuiteNames = Set<String>()

    private func makeDefaults(testName: String = #function) -> UserDefaults {
        let suiteName = "SettingsStoreMigrationTests.\(testName)"
        testSuiteNames.insert(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    override func tearDown() {
        for suiteName in testSuiteNames {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        testSuiteNames.removeAll()
        super.tearDown()
    }

    func testSelectedTextTranslationDefaultsToEnabled() {
        let defaults = makeDefaults()

        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertTrue(settings.selectedTextTranslationEnabled)
    }

    func testLegacyTargetAndBidirectionalPreferencesMigrateToEnglishOnly() {
        let defaults = makeDefaults()
        defaults.set("ja", forKey: AppSettingKey.targetLanguage)
        defaults.set(true, forKey: AppSettingKey.bidirectionalTranslationEnabled)

        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertEqual(settings.targetLanguage, "en")
        XCTAssertEqual(defaults.string(forKey: AppSettingKey.targetLanguage), "en")
        XCTAssertNil(defaults.object(forKey: AppSettingKey.bidirectionalTranslationEnabled))
    }

    func testOCRLanguageFilterAcceptsOnlyJapaneseChineseAndKorean() {
        XCTAssertEqual(LanguageClassificationService.supportedOCRLanguage(for: "こんにちは"), "ja")
        XCTAssertEqual(LanguageClassificationService.supportedOCRLanguage(for: "你好世界"), "zh")
        XCTAssertEqual(LanguageClassificationService.supportedOCRLanguage(for: "안녕하세요"), "ko")
        XCTAssertNil(LanguageClassificationService.supportedOCRLanguage(for: "Hello world"))
    }

    func testOCRLineTranslationIsDisabledByDefaultAndPersists() {
        let defaults = makeDefaults()
        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertFalse(settings.translateOCRLineWithWord)
        settings.translateOCRLineWithWord = true
        XCTAssertEqual(defaults.object(forKey: AppSettingKey.translateOCRLineWithWord) as? Bool, true)
    }

    func testOCRLineTranslationMigratesPreviousSentenceTranslationPreference() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: AppSettingKey.ocrSentenceTranslationEnabled)

        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertFalse(settings.translateOCRLineWithWord)
        XCTAssertNil(defaults.object(forKey: AppSettingKey.ocrSentenceTranslationEnabled))
    }

    func testMenuBarIconStyleDefaultsToAuto() {
        let defaults = makeDefaults()

        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertEqual(settings.menuBarIconStyle, .auto)
        XCTAssertEqual(defaults.string(forKey: AppSettingKey.menuBarIconStyle), MenuBarIconStyle.auto.rawValue)
    }

    func testLoadsPersistedMenuBarIconStyle() {
        let defaults = makeDefaults()
        defaults.set(MenuBarIconStyle.black.rawValue, forKey: AppSettingKey.menuBarIconStyle)

        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertEqual(settings.menuBarIconStyle, .black)
    }

    func testHideOriginalTextInSentenceOverlayDefaultsToEnabled() {
        let defaults = makeDefaults()

        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertTrue(settings.hideOriginalTextInSentenceOverlay)
        XCTAssertEqual(
            defaults.object(forKey: AppSettingKey.hideOriginalTextInSentenceOverlay) as? Bool,
            true
        )
    }

    func testLoadsPersistedHideOriginalTextInSentenceOverlaySetting() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppSettingKey.hideOriginalTextInSentenceOverlay)

        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertTrue(settings.hideOriginalTextInSentenceOverlay)
    }

    func testRemovedTrackingPreferencesAreDeletedDuringMigration() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: AppSettingKey.continuousTranslation)
        defaults.set(true, forKey: AppSettingKey.keepWordOverlayAfterTap)

        _ = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertNil(defaults.object(forKey: AppSettingKey.continuousTranslation))
        XCTAssertNil(defaults.object(forKey: AppSettingKey.keepWordOverlayAfterTap))
    }

    func testAnkiConfigurationPreferencesLoadAndPersist() {
        let defaults = makeDefaults()
        defaults.set("Japanese", forKey: AppSettingKey.ankiDeckName)
        defaults.set("Basic", forKey: AppSettingKey.ankiModelName)
        defaults.set(["term": "Front", "definition": "Back"], forKey: AppSettingKey.ankiFieldMappings)
        defaults.set("kakutra study", forKey: AppSettingKey.ankiTags)

        let store = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertEqual(store.ankiDeckName, "Japanese")
        XCTAssertEqual(store.ankiModelName, "Basic")
        XCTAssertEqual(store.ankiFieldMappings, ["term": "Front", "definition": "Back"])
        XCTAssertEqual(store.ankiTags, "kakutra study")
        store.ankiDeckName = "Japanese::N4"
        XCTAssertEqual(defaults.string(forKey: AppSettingKey.ankiDeckName), "Japanese::N4")
    }
}

@MainActor
final class SelectedTextLookupRoutingTests: XCTestCase {
    func testInsideSelectionRoutesToSelectedTextTranslation() {
        let snapshot = SelectedTextSnapshot(
            text: "Hello world",
            selectedRange: NSRange(location: 0, length: 11),
            bounds: CGRect(x: 100, y: 100, width: 120, height: 24),
            sourceAppIdentifier: "com.apple.TextEdit"
        )

        let intent = SinglePressLookupRouter.resolve(
            mouseLocation: CGPoint(x: 140, y: 110),
            isSelectedTextTranslationSupported: true,
            isSelectedTextTranslationEnabled: true,
            hasAccessibilityPermission: true,
            selectionSnapshot: snapshot
        )

        XCTAssertEqual(intent, .selectedTextSentence(snapshot))
    }

    func testAccessibilitySnapshotWithoutBoundsButKnownRangeRoutesToSelectedTextTranslation() {
        let snapshot = SelectedTextSnapshot(
            text: "Hello world",
            selectedRange: NSRange(location: 0, length: 11),
            bounds: nil,
            sourceAppIdentifier: "com.apple.TextEdit"
        )

        let intent = SinglePressLookupRouter.resolve(
            mouseLocation: CGPoint(x: 260, y: 200),
            isSelectedTextTranslationSupported: true,
            isSelectedTextTranslationEnabled: true,
            hasAccessibilityPermission: true,
            selectionSnapshot: snapshot
        )

        XCTAssertEqual(intent, .selectedTextSentence(snapshot))
    }

    func testAccessibilitySnapshotWithoutBoundsAndUnknownRangeFallsBackToOcrWord() {
        let snapshot = SelectedTextSnapshot(
            text: "Hello world",
            selectedRange: NSRange(location: NSNotFound, length: 11),
            bounds: nil,
            sourceAppIdentifier: "com.example.Unknown"
        )

        let intent = SinglePressLookupRouter.resolve(
            mouseLocation: CGPoint(x: 260, y: 200),
            isSelectedTextTranslationSupported: true,
            isSelectedTextTranslationEnabled: true,
            hasAccessibilityPermission: true,
            selectionSnapshot: snapshot
        )

        XCTAssertEqual(intent, .ocrWord)
    }

    func testMouseOutsideBoundsWithKnownRangeRoutesToSelectedTextTranslation() {
        let snapshot = SelectedTextSnapshot(
            text: "Hello world",
            selectedRange: NSRange(location: 0, length: 11),
            bounds: CGRect(x: 100, y: 100, width: 120, height: 24),
            sourceAppIdentifier: "com.apple.TextEdit"
        )

        let intent = SinglePressLookupRouter.resolve(
            mouseLocation: CGPoint(x: 260, y: 200),
            isSelectedTextTranslationSupported: true,
            isSelectedTextTranslationEnabled: true,
            hasAccessibilityPermission: true,
            selectionSnapshot: snapshot
        )

        XCTAssertEqual(intent, .selectedTextSentence(snapshot))
    }

    func testMouseNearSelectionEdgeRoutesToSelectedTextTranslation() {
        let snapshot = SelectedTextSnapshot(
            text: "Hello world",
            selectedRange: NSRange(location: 0, length: 11),
            bounds: CGRect(x: 100, y: 100, width: 120, height: 24),
            sourceAppIdentifier: "com.apple.TextEdit"
        )

        let intent = SinglePressLookupRouter.resolve(
            mouseLocation: CGPoint(x: 96, y: 110),
            isSelectedTextTranslationSupported: true,
            isSelectedTextTranslationEnabled: true,
            hasAccessibilityPermission: true,
            selectionSnapshot: snapshot
        )

        XCTAssertEqual(intent, .selectedTextSentence(snapshot))
    }

    func testOversizedSelectionBoundsWithKnownRangeRoutesToSelectedTextTranslation() {
        let snapshot = SelectedTextSnapshot(
            text: "Hello world",
            selectedRange: NSRange(location: 0, length: 11),
            bounds: CGRect(x: 100, y: 100, width: 1400, height: 700),
            sourceAppIdentifier: "com.microsoft.teams2"
        )

        let intent = SinglePressLookupRouter.resolve(
            mouseLocation: CGPoint(x: 140, y: 110),
            isSelectedTextTranslationSupported: true,
            isSelectedTextTranslationEnabled: true,
            hasAccessibilityPermission: true,
            selectionSnapshot: snapshot
        )

        XCTAssertEqual(intent, .selectedTextSentence(snapshot))
    }

    func testInvisibleSelectedTextFallsBackToOcrWord() {
        let snapshot = SelectedTextSnapshot(
            text: "\u{200B}\u{FFFC}",
            selectedRange: NSRange(location: 0, length: 2),
            bounds: CGRect(x: 100, y: 100, width: 120, height: 24),
            sourceAppIdentifier: "com.microsoft.teams2"
        )

        let intent = SinglePressLookupRouter.resolve(
            mouseLocation: CGPoint(x: 140, y: 110),
            isSelectedTextTranslationSupported: true,
            isSelectedTextTranslationEnabled: true,
            hasAccessibilityPermission: true,
            selectionSnapshot: snapshot
        )

        XCTAssertEqual(intent, .ocrWord)
    }

    func testMissingAccessibilityFallsBackToOcrWord() {
        let snapshot = SelectedTextSnapshot(
            text: "Hello world",
            selectedRange: NSRange(location: 0, length: 11),
            bounds: CGRect(x: 100, y: 100, width: 120, height: 24),
            sourceAppIdentifier: "com.apple.TextEdit"
        )

        let intent = SinglePressLookupRouter.resolve(
            mouseLocation: CGPoint(x: 140, y: 110),
            isSelectedTextTranslationSupported: true,
            isSelectedTextTranslationEnabled: true,
            hasAccessibilityPermission: false,
            selectionSnapshot: snapshot
        )

        XCTAssertEqual(intent, .ocrWord)
    }

    func testDisabledSelectedTextFeatureFallsBackToOcrWord() {
        let snapshot = SelectedTextSnapshot(
            text: "Hello world",
            selectedRange: NSRange(location: 0, length: 11),
            bounds: CGRect(x: 100, y: 100, width: 120, height: 24),
            sourceAppIdentifier: "com.apple.TextEdit"
        )

        let intent = SinglePressLookupRouter.resolve(
            mouseLocation: CGPoint(x: 140, y: 110),
            isSelectedTextTranslationSupported: true,
            isSelectedTextTranslationEnabled: false,
            hasAccessibilityPermission: true,
            selectionSnapshot: snapshot
        )

        XCTAssertEqual(intent, .ocrWord)
    }

    func testUnsupportedSelectedTextCapabilityFallsBackToOcrWord() {
        let snapshot = SelectedTextSnapshot(
            text: "Hello world",
            selectedRange: NSRange(location: 0, length: 11),
            bounds: CGRect(x: 100, y: 100, width: 120, height: 24),
            sourceAppIdentifier: "com.apple.TextEdit"
        )

        let intent = SinglePressLookupRouter.resolve(
            mouseLocation: CGPoint(x: 140, y: 110),
            isSelectedTextTranslationSupported: false,
            isSelectedTextTranslationEnabled: true,
            hasAccessibilityPermission: true,
            selectionSnapshot: snapshot
        )

        XCTAssertEqual(intent, .ocrWord)
    }
}
