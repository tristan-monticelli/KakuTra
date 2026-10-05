import Foundation

enum SingleKey: String, CaseIterable, Identifiable {
    case leftShift
    case leftControl
    case leftOption
    case leftCommand
    case rightShift
    case rightControl
    case rightOption
    case rightCommand
    case fn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftShift:
            return L("Left Shift")
        case .leftControl:
            return L("Left Control")
        case .leftOption:
            return L("Left Option")
        case .leftCommand:
            return L("Left Command")
        case .rightShift:
            return L("Right Shift")
        case .rightControl:
            return L("Right Control")
        case .rightOption:
            return L("Right Option")
        case .rightCommand:
            return L("Right Command")
        case .fn:
            return "Fn"
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return L("Follow System")
        case .english:
            return "English"
        case .chineseSimplified:
            return "简体中文"
        case .chineseTraditional:
            return "繁體中文"
        case .japanese:
            return "日本語"
        case .korean:
            return "한국어"
        }
    }

    var localeIdentifier: String? {
        switch self {
        case .system:
            return nil
        default:
            return rawValue
        }
    }
}

enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    case auto
    case black
    case white

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:
            return L("Auto")
        case .black:
            return L("Black")
        case .white:
            return L("White")
        }
    }
}

enum AppSettingKey {
    static let playPronunciation = "playPronunciation"
    static let playWordPronunciation = "playWordPronunciation"
    static let playSentencePronunciation = "playSentencePronunciation"
    static let launchAtLogin = "launchAtLogin"
    static let singleKey = "singleKey"
    static let sourceLanguage = "sourceLanguage"
    static let targetLanguage = "targetLanguage"
    static let bidirectionalTranslationEnabled = "bidirectionalTranslationEnabled"
    static let continuousTranslation = "continuousTranslation"
    static let ankiDeckName = "ankiDeckName"
    static let ankiModelName = "ankiModelName"
    static let ankiFieldMappings = "ankiFieldMappings"
    static let ankiTags = "ankiTags"
    static let keepWordOverlayAfterTap = "keepWordOverlayAfterTap"
    static let lastScreenRecordingStatus = "lastScreenRecordingStatus"
    static let hasCompletedInitialSetup = "hasCompletedInitialSetup"
    static let appLanguage = "appLanguage"
    static let legacySentenceTranslationEnabled = "sentenceTranslationEnabled"
    static let ocrSentenceTranslationEnabled = "ocrSentenceTranslationEnabled"
    static let selectedTextTranslationEnabled = "selectedTextTranslationEnabled"
    static let hideOriginalTextInSentenceOverlay = "hideOriginalTextInSentenceOverlay"
    static let translateOCRLineWithWord = "translateOCRLineWithWord"
    static let translateOCRLineDefaultOffMigration = "translateOCRLineDefaultOffMigration"
    static let showAlternateReadings = "showAlternateReadings"
    static let autoCheckUpdates = "autoCheckUpdates"
    static let updateChannel = "updateChannel"
    static let debugShowChannelSelector = "debugShowChannelSelector"
    static let showMenuBarIcon = "showMenuBarIcon"
    static let menuBarIconStyle = "menuBarIconStyle"
    static let showDockIcon = "showDockIcon"
    static let learningMaxRecords = "learningMaxRecords"
    static let learningCleanupDays = "learningCleanupDays"
    static let learningAutoCleanup = "learningAutoCleanup"
    static let voiceGender = "voiceGender"
    static let legacyProviderCredentialCleanupCompleted = "legacyProviderCredentialCleanupCompleted"
}

enum VoiceGenderPreference: String, CaseIterable, Identifiable {
    case female = "female"
    case male = "male"
    case system = "system"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .female:
            return L("Féminin")
        case .male:
            return L("Masculin")
        case .system:
            return L("Système")
        }
    }
}

enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable
    case beta

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stable:
            return L("Stable")
        case .beta:
            return L("Beta")
        }
    }

    var description: String {
        switch self {
        case .stable:
            return L("Receive stable releases only")
        case .beta:
            return L("Receive beta releases for early access to new features")
        }
    }
}
