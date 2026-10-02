//
//  JapaneseDictionaryServiceTests.swift
//  SnapTra TranslatorTests
//
//  Tests for embedded Japanese dictionary engine and de-inflector.
//

import XCTest
@testable import KakuTra

final class JapaneseDictionaryServiceTests: XCTestCase {

    var service: JapaneseDictionaryService!

    override func setUp() {
        super.setUp()
        service = JapaneseDictionaryService.shared
    }

    func testDeinflectionCandidates() {
        // Ichidan verbs
        let tabeta = service.deinflect("食べた")
        XCTAssertTrue(tabeta.contains("食べる"), "Expected 食べる in candidates for 食べた: \(tabeta)")

        let tabenai = service.deinflect("食べない")
        XCTAssertTrue(tabenai.contains("食べる"), "Expected 食べる in candidates for 食べない: \(tabenai)")

        let tabemasu = service.deinflect("食べます")
        XCTAssertTrue(tabemasu.contains("食べる"), "Expected 食べる in candidates for 食べます: \(tabemasu)")

        // Godan verbs
        let yonda = service.deinflect("読んだ")
        XCTAssertTrue(yonda.contains("読む"), "Expected 読む in candidates for 読んだ: \(yonda)")

        let hanashita = service.deinflect("話した")
        XCTAssertTrue(hanashita.contains("話す"), "Expected 話す in candidates for 話した: \(hanashita)")

        let katta = service.deinflect("買った")
        XCTAssertTrue(katta.contains("買う"), "Expected 買う in candidates for 買った: \(katta)")

        let matta = service.deinflect("待った")
        XCTAssertTrue(matta.contains("待つ"), "Expected 待つ in candidates for 待った: \(matta)")

        let oyoida = service.deinflect("泳いだ")
        XCTAssertTrue(oyoida.contains("泳ぐ"), "Expected 泳ぐ in candidates for 泳いだ: \(oyoida)")

        let itta = service.deinflect("行った")
        XCTAssertTrue(itta.contains("行く"), "Expected 行く in candidates for 行った: \(itta)")

        let ikimashita = service.deinflect("行きました")
        XCTAssertTrue(ikimashita.contains("行く"), "Expected 行く in candidates for 行きました: \(ikimashita)")

        // Adjectives
        let oishikatta = service.deinflect("美味しかった")
        XCTAssertTrue(oishikatta.contains("美味しい"), "Expected 美味しい in candidates for 美味しかった: \(oishikatta)")

        let takakunai = service.deinflect("高くない")
        XCTAssertTrue(takakunai.contains("高い"), "Expected 高い in candidates for 高くない: \(takakunai)")

        // Irregulars (suru / kuru)
        let benkyoushita = service.deinflect("勉強した")
        XCTAssertTrue(benkyoushita.contains("勉強する"), "Expected 勉強する in candidates for 勉強した: \(benkyoushita)")

        let mottekita = service.deinflect("持ってきた")
        XCTAssertTrue(mottekita.contains("持ってくる"), "Expected 持ってくる in candidates for 持ってきた: \(mottekita)")
    }

    func testDatabaseLookup() {
        guard service.isDatabaseInstalled else {
            XCTFail("kakutra_japanese.db must be installed in Application Support")
            return
        }

        // Exact term lookup
        let results = service.lookup("食べる")
        XCTAssertFalse(results.isEmpty, "Expected results for 食べる")
        XCTAssertEqual(results.first?.term, "食べる")
        XCTAssertEqual(results.first?.reading, "たべる")

        // Inflected term lookup
        let inflectedResults = service.lookup("食べた")
        XCTAssertFalse(inflectedResults.isEmpty, "Expected results for inflected 食べた")
        XCTAssertEqual(inflectedResults.first?.term, "食べる")

        // Adjective inflected lookup
        let adjResults = service.lookup("美味しかった")
        XCTAssertFalse(adjResults.isEmpty, "Expected results for 美味しかった")
        XCTAssertEqual(adjResults.first?.term, "美味しい")

        // Reading lookup (Hiragana)
        let readingResults = service.lookup("ねこ")
        XCTAssertFalse(readingResults.isEmpty, "Expected results for reading ねこ")
    }

    func testGlossaryLanguagePreference() {
        guard service.isDatabaseInstalled else { return }

        // French preference
        let frResults = service.lookup("食べる", preferredGlossaryLanguage: "fr")
        XCTAssertFalse(frResults.isEmpty)
        XCTAssertTrue(frResults.first?.dictionary.contains("Français") == true)

        // English preference
        let enResults = service.lookup("食べる", preferredGlossaryLanguage: "en")
        XCTAssertFalse(enResults.isEmpty)
        XCTAssertTrue(enResults.first?.dictionary.contains("English") == true)
    }
}
