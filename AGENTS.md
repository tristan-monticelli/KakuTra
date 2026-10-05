# AGENTS.md

## Scope
- Applies to the entire repository.
- This file is intended for agentic coding assistants.

## Project Overview
- **Xcode project**: `KakuTra Translator.xcodeproj`
- **SwiftUI macOS app**: Menu bar (accessory) app for instant OCR translation
- **App targets**: `KakuTra` and `KakuTra Direct`
- **Test target**: `KakuTraTests`
- **Minimum macOS**: 14.0 (translation features require macOS 15.0+)

## Product Goal and User Journeys
- KakuTra helps the user understand foreign text at the cursor with as little interruption as possible. Treat the user's learning or reading goal as the design constraint; do not implement isolated technical behavior without checking how it helps that journey.
- Mode 1 is the reference cursor journey: detect the word under the pointer, show its local dictionary entry in the standard word card, and keep the card and lookup tracking consistent as the pointer moves.
- The word card can optionally show an English translation of the OCR line containing the looked-up word. It defaults off; a one-time settings migration removes the old persisted default-on value and preserves the older sentence preference if present. It is configured under Context Sentence and is a setting within mode 1, not a separate mode or gesture.
- Alternate Japanese readings are configured with the Japanese dictionary settings, not with the cross-language OCR context setting.
- Mode 2 (two presses) translates supported Japanese, Chinese, and Korean OCR text on the display under the cursor. It periodically captures that display, skips Vision OCR when a reduced frame fingerprint is unchanged, and places translations over recognized text; Escape stops it. Unsupported-language-only lines should be skipped.
- Keep the existing App Store versus Direct Accessibility/OCR routing intact unless the user explicitly asks to change it.
- Before editing, state the user-visible journey the change serves. Prefer the smallest implementation that completes that journey using existing components and services; avoid duplicate modes, panels, or fallback paths without a demonstrated need.

## Build / Run / Test Commands

### Build (CLI)
```bash
# Debug build
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra" -configuration Debug build

# Release build
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra" -configuration Release build
```

### Run
Preferred: Open in Xcode and run (⌘R):
```bash
open "KakuTra Translator.xcodeproj"
```

### Clean
```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" clean
```

### Tests
- The `KakuTraTests` target is included in the `KakuTra` scheme.
- Run all tests:
  ```bash
  xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra" test
  ```
- Run a single test:
  ```bash
  xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra" test \
    -only-testing:KakuTraTests/<TestCase>/<testMethod>
  ```

### Lint / Format
- No `SwiftLint`, `SwiftFormat`, or `.editorconfig` currently configured.
- Follow Xcode default formatting (4 spaces, no tabs).

## Code Style Guidelines

### Formatting
- Indentation: 4 spaces (Xcode default).
- Use trailing commas for multiline collections and parameter lists.
- Keep `body` and view builders vertically aligned and indented consistently.
- Prefer line breaks for view modifier chains once they exceed one line.
- Avoid trailing whitespace and excessive vertical spacing.

### Imports
- One `import` per line.
- Keep `SwiftUI` at the top when it is used.
- Avoid unused imports.

### Naming
- Types and protocols: `UpperCamelCase`.
- Variables, functions, and properties: `lowerCamelCase`.
- Boolean properties: affirmative names (`isEnabled`, `hasFocus`).
- SwiftUI views: suffix with `View` only when it clarifies intent.
- File names should match the primary type when practical.

### Types and APIs
- Prefer explicit types at public boundaries.
- Use type inference for local values when it improves readability.
- Avoid force unwraps (`!`); use `guard`, `if let`, or `throws`.
- Avoid `as!`; use safe casts with `as?` and handle nil.

### Error Handling
- Use `throws` for recoverable failures.
- Convert errors to user-visible messages at the UI boundary.
- Prefer `Result` only when you need to store or pass outcomes.
- Do not swallow errors; log or surface them.

### SwiftUI Patterns
- Keep `body` small; extract subviews for complex layouts.
- Use `@State` for local UI state and `@ObservedObject` / `@StateObject` for model state.
- Prefer view modifiers for styling over wrapper views.
- Use `@MainActor` when interacting with UI state from async code.

### View Composition
- Favor small, reusable views over deeply nested stacks.
- Use `ViewBuilder` helpers for conditional composition.
- Group modifier chains by purpose (layout, style, behavior).
- Use `Spacer()` intentionally to express layout intent.
- Prefer `Label` for icon + text pairs when possible.

### State and Data Flow
- Keep a single source of truth for view state.
- Use `@State` for view-owned state and `@StateObject` for owned models.
- Use `@ObservedObject` or `@EnvironmentObject` for injected models.
- Avoid mutating state directly inside `body`.
- Trigger side effects from `task`, `onAppear`, or explicit actions.

### Accessibility
- Provide accessibility labels for non-text buttons and images.
- Avoid embedding critical text inside images.
- Use system colors and dynamic type where possible.
- Ensure tappable areas meet minimum size expectations.

### Previews
- Keep previews lightweight and deterministic.
- Supply sample data for empty and populated states.
- Avoid network calls in previews.

### File Organization
- One primary type per file when practical.
- Group extensions below the main type definition.
- Keep related types close to their primary view or model.

### Logging and Diagnostics
- Use `Logger` if structured logging is introduced.
- Avoid leaving debug `print` statements in production code.

### Dependencies
- Avoid adding dependencies without explicit approval.
- If a dependency is added, document it in this file.

### Testing Guidance
- Add a test target before writing unit tests.
- Prefer XCTest for native Swift tests.
- Keep tests deterministic and fast.
- Avoid network calls in unit tests; use stubs.

### Concurrency
- Use Swift Concurrency (`async`/`await`) for asynchronous work.
- Avoid blocking the main thread; offload work to tasks.
- Wrap UI updates in `MainActor.run` if called off-main.

### Localization
- Use `LocalizedStringKey` / `Text("...")` for user-facing strings.
- Prefer string catalogs if localization is added.

### Assets
- Put image and color assets in `Assets.xcassets`.
- Reference assets by name via `Image("name")` or `Color("name")`.

## Repository Conventions (Observed)
- Minimal project with a single SwiftUI app target.
- File headers include Xcode template comments.

## Editor / Assistant Rules
- No `.cursor/rules/`, `.cursorrules`, or `.github/copilot-instructions.md` found.
- If any are added later, mirror them here.

## Change Discipline
- Keep changes minimal and focused.
- Avoid refactors unless they are required for the task.
- Do not add new dependencies without explicit request.
