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
