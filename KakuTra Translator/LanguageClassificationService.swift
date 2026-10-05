import Foundation
import NaturalLanguage

/// Language and script classification for recognized text.
public struct LanguageClassification: Sendable {
    /// The dominant script according to ISO 15924 (e.g. .japanese, .latin, .korean)
    public let script: NLScript
    /// The detected language according to BCP-47 / ISO 639
    public let language: NLLanguage?
    /// Standard BCP-47 string identifier (e.g. "ja", "fr", "en", "ko")
    public let bcp47Code: String
    /// True if the text belongs to the Japanese linguistic domain (Hiragana, Katakana, Japanese Kanji)
    public let isJapanese: Bool

    nonisolated public init(
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

    /// Returns the supported source language for OCR text, or nil for unsupported text.
    /// Kana and Hangul are identified by Unicode script ranges; Han-only text is
    /// disambiguated with Apple's NaturalLanguage recognizer.
    public nonisolated static func supportedOCRLanguage(for text: String) -> String? {
        var hasKana = false
        var hasHangul = false
        var hasHan = false

        for scalar in text.unicodeScalars {
            let value = scalar.value
            hasKana = hasKana || (0x3040...0x30FF).contains(value) || (0xFF66...0xFF9D).contains(value)
            hasHangul = hasHangul || (0x1100...0x11FF).contains(value) || (0x3130...0x318F).contains(value) || (0xAC00...0xD7AF).contains(value)
            hasHan = hasHan || scalar.properties.isIdeographic
        }

        if hasKana { return "ja" }
        if hasHangul { return "ko" }
        guard hasHan else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.japanese, .simplifiedChinese, .traditionalChinese, .korean]
        recognizer.processString(text)

        // Han-only text is shared by Japanese and Chinese. Do not silently turn
        // every uncertain fragment into Chinese; combine Chinese-script variants
        // and require a clear lead among the supported language families.
        var probabilities: [String: Double] = ["ja": 0, "zh": 0, "ko": 0]
        for (language, probability) in recognizer.languageHypotheses(withMaximum: 8) {
            switch language.rawValue {
            case "ja": probabilities["ja", default: 0] += probability
            case "zh", "zh-Hans", "zh-Hant": probabilities["zh", default: 0] += probability
            case "ko": probabilities["ko", default: 0] += probability
            default: break
            }
        }

        let rankedLanguages = probabilities.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }
        guard let best = rankedLanguages.first,
              best.value >= 0.55,
              best.value - (rankedLanguages.dropFirst().first?.value ?? 0) >= 0.10 else {
            return nil
        }
        return best.key
    }

    /// Classifies text using Apple's NaturalLanguage tags and optional context.
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
            // Short OCR fragments are often impossible to identify reliably. Keep
            // an unknown language unknown instead of silently routing it as English.
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
