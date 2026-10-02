//
//  DictionarySource.swift
//  KakuTra
//

import Foundation

struct DictionarySource: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let type: SourceType
    var isEnabled: Bool

    static func == (lhs: DictionarySource, rhs: DictionarySource) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.type == rhs.type && lhs.isEnabled == rhs.isEnabled
    }

    enum SourceType: String, Codable {
        case system
        case ecdict
        case youdao
        case google
        case freeDictionaryAPI
    }

    var displayName: String {
        type.displayName
    }
}

extension DictionarySource.SourceType {
    nonisolated func supportsLookup(sourceIdentifier: String, targetIdentifier: String) -> Bool {
        switch self {
        case .system:
            return true
        case .ecdict, .freeDictionaryAPI:
            return sourceIdentifier.hasPrefix("en")
        case .youdao:
            return sourceIdentifier.hasPrefix("en") && targetIdentifier.hasPrefix("zh")
        case .google:
            return Self.googleDictionaryLanguageCode(for: sourceIdentifier) != nil
                && Self.googleDictionaryLanguageCode(for: targetIdentifier) != nil
        }
    }

    private nonisolated static func googleDictionaryLanguageCode(for identifier: String) -> String? {
        if identifier.hasPrefix("zh-Hans") || identifier == "zh" {
            return "zh-CN"
        }
        if identifier.hasPrefix("zh-Hant") {
            return "zh-TW"
        }

        switch Locale(identifier: identifier).language.languageCode?.identifier ?? identifier {
        case "en": return "en"
        case "ja": return "ja"
        case "ko": return "ko"
        case "fr": return "fr"
        case "de": return "de"
        case "es": return "es"
        case "it": return "it"
        case "pt": return "pt"
        case "ru": return "ru"
        case "ar": return "ar"
        case "th": return "th"
        case "vi": return "vi"
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .ecdict:
            return L("Advanced Dictionary")
        case .system:
            return L("System Dictionary")
        case .youdao:
            return L("Youdao Dictionary")
        case .google:
            return L("Google Dictionary")
        case .freeDictionaryAPI:
            return L("Free Dictionary API")
        }
    }

    var subtitle: String {
        switch self {
        case .ecdict:
            return L("Advanced offline dictionary")
        case .system:
            return L("macOS built-in dictionary")
        case .youdao:
            return L("Rich English-Chinese web dictionary")
        case .google:
            return L("Structured web dictionary data")
        case .freeDictionaryAPI:
            return L("Free English dictionary API")
        }
    }

    var needsDownloadManagement: Bool {
        self == .ecdict
    }

    var isOnline: Bool {
        switch self {
        case .ecdict, .system:
            return false
        case .youdao, .google, .freeDictionaryAPI:
            return true
        }
    }

    var isExperimental: Bool {
        switch self {
        case .youdao, .google:
            return true
        case .ecdict, .system, .freeDictionaryAPI:
            return false
        }
    }

    var badges: [String] {
        var results: [String] = []
        if isOnline {
            results.append(L("Requires network"))
        }
        if isExperimental {
            results.append(L("Experimental"))
        }
        return results
    }
}

/// Common download state shared between different download managers
enum DownloadState: Equatable {
    case notInstalled
    case downloading(progress: Double)
    case installing
    case installed(sizeMB: Double)
    case error(String)
}
