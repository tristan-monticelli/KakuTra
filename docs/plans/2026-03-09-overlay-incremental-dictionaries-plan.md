# Overlay Incremental Dictionaries Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Change the translation popup from a global blocking loading state to an incremental overlay that shows primary translation and dictionary sections independently as async work finishes.

**Architecture:** Keep request orchestration in `AppModel`, add a single-source dictionary lookup entry point in `DictionaryService`, and evolve the overlay data model so the view can render section-level loading, ready, empty, and failed states without waiting for the whole lookup to finish.

**Tech Stack:** Swift, SwiftUI, Swift Concurrency, XCTest, Translation

---

### Task 1: Add Incremental Overlay State Model

**Files:**
- Modify: `KakuTra Translator/AppModel.swift`

**Steps:**

1. Replace the current final-only `OverlayContent` shape with a partial-result model for:
   - primary translation state
   - ordered dictionary sections
2. Keep the top-level overlay state enum simple so `.result` can represent both partial and final content.
3. Add helper methods that update one section at a time while preserving order and guarding against stale `lookupID`s.

### Task 2: Add Single-Source Dictionary Lookup

**Files:**
- Modify: `KakuTra Translator/DictionaryService.swift`

**Steps:**

1. Add a public async method that looks up exactly one `DictionarySource`.
2. Reuse the existing local/online branching logic instead of duplicating provider behavior.
3. Keep `lookupAll` available, but stop using it from the popup flow.

### Task 3: Refactor Lookup Orchestration

**Files:**
- Modify: `KakuTra Translator/AppModel.swift`

**Steps:**

1. After OCR selects a word, show the popup immediately with placeholder section states.
2. Launch the primary translation as its own task.
3. Launch one task per enabled dictionary source with `TaskGroup`.
4. Translate non-pretranslated definitions within each source task.
5. Update phonetic, fallback translation, and section content incrementally as results arrive.
6. Preserve existing cancellation and error semantics.

### Task 4: Update Overlay Rendering

**Files:**
- Modify: `KakuTra Translator/OverlayView.swift`

**Steps:**

1. Remove reliance on the normal global loading view for active lookups.
2. Render the shell from partial `OverlayContent`.
3. Add inline loading / empty / failed states for the primary translation block and dictionary sections.
4. Keep section order stable and spacing predictable to reduce layout jumpiness.

### Task 5: Verify Behavior

**Files:**
- Modify if needed: `KakuTra TranslatorTests/*`

**Steps:**

1. Run:
   ```bash
   xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -configuration Debug build
   ```
2. Run:
   ```bash
   xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -configuration Debug test
   ```
3. Manually verify:
   - popup appears immediately
   - primary translation and dictionary sections update independently
   - slow providers do not block fast ones
   - changing the hovered word cancels stale updates

Plan complete and saved to `docs/plans/2026-03-09-overlay-incremental-dictionaries-plan.md`. Two execution options:

1. Subagent-Driven (this session) - I dispatch fresh subagent per task, review between tasks, fast iteration

2. Parallel Session (separate) - Open new session with executing-plans, batch execution with checkpoints

Which approach?
