# Paragraph Overlay Interactions Design

**Goal:** Refine the paragraph translation overlay so it behaves like a temporary floating reading panel: it closes on `Esc`, supports selectable original/translated text, localizes paragraph-loading copy through the app language setting, and allows dragging from the top bar for the current session only.

## Scope

- Add a global `Esc` close path only while the paragraph overlay is active.
- Make paragraph original and translated text selectable with the mouse so users can use system copy.
- Route paragraph-loading strings through the existing localization helper.
- Let users drag the paragraph panel from the header row, with drag state lasting only until the overlay is dismissed.

## Product Decisions

### Close Behavior

- Only paragraph mode installs the temporary `Esc` listener.
- Pressing `Esc` should behave like clicking the close button: cancel work, hide the overlay, and hide the paragraph highlight.
- Word lookup mode keeps its current behavior.

### Text Selection

- Only the paragraph body becomes selectable.
- The header keeps explicit copy and close buttons, but users can also select arbitrary fragments from the body.
- Selection should work for both original text and translated text without changing the existing visual hierarchy.

### Localization

- Paragraph-loading text must use the same `L(...)` path as the rest of the app so it follows `SettingsStore.appLanguage`.
- Realtime language changes should update the paragraph overlay without requiring a relaunch.

### Dragging

- Dragging is limited to the first row containing `PARAGRAPH`, copy, and close controls.
- Hovering that row should show a drag-style cursor.
- Dragging moves the current overlay window directly rather than changing the normal anchor logic.
- Drag position is ephemeral: once dismissed, the next paragraph overlay appears from the normal cursor-based anchor again.

## Architecture

### Overlay Window Control

- Extend `OverlayWindowController` with direct frame movement APIs for paragraph mode:
  - begin drag from current frame
  - move by translation delta
  - end drag
- Keep anchor-based positioning as the default path for normal lookups.
- Reset any transient drag state when the overlay hides.

### App Model Coordination

- `AppModel` owns the temporary global/local key monitors for `Esc`.
- Paragraph mode enables the `Esc` monitors when the paragraph overlay becomes visible and tears them down on dismissal.
- `AppModel` also exposes small drag helpers for the view layer so the SwiftUI header can forward gesture events without reaching into AppKit directly.

### Selectable Paragraph Content

- Replace plain `Text` views in paragraph sections with an AppKit-backed selectable text view wrapper.
- Keep the wrapper read-only, transparent, and auto-sizing so it still fits inside the existing SwiftUI scroll view.

## Testing

- Add unit coverage for the new paragraph loading localization keys if practical through existing catalog compilation.
- Add a window-controller geometry test for drag offset application if it can be isolated cheaply.
- Run the full `KakuTra TranslatorTests` suite plus a manual smoke check for:
  - `Esc` closes paragraph overlay
  - body text is selectable and copyable
  - loading strings follow app language
  - top bar drag moves the panel and does not persist after dismissal
