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

### Page assets: vendored vs. first-party

The rendered page's CSS/JS is real `.css`/`.js` files under `Sources/Folium/`
rather than baked into Swift string literals — two kinds, handled
differently:

- **Third-party, vendored**: highlight.js (see
  [`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md)), so there's no CDN
  dependency at runtime. The actual files aren't committed: `make vendor` — a
  prerequisite of `build`/`vet`/`test-unit`/`test-integration`/`coverage`, so
  `make build` and `make check` handle it automatically — regenerates
  `Sources/Folium/Vendor/` from the pinned version in
  [`vendor/package.json`](vendor/package.json) (a real npm manifest Dependabot
  tracks for version bumps and security advisories). Requires `npm` (e.g.
  `brew install node`), but only hits the network on the first run or after a
  version bump; otherwise it's a no-op. Read at runtime via `VendoredAsset` +
  a `.copy` SPM resource: `highlight.min.js` is close to the resource size
  where SPM's compile-time embedding has reported slow debug builds, so it
  stays on the runtime-read path.
- **First-party, authored here**: the base GitHub-matching stylesheet, the
  code-block chrome, and the copy-button script live as ordinary committed
  files under `Sources/Folium/Resources/` — no build step, just real CSS/JS
  editor tooling instead of Swift string literals. Declared `.embedInCode` in
  `Package.swift`, so SPM compiles their bytes directly into the binary as
  `PackageResources.xxx` constants (decoded via `EmbeddedAsset`) — no runtime
  bundle lookup, and a typo'd resource name is a compile error.

**A bare `swift build` / `swift test` / `swift run` (bypassing `make`) needs
`make vendor` run at least once first**, since the vendored (not first-party)
resource files won't exist yet.

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
