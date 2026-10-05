# Chinese-English Auto Translation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Chinese-English automatic mutual translation mode that detects whether the token under the cursor is Chinese or English, then translates it into the opposite language with the existing shortcut workflow.

**Architecture:** Keep the current shortcut -> screen capture -> OCR -> overlay pipeline, but make lookup direction request-scoped instead of globally fixed. Introduce a token classification layer that works for both Chinese and English, then propagate the resolved direction through translation, TTS, dictionary preference, and language-pack checks.

**Tech Stack:** Swift, SwiftUI, Vision, NaturalLanguage, Translation, XCTest, ScreenCaptureKit

---

### Task 1: Add Test Target and Smoke Coverage

**Files:**
- Modify: `KakuTra Translator.xcodeproj/project.pbxproj`
- Create: `KakuTra TranslatorTests/SmokeTests.swift`

**Step 1: Add the failing test target scaffold**

Create a macOS unit-test target named `KakuTra TranslatorTests` and add a minimal smoke test:

```swift
import XCTest
@testable import KakuTra_Translator

final class SmokeTests: XCTestCase {
    func testSmoke() {
        XCTAssertTrue(true)
    }
}
```

**Step 2: Run tests to verify the harness works**

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test
```

Expected: PASS with the new smoke test executing.

**Step 3: Commit**

```bash
git add "KakuTra Translator.xcodeproj/project.pbxproj" "KakuTra TranslatorTests/SmokeTests.swift"
git commit -m "test: add macOS unit test target"
```

### Task 2: Add Lookup Direction Model and Unit Tests

**Files:**
- Create: `KakuTra Translator/LookupDirection.swift`
- Create: `KakuTra TranslatorTests/LookupDirectionTests.swift`

**Step 1: Write the failing tests**

```swift
import XCTest
@testable import KakuTra_Translator

final class LookupDirectionTests: XCTestCase {
    func testResolvesEnglishTokenToEnglishToChinese() {
        let result = LookupDirectionResolver.resolveDirection(
            for: "hello",
            defaultDirection: .englishToChinese,
            lastResolvedDirection: nil
        )

        XCTAssertEqual(result, .englishToChinese)
    }

    func testResolvesChineseTokenToChineseToEnglish() {
        let result = LookupDirectionResolver.resolveDirection(
            for: "你好",
            defaultDirection: .englishToChinese,
            lastResolvedDirection: nil
        )

        XCTAssertEqual(result, .chineseToEnglish)
    }

    func testFallsBackToLastResolvedDirectionForAmbiguousToken() {
        let result = LookupDirectionResolver.resolveDirection(
            for: "2026",
            defaultDirection: .englishToChinese,
            lastResolvedDirection: .chineseToEnglish
        )

        XCTAssertEqual(result, .chineseToEnglish)
    }
}
```

**Step 2: Run the test to verify it fails**

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test -only-testing:"KakuTra TranslatorTests/LookupDirectionTests"
```

Expected: FAIL because `LookupDirectionResolver` does not exist yet.

**Step 3: Write the minimal implementation**

Add a pure Swift helper that defines:

```swift
enum LookupDirection {
    case englishToChinese
    case chineseToEnglish
}

enum LookupDirectionResolver {
    static func resolveDirection(
        for token: String,
        defaultDirection: LookupDirection,
        lastResolvedDirection: LookupDirection?
    ) -> LookupDirection {
        let hasHan = token.unicodeScalars.contains { $0.properties.isIdeographic }
        let hasLatin = token.unicodeScalars.contains { CharacterSet.letters.contains($0) && $0.properties.script == .latin }

        if hasHan { return .chineseToEnglish }
        if hasLatin { return .englishToChinese }
        return lastResolvedDirection ?? defaultDirection
    }
}
```

**Step 4: Run the tests to verify they pass**

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test -only-testing:"KakuTra TranslatorTests/LookupDirectionTests"
```

Expected: PASS.

**Step 5: Commit**

```bash
git add "KakuTra Translator/LookupDirection.swift" "KakuTra TranslatorTests/LookupDirectionTests.swift"
git commit -m "feat: add lookup direction resolver"
```

### Task 3: Add Translation Mode Settings and Persistence

**Files:**
- Modify: `KakuTra Translator/AppSettings.swift`
- Modify: `KakuTra Translator/SettingsStore.swift`
- Create: `KakuTra TranslatorTests/SettingsStoreTests.swift`

**Step 1: Write the failing tests**

```swift
import XCTest
@testable import KakuTra_Translator

final class SettingsStoreTests: XCTestCase {
    func testDefaultsToFixedDirectionMode() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.translationMode, .fixedDirection)
        XCTAssertEqual(store.defaultLookupDirection, .englishToChinese)
    }

    func testPersistsAutoMutualTranslationMode() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        let store = SettingsStore(defaults: defaults)
        store.translationMode = .autoMutualChineseEnglish

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.translationMode, .autoMutualChineseEnglish)
    }
}
```

**Step 2: Run the test to verify it fails**

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test -only-testing:"KakuTra TranslatorTests/SettingsStoreTests"
```

Expected: FAIL because the new settings do not exist.

**Step 3: Write the minimal implementation**

Add new settings primitives in `AppSettings.swift`:

```swift
enum TranslationMode: String, CaseIterable, Identifiable {
    case fixedDirection
    case autoMutualChineseEnglish
}

extension TranslationMode {
    var id: String { rawValue }
}

enum DefaultLookupDirection: String, CaseIterable, Identifiable {
    case englishToChinese
    case chineseToEnglish
}
```

Persist them in `SettingsStore.swift` with new keys:

```swift
@Published var translationMode: TranslationMode
@Published var defaultLookupDirection: DefaultLookupDirection
```

Use conservative defaults:

- `translationMode = .fixedDirection`
- `defaultLookupDirection = .englishToChinese`

**Step 4: Run the tests and a build**

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test -only-testing:"KakuTra TranslatorTests/SettingsStoreTests"
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -configuration Debug build
```

Expected: tests PASS, build PASS.

**Step 5: Commit**

```bash
git add "KakuTra Translator/AppSettings.swift" "KakuTra Translator/SettingsStore.swift" "KakuTra TranslatorTests/SettingsStoreTests.swift"
git commit -m "feat: add auto translation settings model"
```

### Task 4: Update Settings UI for Chinese-English Mutual Translation

**Files:**
- Modify: `KakuTra Translator/SettingsWindowView.swift`
- Modify: `KakuTra Translator/Localizable.xcstrings`

**Step 1: Write the failing UI behavior check**

Build the app with the expectation that the settings UI now exposes:

- translation mode
- default direction
- Chinese-English pair messaging

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -configuration Debug build
```

Expected: BUILD FAIL until the UI references the new settings model correctly.

**Step 2: Write the minimal implementation**

Replace the single `Translate to` row with a small grouped settings surface:

```swift
Picker(L("Translation Mode"), selection: $model.settings.translationMode) {
    Text(L("Fixed Direction")).tag(TranslationMode.fixedDirection)
    Text(L("Chinese <> English Auto")).tag(TranslationMode.autoMutualChineseEnglish)
}

Picker(L("Default Direction"), selection: $model.settings.defaultLookupDirection) {
    Text(L("English -> Chinese")).tag(DefaultLookupDirection.englishToChinese)
    Text(L("Chinese -> English")).tag(DefaultLookupDirection.chineseToEnglish)
}
```

Behavior rules:

- When `translationMode == .autoMutualChineseEnglish`, show that both directions must be installed.
- Keep the control narrow in scope: do not add general language-pair auto-detection UI.

**Step 3: Run the build**

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -configuration Debug build
```

Expected: BUILD PASS.

**Step 4: Commit**

```bash
git add "KakuTra Translator/SettingsWindowView.swift" "KakuTra Translator/Localizable.xcstrings"
git commit -m "feat: add auto mutual translation controls"
```

### Task 5: Refactor Translation Bridge to Honor Request-Scoped Direction

**Files:**
- Modify: `KakuTra Translator/TranslationService.swift`
- Create: `KakuTra TranslatorTests/TranslationRequestContextTests.swift`

**Step 1: Write the failing tests**

Keep the unit test focused on request direction plumbing instead of the system translation API:

```swift
import XCTest
@testable import KakuTra_Translator

final class TranslationRequestContextTests: XCTestCase {
    func testBuildsConfigurationKeyFromRequestDirection() {
        let key = TranslationRequestContext.configurationKey(
            source: .init(identifier: "en"),
            target: .init(identifier: "zh-Hans")
        )

        XCTAssertEqual(key, "en->zh")
    }
}
```

**Step 2: Run the test to verify the current bridge is not enough**

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test -only-testing:"KakuTra TranslatorTests/TranslationRequestContextTests"
```

Expected: FAIL because `TranslationRequestContext` does not exist yet.

**Step 3: Write the minimal implementation**

Refactor `TranslationBridgeView` so it rebuilds or routes `TranslationSession.Configuration` from the request instead of only from global settings.

Target shape:

```swift
enum TranslationRequestContext {
    static func configurationKey(
        source: Locale.Language?,
        target: Locale.Language
    ) -> String {
        let sourceID = source?.minimalIdentifier ?? "auto"
        return "\(sourceID)->\(target.minimalIdentifier)"
    }
}
```

Implementation requirements:

- Do not ignore `request.source` and `request.target`.
- Keep a request-scoped configuration cache or rebuild path keyed by the resolved direction.
- Avoid leaking stale requests when direction changes rapidly in continuous mode.
- Preserve timeout behavior.

**Step 4: Run the tests and build**

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test -only-testing:"KakuTra TranslatorTests/TranslationRequestContextTests"
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -configuration Debug build
```

Expected: PASS.

**Step 5: Commit**

```bash
git add "KakuTra Translator/TranslationService.swift" "KakuTra TranslatorTests/TranslationRequestContextTests.swift"
git commit -m "refactor: make translation bridge request scoped"
```

### Task 6: Upgrade OCR Tokenization for Chinese and English

**Files:**
- Modify: `KakuTra Translator/OCRService.swift`
- Create: `KakuTra TranslatorTests/OCRTokenizationTests.swift`

**Step 1: Write the failing tests**

```swift
import XCTest
@testable import KakuTra_Translator

final class OCRTokenizationTests: XCTestCase {
    func testTokenizesEnglishWords() {
        XCTAssertEqual(
            OCRTokenizationHelper.tokenTexts(in: "hello world"),
            ["hello", "world"]
        )
    }

    func testTokenizesChineseWords() {
        XCTAssertFalse(OCRTokenizationHelper.tokenTexts(in: "你好世界").isEmpty)
    }

    func testSplitsCamelCaseAfterPrimaryTokenization() {
        XCTAssertEqual(
            OCRTokenizationHelper.tokenTexts(in: "HelloWorld"),
            ["Hello", "World"]
        )
    }
}
```

**Step 2: Run the test to verify it fails**

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test -only-testing:"KakuTra TranslatorTests/OCRTokenizationTests"
```

Expected: FAIL because the helper does not exist and the current implementation is English-only.

**Step 3: Write the minimal implementation**

In `OCRService.swift`:

- rename or extend `RecognizedWord` into a token-oriented model
- add an internal `NaturalLanguage`-based tokenization helper
- classify each token as Chinese, English, mixed, or unknown
- keep fallback bounding-box estimation for unsupported Vision range cases

Target helper shape:

```swift
enum OCRTokenScript {
    case chinese
    case english
    case mixed
    case unknown
}

enum OCRTokenizationHelper {
    static func tokenTexts(in text: String) -> [String] { ... }
}
```

**Step 4: Run the tests and build**

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test -only-testing:"KakuTra TranslatorTests/OCRTokenizationTests"
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -configuration Debug build
```

Expected: PASS.

**Step 5: Commit**

```bash
git add "KakuTra Translator/OCRService.swift" "KakuTra TranslatorTests/OCRTokenizationTests.swift"
git commit -m "feat: support chinese and english OCR tokens"
```

### Task 7: Integrate Dynamic Direction into AppModel and Language-Pack Checks

**Files:**
- Modify: `KakuTra Translator/AppModel.swift`
- Modify: `KakuTra Translator/LanguagePackManager.swift`
- Modify: `KakuTra Translator/Snap_TranslateApp.swift`

**Step 1: Write the failing integration-oriented unit test**

Create a small pure helper test around effective-direction mapping:

```swift
import XCTest
@testable import KakuTra_Translator

final class EffectiveLookupContextTests: XCTestCase {
    func testBuildsChineseToEnglishContext() {
        let context = EffectiveLookupContext.make(
            token: "你好",
            mode: .autoMutualChineseEnglish,
            defaultDirection: .englishToChinese,
            lastResolvedDirection: nil
        )

        XCTAssertEqual(context.sourceIdentifier, "zh-Hans")
        XCTAssertEqual(context.targetIdentifier, "en")
    }
}
```

**Step 2: Run the test to verify it fails**

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test -only-testing:"KakuTra TranslatorTests/EffectiveLookupContextTests"
```

Expected: FAIL because `EffectiveLookupContext` does not exist yet.

**Step 3: Write the minimal implementation**

Update `AppModel.swift` so each lookup:

- resolves direction from the selected token
- uses that direction for `translationBridge.translate`
- uses that direction for pronunciation language
- uses that direction for dictionary preference
- stores the last successful direction for ambiguous-token fallback

Update `LanguagePackManager.swift` and startup readiness logic so auto mode checks both directions:

```swift
[
    ("zh-Hans", "en"),
    ("en", "zh-Hans"),
]
```

**Step 4: Run tests, build, and manual verification**

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test -only-testing:"KakuTra TranslatorTests/EffectiveLookupContextTests"
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -configuration Debug build
```

Manual verification:

1. Hover an English word and confirm Chinese output.
2. Hover a Chinese word and confirm English output.
3. Keep holding the shortcut over mixed text and confirm direction switches correctly.

Expected: tests PASS, build PASS, manual verification succeeds.

**Step 5: Commit**

```bash
git add "KakuTra Translator/AppModel.swift" "KakuTra Translator/LanguagePackManager.swift" "KakuTra Translator/Snap_TranslateApp.swift"
git commit -m "feat: add zh-en auto mutual translation flow"
```

### Task 8: Final QA and Release Notes

**Files:**
- Modify: `README.zh-CN.md`
- Modify: `README.md`

**Step 1: Update feature documentation**

Add short documentation for:

- Chinese-English auto mutual translation mode
- requirement that both language-pack directions must be installed
- current dictionary limitation for Chinese-origin lookups

**Step 2: Run final verification**

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -configuration Debug build
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test
```

Expected: PASS.

**Step 3: Commit**

```bash
git add "README.md" "README.zh-CN.md"
git commit -m "docs: describe zh-en auto mutual translation"
```
