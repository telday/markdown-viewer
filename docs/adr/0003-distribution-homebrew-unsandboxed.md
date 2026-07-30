---
status: accepted
---

# Distribute directly (Homebrew), not through the App Store — run unsandboxed

The app is planned to ship via Homebrew (a Cask, once there's a signed/
notarized release artifact), with `make install` from source as the v1 path,
rather than through the Mac App Store. Given that, the app runs outside the
App Sandbox.

## Considered options

- **App Sandbox** — rejected for now. The app doesn't need App Store
  distribution's constraints, and this is a local Markdown file viewer, not a
  process handling untrusted network content — the usual case for wanting
  sandboxing's blast-radius reduction is weaker here. Sandboxing would also
  require security-scoped bookmarks for every file opened via the Open
  dialog, drag-and-drop, or Recent Documents, plus care around how a
  `WKWebView` loads local resources (relative image/link paths from a
  Markdown file) under sandbox restrictions — real plumbing for a benefit
  that's unclear in this threat model.

## Consequences

- This forecloses a clean App Store submission later without revisiting this
  decision (sandboxing would need to be added retroactively).
- Homebrew Cask distribution doesn't require sandboxing, but will eventually
  need Developer ID code signing + notarization for the app to launch
  cleanly under Gatekeeper once it's downloaded rather than built locally
  from source (locally-built binaries aren't quarantined, so this isn't
  blocking the v1 `make install` path).
