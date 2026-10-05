# Paragraph Overlay Interactions Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add temporary `Esc` dismissal, selectable paragraph text, localized paragraph-loading strings, and drag-to-move behavior for the paragraph translation overlay.

**Architecture:** Keep the existing paragraph overlay state in `AppModel`, but add temporary keyboard monitoring for `Esc` and direct window movement hooks in `OverlayWindowController`. Replace paragraph body `Text` rendering with an AppKit-backed selectable text view, and route remaining hard-coded paragraph strings through the existing localization helper.

**Tech Stack:** Swift, SwiftUI, AppKit, XCTest, xcodebuild

---

### Task 1: Add paragraph overlay dismissal and drag plumbing

**Files:**
- Modify: `KakuTra Translator/AppModel.swift`
- Modify: `KakuTra Translator/OverlayWindowController.swift`

**Step 1: Add temporary paragraph keyboard monitoring**

- Install global/local `.keyDown` monitors only when paragraph mode is visible.
- Handle key code `53` and call the same dismissal path as the close button.
- Tear monitors down whenever paragraph mode ends.

**Step 2: Add direct movement APIs to the overlay window controller**

- Add helpers to read the current frame, move by drag delta, and clamp within the visible screen.
- Keep the existing anchor-based methods unchanged for non-drag flows.

**Step 3: Expose drag entry points from `AppModel`**

- Add `beginParagraphOverlayDrag`, `updateParagraphOverlayDrag`, and `endParagraphOverlayDrag`.
- Ignore drag requests outside paragraph mode.

**Step 4: Verify behavior**

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test
```

### Task 2: Make paragraph body text selectable and localize loading copy

**Files:**
- Modify: `KakuTra Translator/OverlayView.swift`
- Modify: `KakuTra Translator/Localizable.xcstrings`

**Step 1: Add a reusable selectable text wrapper**

- Bridge `NSTextView` into SwiftUI with transparent background and disabled editing.
- Let the wrapper report its intrinsic height so the existing scroll layout still works.

**Step 2: Use the wrapper in paragraph sections**

- Apply it to both original text and translated text.
- Keep loading/error rows unchanged.

**Step 3: Localize paragraph-specific strings**

- Replace hard-coded strings in paragraph loading and headings with `L(...)`.
- Add the corresponding string catalog entries.

**Step 4: Verify behavior**

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test
```

### Task 3: Add draggable paragraph header interactions

**Files:**
- Modify: `KakuTra Translator/OverlayView.swift`

**Step 1: Add a header drag gesture**

- Use a zero-distance drag gesture on the paragraph top bar.
- Forward drag phases into the new `AppModel` drag helpers.

**Step 2: Add drag hover affordance**

- Show an open-hand cursor on hover and closed-hand while dragging.
- Keep buttons clickable inside the same row.

**Step 3: Manual validation**

- Confirm text selection still works in the body while drag is limited to the top bar.
- Confirm dragging does not persist after the panel is dismissed.
