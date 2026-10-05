# Structured Paragraph Translation Design

**Goal:** Preserve paragraph line breaks and list-style formatting for sentence/paragraph translation results, especially when the original OCR text is a bullet list or numbered list, while continuing to use the system Translation framework as the primary translator.

## Scope

- Keep paragraph OCR output in a structured form instead of flattening it into one sentence.
- Preserve original line breaks for system paragraph translation.
- Detect list-like lines such as `• item`, `- item`, `1. item`, and `1) item`.
- Render translated paragraph content with list-aware indentation so wrapped lines visually align like Bing or Google Translate.
- Keep the current paragraph overlay shell, layout, close behavior, and third-party service cards.

## Product Decisions

### Translation Fidelity

- The app should preserve structure before translation rather than trying to reconstruct it from a flattened translation result.
- The system translation result remains plain text; list formatting is re-applied by our own structure model and text renderer.
- If structure detection fails, the app falls back to plain multiline paragraph rendering instead of blocking translation.

### List Detection

- Structure is inferred from OCR lines, not from HTML semantics, because the app only sees screen pixels plus OCR output.
- The first version recognizes common list prefixes:
  - bullet markers such as `•`, `·`, `●`, `○`, `▪`, `-`, `–`, `—`, `*`
  - ordered markers such as `1.`, `1)`, `a.`, `a)`
- A list item may span multiple OCR lines when later lines are aligned as a continuation rather than a new sibling item.
- Nested lists are out of scope for the first pass.

### Translation Strategy

- The system translation path should stop replacing `\n` with spaces before translation.
- The recommended path is to split the paragraph into ordered structural segments and translate them with `TranslationSession.translations(from:)`.
- Segment translation lets the app preserve list boundaries even if the Translation framework itself does not keep formatting.
- Third-party services keep their existing behavior for now; this change targets the native paragraph translation result first.

## Architecture

### Structured Paragraph Model

- Introduce a small model that represents the visible paragraph as ordered blocks.
- Each block stores:
  - kind: plain text, list item, or blank line
  - optional marker prefix such as `•` or `1.`
  - source body text without the marker
  - original order index
- The model is derived from `RecognizedParagraph.lines` so it preserves OCR line boundaries.

### Translation Flow

- `AppModel` keeps using the current paragraph lookup pipeline to select one OCR paragraph.
- Before calling the system translator, the selected paragraph text is converted into structured blocks.
- Only translatable bodies are sent to the Translation framework as a batch.
- Batch responses are stitched back into the same structure and then serialized into display text for:
  - copy/export plain text
  - list-aware attributed rendering

### Rendering

- `SelectableTextView` should move from a single paragraph style for the entire string to per-paragraph attributed content.
- Plain paragraphs keep the current line height and spacing.
- List items get a hanging indent so wrapped lines align under the translated content rather than under the bullet.
- Blank lines remain explicit paragraph separators.

## Data Flow

1. OCR groups English lines into a `RecognizedParagraph`.
2. The paragraph lines are converted into structured blocks.
3. The system translation bridge translates block bodies as a batch.
4. The translated blocks are reassembled into a `ParagraphOverlayContent` payload.
5. `OverlayView` renders the translated text with per-block paragraph styles.

## Error Handling

- If batch translation fails entirely, keep the current paragraph translation error state.
- If structure parsing produces no usable blocks, fall back to translating the raw paragraph text with preserved newlines.
- If a translated block is empty, keep the current "No translation result" behavior for the native translation section.
- Marker detection must be conservative so prose lines like `A. Smith` are not misclassified as ordered lists too aggressively.

## Testing

- Add unit tests for structure parsing:
  - bullet list recognition
  - numbered list recognition
  - continuation-line merging
  - non-list paragraph fallback
- Add unit tests for translated block reassembly so marker order and blank lines remain stable.
- Add rendering-focused tests for paragraph attributed output if it can be isolated cheaply; otherwise cover the formatter directly.
- Run the full `KakuTra TranslatorTests` suite and manually verify:
  - original paragraph still shows line breaks
  - native translation keeps bullet-per-line output
  - wrapped list items align correctly in the overlay
  - non-list paragraphs still render normally
