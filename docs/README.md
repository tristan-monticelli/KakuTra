# KakuTra documentation

KakuTra is a macOS menu bar app for cursor based translation. It uses local Vision OCR for Japanese, Chinese, and Korean text and Apple Translation to translate supported text into English.

## User flows

- One hotkey press starts or stops word tracking under the cursor.
- Two presses start or stop visual translation of supported Japanese, Chinese, and Korean OCR text on the display under the cursor. Escape stops screen mode.
- Only one mode runs at a time.

For a single press, the Direct distribution can read an existing Accessibility selection near the cursor and translate it as a sentence. If no usable selection is available, it uses the OCR word path. The App Store distribution uses OCR directly. Two-press screen mode uses OCR in both distributions.

Screen Recording permission is needed for OCR in both modes. Accessibility permission is optional in Direct because OCR remains the fallback. It is not used by the App Store distribution.

## Current services and data

- Translation: Apple Translation, with English as the fixed target.
- Speech: Apple system voices.
- Dictionaries: local Japanese, Chinese, and Korean SQLite databases in `~/Library/Application Support/KakuTra/Dictionaries`.
- Anki: optional, explicit card creation from a displayed result through AnkiConnect.
- No automatic lookup history is stored. The app removes the obsolete SwiftData store on launch after upgrading.
- Interface language is configurable independently from translation languages.

## Build and test

Use the shared `KakuTra` scheme:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra" -configuration Debug build
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra" test
```

The project has App Store and Direct distribution configurations. Preserve their entitlements and distribution-specific capabilities when editing project settings.
