# Repository notes

KakuTra is a macOS menu bar app. See [README.md](README.md) for the current product behavior and [docs/README.md](docs/README.md) for the architecture boundary that matters when changing the app.

## Build and test

Use Xcode’s shared `KakuTra` scheme:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra" -configuration Debug build
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra" test
```

The project contains App Store and Direct distributions. Keep distribution-specific entitlements and capabilities intact.

## Stable lookup routing

On a single press, the Direct build first checks for an existing Accessibility selection near the cursor. It translates a usable selection as a sentence and falls back to the existing OCR word path otherwise. The App Store build uses OCR directly. Double press and full-screen visual translation use OCR in both builds. Accessibility is optional because Direct falls back to OCR. Preserve this routing unless the user explicitly asks to change it.

Translation is limited to Japanese, Chinese, and Korean source text with English as the target. Translation and speech use Apple system frameworks. Local dictionary lookup uses SQLite databases in the app’s KakuTra support directory. Anki card creation is user initiated; lookups are not stored as local history.
