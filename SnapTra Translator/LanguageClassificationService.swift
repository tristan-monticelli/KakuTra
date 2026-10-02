import Foundation
import NaturalLanguage

/// Universal language and script classification engine for KakuTra.
///
/// Grounded strictly in international standards implemented by Apple's `NaturalLanguage` framework:
/// 1. **ISO 15924** script codes (`NLScript`: `Jpan`, `Latn`, `Hans`, `Hant`, `Kore`, `Cyrl`, `Arab`, etc.)
/// 2. **BCP-47 / ISO 639-1** language codes (`NLLanguage`: `ja`, `fr`, `en`, `de`, `es`, `ko`, `zh-Hans`, etc.)
/// 3. Neural-engine backed linguistic analysis combining word-level script tagging and contextual sentence inference.
public struct LanguageClassification: Sendable {
    /// The dominant script according to ISO 15924 (e.g. .japanese, .latin, .korean)
    public let script: NLScript
    /// The detected language according to BCP-47 / ISO 639
    public let language: NLLanguage?
    /// Standard BCP-47 string identifier (e.g. "ja", "fr", "en", "ko")
    public let bcp47Code: String
    /// True if the text belongs to the Japanese linguistic domain (Hiragana, Katakana, Japanese Kanji)
    public let isJapanese: Bool

    public init(
        script: NLScript,
        language: NLLanguage?,
        bcp47Code: String,
        isJapanese: Bool
    ) {
        self.script = script
        self.language = language
        self.bcp47Code = bcp47Code
        self.isJapanese = isJapanese
    }
}

public enum LanguageClassificationService {

    /// Classifies any text universally with zero hardcoded magic numbers.
    ///
    /// - Parameters:
    ///   - text: The candidate text or word to classify.
    ///   - context: Optional surrounding sentence or paragraph for disambiguation.
    /// - Returns: A standard `LanguageClassification` with script and language tags.
    public nonisolated static func classify(_ text: String, context: String? = nil) -> LanguageClassification {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return LanguageClassification(
                script: .undetermined,
                language: nil,
                bcp47Code: "und",
                isJapanese: false
            )
        }

        // 1. Tag script and language using Apple NLTagger (ISO 15924 & BCP-47)
        let tagger = NLTagger(tagSchemes: [.script, .language])
        tagger.string = trimmed

        let scriptTag = tagger.tag(at: trimmed.startIndex, unit: .word, scheme: .script).0
        let wordScript = scriptTag.flatMap { NLScript(rawValue: $0.rawValue) } ?? .undetermined

        let langTag = tagger.tag(at: trimmed.startIndex, unit: .word, scheme: .language).0
        let wordLang = langTag.flatMap { NLLanguage(rawValue: $0.rawValue) }

        // 2. If contextual sentence is provided, evaluate context language with NLLanguageRecognizer
        var contextLanguage: NLLanguage? = nil
        if let context, !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let contextRecognizer = NLLanguageRecognizer()
            contextRecognizer.processString(context)
            contextLanguage = contextRecognizer.dominantLanguage
        }

        // 3. Resolve Japanese status according to ISO 15924 standards
        let resolvedScript: NLScript
        let resolvedLanguage: NLLanguage?
        let isJapanese: Bool

        if wordScript == .japanese {
            // Unambiguously Japanese (Hiragana, Katakana, or Japanese Kanji)
            resolvedScript = .japanese
            resolvedLanguage = wordLang ?? contextLanguage ?? .japanese
            isJapanese = true
        } else if wordScript == .simplifiedChinese || wordScript == .traditionalChinese {
            // Han ideographs: check if context or dominant language indicates Japanese immersion
            if contextLanguage == .japanese {
                resolvedScript = .japanese
                resolvedLanguage = .japanese
                isJapanese = true
            } else {
                resolvedScript = wordScript
                resolvedLanguage = wordLang ?? contextLanguage
                isJapanese = false
            }
        } else if wordScript == .latin {
            resolvedScript = .latin
            resolvedLanguage = wordLang ?? contextLanguage
            isJapanese = false
        } else if wordScript == .korean {
            resolvedScript = .korean
            resolvedLanguage = .korean
            isJapanese = false
        } else if wordScript == .cyrillic {
            resolvedScript = .cyrillic
            resolvedLanguage = wordLang ?? contextLanguage
            isJapanese = false
        } else {
            // Fallback: check if the context or whole string is recognized as Japanese
            if contextLanguage == .japanese || wordLang == .japanese {
                resolvedScript = .japanese
                resolvedLanguage = .japanese
                isJapanese = true
            } else {
                resolvedScript = wordScript
                resolvedLanguage = wordLang ?? contextLanguage
                isJapanese = false
            }
        }

        let bcp47 = resolvedLanguage?.rawValue ?? (isJapanese ? "ja" : "und")

        return LanguageClassification(
            script: resolvedScript,
            language: resolvedLanguage,
            bcp47Code: bcp47,
            isJapanese: isJapanese
        )
    }
}
