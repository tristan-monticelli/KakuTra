import XCTest
@testable import KakuTra

final class LookupLanguagePairTests: XCTestCase {
    func testPairUsesFixedSourceAndTargetIdentifiers() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "ja", targetIdentifier: "en")

        XCTAssertEqual(pair.sourceIdentifier, "ja")
        XCTAssertEqual(pair.targetIdentifier, "en")
        XCTAssertEqual(pair.key, "ja->en")
        XCTAssertFalse(pair.isSameLanguage)
    }

    func testSameLanguageDetection() {
        let pair = LookupLanguagePair.fixed(sourceIdentifier: "en", targetIdentifier: "en-US")

        XCTAssertTrue(pair.isSameLanguage)
    }
}
