# Selected Text Tap Keeps Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development for behavior changes.

**Goal:** Make short-tap overlay persistence apply to selected-text sentence translation as well as word lookup.

**Architecture:** Preserve the existing setting and gesture callbacks. Generalize the pure tap-keep policy to classify supported single-lookup kinds, then map `AppModel` lookup modes into that policy. Keep the UI wording aligned with the broader behavior.

**Tech Stack:** Swift, SwiftUI, AppKit `NSEvent`, XCTest, Xcode build system.

---

### Task 1: Policy Tests

**Files:**
- Modify: `KakuTra TranslatorTests/ParagraphOverlayLayoutTests.swift`

- [x] **Step 1: Write failing tests**

Assert tap-to-keep returns true for selected-text sentence lookup when enabled and false for OCR paragraph lookup.

- [x] **Step 2: Run focused tests**

Run: `xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test -only-testing:"KakuTra TranslatorTests/ParagraphOverlayLayoutTests"`

Expected: FAIL until the policy supports selected-text lookup kinds.

### Task 2: AppModel Integration

**Files:**
- Modify: `KakuTra Translator/AppModel.swift`
- Modify: `KakuTra Translator/OverlayView.swift`

- [x] **Step 1: Generalize the policy**

Replace the word-only boolean with a tap-kept lookup kind that supports `.word` and `.selectedTextSentence`, but not `.ocrSentence`.

- [x] **Step 2: Preserve selected-text work after release**

Use the generalized policy in `finishHotkeyRelease(allowWordOverlayPersistence:)` so selected-text sentence lookup remains visible and continues receiving async updates after a short tap.

- [x] **Step 3: Adjust sentence bubble controls**

When a selected-text sentence bubble is kept by short tap, show close instead of pin.

### Task 3: Copy And Docs

**Files:**
- Modify: `KakuTra Translator/SettingsView.swift`
- Modify: `KakuTra Translator/SettingsWindowView.swift`
- Modify: `KakuTra Translator/Localizable.xcstrings`
- Modify: `README.md`
- Modify: `README.zh-CN.md`
- Modify: `docs/README.md`
- Modify: `docs/README.zh-CN.md`

- [x] **Step 1: Rename the visible setting**

Use "Keep Translation Bubble After Tap" for the broader behavior while preserving the stored setting key.

- [x] **Step 2: Update docs**

Mention that tap-to-keep applies to word lookup and selected-text sentence translation.

### Task 4: Verification

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test -only-testing:"KakuTra TranslatorTests/ParagraphOverlayLayoutTests" -only-testing:"KakuTra TranslatorTests/SettingsStoreMigrationTests" -only-testing:"KakuTra TranslatorTests/SelectedTextLookupRoutingTests" -only-testing:"KakuTra TranslatorTests/HotkeyManagerTests"
jq empty "KakuTra Translator/Localizable.xcstrings"
git diff --check
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -configuration Debug build
```

Expected: all commands succeed.
