# Selected Text Sentence Translation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add selection-aware sentence translation on the existing shortcut while preserving the current OCR word lookup path as a fallback.

**Architecture:** Add a new `SelectedTextService` based on Accessibility APIs, route each lookup in `AppModel` to either sentence or OCR word mode, split service configuration into dictionary-only and translation-only responsibilities, and teach the overlay to render a sentence-specific result state.

**Tech Stack:** Swift, SwiftUI, AppKit, ApplicationServices, Swift Concurrency, XCTest, Translation

---

### Task 1: Add Accessibility Permission State

**Files:**
- Modify: `KakuTra Translator/PermissionManager.swift`
- Modify: `KakuTra Translator/SettingsView.swift`
- Modify: `KakuTra Translator/Localizable.xcstrings`

**Steps:**

1. Add `accessibility` to `PermissionStatus`.
2. Implement a status check with `AXIsProcessTrusted()`.
3. Add methods to request/open Accessibility settings.
4. Show the new permission row in settings without changing the existing screen-recording flow.
5. Build the app and confirm the new permission row renders.
6. Commit:

```bash
git add "KakuTra Translator/PermissionManager.swift" "KakuTra Translator/SettingsView.swift" "KakuTra Translator/Localizable.xcstrings"
git commit -m "feat: add accessibility permission support"
```

### Task 2: Add SelectedTextService

**Files:**
- Create: `KakuTra Translator/SelectedTextService.swift`

**Steps:**

1. Create a snapshot model for selected text, selected range, and bounds.
2. Read the focused element with AX APIs.
3. Read `kAXSelectedTextAttribute` and trim whitespace-only results to nil.
4. Read `kAXSelectedTextRangeAttribute` and resolve bounds with `kAXBoundsForRangeParameterizedAttribute`.
5. Return nil when data is incomplete so callers can fall back safely.
6. Build the app to confirm the new service compiles.
7. Commit:

```bash
git add "KakuTra Translator/SelectedTextService.swift"
git commit -m "feat: add selected text accessibility service"
```

### Task 3: Add Lookup Routing Model

**Files:**
- Modify: `KakuTra Translator/AppModel.swift`
- Create if needed: `KakuTra Translator/LookupIntent.swift`
- Test: `KakuTra TranslatorTests/SelectedTextLookupRoutingTests.swift`

**Steps:**

1. Add a small lookup intent model that distinguishes sentence selection from OCR word lookup.
2. Add pure helper logic that decides whether the pointer is inside the selection bounds.
3. Write tests for inside-bounds, outside-bounds, and missing-selection cases.
4. Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test -only-testing:"KakuTra TranslatorTests/SelectedTextLookupRoutingTests"
```

5. Fix compilation or test failures until the routing helper is stable.
6. Commit:

```bash
git add "KakuTra Translator/AppModel.swift" "KakuTra Translator/LookupIntent.swift" "KakuTra TranslatorTests/SelectedTextLookupRoutingTests.swift"
git commit -m "feat: add selection-first lookup routing"
```

### Task 4: Split AppModel Into Sentence and OCR Paths

**Files:**
- Modify: `KakuTra Translator/AppModel.swift`

**Steps:**

1. Inject `SelectedTextService` into `AppModel`.
2. At the top of `performLookup`, attempt selection lookup before screen capture.
3. Extract the current OCR logic into `performOcrWordLookup`.
4. Add `performSentenceSelectionLookup` that uses full selected text and skips OCR, pronunciation, and dictionary fan-out.
5. Keep `activeLookupID` and cancellation guards on both paths.
6. Manually verify that shortcut release still dismisses both paths.
7. Commit:

```bash
git add "KakuTra Translator/AppModel.swift"
git commit -m "feat: route shortcut lookups by selection or OCR"
```

### Task 5: Separate Dictionary and Translation Provider Configuration

**Files:**
- Modify: `KakuTra Translator/DictionarySettingsView.swift`
- Modify: `KakuTra Translator/SettingsStore.swift`
- Modify: `KakuTra Translator/AppSettings.swift`
- Test: `KakuTra TranslatorTests/SettingsStoreTests.swift`

**Steps:**

1. Add capability metadata or separate setting storage for sentence translation providers.
2. Migrate existing stored `dictionarySources` so `google` and `deepl` no longer live in the dictionary list.
3. Keep `system`, `ecdict`, `wordNet`, `bing`, and `youdao` in dictionary settings.
4. Add tests that verify old saved settings migrate deterministically.
5. Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test -only-testing:"KakuTra TranslatorTests/SettingsStoreTests"
```

6. Commit:

```bash
git add "KakuTra Translator/DictionarySettingsView.swift" "KakuTra Translator/SettingsStore.swift" "KakuTra Translator/AppSettings.swift" "KakuTra TranslatorTests/SettingsStoreTests.swift"
git commit -m "refactor: separate dictionary and translation provider settings"
```

### Task 6: Add Sentence Translation Service Boundary

**Files:**
- Modify: `KakuTra Translator/TranslationService.swift`
- Create if needed: `KakuTra Translator/SentenceTranslationService.swift`
- Modify: `KakuTra Translator/AppModel.swift`

**Steps:**

1. Add a sentence-translation entry point that accepts full text.
2. Keep the existing system translation bridge as the default implementation.
3. Make `AppModel` call this boundary from sentence mode instead of reaching into dictionary code.
4. Preserve existing timeout and error mapping behavior.
5. Build the app and manually verify sentence text is translated with the current language pair.
6. Commit:

```bash
git add "KakuTra Translator/TranslationService.swift" "KakuTra Translator/SentenceTranslationService.swift" "KakuTra Translator/AppModel.swift"
git commit -m "refactor: add sentence translation service boundary"
```

### Task 7: Add Sentence Overlay Presentation

**Files:**
- Modify: `KakuTra Translator/AppModel.swift`
- Modify: `KakuTra Translator/OverlayView.swift`

**Steps:**

1. Extend the overlay result model to distinguish word and sentence content.
2. Add sentence-mode loading, success, and error presentation.
3. Hide phonetic and dictionary sections in sentence mode.
4. Keep copy actions available for the original text and translated text.
5. Manually verify popup width and wrapping for a long sentence.
6. Commit:

```bash
git add "KakuTra Translator/AppModel.swift" "KakuTra Translator/OverlayView.swift"
git commit -m "feat: add sentence translation overlay mode"
```

### Task 8: Verify End-to-End Behavior

**Files:**
- Modify if needed: `KakuTra TranslatorTests/*`
- Modify if needed: `README*.md`

**Steps:**

1. Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -configuration Debug build
```

2. Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test
```

3. Manually verify:
   - selected sentence + pointer inside selection -> sentence translation
   - selected sentence + pointer outside selection -> OCR word lookup
   - missing Accessibility permission -> OCR fallback
   - holding the shortcut over a selection does not continuously retrigger sentence mode
4. Update docs if any user-facing behavior or permission wording changed.
5. Commit:

```bash
git add "KakuTra TranslatorTests" "README.md" "README.zh-CN.md" "README.ja.md" "README.ko.md"
git commit -m "test: verify selected text sentence translation flow"
```

Plan complete and saved to `docs/plans/2026-03-09-selected-text-sentence-translation-plan.md`. Two execution options:

1. Subagent-Driven (this session) - I dispatch fresh subagent per task, review between tasks, fast iteration

2. Parallel Session (separate) - Open new session with executing-plans, batch execution with checkpoints

Which approach?
