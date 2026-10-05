import Foundation

struct LookupLanguagePair: Equatable {
    let sourceIdentifier: String
    let targetIdentifier: String

    var key: String {
        "\(sourceIdentifier)->\(targetIdentifier)"
    }

    var sourceLanguage: Locale.Language {
        Locale.Language(identifier: sourceIdentifier)
    }

    var targetLanguage: Locale.Language {
        Locale.Language(identifier: targetIdentifier)
    }

    var isSameLanguage: Bool {
        sourceLanguage.minimalIdentifier == targetLanguage.minimalIdentifier
    }

    static func fixed(sourceIdentifier: String, targetIdentifier: String) -> LookupLanguagePair {
        LookupLanguagePair(sourceIdentifier: sourceIdentifier, targetIdentifier: targetIdentifier)
    }
}
