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

## Amendments

### 2026-08-16 — the packaged build needs Xcode, not just the Command Line Tools

The rejected option above counts "requires switching the active developer
directory away from the Command Line Tools default" against an Xcode project.
`make bundle` now pays part of that cost anyway. Building the release binary
universal (`--arch arm64 --arch x86_64`) hands the build to Xcode's build
system, which ships inside Xcode.app. With only the Command Line Tools
selected, the build stops at `error: xcbuild executable at
'/Library/Developer/SharedFrameworks/XCBuild.framework/Versions/A/Support/xcbuild'
does not exist or is not executable`.

The decision stands, and the cost is narrower than the one it was weighed
against. `make bundle` and `make install` are the only targets affected; the
development loop — `swift build`, `swift test`, `swift run`, and so `make
check` — stays single-architecture and runs under the Command Line Tools
alone. There is still no `.pbxproj` to merge, and the build is still headless
and scriptable, which is what this ADR was about.

The way out, if the Xcode requirement ever costs someone more than the
universal binary is worth: build each architecture separately
(`swift build --triple …` twice) and join the two with `lipo -create`. That
keeps the native build system, at the price of a hand-rolled recipe. Untried
here — the universal build was verified, this was not.
