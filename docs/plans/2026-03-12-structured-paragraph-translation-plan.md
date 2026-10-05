# Structured Paragraph Translation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Preserve OCR paragraph line breaks and list structure in the native paragraph translation result, and render translated list items with readable hanging indentation in the overlay.

**Architecture:** Keep the existing OCR paragraph selection flow in `AppModel`, but stop flattening paragraph text before native translation. Introduce a small structure model that turns OCR lines into ordered blocks, translate those block bodies in batch through the Translation framework, then render the rebuilt result with list-aware attributed paragraph styles in the existing selectable text view.

**Tech Stack:** Swift, SwiftUI, AppKit, Translation, XCTest, xcodebuild

---

### Task 1: Add structured paragraph block parsing

**Files:**
- Create: `KakuTra Translator/ParagraphTextStructure.swift`
- Test: `KakuTra TranslatorTests/ParagraphTextStructureTests.swift`

**Step 1: Write the failing parser tests**

Add tests for:
- bullet lines becoming separate list-item blocks
- ordered markers such as `1.` and `2)` becoming separate list-item blocks
- wrapped OCR lines joining the previous list item body
- plain multiline text staying as plain paragraph blocks

**Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test -only-testing:'KakuTra TranslatorTests/ParagraphTextStructureTests'
```

Expected: FAIL because the parser and block model do not exist yet.

**Step 3: Write the minimal structure parser**

Implement:
- a block model for plain text, list item, and blank line
- marker detection for bullet and ordered prefixes
- continuation-line joining for indented/follow-on OCR lines
- helpers to rebuild plain text from blocks

**Step 4: Run tests to verify they pass**

Run the same command and expect PASS.

**Step 5: Commit**

```bash
git add "KakuTra Translator/ParagraphTextStructure.swift" "KakuTra TranslatorTests/ParagraphTextStructureTests.swift"
git commit -m "feat: add paragraph structure parser"
```

### Task 2: Batch-translate structured blocks with the system translator

**Files:**
- Modify: `KakuTra Translator/TranslationService.swift`
- Modify: `KakuTra Translator/AppModel.swift`
- Modify: `KakuTra Translator/OverlayView.swift`
- Test: `KakuTra TranslatorTests/ParagraphNativeTranslationTests.swift`

**Step 1: Write failing translation orchestration tests**

Add tests for:
- same-language paragraph mode returning rebuilt multiline text instead of space-flattened text
- native translation path preserving block count and marker order when mock translated bodies are supplied
- fallback to raw multiline translation when structure parsing returns no translatable blocks

**Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test -only-testing:'KakuTra TranslatorTests/ParagraphNativeTranslationTests'
```

Expected: FAIL because the bridge only exposes single-string translation and the paragraph flow still replaces `\n` with spaces.

**Step 3: Add batch translation support**

Implement:
- a batch request/response API in `TranslationBridge` backed by `TranslationSession.translations(from:)`
- paragraph translation helpers in `AppModel` that translate structured block bodies
- raw multiline fallback without replacing `\n` with spaces
- updated overlay payload so the native translation section can keep rebuilt structured text

**Step 4: Run targeted tests**

Run the same command and expect PASS.

**Step 5: Commit**

```bash
git add "KakuTra Translator/TranslationService.swift" "KakuTra Translator/AppModel.swift" "KakuTra Translator/OverlayView.swift" "KakuTra TranslatorTests/ParagraphNativeTranslationTests.swift"
git commit -m "feat: preserve paragraph structure in native translation"
```

### Task 3: Render translated lists with hanging indentation

**Files:**
- Modify: `KakuTra Translator/OverlayView.swift`
- Test: `KakuTra TranslatorTests/ParagraphTextRenderingTests.swift`

**Step 1: Write failing rendering tests**

Add tests for:
- list-item paragraphs receiving a non-zero head indent and first-line offset
- plain paragraphs keeping zero list indent
- blank lines remaining in the rebuilt output order

**Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test -only-testing:'KakuTra TranslatorTests/ParagraphTextRenderingTests'
```

Expected: FAIL because `SelectableTextView` currently applies one paragraph style to the whole string.

**Step 3: Implement per-block attributed rendering**

Implement:
- a formatter that builds `NSAttributedString` paragraph-by-paragraph
- hanging indent for list markers based on marker width plus gap
- existing line height and text styling for non-list paragraphs
- identical rendering support for original and translated paragraph sections

**Step 4: Run targeted tests**

Run the same command and expect PASS.

**Step 5: Commit**

```bash
git add "KakuTra Translator/OverlayView.swift" "KakuTra TranslatorTests/ParagraphTextRenderingTests.swift"
git commit -m "feat: render paragraph lists with hanging indentation"
```

### Task 4: Run regression coverage and manual QA

**Files:**
- Modify: none unless regressions are found

**Step 1: Run focused paragraph-related tests**

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test -only-testing:'KakuTra TranslatorTests/ParagraphTextStructureTests' -only-testing:'KakuTra TranslatorTests/ParagraphNativeTranslationTests' -only-testing:'KakuTra TranslatorTests/ParagraphTextRenderingTests' -only-testing:'KakuTra TranslatorTests/OCRParagraphGroupingTests' -only-testing:'KakuTra TranslatorTests/ParagraphOverlayLayoutTests'
```

Expected: PASS.

**Step 2: Run the full test suite**

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -destination 'platform=macOS' test
```

Expected: PASS.

**Step 3: Manual smoke check**

Verify:
- a plain paragraph still translates as multiline prose
- a bullet list stays one bullet per line in the native translation section
- a long translated bullet wraps under its own text instead of under the bullet marker
- third-party translation cards still render as before

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: preserve paragraph translation structure"
```
