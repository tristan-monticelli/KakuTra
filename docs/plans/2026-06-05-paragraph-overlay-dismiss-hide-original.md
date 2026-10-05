# Paragraph Overlay Dismiss And Hide Original Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a sentence overlay setting that hides the Original section, and dismiss pinned sentence overlays when the user clicks outside without breaking OCR region resizing.

**Architecture:** Persist a new boolean setting, thread it into the paragraph overlay view, and keep pinned/editing overlays showing the Original section. Add a mouse-down dismissal monitor scoped to pinned paragraph overlays, with a pure policy that treats the overlay window, paragraph highlight window, active OCR region, and resize interaction as protected areas.

**Tech Stack:** Swift, SwiftUI, AppKit `NSEvent` monitors, XCTest, Xcode project `KakuTra Translator`.

---

### Task 1: Settings

**Files:**
- Modify: `KakuTra Translator/AppSettings.swift`
- Modify: `KakuTra Translator/SettingsStore.swift`
- Modify: `KakuTra Translator/SettingsWindowView.swift`
- Test: `KakuTra TranslatorTests/SettingsStoreTests.swift`

**Steps:**
1. Add `hideOriginalTextInSentenceOverlay` to `AppSettingKey`.
2. Add a `@Published` setting with default `false` and persistence through `persistAllSettings()`.
3. Add a General settings toggle near `Double-tap OCR Sentence Translation`.
4. Test default and persisted values.

### Task 2: Paragraph Overlay Rendering

**Files:**
- Modify: `KakuTra Translator/OverlayView.swift`

**Steps:**
1. Compute whether the Original section should be shown from `hasOriginalText`, `canEditParagraphOriginalText`, and the new setting.
2. Keep pinned/editable overlays showing Original so OCR text can still be corrected.
3. Keep translation loading, ready, failed, third-party results, and language controls visible when Original is hidden.

### Task 3: Outside Click Dismissal

**Files:**
- Modify: `KakuTra Translator/AppModel.swift`
- Modify: `KakuTra Translator/OverlayWindowController.swift`
- Test: `KakuTra TranslatorTests/ParagraphOverlayLayoutTests.swift`

**Steps:**
1. Add visible-frame accessors for overlay and paragraph highlight windows.
2. Add a pure `ParagraphOutsideClickDismissalPolicy` that returns false for protected frames and region interactions.
3. Add local/global mouse-down monitors only while a paragraph overlay is pinned.
4. Mark OCR region resizing as an active protected interaction.
5. Stop monitors whenever the overlay is hidden.

### Task 4: Verification

**Commands:**
- `xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test -only-testing:"KakuTra TranslatorTests/SettingsStoreMigrationTests"`
- `xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test -only-testing:"KakuTra TranslatorTests/ParagraphOverlayLayoutTests"`
- `xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -configuration Debug build`
