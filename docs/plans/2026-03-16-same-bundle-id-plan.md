# Same Bundle ID Distribution Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the App Store and direct distribution targets share the same bundle identifier while keeping Sparkle out of the App Store build.

**Architecture:** Preserve the current dual-target distribution split and change only the direct target's product bundle identifier back to the production identifier. Verify both schemes still build and that the App Store bundle excludes Sparkle while the direct bundle still includes it.

**Tech Stack:** Xcode project settings, SwiftUI macOS app target configuration, shell-based build verification

---

### Task 1: Document the distribution identity change

**Files:**
- Create: `/Users/yelog/workspace/swift/KakuTra Translator/docs/plans/2026-03-16-same-bundle-id-design.md`
- Create: `/Users/yelog/workspace/swift/KakuTra Translator/docs/plans/2026-03-16-same-bundle-id-plan.md`

**Step 1: Write the design note**

Describe why the direct target should reuse the production bundle identifier and note that channel coexistence is intentionally sacrificed to improve TCC permission continuity.

**Step 2: Save the implementation plan**

Record the exact project file to update and the build validations required after the change.

### Task 2: Restore the production bundle identifier for the direct target

**Files:**
- Modify: `/Users/yelog/workspace/swift/KakuTra Translator/KakuTra Translator.xcodeproj/project.pbxproj`

**Step 1: Update direct target Debug bundle identifier**

Change:

```text
PRODUCT_BUNDLE_IDENTIFIER = org.yelog.KakuTraTranslate.direct;
```

to:

```text
PRODUCT_BUNDLE_IDENTIFIER = org.yelog.KakuTraTranslate;
```

**Step 2: Update direct target Release bundle identifier**

Apply the same identifier change to the direct target Release configuration.

**Step 3: Review remaining direct-distribution settings**

Confirm the direct target still points to:

- `KakuTra Translator/Info-Direct.plist`
- `KakuTra Translator/KakuTra Direct.entitlements`
- `SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DIRECT_DISTRIBUTION $(inherited)"`

### Task 3: Rebuild both distribution schemes

**Files:**
- Verify: `/Users/yelog/workspace/swift/KakuTra Translator/KakuTra Translator.xcodeproj/project.pbxproj`
- Verify: `/Users/yelog/workspace/swift/KakuTra Translator/KakuTra Translator/Info-AppStore.plist`
- Verify: `/Users/yelog/workspace/swift/KakuTra Translator/KakuTra Translator/Info-Direct.plist`

**Step 1: Build the App Store scheme**

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator" -configuration Release -destination "platform=macOS" -derivedDataPath /tmp/KakuTra-appstore-same-bundle CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO build
```

Expected:

- build succeeds
- app bundle does not contain `Sparkle.framework`

**Step 2: Build the direct scheme**

Run:

```bash
xcodebuild -project "KakuTra Translator.xcodeproj" -scheme "KakuTra Translator Direct" -configuration Release -destination "platform=macOS" -derivedDataPath /tmp/KakuTra-direct-same-bundle CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO build
```

Expected:

- build succeeds
- app bundle contains `Sparkle.framework`
- built direct app resolves `CFBundleIdentifier` to `org.yelog.KakuTraTranslate`

**Step 3: Inspect the built artifacts**

Use `plutil` and `find` to confirm:

- App Store build has no Sparkle payload
- Direct build still includes Sparkle helpers
- both builds report the same bundle identifier
