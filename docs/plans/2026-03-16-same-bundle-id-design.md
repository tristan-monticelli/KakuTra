# Same Bundle ID Distribution Design

**Goal:** Preserve macOS privacy permissions such as screen recording when users replace the App Store build with the direct GitHub build.

## Context

The project already splits distribution into two app targets:

- `KakuTra Translator` for the Mac App Store without Sparkle
- `KakuTra Translator Direct` for direct GitHub distribution with Sparkle

That target split fixes App Store validation, but the current direct target uses a different bundle identifier from the App Store target. macOS privacy permissions are tied to app identity, so switching channels can force users to re-authorize screen recording and related TCC permissions.

## Decision

Keep the dual-target architecture, but make both targets use the same production bundle identifier:

- `org.yelog.KakuTraTranslate`

The App Store target still excludes Sparkle entirely. The direct target still includes Sparkle and uses direct-distribution plist and entitlements. Only the bundle identity is unified.

## Why This Approach

1. It keeps the App Store bundle compliant because Sparkle remains isolated to the direct target.
2. It maximizes the chance that macOS treats App Store and direct replacements as the same app for TCC permission continuity.
3. It avoids reverting to a fragile single-target setup that could accidentally ship Sparkle inside the App Store archive.

## Tradeoffs

- App Store and direct builds can no longer coexist reliably on the same machine.
- Installing one channel will replace the other because the app identity is shared.
- Permission retention is improved by matching app identity, but final behavior still depends on macOS treating the replacement as the same signed app lineage.

## Out Of Scope

- Reworking Sparkle update feeds
- Changing notarization/signing strategy
- Adding migration logic for parallel installs, because parallel installs are intentionally no longer supported
