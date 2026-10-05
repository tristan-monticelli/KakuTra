import Foundation

/// Script-level facts for an OCR grapheme. Language-specific word boundaries
/// are resolved later; a Unicode block alone never claims to know a word.
enum OCRCharacterScript: String, Equatable, Sendable {
    case hiragana
    case katakana
    case han
    case hangul
    case latin
    case otherLetter
    case number
    case whitespace
    case punctuation
    case mark
    case symbol

    var isCJKLetter: Bool {
        switch self {
        case .hiragana, .katakana, .han, .hangul:
            return true
        default:
            return false
        }
    }

    var isWordCharacter: Bool {
        isCJKLetter || self == .latin || self == .otherLetter || self == .number
    }
}

struct OCRCharacterDescriptor: Equatable, Sendable {
    let grapheme: String
    let codePoints: [UInt32]
    let script: OCRCharacterScript

    var hexadecimalCodePoints: [String] {
        codePoints.map { String(format: "U+%04X", $0) }
    }
}

/// Unicode range tables classify graphemes before language-specific token
/// resolution. Add a script range here without changing the word resolver.
enum OCRCharacterClassifier {
    private struct Block {
        let lowerBound: UInt32
        let upperBound: UInt32
        let script: OCRCharacterScript

        func contains(_ value: UInt32) -> Bool {
            lowerBound...upperBound ~= value
        }
    }

    private static let blocks: [Block] = [
        Block(lowerBound: 0x3040, upperBound: 0x309F, script: .hiragana),
        Block(lowerBound: 0x1B001, upperBound: 0x1B11F, script: .hiragana),
        Block(lowerBound: 0x1B130, upperBound: 0x1B16F, script: .hiragana),
        Block(lowerBound: 0x30A0, upperBound: 0x30FF, script: .katakana),
        Block(lowerBound: 0x31F0, upperBound: 0x31FF, script: .katakana),
        Block(lowerBound: 0xFF66, upperBound: 0xFF9D, script: .katakana),
        Block(lowerBound: 0x1B000, upperBound: 0x1B000, script: .katakana),
        Block(lowerBound: 0x1B120, upperBound: 0x1B12F, script: .katakana),
        Block(lowerBound: 0x1AFF0, upperBound: 0x1AFFF, script: .katakana),
        Block(lowerBound: 0x1100, upperBound: 0x11FF, script: .hangul),
        Block(lowerBound: 0x3130, upperBound: 0x318F, script: .hangul),
        Block(lowerBound: 0xA960, upperBound: 0xA97F, script: .hangul),
        Block(lowerBound: 0xAC00, upperBound: 0xD7AF, script: .hangul),
        Block(lowerBound: 0xD7B0, upperBound: 0xD7FF, script: .hangul),
        Block(lowerBound: 0x3400, upperBound: 0x4DBF, script: .han),
        Block(lowerBound: 0x4E00, upperBound: 0x9FFF, script: .han),
        Block(lowerBound: 0xF900, upperBound: 0xFAFF, script: .han),
        Block(lowerBound: 0x20000, upperBound: 0x2A6DF, script: .han),
        Block(lowerBound: 0x2A700, upperBound: 0x2B73F, script: .han),
        Block(lowerBound: 0x2B740, upperBound: 0x2B81F, script: .han),
        Block(lowerBound: 0x2B820, upperBound: 0x2CEAF, script: .han),
        Block(lowerBound: 0x2CEB0, upperBound: 0x2EBEF, script: .han),
        Block(lowerBound: 0x2EBF0, upperBound: 0x2EE5F, script: .han),
        Block(lowerBound: 0x2F800, upperBound: 0x2FA1F, script: .han),
        Block(lowerBound: 0x30000, upperBound: 0x3134F, script: .han),
        Block(lowerBound: 0x31350, upperBound: 0x323AF, script: .han),
    ]

    nonisolated static func describe(_ grapheme: Character) -> OCRCharacterDescriptor {
        let scalars = Array(grapheme.unicodeScalars)
        let codePoints = scalars.map(\.value)
        let script = scalars.compactMap(classifyScalar).first(where: \.isWordCharacter)
            ?? scalars.compactMap(classifyScalar).first
            ?? .symbol
        return OCRCharacterDescriptor(
            grapheme: String(grapheme),
            codePoints: codePoints,
            script: script
        )
    }

    nonisolated static func descriptors(in text: String) -> [OCRCharacterDescriptor] {
        text.map(describe)
    }

    nonisolated static func classifyScalar(_ scalar: Unicode.Scalar) -> OCRCharacterScript? {
        let value = scalar.value
        if let block = blocks.first(where: { $0.contains(value) }) {
            return block.script
        }

        if (0x0041...0x024F).contains(value)
            || (0x1E00...0x1EFF).contains(value)
            || (0x2C60...0x2C7F).contains(value)
            || (0xA720...0xA7FF).contains(value)
            || (0xAB30...0xAB6F).contains(value)
            || (0xFF21...0xFF5A).contains(value) {
            return .latin
        }

        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return .mark
        case .decimalNumber:
            return .number
        case .spaceSeparator, .lineSeparator, .paragraphSeparator:
            return .whitespace
        case .connectorPunctuation, .dashPunctuation, .openPunctuation,
             .closePunctuation, .initialPunctuation, .finalPunctuation,
             .otherPunctuation:
            return .punctuation
        default:
            if CharacterSet.letters.contains(scalar) {
                return .otherLetter
            }
            return .symbol
        }
    }

    nonisolated static func languageHint(for text: String) -> String? {
        let scripts = descriptors(in: text).map(\.script)
        if scripts.contains(.hiragana) || scripts.contains(.katakana) { return "ja" }
        if scripts.contains(.hangul) { return "ko" }
        // Han ideographs are shared by Chinese and Japanese. A code point
        // range can identify the script, but cannot infer the language.
        return nil
    }
}
