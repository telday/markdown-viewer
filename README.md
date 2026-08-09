# Folium

A native macOS Markdown viewer. Open a `.md` file and Folium renders it in a
tabbed window using a `WKWebView` (see [`docs/adr/`](docs/adr/) for the design
decisions behind the app).

## Requirements

- macOS 14 (Sonoma) or later
- Swift toolchain with the Swift Package Manager (`swift build`), from Xcode 16
  or the matching Command Line Tools

## Install from source

From a clean checkout:

```sh
make install
```

This builds a release binary (`swift build -c release`), assembles a
`Folium.app` bundle with its `Info.plist`, ad-hoc signs it so it launches
without Gatekeeper complaints on the machine that built it, and copies it to
`/Applications`.

Launch it from Spotlight, Launchpad, or:

```sh
open /Applications/Folium.app
```

### Other make targets

- `make bundle` — build and assemble `Folium.app` under `.build/` without
  installing.
- `make uninstall` — remove `/Applications/Folium.app`.
- `make clean` — remove build artifacts and the local bundle.

## Development

### The rendered page: a real webpage, not an inlined string

`MarkdownWebView` loads a static shell (`Sources/Folium/Resources/page.html`)
once per `WKWebView` via `loadFileURL(_:allowingReadAccessTo:)`, and the
shell references its CSS/JS with ordinary `<link>`/`<script src>` URLs —
the way any webpage loads its assets — rather than inlining their content
into a Swift string. Every Markdown file open/change after that first load
is a `window.FoliumRenderBody(...)` call via `evaluateJavaScript`
(`MarkdownPage.renderBodyScript`, driven by `MarkdownWebViewState`), not a
page reload: a reload would re-parse every stylesheet and re-parse/recompile
all of highlight.js on every single change, which matters once live
source-preview editing (planned, see ADR 0001) means that happens on every
keystroke.

`loadHTMLString(_:baseURL:)` — the more obvious-looking API — does **not**
work for this: WebKit gives every `file://` resource its own origin, and a
plain `baseURL` only resolves relative URLs, it doesn't grant read access to
what they point at (confirmed by testing: referencing a sibling local CSS
file throws `SecurityError: Not allowed to access cross-origin stylesheet`
and the styles silently don't apply). `loadFileURL` is the API that actually
grants that access.

Two kinds of asset, handled differently:

- **Third-party, vendored**: highlight.js (see
  [`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md)), so there's no CDN
  dependency at runtime. The actual files aren't committed: `make vendor` — a
  prerequisite of `build`/`vet`/`test-unit`/`test-integration`/`coverage`, so
  `make build` and `make check` handle it automatically — regenerates
  `Sources/Folium/Vendor/` from the pinned version in
  [`vendor/package.json`](vendor/package.json) (a real npm manifest Dependabot
  tracks for version bumps and security advisories). Requires `npm` (e.g.
  `brew install node`), but only hits the network on the first run or after a
  version bump; otherwise it's a no-op.
- **First-party, authored here**: the shell itself, the base GitHub-matching
  stylesheet, the code-block chrome, and the copy-button script live as
  ordinary committed files under `Sources/Folium/Resources/` — no build
  step, just real CSS/JS/HTML editor tooling instead of Swift string
  literals.

Both are declared as `.copy` resources in `Package.swift`, so they exist as
real files in the app's resource bundle at runtime — nothing reads their
contents into a Swift `String`.

**A bare `swift build` / `swift test` / `swift run` (bypassing `make`) needs
`make vendor` run at least once first**, since the vendored (not first-party)
resource files won't exist yet.

**`make bundle`/`make install` copy the SPM resource bundle into the `.app`
*after* code-signing it**, not before: SPM's generated resource accessor
looks for `Folium_Folium.bundle` as a sibling of the `.app` itself, but
`codesign` refuses to seal a bundle with anything outside `Contents/` at its
root. Signing first and adding the resource bundle after still produces a
working app (verified by hiding every other fallback path and confirming it
still launches and finds its resources) — `codesign --verify` will flag the
added directory as unsealed, which only matters if this project ever moves
beyond ad-hoc signing (see ADR 0003).

### Quality gates

`make check` runs the four gates that make up the Definition of Done for any
code change (see [`docs/agents/definition-of-done.md`](docs/agents/definition-of-done.md)):

- `make lint` — SwiftLint (`--strict`); requires `brew install swiftlint`.
- `make vet` — compiles all targets with warnings treated as errors (the Swift
  equivalent of `go vet`).
- `make test-unit` — fast, isolated unit tests.
- `make test-integration` — end-to-end file-to-render pipeline tests.
- `make coverage` — enforces ≥97% unit-test line coverage on the logic layer
  (UI/host-glue files are excluded and listed on every run).

CI runs `make check` on every pull request (`.github/workflows/ci.yml`).
