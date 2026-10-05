//
//  LocalDictionaryService.swift
//  KakuTra
//
//  Local SQLite lookup for Japanese, Chinese, and Korean dictionaries.
//  Dictionary files stay on device and can be managed from Dictionary settings.
//

import AppKit
import Combine
import Foundation
import SQLite3

final class LocalDictionaryService: ObservableObject, @unchecked Sendable {
    static let shared = LocalDictionaryService()

    static let databaseFilename = "english.db"

    static var databaseDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("KakuTra/Dictionaries")
    }

    static var databaseURL: URL {
        databaseDirectory.appendingPathComponent(databaseFilename)
    }

    @Published private(set) var isDatabaseInstalled: Bool = false
    @Published private(set) var totalEntriesCount: Int = 0
    @Published private(set) var installedDictionaries: [String] = []

    private var db: OpaquePointer?
    private var chineseDb: OpaquePointer?
    private var koreanDb: OpaquePointer?
    private let accessQueue = DispatchQueue(label: "com.kakutra.japanese-dictionary", qos: .userInitiated)

    init() {
        openDatabase()
        refreshStats()
    }

    deinit {
        closeDatabase()
    }

    // MARK: - Connection Management

    func openDatabase() {
        try? FileManager.default.createDirectory(at: Self.databaseDirectory, withIntermediateDirectories: true)
        
        let path = Self.databaseURL.path
        if FileManager.default.fileExists(atPath: path) {
            if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
                db = nil
            }
        } else {
            // Fallback check if old db filename exists
            let legacyPath = (Self.databaseDirectory.path as NSString).appendingPathComponent("kakutra_japanese.db")
            if FileManager.default.fileExists(atPath: legacyPath) {
                if sqlite3_open_v2(legacyPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
                    db = nil
                }
            }
        }

        // Open Chinese database (CC-CEDICT)
        let chinesePath = Self.databaseDirectory.appendingPathComponent("chinese.db").path
        if FileManager.default.fileExists(atPath: chinesePath) {
            if sqlite3_open_v2(chinesePath, &chineseDb, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
                chineseDb = nil
            }
        }

        // Open Korean database (KRDICT)
        let koreanPath = Self.databaseDirectory.appendingPathComponent("korean.db").path
        if FileManager.default.fileExists(atPath: koreanPath) {
            if sqlite3_open_v2(koreanPath, &koreanDb, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
                koreanDb = nil
            }
        }
    }

    func closeDatabase() {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
        if let chineseDb {
            sqlite3_close(chineseDb)
            self.chineseDb = nil
        }
        if let koreanDb {
            sqlite3_close(koreanDb)
            self.koreanDb = nil
        }
    }

    func openDatabaseFolder() {
        NSWorkspace.shared.open(Self.databaseDirectory)
    }

    func refreshStats() {
        accessQueue.async { [weak self] in
            guard let self else { return }
            var count = 0
            var installed: [String] = []

            func countEntries(in database: OpaquePointer?, label: String) {
                guard let database else { return }
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(database, "SELECT count(*) FROM entries", -1, &stmt, nil) == SQLITE_OK {
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        let c = Int(sqlite3_column_int64(stmt, 0))
                        if c > 0 {
                            count += c
                            installed.append(label)
                        }
                    }
                    sqlite3_finalize(stmt)
                }
            }

            countEntries(in: self.db, label: "Jitendex + JMnedict (Japanese)")
            countEntries(in: self.chineseDb, label: "CC-CEDICT (Chinese)")
            countEntries(in: self.koreanDb, label: "KRDICT (Korean)")

            DispatchQueue.main.async {
                self.isDatabaseInstalled = count > 0
                self.totalEntriesCount = count
                self.installedDictionaries = installed
            }
        }
    }

    // MARK: - Text Normalization Helper

    private func cleanWord(_ text: String) -> String {
        let punctuationAndWhitespace = CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: " \t\r\n.,;:!?()[]{}'\"“”‘’`~@#$%^&*-_=+|\\/<>~·！？。，、；：‘’“”（）《》【】…—「」『』〈〉〔〕")
        )
        return text.trimmingCharacters(in: punctuationAndWhitespace)
    }

    private func isKanji(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
    }

    // MARK: - Fast Lookup (<0.1 ms)

    func lookup(_ text: String) -> [DictionaryTermResult] {
        let cleaned = cleanWord(text)
        guard !cleaned.isEmpty else { return [] }

        return accessQueue.sync {
            guard let db else { return [] }

            // 1. Generate de-inflection candidates for the full query
            let candidates = deinflect(cleaned)
            var results = queryCandidates(candidates, in: db)

            if !results.isEmpty {
                return results
            }

            // 2. Try trimming trailing sentence particles and re-evaluating
            let particles: [Character] = ["よ", "ね", "わ", "ぞ", "ぜ", "な", "さ", "か", "が", "は", "を", "に", "へ", "で", "と", "も", "の"]
            if cleaned.count > 1, let lastChar = cleaned.last, particles.contains(lastChar) {
                let stripped = String(cleaned.dropLast())
                let strippedCandidates = deinflect(stripped)
                results = queryCandidates(strippedCandidates, in: db)
                if !results.isEmpty {
                    return results
                }
            }

            // 3. Longest prefix matching (down to 1 char if Kanji)
            if cleaned.count > 1 {
                for len in stride(from: cleaned.count - 1, through: 1, by: -1) {
                    let sub = String(cleaned.prefix(len))
                    if len == 1, let first = sub.first, !isKanji(first) {
                        continue
                    }
                    let subCandidates = deinflect(sub)
                    let subResults = queryCandidates(subCandidates, in: db)
                    if !subResults.isEmpty {
                        return subResults
                    }
                }
            }

            return []
        }
    }

    // MARK: - Chinese Fast Lookup (CC-CEDICT)

    func lookupChinese(_ text: String) -> [DictionaryTermResult] {
        let cleaned = cleanWord(text)
        guard !cleaned.isEmpty else { return [] }

        return accessQueue.sync {
            guard let chineseDb else { return [] }

            // 1. Direct query
            var results = queryCandidates([cleaned], in: chineseDb)
            if !results.isEmpty { return results }

            // 2. Longest prefix matching (compound words / phrases down to 1 character)
            if cleaned.count > 1 {
                for len in stride(from: cleaned.count - 1, through: 1, by: -1) {
                    let sub = String(cleaned.prefix(len))
                    results = queryCandidates([sub], in: chineseDb)
                    if !results.isEmpty { return results }
                }
            }

            return []
        }
    }

    // MARK: - Korean Fast Lookup (KRDICT)

    func lookupKorean(_ text: String) -> [DictionaryTermResult] {
        let cleaned = cleanWord(text)
        guard !cleaned.isEmpty else { return [] }

        return accessQueue.sync {
            guard let koreanDb else { return [] }

            // 1. Direct query
            var results = queryCandidates([cleaned], in: koreanDb)
            if !results.isEmpty { return results }

            // 2. Korean verb de-inflection & particle stripping
            let candidates = deinflectKorean(cleaned)
            if !candidates.isEmpty {
                results = queryCandidates(candidates, in: koreanDb)
                if !results.isEmpty { return results }
            }

            // 3. Longest prefix matching
            if cleaned.count > 1 {
                for len in stride(from: cleaned.count - 1, through: 1, by: -1) {
                    let sub = String(cleaned.prefix(len))
                    results = queryCandidates([sub], in: koreanDb)
                    if !results.isEmpty { return results }
                }
            }

            return []
        }
    }

    func deinflectKorean(_ text: String) -> [String] {
        var candidates: [String] = []

        func add(_ cand: String) {
            let trimmedCand = cand.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedCand.isEmpty && !candidates.contains(trimmedCand) && trimmedCand != text {
                candidates.append(trimmedCand)
            }
        }

        // 1. Standard Past Tense Consonant Suffixes (-았습니다, -었습니다, -었다, etc.)
        let pastConsonantSuffixes = [
            "았습니다", "었습니다", "였습니다", "했습니다",
            "았어요", "었어요", "였어요", "했어요",
            "았다", "었다", "였다", "했다",
            "았어", "었어", "였어", "했어",
            "았고", "었고", "였고", "했고",
            "았지만", "었지만", "였지만", "했지만",
            "았으면", "었으면", "였으면", "했으면"
        ]
        for suf in pastConsonantSuffixes {
            if text.hasSuffix(suf) && text.count > suf.count {
                let stem = String(text.dropLast(suf.count))
                if suf.hasPrefix("았") || suf.hasPrefix("었") || suf.hasPrefix("였") {
                    add(stem + "다")
                }
                if suf.contains("했") {
                    add(stem + "하다")
                }
            }
        }

        // 2. Contracted Past Tense with batchim ㅆ (e.g. 갔다 -> 가다, 봤다 -> 보다, 줬다 -> 주다, 썼다 -> 쓰다)
        let pastEndingLengths: [(suffix: String, count: Int)] = [
            ("습니다", 3), ("어요", 2), ("다", 1), ("어", 1), ("고", 1), ("지만", 2), ("으면", 2)
        ]
        for (suf, _) in pastEndingLengths {
            if text.hasSuffix(suf) && text.count > suf.count {
                let beforeEnding = String(text.dropLast(suf.count))
                if let lastChar = beforeEnding.last {
                    let scalar = lastChar.unicodeScalars.first!.value
                    if scalar >= 0xAC00 && scalar <= 0xD7A3 {
                        let base = scalar - 0xAC00
                        let final = base % 28
                        if final == 20 { // ㅆ (ssangsiot batchim)
                            let strippedScalar = UnicodeScalar(scalar - 20)!
                            let prefix = String(beforeEnding.dropLast())
                            let baseSyllable = String(Character(strippedScalar))

                            let medial = (base % (21 * 28)) / 28
                            let initial = base / (21 * 28)

                            if baseSyllable == "하" {
                                add(prefix + "하다")
                            } else if medial == 9 { // ㅘ (wa) -> ㅗ (o) => 보다, 오다
                                let oScalar = UnicodeScalar(0xAC00 + (initial * 21 + 8) * 28)!
                                add(prefix + String(Character(oScalar)) + "다")
                            } else if medial == 14 { // ㅝ (wo) -> ㅜ (u) => 주다, 두다
                                let uScalar = UnicodeScalar(0xAC00 + (initial * 21 + 13) * 28)!
                                add(prefix + String(Character(uScalar)) + "다")
                            } else if medial == 6 { // ㅕ (yeo) -> ㅣ (i) => 마시다, 켜다
                                let iScalar = UnicodeScalar(0xAC00 + (initial * 21 + 20) * 28)!
                                add(prefix + String(Character(iScalar)) + "다")
                            } else if medial == 10 { // ㅙ (wae) -> ㅚ (oe) => 되다
                                let oeScalar = UnicodeScalar(0xAC00 + (initial * 21 + 11) * 28)!
                                add(prefix + String(Character(oeScalar)) + "다")
                            } else if medial == 4 { // ㅓ (eo) -> ㅡ (eu) => 쓰다, 크다
                                let euScalar = UnicodeScalar(0xAC00 + (initial * 21 + 18) * 28)!
                                add(prefix + String(Character(euScalar)) + "다")
                            }

                            add(prefix + baseSyllable + "다")
                        }
                    }
                }
            }
        }

        // 3. Formal Present -습니다 / -ㅂ니다
        if text.hasSuffix("습니다") && text.count > 3 {
            add(String(text.dropLast(3)) + "다")
        }
        if text.hasSuffix("니다") && text.count > 2 {
            let beforeEnding = String(text.dropLast(2))
            if let lastChar = beforeEnding.last {
                let scalar = lastChar.unicodeScalars.first!.value
                if scalar >= 0xAC00 && scalar <= 0xD7A3 {
                    let base = scalar - 0xAC00
                    let final = base % 28
                    if final == 17 { // ㅂ (pieup batchim) => 갑니다 -> 가다, 봅니다 -> 보다
                        let strippedScalar = UnicodeScalar(scalar - 17)!
                        let prefix = String(beforeEnding.dropLast())
                        add(prefix + String(Character(strippedScalar)) + "다")
                    }
                }
            }
        }

        // 4. Present Polite -아요, -어요, -여요, -해요, -세요
        let presentPoliteSuffixes = ["하세요", "해요", "아요", "어요", "여요", "셔요"]
        for suf in presentPoliteSuffixes {
            if text.hasSuffix(suf) && text.count > suf.count {
                let stem = String(text.dropLast(suf.count))
                if suf.contains("하") {
                    add(stem + "하다")
                } else {
                    add(stem + "다")
                }
            }
        }
        if text.hasSuffix("요") && text.count > 1 {
            let stem = String(text.dropLast(1))
            add(stem + "다")
            if let last = stem.last {
                let scalar = last.unicodeScalars.first!.value
                if scalar >= 0xAC00 && scalar <= 0xD7A3 {
                    let base = scalar - 0xAC00
                    let medial = (base % (21 * 28)) / 28
                    let initial = base / (21 * 28)
                    let prefix = String(stem.dropLast())
                    if medial == 9 { // ㅘ -> ㅗ => 봐요 -> 보다
                        let oScalar = UnicodeScalar(0xAC00 + (initial * 21 + 8) * 28)!
                        add(prefix + String(Character(oScalar)) + "다")
                    } else if medial == 14 { // ㅝ -> ㅜ => 줘요 -> 주다
                        let uScalar = UnicodeScalar(0xAC00 + (initial * 21 + 13) * 28)!
                        add(prefix + String(Character(uScalar)) + "다")
                    } else if medial == 6 { // ㅕ -> ㅣ => 마셔요 -> 마시다
                        let iScalar = UnicodeScalar(0xAC00 + (initial * 21 + 20) * 28)!
                        add(prefix + String(Character(iScalar)) + "다")
                    } else if medial == 10 { // ㅙ -> ㅚ => 돼요 -> 되다
                        let oeScalar = UnicodeScalar(0xAC00 + (initial * 21 + 11) * 28)!
                        add(prefix + String(Character(oeScalar)) + "다")
                    } else if medial == 4 { // ㅓ -> ㅡ => 써요 -> 쓰다, 커요 -> 크다, 예뻐요 -> 예쁘다
                        let euScalar = UnicodeScalar(0xAC00 + (initial * 21 + 18) * 28)!
                        add(prefix + String(Character(euScalar)) + "다")
                    }
                }
            }
        }

        // 5. Connectives & Modifiers (-고, -으며, -으면, -아서, -어서, -지만, -는데, -은데, -으려고, -으면서, -거나, -게, -지, -기)
        let connectiveSuffixes = [
            "으려고", "려고", "으면서", "면서", "어서", "아서", "여서", "해서",
            "으면", "면", "으며", "며", "지만", "는데", "은데", "거나", "도록", "게", "고", "지", "기"
        ]
        for suf in connectiveSuffixes {
            if text.hasSuffix(suf) && text.count > suf.count {
                let stem = String(text.dropLast(suf.count))
                if suf == "해서" {
                    add(stem + "하다")
                } else {
                    add(stem + "다")
                }
            }
        }

        // 6. Adnominal Endings (-는, -은, -을)
        let adnominalSuffixes = ["는", "은", "을"]
        for suf in adnominalSuffixes {
            if text.hasSuffix(suf) && text.count > suf.count {
                add(String(text.dropLast(suf.count)) + "다")
            }
        }

        // 7. Particles & Postpositions
        let particles = [
            "에서는", "에게는", "에게서", "부터는", "까지는",
            "에서", "에게", "한테", "으로", "부터", "까지", "처럼", "마저", "조차", "밖에",
            "은", "는", "이", "가", "을", "를", "에", "로", "과", "와", "도", "만", "의"
        ]
        for p in particles {
            if text.hasSuffix(p) && text.count > p.count {
                add(String(text.dropLast(p.count)))
            }
        }

        return candidates
    }

    private static let knownJitendexMetadata: Set<String> = [
        "n", "noun", "pronoun", "prefix", "pref", "suf", "suffix", "exp", "expression",
        "v1", "1-dan", "ichidan verb", "ichidan", "v5", "5-dan", "godan verb", "godan",
        "v5k", "v5s", "v5t", "v5n", "v5m", "v5r", "v5w", "v5g", "v5b", "v5k-s",
        "vs", "suru verb", "suru", "vk", "kuru verb",
        "vt", "transitive", "transitive verb", "vi", "intransitive", "intransitive verb",
        "adj-i", "i-adj", "adjective", "adjective (keiyoushi)",
        "adj-na", "na-adj", "adjectival noun", "adjective (keiyoudoushi)",
        "adj-no", "adj-pn", "adj-t", "adj-f",
        "adv", "adverb", "adverb (fukushi)", "adv-to", "to-adverb",
        "conj", "conjunction", "int", "interjection", "prt", "particle", "ctr", "counter",
        "num", "numeric", "pn", "proper noun",
        "archaic", "slang", "colloquialism", "colloquial", "vulgar", "obscure", "rare", "mimetic",
        "yojijukugo", "idiomatic expression", "idiom", "derogatory", "dated", "historical",
        "honorific", "humble", "polite", "familiar", "formal", "children's language",
        "male term", "female term", "jocular", "poetic", "poetical", "sensitive", "proverb", "food",
        "computing", "medical", "yoji", "wasei", "adjectival", "buddhism", "math", "chemistry",
        "literally", "taru", "baseball", "astronomy", "net slang", "italian", "finance", "grammar", "mahjong",
        "kansai", "martial arts", "video games", "internet", "childish", "military", "biology", "botany",
        "geology", "music", "law", "anatomy", "physics", "linguistics", "derogatory", "dated", "obsolete",
        "abbr.", "sports",
        "euphemism", "usually written using kana alone", "uk"
    ]

    private func cleanJitendexEntry(
        term: String,
        reading: String?,
        rawGlossary: String,
        rawPos: String?
    ) -> (tags: [String], glosses: [String], redirectTarget: String?, alternateReadings: [String]) {
        var tags: [String] = []
        var glosses: [String] = []
        var alternateReadings: [String] = []
        let hasObsoleteReading = rawPos?.localizedCaseInsensitiveContains("obsolete reading") == true

        let rawLines = rawGlossary.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Check for Jitendex redirect
        for (i, line) in rawLines.enumerated() {
            if line.hasPrefix("redirected from") && i > 0 {
                let target = rawLines[i - 1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !target.isEmpty && target != term {
                    return (tags, ["⟶ \(target)"], target, [])
                }
            }
        }

        var i = 0
        var seenJapanese = false

        while i < rawLines.count {
            let line = rawLines[i]
            let lower = line.lowercased()

            if lower == "forms" || lower == "form" {
                var formIndex = i + 1
                while formIndex < rawLines.count {
                    let form = rawLines[formIndex]
                    let formLower = form.lowercased()
                    if ["jmdict", "jitendex", "tatoeba"].contains(formLower) || form.hasPrefix("|") {
                        break
                    }
                    if form.range(of: #"^[\p{Hiragana}\p{Katakana}ー・]+$"#, options: .regularExpression) != nil,
                       form != reading,
                       !hasObsoleteReading {
                        alternateReadings.append(form)
                    }
                    formIndex += 1
                }
                break
            }
            if lower == "jmdict" || lower == "jitendex" || lower == "tatoeba" || lower.hasPrefix("| tatoeba") {
                break
            }
            if line.range(of: #"^\[\d+\]$"#, options: .regularExpression) != nil || line == "|" || line == "[" || line == "]" {
                i += 1
                continue
            }
            if lower == "see also" || lower == "antonym" {
                i += 1
                if i < rawLines.count,
                   rawLines[i].range(of: #"[\p{Hiragana}\p{Katakana}\p{Han}]"#, options: .regularExpression) != nil {
                    i += 1
                }
                continue
            }
            if lower == "language of origin" {
                i += min(2, rawLines.count - i)
                continue
            }
            if lower == "note" || lower == "explanation" {
                i += 1
                continue
            }

            let stripped = lower.trimmingCharacters(in: CharacterSet(charactersIn: "()[] .,:;"))
            if Self.knownJitendexMetadata.contains(stripped)
                || Self.knownJitendexMetadata.contains(stripped + ".")
                || stripped.hasPrefix("5-dan") || stripped.hasPrefix("1-dan") {
                if !tags.contains(line) { tags.append(line) }
                i += 1
                continue
            }

            let hasJp = line.range(of: #"[\p{Hiragana}\p{Katakana}\p{Han}]"#, options: .regularExpression) != nil
            if hasJp {
                seenJapanese = true
                i += 1
                continue
            }

            // If an English sentence directly follows a Japanese example sentence and ends with period/punctuation,
            // it is the translation of the example sentence: skip it.
            if seenJapanese && (line.hasSuffix(".") || line.hasSuffix("?") || line.hasSuffix("!")) && !line.hasSuffix("etc.") && !line.hasSuffix("esp.") {
                seenJapanese = false
                i += 1
                continue
            }

            seenJapanese = false
            if !line.hasPrefix("⟶") {
                // JMdict/Jitendex separates independent English senses with semicolons.
                // Keep parenthetical qualifiers attached so the UI can expose them on hover.
                let senses = line.components(separatedBy: ";")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                for sense in senses where !glosses.contains(sense) {
                    glosses.append(sense)
                }
            }
            i += 1
        }

        return (tags, Array(glosses.prefix(6)), nil, Array(Set(alternateReadings)).sorted())
    }

    private func cleanChineseEntry(
        term: String,
        reading: String?,
        rawGlossary: String
    ) -> (reading: String?, tags: [String], glosses: [String]) {
        var text = rawGlossary.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("【") {
            if let closeIdx = text.range(of: "】") {
                text = String(text[closeIdx.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        var tags: [String] = []
        let tagPatterns = ["(ACG)", "(slang)", "(dialect)", "(coll.)", "(loanword)", "(idiom)"]
        for p in tagPatterns {
            if text.contains(p) {
                tags.append(p.replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "").capitalized)
                text = text.replacingOccurrences(of: p, with: "")
            }
        }
        text = text.replacingOccurrences(of: #"\s*CL:[^\s;/]+"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        let parts = text.components(separatedBy: CharacterSet(charactersIn: ";/"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var glosses: [String] = []
        for p in parts {
            if p.hasPrefix("CL:") {
                continue
            }
            glosses.append(p)
        }

        return (reading, tags, Array(glosses.prefix(4)))
    }

    private func cleanKoreanEntry(
        term: String,
        reading: String?,
        rawGlossary: String,
        rawPos: String?
    ) -> (reading: String?, tags: [String], glosses: [String]) {
        var resolvedReading = reading
        var text = rawGlossary.trimmingCharacters(in: .whitespacesAndNewlines)

        // Ignore raw Wikipedia encyclopedia dumps
        if text.contains("Wikipedia") || text.hasPrefix("«") || text.hasPrefix("(") {
            return (nil, [], [])
        }

        if let hStart = text.range(of: "〔"), let hEnd = text.range(of: "〕", range: hStart.upperBound..<text.endIndex) {
            let hanja = String(text[hStart.upperBound..<hEnd.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !hanja.isEmpty {
                resolvedReading = hanja
            }
            text.removeSubrange(hStart.lowerBound...hEnd.upperBound)
        }

        if let seeMore = text.range(of: "See More") {
            text = String(text[..<seeMore.lowerBound]).trimmingCharacters(in: .whitespaces)
        }

        if text.hasPrefix(term) {
            text = String(text.dropFirst(term.count)).trimmingCharacters(in: .whitespaces)
        }
        text = text.replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)

        if let m = text.range(of: "^[^a-zA-Z]+", options: .regularExpression) {
            text = String(text[m.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        // Strict POS extraction: NEVER include stars or emoji
        var tags: [String] = []
        if let rawPos = rawPos?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPos.isEmpty {
            let parts = rawPos.components(separatedBy: CharacterSet.whitespacesAndNewlines)
            for p in parts {
                if p.contains("⭐") || p.contains("★") { continue }
                let cleaned = p.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                if !cleaned.isEmpty && !tags.contains(cleaned.capitalized) {
                    tags.append(cleaned.capitalized)
                }
            }
        }

        // Extract translation keywords vs explanatory sentence (e.g. "A small animal...", "One's relatives...")
        let sentencePattern = #"(?<=\S)\s+([A-Z][a-z]*(?:\s+[a-z]+){2,}.*)$"#
        var explanation: String? = nil
        var keywordsPart = text
        if let match = text.range(of: sentencePattern, options: .regularExpression) {
            explanation = String(text[match]).trimmingCharacters(in: .whitespaces)
            keywordsPart = String(text[..<match.lowerBound]).trimmingCharacters(in: .whitespaces)
        }

        var glosses: [String] = []
        let kwList = keywordsPart.components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.range(of: "[a-zA-Z]", options: .regularExpression) != nil }

        for (i, kw) in kwList.enumerated() {
            if i == 0, let explanation = explanation, !explanation.isEmpty {
                glosses.append("\(kw) (\(explanation))")
            } else if !glosses.contains(kw) {
                glosses.append(kw)
            }
        }

        if glosses.isEmpty, let explanation = explanation {
            glosses.append(explanation)
        } else if glosses.isEmpty {
            glosses = [text]
        }

        return (resolvedReading, tags, Array(glosses.prefix(4)))
    }

    private func queryCandidates(_ candidates: [String], in db: OpaquePointer) -> [DictionaryTermResult] {
        guard !candidates.isEmpty else { return [] }

        var entries: [DictionaryTermResult] = []
        var seenKeys = Set<String>()

        let sql = """
        SELECT term, reading, glossary, pos, dictionary, score 
        FROM entries 
        WHERE term = ? OR reading = ? 
        ORDER BY score DESC 
        LIMIT 10;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        for candidate in candidates {
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, (candidate as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (candidate as NSString).utf8String, -1, nil)

            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let termCString = sqlite3_column_text(stmt, 0),
                      let glossaryCString = sqlite3_column_text(stmt, 2),
                      let dictCString = sqlite3_column_text(stmt, 4) else { continue }

                let term = String(cString: termCString)
                var reading = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
                let glossaryRaw = String(cString: glossaryCString)
                let posRaw = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
                let dictionary = String(cString: dictCString)

                // A dictionary can have multiple senses with the same headword
                // and reading. Include the row's content in the key so those
                // senses survive; only repeated fetches of the same SQL row fold.
                let key = "\(dictionary)|\(term)|\(reading ?? "")|\(posRaw ?? "")|\(glossaryRaw)"
                if seenKeys.contains(key) { continue }
                seenKeys.insert(key)

                var tags: [String]
                var glosses: [String]
                var alternateReadings: [String] = []

                if dictionary == "CC-CEDICT" || db == chineseDb {
                    let parsed = cleanChineseEntry(term: term, reading: reading, rawGlossary: glossaryRaw)
                    reading = parsed.reading
                    tags = parsed.tags
                    glosses = parsed.glosses
                    alternateReadings = []
                } else if dictionary == "KRDICT" || db == koreanDb {
                    if dictionary.contains("Wikipedia") || glossaryRaw.contains("Wikipedia") {
                        continue
                    }
                    let parsed = cleanKoreanEntry(term: term, reading: reading, rawGlossary: glossaryRaw, rawPos: posRaw)
                    reading = parsed.reading
                    tags = parsed.tags
                    glosses = parsed.glosses
                    alternateReadings = []
                } else {
                    let parsed = cleanJitendexEntry(term: term, reading: reading, rawGlossary: glossaryRaw, rawPos: posRaw)
                    if let target = parsed.redirectTarget {
                        // Resolve the redirect target to get the canonical entry
                        let targetEntries = queryDirectTerm(target, in: db)
                        if let firstTarget = targetEntries.first {
                            let resolvedEntry = DictionaryTermResult(
                                term: target,
                                reading: firstTarget.reading ?? reading,
                                dictionary: dictionary,
                                glosses: firstTarget.glosses,
                                tags: firstTarget.tags,
                                alternateReadings: firstTarget.alternateReadings
                            )
                            entries.append(resolvedEntry)
                            if entries.count >= 15 { break }
                            continue
                        }
                    }
                    tags = parsed.tags
                    glosses = parsed.glosses
                    alternateReadings = parsed.alternateReadings
                }

                guard !glosses.isEmpty else { continue }

                let entry = DictionaryTermResult(
                    term: term,
                    reading: reading,
                    dictionary: dictionary,
                    glosses: glosses,
                    tags: tags,
                    alternateReadings: alternateReadings
                )
                entries.append(entry)

                if entries.count >= 15 { break }
            }

            if entries.count >= 15 { break }
        }

        let vocabEntries = entries.filter { $0.dictionary != "Names" && !$0.dictionary.contains("Wikipedia") }
        return vocabEntries.isEmpty ? entries : vocabEntries
    }

    private func queryDirectTerm(_ term: String, in db: OpaquePointer) -> [DictionaryTermResult] {
        let sql = "SELECT term, reading, glossary, pos, dictionary, score FROM entries WHERE term = ? ORDER BY score DESC LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (term as NSString).utf8String, -1, nil)
        var results: [DictionaryTermResult] = []
        if sqlite3_step(stmt) == SQLITE_ROW {
            guard let termCString = sqlite3_column_text(stmt, 0),
                  let glossaryCString = sqlite3_column_text(stmt, 2),
                  let dictCString = sqlite3_column_text(stmt, 4) else { return [] }
            let term = String(cString: termCString)
            let reading = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
            let glossaryRaw = String(cString: glossaryCString)
            let posRaw = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
            let dictionary = String(cString: dictCString)
            let parsed = cleanJitendexEntry(term: term, reading: reading, rawGlossary: glossaryRaw, rawPos: posRaw)
            if !parsed.glosses.isEmpty {
                results.append(DictionaryTermResult(
                    term: term,
                    reading: reading,
                    dictionary: dictionary,
                    glosses: parsed.glosses,
                    tags: parsed.tags,
                    alternateReadings: parsed.alternateReadings
                ))
            }
        }
        return results
    }

    // MARK: - Japanese De-inflection Engine

    func deinflect(_ word: String) -> [String] {
        var candidates: [String] = [word]

        func add(_ cand: String) {
            if !candidates.contains(cand) && !cand.isEmpty {
                candidates.append(cand)
            }
        }

        // Kana conversions (Hiragana <-> Katakana)
        if let kanaHiragana = word.applyingTransform(.hiraganaToKatakana, reverse: true), kanaHiragana != word {
            add(kanaHiragana)
        }
        if let kanaKatakana = word.applyingTransform(.hiraganaToKatakana, reverse: false), kanaKatakana != word {
            add(kanaKatakana)
        }

        // 1. Ichidan Verbs
        let ichidanSuffixes: [(suffix: String, rep: String)] = [
            ("ない", "る"), ("なかった", "る"), ("ず", "る"),
            ("ます", "る"), ("ました", "る"), ("ません", "る"), ("ませんでした", "る"),
            ("たい", "る"), ("たかった", "る"),
            ("た", "る"), ("て", "る"), ("だ", "る"), ("で", "る"),
            ("られる", "る"), ("させる", "る"), ("れば", "る"), ("ろ", "る"), ("よ", "る")
        ]
        for rule in ichidanSuffixes {
            if word.hasSuffix(rule.suffix) && word.count > rule.suffix.count {
                add(String(word.dropLast(rule.suffix.count)) + rule.rep)
            }
        }

        // 2. I-Adjectives
        let iAdjSuffixes: [(suffix: String, rep: String)] = [
            ("くない", "い"), ("くなかった", "い"), ("かった", "い"),
            ("くて", "い"), ("ければ", "い"), ("く", "い"), ("さ", "い")
        ]
        for rule in iAdjSuffixes {
            if word.hasSuffix(rule.suffix) && word.count > rule.suffix.count {
                add(String(word.dropLast(rule.suffix.count)) + rule.rep)
            }
        }

        // 3. Irregular Verbs (Kuru / Suru)
        let irregularForms: [(suffix: String, rep: String)] = [
            ("しない", "する"), ("した", "する"), ("して", "する"),
            ("します", "する"), ("しました", "する"), ("しません", "する"),
            ("できる", "する"), ("される", "する"), ("させる", "する"),
            ("こない", "くる"), ("きた", "くる"), ("きて", "くる"),
            ("きます", "くる"), ("きました", "くる"), ("きません", "くる"),
            ("こられる", "くる"), ("こさせる", "くる")
        ]
        for rule in irregularForms {
            if word.hasSuffix(rule.suffix) && word.count >= rule.suffix.count {
                add(String(word.dropLast(rule.suffix.count)) + rule.rep)
            }
        }

        // 4. Godan Verbs - Negative Forms
        let godanNeg: [(suffix: String, rep: String)] = [
            ("わない", "う"), ("かない", "く"), ("がない", "ぐ"), ("さない", "す"),
            ("たない", "つ"), ("なない", "ぬ"), ("ばない", "ぶ"), ("まない", "む"), ("らない", "る")
        ]
        for rule in godanNeg {
            if word.hasSuffix(rule.suffix) && word.count > rule.suffix.count {
                add(String(word.dropLast(rule.suffix.count)) + rule.rep)
            }
        }

        // 5. Godan Verbs - Past / Te Forms
        let godanPast: [(suffix: String, rep: String)] = [
            ("った", "う"), ("った", "つ"), ("った", "る"),
            ("って", "う"), ("って", "つ"), ("って", "る"),
            ("いた", "く"), ("いて", "く"),
            ("いだ", "ぐ"), ("いで", "ぐ"),
            ("した", "す"), ("して", "す"),
            ("んだ", "ぬ"), ("んだ", "ぶ"), ("んだ", "む"),
            ("んで", "ぬ"), ("んで", "ぶ"), ("んで", "む")
        ]
        for rule in godanPast {
            if word.hasSuffix(rule.suffix) && word.count > rule.suffix.count {
                add(String(word.dropLast(rule.suffix.count)) + rule.rep)
            }
        }

        // 6. Godan Verbs - Polite Forms
        let godanPolite: [(suffix: String, rep: String)] = [
            ("います", "う"), ("きます", "く"), ("ぎます", "ぐ"), ("します", "す"),
            ("ちます", "つ"), ("にます", "ぬ"), ("びます", "ぶ"), ("みます", "む"), ("ります", "る"),
            ("いました", "う"), ("きました", "く"), ("ぎました", "ぐ"), ("しました", "す"),
            ("ちました", "つ"), ("にました", "ぬ"), ("びました", "ぶ"), ("みました", "む"), ("りました", "る"),
            ("いません", "う"), ("きません", "く"), ("ぎません", "ぐ"), ("しません", "す"),
            ("ちません", "つ"), ("にません", "ぬ"), ("びません", "ぶ"), ("みません", "む"), ("りません", "る"),
            ("いませんでした", "う"), ("きませんでした", "く"), ("ぎませんでした", "ぐ"), ("しませんでした", "す"),
            ("ちませんでした", "つ"), ("にませんでした", "ぬ"), ("びませんでした", "ぶ"), ("みませんでした", "む"), ("りませんでした", "る")
        ]
        for rule in godanPolite {
            if word.hasSuffix(rule.suffix) && word.count > rule.suffix.count {
                add(String(word.dropLast(rule.suffix.count)) + rule.rep)
            }
        }

        // 7. Godan Verbs - Potential & Desiderative
        let godanOther: [(suffix: String, rep: String)] = [
            ("える", "う"), ("ける", "く"), ("げる", "ぐ"), ("せる", "す"),
            ("てる", "つ"), ("ねる", "ぬ"), ("べる", "ぶ"), ("める", "む"), ("れる", "る"),
            ("いたい", "う"), ("きたい", "く"), ("ぎたい", "ぐ"), ("したい", "す"),
            ("ちたい", "つ"), ("にたい", "ぬ"), ("びたい", "ぶ"), ("みたい", "む"), ("りたい", "る")
        ]
        for rule in godanOther {
            if word.hasSuffix(rule.suffix) && word.count > rule.suffix.count {
                add(String(word.dropLast(rule.suffix.count)) + rule.rep)
            }
        }

        // 8. Volitional Forms
        let volitionalRules: [(suffix: String, rep: String)] = [
            ("よう", "る"), // Ichidan
            ("しよう", "する"), ("こよう", "くる"), // Irregular
            ("おう", "う"), ("こう", "く"), ("ごう", "ぐ"), ("そう", "す"),
            ("とう", "つ"), ("のう", "ぬ"), ("ぼう", "ぶ"), ("もう", "む"), ("ろう", "る") // Godan
        ]
        for rule in volitionalRules {
            if word.hasSuffix(rule.suffix) && word.count >= rule.suffix.count {
                add(String(word.dropLast(rule.suffix.count)) + rule.rep)
            }
        }

        // 9. Imperative Forms
        let imperativeRules: [(suffix: String, rep: String)] = [
            ("え", "う"), ("け", "く"), ("げ", "ぐ"), ("せ", "す"),
            ("て", "つ"), ("ね", "ぬ"), ("べ", "ぶ"), ("め", "む"), ("れ", "る")
        ]
        for rule in imperativeRules {
            if word.hasSuffix(rule.suffix) && word.count > rule.suffix.count {
                add(String(word.dropLast(rule.suffix.count)) + rule.rep)
            }
        }

        return candidates
    }

}
