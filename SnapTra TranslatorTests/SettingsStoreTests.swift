import XCTest
@testable import KakuTra

@MainActor
final class LookupLanguagePairTests: XCTestCase {
    func testFixedLanguagePairPreservesIdentifiers() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "ja")

        XCTAssertEqual(pair.sourceIdentifier, "en")
        XCTAssertEqual(pair.targetIdentifier, "ja")
    }

    func testSameLanguageDetection() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "en")
        XCTAssertTrue(pair.isSameLanguage)
    }

    func testDifferentLanguageDetection() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "zh-Hans")
        XCTAssertFalse(pair.isSameLanguage)
    }
}

@MainActor
final class SettingsStoreMigrationTests: XCTestCase {
    private let testKeys: [String] = [
        AppSettingKey.playPronunciation,
        AppSettingKey.playWordPronunciation,
        AppSettingKey.playSentencePronunciation,
        AppSettingKey.launchAtLogin,
        AppSettingKey.showMenuBarIcon,
        AppSettingKey.menuBarIconStyle,
        AppSettingKey.showDockIcon,
        AppSettingKey.singleKey,
        AppSettingKey.sourceLanguage,
        AppSettingKey.targetLanguage,
        AppSettingKey.bidirectionalTranslationEnabled,
        AppSettingKey.debugShowOcrRegion,
        AppSettingKey.continuousTranslation,
        AppSettingKey.keepWordOverlayAfterTap,
        AppSettingKey.wordTTSProvider,
        AppSettingKey.sentenceTTSProvider,
        AppSettingKey.appLanguage,
        AppSettingKey.englishAccent,
        AppSettingKey.legacySentenceTranslationEnabled,
        AppSettingKey.ocrSentenceTranslationEnabled,
        AppSettingKey.doubleTapSentenceTranslationMode,
        AppSettingKey.selectedTextTranslationEnabled,
        AppSettingKey.hideOriginalTextInSentenceOverlay,
        AppSettingKey.sentenceTranslationPresentationMode,
        AppSettingKey.imageTranslationSource,
        AppSettingKey.imageTranslationSourceEnabled,
        AppSettingKey.autoCheckUpdates,
        AppSettingKey.updateChannel,
        AppSettingKey.debugShowChannelSelector,
        "sentenceTranslationSources",
        "llmProviderConfigurations",
        "imageTranslationProviderConfigurations",
        AppSettingKey.ankiDeckName,
        AppSettingKey.ankiModelName,
        AppSettingKey.ankiFieldMappings,
        AppSettingKey.ankiTags,
    ]

    private func makeDefaults(testName: String = #function) -> UserDefaults {
        let suiteName = "SettingsStoreMigrationTests.\(testName)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        reset(defaults)
        return defaults
    }

    override func tearDown() {
        reset(.standard)
        super.tearDown()
    }

    private func reset(_ defaults: UserDefaults) {
        for key in testKeys {
            defaults.removeObject(forKey: key)
        }
    }

    func testSentenceTranslationSourceMigrationAppendsLLMProvidersDisabled() {
        let existing: [SentenceTranslationSource] = [
            SentenceTranslationSource(id: UUID(), type: .native, isEnabled: true),
            SentenceTranslationSource(id: UUID(), type: .google, isEnabled: true),
            SentenceTranslationSource(id: UUID(), type: .youdao, isEnabled: false),
        ]

        let migrated = SettingsStore.migrateSentenceTranslationSources(existing)

        XCTAssertEqual(migrated.prefix(3).map(\.type), [.native, .google, .youdao])
        XCTAssertTrue(migrated[0].isEnabled)
        XCTAssertTrue(migrated[1].isEnabled)
        XCTAssertFalse(migrated[2].isEnabled)
        XCTAssertEqual(
            migrated.filter { $0.type.isLLMProvider }.map(\.type),
            SentenceTranslationSource.SourceType.llmProviderTypes
        )
        XCTAssertTrue(migrated.filter { $0.type.isLLMProvider }.allSatisfy { !$0.isEnabled })
    }

    func testZhipuProviderNameUsesLocalizedEnglishDisplayName() {
        let localizationManager = LocalizationManager.shared
        localizationManager.setLanguage(.english)
        defer { localizationManager.setLanguage(.system) }

        XCTAssertEqual(SentenceTranslationSource.SourceType.zhipu.displayName, "Zhipu")
    }

    func testDefaultLLMProviderConfigurations() {
        let configurations = SettingsStore.defaultLLMProviderConfigurations()

        XCTAssertEqual(
            configurations.map(\.provider),
            SentenceTranslationSource.SourceType.llmProviderTypes
        )
        XCTAssertEqual(
            configurations.first { $0.provider == .openAI }?.baseURL,
            "https://api.openai.com/v1"
        )
        XCTAssertEqual(
            configurations.first { $0.provider == .anthropic }?.model,
            "claude-haiku-4-5"
        )
        XCTAssertEqual(
            configurations.first { $0.provider == .gemini }?.model,
            "gemini-3.5-flash"
        )
        XCTAssertEqual(
            configurations.first { $0.provider == .deepSeek }?.model,
            "deepseek-v4-flash"
        )
        XCTAssertEqual(
            configurations.first { $0.provider == .zhipu }?.model,
            "glm-4.7-flash"
        )
        XCTAssertEqual(
            configurations.first { $0.provider == .zhipu }?.baseURL,
            "https://open.bigmodel.cn/api/paas/v4"
        )
        XCTAssertEqual(
            configurations.first { $0.provider == .zhipu }?.zhipuRegion,
            .domestic
        )
        XCTAssertEqual(
            configurations.first { $0.provider == .ollama }?.baseURL,
            "http://localhost:11434/v1"
        )
        XCTAssertEqual(
            configurations.first { $0.provider == .omlx }?.baseURL,
            "http://localhost:8000/v1"
        )
    }

    func testLLMProviderConfigurationMigrationPreservesCustomValuesAndFillsMissingProviders() {
        let existing = [
            LLMProviderConfiguration(
                provider: .openAI,
                model: "custom-model",
                baseURL: "https://proxy.example/v1"
            ),
        ]

        let migrated = SettingsStore.migrateLLMProviderConfigurations(existing)

        XCTAssertEqual(
            migrated.map(\.provider),
            SentenceTranslationSource.SourceType.llmProviderTypes
        )
        XCTAssertEqual(migrated.first { $0.provider == .openAI }?.model, "custom-model")
        XCTAssertEqual(migrated.first { $0.provider == .openAI }?.baseURL, "https://proxy.example/v1")
        XCTAssertEqual(migrated.first { $0.provider == .gemini }?.baseURL, "https://generativelanguage.googleapis.com/v1beta")
        XCTAssertEqual(migrated.first { $0.provider == .zhipu }?.model, "glm-4.7-flash")
        XCTAssertEqual(migrated.first { $0.provider == .zhipu }?.baseURL, "https://open.bigmodel.cn/api/paas/v4")
        XCTAssertEqual(migrated.first { $0.provider == .zhipu }?.zhipuRegion, .domestic)
    }

    func testZhipuConfigurationInfersInternationalRegionFromBaseURL() {
        let existing = [
            LLMProviderConfiguration(
                provider: .zhipu,
                model: "glm-custom",
                baseURL: "https://api.z.ai/api/paas/v4"
            ),
        ]

        let migrated = SettingsStore.migrateLLMProviderConfigurations(existing)
        let zhipu = migrated.first { $0.provider == .zhipu }

        XCTAssertEqual(zhipu?.model, "glm-custom")
        XCTAssertEqual(zhipu?.baseURL, "https://api.z.ai/api/paas/v4")
        XCTAssertEqual(zhipu?.zhipuRegion, .international)
    }

    func testLegacySentenceTranslationSettingMigratesToOcrSentenceToggle() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: AppSettingKey.legacySentenceTranslationEnabled)

        let settings = SettingsStore.loadSentenceTranslationSettings(defaults: defaults)

        XCTAssertFalse(settings.ocrSentenceTranslationEnabled)
        XCTAssertEqual(
            defaults.object(forKey: AppSettingKey.ocrSentenceTranslationEnabled) as? Bool,
            false
        )
    }

    func testSelectedTextTranslationDefaultsToEnabled() {
        let defaults = makeDefaults()

        let settings = SettingsStore.loadSentenceTranslationSettings(defaults: defaults)

        XCTAssertTrue(settings.selectedTextTranslationEnabled)
    }

    func testDoubleTapSentenceTranslationModeDefaultsToManualRegion() {
        let defaults = makeDefaults()

        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertEqual(settings.doubleTapSentenceTranslationMode, .manualRegion)
        XCTAssertEqual(
            defaults.string(forKey: AppSettingKey.doubleTapSentenceTranslationMode),
            DoubleTapSentenceTranslationMode.manualRegion.rawValue
        )
    }

    func testLoadsPersistedDoubleTapSentenceTranslationMode() {
        let defaults = makeDefaults()
        defaults.set(
            DoubleTapSentenceTranslationMode.manualRegion.rawValue,
            forKey: AppSettingKey.doubleTapSentenceTranslationMode
        )

        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertEqual(settings.doubleTapSentenceTranslationMode, .manualRegion)
    }

    func testDoubleTapSentenceTranslationModeUsesCompactEnglishLabels() {
        let localizationManager = LocalizationManager.shared
        localizationManager.setLanguage(.english)
        defer { localizationManager.setLanguage(.system) }

        XCTAssertEqual(DoubleTapSentenceTranslationMode.cursorParagraph.displayName, "Under Cursor")
        XCTAssertEqual(DoubleTapSentenceTranslationMode.manualRegion.displayName, "Manual Selection")
    }

    func testTranslationRangeSubtitleExplainsDoubleTapSentenceScope() {
        let localizationManager = LocalizationManager.shared
        defer { localizationManager.setLanguage(.system) }

        localizationManager.setLanguage(.english)
        XCTAssertEqual(L("Used for double-tap sentence translation"), "Used for double-tap sentence translation")

        localizationManager.setLanguage(.chineseSimplified)
        XCTAssertEqual(L("Used for double-tap sentence translation"), "用于双击句子翻译")
    }

    func testBidirectionalTranslationDefaultsToEnabled() {
        let defaults = makeDefaults()

        let isEnabled = SettingsStore.loadBidirectionalTranslationEnabled(defaults: defaults)

        XCTAssertTrue(isEnabled)
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

    func testLoadsPersistedBidirectionalTranslationSetting() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppSettingKey.bidirectionalTranslationEnabled)

        let isEnabled = SettingsStore.loadBidirectionalTranslationEnabled(defaults: defaults)
        XCTAssertTrue(isEnabled)
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

    func testSentenceTranslationPresentationModeDefaultsToOverlayPanel() {
        let defaults = makeDefaults()

        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertEqual(settings.sentenceTranslationPresentationMode, .overlayPanel)
        XCTAssertEqual(
            defaults.string(forKey: AppSettingKey.sentenceTranslationPresentationMode),
            SentenceTranslationPresentationMode.overlayPanel.rawValue
        )
    }

    func testLoadsPersistedSentenceTranslationPresentationMode() {
        let defaults = makeDefaults()
        defaults.set(
            SentenceTranslationPresentationMode.inPlace.rawValue,
            forKey: AppSettingKey.sentenceTranslationPresentationMode
        )

        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertEqual(settings.sentenceTranslationPresentationMode, .inPlace)
    }

    func testSentenceTranslationPresentationModeIncludesImageTranslation() {
        let localizationManager = LocalizationManager.shared
        localizationManager.setLanguage(.english)
        defer { localizationManager.setLanguage(.system) }

        XCTAssertTrue(SentenceTranslationPresentationMode.allCases.contains(.imageTranslation))
        XCTAssertEqual(SentenceTranslationPresentationMode.imageTranslation.displayName, "Image Translation")
    }

    func testSentenceTranslationPresentationModeMarksInPlaceAsBeta() {
        let localizationManager = LocalizationManager.shared
        defer { localizationManager.setLanguage(.system) }

        localizationManager.setLanguage(.english)
        XCTAssertEqual(SentenceTranslationPresentationMode.inPlace.displayName, "In-place (Beta)")

        localizationManager.setLanguage(.chineseSimplified)
        XCTAssertEqual(SentenceTranslationPresentationMode.inPlace.displayName, "原文替换（Beta）")
    }

    func testImageTranslationSourceDefaultsToDisabledBaidu() {
        let defaults = makeDefaults()

        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertEqual(settings.imageTranslationSource.provider, .baidu)
        XCTAssertFalse(settings.imageTranslationSource.isEnabled)
        XCTAssertEqual(
            defaults.string(forKey: AppSettingKey.imageTranslationSource),
            ImageTranslationProvider.baidu.rawValue
        )
    }

    func testDefaultImageTranslationProviderConfigurations() {
        let configurations = SettingsStore.defaultImageTranslationProviderConfigurations()

        XCTAssertEqual(configurations.map(\.provider), ImageTranslationProvider.allCases)
        XCTAssertEqual(
            configurations.first { $0.provider == .baidu }?.endpoint,
            "https://fanyi-api.baidu.com/ait/api/picture/translate"
        )
    }

    func testImageTranslationProviderConfigurationMigrationPreservesCustomEndpoint() {
        let existing = [
            ImageTranslationProviderConfiguration(
                provider: .baidu,
                appID: "custom-appid",
                endpoint: "https://proxy.example/picture"
            ),
        ]

        let migrated = SettingsStore.migrateImageTranslationProviderConfigurations(existing)

        XCTAssertEqual(migrated.map(\.provider), ImageTranslationProvider.allCases)
        XCTAssertEqual(migrated.first { $0.provider == .baidu }?.appID, "custom-appid")
        XCTAssertEqual(migrated.first { $0.provider == .baidu }?.endpoint, "https://proxy.example/picture")
    }

    func testImageTranslationProviderConfigurationMigrationUpgradesDeprecatedBaiduEndpoint() {
        let existing = [
            ImageTranslationProviderConfiguration(
                provider: .baidu,
                appID: "existing-appid",
                endpoint: "https://fanyi-api.baidu.com/api/trans/sdk/picture"
            ),
        ]

        let migrated = SettingsStore.migrateImageTranslationProviderConfigurations(existing)

        XCTAssertEqual(migrated.first { $0.provider == .baidu }?.appID, "existing-appid")
        XCTAssertEqual(
            migrated.first { $0.provider == .baidu }?.endpoint,
            "https://fanyi-api.baidu.com/ait/api/picture/translate"
        )
    }

    func testKeepWordOverlayAfterTapDefaultsToEnabled() {
        let defaults = makeDefaults()

        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertTrue(settings.keepWordOverlayAfterTap)
        XCTAssertEqual(
            defaults.object(forKey: AppSettingKey.keepWordOverlayAfterTap) as? Bool,
            true
        )
    }

    func testLoadsPersistedKeepWordOverlayAfterTapSetting() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppSettingKey.keepWordOverlayAfterTap)

        let settings = SettingsStore(defaults: defaults, loginItemStatus: false)

        XCTAssertTrue(settings.keepWordOverlayAfterTap)
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

final class DoubleTapSentenceTranslationPolicyTests: XCTestCase {
    func testDisabledToggleWinsOverMode() {
        let action = DoubleTapSentenceTranslationPolicy.resolve(
            isEnabled: false,
            mode: .manualRegion
        )

        XCTAssertEqual(action, .disabled)
    }

    func testCursorParagraphModeStartsAutomaticOCR() {
        let action = DoubleTapSentenceTranslationPolicy.resolve(
            isEnabled: true,
            mode: .cursorParagraph
        )

        XCTAssertEqual(action, .automaticOCR)
    }

    func testManualRegionModeStartsRegionSelection() {
        let action = DoubleTapSentenceTranslationPolicy.resolve(
            isEnabled: true,
            mode: .manualRegion
        )

        XCTAssertEqual(action, .manualRegionSelection)
    }
}

final class ParagraphRegionLoadingOverlayPolicyTests: XCTestCase {
    func testImageTranslationDoesNotShowParagraphLoadingOverlayAfterManualRegionSelection() {
        XCTAssertTrue(
            ParagraphRegionLoadingOverlayPolicy.shouldShowLoadingOverlay(
                presentationMode: .overlayPanel
            )
        )
        XCTAssertFalse(
            ParagraphRegionLoadingOverlayPolicy.shouldShowLoadingOverlay(
                presentationMode: .inPlace
            )
        )
        XCTAssertFalse(
            ParagraphRegionLoadingOverlayPolicy.shouldShowLoadingOverlay(
                presentationMode: .imageTranslation
            )
        )
    }
}

final class SentenceTranslationServiceSelectionTests: XCTestCase {
    func testNativeTranslationFollowsNativeSourceToggle() {
        let sources = [
            SentenceTranslationSource(id: UUID(), type: .native, isEnabled: false),
            SentenceTranslationSource(id: UUID(), type: .google, isEnabled: true),
        ]

        XCTAssertFalse(SentenceTranslationServiceSelection.isNativeTranslationEnabled(in: sources))
        XCTAssertEqual(
            SentenceTranslationServiceSelection.enabledThirdPartyServices(in: sources).map(\.type),
            [.google]
        )
    }

    func testNativeTranslationIsEnabledOnlyByEnabledNativeSource() {
        let sources = [
            SentenceTranslationSource(id: UUID(), type: .native, isEnabled: true),
            SentenceTranslationSource(id: UUID(), type: .google, isEnabled: false),
        ]

        XCTAssertTrue(SentenceTranslationServiceSelection.isNativeTranslationEnabled(in: sources))
        XCTAssertTrue(SentenceTranslationServiceSelection.enabledThirdPartyServices(in: sources).isEmpty)
    }

    func testParagraphOverlayContentCanHideNativeTranslationSection() {
        let content = ParagraphOverlayContent(
            originalText: "Hello",
            translationState: .loading,
            showsNativeTranslation: false
        )

        XCTAssertFalse(content.showsNativeTranslation)
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

final class LearningExportServiceTests: XCTestCase {
    private struct StubRecord: LearningExportRecord {
        var exportWord: String
        var exportSourceLanguageIdentifier: String?
        var exportDefinitionText: String?
        var exportLookupCount: Int
        var exportReviewStage: Int
        var exportIsMastered: Bool
    }

    func testExportRowCanBeBuiltFromRecord() {
        let record = StubRecord(
            exportWord: "apple",
            exportSourceLanguageIdentifier: "en",
            exportDefinitionText: "n. 苹果",
            exportLookupCount: 4,
            exportReviewStage: 2,
            exportIsMastered: false
        )

        let row = LearningExportRow(record: record)

        XCTAssertEqual(row.word, "apple")
        XCTAssertEqual(row.sourceLanguageName, "English")
        XCTAssertEqual(row.definitionText, "n. 苹果")
        XCTAssertEqual(row.lookupCount, 4)
        XCTAssertEqual(row.reviewStage, 2)
        XCTAssertFalse(row.isMastered)
    }

    func testAnkiTSVExportEscapesTabsAndNewlines() {
        let rows = [
            LearningExportRow(
                word: "hello",
                sourceLanguageName: "English",
                definitionText: "int. 你好\nused as a greeting\twith tab",
                lookupCount: 3,
                reviewStage: 1,
                isMastered: false
            ),
        ]

        let output = LearningExportService.export(rows: rows, format: .ankiTSV)

        XCTAssertEqual(
            output,
            "Word\tLanguage\tDefinition\tLookup Count\tReview Stage\tMastered\nhello\tEnglish\tint. 你好<br>used as a greeting with tab\t3\t1\tfalse\n"
        )
    }

    func testPlainTextExportWritesOneWordPerLine() {
        let rows = [
            LearningExportRow(
                word: "apple",
                sourceLanguageName: "English",
                definitionText: "n. apple",
                lookupCount: 3,
                reviewStage: 1,
                isMastered: false
            ),
            LearningExportRow(
                word: "banana",
                sourceLanguageName: "English",
                definitionText: "n. banana",
                lookupCount: 1,
                reviewStage: 0,
                isMastered: false
            ),
        ]

        let output = LearningExportService.export(rows: rows, format: .plainText)

        XCTAssertEqual(output, "apple\nbanana\n")
    }

    func testCSVExportQuotesCommaQuoteAndNewline() {
        let rows = [
            LearningExportRow(
                word: "quote",
                sourceLanguageName: "English",
                definitionText: "say, \"hello\"\nagain",
                lookupCount: 2,
                reviewStage: 0,
                isMastered: true
            ),
        ]

        let output = LearningExportService.export(rows: rows, format: .csv)

        XCTAssertEqual(
            output,
            "Word,Language,Definition,Lookup Count,Review Stage,Mastered\nquote,English,\"say, \"\"hello\"\"\nagain\",2,0,true\n"
        )
    }
}
