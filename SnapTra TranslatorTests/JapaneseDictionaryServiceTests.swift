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
        // Jitendex dictionary lookup
        let enResults = service.lookup("食べる", preferredGlossaryLanguage: "en")
        XCTAssertFalse(enResults.isEmpty)
        XCTAssertEqual(enResults.first?.term, "食べる")
        XCTAssertEqual(enResults.first?.dictionary, "Jitendex")
    }

    func testChineseLookup() {
        // Simplified
        let zhSimp = service.lookupChinese("电脑")
        XCTAssertFalse(zhSimp.isEmpty, "Expected CC-CEDICT results for 电脑")
        XCTAssertEqual(zhSimp.first?.term, "电脑")
        XCTAssertEqual(zhSimp.first?.reading, "diànnǎo")
        XCTAssertEqual(zhSimp.first?.dictionary, "CC-CEDICT")

        // Traditional
        let zhTrad = service.lookupChinese("電腦")
        XCTAssertFalse(zhTrad.isEmpty, "Expected CC-CEDICT results for 電腦")
        XCTAssertEqual(zhTrad.first?.term, "電腦")

        // Common phrase
        let hello = service.lookupChinese("你好")
        XCTAssertFalse(hello.isEmpty, "Expected CC-CEDICT results for 你好")
        XCTAssertEqual(hello.first?.reading, "nǐhǎo")

        // Punctuation stripping (quotes, period, exclamation mark)
        let quoted = service.lookupChinese("“电脑”")
        XCTAssertFalse(quoted.isEmpty, "Expected results for quoted “电脑”")
        XCTAssertEqual(quoted.first?.term, "电脑")

        let withPeriod = service.lookupChinese("电脑。")
        XCTAssertFalse(withPeriod.isEmpty, "Expected results for 电脑。")
        XCTAssertEqual(withPeriod.first?.term, "电脑")

        // Single character Hanzi
        let cat = service.lookupChinese("猫")
        XCTAssertFalse(cat.isEmpty, "Expected results for single char 猫")

        let person = service.lookupChinese("人")
        XCTAssertFalse(person.isEmpty, "Expected results for single char 人")
    }

    func testKoreanLookup() {
        // Exact term
        let cat = service.lookupKorean("고양이")
        XCTAssertFalse(cat.isEmpty, "Expected KRDICT results for 고양이")
        XCTAssertEqual(cat.first?.term, "고양이")
        XCTAssertEqual(cat.first?.dictionary, "KRDICT")

        // Punctuation stripping
        let catPunct = service.lookupKorean("고양이.")
        XCTAssertFalse(catPunct.isEmpty, "Expected KRDICT results for 고양이.")
        XCTAssertEqual(catPunct.first?.term, "고양이")

        // Korean verb de-inflection (e.g. 안녕하세요 -> 안녕하다)
        let hello = service.lookupKorean("안녕하세요")
        XCTAssertFalse(hello.isEmpty, "Expected KRDICT results for 안녕하세요 via de-inflection to 안녕하다")
        XCTAssertEqual(hello.first?.term, "안녕하다")

        let helloExcl = service.lookupKorean("안녕하세요!")
        XCTAssertFalse(helloExcl.isEmpty, "Expected KRDICT results for 안녕하세요!")
        XCTAssertEqual(helloExcl.first?.term, "안녕하다")

        // Particle removal (e.g. 사람은 -> 사람)
        let person = service.lookupKorean("사람은")
        XCTAssertFalse(person.isEmpty, "Expected KRDICT results for 사람은 via particle removal to 사람")
        XCTAssertEqual(person.first?.term, "사람")

        let catSubj = service.lookupKorean("고양이가")
        XCTAssertFalse(catSubj.isEmpty, "Expected KRDICT results for 고양이가")
        XCTAssertEqual(catSubj.first?.term, "고양이")

        let friendDative = service.lookupKorean("친구에게")
        XCTAssertFalse(friendDative.isEmpty, "Expected KRDICT results for 친구에게")
        XCTAssertEqual(friendDative.first?.term, "친구")

        // Advanced verb de-inflections: past, present polite, formal, connectives
        let atePast = service.lookupKorean("먹었다")
        XCTAssertFalse(atePast.isEmpty, "Expected KRDICT results for 먹었다 via de-inflection to 먹다")
        XCTAssertEqual(atePast.first?.term, "먹다")

        let atePolite = service.lookupKorean("먹었어요")
        XCTAssertFalse(atePolite.isEmpty, "Expected KRDICT results for 먹었어요 via de-inflection to 먹다")
        XCTAssertEqual(atePolite.first?.term, "먹다")

        let eatFormal = service.lookupKorean("먹습니다")
        XCTAssertFalse(eatFormal.isEmpty, "Expected KRDICT results for 먹습니다 via de-inflection to 먹다")
        XCTAssertEqual(eatFormal.first?.term, "먹다")

        let wentPast = service.lookupKorean("갔다")
        XCTAssertFalse(wentPast.isEmpty, "Expected KRDICT results for 갔다 via de-inflection to 가다")
        XCTAssertEqual(wentPast.first?.term, "가다")

        let sawPast = service.lookupKorean("봤다")
        XCTAssertFalse(sawPast.isEmpty, "Expected KRDICT results for 봤다 via de-inflection to 보다")
        XCTAssertEqual(sawPast.first?.term, "보다")

        let goodPast = service.lookupKorean("좋았다")
        XCTAssertFalse(goodPast.isEmpty, "Expected KRDICT results for 좋았다 via de-inflection to 좋다")
        XCTAssertEqual(goodPast.first?.term, "좋다")

        let goodPolite = service.lookupKorean("좋아요")
        XCTAssertFalse(goodPolite.isEmpty, "Expected KRDICT results for 좋아요 via de-inflection to 좋다")
        XCTAssertEqual(goodPolite.first?.term, "좋다")

        let prettyPolite = service.lookupKorean("예뻐요")
        XCTAssertFalse(prettyPolite.isEmpty, "Expected KRDICT results for 예뻐요 via de-inflection to 예쁘다")
        XCTAssertEqual(prettyPolite.first?.term, "예쁘다")
    }

    func testJapanesePunctuationStripping() {
        let bracketed = service.lookup("「食べる」")
        XCTAssertFalse(bracketed.isEmpty, "Expected results for 「食べる」")
        XCTAssertEqual(bracketed.first?.term, "食べる")

        let period = service.lookup("食べる。")
        XCTAssertFalse(period.isEmpty, "Expected results for 食べる。")
        XCTAssertEqual(period.first?.term, "食べる")
    }
}
