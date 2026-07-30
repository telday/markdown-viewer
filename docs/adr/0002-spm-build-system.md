---
status: accepted
---

# Build with Swift Package Manager, not an Xcode project

The app is built as an SPM executable target (`swift build` / `swift run`), not
a `.xcodeproj`. This was decided once eventual Homebrew packaging was raised
as a requirement: `make install`-from-source now, and Homebrew (likely a Cask
shipping a prebuilt, notarized `.app`) later both want a headless, scriptable
build — `swift build -c release` fits that directly. It also matches the
build system already validated in the rendering-approach prototype
(ADR 0001) and avoids `.pbxproj` merge-conflict churn for what is currently a
single-target app.

## Considered options

- **Xcode project** — rejected. Still scriptable via `xcodebuild`, and gives
  GUI-managed asset catalogs/entitlements, but requires switching the active
  developer directory away from the Command Line Tools default (this machine
  has Xcode.app installed but not selected), and is a heavier ask for anyone
  running `make install` from source than a plain SPM build.

## Consequences

- App bundle assembly (Info.plist, `.icns` icon, code signing, entitlements)
  has to be hand-rolled in a build script/Makefile rather than managed
  through Xcode's build settings UI.
