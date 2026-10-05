# Paragraph Overlay Visual Refresh Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign the paragraph translation overlay so it has clearer hierarchy, better grouping, explicit copy actions, and more readable paragraph typography while keeping current translation behavior unchanged.

**Architecture:** Keep the current paragraph-mode state flow in `AppModel`, but restructure the paragraph presentation in `OverlayView` around two explicit content sections with per-section actions. Use small helper methods for language naming and section metadata, and keep the existing overlay window logic unless layout changes require minor adjustments.

**Tech Stack:** Swift, SwiftUI, AppKit, XCTest, xcodebuild

---

### Task 1: Rebuild paragraph overlay information hierarchy

**Files:**
- Modify: `KakuTra Translator/OverlayView.swift`
- Modify: `KakuTra Translator/AppModel.swift`

**Step 1: Define the visible information model**

- Remove the `PARAGRAPH` label from paragraph mode.
- Introduce display helpers for:
  - source section title
  - target section title
  - whether each section should show a copy action

**Step 2: Rebuild the top bar**

- Keep only drag area and close button.
- Remove the shared paragraph copy action.

**Step 3: Render paragraph mode as two content sections**

- Build:
  - `Original (Language)`
  - `Translation (Language)`
- Keep loading/error handling within the section layout instead of separate floating labels.

**Step 4: Run tests**

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test
```

### Task 2: Improve grouping, spacing, and reading typography

**Files:**
- Modify: `KakuTra Translator/OverlayView.swift`

**Step 1: Add softer section containers**

- Wrap each paragraph section in a subtle inset surface.
- Use restrained fill/stroke so the UI still feels native to macOS.

**Step 2: Update typography**

- Keep section labels compact and secondary.
- Increase paragraph line spacing.
- Make translated text slightly stronger than original text.

**Step 3: Adjust spacing**

- Tighten title-to-body spacing.
- Increase section-to-section spacing.
- Reduce unnecessary visual clutter from dividers.

**Step 4: Run tests**

Run the same `xcodebuild ... test` command.

### Task 3: Make copy semantics explicit

**Files:**
- Modify: `KakuTra Translator/OverlayView.swift`
- Modify: `KakuTra Translator/Localizable.xcstrings`

**Step 1: Add per-section copy buttons**

- Add `Copy` action for the original block.
- Add `Copy` action for the translation block.
- Hide or disable the action when the section has no copyable text.

**Step 2: Add inline success feedback**

- Reuse the existing copied-state pattern.
- Show `Copied` in place of `Copy` briefly after success.

**Step 3: Localize new labels**

- Add any needed strings for:
  - `Original`
  - `Translation`
  - `Copy`
  - `Copied`
- Preserve the existing catalog structure.

**Step 4: Run tests**

Run the same `xcodebuild ... test` command.

### Task 4: Add language-aware section titles

**Files:**
- Modify: `KakuTra Translator/OverlayView.swift`
- Modify: `KakuTra Translator/AppModel.swift` (if helper exposure is cleaner there)

**Step 1: Reuse existing language-name mappings where possible**

- Map `en` to `English`
- Map target language IDs to their user-facing names already used in settings

**Step 2: Compose user-facing section titles**

- Render titles like:
  - `Original (English)`
  - `Translation (简体中文)`

**Step 3: Manual validation**

- Confirm titles match the current target language
- Confirm same-language cases still look reasonable
- Confirm the panel still reads cleanly in loading and error states
