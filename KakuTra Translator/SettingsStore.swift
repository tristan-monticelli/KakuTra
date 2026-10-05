import AppKit
import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var playWordPronunciation: Bool {
        didSet { defaults.set(playWordPronunciation, forKey: AppSettingKey.playWordPronunciation) }
    }
    @Published var playSentencePronunciation: Bool {
        didSet { defaults.set(playSentencePronunciation, forKey: AppSettingKey.playSentencePronunciation) }
    }
    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: AppSettingKey.launchAtLogin) }
    }
    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: AppSettingKey.showMenuBarIcon) }
    }
    @Published var menuBarIconStyle: MenuBarIconStyle {
        didSet { defaults.set(menuBarIconStyle.rawValue, forKey: AppSettingKey.menuBarIconStyle) }
    }

    @Published var showDockIcon: Bool {
        didSet { defaults.set(showDockIcon, forKey: AppSettingKey.showDockIcon) }
    }
    @Published var singleKey: SingleKey {
        didSet { defaults.set(singleKey.rawValue, forKey: AppSettingKey.singleKey) }
    }
    @Published var sourceLanguage: String {
        didSet { defaults.set(sourceLanguage, forKey: AppSettingKey.sourceLanguage) }
    }
    @Published var targetLanguage: String {
        didSet { defaults.set(targetLanguage, forKey: AppSettingKey.targetLanguage) }
    }
    @Published var ankiDeckName: String {
        didSet { defaults.set(ankiDeckName, forKey: AppSettingKey.ankiDeckName) }
    }
    @Published var ankiModelName: String {
        didSet { defaults.set(ankiModelName, forKey: AppSettingKey.ankiModelName) }
    }
    @Published var ankiFieldMappings: [String: String] {
        didSet { defaults.set(ankiFieldMappings, forKey: AppSettingKey.ankiFieldMappings) }
    }
    @Published var ankiTags: String {
        didSet { defaults.set(ankiTags, forKey: AppSettingKey.ankiTags) }
    }
    @Published var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: AppSettingKey.appLanguage)
            LocalizationManager.shared.setLanguage(appLanguage)
        }
    }
    @Published var voiceGender: VoiceGenderPreference {
        didSet { defaults.set(voiceGender.rawValue, forKey: AppSettingKey.voiceGender) }
    }
    @Published var selectedTextTranslationEnabled: Bool {
        didSet { defaults.set(selectedTextTranslationEnabled, forKey: AppSettingKey.selectedTextTranslationEnabled) }
    }
    @Published var hideOriginalTextInSentenceOverlay: Bool {
        didSet { defaults.set(hideOriginalTextInSentenceOverlay, forKey: AppSettingKey.hideOriginalTextInSentenceOverlay) }
    }
    @Published var translateOCRLineWithWord: Bool {
        didSet { defaults.set(translateOCRLineWithWord, forKey: AppSettingKey.translateOCRLineWithWord) }
    }
    @Published var showAlternateReadings: Bool {
        didSet { defaults.set(showAlternateReadings, forKey: AppSettingKey.showAlternateReadings) }
    }
    @Published var autoCheckUpdates: Bool {
        didSet {
            defaults.set(autoCheckUpdates, forKey: AppSettingKey.autoCheckUpdates)
        }
    }
    @Published var updateChannel: UpdateChannel {
        didSet {
            defaults.set(updateChannel.rawValue, forKey: AppSettingKey.updateChannel)
            UpdateChecker.shared.updateFeedURL()
        }
    }

    #if DEBUG
    /// Debug mode: force show update channel selector for testing
    @Published var debugShowChannelSelector: Bool {
        didSet {
            defaults.set(debugShowChannelSelector, forKey: AppSettingKey.debugShowChannelSelector)
        }
    }
    #endif

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, loginItemStatus: Bool? = nil) {
        self.defaults = defaults

        // Migration: check if old playPronunciation exists but new keys don't
        let hasOldKey = defaults.object(forKey: AppSettingKey.playPronunciation) != nil
        let hasNewKeys = defaults.object(forKey: AppSettingKey.playWordPronunciation) != nil
            || defaults.object(forKey: AppSettingKey.playSentencePronunciation) != nil

        if hasOldKey && !hasNewKeys {
            // Migrate from old single toggle to two separate toggles
            let oldValue = defaults.bool(forKey: AppSettingKey.playPronunciation)
            playWordPronunciation = oldValue
            playSentencePronunciation = oldValue
        } else {
            let playWordPronunciationValue = defaults.object(forKey: AppSettingKey.playWordPronunciation) as? Bool
            let playSentencePronunciationValue = defaults.object(forKey: AppSettingKey.playSentencePronunciation) as? Bool
            playWordPronunciation = playWordPronunciationValue ?? true
            playSentencePronunciation = playSentencePronunciationValue ?? false
        }

        let launchAtLoginValue = defaults.object(forKey: AppSettingKey.launchAtLogin) as? Bool
        let loginStatus = loginItemStatus ?? LoginItemManager.isEnabled()
        let showMenuBarIconValue = defaults.object(forKey: AppSettingKey.showMenuBarIcon) as? Bool
        let menuBarIconStyleValue = defaults.string(forKey: AppSettingKey.menuBarIconStyle)
        let showDockIconValue = defaults.object(forKey: AppSettingKey.showDockIcon) as? Bool
        let singleKeyValue = defaults.string(forKey: AppSettingKey.singleKey)
        let savedAnkiDeckName = defaults.string(forKey: AppSettingKey.ankiDeckName)
        let savedAnkiModelName = defaults.string(forKey: AppSettingKey.ankiModelName)
        let savedAnkiFieldMappings = defaults.dictionary(forKey: AppSettingKey.ankiFieldMappings) as? [String: String] ?? [:]
        let savedAnkiTags = defaults.string(forKey: AppSettingKey.ankiTags)

        launchAtLogin = launchAtLoginValue ?? loginStatus
        showMenuBarIcon = showMenuBarIconValue ?? true
        menuBarIconStyle = MenuBarIconStyle(rawValue: menuBarIconStyleValue ?? "auto") ?? .auto
        showDockIcon = showDockIconValue ?? true
        singleKey = SingleKey(rawValue: singleKeyValue ?? "leftControl") ?? .leftControl
        sourceLanguage = "ja"
        // Translation direction is fixed by the product: supported OCR languages → English.
        targetLanguage = "en"
        ankiDeckName = savedAnkiDeckName ?? ""
        ankiModelName = savedAnkiModelName ?? ""
        ankiFieldMappings = savedAnkiFieldMappings
        ankiTags = savedAnkiTags ?? "kakutra"

        // Load app language
        let appLanguageValue = defaults.string(forKey: AppSettingKey.appLanguage)
        appLanguage = AppLanguage(rawValue: appLanguageValue ?? "system") ?? .system

        // Load voice gender preference
        let voiceGenderValue = defaults.string(forKey: AppSettingKey.voiceGender)
        voiceGender = VoiceGenderPreference(rawValue: voiceGenderValue ?? "female") ?? .female

        selectedTextTranslationEnabled = defaults.object(
            forKey: AppSettingKey.selectedTextTranslationEnabled
        ) as? Bool ?? true
        let hideOriginalTextValue = defaults.object(forKey: AppSettingKey.hideOriginalTextInSentenceOverlay) as? Bool
        hideOriginalTextInSentenceOverlay = hideOriginalTextValue ?? true
        let translateOCRLineValue = defaults.object(forKey: AppSettingKey.translateOCRLineWithWord) as? Bool
        let legacyOCRSentenceValue = defaults.object(forKey: AppSettingKey.ocrSentenceTranslationEnabled) as? Bool
        let didMigrateOCRLineDefault = defaults.bool(
            forKey: AppSettingKey.translateOCRLineDefaultOffMigration
        )
        if didMigrateOCRLineDefault {
            translateOCRLineWithWord = translateOCRLineValue ?? legacyOCRSentenceValue ?? false
        } else {
            // Earlier versions persisted their default-on value on every launch.
            // Reset that default once, but preserve a value stored under the older
            // sentence preference key when it exists.
            translateOCRLineWithWord = legacyOCRSentenceValue ?? false
            let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            if defaults !== UserDefaults.standard || !isRunningTests {
                defaults.set(true, forKey: AppSettingKey.translateOCRLineDefaultOffMigration)
            }
        }
        showAlternateReadings = defaults.object(forKey: AppSettingKey.showAlternateReadings) as? Bool ?? true

        // Load auto update settings
        let autoCheckUpdatesValue = defaults.object(forKey: AppSettingKey.autoCheckUpdates) as? Bool
        autoCheckUpdates = autoCheckUpdatesValue ?? true

        let updateChannelValue = defaults.string(forKey: AppSettingKey.updateChannel)
        updateChannel = UpdateChannel(rawValue: updateChannelValue ?? "stable") ?? .stable

        #if DEBUG
        // Load debug settings (default to false)
        let debugShowChannelSelectorValue = defaults.object(forKey: AppSettingKey.debugShowChannelSelector) as? Bool
        debugShowChannelSelector = debugShowChannelSelectorValue ?? false
        #endif

        // Tests construct the app bundle as their host. Avoid migrating or
        // rewriting the user's standard preferences from that test process.
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if defaults !== UserDefaults.standard || !isRunningTests {
            // Persist all settings to UserDefaults since didSet is not called during init.
            persistAllSettings()
            LegacyProviderDataCleanup.removeStoredCredentials(defaults: defaults)
        }
    }

    private func persistAllSettings() {
        defaults.set(playWordPronunciation, forKey: AppSettingKey.playWordPronunciation)
        defaults.set(playSentencePronunciation, forKey: AppSettingKey.playSentencePronunciation)
        defaults.set(launchAtLogin, forKey: AppSettingKey.launchAtLogin)
        defaults.set(showMenuBarIcon, forKey: AppSettingKey.showMenuBarIcon)
        defaults.set(menuBarIconStyle.rawValue, forKey: AppSettingKey.menuBarIconStyle)
        defaults.set(showDockIcon, forKey: AppSettingKey.showDockIcon)
        defaults.set(singleKey.rawValue, forKey: AppSettingKey.singleKey)
        defaults.set("ja", forKey: AppSettingKey.sourceLanguage)
        defaults.set("en", forKey: AppSettingKey.targetLanguage)
        defaults.removeObject(forKey: AppSettingKey.bidirectionalTranslationEnabled)
        defaults.removeObject(forKey: AppSettingKey.learningMaxRecords)
        defaults.removeObject(forKey: AppSettingKey.learningCleanupDays)
        defaults.removeObject(forKey: AppSettingKey.learningAutoCleanup)
        defaults.removeObject(forKey: "sentenceTranslationSources")
        defaults.removeObject(forKey: "llmProviderConfigurations")
        defaults.removeObject(forKey: "imageTranslationProviderConfigurations")
        defaults.removeObject(forKey: "imageTranslationSource")
        defaults.removeObject(forKey: "imageTranslationSourceEnabled")
        defaults.removeObject(forKey: "ttsProvider")
        defaults.removeObject(forKey: "wordTTSProvider")
        defaults.removeObject(forKey: "sentenceTTSProvider")
        defaults.removeObject(forKey: "englishAccent")
        defaults.removeObject(forKey: AppSettingKey.continuousTranslation)
        defaults.removeObject(forKey: AppSettingKey.keepWordOverlayAfterTap)
        defaults.set(ankiDeckName, forKey: AppSettingKey.ankiDeckName)
        defaults.set(ankiModelName, forKey: AppSettingKey.ankiModelName)
        defaults.set(ankiFieldMappings, forKey: AppSettingKey.ankiFieldMappings)
        defaults.set(ankiTags, forKey: AppSettingKey.ankiTags)
        defaults.set(appLanguage.rawValue, forKey: AppSettingKey.appLanguage)
        defaults.set(voiceGender.rawValue, forKey: AppSettingKey.voiceGender)
        defaults.removeObject(forKey: AppSettingKey.legacySentenceTranslationEnabled)
        defaults.removeObject(forKey: AppSettingKey.ocrSentenceTranslationEnabled)
        defaults.removeObject(forKey: AppSettingKey.selectedTextTranslationEnabled)
        defaults.removeObject(forKey: "sentenceTranslationPresentationMode")
        defaults.removeObject(forKey: "doubleTapSentenceTranslationMode")
        defaults.set(selectedTextTranslationEnabled, forKey: AppSettingKey.selectedTextTranslationEnabled)
        defaults.set(hideOriginalTextInSentenceOverlay, forKey: AppSettingKey.hideOriginalTextInSentenceOverlay)
        defaults.set(translateOCRLineWithWord, forKey: AppSettingKey.translateOCRLineWithWord)
        defaults.set(showAlternateReadings, forKey: AppSettingKey.showAlternateReadings)
        defaults.set(autoCheckUpdates, forKey: AppSettingKey.autoCheckUpdates)
        defaults.set(updateChannel.rawValue, forKey: AppSettingKey.updateChannel)
        #if DEBUG
        defaults.set(debugShowChannelSelector, forKey: AppSettingKey.debugShowChannelSelector)
        #endif
    }

    var hotkeyDisplayText: String {
        singleKey.title
    }

}
