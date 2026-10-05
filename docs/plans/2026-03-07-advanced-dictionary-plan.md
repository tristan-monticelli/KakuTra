# Advanced Dictionary Messaging Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reframe ECDICT as a user-friendly advanced dictionary and show when lookups use the advanced or system source.

**Architecture:** Keep the current lookup order, but propagate dictionary source metadata alongside lookup results. Update the settings card and main window copy to explain benefits in plain language, then surface a compact source badge inside the overlay result header.

**Tech Stack:** SwiftUI, Foundation, SQLite3, Xcode string catalog

---

### Task 1: Document dictionary result source

**Files:**
- Modify: `KakuTra Translator/DictionaryEntry.swift`
- Modify: `KakuTra Translator/DictionaryService.swift`
- Modify: `KakuTra Translator/OfflineDictionaryService.swift`

**Steps:**
1. Add a source enum for advanced vs system dictionary.
2. Store that source on `DictionaryEntry`.
3. Return `.advancedDictionary` from offline lookups.
4. Return `.systemDictionary` from Apple Dictionary parsing.

### Task 2: Propagate source into overlay content

**Files:**
- Modify: `KakuTra Translator/AppModel.swift`

**Steps:**
1. Add an optional dictionary source to `OverlayContent`.
2. Pass the source through every result creation path.
3. Keep nil when no dictionary result exists.

### Task 3: Reframe the advanced dictionary UI

**Files:**
- Modify: `KakuTra Translator/SettingsView.swift`
- Modify: `KakuTra Translator/ContentView.swift`

**Steps:**
1. Rename `ECDICT` to `Advanced English Dictionary`.
2. Replace terse install text with plain-language benefit copy.
3. Add a short note that the feature improves definitions but does not replace Apple Translation.
4. Update installed state text to say the advanced dictionary is enabled.

### Task 4: Show source badges in the overlay

**Files:**
- Modify: `KakuTra Translator/OverlayView.swift`

**Steps:**
1. Add a compact badge near the word header.
2. Show `Advanced Dictionary` when the offline dictionary matches.
3. Show `System Dictionary` when falling back to Apple Dictionary.
4. Keep the badge visually secondary to the main word and translation.

### Task 5: Update localizable strings and verify

**Files:**
- Modify: `KakuTra Translator/Localizable.xcstrings`

**Steps:**
1. Add or update strings for the new user-facing copy.
2. Build with `xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -configuration Debug build`.
3. Verify the settings card remains readable and the overlay source badge appears for both advanced and system dictionary results.
