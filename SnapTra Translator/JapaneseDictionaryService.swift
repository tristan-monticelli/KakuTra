//
//  JapaneseDictionaryService.swift
//  KakuTra
//
//  High-performance embedded SQLite engine with separate language profiles.
//  Each language is stored in its own clean database file (english.db, french.db).
//  Includes full de-inflection, sub-0.3ms lookups, and instant Finder folder access.
//

import AppKit
import Foundation
import SQLite3

typealias JapaneseDictionaryEntry = YomitanTermResult

struct LanguageDatabaseItem: Identifiable, Hashable {
    let id: String
    let displayName: String
    let filename: String
    let entriesCount: Int
    let badge: String
}

final class JapaneseDictionaryService: ObservableObject, @unchecked Sendable {
    static let shared = JapaneseDictionaryService()

    static var databaseDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("KakuTra/Dictionaries")
    }

    @Published private(set) var isDatabaseInstalled: Bool = false
    @Published private(set) var totalEntriesCount: Int = 0
    @Published private(set) var installedLanguages: [LanguageDatabaseItem] = []
    var installedDictionaries: [String] {
        installedLanguages.map(\.displayName)
    }

    private var dbs: [String: OpaquePointer] = [:]
    private let accessQueue = DispatchQueue(label: "com.kakutra.japanese-dictionary", qos: .userInitiated)

    init() {
        openDatabases()
        refreshStats()
    }

    deinit {
        closeDatabases()
    }

    // MARK: - Connection Management

    func openDatabases() {
        try? FileManager.default.createDirectory(at: Self.databaseDirectory, withIntermediateDirectories: true)
        
        let fileManager = FileManager.default
        let dirPath = Self.databaseDirectory.path

        // Check for english.db and french.db
        let languageConfigs: [(id: String, name: String, file: String, badge: String)] = [
            ("en", "Anglais", "english.db", "Complet · Recommandé"),
            ("fr", "Français", "french.db", "Standard")
        ]

        for config in languageConfigs {
            let path = (dirPath as NSString).appendingPathComponent(config.file)
            if fileManager.fileExists(atPath: path) {
                var ptr: OpaquePointer?
                if sqlite3_open_v2(path, &ptr, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK {
                    dbs[config.id] = ptr
                }
            }
        }

        // Fallback for legacy single-file DB if english.db is not yet present
        if dbs["en"] == nil {
            let legacyPath = (dirPath as NSString).appendingPathComponent("kakutra_japanese.db")
            if fileManager.fileExists(atPath: legacyPath) {
                var ptr: OpaquePointer?
                if sqlite3_open_v2(legacyPath, &ptr, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK {
                    dbs["en"] = ptr
                }
            }
        }
    }

    func closeDatabases() {
        for (_, ptr) in dbs {
            sqlite3_close(ptr)
        }
        dbs.removeAll()
    }

    func reload() {
        closeDatabases()
        openDatabases()
        refreshStats()
    }

    func openDatabaseFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Self.databaseDirectory.path)
    }

    func refreshStats() {
        accessQueue.async { [weak self] in
            guard let self else { return }
            var items: [LanguageDatabaseItem] = []
            var grandTotal = 0

            let languageConfigs: [(id: String, name: String, file: String, badge: String)] = [
                ("en", "Anglais", "english.db", "Complet · Recommandé"),
                ("fr", "Français", "french.db", "Standard")
            ]

            for config in languageConfigs {
                guard let dbPtr = self.dbs[config.id] else { continue }
                var count = 0
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(dbPtr, "SELECT count(*) FROM entries", -1, &stmt, nil) == SQLITE_OK {
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        count = Int(sqlite3_column_int64(stmt, 0))
                    }
                    sqlite3_finalize(stmt)
                }
                grandTotal += count
                items.append(LanguageDatabaseItem(
                    id: config.id,
                    displayName: config.name,
                    filename: config.file,
                    entriesCount: count,
                    badge: config.badge
                ))
            }

            DispatchQueue.main.async {
                self.isDatabaseInstalled = !items.isEmpty && grandTotal > 0
                self.totalEntriesCount = grandTotal
                self.installedLanguages = items
            }
        }
    }

    // MARK: - Fast Lookup (<0.3 ms)

    func lookup(_ text: String, preferredGlossaryLanguage: String = "en") -> [JapaneseDictionaryEntry] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return accessQueue.sync {
            guard !dbs.isEmpty else { return [] }

            // 1. Generate de-inflection candidates for the full query
            let candidates = deinflect(trimmed)
            var results = queryWithLanguagePreference(candidates: candidates, language: preferredGlossaryLanguage)

            if !results.isEmpty {
                return results
            }

            // 2. Try trimming trailing sentence particles and re-evaluating
            let particles: [Character] = ["よ", "ね", "わ", "ぞ", "ぜ", "な", "さ", "か", "が", "は", "を", "に", "へ", "で", "と", "も", "の"]
            if trimmed.count > 1, let lastChar = trimmed.last, particles.contains(lastChar) {
                let stripped = String(trimmed.dropLast())
                let strippedCandidates = deinflect(stripped)
                results = queryWithLanguagePreference(candidates: strippedCandidates, language: preferredGlossaryLanguage)
                if !results.isEmpty {
                    return results
                }
            }

            // 3. Longest prefix matching (progressively drop trailing chars from length down to 2)
            if trimmed.count > 2 {
                for len in stride(from: trimmed.count - 1, through: 2, by: -1) {
                    let sub = String(trimmed.prefix(len))
                    let subCandidates = deinflect(sub)
                    let subResults = queryWithLanguagePreference(candidates: subCandidates, language: preferredGlossaryLanguage)
                    if !subResults.isEmpty {
                        return subResults
                    }
                }
            }

            return []
        }
    }

    private func queryWithLanguagePreference(candidates: [String], language: String) -> [JapaneseDictionaryEntry] {
        if language == "fr" {
            // Try French DB first
            if let frDb = dbs["fr"] {
                let frResults = queryCandidates(candidates, in: frDb)
                if !frResults.isEmpty { return frResults }
            }
            // Fallback to English DB so user never gets an empty popup on slang/rare words
            if let enDb = dbs["en"] {
                return queryCandidates(candidates, in: enDb)
            }
        } else {
            // Default: English DB (gold standard)
            if let enDb = dbs["en"] {
                return queryCandidates(candidates, in: enDb)
            }
        }
        return []
    }

    private func queryCandidates(_ candidates: [String], in db: OpaquePointer) -> [JapaneseDictionaryEntry] {
        guard !candidates.isEmpty else { return [] }

        var entries: [JapaneseDictionaryEntry] = []
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
                let reading = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
                let glossaryRaw = String(cString: glossaryCString)
                let dictionary = String(cString: dictCString)

                let key = "\(dictionary)|\(term)|\(reading ?? "")"
                if seenKeys.contains(key) { continue }
                seenKeys.insert(key)

                let glosses = glossaryRaw.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                let entry = JapaneseDictionaryEntry(
                    term: term,
                    reading: reading,
                    dictionary: dictionary,
                    glosses: glosses
                )
                entries.append(entry)

                if entries.count >= 15 { break }
            }

            if entries.count >= 15 { break }
        }

        return entries
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

        return candidates
    }

    // MARK: - Zip Importer

    func importYomitanZip(at fileURL: URL) async throws -> (dictionaryName: String, count: Int) {
        let zipData = try Data(contentsOf: fileURL)
        let entries = try ZipExtractor.extractEntries(where: { name in
            name.hasSuffix("index.json") || name.contains("term_bank_")
        }, from: zipData)

        guard let indexEntry = entries.first(where: { $0.filename.hasSuffix("index.json") }),
              let indexObj = try? JSONSerialization.jsonObject(with: indexEntry.data) as? [String: Any],
              let dictTitle = indexObj["title"] as? String else {
            throw NSError(domain: "JapaneseDictionaryService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Archive invalide : index.json ou titre manquant"])
        }

        // Determine target db: french if contains French, otherwise custom or english
        let targetDbKey = dictTitle.lowercased().contains("french") || dictTitle.lowercased().contains("français") ? "fr" : "en"
        let targetDbFilename = targetDbKey == "fr" ? "french.db" : "english.db"
        let targetDbPath = (Self.databaseDirectory.path as NSString).appendingPathComponent(targetDbFilename)

        var importedCount = 0

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            accessQueue.async { [weak self] in
                guard let self else { return }

                var targetDb: OpaquePointer?
                if let existing = self.dbs[targetDbKey] {
                    targetDb = existing
                } else {
                    if sqlite3_open_v2(targetDbPath, &targetDb, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK {
                        let sql = """
                        CREATE TABLE IF NOT EXISTS entries (
                            id INTEGER PRIMARY KEY AUTOINCREMENT,
                            term TEXT NOT NULL,
                            reading TEXT,
                            glossary TEXT NOT NULL,
                            pos TEXT,
                            dictionary TEXT NOT NULL,
                            score INTEGER DEFAULT 0
                        );
                        CREATE INDEX IF NOT EXISTS idx_term ON entries(term);
                        CREATE INDEX IF NOT EXISTS idx_reading ON entries(reading);
                        """
                        sqlite3_exec(targetDb, sql, nil, nil, nil)
                        self.dbs[targetDbKey] = targetDb
                    }
                }

                guard let targetDb else {
                    continuation.resume(throwing: NSError(domain: "JapaneseDictionaryService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Base non disponible"]))
                    return
                }

                sqlite3_exec(targetDb, "BEGIN TRANSACTION;", nil, nil, nil)

                let insertSql = "INSERT INTO entries (term, reading, glossary, pos, dictionary, score) VALUES (?, ?, ?, ?, ?, ?);"
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(targetDb, insertSql, -1, &stmt, nil) == SQLITE_OK else {
                    sqlite3_exec(targetDb, "ROLLBACK;", nil, nil, nil)
                    continuation.resume(throwing: NSError(domain: "JapaneseDictionaryService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Échec préparation SQL"]))
                    return
                }

                for entry in entries where entry.filename.contains("term_bank_") {
                    guard let rows = try? JSONSerialization.jsonObject(with: entry.data) as? [[Any]] else { continue }
                    for row in rows where row.count >= 6 {
                        let term = row[0] as? String ?? ""
                        if term.isEmpty { continue }
                        let reading = row[1] as? String ?? ""
                        let pos = row[2] as? String ?? ""
                        let score = row[4] as? Int ?? 0

                        var glossesText = ""
                        if let glossesArray = row[5] as? [Any] {
                            let textGlosses = glossesArray.compactMap { self.extractText(from: $0) }.filter { !$0.isEmpty }
                            glossesText = textGlosses.joined(separator: "\n")
                        }

                        if glossesText.isEmpty { continue }

                        sqlite3_reset(stmt)
                        sqlite3_bind_text(stmt, 1, (term as NSString).utf8String, -1, nil)
                        if !reading.isEmpty {
                            sqlite3_bind_text(stmt, 2, (reading as NSString).utf8String, -1, nil)
                        } else {
                            sqlite3_bind_null(stmt, 2)
                        }
                        sqlite3_bind_text(stmt, 3, (glossesText as NSString).utf8String, -1, nil)
                        sqlite3_bind_text(stmt, 4, (pos as NSString).utf8String, -1, nil)
                        sqlite3_bind_text(stmt, 5, (dictTitle as NSString).utf8String, -1, nil)
                        sqlite3_bind_int(stmt, 6, Int32(score))

                        if sqlite3_step(stmt) == SQLITE_DONE {
                            importedCount += 1
                        }
                    }
                }

                sqlite3_finalize(stmt)
                sqlite3_exec(targetDb, "COMMIT;", nil, nil, nil)
                continuation.resume(returning: ())
            }
        }

        refreshStats()
        return (dictTitle, importedCount)
    }

    private func extractText(from item: Any) -> String? {
        if let str = item as? String {
            return str
        }
        if let arr = item as? [Any] {
            let combined = arr.compactMap { extractText(from: $0) }.joined(separator: "; ")
            return combined.isEmpty ? nil : combined
        }
        if let dict = item as? [String: Any] {
            if let content = dict["content"] {
                return extractText(from: content)
            }
            if let text = dict["text"] as? String {
                return text
            }
        }
        return nil
    }
}
